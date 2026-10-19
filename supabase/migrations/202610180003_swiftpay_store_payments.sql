begin;
create table if not exists public.swiftpay_store_providers(
 category text primary key references public.stores(category), code uuid not null unique default gen_random_uuid(),
 active boolean not null default true, created_at timestamptz not null default now());
create table if not exists public.swiftpay_store_receipts(
 request_id uuid primary key, customer_id uuid not null references auth.users(id), profile_id uuid not null references public.swiftshop_users(id),
 category text not null references public.stores(category), amount_cents bigint not null check(amount_cents between 1 and 10000000),
 fee_cents bigint not null default 15 check(fee_cents=15), balance_after_cents bigint not null check(balance_after_cents>=0),
 transaction_id uuid not null unique references public.swiftpay_transactions(id),
 created_at timestamptz not null default now(), settled_at timestamptz);
alter table public.swiftpay_store_providers enable row level security;
alter table public.swiftpay_store_receipts enable row level security;
revoke all on public.swiftpay_store_providers,public.swiftpay_store_receipts from public,anon,authenticated;
create or replace function public.swiftpay_store_provider(p_category text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.swiftpay_store_providers; rows jsonb; due bigint;
begin
 if auth.uid() is null or not (exists(select 1 from public.merchant_members where user_id=auth.uid() and category=p_category) or public.swift_admin_session() is true) then raise exception 'Store access required' using errcode='42501';end if;
 insert into public.swiftpay_store_providers(category) values(p_category) on conflict(category) do nothing;
 select * into p from public.swiftpay_store_providers where category=p_category;
 select coalesce(sum(amount_cents),0) into due from public.swiftpay_store_receipts where category=p_category and settled_at is null;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into rows from
 (select request_id,amount_cents,created_at,settled_at from public.swiftpay_store_receipts where category=p_category order by created_at desc limit 50)t;
 return jsonb_build_object('category',p.category,'payload','swiftshop-store:v1:'||p.code,'active',p.active,'dueCents',due,'receipts',rows);
end $$;
create or replace function public.swiftpay_store_lookup(p_payload text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare parts text[];p public.swiftpay_store_providers;
begin
 if auth.uid() is null or not exists(select 1 from public.swiftshop_users where auth_user_id=auth.uid()) then raise exception 'Customer account required' using errcode='42501';end if;
 parts:=string_to_array(p_payload,':');
 if array_length(parts,1) is distinct from 3 or parts[1]<>'swiftshop-store' or parts[2]<>'v1' or parts[3]!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'Scan a SwiftPay store code';end if;
 select * into p from public.swiftpay_store_providers where code=parts[3]::uuid and active;
 if not found then raise exception 'This store payment code is unavailable';end if;
 return jsonb_build_object('category',p.category,'feeCents',15);
end $$;
create or replace function public.swiftpay_store_pay(p_payload text,p_amount_cents bigint,p_expected_total_cents bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare info jsonb;u public.swiftshop_users;r public.swiftpay_store_receipts;held bigint;cents bigint;txn uuid;
begin
 if auth.uid() is null then raise exception 'Sign in to SwiftPay' using errcode='42501';end if;
 if p_request_id is null or p_amount_cents is null or p_amount_cents not between 1 and 10000000 or p_expected_total_cents is distinct from p_amount_cents+15 then raise exception 'Review a valid amount including the BZ$0.15 fee';end if;
 info:=public.swiftpay_store_lookup(p_payload);
 select * into u from public.swiftshop_users where auth_user_id=auth.uid() for update;
 if not found then raise exception 'Customer wallet unavailable';end if;
 select * into r from public.swiftpay_store_receipts where request_id=p_request_id;
 if found then
  if r.customer_id<>auth.uid() or r.category<>info->>'category' or r.amount_cents<>p_amount_cents then raise exception 'Payment reference already used';end if;
  return jsonb_build_object('paid',true,'alreadyPaid',true,'amountCents',r.amount_cents,'totalCents',r.amount_cents+r.fee_cents,'balanceCents',r.balance_after_cents,'receipt',r.request_id);
 end if;
 if exists(select 1 from public.merchant_members where user_id=auth.uid() and category=info->>'category') then raise exception 'You cannot pay your own store';end if;
 select coalesce(sum(amount_cents+fee_cents),0) into held from public.swiftpay_payments where profile_id=u.id and state='reserved';
 cents:=round(coalesce(u.balance,0)*100)::bigint;
 if cents-held<p_expected_total_cents then raise exception 'Insufficient available SwiftCredit';end if;
 cents:=cents-p_expected_total_cents;
 perform set_config('swiftpay.balance_write','allowed',true);
 update public.swiftshop_users set balance=cents::numeric/100 where id=u.id;
 insert into public.swiftpay_transactions(customer_id,profile_id,kind,reference_kind,reference_id,amount_cents,fee_cents,balance_after_cents,reason,actor_id,request_id)
 values(auth.uid(),u.id,'payment','store',p_request_id,-p_amount_cents,15,cents,'SwiftPay store payment: '||(info->>'category'),auth.uid(),p_request_id) returning id into txn;
 insert into public.swiftpay_store_receipts(request_id,customer_id,profile_id,category,amount_cents,balance_after_cents,transaction_id)
 values(p_request_id,auth.uid(),u.id,info->>'category',p_amount_cents,cents,txn);
 return jsonb_build_object('paid',true,'alreadyPaid',false,'amountCents',p_amount_cents,'totalCents',p_expected_total_cents,'balanceCents',cents,'receipt',p_request_id);
end $$;
revoke all on function public.swiftpay_store_provider(text),public.swiftpay_store_lookup(text),public.swiftpay_store_pay(text,bigint,bigint,uuid) from public,anon;
grant execute on function public.swiftpay_store_provider(text),public.swiftpay_store_lookup(text),public.swiftpay_store_pay(text,bigint,bigint,uuid) to authenticated;
notify pgrst,'reload schema';
commit;