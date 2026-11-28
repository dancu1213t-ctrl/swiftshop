create or replace function public.swift_admin_store_entrance(p_category text,p_data jsonb default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.merchant_storefronts;
begin
 perform public.swift_admin_check_store(p_category);
 if not exists(select 1 from public.swift_store_registry where category=p_category and business_type in('Apparel','Tech','Pharmacy')) then raise exception 'Entrance screens are available for Apparel, Tech and Pharmacy stores';end if;
 if p_data is not null then
 update public.merchant_storefronts set entrance_enabled=coalesce((p_data->>'enabled')::boolean,false),entrance_image=case when p_data ? 'image' then nullif(p_data->>'image','') else entrance_image end where category=p_category;
 if not found then raise exception 'Store appearance has not been set up';end if;
 end if;
 select * into r from public.merchant_storefronts where category=p_category;
 return jsonb_build_object('enabled',coalesce(r.entrance_enabled,false),'image',r.entrance_image);
end $$;
revoke all on function public.swift_admin_store_entrance(text,jsonb) from public,anon;
grant execute on function public.swift_admin_store_entrance(text,jsonb) to authenticated;