begin;
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
  if all_offers and all_pinned and jsonb_array_length(routes)>0 and coalesce(new.snapshot->'gift','null'::jsonb)='null'::jsonb then new.snapshot:=jsonb_set(new.snapshot,'{routes}',routes);
  elsif not all_offers and jsonb_array_length(routes)>0 and coalesce(new.snapshot->'gift','null'::jsonb)='null'::jsonb then
   for route in select value from jsonb_array_elements(routes) loop
    if not exists(select 1 from jsonb_array_elements_text(coalesce(new.snapshot->'routes','[]'::jsonb)) v where strpos(v,split_part(route#>>'{}','&destination=',1)||'&destination=')=1) then raise exception 'An offer pickup location changed. Remove the offer and choose it again before checkout.';end if;
   end loop;
  end if;
 end if;return new;
end $$;

notify pgrst,'reload schema';
commit;
