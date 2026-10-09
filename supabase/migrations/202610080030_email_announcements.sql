begin;
create table if not exists public.swift_email_campaigns (
 id uuid primary key default gen_random_uuid(),subject text not null check(length(subject) between 1 and 150),
 html text not null check(octet_length(html) between 1 and 250000),created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),queued_at timestamptz);
create table if not exists public.swift_email_suppressions (
 email text primary key,token uuid not null unique default gen_random_uuid(),unsubscribed_at timestamptz);
create table if not exists public.swift_email_deliveries (
 campaign_id uuid not null references public.swift_email_campaigns(id),email text not null,
 status text not null default 'pending' check(status in('pending','sending','sent','failed','skipped','review')),
 attempts integer not null default 0,first_attempt_at timestamptz,next_attempt_at timestamptz not null default now(),
 provider_id text,last_error text,primary key(campaign_id,email));
alter table public.swift_email_campaigns enable row level security;
alter table public.swift_email_suppressions enable row level security;
alter table public.swift_email_deliveries enable row level security;
revoke all on public.swift_email_campaigns,public.swift_email_suppressions,public.swift_email_deliveries from anon,authenticated;
grant all on public.swift_email_campaigns,public.swift_email_suppressions,public.swift_email_deliveries to service_role;
create or replace function public.swift_email_admin(p_action text,p_id uuid default null,p_subject text default null,p_html text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;campaign public.swift_email_campaigns;n integer;
begin
 if auth.uid() is null or public.swift_worker_kind() is distinct from 'admin' then raise exception 'Administrator session required' using errcode='42501';end if;
 if p_action='audience' then
  select count(distinct lower(trim(u.email))) into n from auth.users u where u.email_confirmed_at is not null and u.deleted_at is null and u.is_anonymous is not true and coalesce(u.email,'')<>'' and (u.banned_until is null or u.banned_until<now()) and not exists(select 1 from public.swift_email_suppressions s where s.email=lower(trim(u.email)) and s.unsubscribed_at is not null);
  return jsonb_build_object('recipients',n);
 elsif p_action='save' then
  if p_id is null then raise exception 'Campaign identifier required';end if;
  insert into public.swift_email_campaigns(id,subject,html,created_by) values(p_id,trim(p_subject),p_html,auth.uid()) on conflict(id) do nothing;
  select * into campaign from public.swift_email_campaigns where id=p_id;
  if campaign.subject is distinct from trim(p_subject) or campaign.html is distinct from p_html then raise exception 'This draft changed. Save a new draft.';end if;
  return jsonb_build_object('id',campaign.id);
 elsif p_action='queue' then
  select * into campaign from public.swift_email_campaigns where id=p_id for update;
  if not found then raise exception 'Draft not found';end if;
  if campaign.queued_at is null then
   insert into public.swift_email_suppressions(email) select distinct lower(trim(u.email)) from auth.users u where u.email_confirmed_at is not null and u.deleted_at is null and u.is_anonymous is not true and coalesce(u.email,'')<>'' and (u.banned_until is null or u.banned_until<now()) on conflict(email) do nothing;
   insert into public.swift_email_deliveries(campaign_id,email) select p_id,s.email from public.swift_email_suppressions s where s.unsubscribed_at is null and exists(select 1 from auth.users u where lower(trim(u.email))=s.email and u.email_confirmed_at is not null and u.deleted_at is null and u.is_anonymous is not true and (u.banned_until is null or u.banned_until<now())) on conflict do nothing;
   update public.swift_email_campaigns set queued_at=now() where id=p_id;
  end if;
  select count(*) into n from public.swift_email_deliveries where campaign_id=p_id;
  return jsonb_build_object('id',p_id,'queued',n);
 elsif p_action='list' then
  select coalesce(jsonb_agg(row),'[]'::jsonb) into result from(select c.id,c.subject,c.created_at,c.queued_at,count(d.email) total,count(d.email) filter(where d.status='sent') sent,count(d.email) filter(where d.status in('failed','review')) failed,count(d.email) filter(where d.status in('pending','sending')) pending from public.swift_email_campaigns c left join public.swift_email_deliveries d on d.campaign_id=c.id group by c.id order by c.created_at desc limit 30) row;
  return result;
 end if;raise exception 'Unknown email action';
end $$;
revoke all on function public.swift_email_admin(text,uuid,text,text) from public,anon;
grant execute on function public.swift_email_admin(text,uuid,text,text) to authenticated;
create or replace function public.swift_email_claim()
returns jsonb language plpgsql security definer set search_path='' as $$
declare job public.swift_email_deliveries;result jsonb;
begin
 update public.swift_email_deliveries set status='skipped',last_error='Unsubscribed' where status in('pending','failed','sending') and email in(select email from public.swift_email_suppressions where unsubscribed_at is not null);
 update public.swift_email_deliveries set status='review',last_error='Retry window elapsed; manual review required' where status in('sending','failed') and first_attempt_at<now()-interval '23 hours';
 select * into job from public.swift_email_deliveries where ((status in('pending','failed') and attempts<5 and next_attempt_at<=now()) or (status='sending' and next_attempt_at<now())) order by next_attempt_at for update skip locked limit 1;
 if not found then return null;end if;
 update public.swift_email_deliveries set status='sending',attempts=attempts+1,first_attempt_at=coalesce(first_attempt_at,now()),next_attempt_at=now()+interval '5 minutes' where campaign_id=job.campaign_id and email=job.email;
 select jsonb_build_object('campaign_id',job.campaign_id,'email',job.email,'subject',c.subject,'html',c.html,'token',s.token) into result from public.swift_email_campaigns c join public.swift_email_suppressions s on s.email=job.email where c.id=job.campaign_id;
 return result;
end $$;
revoke all on function public.swift_email_claim() from public,anon,authenticated;
grant execute on function public.swift_email_claim() to service_role;
notify pgrst,'reload schema';
commit;