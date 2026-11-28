CREATE OR REPLACE FUNCTION public.swiftride_fleet(p_lat double precision, p_lng double precision, p_radius_km double precision DEFAULT NULL::double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$



begin



 if auth.uid() is null then raise exception 'Customer session required'; end if;



 if p_lat is null or p_lng is null or not(p_lat between -90 and 90) or not(p_lng between -180 and 180) then raise exception 'Invalid pickup location'; end if;



 return coalesce((select jsonb_agg(to_jsonb(n) order by n.distance_km) from (



 select d.driver_id,p.display_name,w.photo,coalesce(w.vehicle_type,'car') vehicle_type,



 coalesce(nullif(w.vehicle_model,''),nullif(a.vehicle,''),'Vehicle details pending') vehicle_model,coalesce(w.vehicle_color,'') vehicle_color,



 case when w.vehicle_type='motorcycle' then 1 else coalesce(w.passenger_seats,4) end passenger_seats,



 round(d.lat::numeric,3) lat,round(d.lng::numeric,3) lng,d.updated_at location_updated_at,(d.updated_at>now()-interval '90 seconds' and d.updated_at<=now()) location_fresh,'Available' availability,



 round((6371*2*asin(sqrt(least(1.0,power(sin(radians(d.lat-p_lat)/2),2)+cos(radians(p_lat))*cos(radians(d.lat))*power(sin(radians(d.lng-p_lng)/2),2)))))::numeric,2) distance_km



 from public.swiftride_drivers d join public.profiles p on p.id=d.driver_id



 join public.swift_worker_applications a on a.user_id=p.id and a.kind='driver' and a.status='approved'



 left join public.swift_worker_profiles w on w.user_id=p.id

 left join public.swiftride_driver_online_preferences pref on pref.driver_id=p.id



 where public.swift_worker_zone(d.driver_id,public.swift_zone_at(p_lat,p_lng)) and coalesce(pref.online,d.online) and p.active and d.accuracy between 0 and 200

 and d.lat between -90 and 90 and d.lng between -180 and 180 and d.updated_at is not null



 and not exists(select 1 from swift_ride_private.waiting wait where wait.driver_id=d.driver_id and wait.state='waiting')
and not exists(select 1 from public.swiftride_orders o where o.driver_id=d.driver_id and o.status in ('fare_approval','accepted','en_route','arrived'))
and (not exists(select 1 from public.swiftride_orders o where o.driver_id=d.driver_id and o.status='in_progress') or
(d.updated_at between now()-interval '90 seconds' and now() and d.accuracy<=100 and exists(select 1 from public.swiftride_orders o where o.driver_id=d.driver_id and o.status='in_progress' and public.srx_geo_miles(o.dropoff_lat,o.dropoff_lng,p_lat,p_lng)<=1.864114)))



 order by distance_km limit 100) n where p_radius_km is null or n.distance_km<=greatest(0,least(p_radius_km,500))), '[]'::jsonb);



end $function$
