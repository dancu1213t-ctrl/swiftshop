begin;
-- Internal plan key `pro` remains compatible with existing policies; its name is Plus.
create table if not exists public.swift_merchant_billing_config(id boolean primary key default true check(id), starts_at timestamptz not null default now());
insert into public.swift_merchant_billing_config(id) values(true) on conflict do nothing;
create table if not exists public.swift_merchant_rates(plan text primary key, name text not null, weekly_cents integer not null check(weekly_cents>=0), order_cents integer not null check(order_cents>=0));
insert into public.swift_merchant_rates values('free','No paid plan',0,0),('basic','Basic',650,50),('pro','Plus',1000,35),('premium','Premium',1500,20) on conflict(plan) do update set name=excluded.name,weekly_cents=excluded.weekly_cents,order_cents=excluded.order_cents;
create table if not exists public.swift_merchant_billing_cycles(category text primary key, next_at timestamptz not null);
create table if not exists public.swift_merchant_charges(
 id uuid primary key default gen_random_uuid(), category text not null, kind text not null check(kind in('subscription','order')),
 source_key text not null unique, tracking_id uuid references public.customer_order_tracking(id), plan text not null,
 amount_cents bigint not null check(amount_cents>=0), gross_cents bigint not null default 0 check(gross_cents>=0),
 incurred_at timestamptz not null, period_end timestamptz, unique(tracking_id,category));
create table if not exists public.swift_merchant_receipts(
 id uuid primary key, category text not null, kind text not null check(kind in('payment','withheld')),
 reference text not null check(length(reference) between 1 and 100), amount_cents bigint not null check(amount_cents>0),
 received_at timestamptz not null default now(), created_by uuid not null, unique(category,reference));
create table if not exists public.swift_merchant_charge_allocations(
 receipt_id uuid not null references public.swift_merchant_receipts(id), charge_id uuid not null references public.swift_merchant_charges(id),
 amount_cents bigint not null check(amount_cents>0), primary key(receipt_id,charge_id));
alter table public.swift_merchant_order_parts add column if not exists billing_plan text;
alter table public.swift_merchant_order_parts add column if not exists billing_order_cents integer;
alter table public.swift_merchant_order_parts add column if not exists completed_at timestamptz;
-- Old completed receipts remain uncharged. Open orders keep the rate selected at deployment.
update public.swift_merchant_order_parts p set billing_plan=coalesce(s.plan,'free'),billing_order_cents=coalesce(r.order_cents,0)
 from public.swift_merchant_plans s join public.swift_merchant_rates r on r.plan=s.plan where s.category=p.category and p.billing_plan is null;
update public.swift_merchant_order_parts set billing_plan='free',billing_order_cents=0 where billing_plan is null;
alter table public.swift_merchant_entries drop constraint if exists swift_merchant_entries_kind_check;
alter table public.swift_merchant_entries add constraint swift_merchant_entries_kind_check check(kind in('income','expense','loss','refund','direct_order'));

create or replace function public.swift_merchant_billing_tick() returns void language plpgsql security definer set search_path='' as $$
declare p record; c timestamptz; finish timestamptz;
begin
 for p in select s.category,s.plan,r.weekly_cents from public.swift_merchant_plans s join public.swift_merchant_rates r using(plan) order by s.category loop
  perform pg_advisory_xact_lock(hashtext('merchant-billing:'||p.category));
  insert into public.swift_merchant_billing_cycles(category,next_at) values(p.category,now()) on conflict do nothing;
  select next_at into c from public.swift_merchant_billing_cycles where category=p.category for update;
  if p.plan='free' then update public.swift_merchant_billing_cycles set next_at=now() where category=p.category;continue;end if;
  while c<=now() loop
   finish:=c+interval '7 days';
   insert into public.swift_merchant_charges(category,kind,source_key,plan,amount_cents,incurred_at,period_end)
    values(p.category,'subscription','week:'||p.category||':'||extract(epoch from c)::text,p.plan,p.weekly_cents,c,finish) on conflict do nothing;
   c:=finish;
  end loop;
  update public.swift_merchant_billing_cycles set next_at=c where category=p.category;
 end loop;
