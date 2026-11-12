begin;
create table if not exists public.swiftcredit_receive_codes (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.swiftshop_users(id) on delete cascade,
 token_hash text not null unique,
 avatar_url text not null default '',
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '2 minutes',
 used_by uuid references public.swiftshop_users(id),
 request_id uuid,
 amount_cents bigint,
 used_at timestamptz
);
alter table public.swiftcredit_receive_codes enable row level security;
revoke all on public.swiftcredit_receive_codes from public,anon,authenticated;
create index if not exists swiftcredit_receive_owner_idx on public.swiftcredit_receive_codes(owner_id,created_at desc);
create or replace function public.swiftcredit_receive_code(p_avatar text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare u public.swiftshop_users; t text; c public.swiftcredit_receive_codes; path text; a text:='';
begin
 if auth.uid() is null then raise exception 'Sign in to SwiftPay';end if;
 select * into u from public.swiftshop_users where auth_user_id=auth.uid();
 if not found then raise exception 'Customer account required';end if;
 perform pg_advisory_xact_lock(hashtextextended(u.id::text,0));
 path:=encode(sha256(convert_to('swiftshop-profile:'||case when u.phone like 'account:%' then u.phone when length(regexp_replace(u.phone,'[^0-9]','','g'))=7 then '501'||regexp_replace(u.phone,'[^0-9]','','g') else regexp_replace(u.phone,'[^0-9]','','g') end,'UTF8')),'hex')||'/avatar.jpg';
 if length(coalesce(p_avatar,''))<=3000 and starts_with(p_avatar,'https://sbjadbqlmkktljfpqowc.supabase.co/storage/v1/object/sign/profile-pictures/'||path||'?') then a:=p_avatar;end if;
 update public.swiftcredit_receive_codes set expires_at=least(expires_at,now()) where owner_id=u.id and used_at is null;
 t:=gen_random_uuid()::text||gen_random_uuid()::text;
 insert into public.swiftcredit_receive_codes(owner_id,token_hash,avatar_url) values(u.id,encode(sha256(convert_to(t,'UTF8')),'hex'),a) returning * into c;
 return jsonb_build_object('id',c.id,'token',t,'expiresAt',c.expires_at,'name',u.name);
end $$;
create or replace function public.swiftcredit_scan_code(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u public.swiftshop_users; f public.swiftshop_users;c public.swiftcredit_receive_codes;
begin
 if auth.uid() is null then raise exception 'Sign in to SwiftPay';end if;
 select * into u from public.swiftshop_users where auth_user_id=auth.uid();if not found then raise exception 'Customer account required';end if;
 if p_token is null or length(p_token)<>72 then raise exception 'Invalid receive code';end if;
 select * into c from public.swiftcredit_receive_codes where token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
 if not found or c.expires_at<=now() or c.used_at is not null then raise exception 'Code expired or used. Ask your friend for a new code';end if;
 if c.owner_id=u.id then raise exception 'This is your own code. Scan your friend''s code';end if;
 select * into f from public.swiftshop_users where id=c.owner_id and auth_user_id is not null;if not found then raise exception 'Recipient account unavailable';end if;
 return jsonb_build_object('id',f.id,'name',f.name,'avatar',c.avatar_url,'expiresAt',c.expires_at,'codeId',c.id);
end $$;
create or replace function public.swiftcredit_send_code(p_token text,p_amount_cents bigint,p_request_id uuid,p_message text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare u public.swiftshop_users;c public.swiftcredit_receive_codes;result jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in to SwiftPay';end if;
 select * into u from public.swiftshop_users where auth_user_id=auth.uid();if not found then raise exception 'Customer account required';end if;
 if p_token is null or length(p_token)<>72 then raise exception 'Invalid receive code';end if;
 select * into c from public.swiftcredit_receive_codes where token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') for update;
 if not found then raise exception 'Invalid receive code';end if;
 if c.used_at is not null then
  if c.used_by=u.id and c.request_id=p_request_id then return public.swiftcredit_send(c.owner_id,p_amount_cents,p_request_id,p_message);end if;
  raise exception 'Code already used. Ask your friend for a new code';
 end if;
 if c.expires_at<=now() then raise exception 'Code expired. Ask your friend for a new code';end if;
 result:=public.swiftcredit_send(c.owner_id,p_amount_cents,p_request_id,p_message);
 update public.swiftcredit_receive_codes set used_by=u.id,request_id=p_request_id,amount_cents=p_amount_cents,used_at=now() where id=c.id;
 return result;
end $$;
create or replace function public.swiftcredit_receive_status(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.swiftcredit_receive_codes;u public.swiftshop_users;n text;
begin
 if auth.uid() is null then raise exception 'Sign in to SwiftPay';end if;
 select * into u from public.swiftshop_users where auth_user_id=auth.uid();if not found then raise exception 'Customer account required';end if;
 select * into c from public.swiftcredit_receive_codes where id=p_id and owner_id=u.id;
 if not found then raise exception 'Receive code unavailable';end if;
 if c.used_at is not null then select name into n from public.swiftshop_users where id=c.used_by;return jsonb_build_object('state','received','amountCents',c.amount_cents,'fromName',n);end if;
 return jsonb_build_object('state',case when c.expires_at<=now() then 'expired' else 'waiting' end,'expiresAt',c.expires_at);
end $$;
create or replace function public.swiftcredit_receive_close(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in to SwiftPay';end if;
 update public.swiftcredit_receive_codes c set expires_at=least(c.expires_at,now()) from public.swiftshop_users u where c.id=p_id and c.owner_id=u.id and u.auth_user_id=auth.uid() and c.used_at is null;
end $$;
revoke all on function public.swiftcredit_receive_code(text),public.swiftcredit_scan_code(text),public.swiftcredit_send_code(text,bigint,uuid,text),public.swiftcredit_receive_status(uuid),public.swiftcredit_receive_close(uuid) from public,anon;
grant execute on function public.swiftcredit_receive_code(text),public.swiftcredit_scan_code(text),public.swiftcredit_send_code(text,bigint,uuid,text),public.swiftcredit_receive_status(uuid),public.swiftcredit_receive_close(uuid) to authenticated;
commit;
select 'QR transfer functions installed' as result;
