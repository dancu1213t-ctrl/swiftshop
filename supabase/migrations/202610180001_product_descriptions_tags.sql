-- Optional merchant-authored product copy. Existing product RLS remains unchanged.
begin;
alter table public.products add column if not exists description text not null default '';
alter table public.products add column if not exists tags text[] not null default '{}'::text[];
create or replace function public.swift_product_tags_valid(value text[]) returns boolean language sql immutable set search_path='' as $$
select value is not null and coalesce(array_ndims(value),1)=1 and cardinality(value)<=6
and not exists(select 1 from unnest(value)t where t is null or length(btrim(t))=0 or length(t)>28 or t<>btrim(t) or t ~ '[[:cntrl:]]')
and (select count(*)=count(distinct lower(t)) from unnest(value)t);
$$;
do $$ begin
if not exists(select 1 from pg_constraint where conrelid='public.products'::regclass and conname='products_description_length') then alter table public.products add constraint products_description_length check(char_length(description)<=1500);end if;
if not exists(select 1 from pg_constraint where conrelid='public.products'::regclass and conname='products_custom_tags_valid') then alter table public.products add constraint products_custom_tags_valid check(public.swift_product_tags_valid(tags));end if;
end $$;
notify pgrst,'reload schema';
commit;