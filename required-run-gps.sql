alter table swift_tracking_private.motion add column if not exists accuracy double precision;
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
 if p_lat is null or p_lng is null or p_accuracy is null or not(p_lat between -90 and 90 and p_lng between -180 and 180 and p_accuracy between 0 and 50) or p_observed is null or p_observed<now()-interval '20 seconds' or p_observed>now()+interval '10 seconds' then raise exception 'Fresh accurate GPS required';end if;
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
 insert into swift_tracking_private.motion(order_id,runner_id,lat,lng,observed_at,pickup_seen,departed_at,accuracy) values(o.customer_tracking_id,auth.uid(),p_lat,p_lng,p_observed,coalesce(m.pickup_seen,false),m.departed_at,p_accuracy)
 on conflict(order_id) do update set runner_id=excluded.runner_id,lat=excluded.lat,lng=excluded.lng,observed_at=excluded.observed_at,pickup_seen=excluded.pickup_seen,departed_at=excluded.departed_at,accuracy=excluded.accuracy;
end $function$
;
CREATE OR REPLACE FUNCTION swift_tracking_private.runner_location(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare t public.customer_order_tracking;o public.orders;m swift_tracking_private.motion;points jsonb;fresh boolean;
begin
 select * into t from public.customer_order_tracking where id=p_id;
 if not found or t.phase in('delivered','cancelled') then return jsonb_build_object('active',false);end if;
 select * into o from public.orders where order_id=t.linked_order_id;
 if o.assigned_runner_id is null or o.status not in('Claimed','On the Way') then return jsonb_build_object('active',false);end if;
 select * into m from swift_tracking_private.motion where order_id=p_id and runner_id=o.assigned_runner_id;
 fresh:=coalesce(m.observed_at>now()-interval '30 seconds' and m.observed_at<=now()+interval '10 seconds',false);
 points:=swift_tracking_private.endpoints(p_id);
 return jsonb_build_object('active',true,'fresh',fresh,'lat',case when fresh then m.lat end,'lng',case when fresh then m.lng end,'accuracy',case when fresh then m.accuracy end,'updated_at',m.observed_at,'leg',case when t.phase='on_the_way' or m.departed_at is not null then 'dropoff' else 'pickup' end,'pickup',points->'pickup','dropoff',points->'dropoff','order_id',p_id);
end $function$
;