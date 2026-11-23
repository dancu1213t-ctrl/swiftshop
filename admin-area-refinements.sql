CREATE OR REPLACE FUNCTION public.swift_admin_area_create(p_name text, p_district text, p_data jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare id text;begin if public.swift_admin_portal_access()->>'role'<>'owner' then raise exception 'Owner access required' using errcode='42501';end if;if length(trim(coalesce(p_name,''))) not between 2 and 80 or not exists(select 1 from public.swift_districts where public.swift_districts.id=p_district) then raise exception 'Enter an area name and district';end if;if exists(select 1 from public.swift_service_zones where district_id=p_district and lower(name)=lower(trim(p_name))) then raise exception 'This service area already exists';end if;id:='area_'||replace(gen_random_uuid()::text,'-','');insert into public.swift_service_zones(id,name,district_id) values(id,trim(p_name),p_district);perform public.swift_admin_area_activate(id,true,p_data);return id;end $function$

CREATE OR REPLACE FUNCTION public.swift_admin_can_store(p_category text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$select exists(select 1 from public.swift_admin_portal_members m join public.swift_store_registry r on r.category=p_category where m.user_id=auth.uid() and m.active and (m.portal_role='owner' or m.zone_id=r.zone_id))$function$

CREATE OR REPLACE FUNCTION public.swift_admin_check_store(p_category text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$declare z text;allowed text;begin allowed:=public.swift_admin_effective_zone(null);select zone_id into z from public.swift_store_registry where category=p_category;if not found then if p_category=any(array['Snack','Drink','Household','Hygiene','Vegetables','Treats']) and exists(select 1 from public.stores where category=p_category) then z:='orange-walk';else raise exception 'Store not found';end if;end if;if allowed is not null and z<>allowed then raise exception 'Store access is outside your assigned area' using errcode='42501';end if;end $function$

CREATE OR REPLACE FUNCTION public.swift_admin_product_image(p_id text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$declare cat text;im text;begin select category,image into cat,im from public.products where id=p_id;if not found then return null;end if;perform public.swift_admin_check_store(cat);return im;end $function$

CREATE OR REPLACE FUNCTION public.swift_admin_staff_account(p_email text, p_user uuid DEFAULT NULL::uuid, p_zone text DEFAULT NULL::text, p_active boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
   update public.profiles set role='runner',active=false where id=u;
   insert into public.swift_region_audit(actor_id,action,entity,detail) values(auth.uid(),'area_admin_access',u::text,jsonb_build_object('zone',p_zone,'active',p_active));
  end if;
  return jsonb_build_object('user_id',u,'managed',exists(select 1 from auth.users where id=u and raw_app_meta_data->>'swift_staff_created_by'=auth.uid()::text));
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('email',u.email,'role',m.portal_role,'zone_id',m.zone_id,'active',m.active) order by m.created_at) from public.swift_admin_portal_members m join auth.users u on u.id=m.user_id),'[]');
end $function$

CREATE OR REPLACE FUNCTION public.swift_storefront_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$begin
if tg_op='UPDATE' and new.category is distinct from old.category and auth.uid() is not null and public.swift_worker_kind() is distinct from 'admin' then raise exception 'Only administrators can change a store identifier' using errcode='42501';end if;
if (tg_op='INSERT' and (new.latitude is not null or new.longitude is not null)) or (tg_op='UPDATE' and (new.latitude is distinct from old.latitude or new.longitude is distinct from old.longitude)) then
if auth.uid() is not null and public.swift_worker_kind() is distinct from 'admin' and not public.swift_admin_can_store(new.category) and not (new.category=coalesce(current_setting('swiftshop.onboarding',true),'') and exists(select 1 from public.swift_store_registry where category=new.category and created_by=auth.uid() and status='draft')) then raise exception 'Store coordinate access required' using errcode='42501';end if;end if;
if (new.opens_at is null)<>(new.closes_at is null) or (new.opens_at is not null and new.opens_at=new.closes_at) then raise exception 'Set different opening and closing times, or clear both';end if;return new;end $function$

revoke all on function public.swift_admin_can_store(text),public.swift_admin_product_image(text),public.swift_admin_area_create(text,text,jsonb) from public,anon; grant execute on function public.swift_admin_can_store(text),public.swift_admin_product_image(text),public.swift_admin_area_create(text,text,jsonb) to authenticated;

