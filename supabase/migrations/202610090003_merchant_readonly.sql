begin;
create or replace function public.swift_merchant_finance(p_category text,p_action text default 'list',p_data jsonb default '{}',p_from date default current_date-30,p_to date default current_date) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.swift_merchant_entries;eid uuid;result jsonb;
begin
 if not public.swift_merchant_access(p_category,'orders') then raise exception 'Store access required' using errcode='42501';end if;
 if p_action<>'list' and not public.swift_merchant_access(p_category,'revenue') then raise exception 'Approved Pro or Premium plan required to edit' using errcode='42501';end if;
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
create policy merchant_campaign_view on public.merchant_campaigns for select to authenticated using(public.swift_merchant_access(category,'orders'));
create policy merchant_sales_view on public.merchant_sales for select to authenticated using(public.swift_merchant_access(category,'orders'));
commit;

