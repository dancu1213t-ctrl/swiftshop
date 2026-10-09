begin;
create table if not exists public.swift_merchant_requests(id uuid primary key default gen_random_uuid(),category text not null,plan text not null check(plan in('free','basic','pro','premium')),status text not null default 'pending' check(status in('pending','approved','declined')),created_by uuid not null,created_at timestamptz not null default now(),reviewed_by uuid,reviewed_at timestamptz,note text not null default '');
create unique index if not exists swift_merchant_one_pending on public.swift_merchant_requests(category) where status='pending';
create table if not exists public.swift_merchant_order_parts(tracking_id uuid not null references public.customer_order_tracking(id) on delete cascade,category text not null,items jsonb not null,item_total numeric(14,2) not null check(item_total>=0),decision text not null default 'pending' check(decision in('pending','accepted','rejected')),reason text not null default '',review_needed boolean not null default false,decision_by uuid,decision_at timestamptz,created_at timestamptz not null default now(),primary key(tracking_id,category));
create table if not exists public.swift_merchant_entries(id uuid primary key default gen_random_uuid(),category text not null,kind text not null check(kind in('income','expense','loss','refund')),amount numeric(14,2) not null check(amount>0 and amount<=1000000),entry_date date not null default current_date,reference text not null check(length(reference) between 1 and 100),note text not null default '' check(length(note)<=500),version integer not null default 1,voided boolean not null default false,created_by uuid not null,updated_at timestamptz not null default now());
create table if not exists public.swift_merchant_audit(id bigint generated always as identity primary key,category text not null,actor uuid,action text not null,detail jsonb not null,created_at timestamptz not null default now());
create table if not exists public.swift_merchant_delivery(category text primary key,fee numeric(10,2) check(fee>=0 and fee<=1000),updated_by uuid,updated_at timestamptz not null default now());
alter table public.swift_merchant_requests enable row level security;
alter table public.swift_merchant_order_parts enable row level security;
alter table public.swift_merchant_entries enable row level security;
alter table public.swift_merchant_audit enable row level security;
alter table public.swift_merchant_delivery enable row level security;
revoke all on public.swift_merchant_requests,public.swift_merchant_order_parts,public.swift_merchant_entries,public.swift_merchant_audit,public.swift_merchant_delivery from public,anon,authenticated;
create or replace function public.swift_merchant_access(p_category text,p_feature text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (coalesce(public.swift_worker_kind()='admin',false) or (exists(select 1 from public.merchant_members where user_id=auth.uid() and category=p_category) and case p_feature when 'inventory' then true when 'appearance' then true when 'orders' then true when 'revenue' then coalesce((select plan in('pro','premium') from public.swift_merchant_plans where category=p_category),false) when 'campaigns' then coalesce((select plan='premium' from public.swift_merchant_plans where category=p_category),false) when 'delivery' then coalesce((select plan='premium' from public.swift_merchant_plans where category=p_category),false) else false end));
$$;
create or replace function public.swift_merchant_capture_parts() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if jsonb_typeof(new.snapshot->'items')='array' then
 insert into public.swift_merchant_order_parts(tracking_id,category,items,item_total,created_at)
 select new.id,i->>'category',jsonb_agg(i),round(sum((i->>'price')::numeric*(i->>'quantity')::numeric),2),new.created_at from jsonb_array_elements(new.snapshot->'items') i
 where exists(select 1 from public.stores s where s.category=i->>'category') and coalesce(i->>'price','') ~ '^[0-9]+([.][0-9]+)?$' and coalesce(i->>'quantity','') ~ '^[0-9]+$' and (i->>'quantity')::numeric>0 group by i->>'category' on conflict do nothing;
 end if;return new;
end $$;
drop trigger if exists swift_merchant_capture on public.customer_order_tracking;
create trigger swift_merchant_capture after insert on public.customer_order_tracking for each row execute function public.swift_merchant_capture_parts();
-- Historical receipts preserve the original checkout prices and cannot be counted twice.
insert into public.swift_merchant_order_parts(tracking_id,category,items,item_total,created_at)
select t.id,i->>'category',jsonb_agg(i),round(sum((i->>'price')::numeric*(i->>'quantity')::numeric),2),t.created_at from public.customer_order_tracking t cross join lateral jsonb_array_elements(case when jsonb_typeof(t.snapshot->'items')='array' then t.snapshot->'items' else '[]'::jsonb end) i
where exists(select 1 from public.stores s where s.category=i->>'category') and coalesce(i->>'price','') ~ '^[0-9]+([.][0-9]+)?$' and coalesce(i->>'quantity','') ~ '^[0-9]+$' and (i->>'quantity')::numeric>0 group by t.id,i->>'category' on conflict do nothing;
create or replace function public.swift_merchant_request(p_category text,p_plan text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.swift_merchant_requests;
begin
 if not public.swift_merchant_access(p_category,'inventory') then raise exception 'Store access required' using errcode='42501';end if;
 if p_plan is not null then
 if p_plan not in('free','basic','pro','premium') then raise exception 'Invalid plan';end if;
 if coalesce((select plan from public.swift_merchant_plans where category=p_category),'free')=p_plan then raise exception 'This is already your current plan';end if;
 insert into public.swift_merchant_requests(category,plan,created_by) values(p_category,p_plan,auth.uid()) on conflict(category) where status='pending' do update set plan=excluded.plan,created_by=excluded.created_by,created_at=now() returning * into r;
 insert into public.swift_merchant_audit(category,actor,action,detail) values(p_category,auth.uid(),'plan_requested',jsonb_build_object('id',r.id,'plan',p_plan));
 end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(select * from public.swift_merchant_requests where category=p_category order by created_at desc limit 20)x),'[]');
