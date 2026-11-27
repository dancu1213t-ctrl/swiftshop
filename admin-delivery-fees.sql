create table public.swift_delivery_fee_settings(
 zone_id text primary key references public.swift_service_zones(id),
 custom_enabled boolean not null default false,
 base_cents integer not null default 450 check(base_cents between 0 and 100000),
 stop_cents integer not null default 150 check(stop_cents between 0 and 100000),
 offer_enabled boolean not null default false,
 offer_base_cents integer not null default 300 check(offer_base_cents between 0 and 100000),
 offer_stop_cents integer not null default 100 check(offer_stop_cents between 0 and 100000),
 offer_ends_at timestamptz,
 updated_at timestamptz not null default now(),updated_by uuid references auth.users(id)
);
alter table public.swift_delivery_fee_settings enable row level security;
revoke all on public.swift_delivery_fee_settings from public,anon,authenticated;
create function public.swift_admin_delivery_fees(p_zone text,p_data jsonb default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare z text:=public.swift_admin_effective_zone(p_zone);r public.swift_delivery_fee_settings;k text;
begin
 if z is null then raise exception 'Choose one service area';end if;
 if p_data is not null then
  foreach k in array array['base_cents','stop_cents','offer_base_cents','offer_stop_cents'] loop
   if jsonb_typeof(p_data->k) is distinct from 'number' or (p_data->>k)::numeric<>trunc((p_data->>k)::numeric) or (p_data->>k)::numeric not between 0 and 100000 then raise exception 'Enter valid fees with up to two decimal places';end if;
  end loop;
  if jsonb_typeof(p_data->'custom_enabled') is distinct from 'boolean' or jsonb_typeof(p_data->'offer_enabled') is distinct from 'boolean' then raise exception 'Choose the pricing toggles';end if;
  if (p_data->>'offer_enabled')::boolean and nullif(p_data->>'offer_ends_at','')::timestamptz<=now() then raise exception 'Offer end time must be in the future';end if;
  insert into public.swift_delivery_fee_settings(zone_id,custom_enabled,base_cents,stop_cents,offer_enabled,offer_base_cents,offer_stop_cents,offer_ends_at,updated_by)
  values(z,(p_data->>'custom_enabled')::boolean,(p_data->>'base_cents')::int,(p_data->>'stop_cents')::int,(p_data->>'offer_enabled')::boolean,(p_data->>'offer_base_cents')::int,(p_data->>'offer_stop_cents')::int,nullif(p_data->>'offer_ends_at','')::timestamptz,auth.uid())
  on conflict(zone_id) do update set custom_enabled=excluded.custom_enabled,base_cents=excluded.base_cents,stop_cents=excluded.stop_cents,offer_enabled=excluded.offer_enabled,offer_base_cents=excluded.offer_base_cents,offer_stop_cents=excluded.offer_stop_cents,offer_ends_at=excluded.offer_ends_at,updated_at=now(),updated_by=auth.uid();
  insert into public.swift_region_audit(actor_id,action,entity,detail) values(auth.uid(),'delivery_fees',z,p_data);
 end if;
 select * into r from public.swift_delivery_fee_settings where zone_id=z;
 return coalesce(to_jsonb(r),jsonb_build_object('zone_id',z,'custom_enabled',false,'base_cents',450,'stop_cents',150,'offer_enabled',false,'offer_base_cents',300,'offer_stop_cents',100));
end $$;
revoke all on function public.swift_admin_delivery_fees(text,jsonb) from public,anon;
grant execute on function public.swift_admin_delivery_fees(text,jsonb) to authenticated;
alter function public.swift_region_quote(jsonb,text) rename to swift_region_quote_before_admin_fees;
revoke all on function public.swift_region_quote_before_admin_fees(jsonb,text) from public,anon,authenticated;
create function public.swift_region_quote(p_items jsonb,p_coordinates text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q jsonb;r public.swift_delivery_fee_settings;normal integer;offered integer;fee integer;n integer;offer_on boolean;
begin
 q:=public.swift_region_quote_before_admin_fees(p_items,p_coordinates);
 select * into r from public.swift_delivery_fee_settings where zone_id=q->>'zone_id';
 n:=coalesce((q->>'pickup_count')::integer,(select count(distinct case when nullif(i->>'offer_id','') is not null then 'offer:'||(i->>'offer_id') when i->>'category'=any(array['Snack','Drink','Household','Hygiene','Vegetables','Treats']) then 'Snack' else i->>'category' end)::integer from jsonb_array_elements(p_items)i));
 n:=greatest(1,n);normal:=(q->>'fee_cents')::integer;
 if r.custom_enabled then normal:=r.base_cents+greatest(n-1,0)*r.stop_cents;end if;
 offered:=r.offer_base_cents+greatest(n-1,0)*r.offer_stop_cents;
 offer_on:=coalesce(r.offer_enabled and (r.offer_ends_at is null or now()<r.offer_ends_at) and offered<normal,false);
 fee:=case when offer_on then offered else normal end;
 return q||jsonb_build_object('fee_cents',fee,'normal_fee_cents',normal,'savings_cents',normal-fee,'offer_active',offer_on,'pickup_count',n,'base_fee_cents',case when offer_on then r.offer_base_cents when r.custom_enabled then r.base_cents else (q->>'base_fee_cents')::int end,'extra_stop_fee_cents',case when offer_on then (n-1)*r.offer_stop_cents when r.custom_enabled then (n-1)*r.stop_cents else (q->>'extra_stop_fee_cents')::int end,'offer_ends_at',r.offer_ends_at,'fee_settings_updated_at',r.updated_at);
end $$;
revoke all on function public.swift_region_quote(jsonb,text) from public;
grant execute on function public.swift_region_quote(jsonb,text) to anon,authenticated;

