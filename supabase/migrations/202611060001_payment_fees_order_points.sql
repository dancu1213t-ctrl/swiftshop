begin;
-- Keep old invoices at their recorded rate; new payment records use BZ$0.25.
alter table public.swiftpay_payments alter column fee_cents set default 25;
alter table public.swiftpay_counter_sessions alter column fee_cents set default 25;
alter table public.swiftpay_store_receipts alter column fee_cents set default 25;
alter table public.swiftpay_payments drop constraint if exists swiftpay_payments_fee_cents_check;
alter table public.swiftpay_payments add constraint swiftpay_payments_fee_cents_check check(fee_cents in(15,25));
alter table public.swiftpay_counter_sessions drop constraint if exists swiftpay_counter_sessions_fee_cents_check;
alter table public.swiftpay_counter_sessions add constraint swiftpay_counter_sessions_fee_cents_check check(fee_cents in(15,25));
alter table public.swiftpay_store_receipts drop constraint if exists swiftpay_store_receipts_fee_cents_check;
alter table public.swiftpay_store_receipts add constraint swiftpay_store_receipts_fee_cents_check check(fee_cents in(15,25));
do $patch$ declare p record;d text;n text;begin
 for p in select oid,proname from pg_proc where pronamespace='public'::regnamespace and proname=any(array['swiftpay_reserve','swiftpay_quote_pickup','swiftpay_counter_confirm','swiftpay_store_lookup','swiftpay_store_pay','swiftpay_record_worker_receipt','swiftpay_scan_order_payment','swiftpay_tracking_invoice']) loop
  d:=pg_get_functiondef(p.oid);n:=d;
  case p.proname
   when 'swiftpay_reserve' then n:=replace(replace(n,'p_amount_cents+15','p_amount_cents+coalesce(p.fee_cents,25)'),'BZ$0.15','BZ$0.25');
   when 'swiftpay_quote_pickup' then n:=replace(n,'return jsonb_build_object(''amountCents'',p_amount_cents,''feeCents'',15,''totalCents'',p_amount_cents+15);','select * into p from public.swiftpay_payments where kind=''delivery'' and reference_id=p_id;return jsonb_build_object(''amountCents'',p.amount_cents,''feeCents'',p.fee_cents,''totalCents'',p.amount_cents+p.fee_cents);');
   when 'swiftpay_counter_confirm' then n:=replace(n,'-s.amount_cents,15,cents','-s.amount_cents,s.fee_cents,cents');
   when 'swiftpay_store_lookup' then n:=replace(n,'''feeCents'',15','''feeCents'',25');
   when 'swiftpay_store_pay' then
    if position('p_amount_cents+15' in n)>0 then
     n:=replace(n,' or p_expected_total_cents is distinct from p_amount_cents+15','');
     n:=replace(n,'including the BZ$0.15 fee','and review the total');
     n:=replace(n,'if exists(select 1 from public.merchant_members','if p_expected_total_cents is distinct from p_amount_cents+25 then raise exception ''Review the amount including the BZ$0.25 fee'';end if; if exists(select 1 from public.merchant_members');
     n:=replace(n,'-p_amount_cents,15,cents','-p_amount_cents,25,cents');
    end if;
   when 'swiftpay_record_worker_receipt' then n:=replace(n,'''swiftpay_transaction_fee'',0.15','''swiftpay_transaction_fee'',(select fee_cents/100.0 from public.swiftpay_payments where kind=p_kind and reference_id=p_reference)');
   when 'swiftpay_scan_order_payment' then n:=replace(n,'BZ$0.15','BZ$0.25');
   when 'swiftpay_tracking_invoice' then n:=replace(n,'''swiftpay_fee'',0.15','''swiftpay_fee'',0.25');
  end case;
  if n<>d then execute n;end if;
 end loop;
end $patch$;
-- No historical backfill. One award per newly placed order, regardless of item count.
create table if not exists public.swift_order_points_awards(
 order_id uuid primary key references public.customer_order_tracking(id) on delete cascade,
 customer_id uuid not null references auth.users(id),
 points integer not null default 4 check(points=4),
 awarded_at timestamptz not null default now()
);
alter table public.swift_order_points_awards enable row level security;
revoke all on public.swift_order_points_awards from anon,authenticated;
create or replace function public.swift_award_order_points() returns trigger
language plpgsql security definer set search_path='' as $points$
declare awarded integer;
begin
 if new.customer_id is null then return new;end if;
 insert into public.swift_order_points_awards(order_id,customer_id) values(new.id,new.customer_id) on conflict(order_id) do nothing;
 get diagnostics awarded=row_count;
 if awarded=1 then update public.swiftshop_users set points=coalesce(points,0)+4 where auth_user_id=new.customer_id;end if;
 return new;
end $points$;
revoke all on function public.swift_award_order_points() from public,anon,authenticated;
drop trigger if exists swift_order_points on public.customer_order_tracking;
create trigger swift_order_points after insert on public.customer_order_tracking for each row execute function public.swift_award_order_points();
notify pgrst,'reload schema';
commit;