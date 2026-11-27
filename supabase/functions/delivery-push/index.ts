import { createClient } from 'npm:@supabase/supabase-js@2';
import { SignJWT, importPKCS8 } from 'npm:jose@6';
import webpush from 'npm:web-push@3.6.7';

const messages: Record<string, [string,string]> = {
  chat_message: ['Message from your runner','Open SwiftShop to reply.'],
  sent: ['Order sent','Your request is waiting for SwiftShop confirmation.'],
  accepted: ['Order accepted','SwiftShop has confirmed your request.'],
  preparing: ['Preparing your order','Your order is being prepared.'],
  finding_runner: ['Finding your runner','We’re arranging a runner for your delivery.'],
  runner_assigned: ['Runner assigned','Your runner is getting ready.'],
  on_the_way: ['Your order is on the way','Your runner has started the delivery.'],
  delivered: ['Delivered','Your delivery is complete.']
};
const rideMessages: Record<string, [string,string]> = {
 requested:['Finding your driver','Your SwiftRide request has been sent.'],
 accepted:['Driver on the way','Your driver accepted your SwiftRide request.'],
 arrived:['Your driver has arrived','Your SwiftRide driver is at the pickup point.'],
 in_progress:['Ride started','Your SwiftRide trip is underway.'],
 completed:['Ride completed','You have reached your destination.'],
 cancelled:['Ride cancelled','Your SwiftRide request has been cancelled.']
};
function env(name: string) { const value=Deno.env.get(name); if(!value) throw Error(`Missing ${name}`); return value; }
const db = createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'));
let fcmToken='', fcmExpiry=0, apnsToken='', apnsExpiry=0;
async function firebaseAuth() {
  if(Date.now()<fcmExpiry) return fcmToken;
  const account=JSON.parse(env('FIREBASE_SERVICE_ACCOUNT_JSON'));
  const key=await importPKCS8(account.private_key,'RS256');
  const assertion=await new SignJWT({scope:'https://www.googleapis.com/auth/firebase.messaging'}).setProtectedHeader({alg:'RS256'}).setIssuer(account.client_email).setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h').sign(key);
  const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion}),signal:AbortSignal.timeout(12000)});
  if(!response.ok) throw Error(`Firebase authorization failed HTTP ${response.status}`);
  const data=await response.json(); fcmToken=data.access_token; fcmExpiry=Date.now()+Math.max(0,Number(data.expires_in)-120)*1000; return fcmToken;
}
async function appleAuth() {
  if(Date.now()<apnsExpiry) return apnsToken;
  const key=await importPKCS8(env('APNS_PRIVATE_KEY').replace(/\\n/g,'\n'),'ES256');
  apnsToken=await new SignJWT({}).setProtectedHeader({alg:'ES256',kid:env('APNS_KEY_ID')}).setIssuer(env('APNS_TEAM_ID')).setIssuedAt().sign(key);
  apnsExpiry=Date.now()+45*60000; return apnsToken;
}
async function send(job: any) {
  let motion:any=null;
  if(job.kind==='delivery'&&['on_the_way','delivery_progress'].includes(job.phase)){
    const {data,error}=await db.rpc('swift_delivery_push_progress',{p_id:job.order_id});
    if(!error)motion=data;
    if(job.phase==='delivery_progress'&&!motion?.active)return {ok:true,invalid:false};
  }
  const progressUpdate=job.phase==='delivery_progress';
  if(progressUpdate)job={...job,phase:'on_the_way'};
  const [statusTitle,statusBody]=job.kind==='promotion'?[job.title,job.body]:(job.kind==='ride'?rideMessages:messages)[job.phase] || []; if(!statusTitle) throw Error('Unknown delivery phase');
  const title='SWIFTSHOP';
  let body=job.kind==='promotion'?statusBody:statusTitle+' — '+statusBody;
  if(motion?.active){const percent=Number(motion.progress);const count=motion.progress==null?0:Math.min(4,Math.floor(percent/25));const bar='━'.repeat(count)+'🏍️'+'─'.repeat(4-count)+'⌂';body=bar+'  '+(motion.progress==null?'Delivery started':percent+'% estimated progress')+(motion.eta_minutes?' · about '+motion.eta_minutes+' min':'')+'. '+(motion.mode==='gps_estimate'?'Based on recent runner GPS.':'Time-based estimate; not live GPS.')+(motion.delayed?' Awaiting delivery confirmation.':'');}
  const data=job.kind==='promotion'?{kind:job.phase==='test'?'push_test':'promotion',promotion_id:job.order_id,event_id:job.event_id}:job.kind==='ride'?{kind:'ride',ride_id:job.order_id,phase:job.phase,event_id:job.event_id}:{kind:'delivery',order_id:job.order_id,phase:job.phase,event_id:job.event_id};
  if(motion?.active)Object.assign(data,{progress:String(motion.progress??''),eta_minutes:String(motion.eta_minutes??''),progress_mode:String(motion.mode||'')});
  const collapseTag=job.kind==='delivery'&&job.phase!=='chat_message'?'swiftshop-delivery-'+job.order_id:job.kind==='ride'?'swiftshop-ride-'+job.order_id:'swiftshop-'+job.event_id;
  let response: Response;

  if(job.platform==='web') {
    const subscription=JSON.parse(job.device_token);
    const endpoint=new URL(subscription.endpoint);
    if(endpoint.protocol!=='https:'||endpoint.username||endpoint.password||(endpoint.port&&endpoint.port!=='443')||!(endpoint.hostname==='fcm.googleapis.com'||endpoint.hostname==='updates.push.services.mozilla.com'||endpoint.hostname==='web.push.apple.com'||/^[a-z0-9-]+\.notify\.windows\.com$/i.test(endpoint.hostname)))throw Error('Invalid push endpoint');
    const publicKey=Deno.env.get('TEAM_VAPID_PUBLIC_KEY')||env('VAPID_PUBLIC_KEY');
    const privateKey=Deno.env.get('TEAM_VAPID_PRIVATE_KEY')||env('VAPID_PRIVATE_KEY');
    webpush.setVapidDetails('mailto:dancu1213t@gmail.com',publicKey,privateKey);
    try {await webpush.sendNotification(subscription,JSON.stringify({title,body,data,tag:collapseTag,url:'https://swiftshopow.com/'}),{TTL:3600,urgency:'high',timeout:10000});return {ok:true,invalid:false};}
    catch(e:any){return {ok:false,invalid:e.statusCode===404||e.statusCode===410,reason:'web push HTTP '+(e.statusCode||'unavailable')};}
  }
  if(job.platform==='android') {
    const account=JSON.parse(env('FIREBASE_SERVICE_ACCOUNT_JSON'));
    const live = String(job.device_token).startsWith('swiftshop-live-v1:');
    const deviceToken = live ? String(job.device_token).slice('swiftshop-live-v1:'.length) : job.device_token;
    const fcmMessage = live ? {token:deviceToken,data:{...data,swift_live:'1',title,body,status_title:statusTitle},android:{priority:'high',ttl:'3600s'}} : {token:job.device_token,notification:{title,body},data,android:{priority:'high',ttl:'3600s',notification:{channel_id:job.kind==='promotion'?'swiftshop-promotions-v2':'delivery-updates-v2',tag:collapseTag,icon:'ic_stat_delivery',sound:'default'}}};
    response=await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`,{method:'POST',headers:{Authorization:`Bearer ${await firebaseAuth()}`,'Content-Type':'application/json'},body:JSON.stringify({message:fcmMessage}),signal:AbortSignal.timeout(12000)});
  } else {
    const host=env('APNS_ENVIRONMENT')==='production'?'api.push.apple.com':'api.sandbox.push.apple.com';
    response=await fetch(`https://${host}/3/device/${encodeURIComponent(job.device_token)}`,{method:'POST',headers:{authorization:`bearer ${await appleAuth()}`,'apns-topic':env('APNS_BUNDLE_ID'),'apns-push-type':'alert','apns-priority':'10','apns-collapse-id':collapseTag,'apns-expiration':String(Math.floor(Date.now()/1000)+3600),'Content-Type':'application/json'},body:JSON.stringify({aps:{alert:{title,body},sound:'default'},...data}),signal:AbortSignal.timeout(12000)});
  }
  if(response.ok) return {ok:true,invalid:false};
  const error=await response.json().catch(()=>({}));
  const invalid=job.platform==='android' ? error?.error?.details?.some((d:any)=>d.errorCode==='UNREGISTERED') : error.reason==='Unregistered';
  const code=job.platform==='android' ? error?.error?.status : error.reason;
  const safeCode=typeof code==='string'&&/^[A-Za-z_]{1,60}$/.test(code)?` ${code}`:'';
  return {ok:false,invalid:!!invalid,reason:`${job.platform} HTTP ${response.status}${safeCode}`};
}
Deno.serve(async request => {
  if(request.method!=='POST') return new Response('Method not allowed',{status:405});
  const secret=Deno.env.get('DELIVERY_PUSH_WORKER_SECRET');
  const supplied=request.headers.get('x-delivery-worker-secret');
  if(!secret) return Response.json({error:'worker_secret_missing',message:'DELIVERY_PUSH_WORKER_SECRET is not set for this function.'},{status:401});
  if(!supplied) return Response.json({error:'worker_header_missing',message:'The request has no x-delivery-worker-secret header.'},{status:401});
  if(supplied!==secret) return Response.json({error:'worker_secret_mismatch',message:'The supplied worker secret does not match the function secret.'},{status:401});
  let {data:jobs,error}=await db.rpc('claim_delivery_push_jobs_v2');
  if(error?.code==='PGRST202') ({data:jobs,error}=await db.rpc('claim_delivery_push_jobs'));
  if(error) return Response.json({error:'queue_unavailable',database_code:error.code || 'unknown',message:(error.message || 'Queue request failed').replace(/eyJ[A-Za-z0-9_.-]+/g,'[redacted]').slice(0,400)},{status:503});
  const promotionQueue=await db.rpc('claim_promotion_push_jobs');
  if(promotionQueue.error&&promotionQueue.error.code!=='PGRST202')console.error('Promotion queue unavailable',{code:promotionQueue.error.code});
  jobs=[...(jobs||[]),...(promotionQueue.data||[])];
  const results=await Promise.all((jobs||[]).map(async (job:any)=>{
    try {
      const result=await send(job);
      if(result.invalid) {
        await db.from('delivery_push_devices').delete().eq('install_id',job.install_id).eq('device_token',job.device_token);
      } else {
        const patch=result.ok ? {sent_at:new Date().toISOString(),lease_until:null,last_error:null} : retry(job,result.reason||'Provider rejected notification');
        const {error}=await db.from(job.kind==='promotion'?'promotion_push_jobs':'delivery_push_jobs').update(patch).eq('id',job.job_id).eq('lease_token',job.lease_token);
        if(error) throw Error('Could not acknowledge notification');
      }
      return result.ok?'sent':result.invalid?'removed':'retry';
    } catch (error) {
      const message=error instanceof Error ? error.message : '';
      const safeMessage=/^(Missing [A-Z_]+|Firebase authorization failed HTTP \d{3}|Could not acknowledge notification)$/.test(message)?message:'Notification provider unavailable or misconfigured';
      await db.from(job.kind==='promotion'?'promotion_push_jobs':'delivery_push_jobs').update(retry(job,safeMessage)).eq('id',job.job_id).eq('lease_token',job.lease_token);
      return 'retry';
    }
  }));
  return Response.json({claimed:results.length,sent:results.filter(r=>r==='sent').length,retries:results.filter(r=>r==='retry').length});
});
function retry(job:any, reason:string) { return {lease_until:null,last_error:reason,next_attempt_at:new Date(Date.now()+Math.min(3600,15*2**Math.min(job.attempts,8))*1000).toISOString(),failed_at:job.attempts>=12?new Date().toISOString():null}; }



