begin;
-- All fixtures in this file must roll back with the migration dry-run.
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values('00000000-0000-4000-8000-00000000da01','region-owner-a@example.invalid',now(),false),('00000000-0000-4000-8000-00000000da02','region-owner-b@example.invalid',now(),false);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000da01',true),set_config('request.jwt.claim.role','authenticated',true);
do $$declare d jsonb;c text;c2 text;begin
 if public.swift_district_at(18.0843,-88.5646)<>'BZ-OW' or public.swift_district_at(17.504,-88.196)<>'BZ-BZ' then raise exception 'FAIL district boundary';end if;
 if public.swift_zone_at(17.504,-88.196) is not null then raise exception 'FAIL City active';end if;
 d:=jsonb_build_object('name','Rollback Region Store','business_type','Food','logo','data:image/png;base64,'||repeat('A',64),'owner_email','region-owner-a@example.invalid','phone','5016000000','address','Rollback-only address','zone_id','orange-walk','latitude',18.0843,'longitude',-88.5646);
 c:=public.swift_store_register('00000000-0000-4000-8000-00000000da11',d);c2:=public.swift_store_register('00000000-0000-4000-8000-00000000da11',d);
 if c<>c2 or(select count(*) from public.swift_store_onboarding where request_id='00000000-0000-4000-8000-00000000da11')<>1 then raise exception 'FAIL duplicate registration';end if;
 if exists(select 1 from jsonb_array_elements(public.swift_region_catalogue()->'stores') s where s->>'category'=c) then raise exception 'FAIL public draft exposure';end if;
 if(select active from public.swift_merchant_commission_accounts where category=c) then raise exception 'FAIL commission activated';end if;
 perform public.swift_store_claim();
 if not exists(select 1 from public.merchant_members where category=c and user_id=auth.uid()) then raise exception 'FAIL owner claim';end if;
 begin perform public.swift_store_register('00000000-0000-4000-8000-00000000da11',d||jsonb_build_object('name','Changed'));raise exception 'FAIL changed retry';exception when others then if sqlerrm='FAIL changed retry' then raise;end if;end;
 begin perform public.swift_store_publish(c,true);raise exception 'FAIL owner published';exception when others then if sqlerrm='FAIL owner published' then raise;end if;end;
 begin perform public.swift_store_register(gen_random_uuid(),d||jsonb_build_object('name','Wrong district','latitude',17.504,'longitude',-88.196));raise exception 'FAIL wrong district';exception when others then if sqlerrm='FAIL wrong district' then raise;end if;end;
 begin perform public.swift_store_register(gen_random_uuid(),d||jsonb_build_object('owner_email','another-owner@example.invalid'));raise exception 'FAIL impersonated owner';exception when others then if sqlerrm='FAIL impersonated owner' then raise;end if;end;
 if has_table_privilege('authenticated','public.swift_store_onboarding','SELECT') or has_table_privilege('authenticated','public.swift_region_staff','INSERT') then raise exception 'FAIL raw private access';end if;
 if has_function_privilege('anon','public.swift_store_register(uuid,jsonb)','EXECUTE') then raise exception 'FAIL anonymous registration';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000da02',true);
do $$begin
 if jsonb_array_length(public.swift_store_claim())<>0 then raise exception 'FAIL another owner claimed';end if;
 if jsonb_array_length(public.swift_region_context()->'stores')<>0 then raise exception 'FAIL private store access';end if;
 if public.swift_worker_zone(auth.uid(),'orange-walk') then raise exception 'FAIL customer is runner';end if;
