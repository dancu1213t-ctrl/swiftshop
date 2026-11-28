create or replace function swift_tracking_private.runner_location(p_id uuid) returns jsonb language plpgsql stable set search_path='' as $$
declare t public.customer_order_tracking;o public.orders;m swift_tracking_private.motion;points jsonb;fresh boolean;
begin
 select * into t from public.customer_order_tracking where id=p_id;
 if not found or t.phase in('delivered','cancelled') then return jsonb_build_object('active',false);end if;
 select * into o from public.orders where order_id=t.linked_order_id;
 if o.assigned_runner_id is null or o.status not in('Claimed','On the Way') then return jsonb_build_object('active',false);end if;
 select * into m from swift_tracking_private.motion where order_id=p_id and runner_id=o.assigned_runner_id;
 fresh:=coalesce(m.observed_at>now()-interval '45 seconds' and m.observed_at<=now()+interval '10 seconds',false);
 points:=swift_tracking_private.endpoints(p_id);
 return jsonb_build_object('active',true,'fresh',fresh,'lat',case when fresh then m.lat end,'lng',case when fresh then m.lng end,'updated_at',m.observed_at,'leg',case when t.phase='on_the_way' or m.departed_at is not null then 'dropoff' else 'pickup' end,'pickup',points->'pickup','dropoff',points->'dropoff','order_id',p_id);
end $$;
revoke all on function swift_tracking_private.runner_location(uuid) from public,anon,authenticated;
create or replace function public.get_customer_tracking(p_id uuid,p_token uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r jsonb;begin
 r:=public.get_customer_tracking_before_motion(p_id,p_token);
 return r||jsonb_build_object('delivery_progress',swift_tracking_private.progress(p_id),'runner_location',swift_tracking_private.runner_location(p_id));
end $$;