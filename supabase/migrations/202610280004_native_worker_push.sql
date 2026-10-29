begin;
create or replace function public.swift_native_worker_push(p_token text,p_app text,p_category text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v uuid;e text;
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501';end if;
 if p_app not in ('merchant','runner') or length(p_token) not between 40 and 4096 or p_token !~ '^[A-Za-z0-9_:\-]+$' then raise exception 'Invalid Android device';end if;
 if p_app='merchant' then
  if p_category is null or not public.swift_merchant_access(p_category,'orders') then raise exception 'Store access required' using errcode='42501';end if;
 else
  if p_category is not null or not public.swift_team_is_staff() then raise exception 'Active team account required' using errcode='42501';end if;
 end if;
 e:='android:'||md5(p_token);
 insert into public.swift_team_push_devices(user_id,endpoint,subscription,merchant_category)
 values(auth.uid(),e,jsonb_build_object('platform','android','token',p_token,'app',p_app),p_category)
 on conflict(endpoint) do update set user_id=excluded.user_id,subscription=excluded.subscription,merchant_category=excluded.merchant_category,enabled=true,updated_at=now() returning id into v;
 return v;
end $$;
revoke all on function public.swift_native_worker_push(text,text,text) from public,anon;
grant execute on function public.swift_native_worker_push(text,text,text) to authenticated;
create or replace function public.swift_native_worker_unlink(p_token text) returns void
language plpgsql security definer set search_path='' as $$
begin update public.swift_team_push_devices set enabled=false,updated_at=now() where user_id=auth.uid() and endpoint='android:'||md5(p_token);end $$;
revoke all on function public.swift_native_worker_unlink(text) from public,anon;
grant execute on function public.swift_native_worker_unlink(text) to authenticated;
-- Only the signed-in device can request a private test. No broadcasts.
create or replace function public.swift_worker_push_test(p_endpoint text) returns uuid
language plpgsql security definer set search_path='' as $$
declare d public.swift_team_push_devices;n uuid;
begin
 select * into d from public.swift_team_push_devices where (endpoint=p_endpoint or id::text=p_endpoint) and user_id=auth.uid() and enabled;
 if not found then raise exception 'Enable notifications on this device first';end if;
 if d.merchant_category is not null then
  if not public.swift_merchant_access(d.merchant_category,'orders') then raise exception 'Store access required';end if;
 elsif not public.swift_team_is_staff() then raise exception 'Active team account required';end if;
 if exists(select 1 from public.swift_team_notifications where user_id=auth.uid() and title='SwiftShop test alert' and created_at>now()-interval '1 minute') then raise exception 'Wait a minute before testing again';end if;
 insert into public.swift_team_notifications(user_id,title,body,page,entity_id) values(auth.uid(),'SwiftShop test alert','Notifications are connected on this device.',case when d.merchant_category is null then 'profile' else 'merchant-test' end,'device-test') returning id into n;
 insert into public.swift_team_push_jobs(notification_id,device_id) values(n,d.id);
 return n;
end $$;
revoke all on function public.swift_worker_push_test(text) from public,anon;
grant execute on function public.swift_worker_push_test(text) to authenticated;
create or replace function public.swift_team_claim_push(p_limit integer default 30) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Service role required';end if;
 with candidates as(
 select j.notification_id,j.device_id from public.swift_team_push_jobs j join public.swift_team_push_devices d on d.id=j.device_id join public.swift_team_notifications n on n.id=j.notification_id
 where j.sent_at is null and j.failed_at is null and j.next_attempt_at<=now() and d.enabled and n.user_id=d.user_id and (
 (d.merchant_category is not null and exists(select 1 from public.merchant_members m where m.user_id=d.user_id and m.category=d.merchant_category) and (n.page='merchant-test' or n.page='merchant-orders' and exists(select 1 from public.swift_merchant_order_parts op where op.category=d.merchant_category and op.tracking_id::text=n.entity_id)))
 or(d.merchant_category is null and n.page not in('merchant-orders','merchant-test') and exists(select 1 from public.profiles p where p.id=d.user_id and p.active and p.role in('admin','runner','driver'))))
 order by j.next_attempt_at limit greatest(1,least(p_limit,50)) for update of j skip locked
 ),claimed as(update public.swift_team_push_jobs j set attempts=j.attempts+1,next_attempt_at=now()+interval '2 minutes' from candidates c where j.notification_id=c.notification_id and j.device_id=c.device_id returning j.*)
 select coalesce(jsonb_agg(jsonb_build_object('notification_id',c.notification_id,'device_id',c.device_id,'attempts',c.attempts,'subscription',d.subscription,'title',n.title,'body',n.body,'page',n.page)),'[]'::jsonb) into result from claimed c join public.swift_team_push_devices d on d.id=c.device_id join public.swift_team_notifications n on n.id=c.notification_id;
 return result;
end $$;
-- Native devices also receive new unassigned runs, respecting the existing Online switch.
create or replace function public.swift_native_available_run() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.assigned_runner_id is not null or (new.status not in ('Ready','Pending') or coalesce(new.active_status,'Unassigned')<>'Unassigned') then return new;end if;
 with recipients as(select p.id from public.profiles p where p.active and p.role='runner' and coalesce(p.dispatch_active,true) and exists(select 1 from public.swift_team_push_devices d where d.user_id=p.id and d.enabled and d.subscription->>'platform'='android' and d.merchant_category is null)), notices as(
 insert into public.swift_team_notifications(user_id,title,body,page,entity_id) select id,'New delivery available','Open SwiftShop Runner to review this run.','available',new.order_id from recipients returning id,user_id)
 insert into public.swift_team_push_jobs(notification_id,device_id) select n.id,d.id from notices n join public.swift_team_push_devices d on d.user_id=n.user_id and d.enabled and d.subscription->>'platform'='android' and d.merchant_category is null on conflict do nothing;
 return new;
end $$;
revoke all on function public.swift_native_available_run() from public,anon,authenticated;
drop trigger if exists swift_native_available_run on public.orders;
create trigger swift_native_available_run after insert on public.orders for each row execute function public.swift_native_available_run();
notify pgrst,'reload schema';
commit;
