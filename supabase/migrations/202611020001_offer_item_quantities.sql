create or replace function public.swift_validate_offer_item_quantities(p_items jsonb)
returns void language plpgsql security definer set search_path='' as $body$
declare item jsonb;r public.swift_store_offers;cfg jsonb;choice jsonb;grp jsonb;v_price bigint;n integer;
begin
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)>100 then raise exception 'Invalid order items';end if;
 for item in select value from jsonb_array_elements(p_items) where value ? 'offer_quantity_mode' loop
  if item->>'offer_quantity_mode' is distinct from 'individual' or nullif(item->>'offer_id','') is null then raise exception 'Invalid offer quantity mode';end if;
  select * into r from public.swift_store_offers where id=(item->>'offer_id')::uuid;
  if not found or not r.published or r.starts_at>now() or (r.ends_at is not null and r.ends_at<=now()) or r.category is distinct from item->>'category' then raise exception 'This offer is no longer available';end if;
  cfg:=r.order_config;if coalesce((cfg->>'enabled')::boolean,false) is not true then raise exception 'Offer ordering unavailable';end if;
  if jsonb_typeof(item->'offer_choices') is distinct from 'array' or jsonb_array_length(item->'offer_choices')<>0 then raise exception 'Invalid offer selections';end if;
  if nullif(item->>'offer_option_id','') is not null then
   if nullif(item->>'offer_extra_group_id','') is not null or nullif(item->>'offer_extra_choice_id','') is not null then raise exception 'Invalid offer item';end if;
   select value into choice from jsonb_array_elements(cfg->'options') where value->>'id'=item->>'offer_option_id';
  else
   select value into grp from jsonb_array_elements(cfg->'groups') where value->>'id'=item->>'offer_extra_group_id';
   if grp is null then raise exception 'Extras group changed';end if;
   select value into choice from jsonb_array_elements(grp->'choices') where value->>'id'=item->>'offer_extra_choice_id';
  end if;
  if choice is null then raise exception 'Offer item changed';end if;v_price:=(choice->>'price_cents')::bigint;
  if coalesce(item->>'quantity','')!~'^[0-9]+$' or (item->>'quantity')::numeric not between 1 and 100 or coalesce(item->>'price','')!~'^[0-9]+([.][0-9]+)?$' or (item->>'price')::numeric*100<>v_price then raise exception 'Offer price or quantity changed. Review your cart';end if;
  if exists(select 1 from jsonb_array_elements(p_items) x where x->>'offer_id'=r.id::text and x->>'offer_quantity_mode' is distinct from 'individual') then raise exception 'Remove the older version of this offer from your cart';end if;
  if not exists(select 1 from jsonb_array_elements(p_items) x where x->>'offer_id'=r.id::text and nullif(x->>'offer_option_id','') is not null) then raise exception 'Choose at least one main item for this offer';end if;
  for grp in select value from jsonb_array_elements(cfg->'groups') loop
   select count(distinct x->>'offer_extra_choice_id') into n from jsonb_array_elements(p_items) x where x->>'offer_id'=r.id::text and x->>'offer_extra_group_id'=grp->>'id';
   if n<(grp->>'min')::integer or n>(grp->>'max')::integer then raise exception 'Review the extras selected for this offer';end if;
  end loop;
 end loop;
end $body$;
revoke all on function public.swift_validate_offer_item_quantities(jsonb) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION public.swift_validate_order_offer_prices()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item jsonb;r public.swift_store_offers;config jsonb;o jsonb;g jsonb;c jsonb;pick jsonb;price bigint;n integer;seen text[];
begin
 perform public.swift_validate_offer_item_quantities(coalesce(new.snapshot->'items','[]'::jsonb));
 for item in select value from jsonb_array_elements(coalesce(new.snapshot->'items','[]'::jsonb)) loop
 if item->>'offer_quantity_mode'='individual' then continue;end if;
 if nullif(item->>'offer_id','') is null then continue;end if;
 select * into r from public.swift_store_offers where id=(item->>'offer_id')::uuid;
 if not found or not r.published or r.starts_at>now() or (r.ends_at is not null and r.ends_at<=now()) or r.category is distinct from item->>'category' then raise exception 'This offer is no longer available';end if;
 config:=r.order_config;if coalesce((config->>'enabled')::boolean,false) is not true then raise exception 'Offer ordering unavailable';end if;
 select value into o from jsonb_array_elements(config->'options') where value->>'id'=item->>'offer_option_id';if o is null then raise exception 'Offer option changed';end if;price:=(o->>'price_cents')::bigint;
 if jsonb_typeof(item->'offer_choices') is distinct from 'array' then raise exception 'Invalid offer selections';end if;
 seen:=array[]::text[];
 for pick in select value from jsonb_array_elements(item->'offer_choices') loop
 if ((pick->>'group_id')||':'||(pick->>'choice_id'))=any(seen) then raise exception 'Duplicate selection';end if;seen:=array_append(seen,(pick->>'group_id')||':'||(pick->>'choice_id'));
 select value into g from jsonb_array_elements(config->'groups') where value->>'id'=pick->>'group_id';if g is null then raise exception 'Extras group changed';end if;
 select value into c from jsonb_array_elements(g->'choices') where value->>'id'=pick->>'choice_id';if c is null then raise exception 'Extras choice changed';end if;price:=price+(c->>'price_cents')::bigint;
 end loop;
 for g in select value from jsonb_array_elements(config->'groups') loop
 select count(*) into n from jsonb_array_elements(item->'offer_choices') where value->>'group_id'=g->>'id';if n<(g->>'min')::integer or n>(g->>'max')::integer then raise exception 'Review your offer selections';end if;
 end loop;
 if coalesce(item->>'quantity','')!~'^[0-9]+$' or coalesce(item->>'price','')!~'^[0-9]+([.][0-9]+)?$' or (item->>'quantity')::numeric<1 or (item->>'quantity')::numeric>1000 or (item->>'price')::numeric*100<>price then raise exception 'Offer price changed. Remove it from your cart and choose again';end if;
 end loop;return new;
end $function$
  ;
