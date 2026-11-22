revoke execute on function public.swift_store_scheduled_open(text,timestamptz) from anon,authenticated;
create or replace function public.swift_store_auto_close()
returns void language sql security definer set search_path='' as $$
 with states as (
 select s.category,public.swift_store_scheduled_open(s.category) available,
 (s.is_open='yes' or s.hours_auto_closed) enabled
 from public.stores s join public.merchant_storefronts m using(category)
 
 ) update public.stores s set
 is_open=case when st.enabled and st.available then 'yes' else 'no' end,
 hours_auto_closed=st.enabled and not st.available
 from states st where s.category=st.category
 and (s.is_open is distinct from case when st.enabled and st.available then 'yes' else 'no' end
 or s.hours_auto_closed is distinct from (st.enabled and not st.available))
$$;