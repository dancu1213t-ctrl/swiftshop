begin;
create or replace function public.swift_store_register(p_id uuid,p_data jsonb) returns text language plpgsql security definer set search_path='' as $$
declare cat text;z public.swift_service_zones;u auth.users;lat float8;lng float8;v text;old public.swift_store_onboarding;
begin
 if auth.uid() is null or p_id is null then raise exception 'Sign in required';end if;
 perform pg_advisory_xact_lock(hashtextextended('store:'||p_id::text,0));select * into old from public.swift_store_onboarding where request_id=p_id;
 if found then
  if not public.swift_region_staff_zone((select zone_id from public.swift_store_registry where category=old.category)) and not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and lower(email)=old.owner_email) then raise exception 'Store access required';end if;
  if old.request_data<>p_data then raise exception 'This registration was already saved with other details';end if;return old.category;
 end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>1600000 then raise exception 'Registration is too large';end if;
 select * into z from public.swift_service_zones where id=p_data->>'zone_id';if not found then raise exception 'Choose a service zone';end if;
 select * into u from auth.users where id=auth.uid();
 if not public.swift_region_staff_zone(z.id) and (u.email_confirmed_at is null or lower(u.email)<>lower(trim(p_data->>'owner_email'))) then raise exception 'A verified owner or assigned coworker must register the store';end if;
 if length(trim(coalesce(p_data->>'name',''))) not between 2 and 120 or coalesce(p_data->>'owner_email','') !~* '^[^ @]+@[^ @]+\.[^ @]+$' or length(coalesce(p_data->>'phone','')) not between 7 and 30 or length(trim(coalesce(p_data->>'address',''))) not between 3 and 300 then raise exception 'Complete store name, owner email, phone and address';end if;
 if coalesce(p_data->>'business_type','') not in('Food','Cafes','Pharmacy','Groceries','Shops','Apparel','Tech') then raise exception 'Choose a business category';end if;
 lat:=(p_data->>'latitude')::float8;lng:=(p_data->>'longitude')::float8;
 if public.swift_district_at(lat,lng) is distinct from z.district_id then raise exception 'The store pin must be in the selected district';end if;
 if length(coalesce(p_data->>'logo','')) not between 40 and 200000 or (p_data->>'logo') !~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$' then raise exception 'Upload a store logo';end if;
 if length(coalesce(p_data->>'cover_image',''))>1300000 or (coalesce(p_data->>'cover_image','')<>'' and p_data->>'cover_image' !~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$') then raise exception 'Choose a smaller banner image';end if;
 if (nullif(p_data->>'opens_at','') is null)<>(nullif(p_data->>'closes_at','') is null) then raise exception 'Set both opening and closing time';end if;
 perform pg_advisory_xact_lock(hashtextextended('store-owner:'||auth.uid()::text,0));
 perform pg_advisory_xact_lock(hashtextextended('store-name:'||z.id||':'||lower(trim(p_data->>'name')),0));
 if not public.swift_region_staff_zone(z.id) and (select count(*) from public.swift_store_registry where created_by=auth.uid() and status in('draft','ready'))>=5 then raise exception 'Finish your existing store setups before adding another';end if;
 if exists(select 1 from public.swift_store_registry where zone_id=z.id and lower(trim(name))=lower(trim(p_data->>'name'))) then raise exception 'A store with this name is already registered in this zone';end if;
 cat:='store_'||replace(p_id::text,'-','');
 insert into public.stores(category,is_open) values(cat,'no');
 insert into public.swift_store_registry(category,name,business_type,logo,zone_id,created_by) values(cat,trim(p_data->>'name'),p_data->>'business_type',p_data->>'logo',z.id,auth.uid());
 insert into public.swift_store_onboarding values(p_id,cat,lower(trim(p_data->>'owner_email')),null,null,p_data);
 perform set_config('swiftshop.onboarding',cat,true);
 insert into public.merchant_storefronts(category,cover_image,phone,address,latitude,longitude,opens_at,closes_at,auto_close) values(cat,nullif(p_data->>'cover_image',''),p_data->>'phone',p_data->>'address',lat,lng,nullif(p_data->>'opens_at','')::time,nullif(p_data->>'closes_at','')::time,nullif(p_data->>'opens_at','') is not null);
 perform set_config('swiftshop.onboarding','',true);
 insert into public.swift_merchant_commission_accounts(category,active) values(cat,false) on conflict do nothing;
 insert into public.swift_region_audit(actor_id,action,entity) values(auth.uid(),'store_created',cat);
 return cat;
end$$;
commit;

