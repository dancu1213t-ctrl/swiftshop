begin;
alter table public.swift_admin_portal_members add column zone_id text references public.swift_service_zones(id);
-- Area operators must never inherit the legacy, global administrator role.
update public.profiles p set role='runner',active=m.previous_active from public.swift_admin_portal_members m where m.user_id=p.id and m.portal_role<>'owner' and p.role='admin';
update public.swift_admin_portal_members set active=false where portal_role<>'owner' and zone_id is null;
create or replace function public.swift_admin_portal_access() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m public.swift_admin_portal_members;email text;
begin
 select * into m from public.swift_admin_portal_members where user_id=auth.uid() and active;
 if not found then raise exception 'Admin portal access required' using errcode='42501';end if;
 select u.email into email from auth.users u where u.id=m.user_id and u.email_confirmed_at is not null;
 if email is null then raise exception 'Verified administrator sign-in required' using errcode='42501';end if;
 if m.portal_role='owner' and (lower(email)<>'dancu1213t@gmail.com' or not public.is_admin()) then raise exception 'Owner access required' using errcode='42501';end if;
 if m.portal_role<>'owner' and m.zone_id is null then raise exception 'Ask the owner to assign your service area' using errcode='42501';end if;
 return jsonb_build_object('role',m.portal_role,'email',email,'zone_id',m.zone_id);
end $$;
create function public.swift_admin_effective_zone(p_zone text default null) returns text language plpgsql stable security definer set search_path='' as $$
declare a jsonb;
begin a:=public.swift_admin_portal_access();
 if a->>'role'<>'owner' then if p_zone is not null and p_zone is distinct from a->>'zone_id' then raise exception 'This service area is not assigned to you' using errcode='42501';end if;return a->>'zone_id';end if;
 if p_zone is not null and not exists(select 1 from public.swift_service_zones where id=p_zone) then raise exception 'Choose a service area';end if;return p_zone;
end $$;
revoke all on function public.swift_admin_effective_zone(text) from public,anon;
grant execute on function public.swift_admin_effective_zone(text) to authenticated;
create function public.swift_admin_check_store(p_category text) returns void language plpgsql stable security definer set search_path='' as $$
declare z text;allowed text;
begin allowed:=public.swift_admin_effective_zone(null);select zone_id into z from public.swift_store_registry where category=p_category;
 if not found then raise exception 'Store not found';end if;
 if allowed is not null and z<>allowed then raise exception 'Store access is outside your assigned area' using errcode='42501';end if;
end $$;
revoke all on function public.swift_admin_check_store(text) from public,anon;
grant execute on function public.swift_admin_check_store(text) to authenticated;
create or replace function public.swift_admin_session() returns boolean language plpgsql stable security definer set search_path='' as $$begin if public.swift_admin_portal_access()->>'role'<>'owner' then raise exception 'Global management tools are owner-only' using errcode='42501';end if;return true;end $$;

