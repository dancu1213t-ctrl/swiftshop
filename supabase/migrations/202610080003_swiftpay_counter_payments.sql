begin;
create table public.swiftpay_counter_sessions (
 id uuid primary key, customer_id uuid not null references auth.users(id) on delete cascade,
 secret_hash text not null, expires_at timestamptz not null default now()+interval '5 minutes',
 state text not null default 'open' check(state in ('open','requested','paid','declined','revoked')),
 worker_id uuid references auth.users(id) on delete set null, request_id uuid unique,
 amount_cents bigint check(amount_cents between 1 and 10000000), fee_cents bigint not null default 15 check(fee_cents=15),
 created_at timestamptz not null default now(), paid_at timestamptz, transaction_id uuid references public.swiftpay_transactions(id)
);
alter table public.swiftpay_counter_sessions enable row level security;
revoke all on public.swiftpay_counter_sessions from public,anon,authenticated;

create function public.swiftpay_counter_status(p_id uuid,p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.swiftpay_counter_sessions; n text;
begin
 select * into s from public.swiftpay_counter_sessions where id=p_id;
 if not found or auth.uid() is null or (s.customer_id<>auth.uid() and (s.worker_id is distinct from auth.uid() or s.request_id is distinct from p_request_id)) then raise exception 'Payment unavailable' using errcode='42501';end if;
 select display_name into n from public.profiles where id=s.worker_id;
 return jsonb_build_object('id',s.id,'state',s.state,'expired',s.expires_at<=now(),'expiresAt',s.expires_at,'worker',n,'amountCents',s.amount_cents,'feeCents',s.fee_cents,'totalCents',s.amount_cents+s.fee_cents,'transactionId',s.transaction_id);
end $$;

create function public.swiftpay_counter_code(p_id uuid,p_secret uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.swiftpay_counter_sessions;
begin
 if auth.uid() is null or p_id is null or p_secret is null or not exists(select 1 from public.swiftshop_users where auth_user_id=auth.uid()) then raise exception 'Sign in to SwiftPay';end if;
 insert into public.swiftpay_counter_sessions(id,customer_id,secret_hash) values(p_id,auth.uid(),md5(p_secret::text)) on conflict(id) do nothing;
 select * into s from public.swiftpay_counter_sessions where id=p_id;
 if s.customer_id<>auth.uid() or s.secret_hash<>md5(p_secret::text) or s.expires_at<=now() or s.state not in ('open','requested') then raise exception 'Create a new payment code';end if;
 return public.swiftpay_counter_status(p_id)||jsonb_build_object('payload','swiftshop-wallet:v1:'||p_id||':'||p_secret);
end $$;

create function public.swiftpay_counter_request(p_payload text,p_amount_cents bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a text[];s public.swiftpay_counter_sessions;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and active and role in ('runner','driver')) or not exists(select 1 from public.swift_worker_applications where user_id=auth.uid() and status='approved' and kind in ('runner','driver')) then raise exception 'Approved runner or driver access required' using errcode='42501';end if;
 if p_amount_cents is null or p_amount_cents not between 1 and 10000000 or p_request_id is null then raise exception 'Enter a valid BZD amount';end if;
 a=string_to_array(p_payload,':');
 if array_length(a,1) is distinct from 4 or a[1]<>'swiftshop-wallet' or a[2]<>'v1' then raise exception 'This is not a SwiftPay payment code';end if;
 select * into s from public.swiftpay_counter_sessions where id=a[3]::uuid for update;
 if not found or s.secret_hash<>md5((a[4]::uuid)::text) or s.customer_id=auth.uid() then raise exception 'Payment code unavailable';end if;
 if s.request_id=p_request_id and s.worker_id=auth.uid() and s.amount_cents=p_amount_cents then return public.swiftpay_counter_status(s.id,p_request_id);end if;
 if s.state<>'open' or s.expires_at<=now() then raise exception 'This payment code is already used or expired';end if;
 update public.swiftpay_counter_sessions set state='requested',worker_id=auth.uid(),request_id=p_request_id,amount_cents=p_amount_cents where id=s.id;
 return public.swiftpay_counter_status(s.id,p_request_id);
end $$;

create function public.swiftpay_counter_confirm(p_id uuid,p_expected_total_cents bigint,p_accept boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.swiftpay_counter_sessions;u public.swiftshop_users;held bigint;cents bigint;t uuid;
begin
 select * into s from public.swiftpay_counter_sessions where id=p_id for update;
 if not found or auth.uid() is null or s.customer_id<>auth.uid() then raise exception 'This payment is not yours' using errcode='42501';end if;
 if s.state='paid' then return public.swiftpay_counter_status(s.id);end if;
 if s.state in ('declined','revoked') then return public.swiftpay_counter_status(s.id);end if;
 if p_accept is distinct from true then update public.swiftpay_counter_sessions set state=case when state='open' then 'revoked' else 'declined' end where id=s.id;return public.swiftpay_counter_status(s.id);end if;
 if s.state<>'requested' or s.expires_at<=now() or p_expected_total_cents is distinct from s.amount_cents+s.fee_cents then raise exception 'Payment changed or expired. Request a new code';end if;
 if not exists(select 1 from public.profiles where id=s.worker_id and active and role in ('runner','driver')) or not exists(select 1 from public.swift_worker_applications where user_id=s.worker_id and status='approved') then raise exception 'Worker is no longer approved';end if;
 select * into u from public.swiftshop_users where auth_user_id=auth.uid() for update;
 if not found then raise exception 'Customer wallet unavailable';end if;
 select coalesce(sum(amount_cents+fee_cents),0) into held from public.swiftpay_payments where profile_id=u.id and state='reserved';
 cents=round(coalesce(u.balance,0)*100)::bigint;
 if cents-held<s.amount_cents+s.fee_cents then raise exception 'Insufficient available SwiftPay balance';end if;
 cents=cents-s.amount_cents-s.fee_cents;
 perform set_config('swiftpay.balance_write','allowed',true);
 update public.swiftshop_users set balance=cents::numeric/100 where id=u.id;
 insert into public.swiftpay_transactions(customer_id,profile_id,kind,reference_kind,reference_id,amount_cents,fee_cents,balance_after_cents,reason,actor_id,request_id)
 values(auth.uid(),u.id,'payment','counter',s.id,-s.amount_cents,15,cents,'SwiftPay separate payment',s.worker_id,s.request_id) returning id into t;
 update public.swiftpay_counter_sessions set state='paid',paid_at=now(),transaction_id=t where id=s.id;
 return public.swiftpay_counter_status(s.id);
end $$;

create function public.swiftpay_scan_order_payment(p_payload text,p_amount_cents bigint,p_complete boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 if p_payload not like 'swiftshop-pay:v1:%' then raise exception 'Scan a SwiftPay payment code';end if;
 r=public.swift_scan_completion(p_payload,false);
 if p_amount_cents is null or (r->>'amountCents')::bigint is distinct from p_amount_cents then raise exception 'Entered amount must match the customer-confirmed invoice, before the BZ$0.15 fee';end if;
 if p_complete is true then return public.swift_scan_completion(p_payload,true);end if;
 return r;
end $$;
revoke all on function public.swiftpay_counter_code(uuid,uuid),public.swiftpay_counter_status(uuid,uuid),public.swiftpay_counter_request(text,bigint,uuid),public.swiftpay_counter_confirm(uuid,bigint,boolean),public.swiftpay_scan_order_payment(text,bigint,boolean) from public,anon,authenticated;
grant execute on function public.swiftpay_counter_code(uuid,uuid),public.swiftpay_counter_status(uuid,uuid),public.swiftpay_counter_request(text,bigint,uuid),public.swiftpay_counter_confirm(uuid,bigint,boolean),public.swiftpay_scan_order_payment(text,bigint,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
