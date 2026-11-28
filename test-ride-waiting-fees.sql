begin;
do $$
declare driver uuid;c1 uuid:=gen_random_uuid();c2 uuid:=gen_random_uuid();c3 uuid:=gen_random_uuid();r1 uuid:=gen_random_uuid();r2 uuid:=gen_random_uuid();r3 uuid:=gen_random_uuid();q1 uuid:=gen_random_uuid();q2 uuid:=gen_random_uuid();next1 uuid:=gen_random_uuid();next2 uuid:=gen_random_uuid();r jsonb;b jsonb;amount numeric;commission numeric;
begin
 select p.id into driver from public.profiles p join public.swift_worker_applications a on a.user_id=p.id where p.active and a.kind='driver' and a.status='approved' and not exists(select 1 from public.swiftride_orders o where o.driver_id=p.id and o.status in('accepted','arrived','in_progress')) limit 1;
 if driver is null then raise exception 'No idle test driver available';end if;
 insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,aud,role) select id,'qa-wait-'||id||'@example.com',now(),'{}','{}','authenticated','authenticated' from unnest(array[c1,c2,c3]) id;
 update public.swift_worker_profiles set verification_status='verified' where user_id=driver;
 insert into public.swiftride_drivers(driver_id,online,lat,lng,accuracy,updated_at) values(driver,true,18.082,-88.562,10,now()) on conflict(driver_id) do update set online=true,lat=18.082,lng=-88.562,accuracy=10,updated_at=now();
 insert into public.swiftride_orders(id,customer_id,customer_name,phone,pickup_label,dropoff_label,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng,status,driver_id)
 values(r1,c1,'QA current','0000000','QA pickup','QA dropoff',18.08,-88.56,18.081,-88.561,'in_progress',driver),(r2,c2,'QA waiting','0000000','QA pickup','QA dropoff',18.082,-88.562,18.084,-88.564,'requested',null),(r3,c3,'QA queued','0000000','QA pickup','QA dropoff',18.082,-88.562,18.084,-88.564,'requested',null);
 insert into public.swiftride_pricing_ledger(ride_id,driver_id,customer_id,standard_fare,pickup_supplement,road_miles,pickup_miles) values(r1,driver,c1,5,0,.5,.1),(r2,driver,c2,5,0,.5,.1),(r3,driver,c3,5,0,.5,.1);
 perform set_config('request.jwt.claim.sub',driver::text,true);perform public.swiftride_action_priced(r2,'accept');perform public.swiftride_action_priced(r2,'accept');
 if (select count(*) from swift_ride_private.waiting where driver_id=driver and state='waiting')<>1 then raise exception 'Duplicate queued acceptance';end if;
 begin perform public.swiftride_action_priced(r3,'accept');raise exception 'Second next ride allowed';exception when raise_exception then if sqlerrm='Second next ride allowed' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',c2::text,true);r:=public.swiftride_current_priced(r2);if not(r->>'driver_busy')::boolean or r->>'status'<>'accepted' then raise exception 'Busy notice missing';end if;
 begin perform public.swift_ride_cancel_waiting(r2,false);raise exception 'Fee disclosure bypass';exception when raise_exception then if sqlerrm='Fee disclosure bypass' then raise;end if;end;
 perform public.swift_ride_cancel_waiting(r2,true);perform public.swift_ride_cancel_waiting(r2,true);if public.swift_ride_pending_fees()<>100 then raise exception 'Cancellation fee did not tally';end if;
 b:=jsonb_build_object('p_name','QA fee rider','p_phone','0000000','p_pickup','QA pickup','p_dropoff','QA dropoff','p_pickup_lat',18.082,'p_pickup_lng',-88.562,'p_dropoff_lat',18.084,'p_dropoff_lng',-88.564);
 insert into public.swiftride_pricing_quotes(id,customer_id,driver_id,booking,road_miles,pickup_miles,standard_fare,pickup_supplement,requires_confirmation,expires_at) values(q1,c2,driver,b,.5,.1,5,0,false,now()+interval '5 minutes');
 perform public.swiftpay_book_ride(q1,next1,false,'Cash');perform public.swiftpay_book_ride(q1,next1,false,'Cash');r:=public.swiftride_pricing_for(next1);
 if (r->>'customerTotal')::numeric<>6 or (r->>'deferredCancellationFee')::numeric<>1 then raise exception 'Next fare mismatch: %',r;end if;
 perform public.swift_ride_cancel_waiting(next1,false);if public.swift_ride_pending_fees()<>100 then raise exception 'Unpaid carry-over lost';end if;
 insert into public.swiftride_pricing_quotes(id,customer_id,driver_id,booking,road_miles,pickup_miles,standard_fare,pickup_supplement,requires_confirmation,expires_at) values(q2,c2,driver,b,.5,.1,5,0,false,now()+interval '5 minutes');
 perform public.swiftpay_book_ride(q2,next2,false,'Cash');
 perform set_config('request.jwt.claim.sub',driver::text,true);perform public.swiftride_action_priced(r3,'accept');perform public.swiftride_action_priced(r1,'completed');
 if (select status from public.swiftride_orders where id=r3)<>'accepted' or (select state from swift_ride_private.waiting where ride_id=r3)<>'promoted' then raise exception 'Queued ride did not promote';end if;
 perform set_config('request.jwt.claim.sub',c3::text,true);perform public.swift_ride_cancel_waiting(r3,false);if public.swift_ride_pending_fees()<>0 then raise exception 'Fee charged after driver became free';end if;
 perform set_config('request.jwt.claim.sub',driver::text,true);perform public.swiftride_action_priced(next2,'accept');perform public.swiftride_action_priced(next2,'arrived');perform public.swiftride_action_priced(next2,'in_progress');perform public.swiftride_action_priced(next2,'completed');perform public.swiftride_action_priced(next2,'completed');
 r:=public.swiftride_pricing_for(next2);if (r->>'customerTotal')::numeric<>6 or (r->>'driverEarnings')::numeric<>4.5 or (r->>'swiftRideCommission')::numeric<>1.5 then raise exception 'SwiftShop/driver split mismatch: %',r;end if;
 select w.worker_amount,w.commission into amount,commission from public.swift_worker_payments w where w.worker_kind='driver' and w.source_id=next2::text;
 if amount<>4.5 or commission<>1.5 then raise exception 'Worker receipt mismatch: % / %',amount,commission;end if;
 perform set_config('request.jwt.claim.sub',c2::text,true);if public.swift_ride_pending_fees()<>0 then raise exception 'Fee charged twice';end if;
 if (select count(*) from swift_ride_private.cancellation_fees where customer_id=c2)<>1 then raise exception 'Duplicate fee ledger';end if;
end $$;
rollback;
select 'PASS: one queued ride, disclosure, BZ$1 idempotency, BZ$5+1 total, roll-over, promotion and BZ$4.50 driver/BZ$1.50 SwiftShop split' result;

