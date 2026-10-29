begin;
create or replace function public.swift_operations_report() returns jsonb language plpgsql security definer set search_path='' as $$
declare since_at timestamptz:=now()-interval '7 days';launch_at timestamptz;earned bigint;received bigint;runner_due bigint;
begin
 perform public.swift_admin_session();select started_at into launch_at from public.swift_launch_accounting_config where id;
 select coalesce(sum(fee_cents),0) into earned from public.swift_sale_commissions;
 select coalesce(sum((runs/6)*250),0) into runner_due from(select count(*) runs from public.orders where status='Delivered' and assigned_runner_id is not null and runner_completed_at>=launch_at group by assigned_runner_id)r;
 select coalesce((select sum(amount_cents) from public.swift_commission_receipts),0)+coalesce((select sum(amount_cents) from public.swift_runner_fee_receipts),0) into received;
 return jsonb_build_object('orders_7d',(select count(*) from public.customer_order_tracking where created_at>=since_at),'completed_7d',(select count(*) from public.customer_order_tracking where created_at>=since_at and phase='delivered'),'active_orders',(select count(*) from public.customer_order_tracking where phase not in('delivered','cancelled','rejected')),'repeat_customers_7d',(select count(*) from(select customer_id from public.customer_order_tracking where created_at>=since_at and phase='delivered' and customer_id is not null group by customer_id having count(*)>1)r),
 'commission_earned_cents',earned,'runner_fee_earned_cents',runner_due,'fees_received_cents',received,'outstanding_cents',greatest(earned+runner_due-received,0),
 'commission_received_7d_cents',coalesce((select sum(amount_cents) from public.swift_commission_receipts where created_at>=since_at),0),'runner_fees_received_7d_cents',coalesce((select sum(amount_cents) from public.swift_runner_fee_receipts where created_at>=since_at),0),
 'support_open',(select count(*) from public.swift_support_requests where status in('open','reviewing')),'push_pending',(select count(*) from public.swift_team_push_jobs where sent_at is null and failed_at is null),'push_failed_7d',(select count(*) from public.swift_team_push_jobs where failed_at>=since_at),'generated_at',now());
end $$;
revoke all on function public.swift_operations_report() from public,anon;
grant execute on function public.swift_operations_report() to authenticated;
notify pgrst,'reload schema';commit;
