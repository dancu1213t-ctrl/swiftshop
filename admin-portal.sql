begin;
create table public.swift_admin_portal_members (
 user_id uuid primary key references auth.users(id) on delete cascade,
 portal_role text not null check(portal_role in ('owner','co_owner')),
 active boolean not null default true,
 previous_role text,
 added_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
alter table public.swift_admin_portal_members enable row level security;
revoke all on public.swift_admin_portal_members from anon,authenticated;
insert into public.swift_admin_portal_members(user_id,portal_role,previous_role)
select u.id,'owner',p.role from auth.users u join public.profiles p on p.id=u.id
where lower(u.email)='dancu1213t@gmail.com' and u.email_confirmed_at is not null and p.role='admin' and p.active;

create function public.swift_admin_portal_access() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m public.swift_admin_portal_members; email text;
begin
 select a.* into m from public.swift_admin_portal_members a join public.profiles p on p.id=a.user_id and p.active and p.role='admin' where a.user_id=auth.uid() and a.active;
 if not found then raise exception 'This account has no admin portal access' using errcode='42501';end if;
 select u.email into email from auth.users u where u.id=m.user_id and u.email_confirmed_at is not null;
 if email is null then raise exception 'Verified administrator sign-in required' using errcode='42501';end if;
 return jsonb_build_object('role',m.portal_role,'email',email);
end $$;
revoke all on function public.swift_admin_portal_access() from public,anon;
grant execute on function public.swift_admin_portal_access() to authenticated;

create function public.swift_admin_portal_team(p_email text default null,p_enabled boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; u uuid;old_role text;
begin
 a:=public.swift_admin_portal_access();
 if a->>'role'<>'owner' then raise exception 'Only the owner can assign co-owners' using errcode='42501';end if;
 if nullif(trim(p_email),'') is not null then
  select id into u from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null;
  if u is null then raise exception 'Ask this person to create and verify their SwiftShop account first';end if;
  if exists(select 1 from public.swift_admin_portal_members where user_id=u and portal_role='owner') then raise exception 'The owner account cannot be changed here';end if;
  if p_enabled then
   select role into old_role from public.profiles where id=u;
   insert into public.swift_admin_portal_members(user_id,portal_role,previous_role,added_by) values(u,'co_owner',old_role,auth.uid()) on conflict(user_id) do update set active=true,added_by=auth.uid();
   insert into public.profiles(id,display_name,role,active) select u,coalesce(nullif(raw_user_meta_data->>'display_name',''),split_part(email,'@',1)),'admin',true from auth.users where id=u on conflict(id) do update set role='admin',active=true;
  else
   update public.swift_admin_portal_members set active=false where user_id=u and portal_role='co_owner';
   if found then update public.profiles set role=coalesce((select previous_role from public.swift_admin_portal_members where user_id=u),'runner'),active=case when (select previous_role from public.swift_admin_portal_members where user_id=u) is null then false else active end where id=u;end if;
  end if;
  insert into public.swift_region_audit(actor_id,action,entity,detail) values(auth.uid(),'portal_co_owner',u::text,jsonb_build_object('enabled',p_enabled));
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('email',u.email,'role',m.portal_role,'active',m.active,'created_at',m.created_at) order by m.created_at) from public.swift_admin_portal_members m join auth.users u on u.id=m.user_id),'[]');
end $$;
revoke all on function public.swift_admin_portal_team(text,boolean) from public,anon;
grant execute on function public.swift_admin_portal_team(text,boolean) to authenticated;

