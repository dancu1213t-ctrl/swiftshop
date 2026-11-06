begin;
-- One policy for Orange Walk checkout and dispatch. City quotes remain unchanged.
create or replace function public.swift_pickup_stop_price(p_pickups jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare stop jsonb;dedup jsonb:='[]';seen text[]:=array[]::text[];k text;a double precision;b double precision;pa double precision;pb double precision;km double precision;nearby integer:=0;cross_town integer:=0;i integer:=0;n integer;
begin
 if jsonb_typeof(p_pickups) is distinct from 'array' or jsonb_array_length(p_pickups) not between 1 and 100 then raise exception 'Add pickup stops before quoting delivery';end if;
 for stop in select value from jsonb_array_elements(p_pickups) loop
  a:=(stop->>'lat')::double precision;b:=(stop->>'lng')::double precision;
  if a is not null and b is not null then
   if a not between -90 and 90 or b not between -180 and 180 then raise exception 'Invalid pickup coordinates';end if;
   k:=round(a::numeric,6)::text||','||round(b::numeric,6)::text;
  else k:='missing:'||coalesce(nullif(stop->>'key',''),i::text);end if;
  if not k=any(seen) then seen:=array_append(seen,k);dedup:=dedup||jsonb_build_array(stop);end if;i:=i+1;
 end loop;
 n:=jsonb_array_length(dedup);
 if n>7 then raise exception 'Use up to seven store pickups per order';end if;
 for i in 0..n-1 loop
  stop:=dedup->i;a:=(stop->>'lat')::double precision;b:=(stop->>'lng')::double precision;
  if n>1 and (a is null or b is null) then raise exception 'A store needs a confirmed pickup pin before it can be combined with another store';end if;
  if i>0 then
   km:=6371*2*asin(least(1,sqrt(power(sin(radians(a-pa)/2),2)+cos(radians(pa))*cos(radians(a))*power(sin(radians(b-pb)/2),2))));
   if km>3 then cross_town:=cross_town+1;else nearby:=nearby+1;end if;
  end if;pa:=a;pb:=b;
 end loop;
 return jsonb_build_object('base_fee_cents',450,'nearby_extra_stops',nearby,'cross_town_extra_stops',cross_town,'extra_stop_fee_cents',nearby*150+cross_town*200,'pickup_count',n,'fee_cents',450+nearby*150+cross_town*200,'cross_town_threshold_km',3,'pricing_version','ow-stops-20261106');
end $$;
revoke all on function public.swift_pickup_stop_price(jsonb) from public,anon,authenticated;

do $copy$ declare d text;begin
 if to_regprocedure('public.swift_region_quote_before_stop_pricing(jsonb,text)') is null then
  d:=pg_get_functiondef('public.swift_region_quote(jsonb,text)'::regprocedure);
  execute replace(d,'FUNCTION public.swift_region_quote(','FUNCTION public.swift_region_quote_before_stop_pricing(');
 end if;
 if to_regprocedure('public.swift_region_dispatch_quote_before_stop_pricing(text,jsonb)') is null then
  d:=pg_get_functiondef('public.swift_region_dispatch_quote(text,jsonb)'::regprocedure);
  execute replace(d,'FUNCTION public.swift_region_dispatch_quote(','FUNCTION public.swift_region_dispatch_quote_before_stop_pricing(');
 end if;
end $copy$;
revoke all on function public.swift_region_quote_before_stop_pricing(jsonb,text) from public,anon,authenticated;
revoke all on function public.swift_region_dispatch_quote_before_stop_pricing(text,jsonb) from public,anon,authenticated;

create or replace function public.swift_region_quote(p_items jsonb,p_coordinates text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare q jsonb;item jsonb;pickups jsonb:='[]';m public.merchant_storefronts;o public.swift_store_offers;category text;key text;
begin
 q:=public.swift_region_quote_before_stop_pricing(p_items,p_coordinates);
 if q->>'zone_id'<>'orange-walk' then return q;end if;
 for item in select value from jsonb_array_elements(p_items) loop
  category:=item->>'category';
  if nullif(item->>'offer_id','') is not null then
   select * into o from public.swift_store_offers where id=(item->>'offer_id')::uuid;
   pickups:=pickups||jsonb_build_array(jsonb_build_object('key','offer:'||o.id,'lat',o.pickup_lat,'lng',o.pickup_lng));
  else
   key:=case when category=any(array['Snack','Drink','Household','Hygiene','Vegetables','Treats']) then 'Snack' else category end;
   select * into m from public.merchant_storefronts f where f.category=key;
   pickups:=pickups||jsonb_build_array(jsonb_build_object('key',key,'lat',m.latitude,'lng',m.longitude));
  end if;
 end loop;
 return q||public.swift_pickup_stop_price(pickups);
end $$;

create or replace function public.swift_region_dispatch_quote(p_zone text,p_stops jsonb) returns numeric
language plpgsql stable security definer set search_path='' as $$
declare result numeric;pickups jsonb:='[]';s jsonb;loc text;i integer;
begin
 result:=public.swift_region_dispatch_quote_before_stop_pricing(p_zone,p_stops);
 if p_zone<>'orange-walk' then return result;end if;
 if jsonb_typeof(p_stops) is distinct from 'array' or jsonb_array_length(p_stops) not between 2 and 8 then raise exception 'Add pickups and a final drop-off';end if;
 for i in 0..jsonb_array_length(p_stops)-2 loop
  s:=p_stops->i;loc:=replace(s->>'location',' ','');
  if loc ~ '^-?[0-9]+(\.[0-9]+)?,-?[0-9]+(\.[0-9]+)?$' then
   pickups:=pickups||jsonb_build_array(jsonb_build_object('key',loc,'lat',split_part(loc,',',1)::double precision,'lng',split_part(loc,',',2)::double precision));
  elsif jsonb_array_length(p_stops)=2 then pickups:=jsonb_build_array(jsonb_build_object('key',loc));
  else raise exception 'Use exact map pins for every pickup to calculate extra-stop fees';end if;
 end loop;
 return (public.swift_pickup_stop_price(pickups)->>'fee_cents')::numeric/100;
end $$;

create or replace function public.swift_dispatch_fee_preview(p_zone text,p_stops jsonb,p_tracking uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare fee numeric;t public.customer_order_tracking;
begin
 if not public.swift_region_admin() then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_tracking is not null then
  select * into t from public.customer_order_tracking where id=p_tracking;
  if not found or t.zone_id is distinct from p_zone then raise exception 'Choose the customer order district';end if;
  fee:=nullif(t.snapshot->>'delivery_fee','')::numeric;
  if fee is not null and fee>0 then return jsonb_build_object('fee_cents',round(fee*100),'checkout_locked',true,'breakdown',t.snapshot->'delivery_pricing');end if;
 end if;
 fee:=public.swift_region_dispatch_quote(p_zone,p_stops);
 return jsonb_build_object('fee_cents',round(fee*100),'checkout_locked',false);
end $$;
revoke all on function public.swift_dispatch_fee_preview(text,jsonb,uuid) from public,anon;
grant execute on function public.swift_dispatch_fee_preview(text,jsonb,uuid) to authenticated;

do $patch$ declare d text;begin
 d:=pg_get_functiondef('public.swift_dispatch_run(uuid,text,text,text,text,text,text,numeric,jsonb,jsonb)'::regprocedure);
 if position('''delivery_fee'',base' in d)=0 then
  if position('''zone_id'',target_zone,''kind''' in d)=0 then raise exception 'Unexpected dispatch definition';end if;
  execute replace(d,'''zone_id'',target_zone,''kind''','''delivery_fee'',base,''zone_id'',target_zone,''kind''');
 end if;
 d:=pg_get_functiondef('public.swift_dispatch_route_guard()'::regprocedure);
 if position('base:=case new.run_kind' in d)>0 then
  execute replace(d,'base:=case new.run_kind when ''shopping_list'' then 5 when ''multiple_pickups'' then 6 else 3.5 end;','base:=(d->>''delivery_fee'')::numeric;if base is null or base<0 then raise exception ''A confirmed delivery quote is required'';end if;');
 end if;
 d:=pg_get_functiondef('runner_extension_private.order_details_trigger()'::regprocedure);
 if position('pricing20261106' in d)=0 then
  execute replace(d,'new.runner_pay:=case new.priority when ''Urgent'' then 6 when ''Priority'' then 4.5 else 3.5 end;','new.runner_pay:=coalesce((select (t.snapshot->>''delivery_fee'')::numeric from public.customer_order_tracking t where t.id=new.customer_tracking_id),case new.priority when ''Urgent'' then 6 when ''Priority'' then 4.5 else 3.5 end); /* pricing20261106: preserve quoted delivery pay */');
 end if;
 d:=pg_get_functiondef('public.swift_merchant_validate_delivery()'::regprocedure);
 if position('''delivery_pricing'',q' in d)=0 then
  execute replace(d,'new.zone_id:=q->>''zone_id'';','new.zone_id:=q->>''zone_id'';new.snapshot:=new.snapshot||jsonb_build_object(''delivery_pricing'',q);');
 end if;
 d:=pg_get_functiondef('public.swiftpay_tracking_invoice()'::regprocedure);
 if position('delivery:=(public.swift_region_quote' in d)=0 then
  execute replace(d,'invoice=item_sum+delivery+tip;','delivery:=(public.swift_region_quote(new.snapshot->''items'',new.snapshot->>''customer_location'')->>''fee_cents'')::numeric/100;invoice=item_sum+delivery+tip;');
 end if;
end $patch$;
notify pgrst,'reload schema';
commit;