end $$;
create or replace function public.swift_merchant_requests_admin(p_action text default 'list',p_id uuid default null,p_note text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.swift_merchant_requests;
begin
 if auth.uid() is null or public.swift_worker_kind() is distinct from 'admin' then raise exception 'Administrator access required' using errcode='42501';end if;
 if p_action in('approve','decline') then
 select * into r from public.swift_merchant_requests where id=p_id for update;
 if not found or r.status<>'pending' then raise exception 'Request is no longer pending';end if;
 if p_action='approve' then perform public.swift_merchant_plan_admin(r.category,r.plan);end if;
 update public.swift_merchant_requests set status=case p_action when 'approve' then 'approved' else 'declined' end,reviewed_by=auth.uid(),reviewed_at=now(),note=left(coalesce(p_note,''),500) where id=p_id;
 insert into public.swift_merchant_audit(category,actor,action,detail) values(r.category,auth.uid(),'plan_'||p_action,jsonb_build_object('id',p_id,'plan',r.plan));
 elsif p_action<>'list' then raise exception 'Invalid action';end if;
 return jsonb_build_object('plans',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.swift_merchant_requests order by created_at desc limit 200)x),'[]'),'rejections',coalesce((select jsonb_agg(jsonb_build_object('tracking_id',p.tracking_id,'category',p.category,'items',p.items,'item_total',p.item_total,'reason',p.reason,'created_at',p.decision_at)) from public.swift_merchant_order_parts p where p.review_needed),'[]'));
