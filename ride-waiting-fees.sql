-- One queued acceptance alongside one active ride; active-driver uniqueness stays intact.
create schema if not exists swift_ride_private;
revoke all on schema swift_ride_private from public,anon,authenticated;
create table swift_ride_private.waiting(ride_id uuid primary key references public.swiftride_orders(id),driver_id uuid not null,blocking_ride_id uuid not null references public.swiftride_orders(id),state text not null default 'waiting' check(state in('waiting','promoted','cancelled')),accepted_at timestamptz not null default now(),notice_seen_at timestamptz);
create unique index one_waiting_ride_per_driver on swift_ride_private.waiting(driver_id) where state='waiting';
create table swift_ride_private.cancellation_fees(source_ride_id uuid primary key references public.swiftride_orders(id),customer_id uuid not null,amount_cents bigint not null default 100 check(amount_cents=100),created_at timestamptz not null default now(),charged_ride_id uuid references public.swiftride_orders(id),earned_at timestamptz);
alter table swift_ride_private.waiting enable row level security;
alter table swift_ride_private.cancellation_fees enable row level security;
revoke all on swift_ride_private.waiting,swift_ride_private.cancellation_fees from public,anon,authenticated;
alter table public.swiftride_pricing_quotes add column deferred_fee_cents bigint not null default 0 check(deferred_fee_cents>=0);
create function public.swift_ride_pending_fees() returns bigint language plpgsql stable security definer set search_path='' as $$begin if auth.uid() is null then raise exception 'Customer session required' using errcode='42501';end if;return coalesce((select sum(amount_cents) from swift_ride_private.cancellation_fees where customer_id=auth.uid() and charged_ride_id is null),0);end $$;
revoke all on function public.swift_ride_pending_fees() from public,anon;
grant execute on function public.swift_ride_pending_fees() to authenticated;
create function swift_ride_private.quote_fee() returns trigger language plpgsql security definer set search_path='' as $$begin new.deferred_fee_cents:=coalesce((select sum(amount_cents) from swift_ride_private.cancellation_fees where customer_id=new.customer_id and charged_ride_id is null),0);return new;end $$;
revoke all on function swift_ride_private.quote_fee() from public,anon,authenticated;
create trigger ride_deferred_fee before insert on public.swiftride_pricing_quotes for each row execute function swift_ride_private.quote_fee();
alter function public.swiftride_pricing_for(uuid) rename to swiftride_pricing_before_wait_fee;
revoke all on function public.swiftride_pricing_before_wait_fee(uuid) from public,anon,authenticated;
create function public.swiftride_pricing_for(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare p jsonb;fee numeric;begin p:=public.swiftride_pricing_before_wait_fee(p_id);if p is null then return null;end if;select coalesce(sum(amount_cents),0)/100.0 into fee from swift_ride_private.cancellation_fees where charged_ride_id=p_id;return p||jsonb_build_object('deferredCancellationFee',fee,'customerTotal',(p->>'customerTotal')::numeric+fee,'swiftRideCommission',case when p->>'swiftRideCommission' is not null then (p->>'swiftRideCommission')::numeric+fee end);end $$;
revoke all on function public.swiftride_pricing_for(uuid) from public;
grant execute on function public.swiftride_pricing_for(uuid) to authenticated,service_role;
alter function public.swiftride_book_priced(uuid,uuid,boolean) rename to swiftride_book_before_wait_fee;
revoke all on function public.swiftride_book_before_wait_fee(uuid,uuid,boolean) from public,anon,authenticated;
create function public.swiftride_book_priced(p_quote_id uuid,p_request_id uuid,p_confirm_pickup boolean default false) returns uuid language plpgsql security definer set search_path='' as $$declare q public.swiftride_pricing_quotes;pending bigint;rid uuid;begin
 if auth.uid() is null then raise exception 'Customer session required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':ride-fees',0));
 select * into q from public.swiftride_pricing_quotes where id=p_quote_id and customer_id=auth.uid() for update;if not found then raise exception 'Fare quote not found';end if;if q.ride_id is not null then return q.ride_id;end if;
 pending:=public.swift_ride_pending_fees();if pending<>q.deferred_fee_cents then raise exception 'Fare quote expired. Recalculate to include your saved SwiftShop fee';end if;
 rid:=public.swiftride_book_before_wait_fee(p_quote_id,p_request_id,p_confirm_pickup);
 update swift_ride_private.cancellation_fees set charged_ride_id=rid where customer_id=auth.uid() and charged_ride_id is null;
 return rid;end $$;
revoke all on function public.swiftride_book_priced(uuid,uuid,boolean) from public,anon;
grant execute on function public.swiftride_book_priced(uuid,uuid,boolean) to authenticated;
alter function public.swiftride_action_priced(uuid,text) rename to swiftride_action_before_waiting;
revoke all on function public.swiftride_action_before_waiting(uuid,text) from public,anon,authenticated;
create function public.swiftride_action_priced(p_id uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$declare r public.swiftride_orders;current_ride public.swiftride_orders;l public.swiftride_pricing_ledger;q swift_ride_private.waiting;e uuid;begin
 if p_action='accept' and public.swift_worker_kind()='driver' then
  perform 1 from public.profiles where id=auth.uid() for update;
  select * into r from public.swiftride_orders where id=p_id for update;
  select * into q from swift_ride_private.waiting where ride_id=p_id;
  if q.driver_id=auth.uid() and q.state='waiting' then return;end if;
  select * into current_ride from public.swiftride_orders where driver_id=auth.uid() and status='in_progress' for update;
  if current_ride.id is not null then
   select * into l from public.swiftride_pricing_ledger where ride_id=p_id;
   if r.status<>'requested' or l.driver_id is distinct from auth.uid() then raise exception 'This is not your quoted ride' using errcode='42501';end if;
   if public.srx_geo_miles(current_ride.dropoff_lat,current_ride.dropoff_lng,r.pickup_lat,r.pickup_lng)>1.864114 or not exists(select 1 from public.swiftride_drivers d join public.swift_worker_profiles w on w.user_id=d.driver_id where d.driver_id=auth.uid() and d.online and d.updated_at between now()-interval '90 seconds' and now() and d.accuracy between 0 and 100 and w.verification_status='verified') then raise exception 'Only a nearby next pickup with fresh GPS can be queued';end if;
   if exists(select 1 from swift_ride_private.waiting where driver_id=auth.uid() and state='waiting') then raise exception 'You already accepted your next ride';end if;
   insert into swift_ride_private.waiting(ride_id,driver_id,blocking_ride_id) values(p_id,auth.uid(),current_ride.id);
   insert into public.delivery_notification_events(ride_id,phase) values(p_id,'accepted') returning id into e;
   insert into public.delivery_push_jobs(event_id,install_id) select e,install_id from public.ride_push_subscriptions where ride_id=p_id;
   return;
  end if;
 end if;
 perform public.swiftride_action_before_waiting(p_id,p_action);
end $$;
revoke all on function public.swiftride_action_priced(uuid,text) from public,anon;
grant execute on function public.swiftride_action_priced(uuid,text) to authenticated;
create function swift_ride_private.lifecycle() returns trigger language plpgsql security definer set search_path='' as $$declare q swift_ride_private.waiting;begin
 if new.status='cancelled' and old.status<>'cancelled' then
  select * into q from swift_ride_private.waiting where ride_id=new.id and state='waiting' for update;
  if found and auth.uid()=old.customer_id and exists(select 1 from public.swiftride_orders where id=q.blocking_ride_id and status='in_progress') then
   if q.notice_seen_at is null or current_setting('swiftshop.busy_cancel_confirm',true) is distinct from new.id::text then raise exception 'Confirm the BZ$1 SwiftShop cancellation fee before cancelling this waiting ride';end if;
   perform pg_advisory_xact_lock(hashtextextended(old.customer_id::text||':ride-fees',0));
   insert into swift_ride_private.cancellation_fees(source_ride_id,customer_id) values(new.id,old.customer_id) on conflict do nothing;
  end if;
  update swift_ride_private.cancellation_fees set charged_ride_id=null where charged_ride_id=new.id and earned_at is null;
  update swift_ride_private.waiting set state='cancelled' where ride_id=new.id and state='waiting';
 end if;return new;end $$;
revoke all on function swift_ride_private.lifecycle() from public,anon,authenticated;
create trigger b01_waiting_cancel_guard before update of status on public.swiftride_orders for each row execute function swift_ride_private.lifecycle();
create function public.swift_ride_cancel_waiting(p_id uuid,p_accept_fee boolean default false) returns void language plpgsql security definer set search_path='' as $$declare r public.swiftride_orders;begin
 select * into r from public.swiftride_orders where id=p_id and customer_id=auth.uid() for update;if not found then raise exception 'Customer ride access required' using errcode='42501';end if;
 if r.status='cancelled' then return;end if;if p_accept_fee then perform set_config('swiftshop.busy_cancel_confirm',p_id::text,true);end if;
 perform public.swiftride_cancel(p_id);perform set_config('swiftshop.busy_cancel_confirm','',true);
end $$;
revoke all on function public.swift_ride_cancel_waiting(uuid,boolean) from public,anon;
grant execute on function public.swift_ride_cancel_waiting(uuid,boolean) to authenticated;
create function swift_ride_private.promote() returns trigger language plpgsql security definer set search_path='' as $$declare q swift_ride_private.waiting;begin
 if old.status in('completed','cancelled') or new.status not in('completed','cancelled') or new.driver_id is null then return new;end if;
 perform 1 from public.profiles where id=new.driver_id for update;
 select * into q from swift_ride_private.waiting where blocking_ride_id=new.id and driver_id=new.driver_id and state='waiting' for update;
 if q.ride_id is not null then
  update public.swiftride_orders set driver_id=q.driver_id,status='accepted',accepted_at=q.accepted_at,updated_at=now() where id=q.ride_id and status='requested';
  update swift_ride_private.waiting set state=case when found then 'promoted' else 'cancelled' end where ride_id=q.ride_id;
 end if;return new;end $$;
revoke all on function swift_ride_private.promote() from public,anon,authenticated;
create trigger zz_promote_waiting_ride after update of status on public.swiftride_orders for each row execute function swift_ride_private.promote();
alter function public.swiftride_current_priced(uuid) rename to swiftride_current_before_waiting;
revoke all on function public.swiftride_current_before_waiting(uuid) from public,anon,authenticated;
create function public.swiftride_current_priced(p_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$declare r jsonb;q swift_ride_private.waiting;w public.swift_worker_profiles;begin
 r:=public.swiftride_current_before_waiting(p_id);if r is null then return null;end if;
 select * into q from swift_ride_private.waiting where ride_id=(r->>'id')::uuid and state='waiting';
 if found and exists(select 1 from public.swiftride_orders where id=q.blocking_ride_id and status='in_progress') then
  update swift_ride_private.waiting set notice_seen_at=coalesce(notice_seen_at,now()) where ride_id=q.ride_id and notice_seen_at is null;
  select * into w from public.swift_worker_profiles where user_id=q.driver_id;
  return r||jsonb_build_object('status','accepted','driver_busy',true,'driver_id',q.driver_id,'driver_name',(select display_name from public.profiles where id=q.driver_id),'driver_photo',w.photo,'vehicle_photo',(select photo from public.swiftride_vehicle_photos where driver_id=q.driver_id),'license_plate',(select license_plate from public.swiftride_driver_plates where driver_id=q.driver_id),'vehicle_type',w.vehicle_type,'vehicle_model',w.vehicle_model,'vehicle_color',w.vehicle_color,'driver_phone',w.phone,'location_fresh',false,'lat',null,'lng',null,'waiting_cancellation_fee_cents',100);
 end if;return r||jsonb_build_object('driver_busy',false,'waiting_cancellation_fee_cents',0);end $$;
revoke all on function public.swiftride_current_priced(uuid) from public,anon;
grant execute on function public.swiftride_current_priced(uuid) to authenticated;
alter function public.swiftride_queue_priced() rename to swiftride_queue_before_waiting;
revoke all on function public.swiftride_queue_before_waiting() from public,anon,authenticated;
create function public.swiftride_queue_priced() returns jsonb language plpgsql security definer set search_path='' as $$declare r jsonb;q swift_ride_private.waiting;result jsonb:='[]';begin
 for r in select value from jsonb_array_elements(public.swiftride_queue_before_waiting()) loop
  select * into q from swift_ride_private.waiting where ride_id=(r->>'id')::uuid and state='waiting';
  if found then if q.driver_id<>auth.uid() and public.swift_worker_kind()<>'admin' then continue;end if;r:=r||jsonb_build_object('status','queued','driver_id',q.driver_id,'driver_name',(select display_name from public.profiles where id=q.driver_id));end if;
  result:=result||jsonb_build_array(r);
 end loop;return result;end $$;
revoke all on function public.swiftride_queue_priced() from public,anon;
grant execute on function public.swiftride_queue_priced() to authenticated;
create function swift_ride_private.earn_fee() returns trigger language plpgsql security definer set search_path='' as $$declare fee numeric;r public.swiftride_orders;paid boolean;begin
 if new.completed_at is null or old.completed_at is not null then return new;end if;
 select coalesce(sum(amount_cents),0)/100.0 into fee from swift_ride_private.cancellation_fees where charged_ride_id=new.ride_id;if fee=0 then return new;end if;
 select * into r from public.swiftride_orders where id=new.ride_id;paid:=exists(select 1 from public.swiftpay_payments where kind='ride' and reference_id=new.ride_id and state='captured');
 update swift_ride_private.cancellation_fees set earned_at=now() where charged_ride_id=new.ride_id;
 insert into public.swift_worker_payments(worker_kind,source_id,worker_id,completed_at,payment_method,worker_amount,commission,customer_paid)
 values('driver',new.ride_id::text,new.driver_id,new.completed_at,coalesce(r.payment_method,'Cash'),new.standard_fare+new.pickup_supplement+new.return_allowance+new.rounding_adjustment+new.driver_protection_fee-coalesce(new.commission,0),coalesce(new.commission,0)+fee,paid)
 on conflict(worker_kind,source_id) do update set worker_amount=excluded.worker_amount,commission=excluded.commission;
 return new;end $$;
revoke all on function swift_ride_private.earn_fee() from public,anon,authenticated;
create trigger earn_wait_cancellation_fee after update of completed_at on public.swiftride_pricing_ledger for each row execute function swift_ride_private.earn_fee();

