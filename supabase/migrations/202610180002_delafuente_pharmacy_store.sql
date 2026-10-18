begin;
insert into public.stores(category,is_open) values('DeLaFuentePharmacy','no') on conflict(category) do nothing;
insert into public.merchant_storefronts(category) values('DeLaFuentePharmacy') on conflict(category) do nothing;
commit;
