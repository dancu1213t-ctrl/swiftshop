begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values('00000000-0000-4000-8000-00000000c901','rollback-support-a@example.invalid',now(),false),('00000000-0000-4000-8000-00000000c902','rollback-support-b@example.invalid',now(),false);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000c901',true),set_config('request.jwt.claim.role','authenticated',true);
select public.swift_support_request('00000000-0000-4000-8000-00000000c911','general','Rollback-only support test');
select public.swift_support_request('00000000-0000-4000-8000-00000000c911','general','Rollback-only support test');
select public.swift_support_request('00000000-0000-4000-8000-00000000c912','topup_request','Rollback-only top-up reference',null,1250);
do $$begin
 if (select count(*) from public.swift_support_requests where owner_id=auth.uid())<>2 then raise exception 'FAIL: duplicate support record';end if;
 if jsonb_array_length(public.swift_support_list())<>2 then raise exception 'FAIL: own requests not returned';end if;
 if exists(select 1 from public.swiftpay_transactions where customer_id=auth.uid()) then raise exception 'FAIL: top-up request moved money';end if;
 begin perform public.swift_support_request(gen_random_uuid(),'order_problem','Invalid order access','00000000-0000-4000-8000-00000000c999');raise exception 'FAIL: unauthorized order';exception when insufficient_privilege then null;end;
 begin perform public.swift_support_review('00000000-0000-4000-8000-00000000c911','resolved','not admin');raise exception 'FAIL: customer reviewed request';exception when insufficient_privilege then null;end;
 begin perform public.swift_native_worker_push(repeat('a',60),'runner');raise exception 'FAIL: customer registered team device';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-00000000c902',true);
do $$begin
 if jsonb_array_length(public.swift_support_list())<>0 then raise exception 'FAIL: another account can read requests';end if;
 begin perform public.swift_support_request('00000000-0000-4000-8000-00000000c911','general','Different owner request');raise exception 'FAIL: request id takeover';exception when others then if sqlerrm='FAIL: request id takeover' then raise;end if;end;
 if has_table_privilege('authenticated','public.swift_support_requests','SELECT') then raise exception 'FAIL: direct support table access';end if;
 if has_function_privilege('anon','public.swift_support_list(boolean)','EXECUTE') then raise exception 'FAIL: anonymous support access';end if;
end $$;
select 'PASS: ownership, order authorization, admin review, retry deduplication, no wallet movement and native role checks' as result;
rollback;
