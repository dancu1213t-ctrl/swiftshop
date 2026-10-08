-- SwiftPay prepaid funds use integer cents and an append-only transaction ledger.
begin;
create table if not exists public.swiftpay_payments (
 kind text not null check(kind in ('delivery','ride')),
 reference_id uuid not null,
 customer_id uuid references auth.users(id) on delete set null,
 profile_id uuid references public.swiftshop_users(id) on delete set null,
 amount_cents bigint not null check(amount_cents between 1 and 10000000),
 fee_cents bigint not null default 15 check(fee_cents=15),
 state text not null default 'reserved' check(state in ('quoted','reserved','captured','released')),
 approved_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(), captured_at timestamptz, released_at timestamptz,
 primary key(kind,reference_id)
);
create table if not exists public.swiftpay_transactions (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid references auth.users(id) on delete set null,
 profile_id uuid references public.swiftshop_users(id) on delete set null,
 kind text not null check(kind in ('adjustment','payment')),
 reference_kind text,reference_id uuid,
 amount_cents bigint not null,
 fee_cents bigint not null default 0,
 balance_after_cents bigint not null check(balance_after_cents>=0),
 reason text not null check(length(reason) between 1 and 500),
 actor_id uuid references auth.users(id) on delete set null,
 request_id uuid not null unique,
 created_at timestamptz not null default now()
);
create unique index if not exists swiftpay_once_per_payment on public.swiftpay_transactions(reference_kind,reference_id) where kind='payment';
create index if not exists swiftpay_customer_history on public.swiftpay_transactions(customer_id,created_at desc);
alter table public.swiftpay_payments enable row level security;
alter table public.swiftpay_transactions enable row level security;
revoke all on public.swiftpay_payments,public.swiftpay_transactions from public,anon,authenticated;

create or replace function public.swiftpay_wallet()
returns jsonb language plpgsql security definer set search_path='' as $$
declare u public.swiftshop_users; held bigint; cents bigint; history jsonb; payments jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in to open SwiftPay';end if;
 select * into u from public.swiftshop_users where auth_user_id=auth.uid();
 if not found then raise exception 'Your customer profile is required';end if;
 cents=round(coalesce(u.balance,0)*100)::bigint;
 select coalesce(sum(amount_cents+fee_cents),0) into held from public.swiftpay_payments where profile_id=u.id and state='reserved';
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into history from
 (select id,kind,amount_cents,fee_cents,balance_after_cents,reason,reference_kind,reference_id,created_at from public.swiftpay_transactions where customer_id=auth.uid() order by created_at desc,id desc limit 50)t;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into payments from
 (select kind,reference_id,amount_cents,fee_cents,state,created_at,captured_at from public.swiftpay_payments where customer_id=auth.uid() order by created_at desc limit 50)t;
 return jsonb_build_object('name',u.name,'balanceCents',cents,'reservedCents',held,'availableCents',greatest(0,cents-held),'transactions',history,'payments',payments);
end $$;

