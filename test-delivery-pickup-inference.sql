begin;do $$declare o public.orders;q jsonb;t uuid:=gen_random_uuid();run_id text:='qa-motion-'||gen_random_uuid()::text;begin
perform set_config('request.jwt.claim.sub',(select id::text from auth.users where lower(email)='dancu1213t@gmail.com'),true);
select * into o from public.orders where status='Delivered' and customer_tracking_id is not null and assigned_runner_id in(select id from public.profiles where role='runner' and active) limit 1;if o.order_id is null then raise exception 'No test runner fixture';end if;
insert into public.customer_order_tracking(id,access_token,snapshot,phase,zone_id) values(t,gen_random_uuid(),'{"pickup_service":true,"pickup_location":"18.08,-88.56","customer_location":"18.10,-88.56","items":[]}', 'finding_runner','orange-walk');
insert into public.orders select (jsonb_populate_record(null::public.orders,to_jsonb(o)||jsonb_build_object('order_id',run_id,'dispatch_request_id',gen_random_uuid(),'order_type','QA delivery motion','status','Claimed','customer_tracking_id',t,'pickup_location','18.08,-88.56','dropoff_location','18.10,-88.56','run_stops','[{"location":"18.08,-88.56"},{"location":"18.10,-88.56"}]'::jsonb,'next_stop',0,'runner_completed_at',null))).*;
perform set_config('request.jwt.claim.sub',o.assigned_runner_id::text,true);
perform public.swift_runner_delivery_position(run_id,18.08,-88.56,10,now()-interval '2 seconds');q:=swift_tracking_private.progress(t);if (q->>'active')::boolean then raise exception 'Activated at pickup without departing';end if;
perform public.swift_runner_delivery_position(run_id,18.09,-88.56,10,now());q:=swift_tracking_private.progress(t);
if not (q->>'active')::boolean or not (q->>'pickup_inferred')::boolean or (q->>'progress')::int not between 45 and 55 then raise exception 'Forgotten pickup inference failed: %',q;end if;
begin perform public.swift_runner_delivery_position(run_id,18.09,-88.56,250,now());raise exception 'Inaccurate GPS accepted';exception when raise_exception then if sqlerrm='Inaccurate GPS accepted' then raise;end if;end;
end $$;rollback;select 'PASS: opted-in assigned-run GPS, pickup proximity then departure, halfway catch-up, inaccurate GPS rejection' result;

