begin;
create table if not exists public.swift_order_reviews (
 customer_id uuid not null references auth.users(id) on delete cascade,
 tracking_id uuid not null references public.customer_order_tracking(id) on delete cascade,
 target_kind text not null check(target_kind in ('store','runner')),
 target_key text not null,
 stars smallint not null check(stars between 1 and 5),
 created_at timestamptz not null default now(),
 primary key(tracking_id,target_kind,target_key)
);
alter table public.swift_order_reviews enable row level security;
revoke all on public.swift_order_reviews from anon,authenticated;

create or replace function public.swift_order_review_targets(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.customer_order_tracking; worker uuid; result jsonb;
begin
 select * into d from public.customer_order_tracking where id=p_id and customer_id=auth.uid();
 if not found or d.phase is distinct from 'delivered' then raise exception 'Only your completed orders can be rated';end if;
 select assigned_runner_id into worker from public.orders where order_id=d.linked_order_id and status='Delivered';
 select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'key',key,'stars',r.stars)), '[]'::jsonb) into result
 from (
  select distinct 'store'::text kind, item->>'category' key
  from jsonb_array_elements(coalesce(d.snapshot->'items','[]'::jsonb)) item
  where nullif(trim(item->>'category'),'') is not null
  union all select 'runner',worker::text where worker is not null
 ) targets left join public.swift_order_reviews r on r.tracking_id=p_id and r.target_kind=targets.kind and r.target_key=targets.key;
 return result;
end $$;

create or replace function public.swift_submit_order_review(p_id uuid,p_kind text,p_key text,p_stars integer)
returns void language plpgsql security definer set search_path='' as $$
declare targets jsonb;
begin
 if p_stars is null or p_stars not between 1 and 5 then raise exception 'Choose 1 to 5 stars';end if;
 targets=public.swift_order_review_targets(p_id);
 if not exists(select 1 from jsonb_array_elements(targets) t where t->>'kind'=p_kind and t->>'key'=p_key) then raise exception 'This store or runner is not part of your completed order';end if;
 insert into public.swift_order_reviews(customer_id,tracking_id,target_kind,target_key,stars) values(auth.uid(),p_id,p_kind,p_key,p_stars)
 on conflict(tracking_id,target_kind,target_key) do nothing;
end $$;

create or replace function public.swift_rating_summary(p_kind text,p_key text)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('count',count(*),'average',round(avg(stars),1)) from public.swift_order_reviews where target_kind=p_kind and target_key=p_key;
$$;
create or replace function public.swift_completed_review_orders()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',id)), '[]'::jsonb) from
 (select id from public.customer_order_tracking where customer_id=auth.uid() and phase='delivered' order by id desc limit 50) orders;
$$;
revoke all on function public.swift_order_review_targets(uuid),public.swift_submit_order_review(uuid,text,text,integer),public.swift_rating_summary(text,text) from public,anon;
grant execute on function public.swift_order_review_targets(uuid),public.swift_submit_order_review(uuid,text,text,integer) to authenticated;
grant execute on function public.swift_rating_summary(text,text) to anon,authenticated;
revoke all on function public.swift_completed_review_orders() from public,anon;
grant execute on function public.swift_completed_review_orders() to authenticated;
commit;
