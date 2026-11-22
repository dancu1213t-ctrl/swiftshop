begin;
create or replace function public.swift_courier_quote(p_pickup jsonb,p_dropoff jsonb,p_zone text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare a float8;b float8;c float8;d float8;meters float8;miles float8;fee integer;
begin
 if jsonb_typeof(p_pickup->'lat') is distinct from 'number' or jsonb_typeof(p_pickup->'lng') is distinct from 'number' or jsonb_typeof(p_dropoff->'lat') is distinct from 'number' or jsonb_typeof(p_dropoff->'lng') is distinct from 'number' then raise exception 'Confirm both map pins';end if;
 a:=(p_pickup->>'lat')::float8;b:=(p_pickup->>'lng')::float8;c:=(p_dropoff->>'lat')::float8;d:=(p_dropoff->>'lng')::float8;
 if not(a between -90 and 90 and b between -180 and 180 and c between -90 and 90 and d between -180 and 180) then raise exception 'Invalid map pins';end if;
 if p_zone is null or public.swift_zone_at(a,b) is distinct from p_zone or public.swift_zone_at(c,d) is distinct from p_zone then raise exception 'Both pins must be inside your selected active service area';end if;
 meters:=6371000*2*asin(sqrt(least(1.0,power(sin(radians(c-a)/2),2)+cos(radians(a))*cos(radians(c))*power(sin(radians(d-b)/2),2))));
 if meters<1 then raise exception 'Pickup and delivery must be different entrances';end if;
 miles:=meters/1609.344;fee:=case when miles>1.5 then 700 when miles>1.3 then 600 else 500 end;
 return jsonb_build_object('fee_cents',fee,'distance_meters',round(meters::numeric),'distance_miles',round(miles::numeric,3),'zone_id',p_zone,'distance_basis','pin_to_pin');
end $$;
revoke all on function public.swift_courier_quote(jsonb,jsonb,text) from public;
grant execute on function public.swift_courier_quote(jsonb,jsonb,text) to anon,authenticated;
CREATE OR REPLACE FUNCTION public.swift_merchant_validate_delivery()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare q jsonb;begin if tg_op='INSERT' and new.snapshot->>'courier_service'='true' then
 if jsonb_array_length(coalesce(new.snapshot->'items','[]'::jsonb))<>0 or coalesce(new.snapshot->>'pickup_service','false')='true' or new.snapshot->>'courier_mode' not in('send','receive') then raise exception 'Invalid courier request';end if;
 q:=public.swift_courier_quote(new.snapshot->'courier_pickup',new.snapshot->'courier_dropoff',new.snapshot->>'service_zone');
 if (new.snapshot->>'delivery_fee')::numeric is distinct from (q->>'fee_cents')::numeric/100 or (new.snapshot->>'total')::numeric is distinct from (q->>'fee_cents')::numeric/100 or coalesce((new.snapshot->>'platform_fee')::numeric,0)<>0 then raise exception 'Courier price changed. Review your quote';end if;
 new.zone_id:=q->>'zone_id';new.snapshot:=new.snapshot||jsonb_build_object('courier_quote',q,'local_shopping',false);return new;end if;
 if tg_op<>'INSERT' then return new;end if; if exists(select 1 from public.customer_order_tracking where id=new.id) then return new;end if; if coalesce(new.snapshot->>'pickup_service','false')='true' then new.zone_id:=public.swift_zone_at(split_part(new.snapshot->>'pickup_location',',',1)::float8,split_part(new.snapshot->>'pickup_location',',',2)::float8);if new.zone_id is null then raise exception 'Pickup service is not active in this area';end if;return new;end if; if jsonb_array_length(coalesce(new.snapshot->'items','[]'::jsonb))=0 and nullif(new.snapshot->>'taco_note','') is not null then new.zone_id:='orange-walk';if (new.snapshot->>'delivery_fee')::numeric is distinct from 3.50 then raise exception 'Delivery fee changed';end if;return new;end if; q:=public.swift_region_quote(new.snapshot->'items',new.snapshot->>'customer_location');new.zone_id:=q->>'zone_id';new.snapshot:=new.snapshot||jsonb_build_object('delivery_pricing',q); if (new.snapshot->>'delivery_fee')::numeric is distinct from (q->>'fee_cents')::numeric/100 or coalesce((new.snapshot->>'platform_fee')::numeric,0)<>0 then raise exception 'Delivery fee changed. Refresh checkout before sending the order';end if; new.snapshot:=new.snapshot||jsonb_build_object('service_zone',new.zone_id,'district_id',q->>'district_id'); new.snapshot:=new.snapshot||jsonb_build_object('local_shopping',coalesce(new.snapshot->'gift','null'::jsonb)='null'::jsonb and jsonb_array_length(new.snapshot->'items')>0 and not exists(select 1 from jsonb_array_elements(new.snapshot->'items') i where not(i->>'category'=any(array['Snack','Drink','Household','Hygiene','Vegetables','Treats'])) or nullif(i->>'offer_id','') is not null)); if (new.snapshot->>'local_shopping')::boolean then new.snapshot:=new.snapshot||jsonb_build_object('routes',jsonb_build_array('https://www.google.com/maps/dir/?api=1&destination='||(new.snapshot->>'customer_location')),'shopping_instructions','Buy these items from a nearby store. After buying everything, start delivery from your current GPS location to the customer.');end if;return new; end$function$
;
CREATE OR REPLACE FUNCTION public.swiftpay_tracking_invoice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare line jsonb;item_sum numeric=0;qty integer;price numeric;delivery numeric=3.50;drink_count integer=0;only_brew boolean=true;invoice numeric;tip numeric;

begin

 if tg_op='INSERT' then

  if new.snapshot->>'payment' is distinct from 'SwiftPay' then return new;end if;

  if new.snapshot->>'courier_service'='true' then
   delivery:=(public.swift_courier_quote(new.snapshot->'courier_pickup',new.snapshot->'courier_dropoff',new.snapshot->>'service_zone')->>'fee_cents')::numeric/100;
   if (new.snapshot->>'total')::numeric is distinct from delivery or jsonb_array_length(new.snapshot->'items')<>0 then raise exception 'Invalid courier total';end if;
   perform public.swiftpay_reserve('delivery',new.id,new.customer_id,round(delivery*100)::bigint,null);
   new.snapshot:=new.snapshot||jsonb_build_object('swiftpay_fee',0.25);return new;
  end if;
  if new.snapshot->>'pickup_service'='true' then

   if new.snapshot->>'store_paid' is distinct from 'true' or jsonb_array_length(new.snapshot->'items')<>0 then raise exception 'SwiftPay pickup covers the service fee for already-paid store items';end if;

   new.snapshot=new.snapshot||jsonb_build_object('total',null,'swiftpay_fee',0.25);

   return new;

  end if;

  if jsonb_array_length(new.snapshot->'items')=0 or coalesce(new.snapshot->>'taco_note','')<>'' then

   new.snapshot=new.snapshot||jsonb_build_object('needs_invoice',true,'total',null,'swiftpay_fee',0.25);return new;

  end if;

  for line in select value from jsonb_array_elements(new.snapshot->'items') loop

   qty=(line->>'quantity')::integer;price=(line->>'price')::numeric;

   if qty is null or qty not between 1 and 100 or price is null or price<0 or price<>round(price,2) then raise exception 'Invalid item quantity or price';end if;

   if not exists(select 1 from public.products catalog where catalog.name=line->>'name' and catalog.category=line->>'category' and public.swift_product_checkout_price(catalog,coalesce(line->'selected_options','{}'::jsonb))=(line->>'price')::numeric) then

    new.snapshot=new.snapshot||jsonb_build_object('needs_invoice',true,'total',null,'swiftpay_fee',0.25);return new;

   end if;

   item_sum=item_sum+qty*price;drink_count=drink_count+qty;

   only_brew=only_brew and lower(trim(coalesce(line->>'category','')))='brew';

  end loop;

  

  tip=coalesce((new.snapshot->>'tip')::numeric,0);

  if tip<0 or tip>1000 or tip<>round(tip,2) then raise exception 'Invalid runner tip';end if;

  delivery:=(public.swift_region_quote(new.snapshot->'items',new.snapshot->>'customer_location')->>'fee_cents')::numeric/100;invoice=item_sum+delivery+tip;

  if (new.snapshot->>'total')::numeric is distinct from invoice then raise exception 'Order total changed. Refresh your checkout';end if;

  perform public.swiftpay_reserve('delivery',new.id,new.customer_id,round(invoice*100)::bigint,null);

  new.snapshot=new.snapshot||jsonb_build_object('swiftpay_fee',0.25);

 elsif new.snapshot is distinct from old.snapshot and exists(select 1 from public.swiftpay_payments where kind='delivery' and reference_id=new.id) then

  if new.snapshot->'total' is distinct from old.snapshot->'total' or new.snapshot->'payment' is distinct from old.snapshot->'payment' or new.snapshot->'items' is distinct from old.snapshot->'items' then raise exception 'A reserved SwiftPay invoice cannot be changed';end if;

 end if;

 if tg_op='UPDATE' then

  if new.phase in ('accepted','preparing','finding_runner') and public.swift_worker_kind() = 'admin' then

   update public.swiftpay_payments set approved_by=auth.uid() where kind='delivery' and reference_id=new.id and state='reserved' and approved_by is null;

  end if;

  if new.phase in ('cancelled','canceled','expired') then update public.swiftpay_payments set state='released',released_at=now() where kind='delivery' and reference_id=new.id and state in ('quoted','reserved');end if;

  if new.linked_order_id is not null and old.linked_order_id is null and new.snapshot->>'payment'='SwiftPay' and not exists(select 1 from public.swiftpay_payments where kind='delivery' and reference_id=new.id and state='reserved') then raise exception 'Wait for the customer to accept the SwiftPay invoice before dispatch';end if;

 end if;

 return new;

end $function$
;

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
 update public.customer_order_tracking set phase='accepted',dispatch_control='manual',auto_accept_after=null where id=p_id;
 stops:=jsonb_build_array(jsonb_build_object('label',case when mode='send' then 'Pickup · Customer' else 'Pickup · '||(p_request->>'contact_name') end,'location',a),jsonb_build_object('label',case when mode='receive' then 'Deliver · Customer' else 'Deliver · '||(p_request->>'contact_name') end,'location',b));
 job:=public.swift_dispatch_run(p_id,coalesce(nullif(u.name,''),'Customer'),coalesce(u.contact_phone,u.phone),brief,route,case when payment='SwiftPay' then 'SwiftPay' else 'Cash' end,'pickup_dropoff',0,stops,jsonb_build_object('customer_tracking_id',p_id,'customer_location',case when mode='send' then a else b end,'route_notes',notes,'is_paid',false));
 perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);perform set_config('request.jwt.claims',coalesce(old_claims,''),true);
 return public.get_customer_tracking(p_id,p_token);
 exception when others then perform set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);perform set_config('request.jwt.claims',coalesce(old_claims,''),true);raise;
