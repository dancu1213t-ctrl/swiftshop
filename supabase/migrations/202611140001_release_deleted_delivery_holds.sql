-- Release unpaid holds when their delivery records are deleted in the dashboard.
-- Captured payments, wallet balances and the transaction ledger are untouched.
begin;
create or replace function public.swiftpay_release_deleted_delivery()
returns trigger language plpgsql security definer set search_path='' as $$
declare ref uuid;
begin
 if tg_table_name='customer_order_tracking' then ref=old.id;
 else ref=old.customer_tracking_id;
 end if;
 if ref is not null
 and not exists(select 1 from public.customer_order_tracking where id=ref)
 and not exists(select 1 from public.orders where customer_tracking_id=ref) then
  update public.swiftpay_payments set state='released',released_at=now()
   where kind='delivery' and reference_id=ref and state in ('quoted','reserved');
 end if;
 return old;
end $$;
revoke all on function public.swiftpay_release_deleted_delivery() from public,anon,authenticated;
drop trigger if exists swiftpay_release_deleted_tracking on public.customer_order_tracking;
create trigger swiftpay_release_deleted_tracking after delete on public.customer_order_tracking
 for each row execute function public.swiftpay_release_deleted_delivery();
drop trigger if exists swiftpay_release_deleted_order on public.orders;
create trigger swiftpay_release_deleted_order after delete on public.orders
 for each row execute function public.swiftpay_release_deleted_delivery();
commit;
