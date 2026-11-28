alter view swift_admin_reporting.income_rows rename to income_rows_before_wait_fee;
create view swift_admin_reporting.income_rows as
select * from swift_admin_reporting.income_rows_before_wait_fee
union all
select 'ride-wait-fee:'||f.charged_ride_id::text,'swiftride',o.zone_id,max(f.earned_at),'Saved SwiftShop cancellation fee · ride #'||left(o.id::text,8),sum(f.amount_cents)::bigint,0::bigint,sum(f.amount_cents)::bigint,
case when exists(select 1 from public.swiftpay_payments p where p.kind='ride' and p.reference_id=o.id and p.state='captured') then sum(f.amount_cents)::bigint else least(sum(f.amount_cents)::bigint,greatest(0,coalesce((select round(sum(e.amount)*100)::bigint from public.swift_worker_payments w join public.swift_worker_payment_events e on e.payment_id=w.id where w.worker_kind='driver' and w.source_id=o.id::text and e.event_kind='commission_received'),0)-round(coalesce(l.commission,0)*100)::bigint)) end,
false,sum(f.amount_cents)::bigint
from swift_ride_private.cancellation_fees f join public.swiftride_orders o on o.id=f.charged_ride_id join public.swiftride_pricing_ledger l on l.ride_id=o.id where f.earned_at is not null group by f.charged_ride_id,o.id,o.zone_id,l.commission;
revoke all on swift_admin_reporting.income_rows,swift_admin_reporting.income_rows_before_wait_fee from public,anon,authenticated;
alter function public.swift_admin_portal_rides(text) rename to swift_admin_portal_rides_before_wait_fee;
revoke all on function public.swift_admin_portal_rides_before_wait_fee(text) from public,anon,authenticated;
create function public.swift_admin_portal_rides(p_zone text default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r jsonb;result jsonb:='[]';fee numeric;begin
 for r in select value from jsonb_array_elements(public.swift_admin_portal_rides_before_wait_fee(p_zone)) loop
 select coalesce(sum(amount_cents),0)/100.0 into fee from swift_ride_private.cancellation_fees where charged_ride_id=(r->>'id')::uuid;
 r:=r||jsonb_build_object('total_fare',case when r->>'total_fare' is not null then (r->>'total_fare')::numeric+fee end,'swiftshop_income',case when r->>'swiftshop_income' is not null then (r->>'swiftshop_income')::numeric+fee end,'saved_cancellation_fee',fee);
 result:=result||jsonb_build_array(r);end loop;return result;end $$;
revoke all on function public.swift_admin_portal_rides(text) from public,anon;
grant execute on function public.swift_admin_portal_rides(text) to authenticated;

