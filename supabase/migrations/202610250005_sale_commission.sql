begin;
create table public.swift_merchant_commission_accounts(category text primary key,active boolean not null default false,started_at timestamptz,updated_at timestamptz not null default now(),updated_by uuid);
create table public.swift_sale_commissions(id uuid primary key default gen_random_uuid(),category text not null,source_kind text not null check(source_kind in('order','direct','swiftpay')),source_key text not null unique,source_group text not null,gross_cents bigint not null,fee_cents bigint not null,sale_at timestamptz not null default now(),metadata jsonb not null default '{}');
create index on public.swift_sale_commissions(category,sale_at);
create table public.swift_commission_receipts(id uuid primary key,category text not null,amount_cents bigint not null check(amount_cents>0),reference text not null,created_at timestamptz not null default now(),created_by uuid not null);
create table public.swift_launch_accounting_config(id boolean primary key default true check(id),started_at timestamptz not null default clock_timestamp());
insert into public.swift_launch_accounting_config(id) values(true);
insert into public.swift_merchant_commission_accounts(category) select category from public.stores union select category from public.merchant_members;
alter table public.swift_merchant_commission_accounts enable row level security;
alter table public.swift_sale_commissions enable row level security;
alter table public.swift_commission_receipts enable row level security;
alter table public.swift_launch_accounting_config enable row level security;
revoke all on public.swift_merchant_commission_accounts,public.swift_sale_commissions,public.swift_commission_receipts,public.swift_launch_accounting_config from public,anon,authenticated;
alter table public.swift_merchant_order_parts add column commission_eligible boolean not null default false;
alter table public.swift_merchant_order_parts add column commission_quote_cents bigint not null default 0;
alter table public.swift_merchant_entries add column recording_enabled boolean not null default false;
alter table public.swift_merchant_entries add column commission_eligible boolean not null default false;
-- Stop the old flat charge immediately. New orders only carry a commission quote when enrolled.
create or replace function public.swift_merchant_charge_placed() returns trigger language plpgsql security definer set search_path='' as $$begin return new;end$$;
create or replace function public.swift_merchant_billing_quote() returns trigger language plpgsql security definer set search_path='' as $$begin
 new.commission_eligible:=coalesce((select active and new.created_at>=started_at from public.swift_merchant_commission_accounts where category=new.category),false);
 new.billing_plan:=case when new.commission_eligible then 'commission10' else 'free' end;
 new.billing_order_cents:=0;new.commission_quote_cents:=case when new.commission_eligible then round(new.item_total*100*0.10)::bigint else 0 end;return new;
end$$;
create or replace function public.swift_merchant_billing_complete() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.phase='delivered' and old.phase is distinct from 'delivered' then
 update public.swift_merchant_order_parts set completed_at=coalesce(completed_at,now()) where tracking_id=new.id and decision<>'rejected';
 insert into public.swift_sale_commissions(category,source_kind,source_key,source_group,gross_cents,fee_cents,sale_at,metadata)
 select category,'order','order:'||tracking_id||':'||category,'order:'||tracking_id||':'||category,round(item_total*100)::bigint,commission_quote_cents,completed_at,jsonb_build_object('tracking_id',tracking_id)
 from public.swift_merchant_order_parts where tracking_id=new.id and commission_eligible and decision<>'rejected' on conflict(source_key) do nothing;
 end if;return new;end$$;
create function public.swift_commission_entry_quote() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='INSERT' then
 new.recording_enabled:=coalesce((select active from public.swift_merchant_commission_accounts where category=new.category),false);
 if not new.recording_enabled then raise exception 'Management starts after SwiftShop activates your store';end if;
 new.commission_eligible:=new.recording_enabled and new.kind='direct_order' and new.entry_date>=(select (started_at at time zone 'America/Belize')::date from public.swift_merchant_commission_accounts where category=new.category);
 else new.recording_enabled:=old.recording_enabled;new.commission_eligible:=old.commission_eligible;end if;return new;end$$;
create trigger swift_commission_entry_quote before insert or update on public.swift_merchant_entries for each row execute function public.swift_commission_entry_quote();
create function public.swift_commission_entry_record() returns trigger language plpgsql security definer set search_path='' as $$declare gross bigint;fee bigint;previous_gross bigint;previous_fee bigint;begin
 if not new.commission_eligible then return new;end if;
 perform pg_advisory_xact_lock(hashtext('commission:'||new.category));
 gross:=case when new.voided or new.kind<>'direct_order' then 0 else round(new.amount*100)::bigint end;fee:=round(gross*0.10);
 select coalesce(sum(gross_cents),0),coalesce(sum(fee_cents),0) into previous_gross,previous_fee from public.swift_sale_commissions where source_group='direct:'||new.id;
 if gross<>previous_gross or fee<>previous_fee then
 insert into public.swift_sale_commissions(category,source_kind,source_key,source_group,gross_cents,fee_cents,sale_at,metadata) values(new.category,'direct','direct:'||new.id||':'||new.version,'direct:'||new.id,gross-previous_gross,fee-previous_fee,now(),jsonb_build_object('entry_id',new.id,'reference',new.reference)) on conflict(source_key) do nothing;
 end if;return new;end$$;
