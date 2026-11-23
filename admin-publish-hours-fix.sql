begin;
create or replace function public.swift_store_schedule_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.is_open='yes' and not public.swift_store_scheduled_open(new.category) then
  raise exception 'Outside your saved opening hours. Update Store appearance to change the schedule.';
 end if;
 if tg_op='UPDATE' and old.is_open is distinct from new.is_open and old.hours_auto_closed is not distinct from new.hours_auto_closed then new.hours_auto_closed:=false;end if;
 return new;
end $$;
create or replace function public.swift_store_publish(p_category text,p_live boolean) returns void language plpgsql security definer set search_path='' as $$
declare scheduled_open boolean;
begin
 perform public.swift_admin_portal_access();
 update public.swift_store_registry set status=case when p_live then 'live' else 'paused' end,updated_at=now() where category=p_category;
 if not found then raise exception 'Store not found';end if;
 scheduled_open:=public.swift_store_scheduled_open(p_category);
 update public.stores set is_open=case when p_live and scheduled_open then 'yes' else 'no' end,hours_auto_closed=p_live and not scheduled_open where category=p_category;
 insert into public.swift_region_audit(actor_id,action,entity,detail) values(auth.uid(),'store_publication',p_category,jsonb_build_object('live',p_live,'scheduled_open',scheduled_open));
end $$;
commit;

