begin;
alter table public.swift_merchant_order_parts add column if not exists merchant_ack_at timestamptz;
alter table public.swift_merchant_order_parts add column if not exists merchant_ack_by uuid;
update public.swift_merchant_order_parts set merchant_ack_at=decision_at,merchant_ack_by=decision_by where decision='accepted' and reason<>'Accepted by Dispatch' and merchant_ack_at is null;
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
 update public.swift_merchant_order_parts set decision=case p_action when 'accept' then 'accepted' else 'rejected' end,reason=left(coalesce(p_reason,''),300),review_needed=p_action='reject',decision_by=auth.uid(),decision_at=now(),merchant_ack_at=now(),merchant_ack_by=auth.uid() where tracking_id=p_id and category=p_category;
 end if;
 insert into public.swift_merchant_audit(category,actor,action,detail) values(p_category,auth.uid(),'order_'||p_action,jsonb_build_object('id',p_id,'reason',left(coalesce(p_reason,''),300)));
 elsif p_action<>'list' then raise exception 'Invalid action';end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(select p.*,t.phase,t.linked_order_id,t.snapshot->>'payment' payment,left(coalesce(nullif(t.snapshot->>'customer_name',''),'Customer'),120) customer_name,(select coalesce(jsonb_agg(i||jsonb_build_object('image',coalesce(nullif(i->>'image',''),(select pr.image from public.products pr where pr.category=p.category and pr.name=i->>'name' order by pr.id limit 1)))), '[]'::jsonb) from jsonb_array_elements(p.items)i) display_items from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id where p.category=p_category order by p.created_at desc limit 200)x),'[]');
end $$;
create or replace function public.swift_merchant_ack_order(p_category text,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.swift_merchant_order_parts;phase text;stamp timestamptz;
begin
 if not public.swift_merchant_access(p_category,'orders') then raise exception 'Store access required' using errcode='42501';end if;
 select p.* into r from public.swift_merchant_order_parts p join public.customer_order_tracking t on t.id=p.tracking_id where p.tracking_id=p_id and p.category=p_category for update of p,t;
 if r.tracking_id is null then raise exception 'Store order not found';end if;
 if r.merchant_ack_at is not null then return jsonb_build_object('acknowledged_at',r.merchant_ack_at);end if;
 select t.phase into phase from public.customer_order_tracking t where t.id=p_id;
 if phase in('delivered','cancelled') or r.decision='rejected' then raise exception 'Order is no longer awaiting acceptance';end if;
 stamp:=clock_timestamp();
 update public.swift_merchant_order_parts set merchant_ack_at=stamp,merchant_ack_by=auth.uid(),decision='accepted',decision_at=case when decision='pending' then stamp else decision_at end,decision_by=case when decision='pending' then auth.uid() else decision_by end where tracking_id=p_id and category=p_category;
 insert into public.swift_merchant_audit(category,actor,action,detail) values(p_category,auth.uid(),'merchant_acknowledge',jsonb_build_object('tracking_id',p_id));
 return jsonb_build_object('acknowledged_at',stamp);
end $$;
revoke all on function public.swift_merchant_ack_order(text,uuid) from public,anon;
grant execute on function public.swift_merchant_ack_order(text,uuid) to authenticated;
commit;