alter function public.swift_admin_portal_snapshot(text) rename to swift_admin_portal_snapshot_internal;
revoke all on function public.swift_admin_portal_snapshot_internal(text) from public,anon,authenticated;
create function public.swift_admin_portal_snapshot(p_zone text default null) returns jsonb language sql stable security definer set search_path='' as $$select public.swift_admin_portal_snapshot_internal(public.swift_admin_effective_zone(p_zone))$$;
revoke all on function public.swift_admin_portal_snapshot(text) from public,anon;grant execute on function public.swift_admin_portal_snapshot(text) to authenticated;
alter function public.swift_admin_portal_rides(text) rename to swift_admin_portal_rides_internal;
revoke all on function public.swift_admin_portal_rides_internal(text) from public,anon,authenticated;
create function public.swift_admin_portal_rides(p_zone text default null) returns jsonb language sql stable security definer set search_path='' as $$select public.swift_admin_portal_rides_internal(public.swift_admin_effective_zone(p_zone))$$;
revoke all on function public.swift_admin_portal_rides(text) from public,anon;grant execute on function public.swift_admin_portal_rides(text) to authenticated;
alter function public.swift_admin_portal_extras(text) rename to swift_admin_portal_extras_internal;
revoke all on function public.swift_admin_portal_extras_internal(text) from public,anon,authenticated;
create function public.swift_admin_portal_extras(p_zone text default null) returns jsonb language sql stable security definer set search_path='' as $$select public.swift_admin_portal_extras_internal(public.swift_admin_effective_zone(p_zone))$$;
revoke all on function public.swift_admin_portal_extras(text) from public,anon;grant execute on function public.swift_admin_portal_extras(text) to authenticated;
alter function public.swift_admin_quick_store(uuid,uuid,jsonb) rename to swift_admin_quick_store_internal;
revoke all on function public.swift_admin_quick_store_internal(uuid,uuid,jsonb) from public,anon,authenticated;
create function public.swift_admin_quick_store(p_id uuid,p_user uuid,p_data jsonb) returns text language plpgsql security definer set search_path='' as $$begin perform public.swift_admin_effective_zone(p_data->>'zone_id');return public.swift_admin_quick_store_internal(p_id,p_user,p_data);end $$;
revoke all on function public.swift_admin_quick_store(uuid,uuid,jsonb) from public,anon;grant execute on function public.swift_admin_quick_store(uuid,uuid,jsonb) to authenticated;
alter function public.swift_store_publish(text,boolean) rename to swift_store_publish_internal;
revoke all on function public.swift_store_publish_internal(text,boolean) from public,anon,authenticated;
create function public.swift_store_publish(p_category text,p_live boolean) returns void language plpgsql security definer set search_path='' as $$begin perform public.swift_admin_check_store(p_category);perform public.swift_store_publish_internal(p_category,p_live);end $$;
revoke all on function public.swift_store_publish(text,boolean) from public,anon;grant execute on function public.swift_store_publish(text,boolean) to authenticated;

