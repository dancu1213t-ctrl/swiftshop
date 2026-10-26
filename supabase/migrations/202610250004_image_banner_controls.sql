begin;
alter table public.merchant_campaigns add column if not exists button_label text not null default 'Shop now', add column if not exists banner_tags text[] not null default '{}';
create or replace function public.swift_banner_tags_valid(tags text[]) returns boolean language sql immutable set search_path=public,pg_temp as $$ select coalesce(cardinality(tags)<=3 and coalesce(array_ndims(tags),1)=1 and not exists(select 1 from unnest(tags) t where t is null or char_length(btrim(t)) not between 1 and 24),false) $$;
alter table public.merchant_campaigns add constraint merchant_banner_button_valid check(char_length(btrim(button_label)) between 1 and 24);
alter table public.merchant_campaigns add constraint merchant_banner_tags_valid check(public.swift_banner_tags_valid(banner_tags));
notify pgrst,'reload schema';
commit;
select column_name,data_type from information_schema.columns where table_schema='public' and table_name='merchant_campaigns' and column_name in ('button_label','banner_tags');

