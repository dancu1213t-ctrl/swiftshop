begin;
create or replace function public.swift_commission_entry_quote() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='INSERT' then
 new.recording_enabled:=coalesce((select active from public.swift_merchant_commission_accounts where category=new.category),false);
 if not new.recording_enabled then raise exception 'Management starts after SwiftShop activates your store';end if;
 new.commission_eligible:=new.recording_enabled and new.kind='direct_order' and new.entry_date>=(select (started_at at time zone 'America/Belize')::date from public.swift_merchant_commission_accounts where category=new.category);
 else new.recording_enabled:=old.recording_enabled;new.commission_eligible:=old.commission_eligible or (old.recording_enabled and new.kind='direct_order' and new.entry_date>=(select (started_at at time zone 'America/Belize')::date from public.swift_merchant_commission_accounts where category=new.category));end if;return new;end$$;

commit;