create function public.swift_admin_staff_account(p_email text,p_user uuid default null,p_zone text default null,p_active boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;u uuid;
begin
 a:=public.swift_admin_portal_access();if a->>'role'<>'owner' then raise exception 'Only the owner manages co-admins' using errcode='42501';end if;
 if nullif(p_email,'') is not null then
  select id into u from auth.users where lower(email)=lower(trim(p_email));if u is null then return jsonb_build_object('user_id',null);end if;
  if exists(select 1 from public.swift_admin_portal_members where user_id=u and portal_role='owner') then raise exception 'The owner cannot be modified here';end if;
  if p_user is not null then
   if p_user<>u or not exists(select 1 from auth.users where id=u and raw_app_meta_data->>'swift_staff_created_by'=auth.uid()::text) then raise exception 'Use a separate admin login email; this email belongs to an existing account';end if;
   if not exists(select 1 from public.swift_service_zones where id=p_zone) then raise exception 'Assign a service area';end if;
   insert into public.swift_admin_portal_members(user_id,portal_role,zone_id,active,added_by) values(u,'co_owner',p_zone,p_active,auth.uid()) on conflict(user_id) do update set zone_id=excluded.zone_id,active=excluded.active;
   delete from public.swift_region_staff where user_id=u;
   if p_active then insert into public.swift_region_staff(user_id,zone_id) values(u,p_zone);end if;
   update public.profiles set role='runner',active=false where id=u and role='admin';
   insert into public.swift_region_audit(actor_id,action,entity,detail) values(auth.uid(),'area_admin_access',u::text,jsonb_build_object('zone',p_zone,'active',p_active));
  end if;
  return jsonb_build_object('user_id',u,'managed',exists(select 1 from auth.users where id=u and raw_app_meta_data->>'swift_staff_created_by'=auth.uid()::text));
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('email',u.email,'role',m.portal_role,'zone_id',m.zone_id,'active',m.active) order by m.created_at) from public.swift_admin_portal_members m join auth.users u on u.id=m.user_id),'[]');
end $$;
revoke all on function public.swift_admin_staff_account(text,uuid,text,boolean) from public,anon;grant execute on function public.swift_admin_staff_account(text,uuid,text,boolean) to authenticated;
create or replace function public.swift_admin_portal_team(p_email text default null,p_enabled boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$begin if public.swift_admin_portal_access()->>'role'<>'owner' then raise exception 'Owner access required' using errcode='42501';end if;if nullif(p_email,'') is not null then raise exception 'Use the area assignment form to create co-admin access';end if;return public.swift_admin_staff_account(null);end $$;

create function public.swift_admin_workspace(p_zone text default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare z text:=public.swift_admin_effective_zone(p_zone);a jsonb:=public.swift_admin_portal_access();
begin return jsonb_build_object('access',a,'zones',(select jsonb_agg(to_jsonb(x)) from(select id,name,district_id,active,rates_approved,coverage is not null has_coverage from public.swift_service_zones where a->>'role'='owner' or id=a->>'zone_id' order by name)x),'districts',(select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.swift_districts),'stores',coalesce((select jsonb_agg(to_jsonb(x) order by name) from(select r.category,r.name,r.zone_id,r.business_type,r.status,m.phone,m.address,m.latitude,m.longitude,(select count(*) from public.products p where p.category=r.category) product_count from public.swift_store_registry r left join public.merchant_storefronts m using(category) where z is null or r.zone_id=z)x),'[]'));end $$;
revoke all on function public.swift_admin_workspace(text) from public,anon;grant execute on function public.swift_admin_workspace(text) to authenticated;
create function public.swift_admin_store_art(p_categories text[]) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare z text:=public.swift_admin_effective_zone(null);
begin if cardinality(p_categories)>8 then raise exception 'Load up to eight stores at a time';end if;return coalesce((select jsonb_object_agg(r.category,jsonb_build_object('logo',r.logo,'cover',m.cover_image)) from public.swift_store_registry r left join public.merchant_storefronts m using(category) where r.category=any(p_categories) and (z is null or r.zone_id=z)),'{}');end $$;
revoke all on function public.swift_admin_store_art(text[]) from public,anon;grant execute on function public.swift_admin_store_art(text[]) to authenticated;

create function public.swift_admin_catalogue(p_zone text default null,p_category text default null,p_query text default '',p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare z text:=public.swift_admin_effective_zone(p_zone);
begin
 if p_category is not null then perform public.swift_admin_check_store(p_category);end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.name,p.category,p.price,p.was,p.active,p.subcategory,p.description,p.tags,p.catalog_details from public.products p left join public.swift_store_registry r using(category) where (z is null or r.zone_id=z or z='orange-walk' and r.category is null) and (p_category is null or p.category=p_category) and (nullif(trim(p_query),'') is null or p.name ilike '%'||left(p_query,80)||'%') order by p.name,p.id limit 25 offset greatest(0,least(p_offset,100000)))x),'[]'),'more',(select count(*)>greatest(0,p_offset)+25 from public.products p left join public.swift_store_registry r using(category) where (z is null or r.zone_id=z or z='orange-walk' and r.category is null) and (p_category is null or p.category=p_category) and (nullif(trim(p_query),'') is null or p.name ilike '%'||left(p_query,80)||'%')));
