begin;
create temporary table swift_offer_pickup_test(snapshot jsonb) on commit drop;
alter table swift_offer_pickup_test enable row level security;
create trigger test_pickup before insert on swift_offer_pickup_test for each row execute function public.swift_order_offer_pickups();
do $$
declare offer_id uuid:=gen_random_uuid(); result jsonb; denied boolean:=false; invalid boolean:=false;stale boolean:=false;
begin
 insert into public.swift_store_offers(id,category,title,description,image_url,tags,published,starts_at,created_by,order_config,pickup_name,pickup_lat,pickup_lng)
 values(offer_id,'Aroma','Rollback-only pickup test','','https://example.invalid/offer-test.png','{}',false,now(),(select id from auth.users limit 1),'{"enabled":false,"options":[],"groups":[]}', 'Test entrance',18.08125,-88.56688);
 insert into swift_offer_pickup_test values(jsonb_build_object('items',jsonb_build_array(jsonb_build_object('offer_id',offer_id,'category','Aroma','offer_pickup',jsonb_build_object('lat',0,'lng',0))),'customer_location','18.09,-88.56')) returning snapshot into result;
 if (result#>>'{items,0,offer_pickup,lat}')::numeric<>18.08125 or (result#>>'{offer_pickups,0,lng}')::numeric<>-88.56688 or strpos(result#>>'{routes,0}','origin=18.08125,-88.56688')=0 then raise exception 'Canonical pickup test failed';end if;
 insert into swift_offer_pickup_test values(jsonb_build_object('items',jsonb_build_array(jsonb_build_object('offer_id',offer_id,'category','Aroma'),jsonb_build_object('category','Snack')),'customer_location','18.09,-88.56','routes',jsonb_build_array('https://www.google.com/maps/dir/?api=1&origin=18.08125,-88.56688&destination=18.09%2C-88.56')));
 begin insert into swift_offer_pickup_test values(jsonb_build_object('items',jsonb_build_array(jsonb_build_object('offer_id',offer_id,'category','Aroma'),jsonb_build_object('category','Snack')),'customer_location','18.09,-88.56','routes','[]'::jsonb));exception when raise_exception then stale:=true;end;
 if not stale then raise exception 'Stale mixed-cart pickup was accepted';end if;
 begin update public.swift_store_offers set pickup_lat=91 where id=offer_id;exception when check_violation then invalid:=true;end;
 if not invalid then raise exception 'Out-of-range location was accepted';end if;
 begin update public.swift_store_offers set is_general=true,category='Snack' where id=offer_id;exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Non-admin General offer mutation was accepted';end if;
 if has_table_privilege('anon','public.swift_offer_tabs','INSERT') then raise exception 'Anonymous tab writes are allowed';end if;
end $$;
select 'PASS: canonical pickup routes, coordinate validation, General admin guard and tab permissions. All temporary data rolled back.' as checks;
rollback;
