begin;
do $migration$
declare definition text;
begin
 select pg_get_functiondef(oid) into strict definition from pg_proc where pronamespace='public'::regnamespace and proname='swift_merchant_orders';
 if position(' customer_instructions,' in definition)=0 then
 if position('t.snapshot->>''payment'' payment,' in definition)=0 then raise exception 'Unexpected merchant order definition';end if;
 definition:=replace(definition,'t.snapshot->>''payment'' payment,','t.snapshot->>''payment'' payment,left(coalesce(t.snapshot->''order_instructions''->>p.category,''''),500) customer_instructions,');
 execute definition;
 end if;
 select pg_get_functiondef(oid) into strict definition from pg_proc where pronamespace='public'::regnamespace and proname='create_customer_tracking';
 if position('Invalid order instructions' in definition)=0 then
 if position('insert into public.customer_order_tracking' in definition)=0 then raise exception 'Unexpected tracking definition';end if;
 definition:=replace(definition,'insert into public.customer_order_tracking',
 $validation$
 if p_snapshot ? 'order_instructions' then
 if jsonb_typeof(p_snapshot->'order_instructions') is distinct from 'object' then raise exception 'Invalid order instructions';end if;
 if exists(select 1 from jsonb_each(p_snapshot->'order_instructions') n
 where jsonb_typeof(n.value)<>'string' or length(n.value#>>'{}')>500
 or not exists(select 1 from jsonb_array_elements(p_snapshot->'items') i where i->>'category'=n.key)) then raise exception 'Invalid order instructions';end if;
 end if;
 insert into public.customer_order_tracking$validation$);
 execute definition;
 end if;
end $migration$;
commit;