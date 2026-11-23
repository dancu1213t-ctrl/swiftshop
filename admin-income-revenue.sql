create view swift_admin_reporting.income_rows as
select e.*,case when service='swiftride' then gross_cents when service in('delivery','courier') then case when earned_cents is not null then earned_cents+(select round(o.runner_pay*100)::bigint from public.orders o where o.order_id=substring(e.event_id from 5)) end else earned_cents end service_revenue_cents from swift_admin_reporting.income_events e;
revoke all on swift_admin_reporting.income_rows from public,anon,authenticated;
create or replace function public.swift_admin_income(p_zone text default null,p_from date default null,p_to date default null,p_service text default null,p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare z text:=public.swift_admin_effective_zone(p_zone);result jsonb;from_at timestamptz;to_at timestamptz;
begin
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'Start date must come before the end date';end if;
 from_at:=p_from::timestamp at time zone 'America/Belize';to_at:=(p_to+1)::timestamp at time zone 'America/Belize';
 with filtered as(select * from swift_admin_reporting.income_rows where (z is null or zone_id=z) and (from_at is null or occurred_at>=from_at) and (to_at is null or occurred_at<to_at)),
 grouped as(select service,count(*) entries,coalesce(sum(gross_cents),0) gross_cents,coalesce(sum(service_revenue_cents),0) revenue_cents,coalesce(sum(worker_cents),0) worker_cents,coalesce(sum(earned_cents),0) earned_cents,coalesce(sum(collected_cents),0) collected_cents,count(*) filter(where missing_data) missing_count from filtered group by service)
 select jsonb_build_object('zone_id',z,'from',p_from,'to',p_to,'updated_at',now(),'services',coalesce((select jsonb_agg(to_jsonb(g) order by service) from grouped g),'[]'),
 'totals',(select jsonb_build_object('earned_cents',coalesce(sum(earned_cents),0),'collected_cents',coalesce(sum(collected_cents),0),'gross_cents',coalesce(sum(gross_cents),0),'revenue_cents',coalesce(sum(service_revenue_cents),0),'worker_cents',coalesce(sum(worker_cents),0),'missing_count',count(*) filter(where missing_data),'unassigned_count',count(*) filter(where zone_id is null)) from filtered),
 'entries',coalesce((select jsonb_agg(to_jsonb(d) order by occurred_at desc,event_id) from(select * from filtered where p_service is null or service=p_service order by occurred_at desc,event_id limit 25 offset greatest(0,least(coalesce(p_offset,0),100000)))d),'[]'),
 'more',(select count(*)>greatest(0,coalesce(p_offset,0))+25 from filtered where p_service is null or service=p_service)) into result;return result;
end $$;

