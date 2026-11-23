alter table public.swift_admin_portal_members add column if not exists previous_active boolean not null default false;
update public.swift_admin_portal_members set previous_active=true where portal_role='owner';
create or replace function public.swift_admin_portal_team(p_email text default null,p_enabled boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; u uuid;old_role text;old_active boolean;
begin
 a:=public.swift_admin_portal_access();
 if a->>'role'<>'owner' then raise exception 'Only the owner can assign co-owners' using errcode='42501';end if;
 if nullif(trim(p_email),'') is not null then
  select id into u from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null;
  if u is null then raise exception 'Ask this person to create and verify their SwiftShop account first';end if;
  if exists(select 1 from public.swift_admin_portal_members where user_id=u and portal_role='owner') then raise exception 'The owner account cannot be changed here';end if;
  if p_enabled then
   select role,active into old_role,old_active from public.profiles where id=u;
   insert into public.swift_admin_portal_members(user_id,portal_role,previous_role,previous_active,added_by) values(u,'co_owner',old_role,coalesce(old_active,false),auth.uid()) on conflict(user_id) do update set active=true,added_by=auth.uid();
   insert into public.profiles(id,display_name,role,active) select u,coalesce(nullif(raw_user_meta_data->>'display_name',''),split_part(email,'@',1)),'admin',true from auth.users where id=u on conflict(id) do update set role='admin',active=true;
  else
   update public.swift_admin_portal_members set active=false where user_id=u and portal_role='co_owner';
   if found then update public.profiles set role=coalesce((select previous_role from public.swift_admin_portal_members where user_id=u),'runner'),active=(select previous_active from public.swift_admin_portal_members where user_id=u) where id=u;end if;
  end if;
  insert into public.swift_region_audit(actor_id,action,entity,detail) values(auth.uid(),'portal_co_owner',u::text,jsonb_build_object('enabled',p_enabled));
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('email',u.email,'role',m.portal_role,'active',m.active,'created_at',m.created_at) order by m.created_at) from public.swift_admin_portal_members m join auth.users u on u.id=m.user_id),'[]');
end $$;
create or replace function public.swift_admin_portal_rides(p_zone text default null) returns jsonb language plpgsql stable security definer set search_path='' as $$begin perform public.swift_admin_portal_access(); return coalesce((select jsonb_agg(to_jsonb(x)) from (select id,customer_name,status,zone_id,driver_id,created_at,pickup_label,dropoff_label,total_fare from public.swiftride_orders where (p_zone is null or zone_id=p_zone) and (created_at>now()-interval '30 days' or status not in('completed','cancelled')) order by created_at desc limit 100)x),'[]');end $$;
revoke all on function public.swift_admin_portal_rides(text) from public,anon;
grant execute on function public.swift_admin_portal_rides(text) to authenticated;


create or replace function public.swift_admin_quick_lookup(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin perform public.swift_admin_portal_access();return jsonb_build_object('category',(select o.category from public.swift_store_onboarding o join public.swift_store_registry r using(category) where o.request_id=p_id and r.created_by=auth.uid()),'user_id',(select id from auth.users where raw_app_meta_data->>'swift_admin_store_request'=p_id::text and raw_app_meta_data->>'swift_admin_created_by'=auth.uid()::text limit 1),'email',(select email from auth.users where raw_app_meta_data->>'swift_admin_store_request'=p_id::text and raw_app_meta_data->>'swift_admin_created_by'=auth.uid()::text limit 1));end $$;