end $$;
create or replace function public.swift_merchant_orders(p_category text,p_id uuid default null,p_action text default 'list',p_reason text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.swift_merchant_order_parts;phase text;
begin
 if not public.swift_merchant_access(p_category,'orders') then raise exception 'Store access required' using errcode='42501';end if;
 if p_action in('accept','reject','review') then
 select * into r from public.swift_merchant_order_parts where tracking_id=p_id and category=p_category for update;
 select t.phase into phase from public.customer_order_tracking t where t.id=p_id;
 if r.tracking_id is null or (p_action<>'review' and phase in('delivered','cancelled')) then raise exception 'Order is unavailable or already finished';end if;
 if p_action='review' then
 if public.swift_worker_kind() is distinct from 'admin' then raise exception 'Dispatch administrator required';end if;
 update public.swift_merchant_order_parts set review_needed=false,reason=reason||' · Dispatch: '||left(coalesce(p_reason,''),300) where tracking_id=p_id and category=p_category;
 else
 if r.decision<>'pending' then raise exception 'This store has already responded';end if;
 if p_action='reject' and length(trim(coalesce(p_reason,'')))<3 then raise exception 'Add a rejection reason';end if;
 update public.swift_merchant_order_parts set decision=case p_action when 'accept' then 'accepted' else 'rejected' end,reason=left(coalesce(p_reason,''),300),review_needed=p_action='reject',decision_by=auth.uid(),decision_at=now() where tracking_id=p_id and category=p_category;
 end if;
 insert into public.swift_merchant_audit(category,actor,action,detail) values(p_category,auth.uid(),'order_'||p_action,jsonb_build_object('id',p_id,'reason',left(coalesce(p_reason,''),300)));
 elsif p_action<>'list' then raise exception 'Invalid action';end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(select p.*,t.phase,t.linked_order_id,t.snapshot->>'payment' payment from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id where p.category=p_category order by p.created_at desc limit 200)x),'[]');
end $$;
create or replace function public.swift_merchant_finance(p_category text,p_action text default 'list',p_data jsonb default '{}',p_from date default current_date-30,p_to date default current_date) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.swift_merchant_entries;eid uuid;result jsonb;
begin
 if not public.swift_merchant_access(p_category,'revenue') then raise exception 'Pro or Premium store access required' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>3660 then raise exception 'Choose a valid date range (maximum 10 years)';end if;
 if p_action in('save','void') then
 eid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
 select * into r from public.swift_merchant_entries where id=eid for update;
 if found and (r.category<>p_category or r.version<>coalesce((p_data->>'version')::integer,0)) then raise exception 'Entry changed or belongs to another store. Refresh first.';end if;
 if p_action='void' then
 if r.id is null then raise exception 'Entry not found';end if;
 update public.swift_merchant_entries set voided=true,version=version+1,updated_at=now() where id=eid;
 else
 if p_data->>'kind' not in('income','expense','loss','refund') or (p_data->>'amount')::numeric<=0 or (p_data->>'entry_date')::date>current_date then raise exception 'Enter a valid type, amount, and date';end if;
 insert into public.swift_merchant_entries(id,category,kind,amount,entry_date,reference,note,created_by) values(eid,p_category,p_data->>'kind',round((p_data->>'amount')::numeric,2),(p_data->>'entry_date')::date,trim(p_data->>'reference'),left(coalesce(p_data->>'note',''),500),auth.uid()) on conflict(id) do update set kind=excluded.kind,amount=excluded.amount,entry_date=excluded.entry_date,reference=excluded.reference,note=excluded.note,version=swift_merchant_entries.version+1,updated_at=now();
 end if;
 insert into public.swift_merchant_audit(category,actor,action,detail) values(p_category,auth.uid(),'entry_'||p_action,jsonb_build_object('before',to_jsonb(r),'after',(select to_jsonb(e) from public.swift_merchant_entries e where id=eid)));
 elsif p_action<>'list' then raise exception 'Invalid action';end if;
 result:=jsonb_build_object('orders',coalesce((select jsonb_agg(to_jsonb(x)) from(select p.tracking_id,p.item_total,p.decision,t.phase,(t.created_at at time zone 'America/Belize')::date entry_date,p.review_needed from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id where p.category=p_category and (t.created_at at time zone 'America/Belize')::date between p_from and p_to order by t.created_at desc)x),'[]'),'entries',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.swift_merchant_entries where category=p_category and entry_date between p_from and p_to order by entry_date desc,updated_at desc)x),'[]'),'legacy',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.merchant_sales where category=p_category and sold_on between p_from and p_to)x),'[]'));
 select result||jsonb_build_object('totals',jsonb_build_object('completed',coalesce((select sum((o->>'item_total')::numeric) from jsonb_array_elements(result->'orders')o where o->>'phase'='delivered' and o->>'decision'<>'rejected'),0),'pending',coalesce((select sum((o->>'item_total')::numeric) from jsonb_array_elements(result->'orders')o where o->>'phase' not in('delivered','cancelled') and o->>'decision'<>'rejected'),0),'income',coalesce((select sum((e->>'amount')::numeric) from jsonb_array_elements(result->'entries')e where e->>'kind'='income' and not (e->>'voided')::boolean),0),'refunds',coalesce((select sum((e->>'amount')::numeric) from jsonb_array_elements(result->'entries')e where e->>'kind'='refund' and not (e->>'voided')::boolean),0),'expenses',coalesce((select sum((e->>'amount')::numeric) from jsonb_array_elements(result->'entries')e where e->>'kind'='expense' and not (e->>'voided')::boolean),0),'losses',coalesce((select sum((e->>'amount')::numeric) from jsonb_array_elements(result->'entries')e where e->>'kind'='loss' and not (e->>'voided')::boolean),0))) into result;
 return result;
