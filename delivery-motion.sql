create schema if not exists swift_tracking_private;
revoke all on schema swift_tracking_private from public,anon,authenticated;
create table swift_tracking_private.motion(order_id uuid primary key references public.customer_order_tracking(id) on delete cascade,runner_id uuid,lat double precision,lng double precision,observed_at timestamptz,pickup_seen boolean not null default false,departed_at timestamptz,last_notice timestamptz,notice_bucket integer not null default -1);
alter table swift_tracking_private.motion enable row level security;
revoke all on swift_tracking_private.motion from public,anon,authenticated;
create function swift_tracking_private.point(p text) returns double precision[] language sql immutable set search_path='' as $$select case when p ~ '^[ ]*-?[0-9]+([.][0-9]+)?[ ]*,[ ]*-?[0-9]+([.][0-9]+)?[ ]*$' then array[split_part(p,',',1)::float8,split_part(p,',',2)::float8] end$$;
create function swift_tracking_private.progress(p_id uuid) returns jsonb language plpgsql stable set search_path='' as $$
declare t public.customer_order_tracking;o public.orders;m swift_tracking_private.motion;a float8[];b float8[];started timestamptz;distance numeric;remaining numeric;ratio numeric:=0;minutes integer;fresh boolean:=false;mode text:='time_estimate';
begin
 select * into t from public.customer_order_tracking where id=p_id;if not found then return null;end if;
 if t.phase in('cancelled','delivered') then return jsonb_build_object('active',false,'completed',t.phase='delivered');end if;
 select * into o from public.orders where order_id=t.linked_order_id;
 select * into m from swift_tracking_private.motion where order_id=p_id;
 if t.phase<>'on_the_way' and m.departed_at is null then return jsonb_build_object('active',false);end if;
 if jsonb_array_length(coalesce(o.run_stops,'[]'))>2 and coalesce(o.next_stop,0)<jsonb_array_length(o.run_stops)-1 and m.departed_at is null then return jsonb_build_object('active',false,'collecting',true);end if;
 a:=swift_tracking_private.point(coalesce(o.run_stops->(jsonb_array_length(o.run_stops)-2)->>'location',o.pickup_location,t.snapshot->>'pickup_location'));
 b:=swift_tracking_private.point(coalesce(o.dropoff_location,t.snapshot->>'customer_location'));
 select min(created_at) into started from public.delivery_notification_events where order_id=p_id and phase='on_the_way';
 started:=coalesce(m.departed_at,started,t.updated_at);
 if a is null or b is null then return jsonb_build_object('active',true,'progress',null,'mode','awaiting_route','started_at',started,'eta_minutes',null);end if;
 distance:=public.srx_geo_miles(a[1],a[2],b[1],b[2])*1.609344;
 minutes:=greatest(3,ceil(distance*1.3/20*60)::int+2);
 ratio:=least(.95,greatest(0,extract(epoch from now()-started)/(minutes*60)));
 fresh:=m.observed_at>now()-interval '90 seconds';
 if fresh then remaining:=public.srx_geo_miles(m.lat,m.lng,b[1],b[2])*1.609344;ratio:=least(.95,greatest(0,1-remaining/greatest(distance,.05)));minutes:=greatest(1,ceil(remaining*1.3/20*60)::int+1);mode:='gps_estimate';
 else minutes:=greatest(1,ceil(minutes*(1-ratio))::int);end if;
 return jsonb_build_object('active',true,'progress',round(ratio*100)::int,'eta_minutes',minutes,'mode',mode,'started_at',started,'location_updated_at',m.observed_at,'pickup_inferred',m.departed_at is not null and t.phase<>'on_the_way','delayed',ratio>=.95);
