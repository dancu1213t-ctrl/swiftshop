begin;
alter table public.stores add column if not exists hours_auto_closed boolean not null default false;
create or replace function public.swift_store_schedule_state(p_open text,p_closed boolean,p_auto boolean,p_opens time,p_closes time,p_at timestamptz default now())
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('is_open',case when not coalesce(p_auto,false) or p_opens is null or p_closes is null then p_open when not public.swift_store_hours_open(p_opens,p_closes,p_at) then 'no' when p_closed then 'yes' else p_open end,
 'hours_auto_closed',case when coalesce(p_auto,false) and p_opens is not null and p_closes is not null then not public.swift_store_hours_open(p_opens,p_closes,p_at) else false end)
$$;
create or replace function public.swift_store_auto_close()
returns void language sql security definer set search_path='' as $$
 with states as(select s.category,public.swift_store_schedule_state(s.is_open,s.hours_auto_closed,m.auto_close,m.opens_at,m.closes_at) as next from public.stores s join public.merchant_storefronts m using(category))
 update public.stores s set is_open=states.next->>'is_open',hours_auto_closed=(states.next->>'hours_auto_closed')::boolean from states where s.category=states.category and (s.is_open is distinct from (states.next->>'is_open') or s.hours_auto_closed is distinct from (states.next->>'hours_auto_closed')::boolean)
$$;
create or replace function public.swift_store_schedule_guard()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.is_open='yes' and exists(select 1 from public.merchant_storefronts m where m.category=new.category and m.auto_close and not public.swift_store_hours_open(m.opens_at,m.closes_at)) then raise exception 'Outside your saved opening hours. Update Store appearance to change the schedule.';end if;
 if tg_op='UPDATE' and old.is_open is distinct from new.is_open and old.hours_auto_closed is not distinct from new.hours_auto_closed then new.hours_auto_closed:=false;end if;
 return new;
end $$;
create or replace function public.swift_storefront_close_after_save()
returns trigger language plpgsql security definer set search_path='' as $$
declare next jsonb;
begin
 select public.swift_store_schedule_state(s.is_open,s.hours_auto_closed,new.auto_close,new.opens_at,new.closes_at) into next from public.stores s where s.category=new.category;
 if next is not null then update public.stores set is_open=next->>'is_open',hours_auto_closed=(next->>'hours_auto_closed')::boolean where category=new.category and (is_open is distinct from (next->>'is_open') or hours_auto_closed is distinct from (next->>'hours_auto_closed')::boolean);end if;
 return new;
end $$;
revoke all on function public.swift_store_schedule_state(text,boolean,boolean,time,time,timestamptz) from public,anon,authenticated;
select public.swift_store_auto_close();
commit;