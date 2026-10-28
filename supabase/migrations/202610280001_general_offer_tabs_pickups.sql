begin;
alter table public.swift_store_offers add column if not exists is_general boolean not null default false,
 add column if not exists pickup_name text not null default '',
 add column if not exists pickup_lat double precision,
 add column if not exists pickup_lng double precision;
alter table public.swift_store_offers add constraint swift_offer_pickup_valid check (
 length(pickup_name)<=150 and ((pickup_lat is null and pickup_lng is null) or
 (pickup_lat between -90 and 90 and pickup_lng between -180 and 180 and pickup_lat is not null and pickup_lng is not null)));
update public.swift_store_offers set is_general=true where category in('Snack','Drink','Household','Hygiene','Vegetables','Treats');
create table if not exists public.swift_offer_tabs(name text primary key check(length(trim(name)) between 1 and 60 and name=trim(name)),position integer not null default 1000,created_at timestamptz not null default now());
create unique index if not exists swift_offer_tabs_name_case on public.swift_offer_tabs(lower(name));
alter table public.swift_offer_tabs enable row level security;
create policy "offer tabs read" on public.swift_offer_tabs for select to anon,authenticated using(true);
create policy "admin offer tabs insert" on public.swift_offer_tabs for insert to authenticated with check(public.swift_admin_session() is true);
create policy "admin offer tabs update" on public.swift_offer_tabs for update to authenticated using(public.swift_admin_session() is true) with check(public.swift_admin_session() is true);
revoke all on public.swift_offer_tabs from anon,authenticated;
grant select on public.swift_offer_tabs to anon,authenticated;
grant insert,update on public.swift_offer_tabs to authenticated;
insert into public.swift_offer_tabs(name,position) select name,n::integer from unnest(array['Grocery','Pizza','Sushi','Burgers','Fast Food','American','Wings','Desserts','Breakfast','Mexican','Gifts','BBQ','Italian','Asian','Coffee','Pharmacy']) with ordinality as t(name,n) on conflict do nothing;
create or replace function public.swift_offer_location_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.is_general then
  if public.swift_admin_session() is not true then raise exception 'Administrator access required for general offers' using errcode='42501';end if;
  if new.category not in('Snack','Drink','Household','Hygiene','Vegetables','Treats') then raise exception 'Invalid general offer destination';end if;
  if new.published and coalesce((new.order_config->>'enabled')::boolean,false) and (new.pickup_lat is null or new.pickup_lng is null or length(trim(new.pickup_name))=0) then raise exception 'Add a pickup name and exact map pin before enabling General offer orders';end if;
 end if;return new;
end $$;
create trigger swift_offer_location_guard before insert or update on public.swift_store_offers for each row execute function public.swift_offer_location_guard();
revoke all on function public.swift_offer_location_guard() from public,anon,authenticated;
-- Copy pickup pins from trusted offer records, never from customer-submitted cart coordinates.
create or replace function public.swift_order_offer_pickups() returns trigger language plpgsql security definer set search_path='' as $$
declare item jsonb;r public.swift_store_offers;items jsonb:='[]';pickups jsonb:='[]';routes jsonb:='[]';origin text;destination text;all_offers boolean:=true;all_pinned boolean:=true;seen text[]:=array[]::text[];route jsonb;
begin
 if jsonb_typeof(new.snapshot->'items') is distinct from 'array' then return new;end if;
 destination:=new.snapshot->>'customer_location';
 for item in select value from jsonb_array_elements(new.snapshot->'items') loop
  if nullif(item->>'offer_id','') is null then all_offers:=false;items:=items||jsonb_build_array(item);continue;end if;
  select * into r from public.swift_store_offers where id=(item->>'offer_id')::uuid;
  if found and r.pickup_lat is not null and r.pickup_lng is not null then
   origin:=r.pickup_lat::text||','||r.pickup_lng::text;
   item:=(item-'offer_pickup')||jsonb_build_object('offer_pickup',jsonb_build_object('lat',r.pickup_lat,'lng',r.pickup_lng,'name',r.pickup_name));
   if not origin=any(seen) then
    seen:=array_append(seen,origin);pickups:=pickups||jsonb_build_array(jsonb_build_object('offer_id',r.id,'name',r.pickup_name,'lat',r.pickup_lat,'lng',r.pickup_lng));
    if destination ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*,\s*-?[0-9]+(\.[0-9]+)?\s*$' then routes:=routes||jsonb_build_array('https://www.google.com/maps/dir/?api=1&origin='||origin||'&destination='||replace(destination,' ',''));end if;
   end if;
  else all_pinned:=false;item:=item-'offer_pickup';end if;
  items:=items||jsonb_build_array(item);
 end loop;
 new.snapshot:=jsonb_set(new.snapshot,'{items}',items);
 if jsonb_array_length(pickups)>0 then
  new.snapshot:=jsonb_set(new.snapshot,'{offer_pickups}',pickups);
  if all_offers and all_pinned and jsonb_array_length(routes)>0 then new.snapshot:=jsonb_set(new.snapshot,'{routes}',routes);
  elsif not all_offers and jsonb_array_length(routes)>0 and coalesce(new.snapshot->'gift','null'::jsonb)='null'::jsonb then
   for route in select value from jsonb_array_elements(routes) loop
    if not exists(select 1 from jsonb_array_elements_text(coalesce(new.snapshot->'routes','[]'::jsonb)) v where strpos(v,split_part(route#>>'{}','&destination=',1)||'&destination=')=1) then raise exception 'An offer pickup location changed. Remove the offer and choose it again before checkout.';end if;
   end loop;
  end if;
 end if;return new;
end $$;
create trigger a00_swift_order_offer_pickups before insert on public.customer_order_tracking for each row execute function public.swift_order_offer_pickups();
revoke all on function public.swift_order_offer_pickups() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
