begin;
create table if not exists public.swift_support_requests(
 id uuid primary key, owner_id uuid not null references auth.users(id), category text, order_id uuid references public.customer_order_tracking(id),
 kind text not null check(kind in('order_problem','cancel_request','refund_request','customer_unreachable','topup_request','general')),details text not null check(length(details) between 5 and 1200),
 amount_cents integer check(amount_cents between 100 and 100000),status text not null default 'open' check(status in('open','reviewing','resolved','declined')),
 admin_note text not null default '' check(length(admin_note)<=1000),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),reviewed_by uuid references auth.users(id));
create index if not exists swift_support_owner on public.swift_support_requests(owner_id,created_at desc);
alter table public.swift_support_requests enable row level security;
revoke all on public.swift_support_requests from public,anon,authenticated;
grant all on public.swift_support_requests to service_role;
create or replace function public.swift_support_request(p_id uuid,p_kind text,p_details text,p_order uuid default null,p_amount integer default null,p_category text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare existing public.swift_support_requests;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501';end if;
 select * into existing from public.swift_support_requests where id=p_id;
 if found then if existing.owner_id<>auth.uid() then raise exception 'Request unavailable';end if;return existing.id;end if;
 if p_kind not in('order_problem','cancel_request','refund_request','customer_unreachable','topup_request','general') or p_details is null or length(trim(p_details)) not between 5 and 1200 then raise exception 'Choose a request type and enter 5–1200 characters';end if;
 if p_kind in('order_problem','cancel_request','refund_request','customer_unreachable') and p_order is null then raise exception 'Choose an order';end if;
 if p_order is not null and not exists(select 1 from public.customer_order_tracking t where t.id=p_order and(t.customer_id=auth.uid() or t.runner_id=auth.uid() or exists(select 1 from public.swift_merchant_order_parts op join public.merchant_members m on m.category=op.category and m.user_id=auth.uid() where op.tracking_id=t.id))) then raise exception 'Order access required' using errcode='42501';end if;
 if p_category is not null and not public.swift_merchant_access(p_category,'orders') then raise exception 'Store access required';end if;
 if p_kind='topup_request' then
  if p_amount is null or p_amount not between 100 and 100000 then raise exception 'Enter BZ$1–1000';end if;
 else p_amount:=null;end if;
 if (select count(*) from public.swift_support_requests where owner_id=auth.uid() and created_at>now()-interval '1 hour')>=10 then raise exception 'Please wait before sending another request';end if;
 insert into public.swift_support_requests(id,owner_id,category,order_id,kind,details,amount_cents) values(p_id,auth.uid(),p_category,p_order,p_kind,trim(p_details),p_amount);
 return p_id;
end $$;
create or replace function public.swift_support_list(p_admin boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 if p_admin then perform public.swift_admin_session();end if;
 return coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from(select id,owner_id,order_id,kind,details,amount_cents,status,admin_note,created_at,updated_at,category from public.swift_support_requests where p_admin or owner_id=auth.uid() order by created_at desc limit 100)r),'[]'::jsonb);
end $$;
create or replace function public.swift_support_review(p_id uuid,p_status text,p_note text default '') returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.swift_admin_session();
 if p_status not in('open','reviewing','resolved','declined') or length(coalesce(p_note,''))>1000 then raise exception 'Invalid review';end if;
 update public.swift_support_requests set status=p_status,admin_note=coalesce(p_note,''),reviewed_by=auth.uid(),updated_at=now() where id=p_id;
 if not found then raise exception 'Request unavailable';end if;
 -- Reviewing a request never moves money, cancels an order, or changes wallet balances.
end $$;
revoke all on function public.swift_support_request(uuid,text,text,uuid,integer,text),public.swift_support_list(boolean),public.swift_support_review(uuid,text,text) from public,anon;
grant execute on function public.swift_support_request(uuid,text,text,uuid,integer,text),public.swift_support_list(boolean),public.swift_support_review(uuid,text,text) to authenticated;
create or replace function public.swift_support_orders() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 return coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from(select t.id,t.phase,t.created_at from public.customer_order_tracking t where t.customer_id=auth.uid() or t.runner_id=auth.uid() or exists(select 1 from public.swift_merchant_order_parts op join public.merchant_members m on m.category=op.category and m.user_id=auth.uid() where op.tracking_id=t.id) order by t.created_at desc limit 50)r),'[]'::jsonb);
end $$;
revoke all on function public.swift_support_orders() from public,anon;
grant execute on function public.swift_support_orders() to authenticated;
notify pgrst,'reload schema';
commit;