end $$;
revoke all on function public.swift_admin_catalogue(text,text,text,integer) from public,anon;grant execute on function public.swift_admin_catalogue(text,text,text,integer) to authenticated;
create function public.swift_admin_product_save(p_id text,p_data jsonb) returns text language plpgsql security definer set search_path='' as $$
declare cat text;old_cat text;new_id text:=coalesce(nullif(p_id,''),gen_random_uuid()::text);tags text[];
begin
 cat:=p_data->>'category';perform public.swift_admin_check_store(cat);
 if p_id is not null then select category into old_cat from public.products where id=p_id for update;if not found then raise exception 'Product not found';end if;perform public.swift_admin_check_store(old_cat);end if;
 if length(trim(coalesce(p_data->>'name',''))) not between 1 and 200 or (p_data->>'price')::numeric not between 0 and 100000 then raise exception 'Enter a product name and valid price';end if;
 if octet_length(p_data::text)>1500000 then raise exception 'Choose a smaller image';end if;
 if p_data ? 'image' and coalesce(p_data->>'image','')<>'' and p_data->>'image' !~ '^(https://|data:image/(png|jpeg|webp);base64,)' then raise exception 'Use a JPG, PNG or WebP image';end if;
 select coalesce(array_agg(value),'{}') into tags from jsonb_array_elements_text(coalesce(p_data->'tags','[]'));
 insert into public.products(id,name,category,price,active,subcategory,description,tags,image,catalog_details) values(new_id,trim(p_data->>'name'),cat,(p_data->>'price')::numeric,case when p_data->>'active'='no' then 'no' else 'yes' end,coalesce(nullif(p_data->>'subcategory',''),'Items'),left(coalesce(p_data->>'description',''),10000),tags,nullif(p_data->>'image',''),coalesce(p_data->'catalog_details','{}'))
 on conflict(id) do update set name=excluded.name,category=excluded.category,price=excluded.price,active=excluded.active,subcategory=excluded.subcategory,description=excluded.description,tags=excluded.tags,image=case when p_data ? 'image' then excluded.image else products.image end,catalog_details=excluded.catalog_details;
 return new_id;
end $$;
revoke all on function public.swift_admin_product_save(text,jsonb) from public,anon;grant execute on function public.swift_admin_product_save(text,jsonb) to authenticated;

create function public.swift_admin_banner(p_action text,p_category text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;new_id uuid:=coalesce(p_id,gen_random_uuid());
begin perform public.swift_admin_check_store(p_category);
 if p_action='list' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'alt_text',alt_text,'published',published)) from public.store_paid_banners where category=p_category),'[]');
 elsif p_action='save' then
 if p_id is not null and not exists(select 1 from public.store_paid_banners where id=p_id and category=p_category) then raise exception 'Banner not found';end if;
 if p_data ? 'image_data' and (length(p_data->>'image_data')>1300000 or p_data->>'image_data' !~ '^data:image/(png|jpeg|webp);base64,') then raise exception 'Choose a smaller banner image';end if;
 if p_id is null and nullif(p_data->>'image_data','') is null then raise exception 'Upload a banner';end if;
 if p_id is null then insert into public.store_paid_banners(id,category,image_data,alt_text,published) values(new_id,p_category,p_data->>'image_data',left(coalesce(p_data->>'alt_text','Store banner'),240),coalesce((p_data->>'published')::boolean,false));
 else update public.store_paid_banners set image_data=coalesce(p_data->>'image_data',image_data),alt_text=left(coalesce(p_data->>'alt_text',alt_text),240),published=coalesce((p_data->>'published')::boolean,published) where id=p_id and category=p_category;end if;
 return jsonb_build_object('id',new_id);
 end if;raise exception 'Unknown banner action';end $$;
revoke all on function public.swift_admin_banner(text,text,uuid,jsonb) from public,anon;grant execute on function public.swift_admin_banner(text,text,uuid,jsonb) to authenticated;