create or replace function public.swiftpay_admin_adjust(p_profile_id uuid,p_balance_cents bigint,p_reason text,p_request_id uuid,p_expected_balance_cents bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u public.swiftshop_users;t public.swiftpay_transactions;held bigint;before_cents bigint;
begin
 if auth.uid() is null or public.swift_admin_session() is distinct from true then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_request_id is null or p_balance_cents is null or p_balance_cents not between 0 and 10000000 or length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'Enter a valid balance and adjustment reason';end if;
 select * into u from public.swiftshop_users where id=p_profile_id for update;
 if not found or u.auth_user_id is null then raise exception 'A verified customer account is required';end if;
 select * into t from public.swiftpay_transactions where request_id=p_request_id;
 if found then
  if t.profile_id is distinct from p_profile_id or t.actor_id is distinct from auth.uid() or t.balance_after_cents<>p_balance_cents or t.reason<>trim(p_reason) then raise exception 'Adjustment reference already used';end if;
  return jsonb_build_object('transactionId',t.id,'balanceCents',t.balance_after_cents,'alreadyApplied',true);
 end if;
 before_cents=round(coalesce(u.balance,0)*100)::bigint;
 if p_expected_balance_cents is distinct from before_cents then raise exception 'Balance changed. Refresh this customer before saving';end if;
 select coalesce(sum(amount_cents+fee_cents),0) into held from public.swiftpay_payments where profile_id=u.id and state='reserved';
 if p_balance_cents<held then raise exception 'Balance cannot be lower than funds reserved for active requests';end if;
 if p_balance_cents=before_cents then raise exception 'The balance is unchanged';end if;
 perform set_config('swiftpay.balance_write','allowed',true);
 update public.swiftshop_users set balance=p_balance_cents::numeric/100 where id=u.id;
 insert into public.swiftpay_transactions(customer_id,profile_id,kind,amount_cents,balance_after_cents,reason,actor_id,request_id)
 values(u.auth_user_id,u.id,'adjustment',p_balance_cents-before_cents,p_balance_cents,trim(p_reason),auth.uid(),p_request_id) returning * into t;
 return jsonb_build_object('transactionId',t.id,'balanceCents',p_balance_cents,'alreadyApplied',false);
end $$;

-- Called only by trusted booking functions. No direct customer or worker grant.
create or replace function public.swiftpay_reserve(p_kind text,p_reference_id uuid,p_customer_id uuid,p_amount_cents bigint,p_approved_by uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare u public.swiftshop_users;p public.swiftpay_payments;held bigint;
begin
 if p_kind not in ('delivery','ride') or p_reference_id is null or p_customer_id is null or p_amount_cents is null or p_amount_cents not between 1 and 10000000 then raise exception 'A valid SwiftPay invoice is required';end if;
 select * into u from public.swiftshop_users where auth_user_id=p_customer_id for update;
 if not found then raise exception 'Customer wallet unavailable';end if;
 select * into p from public.swiftpay_payments where kind=p_kind and reference_id=p_reference_id;
 if found then
  if p.customer_id is distinct from p_customer_id or p.amount_cents<>p_amount_cents or p.state='released' then raise exception 'Payment request does not match the original reservation';end if;
  if p.state<>'quoted' then return;end if;
 end if;
 select coalesce(sum(amount_cents+fee_cents),0) into held from public.swiftpay_payments where profile_id=u.id and state='reserved';
 if round(coalesce(u.balance,0)*100)::bigint-held<p_amount_cents+15 then raise exception 'Insufficient SwiftPay funds, including the BZ$0.15 transaction fee';end if;
 insert into public.swiftpay_payments(kind,reference_id,customer_id,profile_id,amount_cents,approved_by) values(p_kind,p_reference_id,p_customer_id,u.id,p_amount_cents,p_approved_by)
 on conflict(kind,reference_id) do update set state='reserved' where swiftpay_payments.state='quoted';
end $$;

create or replace function public.swiftpay_capture(p_kind text,p_reference_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.swiftpay_payments;u public.swiftshop_users;cents bigint;out_id uuid;
begin
 select * into p from public.swiftpay_payments where kind=p_kind and reference_id=p_reference_id;
 if not found then raise exception 'SwiftPay reservation unavailable';end if;
 select * into u from public.swiftshop_users where id=p.profile_id for update;
 if not found then raise exception 'Customer wallet unavailable';end if;
 select * into p from public.swiftpay_payments where kind=p_kind and reference_id=p_reference_id for update;
 if p.state='captured' then return jsonb_build_object('alreadyPaid',true,'totalCents',p.amount_cents+p.fee_cents);end if;
 if p.state<>'reserved' then raise exception 'This reservation was released';end if;
 if p.kind='delivery' and p.approved_by is null then raise exception 'SwiftShop must confirm this invoice before payment';end if;
 cents=round(coalesce(u.balance,0)*100)::bigint-p.amount_cents-p.fee_cents;
 if cents<0 then raise exception 'Insufficient SwiftPay funds';end if;
 perform set_config('swiftpay.balance_write','allowed',true);
 update public.swiftshop_users set balance=cents::numeric/100 where id=u.id;
 insert into public.swiftpay_transactions(customer_id,profile_id,kind,reference_kind,reference_id,amount_cents,fee_cents,balance_after_cents,reason,actor_id,request_id)
 values(p.customer_id,p.profile_id,'payment',p.kind,p.reference_id,-p.amount_cents,p.fee_cents,cents,'SwiftPay '||p.kind||' payment',auth.uid(),gen_random_uuid()) returning id into out_id;
 update public.swiftpay_payments set state='captured',captured_at=now() where kind=p_kind and reference_id=p_reference_id;
 return jsonb_build_object('transactionId',out_id,'totalCents',p.amount_cents+p.fee_cents,'balanceCents',cents,'alreadyPaid',false);
end $$;

create or replace function public.swiftpay_balance_guard()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.balance is distinct from old.balance and current_setting('swiftpay.balance_write',true) is distinct from 'allowed' then raise exception 'Use the audited SwiftPay balance adjustment';end if;
 return new;
end $$;
drop trigger if exists swiftpay_balance_guard on public.swiftshop_users;
create trigger swiftpay_balance_guard before update of balance on public.swiftshop_users for each row execute function public.swiftpay_balance_guard();
revoke all on function public.swiftpay_wallet(),public.swiftpay_admin_adjust(uuid,bigint,text,uuid,bigint),public.swiftpay_reserve(text,uuid,uuid,bigint,uuid),public.swiftpay_capture(text,uuid),public.swiftpay_balance_guard() from public,anon,authenticated;
grant execute on function public.swiftpay_wallet(),public.swiftpay_admin_adjust(uuid,bigint,text,uuid,bigint) to authenticated;
-- Integration triggers and payment QR are appended before committing this migration.
DO $phase$ declare expression text;begin
 select pg_get_expr(conbin,conrelid) into expression from pg_constraint where conrelid='public.customer_order_tracking'::regclass and conname='customer_order_tracking_phase_check';
 if expression is not null then
  alter table public.customer_order_tracking drop constraint customer_order_tracking_phase_check;
  execute 'alter table public.customer_order_tracking add constraint customer_order_tracking_phase_check check (('||expression||') or phase=''cancelled'')';
 end if;
end $phase$;

create or replace function public.swiftpay_cancel_pending(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare d public.customer_order_tracking;
begin
 select * into d from public.customer_order_tracking where id=p_id for update;
 if not found or (d.customer_id is distinct from auth.uid() and public.swift_admin_session() is distinct from true) then raise exception 'Request access required';end if;
 if d.linked_order_id is not null then raise exception 'Contact SwiftShop to cancel an already-dispatched request';end if;
 if d.snapshot->>'payment' is distinct from 'SwiftPay' then raise exception 'SwiftPay request required';end if;
 update public.customer_order_tracking set phase='cancelled',updated_at=now() where id=p_id;
end $$;
revoke all on function public.swiftpay_cancel_pending(uuid) from public,anon,authenticated;
grant execute on function public.swiftpay_cancel_pending(uuid) to authenticated;

alter table public.swiftride_orders add column if not exists payment_method text not null default 'Cash';
create or replace function public.swiftpay_book_ride(p_quote_id uuid,p_request_id uuid,p_confirm_pickup boolean default false,p_payment_method text default 'Cash')
returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid;r public.swiftride_orders;fare jsonb;
begin
 if p_payment_method not in ('Cash','SwiftPay') then raise exception 'Choose Cash or SwiftPay';end if;
 rid=public.swiftride_book_priced(p_quote_id,p_request_id,p_confirm_pickup);
 select * into r from public.swiftride_orders where id=rid and customer_id=auth.uid() for update;
 if not found then raise exception 'Ride access required';end if;
 if exists(select 1 from public.swiftpay_payments where kind='ride' and reference_id=rid) then
  if p_payment_method<>'SwiftPay' then raise exception 'This ride already uses SwiftPay';end if;
  return rid;
 end if;
 if p_payment_method='SwiftPay' then
  if r.status<>'requested' then raise exception 'Choose SwiftPay before the driver accepts this ride';end if;
  fare=public.swiftride_pricing_for(rid);
  perform public.swiftpay_reserve('ride',rid,auth.uid(),round((fare->>'customerTotal')::numeric*100)::bigint,null);
  update public.swiftride_orders set payment_method='SwiftPay' where id=rid;
 end if;
 return rid;
end $$;

-- Copy the validated existing QR routines to private helpers; legacy clients keep their RPC names.
DO $copy$ declare source text;begin
 if to_regprocedure('public.swiftpay_legacy_scan_completion(text,boolean)') is null then
  source=pg_get_functiondef('public.swift_scan_completion(text,boolean)'::regprocedure);
  execute replace(source,'public.swift_scan_completion(','public.swiftpay_legacy_scan_completion(');
 end if;
 if to_regprocedure('public.swiftpay_legacy_completion_code(text,uuid,uuid)') is null then
  source=pg_get_functiondef('public.swift_completion_code(text,uuid,uuid)'::regprocedure);
  execute replace(source,'public.swift_completion_code(','public.swiftpay_legacy_completion_code(');
 end if;
end $copy$;
revoke all on function public.swiftpay_legacy_scan_completion(text,boolean),public.swiftpay_legacy_completion_code(text,uuid,uuid) from public,anon,authenticated;

create or replace function public.swift_completion_code(p_kind text,p_id uuid,p_access_token uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.swiftpay_payments where kind=p_kind and reference_id=p_id and state<>'released') then return null;end if;
 return public.swiftpay_legacy_completion_code(p_kind,p_id,p_access_token);
end $$;

create or replace function public.swiftpay_payment_code(p_kind text,p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.swiftpay_payments;code jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in to pay';end if;
 select * into p from public.swiftpay_payments where kind=p_kind and reference_id=p_id and customer_id=auth.uid();
 if not found then raise exception 'This SwiftPay request is not yours';end if;
 if p.state='captured' then return jsonb_build_object('paid',true,'totalCents',p.amount_cents+p.fee_cents);end if;
 if p.state<>'reserved' then raise exception 'Confirm the fee and reserve funds before paying';end if;
 if p.kind='delivery' and p.approved_by is null then raise exception 'Waiting for SwiftShop to confirm your invoice';end if;
 code=public.swiftpay_legacy_completion_code(p_kind,p_id,null);
 if code is null then raise exception 'Your request must be at delivery or the end of the trip before paying';end if;
 return code||jsonb_build_object('payload',replace(code->>'payload','swiftshop-confirm:','swiftshop-pay:'),'amountCents',p.amount_cents,'feeCents',p.fee_cents,'totalCents',p.amount_cents+p.fee_cents,'paid',false);
end $$;

create or replace function public.swift_scan_completion(p_payload text,p_complete boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare converted text;preview jsonb;p public.swiftpay_payments;receipt jsonb;result jsonb;
begin
 if p_payload like 'swiftshop-pay:v1:%' then
  converted=replace(p_payload,'swiftshop-pay:','swiftshop-confirm:');
  preview=public.swiftpay_legacy_scan_completion(converted,false);
  select * into p from public.swiftpay_payments where kind=preview->>'kind' and reference_id=(preview->>'reference')::uuid;
  if not found or p.state not in ('reserved','captured') then raise exception 'SwiftPay funds are not reserved for this request';end if;
  if not coalesce(p_complete,false) then return preview||jsonb_build_object('swiftpay',true,'totalCents',p.amount_cents+p.fee_cents,'title','SwiftPay · Confirm payment & completion');end if;
  receipt=public.swiftpay_capture(p.kind,p.reference_id);
  result=public.swiftpay_legacy_scan_completion(converted,true);
  perform public.swiftpay_record_worker_receipt(p.kind,p.reference_id);
  return result||receipt||jsonb_build_object('swiftpay',true);
 end if;
 preview=public.swiftpay_legacy_scan_completion(p_payload,false);
 if exists(select 1 from public.swiftpay_payments where kind=preview->>'kind' and reference_id=(preview->>'reference')::uuid and state<>'released') then raise exception 'Ask the customer to tap Pay and show their SwiftPay payment code';end if;
 return public.swiftpay_legacy_scan_completion(p_payload,p_complete);
end $$;

create or replace function public.swiftpay_completion_guard()
returns trigger language plpgsql security definer set search_path='' as $$
declare k text;ref uuid;next_status text;
begin
 if tg_table_name='orders' then k='delivery';ref=coalesce(old.customer_tracking_id,new.customer_tracking_id,(select id from public.customer_order_tracking where linked_order_id=old.order_id limit 1));next_status=new.status;
 else k='ride';ref=new.id;next_status=new.status;end if;
 if next_status in ('Delivered','completed') and old.status is distinct from new.status then
  if exists(select 1 from public.swiftpay_payments where kind=k and reference_id=ref and state<>'captured') then raise exception 'Scan the customer SwiftPay payment QR to finish this request';end if;
 elsif next_status in ('Cancelled','Canceled','cancelled','canceled','declined','expired') then
  update public.swiftpay_payments set state='released',released_at=now() where kind=k and reference_id=ref and state in ('quoted','reserved');
 end if;
 return new;
end $$;
drop trigger if exists swiftpay_completion_guard on public.orders;
create trigger swiftpay_completion_guard before update of status on public.orders for each row execute function public.swiftpay_completion_guard();
drop trigger if exists swiftpay_completion_guard on public.swiftride_orders;
create trigger swiftpay_completion_guard before update of status on public.swiftride_orders for each row execute function public.swiftpay_completion_guard();
revoke all on function public.swiftpay_book_ride(uuid,uuid,boolean,text),public.swiftpay_payment_code(text,uuid),public.swiftpay_completion_guard() from public,anon,authenticated;
grant execute on function public.swiftpay_book_ride(uuid,uuid,boolean,text),public.swiftpay_payment_code(text,uuid) to authenticated;

create or replace function public.swiftpay_tracking_invoice()
returns trigger language plpgsql security definer set search_path='' as $$
declare line jsonb;item_sum numeric=0;qty integer;price numeric;delivery numeric=3;drink_count integer=0;only_brew boolean=true;invoice numeric;tip numeric;
begin
 if tg_op='INSERT' then
  if new.snapshot->>'payment' is distinct from 'SwiftPay' then return new;end if;
  if new.snapshot->>'pickup_service'='true' then
   if new.snapshot->>'store_paid' is distinct from 'true' or jsonb_array_length(new.snapshot->'items')<>0 then raise exception 'SwiftPay pickup covers the service fee for already-paid store items';end if;
   new.snapshot=new.snapshot||jsonb_build_object('total',null,'swiftpay_fee',0.15);
   return new;
  end if;
  if jsonb_array_length(new.snapshot->'items')=0 or coalesce(new.snapshot->>'taco_note','')<>'' then
   new.snapshot=new.snapshot||jsonb_build_object('needs_invoice',true,'total',null,'swiftpay_fee',0.15);return new;
  end if;
  for line in select value from jsonb_array_elements(new.snapshot->'items') loop
   qty=(line->>'quantity')::integer;price=(line->>'price')::numeric;
   if qty is null or qty not between 1 and 100 or price is null or price<0 or price<>round(price,2) then raise exception 'Invalid item quantity or price';end if;
   if not exists(select 1 from public.products catalog where catalog.name=line->>'name' and catalog.category=line->>'category' and catalog.price=(line->>'price')::numeric) then
    new.snapshot=new.snapshot||jsonb_build_object('needs_invoice',true,'total',null,'swiftpay_fee',0.15);return new;
   end if;
   item_sum=item_sum+qty*price;drink_count=drink_count+qty;
   only_brew=only_brew and lower(trim(coalesce(line->>'category','')))='brew';
  end loop;
  if only_brew and drink_count>=3 then delivery=0;end if;
  tip=coalesce((new.snapshot->>'tip')::numeric,0);
  if tip<0 or tip>1000 or tip<>round(tip,2) then raise exception 'Invalid runner tip';end if;
  invoice=item_sum+delivery+0.50+tip;
  if (new.snapshot->>'total')::numeric is distinct from invoice then raise exception 'Order total changed. Refresh your checkout';end if;
  perform public.swiftpay_reserve('delivery',new.id,new.customer_id,round(invoice*100)::bigint,null);
  new.snapshot=new.snapshot||jsonb_build_object('swiftpay_fee',0.15);
 elsif new.snapshot is distinct from old.snapshot and exists(select 1 from public.swiftpay_payments where kind='delivery' and reference_id=new.id) then
  if new.snapshot->'total' is distinct from old.snapshot->'total' or new.snapshot->'payment' is distinct from old.snapshot->'payment' or new.snapshot->'items' is distinct from old.snapshot->'items' then raise exception 'A reserved SwiftPay invoice cannot be changed';end if;
 end if;
 if tg_op='UPDATE' then
  if new.phase in ('accepted','preparing','finding_runner') and public.swift_admin_session() is true then
   update public.swiftpay_payments set approved_by=auth.uid() where kind='delivery' and reference_id=new.id and state='reserved' and approved_by is null;
  end if;
  if new.phase in ('cancelled','canceled','expired') then update public.swiftpay_payments set state='released',released_at=now() where kind='delivery' and reference_id=new.id and state in ('quoted','reserved');end if;
  if new.linked_order_id is not null and old.linked_order_id is null and new.snapshot->>'payment'='SwiftPay' and not exists(select 1 from public.swiftpay_payments where kind='delivery' and reference_id=new.id and state='reserved') then raise exception 'Wait for the customer to accept the SwiftPay invoice before dispatch';end if;
 end if;
 return new;
end $$;
drop trigger if exists swiftpay_tracking_invoice on public.customer_order_tracking;
create trigger swiftpay_tracking_invoice before insert or update on public.customer_order_tracking for each row execute function public.swiftpay_tracking_invoice();

create or replace function public.swiftpay_quote_pickup(p_id uuid,p_amount_cents bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.customer_order_tracking;u public.swiftshop_users;p public.swiftpay_payments;
begin
 if public.swift_admin_session() is distinct from true then raise exception 'Administrator access required';end if;
 if p_amount_cents is null or p_amount_cents not between 1 and 10000000 then raise exception 'Enter the pickup service fee';end if;
 select * into d from public.customer_order_tracking where id=p_id for update;
 if not found or (d.snapshot->>'pickup_service' is distinct from 'true' and d.snapshot->>'needs_invoice' is distinct from 'true') or d.snapshot->>'payment' is distinct from 'SwiftPay' or d.linked_order_id is not null or d.phase='cancelled' then raise exception 'This request is not waiting for a SwiftPay invoice';end if;
 select * into u from public.swiftshop_users where auth_user_id=d.customer_id for update;
 if not found then raise exception 'Customer wallet unavailable';end if;
 select * into p from public.swiftpay_payments where kind='delivery' and reference_id=p_id for update;
 if found and p.state<>'quoted' then raise exception 'Customer has already accepted this invoice';end if;
 insert into public.swiftpay_payments(kind,reference_id,customer_id,profile_id,amount_cents,state,approved_by)
 values('delivery',p_id,d.customer_id,u.id,p_amount_cents,'quoted',auth.uid())
 on conflict(kind,reference_id) do update set amount_cents=excluded.amount_cents,approved_by=auth.uid() where swiftpay_payments.state='quoted';
 return jsonb_build_object('amountCents',p_amount_cents,'feeCents',15,'totalCents',p_amount_cents+15);
end $$;
create or replace function public.swiftpay_accept_pickup_fee(p_id uuid,p_expected_total_cents bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.swiftpay_payments;
begin
 select * into p from public.swiftpay_payments where kind='delivery' and reference_id=p_id and customer_id=auth.uid();
 if not found or p.state not in ('quoted','reserved') or p_expected_total_cents is distinct from p.amount_cents+p.fee_cents then raise exception 'Pickup fee changed. Refresh before accepting';end if;
 perform public.swiftpay_reserve('delivery',p_id,auth.uid(),p.amount_cents,p.approved_by);
 return public.swiftpay_wallet();
end $$;
revoke all on function public.swiftpay_tracking_invoice(),public.swiftpay_quote_pickup(uuid,bigint),public.swiftpay_accept_pickup_fee(uuid,bigint) from public,anon,authenticated;
grant execute on function public.swiftpay_quote_pickup(uuid,bigint),public.swiftpay_accept_pickup_fee(uuid,bigint) to authenticated;

CREATE OR REPLACE FUNCTION public.swiftride_current_priced(p_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r jsonb; begin
 r=to_jsonb(public.swiftride_current(p_id));
 if r is null or r='null'::jsonb then return null; end if;
 return r||jsonb_build_object('payment_method',(select payment_method from public.swiftride_orders where id=(r->>'id')::uuid),'pricing',public.swiftride_pricing_for((r->>'id')::uuid));
end $function$
;
CREATE OR REPLACE FUNCTION public.swiftride_queue_priced()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r jsonb; result jsonb='[]'; p jsonb; begin
 for r in select value from jsonb_array_elements(to_jsonb(public.swiftride_queue())) loop
  p=public.swiftride_pricing_for((r->>'id')::uuid);
  -- Only the quoted driver may accept. Keep already assigned and history rows visible.
  if p is null or r->>'status'<>'requested' or p->>'driverId'=auth.uid()::text or exists(select 1 from profiles where id=auth.uid() and role='admin') then
   result=result||jsonb_build_array(r||jsonb_build_object('payment_method',(select payment_method from public.swiftride_orders where id=(r->>'id')::uuid),'pricing',p));
  end if;
 end loop; return result;
end $function$
;
CREATE OR REPLACE FUNCTION public.admin_customer_tracking()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$

begin

 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and active) then raise exception 'Admin access required';end if;

 return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'snapshot',r.snapshot,'swiftpay',(select jsonb_build_object('state',state,'amountCents',amount_cents,'feeCents',fee_cents) from public.swiftpay_payments where kind='delivery' and reference_id=r.id),'phase',r.phase,'linked_order_id',r.linked_order_id,'created_at',r.created_at) order by r.created_at desc) from (select * from public.customer_order_tracking where phase<>'delivered' order by created_at desc limit 100) r),'[]'::jsonb);

end $function$
;

create or replace function public.swiftpay_record_worker_receipt(p_kind text,p_reference uuid)
returns void language plpgsql security definer set search_path='' as $$
declare d public.orders;r public.swiftride_orders;l public.swiftride_pricing_ledger;
begin
 if not exists(select 1 from public.swiftpay_payments where kind=p_kind and reference_id=p_reference and state='captured') then raise exception 'Payment capture required';end if;
 if p_kind='delivery' then
  select * into d from public.orders where customer_tracking_id=p_reference;
  update public.orders set is_paid=true,payment_method='SwiftPay' where order_id=d.order_id;
  insert into public.swift_worker_payments(worker_kind,source_id,worker_id,completed_at,payment_method,worker_amount,commission,customer_paid)
  values('runner',d.order_id,d.assigned_runner_id,now(),'SwiftPay',d.runner_pay,null,true)
  on conflict(worker_kind,source_id) do update set payment_method='SwiftPay',customer_paid=true;
 else
  select * into r from public.swiftride_orders where id=p_reference;
  select * into l from public.swiftride_pricing_ledger where ride_id=p_reference;
  insert into public.swift_worker_payments(worker_kind,source_id,worker_id,completed_at,payment_method,worker_amount,commission,customer_paid)
  values('driver',r.id::text,r.driver_id,now(),'SwiftPay',coalesce(l.standard_fare+l.pickup_supplement+l.return_allowance+l.rounding_adjustment-l.commission,r.total_fare-coalesce(r.commission_bzd,0)),coalesce(l.commission,r.commission_bzd,0),true)
  on conflict(worker_kind,source_id) do update set payment_method='SwiftPay',customer_paid=true;
  update public.srx_receipts set receipt=receipt||jsonb_build_object('payment','SwiftPay prepaid','swiftpay_transaction_fee',0.15,'paid',true) where ride_id=p_reference;
 end if;
end $$;
revoke all on function public.swiftpay_record_worker_receipt(text,uuid) from public,anon,authenticated;

DO $commission$ declare source text;patched text;begin
 source=pg_get_functiondef('public.srx_record_status()'::regprocedure);
 patched=replace(source,'if found then update public.srx_accounts set commission_due_bzd=commission_due_bzd+charge','if found and new.payment_method<>''SwiftPay'' then update public.srx_accounts set commission_due_bzd=commission_due_bzd+charge');
 if patched=source and source not like '%new.payment_method<>''SwiftPay''%' then raise exception 'Ride commission integration changed; review before deployment';end if;
 execute patched;
end $commission$;

notify pgrst,'reload schema';
commit;
