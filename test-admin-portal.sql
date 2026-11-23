begin;
-- All fixtures and permission changes are rolled back.
do $$
declare owner_id uuid; merchant_id uuid:=gen_random_uuid(); coworker_id uuid:=gen_random_uuid(); request_id uuid:=gen_random_uuid(); v_category text; again text; result jsonb;
begin
 select id into owner_id from auth.users where lower(email)='dancu1213t@gmail.com';
 if owner_id is null then raise exception 'Owner fixture is missing';end if;
 insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,aud,role) values
 (merchant_id,'qa-merchant-'||merchant_id||'@stores.swiftshopow.com',now(),jsonb_build_object('swift_admin_store_request',request_id,'swift_admin_created_by',owner_id),'{}','authenticated','authenticated'),
 (coworker_id,'qa-coworker-'||coworker_id||'@example.com',now(),'{}','{}','authenticated','authenticated');
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 if public.swift_admin_portal_access()->>'role'<>'owner' then raise exception 'Owner access failed';end if;
 v_category:=public.swift_admin_quick_store(request_id,merchant_id,jsonb_build_object('name','QA Rollback '||request_id,'business_type','Cafes','zone_id','orange-walk','logo','data:image/webp;base64,'||repeat('A',40),'cover_image','data:image/webp;base64,'||repeat('A',40)));
 if not exists(select 1 from public.swift_store_registry where public.swift_store_registry.category=v_category and status='live') then raise exception 'Store did not publish immediately';end if;
 if not exists(select 1 from public.merchant_members mm where mm.category=v_category and user_id=merchant_id) then raise exception 'Merchant access missing';end if;
 if not exists(select 1 from public.merchant_storefronts m where m.category=v_category and latitude is null and longitude is null) then raise exception 'Optional pickup pin failed';end if;
 again:=public.swift_admin_quick_store(request_id,merchant_id,'{}');
 if again<>v_category then raise exception 'Idempotent retry failed';end if;
 update public.merchant_storefronts set auto_close=true,weekly_hours=(select jsonb_object_agg(i::text,jsonb_build_object('closed',true)) from generate_series(1,7)i) where public.merchant_storefronts.category=v_category;
 perform public.swift_store_publish(v_category,true);
 if not exists(select 1 from public.stores s join public.swift_store_registry r using(category) where s.category=v_category and r.status='live' and s.is_open='no' and s.hours_auto_closed) then raise exception 'Closed-hours publication must stay live but closed';end if;
 perform public.swift_store_publish(v_category,false);perform public.swift_store_auto_close();
 if exists(select 1 from public.stores s where s.category=v_category and (s.is_open='yes' or s.hours_auto_closed)) then raise exception 'Paused store must not automatically reopen';end if;
 update public.merchant_storefronts set auto_close=false where public.merchant_storefronts.category=v_category;
 perform public.swift_store_publish(v_category,true);
 if not exists(select 1 from public.stores s where s.category=v_category and s.is_open='yes') then raise exception 'Unscheduled store should open when published';end if;
 result:=public.swift_admin_portal_snapshot('orange-walk');
 if jsonb_typeof(result->'orders')<>'array' then raise exception 'Tracking shape invalid';end if;
 perform public.swift_admin_portal_extras('orange-walk');
 perform public.swift_admin_portal_team('qa-coworker-'||coworker_id||'@example.com',true);
 perform set_config('request.jwt.claim.sub',coworker_id::text,true);
 if public.swift_admin_portal_access()->>'role'<>'co_owner' then raise exception 'Co-owner access failed';end if;
 begin perform public.swift_admin_portal_team();raise exception 'Co-owner incorrectly permitted to manage team';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 perform public.swift_admin_portal_team('qa-coworker-'||coworker_id||'@example.com',false);
 perform set_config('request.jwt.claim.sub',coworker_id::text,true);
 begin perform public.swift_admin_portal_access();raise exception 'Removed co-owner retained access';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',merchant_id::text,true);
 begin perform public.swift_admin_portal_snapshot();raise exception 'Merchant incorrectly granted admin data';exception when insufficient_privilege then null;end;
 begin perform public.swift_store_publish(v_category,true);raise exception 'Merchant incorrectly granted direct publishing';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.swift_admin_portal_access();raise exception 'Anonymous account incorrectly granted access';exception when insufficient_privilege then null;end;
end $$;
set local role authenticated;
do $$begin
 begin perform public.swift_admin_portal_snapshot();raise exception 'Authenticated customer incorrectly granted access';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: direct publication, merchant linking, optional pickup pin, retries, tracking, co-owner assignment/revocation, owner-only access management, non-admin and anonymous denial' as result;
rollback;

