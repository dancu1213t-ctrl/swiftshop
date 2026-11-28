CREATE OR REPLACE FUNCTION swift_tracking_private.progress(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare t public.customer_order_tracking;o public.orders;m swift_tracking_private.motion;a float8[];b float8[];started timestamptz;distance numeric;remaining numeric;ratio numeric:=0;minutes integer;fresh boolean:=false;points jsonb;mode text:='time_estimate';
begin
 select * into t from public.customer_order_tracking where id=p_id;if not found then return null;end if;
 if t.phase in('cancelled','delivered') then return jsonb_build_object('active',false,'completed',t.phase='delivered');end if;
 select * into o from public.orders where order_id=t.linked_order_id;
 select * into m from swift_tracking_private.motion where order_id=p_id;
 if t.phase<>'on_the_way' and m.departed_at is null then return jsonb_build_object('active',false);end if;
 if jsonb_array_length(coalesce(o.run_stops,'[]'))>2 and coalesce(o.next_stop,0)<jsonb_array_length(o.run_stops)-1 and m.departed_at is null then return jsonb_build_object('active',false,'collecting',true);end if;
 points:=swift_tracking_private.endpoints(p_id);a:=array[(points->'pickup'->>0)::float8,(points->'pickup'->>1)::float8];b:=array[(points->'dropoff'->>0)::float8,(points->'dropoff'->>1)::float8];if a[1] is null or b[1] is null then a:=null;b:=null;end if;
 select min(created_at) into started from public.delivery_notification_events where order_id=p_id and phase='on_the_way';
 started:=coalesce(m.departed_at,started,t.updated_at);
 if a is null or b is null then return jsonb_build_object('active',true,'progress',null,'mode','awaiting_route','started_at',started,'eta_minutes',null);end if;
 distance:=public.srx_geo_miles(a[1],a[2],b[1],b[2])*1.609344;
 fresh:=m.observed_at>now()-interval '45 seconds' and m.observed_at<=now()+interval '10 seconds' and m.runner_id=o.assigned_runner_id;
 if not coalesce(fresh,false) then
 return jsonb_build_object('active',true,'progress',null,'eta_minutes',null,'mode',case when m.observed_at is null then 'awaiting_gps' else 'stale_gps' end,'location_updated_at',m.observed_at,'started_at',started,'pickup_inferred',m.departed_at is not null and t.phase<>'on_the_way');
 end if;
 remaining:=public.srx_geo_miles(m.lat,m.lng,b[1],b[2])*1.609344;ratio:=least(.95,greatest(0,1-remaining/greatest(distance,.05)));minutes:=greatest(1,ceil(remaining*1.3/20*60)::int+1);mode:='live_gps';
 return jsonb_build_object('active',true,'progress',round(ratio*100)::int,'eta_minutes',minutes,'mode',mode,'started_at',started,'location_updated_at',m.observed_at,'pickup_inferred',m.departed_at is not null and t.phase<>'on_the_way','delayed',ratio>=.95);
end $function$
;
CREATE OR REPLACE FUNCTION public.swift_runner_delivery_position(p_order text, p_lat double precision, p_lng double precision, p_accuracy double precision, p_observed timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.orders;m swift_tracking_private.motion;a float8[];b float8[];d numeric;remaining numeric;points jsonb;
begin
 if public.swift_worker_kind() is distinct from 'runner' then raise exception 'Approved runner required' using errcode='42501';end if;
 select * into o from public.orders where order_id=p_order and assigned_runner_id=auth.uid() and status in('Claimed','On the Way');
 if not found or o.customer_tracking_id is null then raise exception 'Assigned active run required' using errcode='42501';end if;
 if p_lat is null or p_lng is null or p_accuracy is null or not(p_lat between -90 and 90 and p_lng between -180 and 180 and p_accuracy between 0 and 100) or p_observed is null or p_observed<now()-interval '30 seconds' or p_observed>now()+interval '10 seconds' then raise exception 'Fresh accurate GPS required';end if;
 select * into m from swift_tracking_private.motion where order_id=o.customer_tracking_id;
 if m.observed_at>=p_observed then return;end if;
 if m.runner_id is distinct from auth.uid() then m.pickup_seen:=false;m.departed_at:=null;end if;
 points:=swift_tracking_private.endpoints(o.customer_tracking_id);a:=array[(points->'pickup'->>0)::float8,(points->'pickup'->>1)::float8];b:=array[(points->'dropoff'->>0)::float8,(points->'dropoff'->>1)::float8];if a[1] is null or b[1] is null then a:=null;b:=null;end if;
 if a is not null and b is not null and (o.run_stops is null or coalesce(o.next_stop,0)>=jsonb_array_length(o.run_stops)-2) then
  d:=public.srx_geo_miles(a[1],a[2],p_lat,p_lng)*1609.344;
  if d<=150 then m.pickup_seen:=true;end if;
  remaining:=public.srx_geo_miles(b[1],b[2],p_lat,p_lng);
  if m.pickup_seen and d>300 and remaining<public.srx_geo_miles(a[1],a[2],b[1],b[2])*.9 then m.departed_at:=coalesce(m.departed_at,now());end if;
 end if;
 insert into swift_tracking_private.motion(order_id,runner_id,lat,lng,observed_at,pickup_seen,departed_at) values(o.customer_tracking_id,auth.uid(),p_lat,p_lng,p_observed,coalesce(m.pickup_seen,false),m.departed_at)
 on conflict(order_id) do update set runner_id=excluded.runner_id,lat=excluded.lat,lng=excluded.lng,observed_at=excluded.observed_at,pickup_seen=excluded.pickup_seen,departed_at=excluded.departed_at;
end $function$
;
CREATE OR REPLACE FUNCTION swift_tracking_private.enqueue_progress()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare t record;q jsonb;m swift_tracking_private.motion;e uuid;bucket int;begin
 for t in select c.id,c.runner_id from public.customer_order_tracking c where c.created_at>now()-interval '12 hours' and c.phase not in('delivered','cancelled') and (c.phase='on_the_way' or exists(select 1 from swift_tracking_private.motion m where m.order_id=c.id and m.departed_at is not null)) and exists(select 1 from public.delivery_push_subscriptions s where s.order_id=c.id) loop
 q:=swift_tracking_private.progress(t.id);if not coalesce((q->>'active')::boolean,false) then continue;end if;
 if q->>'mode' is distinct from 'live_gps' then continue;end if;
 bucket:=coalesce((q->>'progress')::integer/25,0);select * into m from swift_tracking_private.motion where order_id=t.id;
 if m.last_notice>now()-interval '3 minutes' or m.notice_bucket>=bucket then continue;end if;
 insert into public.delivery_notification_events(order_id,phase) values(t.id,'delivery_progress') returning id into e;
 insert into public.delivery_push_jobs(event_id,install_id) select e,s.install_id from public.delivery_push_subscriptions s where s.order_id=t.id;
 insert into swift_tracking_private.motion(order_id,runner_id,last_notice,notice_bucket) values(t.id,t.runner_id,now(),bucket) on conflict(order_id) do update set last_notice=excluded.last_notice,notice_bucket=excluded.notice_bucket;
 end loop;end $function$
;