end $$;
create or replace function public.swift_merchant_delivery_fees() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(d.category,d.fee),'{}') from public.swift_merchant_delivery d join public.swift_merchant_plans p using(category) where p.plan='premium' and d.fee is not null;
$$;
create or replace function public.swift_merchant_delivery_save(p_category text,p_fee numeric default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.swift_merchant_access(p_category,'delivery') then raise exception 'Premium store access required' using errcode='42501';end if;
 if p_fee is not null and (p_fee<0 or p_fee>1000) then raise exception 'Delivery fee must be between 0 and 1000';end if;
 insert into public.swift_merchant_delivery(category,fee,updated_by) values(p_category,round(p_fee,2),auth.uid()) on conflict(category) do update set fee=excluded.fee,updated_by=excluded.updated_by,updated_at=now();
 insert into public.swift_merchant_audit(category,actor,action,detail) values(p_category,auth.uid(),'delivery_fee',jsonb_build_object('fee',p_fee));
end $$;
create or replace function public.swift_merchant_validate_delivery() returns trigger language plpgsql security definer set search_path='' as $$
declare cat text;count_stores integer;fee numeric;
begin
 if jsonb_typeof(new.snapshot->'items')<>'array' or coalesce(new.snapshot->>'taco_note','')<>'' then return new;end if;
 select count(distinct i->>'category'),min(i->>'category') into count_stores,cat from jsonb_array_elements(new.snapshot->'items')i;
 if count_stores=1 then
 select d.fee into fee from public.swift_merchant_delivery d join public.swift_merchant_plans p using(category) where d.category=cat and p.plan='premium';
 if fee is not null and (new.snapshot->>'delivery_fee')::numeric is distinct from fee then raise exception 'This store delivery fee changed. Refresh checkout before sending your order.';end if;
 end if;return new;
end $$;
drop trigger if exists swift_merchant_delivery_check on public.customer_order_tracking;
create trigger swift_merchant_delivery_check before insert on public.customer_order_tracking for each row execute function public.swift_merchant_validate_delivery();
revoke all on function public.swift_merchant_validate_delivery() from public,anon,authenticated;
revoke all on function public.swift_merchant_capture_parts() from public,anon,authenticated;
revoke all on function public.swift_merchant_request(text,text),public.swift_merchant_requests_admin(text,uuid,text),public.swift_merchant_orders(text,uuid,text,text),public.swift_merchant_finance(text,text,jsonb,date,date),public.swift_merchant_delivery_save(text,numeric) from public,anon;
grant execute on function public.swift_merchant_request(text,text),public.swift_merchant_requests_admin(text,uuid,text),public.swift_merchant_orders(text,uuid,text,text),public.swift_merchant_finance(text,text,jsonb,date,date),public.swift_merchant_delivery_save(text,numeric) to authenticated;
revoke all on function public.swift_merchant_delivery_fees() from public;
grant execute on function public.swift_merchant_delivery_fees() to anon,authenticated;
notify pgrst,'reload schema';
commit;