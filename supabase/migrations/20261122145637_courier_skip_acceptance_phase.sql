create or replace function public.swift_courier_request(p_id uuid,p_token uuid,p_request jsonb,p_expected_fee_cents integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u public.swiftshop_users;r public.customer_order_tracking;q jsonb;snap jsonb;job public.orders;admin_id uuid;old_sub text:=current_setting('request.jwt.claim.sub',true);old_claims text:=current_setting('request.jwt.claims',true);a text;b text;brief text;mode text;payment text;route text;notes text;stops jsonb;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and not coalesce(is_anonymous,false)) then raise exception 'Sign in with a verified customer account' using errcode='42501';end if;
 if p_id is null or p_token is null or p_id=p_token or jsonb_typeof(p_request) is distinct from 'object' or octet_length(p_request::text)>8000 then raise exception 'Invalid courier request';end if;
 perform pg_advisory_xact_lock(hashtext('courier:'||p_id::text));
 select * into r from public.customer_order_tracking where id=p_id;
 if found then
  if r.customer_id is distinct from auth.uid() or r.access_token is distinct from p_token or r.snapshot->'courier_request' is distinct from p_request or r.snapshot->>'courier_service' is distinct from 'true' then raise exception 'Courier request does not match the original' using errcode='42501';end if;
  return public.get_customer_tracking(p_id,p_token);
 end if;
 select * into u from public.swiftshop_users where auth_user_id=auth.uid();if not found then raise exception 'Complete your customer profile';end if;
 mode:=p_request->>'mode';payment:=p_request->>'payment';
 if mode is null or mode not in('send','receive') or payment is null or payment not in('Cash on Delivery','SwiftPay') then raise exception 'Choose Send or Receive and a payment method';end if;
 if length(trim(coalesce(p_request->>'description',''))) not between 2 and 500 or length(trim(coalesce(p_request->>'contact_name',''))) not between 1 and 100 or coalesce(p_request->>'contact_phone','') !~ '^\+?[0-9 ()-]{7,20}$' or length(coalesce(p_request->>'notes',''))>500 or length(coalesce(p_request->>'pickup_label','')) not between 1 and 150 or length(coalesce(p_request->>'dropoff_label','')) not between 1 and 150 then raise exception 'Add package details and the other contact name and phone';end if;
 q:=public.swift_courier_quote(p_request->'pickup',p_request->'dropoff',p_request->>'zone_id');
 if p_expected_fee_cents is distinct from (q->>'fee_cents')::integer then raise exception 'Courier quote changed. Review the price and retry';end if;
 a:=(p_request->'pickup'->>'lat')||','||(p_request->'pickup'->>'lng');b:=(p_request->'dropoff'->>'lat')||','||(p_request->'dropoff'->>'lng');
 route:='https://www.google.com/maps/dir/?api=1&origin='||a||'&destination='||b;
 notes:='COURIER · '||upper(mode)||E'\nPickup: '||(p_request->>'pickup_label')||E'\nDeliver to: '||(p_request->>'dropoff_label')||E'\nOther contact: '||(p_request->>'contact_name')||' · '||(p_request->>'contact_phone')||E'\n'||coalesce(p_request->>'notes','');
 brief:='COURIER · '||upper(mode)||E'\nPackage: '||(p_request->>'description')||E'\n'||notes;
 snap:=jsonb_build_object('customer_name',coalesce(nullif(u.name,''),'Customer'),'phone',coalesce(u.contact_phone,u.phone),'sender_phone',coalesce(u.contact_phone,u.phone),'items','[]'::jsonb,'total',p_expected_fee_cents/100.0,'delivery_fee',p_expected_fee_cents/100.0,'platform_fee',0,'payment',payment,'courier_service',true,'courier_mode',mode,'courier_request',p_request,'courier_pickup',p_request->'pickup','courier_dropoff',p_request->'dropoff','courier_quote',q,'service_zone',q->>'zone_id','pickup_location',a,'customer_location',case when mode='send' then a else b end,'arrival_notes',notes,'routes',jsonb_build_array(route),'dispatch_text',brief);
 perform public.create_customer_tracking(p_id,p_token,snap);
 select id into admin_id from public.profiles where role='admin' and active order by id limit 1;if admin_id is null then raise exception 'Courier dispatch is temporarily unavailable';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
 update public.customer_order_tracking set phase='finding_runner',dispatch_control='manual',auto_accept_after=null where id=p_id;
 stops:=jsonb_build_array(jsonb_build_object('label',case when mode='send' then 'Pickup · Customer' else 'Pickup · '||(p_request->>'contact_name') end,'location',a),jsonb_build_object('label',case when mode='receive' then 'Deliver · Customer' else 'Deliver · '||(p_request->>'contact_name') end,'location',b));
 job:=public.swift_dispatch_run(p_id,coalesce(nullif(u.name,''),'Customer'),coalesce(u.contact_phone,u.phone),brief,route,case when payment='SwiftPay' then 'SwiftPay' else 'Cash' end,'pickup_dropoff',0,stops,jsonb_build_object('customer_tracking_id',p_id,'customer_location',case when mode='send' then a else b end,'route_notes',notes,'is_paid',false));
 perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);perform set_config('request.jwt.claims',coalesce(old_claims,''),true);
 return public.get_customer_tracking(p_id,p_token);
 exception when others then perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);perform set_config('request.jwt.claims',coalesce(old_claims,''),true);raise;
end $$;
