create or replace function public.swift_budget_menu(p_budget_cents integer,p_zone text,p_kind text default 'meals',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_budget_cents is null or p_budget_cents<1 or p_budget_cents>100000 or p_kind is null or p_kind not in ('meals','drinks') or p_offset is null or p_offset<0 or p_offset>500 then raise exception 'Choose a valid budget and menu.'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (
 select p.id,p.name,p.category,p.price,p.image,p.was,p.description,p.tags,p.catalog_details,p.active,
 coalesce(r.display_name,r.name,case when p.category='Drink' then 'SwiftShop Drinks' end) store_name
 from public.products p
 left join public.swift_store_registry r using(category)
 left join public.stores s using(category)
 left join public.swift_service_zones z on z.id=r.zone_id
 cross join lateral (select p.category='Drink' or p.catalog_details->>'type'='coffee' or
 concat_ws(' ',p.name,p.subcategory) ~* '(frappe|frappuccino|latte|espresso|beverage|drink|matcha|coffee|juice|smoothie|lemonade|iced tea|milkshake|horchata|soda|cappuccino|cold brew|americano)' is_drink) k
 where p.active='yes' and p.price>0 and round(p.price*100)<=p_budget_cents
 and ((r.zone_id=p_zone and z.active and r.status='live' and r.business_type in ('Food','Cafes')
 and public.swift_store_visible(p.category) and (s.is_open='yes' or s.hours_auto_closed)
 and public.swift_store_scheduled_open(p.category))
 or (p.category='Drink' and r.category is null and p_zone='orange-walk' and exists(select 1 from public.swift_service_zones where id=p_zone and active)))
 and concat_ws(' ',p.name,p.subcategory) !~* '(gift.?card|subscription|cold foam|add.?on)'
 and coalesce(p.catalog_details->>'type','') not in ('technology','pharmacy','clothing','sneakers')
 and case when p_kind='drinks' then coalesce(k.is_drink,false) else not coalesce(k.is_drink,false) end
 order by p.price desc,p.id limit 24 offset p_offset
 )x);
end $$;
revoke all on function public.swift_budget_menu(integer,text,text,integer) from public;
grant execute on function public.swift_budget_menu(integer,text,text,integer) to anon,authenticated;
notify pgrst,'reload schema';
