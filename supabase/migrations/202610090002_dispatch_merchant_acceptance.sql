begin;
create or replace function public.swift_merchant_dispatch_acceptance() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.phase='accepted' and old.phase is distinct from new.phase then
  with changed as (
   update public.swift_merchant_order_parts set decision='accepted',reason='Accepted by Dispatch',decision_by=auth.uid(),decision_at=now()
   where tracking_id=new.id and decision='pending' returning category
  ) insert into public.swift_merchant_audit(category,actor,action,detail)
    select category,auth.uid(),'dispatch_accept',jsonb_build_object('tracking_id',new.id) from changed;
 end if;
 return new;
end $$;
drop trigger if exists swift_merchant_dispatch_acceptance on public.customer_order_tracking;
create trigger swift_merchant_dispatch_acceptance after update of phase on public.customer_order_tracking for each row execute function public.swift_merchant_dispatch_acceptance();
revoke all on function public.swift_merchant_dispatch_acceptance() from public,anon,authenticated;
commit;