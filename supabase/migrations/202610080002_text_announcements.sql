begin;
alter table public.delivery_push_devices add column if not exists announcements_enabled boolean not null default true;
DO $patch$ declare source text;begin
 source=pg_get_functiondef('public.manage_app_promotion(text,jsonb,uuid)'::regprocedure);
 source=replace(source,'if jsonb_typeof(p_data)<>''object'' then raise exception ''Invalid promotion'';end if;','if jsonb_typeof(p_data)<>''object'' then raise exception ''Invalid announcement'';end if; p_data=jsonb_build_object(''title'',''SWIFTSHOP'',''body'',trim(p_data->>''body''),''item_name'','''',''price'',null,''image'','''',''category'',''__announcement'',''expires_at'',null);');
 source=replace(source,'from public.delivery_push_devices where promotions_enabled on conflict do nothing','from public.delivery_push_devices where (r.category=''__announcement'' and announcements_enabled) or (r.category<>''__announcement'' and promotions_enabled) on conflict do nothing');
 execute source;
 source=pg_get_functiondef('public.claim_promotion_push_jobs()'::regprocedure);
 source=replace(source,'where d.promotions_enabled and p.published_at','where ((p.category=''__announcement'' and d.announcements_enabled) or (p.category<>''__announcement'' and d.promotions_enabled)) and p.published_at');
 execute source;
 source=pg_get_functiondef('public.register_promotion_device(uuid,uuid,text,text,boolean)'::regprocedure);
 source=replace(source,'where install_id=p_install_id and sent_at is null','where install_id=p_install_id and sent_at is null and exists(select 1 from public.app_promotions p where p.id=promotion_push_jobs.promotion_id and p.category is distinct from ''__announcement'')');
 execute source;
end $patch$;
create or replace function public.register_announcement_preferences(p_install_id uuid,p_install_secret uuid,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_install_id is null or p_install_secret is null or p_enabled is null then raise exception 'Invalid notification preference';end if;
 update public.delivery_push_devices set announcements_enabled=p_enabled,updated_at=now()
 where install_id=p_install_id and secret_hash=encode(sha256(convert_to(p_install_secret::text,'UTF8')),'hex');
 if not found then raise exception 'Device access required';end if;
 if not p_enabled then update public.promotion_push_jobs j set failed_at=now(),last_error='Announcements disabled' from public.app_promotions p where p.id=j.promotion_id and p.category='__announcement' and j.install_id=p_install_id and j.sent_at is null;end if;
end $$;
revoke all on function public.register_announcement_preferences(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.register_announcement_preferences(uuid,uuid,boolean) to anon,authenticated;
notify pgrst,'reload schema';
commit;
