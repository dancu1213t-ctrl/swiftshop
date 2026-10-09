begin;
create extension if not exists pg_cron;
alter table public.customer_order_tracking add column if not exists auto_accept_after timestamptz;
create index if not exists customer_auto_accept_due on public.customer_order_tracking(auto_accept_after) where phase='sent' and auto_accept_after is not null;
create or replace function public.swift_dispatch_accept_deadline() returns trigger language plpgsql security definer set search_path='' as $$
begin new.auto_accept_after:=clock_timestamp()+interval '6 seconds';return new;end $$;
create trigger swift_dispatch_accept_deadline before insert on public.customer_order_tracking for each row execute function public.swift_dispatch_accept_deadline();
create or replace function public.swift_dispatch_auto_accept() returns integer language plpgsql security definer set search_path='' as $$
declare r record;n integer:=0;
begin
 for r in select id from public.customer_order_tracking where phase='sent' and auto_accept_after<=clock_timestamp() order by auto_accept_after limit 100 for update skip locked loop
  begin
   update public.customer_order_tracking set phase='accepted' where id=r.id and phase='sent';
   n:=n+1;
  exception when others then raise log 'Auto-accept failed for order %: %',r.id,sqlerrm;
  end;
 end loop;
 return n;
end $$;
revoke all on function public.swift_dispatch_accept_deadline() from public,anon,authenticated;
revoke all on function public.swift_dispatch_auto_accept() from public,anon,authenticated;
select cron.schedule('swift-dispatch-auto-accept','1 second','select public.swift_dispatch_auto_accept()');
commit;