create trigger swift_commission_entry_record after insert or update on public.swift_merchant_entries for each row execute function public.swift_commission_entry_record();
create function public.swift_commission_store_payment() returns trigger language plpgsql security definer set search_path='' as $$begin
 if coalesce((select active and new.created_at>=started_at from public.swift_merchant_commission_accounts where category=new.category),false) then
 insert into public.swift_sale_commissions(category,source_kind,source_key,source_group,gross_cents,fee_cents,sale_at,metadata) values(new.category,'swiftpay','swiftpay:'||new.request_id,'swiftpay:'||new.request_id,new.amount_cents,round(new.amount_cents*0.10),new.created_at,jsonb_build_object('receipt_id',new.request_id)) on conflict(source_key) do nothing;
 end if;return new;end$$;
create trigger swift_commission_store_payment after insert on public.swiftpay_store_receipts for each row execute function public.swift_commission_store_payment();
create function public.swift_commission_report(p_category text) returns jsonb language plpgsql security definer set search_path='' as $$declare fees bigint;paid bigint;ws date:=date_trunc('week',now() at time zone 'America/Belize')::date;a public.swift_merchant_commission_accounts;begin
 if not public.swift_merchant_access(p_category,'orders') then raise exception 'Store access required' using errcode='42501';end if;
 select * into a from public.swift_merchant_commission_accounts where category=p_category;
 select coalesce(sum(fee_cents),0) into fees from public.swift_sale_commissions where category=p_category;
 select coalesce(sum(amount_cents),0) into paid from public.swift_commission_receipts where category=p_category;
 return jsonb_build_object('active',coalesce(a.active,false),'started_at',a.started_at,'rate',0.10,'commission_percent',10,'balance',greatest(fees-paid,0)/100.0,'credit',greatest(paid-fees,0)/100.0,'collected',paid/100.0,'week_start',ws,'due_on',ws+6,'is_sunday',extract(isodow from (now() at time zone 'America/Belize'))=7,
 'pending',coalesce((select sum(amount_cents)/100.0 from public.swift_merchant_payment_claims where category=p_category and status='pending' and created_at>=(select started_at from public.swift_launch_accounting_config where id)),0),
 'this_week',coalesce((select sum(fee_cents)/100.0 from public.swift_sale_commissions where category=p_category and (sale_at at time zone 'America/Belize')::date between ws and ws+6),0),
 'weeks',coalesce((select jsonb_agg(to_jsonb(w) order by week_start desc) from(select date_trunc('week',sale_at at time zone 'America/Belize')::date week_start,date_trunc('week',sale_at at time zone 'America/Belize')::date+6 due_on,count(distinct source_group) orders,sum(fee_cents)/100.0 fees,sum(fee_cents)/100.0 outstanding from public.swift_sale_commissions where category=p_category group by 1,2)w),'[]'::jsonb),
 'orders',coalesce((select jsonb_agg(jsonb_build_object('id',id,'date',sale_at,'kind',source_kind,'gross',gross_cents/100.0,'fee',fee_cents/100.0,'outstanding',null) order by sale_at desc) from public.swift_sale_commissions where category=p_category),'[]'::jsonb),
 'history',coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount',amount_cents/100.0,'reference',reference,'status',status,'created_at',created_at,'reviewed_at',reviewed_at,'note',note) order by created_at desc) from public.swift_merchant_payment_claims where category=p_category and created_at>=(select started_at from public.swift_launch_accounting_config where id)),'[]'::jsonb));end$$;
revoke all on function public.swift_commission_report(text) from public,anon,authenticated;
create or replace function public.swift_merchant_order_fees(p_category text,p_action text default 'report',p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$declare report jsonb;cid uuid;amount bigint;ref text;begin
 report:=public.swift_commission_report(p_category);
 if p_action='submit' then
 perform pg_advisory_xact_lock(hashtext('commission:'||p_category));report:=public.swift_commission_report(p_category);
 cid:=(p_data->>'id')::uuid;amount:=round((p_data->>'amount')::numeric*100);ref:=trim(p_data->>'reference');
 if cid is null or amount is null or amount<=0 or ref is null or length(ref) not between 1 and 100 then raise exception 'Enter a valid payment amount and reference';end if;
 if exists(select 1 from public.swift_merchant_payment_claims where id=cid) then
 if not exists(select 1 from public.swift_merchant_payment_claims where id=cid and category=p_category and amount_cents=amount and reference=ref) then raise exception 'Payment reference conflict';end if;
 else
 if amount>(report->>'balance')::numeric*100 then raise exception 'Payment exceeds commission owed';end if;
 if (report->>'pending')::numeric>0 then raise exception 'Your previous payment is awaiting confirmation';end if;
 insert into public.swift_merchant_payment_claims(id,category,amount_cents,reference,created_by) values(cid,p_category,amount,ref,auth.uid());end if;
 elsif p_action<>'report' then raise exception 'Invalid action';end if;return public.swift_commission_report(p_category);end$$;
create or replace function public.swift_merchant_billing_admin(p_category text default null,p_action text default 'report',p_data jsonb default '{}',p_from date default current_date-30,p_to date default current_date) returns jsonb language plpgsql security definer set search_path='' as $$declare cat text;r public.swift_merchant_payment_claims;report jsonb;begin
 if auth.uid() is null or public.swift_worker_kind() is distinct from 'admin' then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_action in('activate','deactivate') then
 cat:=coalesce(p_data->>'category',p_category);if not exists(select 1 from public.stores where category=cat) and not exists(select 1 from public.merchant_members where category=cat) then raise exception 'Store not found';end if;
 perform pg_advisory_xact_lock(hashtext('commission:'||cat));
 insert into public.swift_merchant_commission_accounts(category,active,started_at,updated_by) values(cat,p_action='activate',case when p_action='activate' then clock_timestamp() end,auth.uid()) on conflict(category) do update set active=excluded.active,started_at=case when excluded.active then coalesce(swift_merchant_commission_accounts.started_at,excluded.started_at) else swift_merchant_commission_accounts.started_at end,updated_at=now(),updated_by=auth.uid();
 insert into public.swift_merchant_audit(category,actor,action,detail) values(cat,auth.uid(),'commission_'||p_action,jsonb_build_object('rate_percent',10));
 elsif p_action in('confirm','reject') then
 select * into r from public.swift_merchant_payment_claims where id=(p_data->>'id')::uuid;
 if not found or r.created_at<(select started_at from public.swift_launch_accounting_config where id) then raise exception 'Payment not found';end if;
 perform pg_advisory_xact_lock(hashtext('commission:'||r.category));select * into r from public.swift_merchant_payment_claims where id=r.id for update;
 if r.status='pending' then
 if p_action='confirm' then report:=public.swift_commission_report(r.category);if r.amount_cents>(report->>'balance')::numeric*100 then raise exception 'Payment exceeds commission owed';end if;
 insert into public.swift_commission_receipts(id,category,amount_cents,reference,created_by) values(r.id,r.category,r.amount_cents,r.reference,auth.uid()) on conflict(id) do nothing;end if;
 update public.swift_merchant_payment_claims set status=case when p_action='confirm' then 'confirmed' else 'rejected' end,reviewed_at=now(),reviewed_by=auth.uid(),note=left(coalesce(p_data->>'note',''),500) where id=r.id;
 elsif r.status<>(case when p_action='confirm' then 'confirmed' else 'rejected' end) then raise exception 'Payment already reviewed';end if;
 elsif p_action<>'report' then raise exception 'Invalid action';end if;
 return jsonb_build_object('billing_enabled',true,'stores',coalesce((select jsonb_agg(jsonb_build_object('category',s.category,'report',public.swift_commission_report(s.category)) order by s.category) from(select category from public.stores union select category from public.merchant_members)s),'[]'::jsonb),
 'claims',coalesce((select jsonb_agg(to_jsonb(c) order by created_at) from public.swift_merchant_payment_claims c where status='pending' and created_at>=(select started_at from public.swift_launch_accounting_config where id)),'[]'::jsonb),
 'daily',coalesce((select jsonb_agg(to_jsonb(x) order by day desc) from(select (sale_at at time zone 'America/Belize')::date as day,count(distinct source_group) orders,sum(fee_cents)/100.0 revenue from public.swift_sale_commissions group by 1)x),'[]'::jsonb),
 'weekly',coalesce((select jsonb_agg(to_jsonb(x) order by week_start desc) from(select date_trunc('week',sale_at at time zone 'America/Belize')::date week_start,count(distinct source_group) orders,sum(fee_cents)/100.0 revenue from public.swift_sale_commissions group by 1)x),'[]'::jsonb));end$$;
-- Trigger helpers cannot be called by clients.
revoke all on function public.swift_commission_entry_quote(),public.swift_commission_entry_record(),public.swift_commission_store_payment() from public,anon,authenticated;
create or replace function public.swift_merchant_sales_report_20261024(p_category text,p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; today date:=(now() at time zone 'America/Belize')::date; week date; gross numeric; direct numeric; extra numeric; fees numeric; subs numeric; charges bigint; paid bigint;
begin
 if not public.swift_merchant_access(p_category,'orders') then raise exception 'Store access required' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>3660 then raise exception 'Choose a valid date range';end if;
 
 week:=date_trunc('week',today::timestamp)::date;
 select coalesce(sum(p.item_total),0) into gross from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id
 where p.category=p_category and p.commission_eligible and t.phase='delivered' and p.decision<>'rejected' and (coalesce(p.completed_at,t.updated_at) at time zone 'America/Belize')::date between p_from and p_to;
 select coalesce(sum(amount) filter(where kind='direct_order'),0),coalesce(sum(amount) filter(where kind='income'),0) into direct,extra
 from public.swift_merchant_entries where category=p_category and recording_enabled and not voided and entry_date between p_from and p_to;
 fees:=0;subs:=0;charges:=0;paid:=0;
 result:=jsonb_build_object('gross',gross,'direct',direct,'income',extra,'fees',fees,'subscriptions',subs,'revenue',gross+direct+extra-fees-subs,
 'balance',greatest(charges-paid,0)/100.0,'collected',paid/100.0,'next_billing',null,'billing_enabled',false,
 'charges','[]'::jsonb,'receipts','[]'::jsonb,
 'sales',coalesce((select jsonb_agg(to_jsonb(x) order by x.completed_at desc) from(
 select p.tracking_id,p.items,p.item_total,coalesce(p.completed_at,t.updated_at) completed_at,t.snapshot->>'payment' payment,
 0::numeric fee,p.item_total net
 from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id
 where p.category=p_category and p.commission_eligible and t.phase='delivered' and p.decision<>'rejected' and (coalesce(p.completed_at,t.updated_at) at time zone 'America/Belize')::date between p_from and p_to)x),'[]'),
 'top_items',coalesce((select jsonb_agg(to_jsonb(x)) from(
 select i->>'name' name,sum((i->>'quantity')::numeric) quantity,sum((i->>'quantity')::numeric*(i->>'price')::numeric) sales
 from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id cross join lateral jsonb_array_elements(p.items)i
 where p.category=p_category and p.commission_eligible and t.phase='delivered' and p.decision<>'rejected' and (coalesce(p.completed_at,t.updated_at) at time zone 'America/Belize')::date between p_from and p_to
 group by i->>'name' order by quantity desc,name limit 10)x),'[]'),
 'weeks',coalesce((select jsonb_agg(to_jsonb(x) order by x.week_start) from(
 select date_trunc('week',coalesce(p.completed_at,t.updated_at) at time zone 'America/Belize')::date week_start,count(*) orders,sum(p.item_total) sales
 from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id where p.category=p_category and p.commission_eligible and t.phase='delivered' and p.decision<>'rejected'
 and (coalesce(p.completed_at,t.updated_at) at time zone 'America/Belize')::date>=week-7 group by 1)x),'[]'));
 return result;
end $$;


create or replace function public.swift_merchant_billing_report(p_category text,p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$declare r jsonb;c jsonb;fees numeric;qr numeric;sales jsonb;begin
 r:=public.swift_merchant_sales_report_20261024(p_category,p_from,p_to);c:=public.swift_commission_report(p_category);
 select coalesce(sum(fee_cents)/100.0,0),coalesce(sum(gross_cents) filter(where source_kind='swiftpay')/100.0,0) into fees,qr from public.swift_sale_commissions where category=p_category and (sale_at at time zone 'America/Belize')::date between p_from and p_to;
 select coalesce(jsonb_agg(x||jsonb_build_object('fee',round((x->>'item_total')::numeric*.10,2),'net',(x->>'item_total')::numeric-round((x->>'item_total')::numeric*.10,2))),'[]'::jsonb) into sales from jsonb_array_elements(r->'sales')x;
 sales:=sales||coalesce((select jsonb_agg(jsonb_build_object('tracking_id',metadata->>'receipt_id','items',jsonb_build_array(jsonb_build_object('name','SwiftPay in-store sale','quantity',1,'price',gross_cents/100.0)),'item_total',gross_cents/100.0,'completed_at',sale_at,'payment','SwiftPay','fee',fee_cents/100.0,'net',(gross_cents-fee_cents)/100.0)) from public.swift_sale_commissions where category=p_category and source_kind='swiftpay' and (sale_at at time zone 'America/Belize')::date between p_from and p_to),'[]'::jsonb);
 return r||jsonb_build_object('gross',(r->>'gross')::numeric+qr,'fees',fees,'revenue',(r->>'gross')::numeric+qr+(r->>'direct')::numeric+(r->>'income')::numeric-fees,'balance',c->'balance','collected',c->'collected','billing_enabled',c->'active','order_fees',c,'sales',sales);
end$$;
notify pgrst,'reload schema';
commit;