end $$;
create or replace function public.swift_merchant_billing_plan_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtext('merchant-billing:'||new.category));
 -- Changes apply to new order quotes immediately; existing seven-day invoices remain unchanged.
 if tg_op='INSERT' or old.plan='free' then
  insert into public.swift_merchant_billing_cycles(category,next_at) values(new.category,now()) on conflict(category) do update set next_at=excluded.next_at;
 end if;
 return new;
end $$;
drop trigger if exists swift_billing_plan_change on public.swift_merchant_plans;
create trigger swift_billing_plan_change after insert or update of plan on public.swift_merchant_plans for each row execute function public.swift_merchant_billing_plan_change();
create or replace function public.swift_merchant_billing_quote() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select p.plan,r.order_cents into new.billing_plan,new.billing_order_cents from public.swift_merchant_plans p join public.swift_merchant_rates r using(plan) where p.category=new.category;
 new.billing_plan:=coalesce(new.billing_plan,'free');new.billing_order_cents:=coalesce(new.billing_order_cents,0);return new;
end $$;
drop trigger if exists swift_billing_quote on public.swift_merchant_order_parts;
create trigger swift_billing_quote before insert on public.swift_merchant_order_parts for each row execute function public.swift_merchant_billing_quote();
create or replace function public.swift_merchant_billing_complete() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.phase='delivered' and old.phase is distinct from 'delivered' then
  update public.swift_merchant_order_parts set completed_at=coalesce(completed_at,now()) where tracking_id=new.id and decision<>'rejected';
  insert into public.swift_merchant_charges(category,kind,source_key,tracking_id,plan,amount_cents,gross_cents,incurred_at)
   select p.category,'order','order:'||p.tracking_id||':'||p.category,p.tracking_id,p.billing_plan,
    least(p.billing_order_cents,round(p.item_total*100)::bigint),round(p.item_total*100)::bigint,p.completed_at
   from public.swift_merchant_order_parts p where p.tracking_id=new.id and p.decision<>'rejected' and p.billing_order_cents>0
   and new.created_at >= (select starts_at from public.swift_merchant_billing_config where id)
   on conflict do nothing;
 end if;return new;
end $$;
drop trigger if exists swift_billing_complete on public.customer_order_tracking;
create trigger swift_billing_complete after update of phase on public.customer_order_tracking for each row execute function public.swift_merchant_billing_complete();

