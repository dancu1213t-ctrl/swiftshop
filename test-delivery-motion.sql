begin;
do $$declare t public.customer_order_tracking;q jsonb;points jsonb;a float8[];b float8[];
begin
select * into t from public.customer_order_tracking where swift_tracking_private.endpoints(id)->'pickup'->>0 is not null and swift_tracking_private.endpoints(id)->'dropoff'->>0 is not null and linked_order_id in(select order_id from public.orders where coalesce(jsonb_array_length(run_stops),0)<=2) limit 1;
if t.id is null then raise exception 'No route fixture';end if;
update public.customer_order_tracking set phase='runner_assigned' where id=t.id;
delete from swift_tracking_private.motion where order_id=t.id;
q:=swift_tracking_private.progress(t.id);if (q->>'active')::boolean then raise exception 'Started before pickup';end if;
update public.customer_order_tracking set phase='on_the_way' where id=t.id;
q:=swift_tracking_private.progress(t.id);if not (q->>'active')::boolean or q->>'mode'<>'time_estimate' then raise exception 'Time estimate unavailable: %',q;end if;
points:=swift_tracking_private.endpoints(t.id);a:=array[(points->'pickup'->>0)::float8,(points->'pickup'->>1)::float8];b:=array[(points->'dropoff'->>0)::float8,(points->'dropoff'->>1)::float8];
insert into swift_tracking_private.motion(order_id,runner_id,lat,lng,observed_at) values(t.id,t.runner_id,(a[1]+b[1])/2,(a[2]+b[2])/2,now());
q:=swift_tracking_private.progress(t.id);if q->>'mode'<>'gps_estimate' or (q->>'progress')::int not between 45 and 55 then raise exception 'Halfway GPS mismatch: %',q;end if;
update swift_tracking_private.motion set observed_at=now()-interval '2 minutes' where order_id=t.id;q:=swift_tracking_private.progress(t.id);if q->>'mode'<>'time_estimate' then raise exception 'Stale GPS exposed';end if;
update public.customer_order_tracking set phase='delivered' where id=t.id;q:=swift_tracking_private.progress(t.id);if (q->>'active')::boolean then raise exception 'Progress continued after completion';end if;
begin perform public.get_customer_tracking(t.id,gen_random_uuid());raise exception 'Token bypass';exception when raise_exception then if sqlerrm='Token bypass' then raise;end if;end;
perform set_config('request.jwt.claim.sub','',true);begin perform public.swift_runner_delivery_position('unassigned',18,-88,10,now());raise exception 'Runner bypass';exception when insufficient_privilege then null;end;
end $$;
rollback;
select 'PASS: pickup gating, midpoint 50%, stale GPS fallback, terminal cleanup, tracking token and runner authorization' result;