create function public.swift_admin_quick_lookup(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform public.swift_admin_portal_access();
 return jsonb_build_object('category',(select category from public.swift_store_onboarding where request_id=p_id),'user_id',(select id from auth.users where raw_app_meta_data->>'swift_admin_store_request'=p_id::text and raw_app_meta_data->>'swift_admin_created_by'=auth.uid()::text limit 1));
end $$;
revoke all on function public.swift_admin_quick_lookup(uuid) from public,anon;
grant execute on function public.swift_admin_quick_lookup(uuid) to authenticated;

create function public.swift_admin_quick_store(p_id uuid,p_user uuid,p_data jsonb) returns text language plpgsql security definer set search_path='' as $$
declare cat text;z text;login text;store_name text;
begin
 perform public.swift_admin_portal_access();
 if p_id is null or p_user is null then raise exception 'Store request is missing';end if;
 perform pg_advisory_xact_lock(hashtextextended('quick-store:'||p_id::text,0));
 select o.category into cat from public.swift_store_onboarding o join public.swift_store_registry r using(category) where request_id=p_id and r.created_by=auth.uid();
 if found then return cat;end if;
 select email into login from auth.users where id=p_user and raw_app_meta_data->>'swift_admin_store_request'=p_id::text and raw_app_meta_data->>'swift_admin_created_by'=auth.uid()::text;
 if login is null then raise exception 'Merchant login was not created by this administrator';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>1600000 then raise exception 'Store details are too large';end if;
 store_name:=trim(p_data->>'name');z:=p_data->>'zone_id';
 if length(coalesce(store_name,'')) not between 2 and 120 then raise exception 'Enter a store name';end if;
 if not exists(select 1 from public.swift_service_zones where id=z) then raise exception 'Choose a service area';end if;
 if coalesce(p_data->>'business_type','') not in('Food','Cafes','Pharmacy','Groceries','Shops','Apparel','Tech') then raise exception 'Choose a business category';end if;
 if length(coalesce(p_data->>'logo','')) not between 40 and 200000 or p_data->>'logo' !~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$' then raise exception 'Upload a profile image';end if;
 if length(coalesce(p_data->>'cover_image','')) not between 40 and 1300000 or p_data->>'cover_image' !~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$' then raise exception 'Upload a cover image';end if;
 perform pg_advisory_xact_lock(hashtextextended('store-name:'||z||':'||lower(store_name),0));
 if exists(select 1 from public.swift_store_registry r where r.zone_id=z and lower(trim(r.name))=lower(store_name)) then raise exception 'A store with this name already exists in this area';end if;
 cat:='store_'||replace(p_id::text,'-','');
 insert into public.stores(category,is_open) values(cat,'yes');
 insert into public.swift_store_registry(category,name,business_type,logo,zone_id,status,created_by) values(cat,store_name,p_data->>'business_type',p_data->>'logo',z,'live',auth.uid());
 insert into public.swift_store_onboarding(request_id,category,owner_email,claimed_by,claimed_at,request_data) values(p_id,cat,login,p_user,now(),p_data);
 insert into public.merchant_members(user_id,category) values(p_user,cat);
 insert into public.merchant_storefronts(category,cover_image,auto_close) values(cat,p_data->>'cover_image',false);
 insert into public.swift_merchant_commission_accounts(category,active) values(cat,false) on conflict do nothing;
 insert into public.swift_region_audit(actor_id,action,entity,detail) values(auth.uid(),'admin_store_published',cat,jsonb_build_object('zone_id',z,'merchant_user',p_user));
 return cat;
end $$;
revoke all on function public.swift_admin_quick_store(uuid,uuid,jsonb) from public,anon;
grant execute on function public.swift_admin_quick_store(uuid,uuid,jsonb) to authenticated;

create function public.swift_admin_portal_snapshot(p_zone text default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform public.swift_admin_portal_access();
 if p_zone is not null and not exists(select 1 from public.swift_service_zones where id=p_zone) then raise exception 'Choose a service area';end if;
 return jsonb_build_object('updated_at',now(),'orders',coalesce((select jsonb_agg(to_jsonb(x) order by created_at desc) from (select r.id,r.phase,r.zone_id,r.created_at,r.updated_at,r.linked_order_id,r.runner_id,p.display_name runner_name,r.snapshot from public.customer_order_tracking r left join public.profiles p on p.id=r.runner_id where (p_zone is null or r.zone_id=p_zone) and (r.created_at>now()-interval '30 days' or r.phase not in('delivered','cancelled')) order by r.created_at desc limit 200)x),'[]'),'runs',coalesce((select jsonb_agg(to_jsonb(x)) from (select o.order_id,o.customer_name,o.status,o.run_kind,o.zone_id,o.assigned_runner_id,p.display_name runner_name,o.timestamp,o.customer_tracking_id,o.customer_total from public.orders o left join public.profiles p on p.id=o.assigned_runner_id where (p_zone is null or o.zone_id=p_zone) and o.status not in('Delivered','Cancelled') order by o.timestamp desc limit 200)x),'[]'));
end $$;
revoke all on function public.swift_admin_portal_snapshot(text) from public,anon;
grant execute on function public.swift_admin_portal_snapshot(text) to authenticated;
create function public.swift_admin_portal_extras(p_zone text default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform public.swift_admin_portal_access();
 return jsonb_build_object('covers',coalesce((select jsonb_object_agg(m.category,m.cover_image) from public.merchant_storefronts m join public.swift_store_registry r using(category) where p_zone is null or r.zone_id=p_zone),'{}'),'rides',coalesce((select jsonb_agg(to_jsonb(x)) from (select id,customer_name,status,zone_id,driver_id,created_at,pickup_label,dropoff_label,total_fare from public.swiftride_orders where (p_zone is null or zone_id=p_zone) and created_at>now()-interval '30 days' order by created_at desc limit 100)x),'[]'));
end $$;
revoke all on function public.swift_admin_portal_extras(text) from public,anon;
grant execute on function public.swift_admin_portal_extras(text) to authenticated;

create or replace function public.swift_store_publish(p_category text,p_live boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.swift_admin_portal_access();
 update public.swift_store_registry set status=case when p_live then 'live' else 'paused' end,updated_at=now() where category=p_category;
 if not found then raise exception 'Store not found';end if;
 update public.stores set is_open=case when p_live then 'yes' else 'no' end where category=p_category;
 insert into public.swift_region_audit(actor_id,action,entity,detail) values(auth.uid(),'store_publication',p_category,jsonb_build_object('live',p_live));
end $$;
create or replace function public.swift_admin_session() returns boolean language plpgsql stable security definer set search_path='' as $$
begin perform public.swift_admin_portal_access();return true;end $$;
commit;

