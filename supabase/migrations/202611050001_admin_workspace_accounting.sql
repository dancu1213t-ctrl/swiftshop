begin;
-- Preserve the payment event ledger; remove per-delivery runner commission from reporting and new terms.
do $migration$
declare s text;
begin
 s:=pg_get_functiondef('public.swift_admin_payments()'::regprocedure);
 if position('workspace20261105' in s)=0 then
  if position('select p.*,public.swift_funded_run_tip' in s)=0 then raise exception 'Unexpected payment report definition';end if;
  s:=replace(s,'select p.*,public.swift_funded_run_tip','select p.*,coalesce((select o.zone_id from public.orders o where p.worker_kind=''runner'' and o.order_id=p.source_id),(select r.zone_id from public.swiftride_orders r where p.worker_kind=''driver'' and r.id::text=p.source_id),''orange-walk'') zone_id,public.swift_funded_run_tip');
  s:=replace(s,'case when p.payment_method=''Cash'' and p.commission is not null','case when p.worker_kind=''driver'' and p.payment_method=''Cash'' and p.commission is not null');
  s:=replace(s,',null,coalesce((o->>''is_paid'')',',0,coalesce((o->>''is_paid'')');
  s:=replace(s,'declare o jsonb;','declare o jsonb; /* workspace20261105 */');
  execute s;
 end if;
 s:=pg_get_functiondef('public.swift_admin_payment_terms(uuid,text,numeric,numeric,uuid,text)'::regprocedure);
 if position('Runner service fees are tracked separately' in s)=0 then
  if position('if p_method not in' in s)=0 then raise exception 'Unexpected terms definition';end if;
  s:=replace(s,'if p_method not in','if p.worker_kind=''runner'' and p_commission is distinct from 0 then raise exception ''Runner service fees are tracked separately; per-run commission must be zero'';end if; if p_method not in');
  execute s;
 end if;
end $migration$;
-- No old balances, payouts, fee receipts or SwiftPay transactions are modified.
create or replace function public.swift_admin_fee_income()
returns jsonb language plpgsql security definer set search_path='' as $function$
declare result jsonb;
begin
 perform public.swift_require_payment_admin();
 with fees as (
  select (created_at at time zone 'America/Belize')::date fee_day,fee_cents,
   case when reference_kind='transfer_out' then 'transfer' when kind='payment' then 'payment' else 'other' end category
  from public.swiftpay_transactions where fee_cents<>0
 ), daily as (
  select fee_day,sum(fee_cents)/100.0 total,
   coalesce(sum(fee_cents) filter(where category='transfer'),0)/100.0 transfers,
   coalesce(sum(fee_cents) filter(where category='payment'),0)/100.0 payments
  from fees group by fee_day
 ) select jsonb_build_object(
  'today',coalesce(sum(fee_cents) filter(where fee_day=(now() at time zone 'America/Belize')::date),0)/100.0,
  'week',coalesce(sum(fee_cents) filter(where fee_day>=date_trunc('week',now() at time zone 'America/Belize')::date),0)/100.0,
  'transfers',coalesce(sum(fee_cents) filter(where category='transfer'),0)/100.0,
  'payments',coalesce(sum(fee_cents) filter(where category='payment'),0)/100.0,
  'other',coalesce(sum(fee_cents) filter(where category='other'),0)/100.0,
  'total',coalesce(sum(fee_cents),0)/100.0,
  'days',coalesce((select jsonb_agg(to_jsonb(d) order by fee_day desc) from daily d),'[]'::jsonb)
 ) into result from fees;
 return result;
end $function$;
revoke all on function public.swift_admin_fee_income() from public,anon;
grant execute on function public.swift_admin_fee_income() to authenticated;
notify pgrst,'reload schema';
commit;


