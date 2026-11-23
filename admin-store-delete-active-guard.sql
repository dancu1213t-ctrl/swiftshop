CREATE OR REPLACE FUNCTION public.swift_admin_delete_store(p_category text, p_confirm text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.swift_store_registry;result jsonb;
begin
 if public.swift_admin_portal_access()->>'role'<>'owner' then raise exception 'Only the owner can permanently delete a store' using errcode='42501';end if;
 select * into r from public.swift_store_registry where category=p_category for update;if not found then raise exception 'Store not found';end if;
 result:=jsonb_build_object('name',r.name,'products',(select count(*) from public.products where category=p_category),'banners',(select count(*) from public.store_paid_banners where category=p_category),'offers',(select count(*) from public.swift_store_offers where category=p_category),'history_preserved',true);
 if p_confirm is null then return result;end if;
 if p_confirm is distinct from r.name then raise exception 'Type the exact store name to delete it';end if;
 if exists(select 1 from public.orders where status not in('Delivered','Cancelled') and (store_name=p_category or store_name=r.name or run_stops::text like '%'||p_category||'%')) or exists(select 1 from public.store_live_orders where category=p_category and lower(status) not in('delivered','cancelled','completed','rejected')) or exists(select 1 from public.customer_order_tracking where phase not in('delivered','cancelled') and snapshot::text like '%'||p_category||'%') then raise exception 'Finish or cancel active orders before deleting this store';end if;
 perform pg_advisory_xact_lock(hashtextextended('delete-store:'||p_category,0));
 delete from public.product_likes where product_id in(select id from public.products where category=p_category);
 delete from public.products where category=p_category;
 delete from public.store_paid_banners where category=p_category;
 delete from public.store_paid_ads where category=p_category;
 delete from public.merchant_campaigns where category=p_category;
 delete from public.swift_store_offers where category=p_category;
 delete from public.promos where category=p_category;
 delete from public.app_promotions where category=p_category;
 delete from public.merchant_members where category=p_category;
 delete from public.swift_merchant_delivery where category=p_category;
 delete from public.merchant_storefronts where category=p_category;
 delete from public.swift_store_onboarding where category=p_category;
 delete from public.swift_store_registry where category=p_category;
 delete from public.stores where category=p_category;
 update public.swiftpay_store_providers set active=false where category=p_category;
 update public.swift_merchant_commission_accounts set active=false where category=p_category;
 insert into public.swift_region_audit(actor_id,action,entity,detail) values(auth.uid(),'store_deleted',p_category,result);
 return result||jsonb_build_object('deleted',true);
end $function$


