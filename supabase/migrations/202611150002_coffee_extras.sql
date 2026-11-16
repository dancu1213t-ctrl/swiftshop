begin;
create or replace function public.swift_catalog_details_valid(v jsonb) returns boolean language plpgsql immutable set search_path='' as $$declare x jsonb;k text;begin
 if jsonb_typeof(v)<>'object' or length(v::text)>16000 then return false;end if;
 if exists(select 1 from jsonb_object_keys(v) t where t not in('type','size_system','sizes','colors','specifications','addons','addon_label')) then return false;end if;
 if v ? 'type' and v->>'type' not in('other','tennis','apparel','technology','pharmacy','coffee','food') then return false;end if;
 if v ? 'size_system' and v->>'size_system' not in('US','EU','MX','Standard') then return false;end if;
 foreach k in array array['sizes','colors'] loop
 if v ? k then if jsonb_typeof(v->k)<>'array' or jsonb_array_length(v->k)>40 then return false;end if;
 for x in select value from jsonb_array_elements(v->k) loop if jsonb_typeof(x)<>'string' or length(btrim(x#>>'{}')) not between 1 and 32 or (x#>>'{}')~'[[:cntrl:]·—]' then return false;end if;end loop;
 if (select count(*)<>count(distinct lower(value#>>'{}')) from jsonb_array_elements(v->k)) then return false;end if;end if;end loop;
 if v ? 'specifications' and (jsonb_typeof(v->'specifications')<>'string' or length(v->>'specifications')>1500) then return false;end if;
 if v ? 'addon_label' and (jsonb_typeof(v->'addon_label') is distinct from 'string' or length(trim(v->>'addon_label')) not between 1 and 40) then return false;end if;
 if v ? 'addons' then
  if jsonb_typeof(v->'addons') is distinct from 'array' or jsonb_array_length(v->'addons')>12 then return false;end if;
  for x in select value from jsonb_array_elements(v->'addons') loop
   if jsonb_typeof(x) is distinct from 'object' or exists(select 1 from jsonb_object_keys(x)t where t not in('id','name','price_cents')) then return false;end if;
   if jsonb_typeof(x->'id') is distinct from 'string' or (x->>'id') !~ '^[A-Za-z0-9_-]{1,64}$' or jsonb_typeof(x->'name') is distinct from 'string' or length(trim(x->>'name')) not between 1 and 40 or (x->>'name')~'[[:cntrl:]·—]' then return false;end if;
   if jsonb_typeof(x->'price_cents') is distinct from 'number' or (x->>'price_cents')::numeric not between 0 and 100000 or (x->>'price_cents')::numeric<>trunc((x->>'price_cents')::numeric) then return false;end if;
  end loop;
  if (select count(*)<>count(distinct value->>'id') or count(*)<>count(distinct lower(trim(value->>'name'))) from jsonb_array_elements(v->'addons')) then return false;end if;
 end if;
 return true;exception when others then return false;end $$;

create or replace function public.swift_product_checkout_price(p public.products,chosen jsonb)
returns numeric language plpgsql immutable set search_path='' as $$declare extra jsonb;begin
 if jsonb_typeof(chosen) is distinct from 'object' then raise exception 'Choose valid product options';end if;
 if not chosen ? 'addon_id' then return p.price;end if;
 if jsonb_typeof(chosen->'addon_id') is distinct from 'string' then raise exception 'Choose a valid extra';end if;
 select value into extra from jsonb_array_elements(coalesce(p.catalog_details->'addons','[]')) where value->>'id'=chosen->>'addon_id';
 if extra is null then raise exception 'This extra changed. Reopen the product';end if;
 return p.price+(extra->>'price_cents')::numeric/100;
end $$;
revoke all on function public.swift_product_checkout_price(public.products,jsonb) from public,anon,authenticated;
create or replace function public.swift_validate_product_selections() returns trigger language plpgsql security definer set search_path='' as $$declare i jsonb;p public.products;chosen jsonb;meta jsonb;result jsonb:='[]';label text;begin
 if jsonb_typeof(new.snapshot->'items') is distinct from 'array' then return new;end if;
 for i in select value from jsonb_array_elements(new.snapshot->'items') loop
 if nullif(i->>'offer_id','') is not null then result:=result||jsonb_build_array(i);continue;end if;
 select * into p from public.products where category=i->>'category' and name=i->>'name' and (nullif(i->>'product_id','') is null or id::text=i->>'product_id') limit 1;
 if not found then if nullif(i->>'product_id','') is not null then raise exception 'This product changed. Reopen the store';end if;result:=result||jsonb_build_array(i);continue;end if;
 meta:=p.catalog_details;chosen:=coalesce(i->'selected_options','{}'::jsonb);label:=p.name;
 if jsonb_typeof(chosen)<>'object' or exists(select 1 from jsonb_object_keys(chosen)t where t not in('size','size_system','color','addon_id')) then raise exception 'Choose valid product options';end if;
 if jsonb_array_length(coalesce(meta->'sizes','[]'))>0 then
 if coalesce(chosen->>'size_system','')<>coalesce(meta->>'size_system','Standard') or not (meta->'sizes' ? coalesce(chosen->>'size','')) then raise exception 'Choose an available size for %',p.name;end if;label:=label||' — '||coalesce(meta->>'size_system','Standard')||' '||(chosen->>'size');
 elsif chosen ? 'size' or chosen ? 'size_system' then raise exception 'This item has no size selection';end if;
 if jsonb_array_length(coalesce(meta->'colors','[]'))>0 then if not (meta->'colors' ? coalesce(chosen->>'color','')) then raise exception 'Choose an available color for %',p.name;end if;label:=label||' · '||(chosen->>'color');elsif chosen ? 'color' then raise exception 'This item has no color selection';end if;
 if (i->>'price')::numeric is distinct from public.swift_product_checkout_price(p,chosen) then raise exception 'Item or extra price changed. Reopen the product';end if;
 if chosen ? 'addon_id' then label:=label||' · '||(select value->>'name' from jsonb_array_elements(meta->'addons') where value->>'id'=chosen->>'addon_id');end if;
 i:=i||jsonb_build_object('display_name',label,'product_id',p.id,'selected_options',chosen);result:=result||jsonb_build_array(i);
 end loop;new.snapshot:=jsonb_set(new.snapshot,'{items}',result);return new;end $$;

do $patch$ declare d text;begin
 d:=pg_get_functiondef('public.swiftpay_tracking_invoice()'::regprocedure);
 if position('public.swift_product_checkout_price(catalog' in d)=0 then
  if position('catalog.price=(line->>''price'')::numeric' in d)=0 then raise exception 'Unexpected SwiftPay price validation. No changes applied';end if;
  execute replace(d,'catalog.price=(line->>''price'')::numeric','public.swift_product_checkout_price(catalog,coalesce(line->''selected_options'',''{}''::jsonb))=(line->>''price'')::numeric');
 end if;
end $patch$;
notify pgrst,'reload schema';
commit;
