begin;
create table if not exists public.swift_runner_transport(
 runner_id uuid primary key references public.profiles(id) on delete cascade,
 transport text not null check(transport in('bicycle','motorcycle','car')),
 updated_at timestamptz not null default now());
alter table public.swift_runner_transport enable row level security;
revoke all on public.swift_runner_transport from public,anon,authenticated;
create table if not exists public.swift_order_messages(
 id uuid primary key,tracking_id uuid not null references public.customer_order_tracking(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 sender_kind text not null check(sender_kind in('customer','runner')),
 body text not null check(length(trim(body)) between 1 and 1000),
 created_at timestamptz not null default now(),read_at timestamptz);
create index if not exists swift_order_messages_order on public.swift_order_messages(tracking_id,created_at,id);
alter table public.swift_order_messages enable row level security;
revoke all on public.swift_order_messages from public,anon,authenticated;
alter table public.delivery_notification_events add column if not exists chat_message_id uuid references public.swift_order_messages(id) on delete cascade;
alter table public.swift_team_notifications add column if not exists chat_message_id uuid references public.swift_order_messages(id) on delete cascade;

create or replace function public.swift_runner_transport(p_transport text default null)
returns text language plpgsql security definer set search_path='' as $$
declare result text;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and active and role='runner') then raise exception 'Active runner account required' using errcode='42501';end if;
 if p_transport is not null then
 if p_transport not in('bicycle','motorcycle','car') then raise exception 'Choose your delivery transport';end if;
 insert into public.swift_runner_transport(runner_id,transport)values(auth.uid(),p_transport)
 on conflict(runner_id)do update set transport=excluded.transport,updated_at=now();
 end if;
 select transport into result from public.swift_runner_transport where runner_id=auth.uid();
 if result is null then
 select case when lower(vehicle) like '%bicy%' or lower(vehicle) like '%cycle%' and lower(vehicle) not like '%motor%' then 'bicycle'
 when lower(vehicle) like '%motor%' or lower(vehicle) like '%bike%' then 'motorcycle'
 when lower(vehicle) like '%car%' then 'car' end into result from public.swift_worker_applications where user_id=auth.uid();
 end if;
 return result;
end $$;

create or replace function public.swift_order_chat_contexts()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in to open order chat' using errcode='42501';end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from(
 select t.id,t.phase,t.runner_id,p.display_name runner_name,p.delivery_contact_phone runner_phone,
 coalesce(ph.photo,wp.photo) runner_photo,
 coalesce(rt.transport,case when lower(a.vehicle) like '%bicy%' or lower(a.vehicle) like '%cycle%' and lower(a.vehicle) not like '%motor%' then 'bicycle' when lower(a.vehicle) like '%motor%' or lower(a.vehicle) like '%bike%' then 'motorcycle' when lower(a.vehicle) like '%car%' then 'car' end) transport,
 case when t.customer_id=auth.uid() then 'customer' else 'runner' end viewer,
 left(coalesce(t.snapshot->>'customer_name','Customer'),120) customer_name,
 (select count(*) from public.swift_order_messages m where m.tracking_id=t.id and m.sender_id<>auth.uid() and m.read_at is null) unread
 from public.customer_order_tracking t join public.profiles p on p.id=t.runner_id and p.active and p.role='runner'
 left join public.runner_profile_photos ph on ph.runner_id=p.id
 left join public.swift_worker_profiles wp on wp.user_id=p.id
 left join public.swift_runner_transport rt on rt.runner_id=p.id
 left join public.swift_worker_applications a on a.user_id=p.id
 where (t.customer_id=auth.uid() or t.runner_id=auth.uid()) and t.phase in('runner_assigned','on_the_way')
 and (t.linked_order_id is null or exists(select 1 from public.orders o where o.order_id=t.linked_order_id and o.assigned_runner_id=t.runner_id and o.status<>'Delivered'))
 order by t.created_at desc limit 20)x),'[]'::jsonb);
end $$;

