create or replace function public.swift_save_store_weekly_hours(p_category text,p_hours jsonb,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not (
 exists(select 1 from public.merchant_members where user_id=auth.uid() and category=p_category)
 or coalesce(public.swift_worker_kind()='admin',false)
 ) then raise exception 'You cannot change this store.'; end if;
 if p_enabled is null or p_hours is null or not public.swift_weekly_hours_valid(p_hours) then raise exception 'Set valid hours for all seven days. Opening and closing times must differ.'; end if;
 if not exists(select 1 from public.stores where category=p_category) then raise exception 'Store not found.'; end if;
 insert into public.merchant_storefronts(category,weekly_hours,auto_close)
 values(p_category,p_hours,p_enabled)
 on conflict(category) do update set weekly_hours=excluded.weekly_hours,auto_close=excluded.auto_close;
 -- A previous scheduled closure must be released when automatic hours are disabled.
 if not p_enabled then
 update public.stores set is_open=case when hours_auto_closed then 'yes' else is_open end,hours_auto_closed=false where category=p_category;
 else perform public.swift_store_auto_close(); end if;
 return jsonb_build_object('category',p_category,'weekly_hours',p_hours,'auto_close',p_enabled);
end $$;