end $$;
revoke all on function swift_tracking_private.point(text),swift_tracking_private.progress(uuid) from public,anon,authenticated;
create function public.swift_runner_delivery_position(p_order text,p_lat float8,p_lng float8,p_accuracy float8,p_observed timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare o public.orders;m swift_tracking_private.motion;a float8[];b float8[];d numeric;remaining numeric;
begin
 if public.swift_worker_kind() is distinct from 'runner' then raise exception 'Approved runner required' using errcode='42501';end if;
 select * into o from public.orders where order_id=p_order and assigned_runner_id=auth.uid() and status in('Claimed','On the Way');
 if not found or o.customer_tracking_id is null then raise exception 'Assigned active run required' using errcode='42501';end if;
 if p_lat is null or p_lng is null or p_accuracy is null or not(p_lat between -90 and 90 and p_lng between -180 and 180 and p_accuracy between 0 and 100) or p_observed is null or p_observed<now()-interval '90 seconds' or p_observed>now()+interval '10 seconds' then raise exception 'Fresh accurate GPS required';end if;
 select * into m from swift_tracking_private.motion where order_id=o.customer_tracking_id;
 if m.observed_at>=p_observed then return;end if;
 if m.runner_id is distinct from auth.uid() then m.pickup_seen:=false;m.departed_at:=null;end if;
 a:=swift_tracking_private.point(coalesce(o.run_stops->(jsonb_array_length(o.run_stops)-2)->>'location',o.pickup_location));b:=swift_tracking_private.point(o.dropoff_location);
 if a is not null and b is not null and (o.run_stops is null or coalesce(o.next_stop,0)>=jsonb_array_length(o.run_stops)-2) then
  d:=public.srx_geo_miles(a[1],a[2],p_lat,p_lng)*1609.344;
  if d<=150 then m.pickup_seen:=true;end if;
  remaining:=public.srx_geo_miles(b[1],b[2],p_lat,p_lng);
  if m.pickup_seen and d>300 and remaining<public.srx_geo_miles(a[1],a[2],b[1],b[2])*.9 then m.departed_at:=coalesce(m.departed_at,now());end if;
 end if;
 insert into swift_tracking_private.motion(order_id,runner_id,lat,lng,observed_at,pickup_seen,departed_at) values(o.customer_tracking_id,auth.uid(),p_lat,p_lng,p_observed,coalesce(m.pickup_seen,false),m.departed_at)
 on conflict(order_id) do update set runner_id=excluded.runner_id,lat=excluded.lat,lng=excluded.lng,observed_at=excluded.observed_at,pickup_seen=excluded.pickup_seen,departed_at=excluded.departed_at;
end $$;
revoke all on function public.swift_runner_delivery_position(text,float8,float8,float8,timestamptz) from public,anon;
grant execute on function public.swift_runner_delivery_position(text,float8,float8,float8,timestamptz) to authenticated;
alter function public.get_customer_tracking(uuid,uuid) rename to get_customer_tracking_before_motion;
revoke all on function public.get_customer_tracking_before_motion(uuid,uuid) from public,anon,authenticated;
create function public.get_customer_tracking(p_id uuid,p_token uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;begin r:=public.get_customer_tracking_before_motion(p_id,p_token);return r||jsonb_build_object('delivery_progress',swift_tracking_private.progress(p_id));end $$;
revoke all on function public.get_customer_tracking(uuid,uuid) from public;
grant execute on function public.get_customer_tracking(uuid,uuid) to anon,authenticated;
create function public.swift_delivery_push_progress(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$select swift_tracking_private.progress(p_id)$$;
revoke all on function public.swift_delivery_push_progress(uuid) from public,anon,authenticated;
grant execute on function public.swift_delivery_push_progress(uuid) to service_role;
create function swift_tracking_private.enqueue_progress() returns void language plpgsql security definer set search_path='' as $$declare t record;q jsonb;m swift_tracking_private.motion;e uuid;bucket int;begin
 for t in select c.id,c.runner_id from public.customer_order_tracking c where c.created_at>now()-interval '12 hours' and c.phase not in('delivered','cancelled') and (c.phase='on_the_way' or exists(select 1 from swift_tracking_private.motion m where m.order_id=c.id and m.departed_at is not null)) and exists(select 1 from public.delivery_push_subscriptions s where s.order_id=c.id) loop
 q:=swift_tracking_private.progress(t.id);if not coalesce((q->>'active')::boolean,false) then continue;end if;
 bucket:=coalesce((q->>'progress')::integer/25,0);select * into m from swift_tracking_private.motion where order_id=t.id;
 if m.last_notice>now()-interval '3 minutes' or m.notice_bucket>=bucket then continue;end if;
 insert into public.delivery_notification_events(order_id,phase) values(t.id,'delivery_progress') returning id into e;
 insert into public.delivery_push_jobs(event_id,install_id) select e,s.install_id from public.delivery_push_subscriptions s where s.order_id=t.id;
 insert into swift_tracking_private.motion(order_id,runner_id,last_notice,notice_bucket) values(t.id,t.runner_id,now(),bucket) on conflict(order_id) do update set last_notice=excluded.last_notice,notice_bucket=excluded.notice_bucket;
 end loop;end $$;
revoke all on function swift_tracking_private.enqueue_progress() from public,anon,authenticated;
select cron.schedule('swiftshop-delivery-progress','* * * * *','select swift_tracking_private.enqueue_progress()');