create or replace function public.swift_merchant_plan(p_category text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.swift_merchant_rates; a boolean;
begin
 if not public.swift_merchant_access(p_category,'inventory') then raise exception 'Store access required' using errcode='42501';end if;
 select rates.* into r from public.swift_merchant_rates rates where rates.plan=coalesce((select plan from public.swift_merchant_plans where category=p_category),'free');
 a:=coalesce((select ads_enabled from public.swift_merchant_plans where category=p_category),false);
 return jsonb_build_object('plan',r.plan,'name',r.name,'weekly_price',r.weekly_cents/100.0,'order_fee',r.order_cents/100.0,'ads_enabled',a,
 'revenue',public.swift_merchant_access(p_category,'revenue'),'campaigns',public.swift_merchant_access(p_category,'campaigns'),'admin',coalesce(public.swift_worker_kind()='admin',false));
end $$;
-- Basic merchants also need access to their own complete financial records.
create or replace function public.swift_merchant_access(p_category text,p_feature text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (coalesce(public.swift_worker_kind()='admin',false) or
 (exists(select 1 from public.merchant_members where user_id=auth.uid() and category=p_category) and
 case p_feature when 'inventory' then true when 'appearance' then true when 'orders' then true
 when 'revenue' then coalesce((select plan in('basic','pro','premium') from public.swift_merchant_plans where category=p_category),false)
 when 'campaigns' then coalesce((select plan in('pro','premium') from public.swift_merchant_plans where category=p_category),false)
 when 'delivery' then coalesce((select plan='premium' from public.swift_merchant_plans where category=p_category),false) else false end));
$$;

-- Keep the existing entry API and audit trail; add direct sales without changing payment balances.
do $patch$ declare s text;begin
 s:=pg_get_functiondef('public.swift_merchant_finance(text,text,jsonb,date,date)'::regprocedure);
 s:=replace(s,$old$('income','expense','loss','refund')$old$,$new$('income','expense','loss','refund','direct_order')$new$);
 s:=replace(s,'select * into r from public.swift_merchant_entries where id=eid for update;','perform pg_advisory_xact_lock(hashtext(''merchant-entry:''||eid::text)); select * into r from public.swift_merchant_entries where id=eid for update;');
s:=replace(s,'(p_data->>''entry_date'')::date>current_date','(p_data->>''entry_date'')::date>(now() at time zone ''America/Belize'')::date');
s:=replace(s,'Approved Pro or Premium plan required to edit','Approved merchant plan required to edit');
 execute s;
end $patch$;

create or replace function public.swift_merchant_billing_report(p_category text,p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; today date:=(now() at time zone 'America/Belize')::date; week date; gross numeric; direct numeric; extra numeric; fees numeric; subs numeric; charges bigint; paid bigint;
begin
 if not public.swift_merchant_access(p_category,'orders') then raise exception 'Store access required' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>3660 then raise exception 'Choose a valid date range';end if;
 perform public.swift_merchant_billing_tick();
 week:=date_trunc('week',today::timestamp)::date;
 select coalesce(sum(p.item_total),0) into gross from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id
 where p.category=p_category and t.phase='delivered' and p.decision<>'rejected' and (coalesce(p.completed_at,t.updated_at) at time zone 'America/Belize')::date between p_from and p_to;
 select coalesce(sum(amount) filter(where kind='direct_order'),0),coalesce(sum(amount) filter(where kind='income'),0) into direct,extra
 from public.swift_merchant_entries where category=p_category and not voided and entry_date between p_from and p_to;
 select coalesce(sum(amount_cents) filter(where kind='order'),0)/100.0,coalesce(sum(amount_cents) filter(where kind='subscription'),0)/100.0 into fees,subs
 from public.swift_merchant_charges where category=p_category and (incurred_at at time zone 'America/Belize')::date between p_from and p_to;
 select coalesce(sum(amount_cents),0) into charges from public.swift_merchant_charges where category=p_category;
 select coalesce(sum(amount_cents),0) into paid from public.swift_merchant_receipts where category=p_category;
 result:=jsonb_build_object('gross',gross,'direct',direct,'income',extra,'fees',fees,'subscriptions',subs,'revenue',gross+direct+extra-fees-subs,
 'balance',greatest(charges-paid,0)/100.0,'collected',paid/100.0,'next_billing',(select next_at from public.swift_merchant_billing_cycles where category=p_category),
 'charges',coalesce((select jsonb_agg(to_jsonb(x) order by x.incurred_at desc) from (
  select c.*,c.amount_cents-coalesce((select sum(a.amount_cents) from public.swift_merchant_charge_allocations a where a.charge_id=c.id),0) outstanding_cents
  from public.swift_merchant_charges c where c.category=p_category and (c.incurred_at at time zone 'America/Belize')::date between p_from and p_to)x),'[]'),
 'receipts',coalesce((select jsonb_agg(to_jsonb(x) order by x.received_at desc) from(select id,kind,reference,amount_cents,received_at from public.swift_merchant_receipts where category=p_category and (received_at at time zone 'America/Belize')::date between p_from and p_to)x),'[]'),
 'sales',coalesce((select jsonb_agg(to_jsonb(x) order by x.completed_at desc) from(
 select p.tracking_id,p.items,p.item_total,coalesce(p.completed_at,t.updated_at) completed_at,t.snapshot->>'payment' payment,
 coalesce(c.amount_cents,0)/100.0 fee,p.item_total-coalesce(c.amount_cents,0)/100.0 net
 from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id left join public.swift_merchant_charges c on c.tracking_id=p.tracking_id and c.category=p.category
 where p.category=p_category and t.phase='delivered' and p.decision<>'rejected' and (coalesce(p.completed_at,t.updated_at) at time zone 'America/Belize')::date between p_from and p_to)x),'[]'),
 'top_items',coalesce((select jsonb_agg(to_jsonb(x)) from(
 select i->>'name' name,sum((i->>'quantity')::numeric) quantity,sum((i->>'quantity')::numeric*(i->>'price')::numeric) sales
 from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id cross join lateral jsonb_array_elements(p.items)i
 where p.category=p_category and t.phase='delivered' and p.decision<>'rejected' and (coalesce(p.completed_at,t.updated_at) at time zone 'America/Belize')::date between p_from and p_to
 group by i->>'name' order by quantity desc,name limit 10)x),'[]'),
 'weeks',coalesce((select jsonb_agg(to_jsonb(x) order by x.week_start) from(
 select date_trunc('week',coalesce(p.completed_at,t.updated_at) at time zone 'America/Belize')::date week_start,count(*) orders,sum(p.item_total) sales
 from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id where p.category=p_category and t.phase='delivered' and p.decision<>'rejected'
 and (coalesce(p.completed_at,t.updated_at) at time zone 'America/Belize')::date>=week-7 group by 1)x),'[]'));
 return result;
end $$;

create or replace function public.swift_merchant_billing_admin(p_category text default null,p_action text default 'report',p_data jsonb default '{}',p_from date default current_date-30,p_to date default current_date) returns jsonb language plpgsql security definer set search_path='' as $$
declare rid uuid; amount bigint; remaining bigint; due bigint; take bigint; allocrow record; existing public.swift_merchant_receipts; result jsonb;
begin
 if auth.uid() is null or public.swift_worker_kind() is distinct from 'admin' then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>3660 then raise exception 'Choose a valid date range';end if;
 perform public.swift_merchant_billing_tick();
 if p_action='receipt' then
  if p_category is null or not exists(select 1 from public.stores where category=p_category) then raise exception 'Choose a store';end if;
  perform pg_advisory_xact_lock(hashtext('merchant-billing:'||p_category));
  rid:=(p_data->>'id')::uuid; amount:=round((p_data->>'amount')::numeric*100)::bigint;
  if rid is null or amount is null or amount<=0 or amount>100000000 or (p_data->>'amount')::numeric<>amount/100.0 or p_data->>'kind' not in('payment','withheld') or length(trim(coalesce(p_data->>'reference',''))) not between 1 and 100 then raise exception 'Enter a valid amount, type and reference';end if;
  select * into existing from public.swift_merchant_receipts where id=rid or (category=p_category and reference=trim(p_data->>'reference')) limit 1;
  if found then
   if existing.category<>p_category or existing.amount_cents<>amount or existing.kind<>p_data->>'kind' or existing.reference<>trim(p_data->>'reference') then raise exception 'Receipt already exists with different details';end if;
  else
   select coalesce(sum(c.amount_cents-coalesce((select sum(a.amount_cents) from public.swift_merchant_charge_allocations a where a.charge_id=c.id),0)),0) into due from public.swift_merchant_charges c where c.category=p_category;
   if amount>due then raise exception 'Amount exceeds the outstanding balance';end if;
   insert into public.swift_merchant_receipts(id,category,kind,reference,amount_cents,created_by) values(rid,p_category,p_data->>'kind',trim(p_data->>'reference'),amount,auth.uid());
   remaining:=amount;
   for allocrow in select ch.id,ch.amount_cents-coalesce((select sum(a.amount_cents) from public.swift_merchant_charge_allocations a where a.charge_id=ch.id),0) outstanding from public.swift_merchant_charges ch where ch.category=p_category and (p_data->>'kind'<>'withheld' or ch.kind='order') order by ch.incurred_at,ch.id for update loop
    take:=least(allocrow.outstanding,remaining);if take>0 then insert into public.swift_merchant_charge_allocations values(rid,allocrow.id,take);remaining:=remaining-take;end if;exit when remaining=0;
   end loop;
   if remaining<>0 then raise exception 'Withholding can cover order fees only; record subscription payments separately';end if;
   insert into public.swift_merchant_audit(category,actor,action,detail) values(p_category,auth.uid(),'billing_receipt',jsonb_build_object('id',rid,'amount_cents',amount,'reference',p_data->>'reference','kind',p_data->>'kind'));
  end if;
 elsif p_action<>'report' then raise exception 'Unknown billing action';end if;
 result:=jsonb_build_object('daily',coalesce((select jsonb_agg(to_jsonb(x) order by x.day) from(
 select (incurred_at at time zone 'America/Belize')::date as day,sum(amount_cents) filter(where kind='subscription')/100.0 subscriptions,sum(amount_cents) filter(where kind='order')/100.0 order_fees,sum(amount_cents)/100.0 total
 from public.swift_merchant_charges where (incurred_at at time zone 'America/Belize')::date between p_from and p_to group by 1)x),'[]'),
 'weekly',coalesce((select jsonb_agg(to_jsonb(x) order by x.week) from(
 select date_trunc('week',incurred_at at time zone 'America/Belize')::date week,sum(amount_cents) filter(where kind='subscription')/100.0 subscriptions,sum(amount_cents) filter(where kind='order')/100.0 order_fees,sum(amount_cents)/100.0 total
 from public.swift_merchant_charges where (incurred_at at time zone 'America/Belize')::date between p_from and p_to group by 1)x),'[]'),
 'collected',coalesce((select sum(amount_cents)/100.0 from public.swift_merchant_receipts where (received_at at time zone 'America/Belize')::date between p_from and p_to),0),
 'stores',coalesce((select jsonb_agg(to_jsonb(x) order by x.category) from(
 select s.category,coalesce(p.plan,'free') plan,coalesce((select sum(amount_cents)/100.0 from public.swift_merchant_charges c where c.category=s.category),0) charges,
 coalesce((select sum(amount_cents)/100.0 from public.swift_merchant_receipts r where r.category=s.category),0) collected
 from (select distinct category from public.stores where category is not null)s left join public.swift_merchant_plans p using(category))x),'[]'));
 if p_category is not null then result:=result||jsonb_build_object('store',public.swift_merchant_billing_report(p_category,p_from,p_to));end if;return result;
end $$;

-- All financial tables are private; clients use scoped, authenticated RPCs only.
do $secure$ declare t text;f record;begin
 foreach t in array array['swift_merchant_billing_config','swift_merchant_rates','swift_merchant_billing_cycles','swift_merchant_charges','swift_merchant_receipts','swift_merchant_charge_allocations'] loop
  execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
 for f in select oid::regprocedure signature from pg_proc where pronamespace='public'::regnamespace and proname in('swift_merchant_billing_tick','swift_merchant_billing_plan_change','swift_merchant_billing_quote','swift_merchant_billing_complete','swift_merchant_billing_report','swift_merchant_billing_admin') loop execute 'revoke all on function '||f.signature||' from public,anon,authenticated';end loop;
end $secure$;
grant execute on function public.swift_merchant_billing_report(text,date,date),public.swift_merchant_billing_admin(text,text,jsonb,date,date) to authenticated;
select public.swift_merchant_billing_tick();
select cron.schedule('swift-merchant-weekly-billing','5 * * * *','select public.swift_merchant_billing_tick()') where not exists(select 1 from cron.job where jobname='swift-merchant-weekly-billing');
notify pgrst,'reload schema';
commit;
