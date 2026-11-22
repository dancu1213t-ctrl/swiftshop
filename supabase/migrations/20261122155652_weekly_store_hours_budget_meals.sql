-- Per-day schedules use ISO weekdays (1=Monday, 7=Sunday), in Belize time.
alter table public.merchant_storefronts add column if not exists weekly_hours jsonb;
create or replace function public.swift_weekly_hours_valid(p jsonb)
returns boolean language plpgsql immutable set search_path='' as $$
declare d jsonb; i integer;
begin
 if p is null then return true; end if;
 if jsonb_typeof(p)<>'object' or (select count(*) from jsonb_object_keys(p))<>7 then return false; end if;
 for i in 1..7 loop
  d:=p->i::text;
  if d is null or jsonb_typeof(d)<>'object' or jsonb_typeof(d->'closed') is distinct from 'boolean' then return false; end if;
  if not (d->>'closed')::boolean and (
   coalesce(d->>'open','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or
   coalesce(d->>'close','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or d->>'open'=d->>'close'
  ) then return false; end if;
 end loop;
 return true;
end $$;
alter table public.merchant_storefronts add constraint merchant_weekly_hours_valid check(public.swift_weekly_hours_valid(weekly_hours));

create or replace function public.swift_weekly_hours_open(p jsonb,p_at timestamptz default now())
returns boolean language plpgsql stable set search_path='' as $$
declare local_at timestamp:=p_at at time zone 'America/Belize'; day_no integer:=extract(isodow from local_at); t text:=to_char(local_at,'HH24:MI'); d jsonb:=p->day_no::text; prev jsonb:=p->(case when day_no=1 then 7 else day_no-1 end)::text;
begin
 if p is null then return true; end if;
 if not coalesce((d->>'closed')::boolean,true) then
  if d->>'open'<d->>'close' and t>=d->>'open' and t<d->>'close' then return true; end if;
  if d->>'open'>d->>'close' and t>=d->>'open' then return true; end if;
 end if;
 return not coalesce((prev->>'closed')::boolean,true) and prev->>'open'>prev->>'close' and t<prev->>'close';
end $$;
create or replace function public.swift_store_scheduled_open(p_category text,p_at timestamptz default now())
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select not coalesce(m.auto_close,false) or case when m.weekly_hours is not null
 then public.swift_weekly_hours_open(m.weekly_hours,p_at)
 else public.swift_store_hours_open(m.opens_at,m.closes_at,p_at) end
 from public.merchant_storefronts m where m.category=p_category),true)
$$;
create or replace function public.swift_store_auto_close()
returns void language sql security definer set search_path='' as $$
 with states as (
 select s.category,public.swift_store_scheduled_open(s.category) available,
 (s.is_open='yes' or s.hours_auto_closed) enabled
 from public.stores s join public.merchant_storefronts m using(category)
 where m.auto_close
 ) update public.stores s set
 is_open=case when st.enabled and st.available then 'yes' else 'no' end,
 hours_auto_closed=st.enabled and not st.available
 from states st where s.category=st.category
 and (s.is_open is distinct from case when st.enabled and st.available then 'yes' else 'no' end
 or s.hours_auto_closed is distinct from (st.enabled and not st.available))
$$;

