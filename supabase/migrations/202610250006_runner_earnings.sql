begin;
create table public.swift_runner_fee_receipts(id uuid primary key,runner_id uuid not null,amount_cents bigint not null check(amount_cents>0),reference text not null check(length(reference) between 1 and 100),created_at timestamptz not null default now(),created_by uuid not null,unique(runner_id,reference));
alter table public.swift_runner_fee_receipts enable row level security;
revoke all on public.swift_runner_fee_receipts from public,anon,authenticated;
create function public.swift_runner_earnings_report(p_runner uuid default null,p_action text default 'report',p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare admin boolean:=coalesce(public.swift_worker_kind()='admin',false);due bigint;amount bigint;rid uuid;ref text;begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and active and role in('admin','runner')) then raise exception 'Active runner or administrator required' using errcode='42501';end if;
 if not admin and (p_action<>'report' or p_runner is not null and p_runner<>auth.uid()) then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_action='record_received' then
 if not admin or p_runner is null or not exists(select 1 from public.profiles where id=p_runner and role='runner') then raise exception 'Choose a runner' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtext('runner-fee:'||p_runner));
 rid:=(p_data->>'id')::uuid;amount:=round((p_data->>'amount')::numeric*100);ref:=trim(p_data->>'reference');
 if rid is null or amount is null or amount<=0 or length(coalesce(ref,'')) not between 1 and 100 then raise exception 'Enter a valid amount and payment reference';end if;
 if exists(select 1 from public.swift_runner_fee_receipts where id=rid) then
 if not exists(select 1 from public.swift_runner_fee_receipts where id=rid and runner_id=p_runner and amount_cents=amount and reference=ref) then raise exception 'Payment reference conflict';end if;
 else
 select (count(*)/6)*250 into due from public.orders where assigned_runner_id=p_runner and status='Delivered' and runner_completed_at>=(select started_at from public.swift_launch_accounting_config where id);
 due:=due-coalesce((select sum(amount_cents) from public.swift_runner_fee_receipts where runner_id=p_runner),0);
 if amount>due then raise exception 'Payment exceeds the runner fee owed';end if;
 insert into public.swift_runner_fee_receipts values(rid,p_runner,amount,ref,now(),auth.uid());end if;
 elsif p_action<>'report' then raise exception 'Invalid action';end if;
 return coalesce((with allowed as(select id,display_name from public.profiles where role='runner' and (admin or id=auth.uid()) and (p_runner is null or id=p_runner)), completed as(
 select o.order_id,o.assigned_runner_id runner_id,coalesce(o.runner_pay,0) pay,least(greatest(coalesce(o.swift_tip_cents,0),0)/100.0,coalesce(o.runner_pay,0)) tips,o.runner_completed_at done_at from public.orders o join allowed a on a.id=o.assigned_runner_id where o.status='Delivered' and o.runner_completed_at>=(select started_at from public.swift_launch_accounting_config where id)), totals as(
 select a.id,a.display_name,count(c.order_id) runs,coalesce(sum(c.pay),0) total,coalesce(sum(c.pay-c.tips),0) base,coalesce(sum(c.tips),0) tips,coalesce((select sum(amount_cents) from public.swift_runner_fee_receipts where runner_id=a.id),0) paid from allowed a left join completed c on c.runner_id=a.id group by a.id,a.display_name)
 select jsonb_agg(jsonb_build_object('runner_id',t.id,'display_name',t.display_name,'completed_runs',t.runs,'total',t.total,'base',t.base,'tips',t.tips,'fee_total',(t.runs/6)*2.50,'fee_paid',t.paid/100.0,'fee_owed',greatest((t.runs/6)*250-t.paid,0)/100.0,'progress',t.runs%6,'runs_until_next',6-t.runs%6,
 'weeks',coalesce((select jsonb_agg(to_jsonb(w) order by week desc) from(select date_trunc('week',done_at at time zone 'America/Belize')::date week,count(*) runs,sum(pay-tips) base,sum(tips) tips,sum(pay) total from completed where runner_id=t.id group by 1)w),'[]'::jsonb),
 'payments',coalesce((select jsonb_agg(jsonb_build_object('date',created_at,'amount',amount_cents/100.0,'reference',reference) order by created_at desc) from public.swift_runner_fee_receipts where runner_id=t.id),'[]'::jsonb)) order by t.display_name) from totals t),'[]'::jsonb);
end$$;
revoke all on function public.swift_runner_earnings_report(uuid,text,jsonb) from public,anon;
grant execute on function public.swift_runner_earnings_report(uuid,text,jsonb) to authenticated;
notify pgrst,'reload schema';commit;
