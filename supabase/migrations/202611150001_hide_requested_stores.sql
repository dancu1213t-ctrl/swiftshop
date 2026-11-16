-- Reversible customer-only suppression. Preserve store records, products and orders.
begin;
update public.swift_store_registry set status='paused',updated_at=now()
 where category in ('Daily Menu','Fonda','Burger Hut','Burger But','Neeyas Backyard','Saritas','Cosmetics','Sister');
do $$ begin
 if to_regprocedure('public.swift_region_catalogue_before_hidden_20261115()') is null then
  alter function public.swift_region_catalogue() rename to swift_region_catalogue_before_hidden_20261115;
 end if;
 if to_regprocedure('public.swift_region_catalogue_fast_before_hidden_20261115()') is null then
  alter function public.swift_region_catalogue_fast() rename to swift_region_catalogue_fast_before_hidden_20261115;
 end if;
end $$;
create or replace function public.swift_catalogue_hidden_20261115(p_data jsonb)
returns jsonb language sql immutable set search_path='' as $$
 with hidden(category,name) as (values
 ('Daily Menu','Dinner House'),('Fonda','La Fonda de Nilo'),
 ('Burger Hut','Burga Hut'),('Burger But','Burga Hut'),
 ('Neeyas Backyard','Neeyas Backyaad'),('Saritas','Saritas Orange Walk'),
 ('Cosmetics','Bree''s'),('Sister','Sisters CO.'))
 select p_data || jsonb_build_object('stores',
 coalesce((select jsonb_agg(r) from jsonb_array_elements(coalesce(p_data->'stores','[]'::jsonb)) r
 where r->>'category' not in(select category from hidden)),'[]'::jsonb)
 || (select jsonb_agg(jsonb_build_object('category',category,'name',name,'zone_id','orange-walk','status','paused','legacy',true)) from hidden));
$$;
revoke all on function public.swift_catalogue_hidden_20261115(jsonb) from public,anon,authenticated;
create or replace function public.swift_region_catalogue() returns jsonb
language sql stable security definer set search_path='' as $$
 select public.swift_catalogue_hidden_20261115(public.swift_region_catalogue_before_hidden_20261115());$$;
create or replace function public.swift_region_catalogue_fast() returns jsonb
language sql stable security definer set search_path='' as $$
 select public.swift_catalogue_hidden_20261115(public.swift_region_catalogue_fast_before_hidden_20261115());$$;
grant execute on function public.swift_region_catalogue(),public.swift_region_catalogue_fast() to anon,authenticated;
commit;