create or replace function public.swift_save_store_weekly_hours(p_category text,p_hours jsonb,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not (
 exists(select 1 from public.merchant_members where user_id=auth.uid() and category=p_category)
 or public.swift_worker_kind()='admin'
 ) then raise exception 'You cannot change this store.'; end if;
 if p_enabled is null or p_hours is null or not public.swift_weekly_hours_valid(p_hours) then raise exception 'Set valid hours for all seven days. Opening and closing times must differ.'; end if;
 if not exists(select 1 from public.stores where category=p_category) then raise exception 'Store not found.'; end if;
 insert into public.merchant_storefronts(category,weekly_hours,auto_close)
 values(p_category,p_hours,p_enabled)
 on conflict(category) do update set weekly_hours=excluded.weekly_hours,auto_close=excluded.auto_close;
 -- A previous scheduled closure must be released when automatic hours are disabled.
 if not p_enabled then
 update public.stores set is_open=case when hours_auto_closed then 'yes' else is_open end,hours_auto_closed=false where category=p_category;
 else perform public.swift_store_auto_close(); end if;
 return jsonb_build_object('category',p_category,'weekly_hours',p_hours,'auto_close',p_enabled);
end $$;
revoke all on function public.swift_save_store_weekly_hours(text,jsonb,boolean) from public,anon;
grant execute on function public.swift_save_store_weekly_hours(text,jsonb,boolean) to authenticated;
revoke all on function public.swift_store_scheduled_open(text,timestamptz) from public;
grant execute on function public.swift_store_scheduled_open(text,timestamptz) to anon,authenticated,service_role;

create or replace function public.swift_store_directory()
returns jsonb language sql stable security definer set search_path='' as $$
select coalesce(jsonb_agg(jsonb_build_object(
'category',s.category,
'is_open',case when (s.is_open='yes' or s.hours_auto_closed) and r.status='live' and z.active and public.swift_store_scheduled_open(s.category) then 'yes' else 'no' end,
'manual_open',s.is_open='yes' or s.hours_auto_closed,
'tags',coalesce(m.tags,'{}'::text[]),'opens_at',m.opens_at,'closes_at',m.closes_at,
'auto_close',coalesce(m.auto_close,false),'weekly_hours',m.weekly_hours,
'latitude',m.latitude,'longitude',m.longitude,'name',coalesce(r.display_name,r.name),'logo',r.logo,
'zone_id',r.zone_id,'district_id',z.district_id)),'[]'::jsonb)
from public.stores s join public.swift_store_registry r using(category)
join public.swift_service_zones z on z.id=r.zone_id
left join public.merchant_storefronts m using(category)
where public.swift_store_visible(s.category)
$$;
create or replace function public.swift_store_legacy_hours_guard()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not public.swift_store_scheduled_open(new.category) then raise exception 'Store % is outside opening hours',new.category; end if;
 return new;
end $$;
create or replace function public.swift_store_checkout_hours_guard()
returns trigger language plpgsql security definer set search_path='' as $$
declare v text;
begin
 if exists(select 1 from public.customer_order_tracking where id=new.id) then return new; end if;
 select i->>'category' into v from jsonb_array_elements(new.snapshot->'items') i
 where not public.swift_store_scheduled_open(i->>'category') limit 1;
 if v is not null then raise exception 'Store % is closed. Remove its items or try again during opening hours.',v; end if;
 return new;
end $$;

create or replace function public.swift_budget_meals(p_budget_cents integer,p_zone text,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_budget_cents is null or p_budget_cents<1 or p_budget_cents>100000 or p_offset<0 or p_offset>500 then raise exception 'Enter a food budget between BZ$0.01 and BZ$1,000.'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (
 select p.id,p.name,p.category,p.price,p.image,p.was,p.description,p.tags,p.catalog_details,p.active,
 coalesce(r.display_name,r.name) store_name
 from public.products p join public.swift_store_registry r using(category)
 join public.stores s using(category) join public.swift_service_zones z on z.id=r.zone_id
 where r.zone_id=p_zone and z.active and r.status='live' and public.swift_store_visible(p.category)
 and r.business_type='Food' and p.active='yes' and p.price>0 and round(p.price*100)<=p_budget_cents
 and (s.is_open='yes' or s.hours_auto_closed) and public.swift_store_scheduled_open(p.category)
 and coalesce(p.catalog_details->>'type','') not in ('coffee','technology','pharmacy','clothing','sneakers')
 and concat_ws(' ',p.name,p.subcategory) !~* '(gift.?card|subscription|frappe|frappuccino|latte|cold foam|espresso|beverage|drink|matcha|coffee)'
 order by p.price desc,p.id limit 24 offset p_offset
 ) x);
end $$;
revoke all on function public.swift_budget_meals(integer,text,integer) from public;
grant execute on function public.swift_budget_meals(integer,text,integer) to anon,authenticated;
notify pgrst,'reload schema';

