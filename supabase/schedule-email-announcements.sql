-- Uses the existing delivery worker secret; never place secret values in source.
select cron.schedule('swiftshop-email-announcements','* * * * *',$job$
select net.http_post(
 url:='https://sbjadbqlmkktljfpqowc.supabase.co/functions/v1/email-announcements',
 headers:=jsonb_build_object('Content-Type','application/json','x-delivery-worker-secret',(select decrypted_secret from vault.decrypted_secrets where name='delivery_push_worker_secret' limit 1)),
 body:='{}'::jsonb,timeout_milliseconds:=55000
) where exists(select 1 from public.swift_email_deliveries where status in('pending','sending','failed') and attempts<5);
$job$);