end $$;
revoke all on function public.swift_courier_request(uuid,uuid,jsonb,integer) from public,anon;
grant execute on function public.swift_courier_request(uuid,uuid,jsonb,integer) to authenticated;

CREATE OR REPLACE FUNCTION public.get_customer_tracking(p_id uuid, p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.customer_order_tracking; runner_name text; runner_phone text; runner_photo text;
begin
 select * into r from public.customer_order_tracking where id=p_id and access_token=p_token;
 if not found then raise exception 'Tracking request unavailable';end if;
 if r.runner_id is not null then
  select display_name,delivery_contact_phone into runner_name,runner_phone from public.profiles where id=r.runner_id;
  select photo into runner_photo from public.runner_profile_photos where runner_id=r.runner_id;
 end if;
 return jsonb_build_object('id',r.id,'phase',r.phase,'created_at',r.created_at,'updated_at',r.updated_at,'runner_name',runner_name,'runner_phone',runner_phone,'runner_photo',runner_photo)||case when r.snapshot->>'courier_service'='true' then jsonb_build_object('courier_service',true,'courier_mode',r.snapshot->>'courier_mode','courier_leg',case when r.phase='delivered' then 'delivered' when coalesce((select next_stop from public.orders where order_id=r.linked_order_id),0)>0 then 'dropoff' else 'pickup' end) else '{}'::jsonb end;
end $function$
;
notify pgrst,'reload schema';
commit;
