import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
const url=Deno.env.get('SUPABASE_URL')!,service=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const headers={'Access-Control-Allow-Origin':'https://swiftshopow.com','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Content-Type':'application/json'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
async function processQueue(){
 const key=Deno.env.get('RESEND_API_KEY'),from=Deno.env.get('SWIFT_EMAIL_FROM');if(!key||!from)return;
 for(let i=0;i<30;i++){
  const {data:job,error}=await service.rpc('swift_email_claim');if(error)throw error;if(!job)break;
  const unsubscribe=url+'/functions/v1/email-announcements?unsubscribe='+encodeURIComponent(job.token);
  const footer='<p style="text-align:center;font:12px Arial;color:#777;padding:20px">SwiftShop · Orange Walk, Belize<br><a href="'+unsubscribe+'">Unsubscribe from announcement emails</a></p>';
  const html=/<\/body\s*>/i.test(job.html)?job.html.replace(/<\/body\s*>/i,footer+'</body>'):job.html+footer;
  try{
   const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json','Idempotency-Key':'swift-email/'+job.campaign_id+'/'+job.token},body:JSON.stringify({from,to:[job.email],subject:job.subject,html,headers:{'List-Unsubscribe':'<'+unsubscribe+'>','List-Unsubscribe-Post':'List-Unsubscribe=One-Click'}}),signal:AbortSignal.timeout(15000)});
   const result=await response.json();if(!response.ok||!result.id)throw Error('Email provider rejected request ('+response.status+').');
   const done=await service.from('swift_email_deliveries').update({status:'sent',provider_id:result.id,last_error:null}).eq('campaign_id',job.campaign_id).eq('email',job.email);if(done.error)throw done.error;
  }catch(e){await service.from('swift_email_deliveries').update({status:'failed',last_error:String(e).slice(0,200),next_attempt_at:new Date(Date.now()+60000).toISOString()}).eq('campaign_id',job.campaign_id).eq('email',job.email);}
  await new Promise(resolve=>setTimeout(resolve,600));
 }
}
Deno.serve(async request=>{
 if(request.method==='OPTIONS')return new Response(null,{headers});
 const token=new URL(request.url).searchParams.get('unsubscribe');
 if(token){if(!/^[0-9a-f-]{36}$/i.test(token))return reply({error:'Invalid link'},400);if(request.method==='GET')return new Response('<html><body style="font-family:Arial;padding:40px"><h1>SwiftShop email preferences</h1><form method="post"><button>Unsubscribe from announcement emails</button></form></body></html>',{headers:{'Content-Type':'text/html;charset=utf-8'}});if(request.method==='POST'){const r=await service.from('swift_email_suppressions').update({unsubscribed_at:new Date().toISOString()}).eq('token',token).select('token');if(r.error||!r.data?.length)return reply({error:'Invalid link'},400);return new Response('You are unsubscribed from SwiftShop announcement emails. Account and order emails are unchanged.');}return reply({error:'Method not allowed'},405);}
 if(request.method!=='POST')return reply({error:'Method not allowed'},405);
 const workerSecret=Deno.env.get('DELIVERY_PUSH_WORKER_SECRET');
 if(workerSecret&&request.headers.get('x-delivery-worker-secret')===workerSecret){await processQueue();return reply({processed:true});}
 try{
  const client=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:request.headers.get('Authorization')||''}}});
  const {data:identity,error:authError}=await client.auth.getUser();if(authError||!identity.user)return reply({error:'Sign in required'},401);
  const role=await client.rpc('swift_worker_kind');if(role.error||role.data!=='admin')return reply({error:'Administrator access required'},403);
  const body=await request.json();const configured=!!Deno.env.get('RESEND_API_KEY')&&!!Deno.env.get('SWIFT_EMAIL_FROM');
  if(body.action==='setup')return reply({configured,sender:Deno.env.get('SWIFT_EMAIL_FROM')||null});
  if(body.action==='test'){
   if(!configured)return reply({error:'Email sender setup is incomplete'},503);
   if(typeof body.subject!=='string'||!body.subject.trim()||body.subject.length>150||typeof body.html!=='string'||new TextEncoder().encode(body.html).length>250000)return reply({error:'Invalid subject or HTML'},400);
   const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+Deno.env.get('RESEND_API_KEY'),'Content-Type':'application/json'},body:JSON.stringify({from:Deno.env.get('SWIFT_EMAIL_FROM'),to:[identity.user.email],subject:'[Preview] '+body.subject,html:body.html}),signal:AbortSignal.timeout(15000)});const result=await r.json();if(!r.ok||!result.id)return reply({error:'Test email was rejected by the provider'},502);return reply({sent:true});
  }
  if(body.action==='queue'&&!configured)return reply({error:'Email sender setup is incomplete'},503);
  if(!['audience','list','save','queue'].includes(body.action))return reply({error:'Unknown action'},400);
  const {data,error}=await client.rpc('swift_email_admin',{p_action:body.action,p_id:body.id||null,p_subject:body.subject||null,p_html:body.html||null});if(error)return reply({error:error.message},400);
  if(body.action==='queue')EdgeRuntime.waitUntil(processQueue());return reply(data);
 }catch{return reply({error:'Email request could not be completed. Please retry.'},500);}
});