begin;
create schema if not exists swift_admin_reporting;
revoke all on schema swift_admin_reporting from public,anon,authenticated;

create function swift_admin_reporting.store_zone(p_category text) returns text language sql stable set search_path='' as $$
 select coalesce((select zone_id from public.swift_store_registry where category=p_category),
 (select coalesce(detail->>'zone_id',detail->>'zone') from public.swift_region_audit where entity=p_category and coalesce(detail->>'zone_id',detail->>'zone') is not null order by created_at desc limit 1))
$$;
revoke all on function swift_admin_reporting.store_zone(text) from public,anon,authenticated;

create view swift_admin_reporting.ride_facts as
with priced as (
 select r.*,r.total_fare recorded_total_fare,
 round(coalesce(l.standard_fare+coalesce(l.pickup_supplement,0)+coalesce(l.return_allowance,0)+coalesce(l.rounding_adjustment,0)+coalesce(l.driver_protection_fee,0),r.total_fare,w.worker_amount+w.commission,tx.fare_cents/100.0)*100)::bigint fare_cents,
 round(coalesce(l.commission,r.commission_bzd,w.commission)*100)::bigint commission_cents,
 round(w.worker_amount*100)::bigint recorded_worker_cents,
 case when l.standard_fare is not null then 'pricing_ledger' when r.total_fare is not null then 'ride_record' when w.worker_amount+w.commission is not null then 'worker_ledger' when tx.fare_cents is not null then 'payment_record' else 'missing' end fare_source,
 coalesce(r.completed_at,l.completed_at,w.completed_at,r.updated_at,r.created_at) accounting_at,
 coalesce(w.customer_paid,false) customer_paid,w.payment_method recorded_payment_method,tx.fare_cents paid_fare_cents,
 coalesce((select sum(round(e.amount*100)::bigint) from public.swift_worker_payment_events e where e.payment_id=w.id and e.event_kind='commission_received'),0)::bigint commission_received_cents
 from public.swiftride_orders r left join public.swiftride_pricing_ledger l on l.ride_id=r.id
 left join public.swift_worker_payments w on w.worker_kind='driver' and w.source_id=r.id::text
 left join lateral(select sum(-amount_cents)::bigint fare_cents from public.swiftpay_transactions where kind='payment' and reference_kind='ride' and reference_id=r.id) tx on true
)
select p.*,coalesce(round(p.earnings_bzd*100)::bigint,p.fare_cents-p.commission_cents,p.recorded_worker_cents) driver_cents,
 case when p.status='completed' then case when p.paid_fare_cents is not null or (p.customer_paid and p.recorded_payment_method in('Online','SwiftPay')) then p.commission_cents else p.commission_received_cents end else 0 end collected_commission_cents
from priced p;
revoke all on swift_admin_reporting.ride_facts from public,anon,authenticated;

