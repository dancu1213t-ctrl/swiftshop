import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
import webpush from 'npm:web-push@3.6.7';
import {SignJWT,importPKCS8} from 'npm:jose@6';
function allowedEndpoint(value:string){try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&(!u.port||u.port==='443')&&(u.hostname==='fcm.googleapis.com'||u.hostname==='updates.push.services.mozilla.com'||u.hostname==='web.push.apple.com'||/^[a-z0-9-]+\.notify\.windows\.com$/i.test(u.hostname));}catch{return false;}}
let bearer='',expires=0;
async function nativePush(job:any){
 const account=JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')||'{}');
 if(!account.project_id||!account.private_key||!account.client_email)throw Error('Native push configuration missing');
 if(Date.now()>=expires){const key=await importPKCS8(account.private_key,'RS256');const jwt=await new SignJWT({scope:'https://www.googleapis.com/auth/firebase.messaging'}).setProtectedHeader({alg:'RS256'}).setIssuer(account.client_email).setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h').sign(key);const r=await fetch('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:jwt}),signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Firebase authorization failed');const t=await r.json();bearer=t.access_token;expires=Date.now()+(Number(t.expires_in)-120)*1000;}
 const r=await fetch('https://fcm.googleapis.com/v1/projects/'+encodeURIComponent(account.project_id)+'/messages:send',{method:'POST',headers:{Authorization:'Bearer '+bearer,'Content-Type':'application/json'},body:JSON.stringify({message:{token:job.subscription.token,notification:{title:job.title,body:job.body},data:{page:job.page,notification_id:job.notification_id},android:{priority:'HIGH',ttl:'300s',notification:{channel_id:'delivery-updates-v2',sound:'default',tag:'team-'+job.notification_id}}}}),signal:AbortSignal.timeout(10000)});
 if(!r.ok){const body=await r.json().catch(()=>({}));const invalid=body.error?.details?.some((x:any)=>x.errorCode==='UNREGISTERED');throw Object.assign(Error('FCM delivery failed'),{statusCode:invalid?410:r.status});}
}
const json=(body:unknown,status=200)=>Response.json(body,{status});
Deno.serve(async request=>{
 if(request.method!=='POST')return json({error:'POST required'},405);
 const secret=Deno.env.get('DELIVERY_PUSH_WORKER_SECRET');if(!secret||request.headers.get('x-delivery-worker-secret')!==secret)return json({error:'Unauthorized'},401);
 const publicKey=Deno.env.get('TEAM_VAPID_PUBLIC_KEY')||Deno.env.get('VAPID_PUBLIC_KEY'),privateKey=Deno.env.get('TEAM_VAPID_PRIVATE_KEY')||Deno.env.get('VAPID_PRIVATE_KEY');
 if(!publicKey||!privateKey)return json({error:'Team VAPID configuration missing'},503);
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');if(!url||!key)return json({error:'Server configuration missing'},503);
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});try{webpush.setVapidDetails('mailto:dancu1213t@gmail.com',publicKey,privateKey);}catch{return json({error:'Invalid team VAPID configuration'},503);}
 const {data,error}=await db.rpc('swift_team_claim_push',{p_limit:30});if(error)return json({error:'Queue unavailable'},500);
 let sent=0,retries=0,expired=0,ackErrors=0;
 for(let offset=0;offset<(data||[]).length;offset+=6){await Promise.all(data.slice(offset,offset+6).map(async(job:any)=>{
 let result='sent',message=null;try{
 if(job.subscription?.platform==='android'){await nativePush(job);}else{
 if(!allowedEndpoint(job.subscription?.endpoint))throw Object.assign(Error('Unsupported push host'),{statusCode:410});
 const merchant=['merchant-orders','merchant-test'].includes(job.page);const page=['dispatch','available','active','rides','applications','payments','profile'].includes(job.page)?job.page:'dispatch';
 await webpush.sendNotification(job.subscription,JSON.stringify({title:job.title,body:job.body,tag:'team-'+job.notification_id,url:merchant?'https://portal.swiftshopow.com/?open=orders':'https://runner.swiftshopow.com/#'+page}),{TTL:300,urgency:'high',timeout:5000});}sent++;
 }catch(e:any){if(e.statusCode===404||e.statusCode===410){result='expired';expired++;}else{result='retry';retries++;}message=e.statusCode?'Push service HTTP '+e.statusCode:'Push send failed';}
 const {error}=await db.rpc('swift_team_finish_push',{p_notification:job.notification_id,p_device:job.device_id,p_attempt:job.attempts,p_result:result,p_error:message});if(error)ackErrors++;
 }));}
 return json({claimed:(data||[]).length,sent,retries,expired,ack_errors:ackErrors},ackErrors?500:200);
});
