begin;
create or replace function public.swift_order_customer_photo(p_id uuid)
returns text language sql stable security definer set search_path='' as $$
 select path.value from public.customer_order_tracking t
 join public.profiles p on p.id=t.runner_id and p.active and p.role='runner'
 join public.swiftshop_users u on u.auth_user_id=t.customer_id
 cross join lateral(select encode(sha256(convert_to('swiftshop-profile:'||case when u.phone like 'account:%' then u.phone when length(regexp_replace(u.phone,'[^0-9]','','g'))=7 then '501'||regexp_replace(u.phone,'[^0-9]','','g') else regexp_replace(u.phone,'[^0-9]','','g') end,'UTF8')),'hex')||'/avatar.jpg' value) path
 where t.id=p_id and t.runner_id=auth.uid() and t.phase in('runner_assigned','on_the_way')
 and (t.linked_order_id is null or exists(select 1 from public.orders o where o.order_id=t.linked_order_id and o.assigned_runner_id=t.runner_id and o.status<>'Delivered'))
 and exists(select 1 from storage.objects o where o.bucket_id='profile-pictures' and o.name=path.value)
$$;
create or replace function public.swift_order_customer_photo_allowed(p_path text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.customer_order_tracking t where t.runner_id=auth.uid() and t.phase in('runner_assigned','on_the_way') and public.swift_order_customer_photo(t.id)=p_path)
$$;
revoke all on function public.swift_order_customer_photo(uuid),public.swift_order_customer_photo_allowed(text) from public,anon;
grant execute on function public.swift_order_customer_photo(uuid),public.swift_order_customer_photo_allowed(text) to authenticated;
create policy "assigned runner reads customer chat photo" on storage.objects for select to authenticated using(bucket_id='profile-pictures' and public.swift_order_customer_photo_allowed(name));
do $migration$
declare definition text;marker text:='left(coalesce(t.snapshot->>''customer_name'',''Customer''),120) customer_name,';
begin
 select pg_get_functiondef(oid) into strict definition from pg_proc where pronamespace='public'::regnamespace and proname='swift_order_chat_contexts';
 if position('customer_photo_path' in definition)=0 then
 if position(marker in definition)=0 then raise exception 'Unexpected chat context definition';end if;
 execute replace(definition,marker,marker||'public.swift_order_customer_photo(t.id) customer_photo_path,');
 end if;
end $migration$;
commit;