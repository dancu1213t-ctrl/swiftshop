begin;
create table if not exists public.swift_app_health_daily(day date not null,portal text not null,build text not null,reports bigint not null default 0,errors bigint not null default 0,lcp_good bigint not null default 0,lcp_slow bigint not null default 0,primary key(day,portal,build));
create table if not exists public.swift_app_health_rate(fingerprint text primary key,last_at timestamptz not null);
alter table public.swift_app_health_daily enable row level security;alter table public.swift_app_health_rate enable row level security;
revoke all on public.swift_app_health_daily,public.swift_app_health_rate from public,anon,authenticated;
create or replace function public.swift_app_health(p_portal text,p_build text,p_errors integer,p_lcp integer default null) returns void language plpgsql security definer set search_path='' as $$
declare key text;previous timestamptz;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 if p_portal is null or p_portal not in('customer','merchant','runner') or p_build is null or p_build !~ '^[a-zA-Z0-9._-]{1,40}$' or p_errors is null or p_errors not between 0 and 20 or(p_lcp is not null and p_lcp not between 0 and 60000) then raise exception 'Invalid health signal';end if;
 key:=md5(auth.uid()::text||current_date::text||p_portal);perform pg_advisory_xact_lock(hashtext(key));
 select last_at into previous from public.swift_app_health_rate where fingerprint=key;if previous>now()-interval '3 minutes' then return;end if;
 insert into public.swift_app_health_rate values(key,now()) on conflict(fingerprint) do update set last_at=excluded.last_at;
 insert into public.swift_app_health_daily(day,portal,build,reports,errors,lcp_good,lcp_slow) values(current_date,p_portal,p_build,1,p_errors,case when p_lcp<=2500 then 1 else 0 end,case when p_lcp>2500 then 1 else 0 end)
 on conflict(day,portal,build) do update set reports=swift_app_health_daily.reports+1,errors=swift_app_health_daily.errors+excluded.errors,lcp_good=swift_app_health_daily.lcp_good+excluded.lcp_good,lcp_slow=swift_app_health_daily.lcp_slow+excluded.lcp_slow;
 delete from public.swift_app_health_rate where last_at<now()-interval '2 days';
end $$;
revoke all on function public.swift_app_health(text,text,integer,integer) from public,anon;grant execute on function public.swift_app_health(text,text,integer,integer) to authenticated;
create or replace function public.swift_app_health_report() returns jsonb language plpgsql security definer set search_path='' as $$
begin perform public.swift_admin_session();return coalesce((select jsonb_agg(to_jsonb(r) order by day desc,portal) from(select * from public.swift_app_health_daily where day>=current_date-7 order by day desc,portal limit 100)r),'[]'::jsonb);end $$;
revoke all on function public.swift_app_health_report() from public,anon;grant execute on function public.swift_app_health_report() to authenticated;
notify pgrst,'reload schema';commit;
