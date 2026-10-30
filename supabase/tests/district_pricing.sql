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