create or replace function public.swift_order_chat(p_id uuid,p_body text default null,p_message_id uuid default null,p_read boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.customer_order_tracking;kind text;msg public.swift_order_messages;notification uuid;content text;
begin
 if auth.uid() is null then raise exception 'Sign in to open order chat' using errcode='42501';end if;
 select * into t from public.customer_order_tracking where id=p_id for update;
 if not found or t.runner_id is null or not (
 t.customer_id=auth.uid() or t.runner_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and active and role='runner')
 ) then raise exception 'This conversation is unavailable' using errcode='42501';end if;
 if t.phase not in('runner_assigned','on_the_way') or
 (t.linked_order_id is not null and not exists(select 1 from public.orders where order_id=t.linked_order_id and assigned_runner_id=t.runner_id and status<>'Delivered')) then
 return jsonb_build_object('closed',true,'messages','[]'::jsonb);
 end if;
 kind:=case when auth.uid()=t.customer_id then 'customer' else 'runner' end;
 if p_body is not null then
 content:=trim(p_body);
 if length(content) not between 1 and 1000 or p_message_id is null then raise exception 'Write a message of 1–1000 characters';end if;
 select * into msg from public.swift_order_messages where id=p_message_id;
 if found and (msg.tracking_id<>p_id or msg.sender_id<>auth.uid() or msg.body<>content) then raise exception 'Message reference already used';end if;
 if not found then
 if (select count(*) from public.swift_order_messages where tracking_id=p_id and sender_id=auth.uid() and created_at>now()-interval '1 minute')>=10 then raise exception 'Please wait a moment before sending more messages';end if;
 if (select count(*) from public.swift_order_messages where tracking_id=p_id)>=1000 then raise exception 'This conversation has reached its message limit. Please call your runner.';end if;
 insert into public.swift_order_messages(id,tracking_id,sender_id,sender_kind,body)values(p_message_id,p_id,auth.uid(),kind,content);
 if kind='customer' then
 insert into public.swift_team_notifications(user_id,title,body,page,entity_id,chat_message_id)
 values(t.runner_id,'Message from your customer','Open your active run to reply.','active',p_id::text,p_message_id) returning id into notification;
 insert into public.swift_team_push_jobs(notification_id,device_id)
 select notification,d.id from public.swift_team_push_devices d where d.user_id=t.runner_id and d.enabled and d.merchant_category is null on conflict do nothing;
 else
 insert into public.delivery_notification_events(order_id,phase,chat_message_id)values(p_id,'chat_message',p_message_id) returning id into notification;
 insert into public.delivery_push_jobs(event_id,install_id)
 select notification,s.install_id from public.delivery_push_subscriptions s where s.order_id=p_id on conflict do nothing;
 end if;
 end if;
 end if;
 if p_read then update public.swift_order_messages set read_at=now() where tracking_id=p_id and sender_id<>auth.uid() and read_at is null;end if;
 return jsonb_build_object('closed',false,'messages',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at,x.id) from(
 select id,sender_kind,body,created_at,read_at from public.swift_order_messages where tracking_id=p_id order by created_at desc,id desc limit 100)x),'[]'::jsonb));
end $$;

create or replace function public.swift_order_chat_purge()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.phase in('delivered','cancelled') or new.runner_id is distinct from old.runner_id then
 delete from public.swift_order_messages where tracking_id=new.id;
 end if;
 return new;
end $$;
drop trigger if exists swift_order_chat_purge on public.customer_order_tracking;
create trigger swift_order_chat_purge after update of phase,runner_id on public.customer_order_tracking for each row execute function public.swift_order_chat_purge();
revoke all on function public.swift_order_chat_purge() from public,anon,authenticated;
revoke all on function public.swift_order_chat_contexts() from public,anon;
revoke all on function public.swift_order_chat(uuid,text,uuid,boolean) from public,anon;
revoke all on function public.swift_runner_transport(text) from public,anon;
grant execute on function public.swift_order_chat_contexts(),public.swift_order_chat(uuid,text,uuid,boolean),public.swift_runner_transport(text) to authenticated;
commit;