begin;
do $$
declare h jsonb:='{}'; i integer; uid uuid:=gen_random_uuid(); response jsonb; store text:='Dumpling'; denied boolean:=false;
begin
 for i in 1..7 loop h:=h||jsonb_build_object(i::text,jsonb_build_object('closed',i=7,'open','08:00','close','17:00'));end loop;
 assert public.swift_weekly_hours_valid(h),'valid schedule';
 assert not public.swift_weekly_hours_valid('{}'),'missing weekdays';
 assert not public.swift_weekly_hours_valid(jsonb_set(h,'{1,open}','"25:00"')),'invalid time';
 assert public.swift_weekly_hours_open(h,'2026-11-23 14:00Z'),'Monday opens at 08 Belize';
 assert not public.swift_weekly_hours_open(h,'2026-11-23 23:00Z'),'closed at closing boundary';
 assert not public.swift_weekly_hours_open(h,'2026-11-22 16:00Z'),'Sunday closed';
 h:=jsonb_set(jsonb_set(h,'{1,open}','"20:00"'),'{1,close}','"02:00"');
 assert public.swift_weekly_hours_open(h,'2026-11-24 07:00Z'),'previous-day overnight shift';
 assert not public.swift_weekly_hours_open(h,'2026-11-24 08:00Z'),'overnight closing boundary';
 insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,is_anonymous,aud,role)
 values(uid,'hours-'||uid||'@example.invalid',now(),'{"provider":"email"}','{}',false,'authenticated','authenticated');
 perform set_config('request.jwt.claim.sub',uid::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 begin perform public.swift_save_store_weekly_hours(store,h,true);exception when others then denied:=true;end;
 assert denied,'unassigned user rejected';
 insert into public.merchant_members(user_id,category) values(uid,store);
 response:=public.swift_save_store_weekly_hours(store,h,true);
 assert response->>'category'=store,'assigned merchant save confirmed';
 update public.merchant_storefronts set weekly_hours=(select jsonb_object_agg(n::text,jsonb_build_object('closed',true)) from generate_series(1,7)n),auto_close=true where category=store;
 assert not public.swift_store_scheduled_open(store),'closed-week schedule enforced';
 assert not exists(select 1 from jsonb_array_elements(public.swift_budget_meals(2000,'orange-walk')) x where x->>'category'=store),'closed store excluded from finder';
 assert not exists(select 1 from jsonb_array_elements(public.swift_budget_meals(500,'orange-walk')) x where (x->>'price')::numeric>5),'budget bounded';
 assert public.swift_budget_meals(500,'invalid-zone')='[]'::jsonb,'zone isolated';
end $$;
select 'PASS: weekly boundaries, Belize timezone, overnight hours, ownership, closed stores and price/zone filtering' verification;
rollback;