create or replace function public.swift_admin_portal_rides(p_zone text default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare z text:=public.swift_admin_effective_zone(p_zone);
begin return coalesce((select jsonb_agg(to_jsonb(x) order by created_at desc) from(
 select id,customer_name,status,zone_id,driver_id,created_at,pickup_label,dropoff_label,
 fare_cents/100.0 total_fare,case when status='completed' then driver_cents/100.0 end driver_earnings,
 case when status='completed' then commission_cents/100.0 end swiftshop_income,fare_source,fare_cents is null fare_missing
 from swift_admin_reporting.ride_facts where (z is null or zone_id=z) and (created_at>now()-interval '30 days' or status not in('completed','cancelled')) order by created_at desc limit 100)x),'[]');end $$;

create view swift_admin_reporting.income_events as
select 'ride:'||r.id event_id,'swiftride'::text service,r.zone_id,r.accounting_at occurred_at,'Ride #'||left(r.id::text,8) description,
 r.fare_cents gross_cents,r.driver_cents worker_cents,r.commission_cents earned_cents,r.collected_commission_cents collected_cents,
 (r.fare_cents is null or r.commission_cents is null or r.zone_id is null) missing_data
from swift_admin_reporting.ride_facts r where r.status='completed'
union all
select 'ride-payment:'||t.id,'swiftride',null,t.created_at,'Historic payment; ride record unavailable',-t.amount_cents,null,null,0,true
from public.swiftpay_transactions t where t.kind='payment' and t.reference_kind='ride' and not exists(select 1 from public.swiftride_orders r where r.id=t.reference_id)
union all
select 'run:'||o.order_id,case when coalesce(t.snapshot->>'courier_service','false')='true' or coalesce(t.snapshot->>'pickup_service','false')='true' or lower(coalesce(o.order_type,'')) like '%courier%' then 'courier' else 'delivery' end,
 o.zone_id,coalesce(o.runner_completed_at,w.completed_at,o.updated_at,o.timestamp),'Run #'||o.order_id,
 round(coalesce(o.customer_total,case when t.snapshot->>'total' ~ '^[0-9]+(\.[0-9]+)?$' then (t.snapshot->>'total')::numeric end)*100)::bigint,
 round(coalesce(w.worker_amount,o.runner_pay)*100)::bigint,
 case when f.fee is not null and o.runner_pay is not null then round((f.fee-o.runner_pay+f.platform)*100)::bigint end,
 case when (coalesce(w.customer_paid,false) or o.is_paid or exists(select 1 from public.swiftpay_payments p where p.kind='delivery' and p.reference_id=t.id and p.state='captured')) and coalesce(w.payment_method,o.payment_method) in('SwiftPay','Online') then case when f.fee is not null and o.runner_pay is not null then round((f.fee-o.runner_pay+f.platform)*100)::bigint end
 else coalesce((select sum(round(e.amount*100)::bigint) from public.swift_worker_payment_events e where e.payment_id=w.id and e.event_kind='commission_received'),0)::bigint end,
 (f.fee is null or o.runner_pay is null or o.zone_id is null)
from public.orders o
left join public.swift_worker_payments w on w.worker_kind='runner' and w.source_id=o.order_id
left join lateral(select q.id,q.snapshot from public.customer_order_tracking q where q.id=o.customer_tracking_id or q.linked_order_id=o.order_id order by (q.id=o.customer_tracking_id) desc nulls last,q.created_at desc limit 1)t on true
cross join lateral(select case when t.snapshot->>'delivery_fee' ~ '^[0-9]+(\.[0-9]+)?$' then (t.snapshot->>'delivery_fee')::numeric end fee,case when t.snapshot->>'platform_fee' ~ '^[0-9]+(\.[0-9]+)?$' then (t.snapshot->>'platform_fee')::numeric else 0 end platform)f
where o.status='Delivered'
union all
select 'wallet-fee:'||t.id,'swiftpay',coalesce(r.zone_id,c.zone_id,swift_admin_reporting.store_zone(sr.category)),t.created_at,
 case when t.reference_kind='transfer_out' then 'SwiftPay transfer fee' else 'SwiftPay '||coalesce(t.reference_kind,'other')||' fee' end,
 0,0,t.fee_cents,t.fee_cents,coalesce(r.zone_id,c.zone_id,swift_admin_reporting.store_zone(sr.category)) is null
from public.swiftpay_transactions t
left join public.swiftride_orders r on t.reference_kind='ride' and r.id=t.reference_id
left join public.customer_order_tracking c on t.reference_kind='delivery' and c.id=t.reference_id
left join public.swiftpay_store_receipts sr on sr.transaction_id=t.id
where t.fee_cents<>0
union all
select 'merchant-commission:'||s.id,'merchant_commissions',swift_admin_reporting.store_zone(s.category),s.sale_at,'Merchant sales commission',s.gross_cents,0,s.fee_cents,0,swift_admin_reporting.store_zone(s.category) is null
from public.swift_sale_commissions s
union all
select 'merchant-commission-receipt:'||s.id,'merchant_commissions',swift_admin_reporting.store_zone(s.category),s.created_at,'Merchant commission received',0,0,0,s.amount_cents,swift_admin_reporting.store_zone(s.category) is null
from public.swift_commission_receipts s
union all
select 'merchant-charge:'||s.id,case when s.kind='commission' then 'merchant_commissions' else 'merchant_fees' end,swift_admin_reporting.store_zone(s.category),s.incurred_at,'Merchant '||s.kind,0,0,s.amount_cents,0,swift_admin_reporting.store_zone(s.category) is null
from public.swift_merchant_charges s where s.kind<>'commission' or not exists(select 1 from public.swift_sale_commissions c where c.category=s.category and c.source_key=s.source_key)
union all
select 'merchant-receipt:'||s.id,case when s.kind='commission' then 'merchant_commissions' else 'merchant_fees' end,swift_admin_reporting.store_zone(s.category),s.received_at,'Merchant '||s.kind||' received',0,0,0,s.amount_cents,swift_admin_reporting.store_zone(s.category) is null
from public.swift_merchant_receipts s where s.kind<>'commission' or not exists(select 1 from public.swift_commission_receipts c where c.category=s.category and c.reference=s.reference and c.amount_cents=s.amount_cents)
union all
select 'runner-fee:'||s.id,'runner_fees',null,s.created_at,'Runner service fee received',0,0,s.amount_cents,s.amount_cents,true from public.swift_runner_fee_receipts s;
revoke all on swift_admin_reporting.income_events from public,anon,authenticated;

create function public.swift_admin_income(p_zone text default null,p_from date default null,p_to date default null,p_service text default null,p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare z text:=public.swift_admin_effective_zone(p_zone);result jsonb;from_at timestamptz;to_at timestamptz;
begin
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'Start date must come before the end date';end if;
 from_at:=p_from::timestamp at time zone 'America/Belize';to_at:=(p_to+1)::timestamp at time zone 'America/Belize';
 with filtered as(select * from swift_admin_reporting.income_events where (z is null or zone_id=z) and (from_at is null or occurred_at>=from_at) and (to_at is null or occurred_at<to_at)),
 grouped as(select service,count(*) entries,coalesce(sum(gross_cents),0) gross_cents,coalesce(sum(worker_cents),0) worker_cents,coalesce(sum(earned_cents),0) earned_cents,coalesce(sum(collected_cents),0) collected_cents,count(*) filter(where missing_data) missing_count from filtered group by service)
 select jsonb_build_object('zone_id',z,'from',p_from,'to',p_to,'updated_at',now(),'services',coalesce((select jsonb_agg(to_jsonb(g) order by service) from grouped g),'[]'),
 'totals',(select jsonb_build_object('earned_cents',coalesce(sum(earned_cents),0),'collected_cents',coalesce(sum(collected_cents),0),'gross_cents',coalesce(sum(gross_cents),0),'worker_cents',coalesce(sum(worker_cents),0),'missing_count',count(*) filter(where missing_data),'unassigned_count',count(*) filter(where zone_id is null)) from filtered),
 'entries',coalesce((select jsonb_agg(to_jsonb(d) order by occurred_at desc,event_id) from(select * from filtered where p_service is null or service=p_service order by occurred_at desc,event_id limit 25 offset greatest(0,least(coalesce(p_offset,0),100000)))d),'[]'),
 'more',(select count(*)>greatest(0,coalesce(p_offset,0))+25 from filtered where p_service is null or service=p_service)) into result;return result;
end $$;
revoke all on function public.swift_admin_income(text,date,date,text,integer) from public,anon;
grant execute on function public.swift_admin_income(text,date,date,text,integer) to authenticated;
commit;

