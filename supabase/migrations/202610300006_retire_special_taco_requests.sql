begin;
create or replace function public.swift_no_special_taco_orders() returns trigger language plpgsql security definer set search_path='' as $$begin
 if nullif(btrim(coalesce(new.snapshot->>'taco_note','')),'') is not null then raise exception 'Special taco requests are no longer available. Choose items from a store.';end if;
 return new;
end$$;
drop trigger if exists a00_no_special_taco_orders on public.customer_order_tracking;
create trigger a00_no_special_taco_orders before insert on public.customer_order_tracking for each row execute function public.swift_no_special_taco_orders();
revoke all on function public.swift_no_special_taco_orders() from public;
notify pgrst,'reload schema';
commit;