end$$;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where role='admin' and active limit 1),true);
do $$declare polygon jsonb:='{"type":"Polygon","coordinates":[[[-88.24,17.46],[-88.16,17.46],[-88.16,17.55],[-88.24,17.55],[-88.24,17.46]]]}';begin
 if not public.swift_region_admin() then raise exception 'FAIL no admin test context';end if;
 begin perform public.swift_zone_save('belize-city',polygon,'[{"max_km":10,"fee_cents":1000}]',true,true);raise exception 'FAIL excessive City fee';exception when others then if sqlerrm='FAIL excessive City fee' then raise;end if;end;
 begin perform public.swift_zone_save('belize-city',polygon,'[{"max_km":10,"fee_cents":500}]',false,true);raise exception 'FAIL unapproved activation';exception when others then if sqlerrm='FAIL unapproved activation' then raise;end if;end;
 perform public.swift_zone_save('belize-city',polygon,'[{"max_km":2,"fee_cents":500},{"max_km":10,"fee_cents":900}]',false,false);
 if public.swift_zone_at(17.504,-88.196) is not null then raise exception 'FAIL inactive coverage accepted';end if;
 if(select active from public.swift_service_zones where id='orange-walk') is not true then raise exception 'FAIL Orange Walk changed';end if;
end$$;
select 'PASS: registration retry safety, verified owner assignment, private access, draft visibility, district pins, inactive City and fee limits. All fixtures rolled back.' result;

-- Additional rollout checks. All changes are inside the surrounding rollback transaction.
do $$declare c text;d jsonb;q jsonb;polygon jsonb:='{"type":"Polygon","coordinates":[[[-88.24,17.46],[-88.16,17.46],[-88.16,17.55],[-88.24,17.55],[-88.24,17.46]]]}';begin
 select category into c from public.swift_store_onboarding where request_id='00000000-0000-4000-8000-00000000da11';
 insert into public.products(id,name,category,price,active) values('region-rollback-item','Rollback item',c,10,'yes');
 perform public.swift_store_publish(c,true);
 if not exists(select 1 from jsonb_array_elements(public.swift_region_catalogue()->'stores') s where s->>'category'=c) then raise exception 'FAIL published store missing';end if;
 q:=public.swift_region_quote(jsonb_build_array(jsonb_build_object('category',c)),'18.0844,-88.5647');
 if(q->>'fee_cents')::int<>350 or q->>'zone_id'<>'orange-walk' then raise exception 'FAIL Orange Walk quote';end if;
 perform public.swift_zone_save('belize-city',polygon,'[{"max_km":2,"fee_cents":500},{"max_km":10,"fee_cents":900}]',true,true);
 if public.swift_zone_at(17.504,-88.196) is distinct from 'belize-city' then raise exception 'FAIL approved coverage';end if;
 if public.swift_region_dispatch_quote('belize-city','[{"location":"17.504,-88.196"},{"location":"17.505,-88.197"}]')<>5 then raise exception 'FAIL City short fee';end if;
 if public.swift_region_dispatch_quote('belize-city','[{"location":"17.504,-88.196"},{"location":"17.5,-88.235"}]')<>9 then raise exception 'FAIL City long fee';end if;
 begin perform public.swift_region_dispatch_quote('belize-city','[{"location":"17.504,-88.196"},{"location":"18.0844,-88.5647"}]');raise exception 'FAIL cross-zone dispatch';exception when others then if sqlerrm='FAIL cross-zone dispatch' then raise;end if;end;
 insert into public.swift_worker_zones values('00000000-0000-4000-8000-00000000da02','belize-city');
 if not public.swift_worker_zone('00000000-0000-4000-8000-00000000da02','belize-city') or public.swift_worker_zone('00000000-0000-4000-8000-00000000da02','orange-walk') then raise exception 'FAIL worker isolation';end if;
 perform public.swift_store_publish(c,false);
 if exists(select 1 from jsonb_array_elements(public.swift_region_catalogue()->'stores') s where s->>'category'=c) then raise exception 'FAIL paused store exposed';end if;
end$$;
select 'PASS: publication, pause, Orange Walk pricing, City approved-distance pricing, cross-zone dispatch and worker isolation. All changes rolled back.' result;



rollback;