create function public.swift_admin_store_details(p_category text,p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
begin perform public.swift_admin_check_store(p_category);
 update public.merchant_storefronts set phone=left(p_data->>'phone',30),address=left(p_data->>'address',300),latitude=(p_data->>'latitude')::float8,longitude=(p_data->>'longitude')::float8 where category=p_category;
end $$;
revoke all on function public.swift_admin_store_details(text,jsonb) from public,anon;grant execute on function public.swift_admin_store_details(text,jsonb) to authenticated;

create function public.swift_admin_delete_store(p_category text,p_confirm text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.swift_store_registry;result jsonb;
begin
 if public.swift_admin_portal_access()->>'role'<>'owner' then raise exception 'Only the owner can permanently delete a store' using errcode='42501';end if;
 select * into r from public.swift_store_registry where category=p_category for update;if not found then raise exception 'Store not found';end if;
 result:=jsonb_build_object('name',r.name,'products',(select count(*) from public.products where category=p_category),'banners',(select count(*) from public.store_paid_banners where category=p_category),'offers',(select count(*) from public.swift_store_offers where category=p_category),'history_preserved',true);
 if p_confirm is null then return result;end if;
 if p_confirm is distinct from r.name then raise exception 'Type the exact store name to delete it';end if;
 if exists(select 1 from public.store_live_orders where category=p_category and lower(status) not in('delivered','cancelled','completed','rejected')) or exists(select 1 from public.customer_order_tracking where phase not in('delivered','cancelled') and snapshot::text like '%'||p_category||'%') then raise exception 'Finish or cancel active orders before deleting this store';end if;
 perform pg_advisory_xact_lock(hashtextextended('delete-store:'||p_category,0));
 delete from public.product_likes where product_id in(select id from public.products where category=p_category);
 delete from public.products where category=p_category;
 delete from public.store_paid_banners where category=p_category;
 delete from public.store_paid_ads where category=p_category;
 delete from public.merchant_campaigns where category=p_category;
 delete from public.swift_store_offers where category=p_category;
 delete from public.promos where category=p_category;
 delete from public.app_promotions where category=p_category;
 delete from public.merchant_members where category=p_category;
 delete from public.swift_merchant_delivery where category=p_category;
 delete from public.merchant_storefronts where category=p_category;
 delete from public.swift_store_onboarding where category=p_category;
 delete from public.swift_store_registry where category=p_category;
 delete from public.stores where category=p_category;
 update public.swiftpay_store_providers set active=false where category=p_category;
 update public.swift_merchant_commission_accounts set active=false where category=p_category;
 insert into public.swift_region_audit(actor_id,action,entity,detail) values(auth.uid(),'store_deleted',p_category,result);
 return result||jsonb_build_object('deleted',true);
end $$;
revoke all on function public.swift_admin_delete_store(text,text) from public,anon;grant execute on function public.swift_admin_delete_store(text,text) to authenticated;

create function public.swift_admin_area_activate(p_id text,p_active boolean,p_data jsonb default '{}') returns void language plpgsql security definer set search_path='' as $$
declare z public.swift_service_zones;lat float8;lng float8;radius float8;fee integer;points jsonb:='[]';i integer;angle float8;point jsonb;
begin
 if public.swift_admin_portal_access()->>'role'<>'owner' then raise exception 'Only the owner activates service areas' using errcode='42501';end if;
 select * into z from public.swift_service_zones where id=p_id for update;if not found then raise exception 'Area not found';end if;
 if not p_active then update public.swift_service_zones set active=false,updated_at=now() where id=p_id;return;end if;
 if z.rates_approved and jsonb_array_length(z.rate_brackets)>0 and (z.coverage is not null or z.id='orange-walk') and p_data='{}' then update public.swift_service_zones set active=true,updated_at=now() where id=p_id;return;end if;
 lat:=(p_data->>'latitude')::float8;lng:=(p_data->>'longitude')::float8;radius:=(p_data->>'radius_km')::float8;fee:=(p_data->>'fee_cents')::integer;
 if lat is null or lng is null or radius is null or fee is null or radius not between 0.5 and 20 or fee not between 100 and 10000 or public.swift_district_at(lat,lng) is distinct from z.district_id then raise exception 'Choose a center in this district, a 0.5–20 km radius, and a valid delivery fee';end if;
 for i in 0..24 loop angle:=2*pi()*i/24;point:=jsonb_build_array(lng+(radius/(111.32*cos(radians(lat))))*cos(angle),lat+(radius/111.32)*sin(angle));points:=points||jsonb_build_array(point);end loop;
 points:=jsonb_set(points,array['24'],points->0);
 perform public.swift_zone_save(p_id,jsonb_build_object('type','Polygon','coordinates',jsonb_build_array(points)),jsonb_build_array(jsonb_build_object('max_km',radius*2,'fee_cents',fee)),true,true);
end $$;
revoke all on function public.swift_admin_area_activate(text,boolean,jsonb) from public,anon;grant execute on function public.swift_admin_area_activate(text,boolean,jsonb) to authenticated;
commit;

