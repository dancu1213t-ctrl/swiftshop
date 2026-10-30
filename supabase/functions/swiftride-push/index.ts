// Deploy as swiftride-push; keep verify_jwt=false for authenticated database webhooks.
// Secrets: SWIFT_RIDE_WEBHOOK_SECRET, VAPID_PRIVATE_KEY, VAPID_PUBLIC_KEY, VAPID_SUBJECT, DRIVER_PORTAL_URL.
import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';
const env=(key:string)=>{const value=Deno.env.get(key);if(!value)throw new Error('Missing '+key);return value;};
const db=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'));
webpush.setVapidDetails(env('VAPID_SUBJECT'),env('VAPID_PUBLIC_KEY'),env('VAPID_PRIVATE_KEY'));
function deliveryResult(reason:string, body:string, status=200){console.log(JSON.stringify({event:'swiftride-push-result',reason,status}));return new Response(body,{status});}
function allowedEndpoint(value:string){try{const u=new URL(value);return u.protocol==='https:'&&!u.port&&!u.username&&!u.password&&(u.hostname==='fcm.googleapis.com'||u.hostname==='updates.push.services.mozilla.com'||u.hostname==='push.services.mozilla.com'||u.hostname.endsWith('.notify.windows.com')||u.hostname.endsWith('.push.apple.com'));}catch{return false;}}
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return new Response('Method not allowed',{status:405});
 if(req.headers.get('x-swift-webhook-secret')!==env('SWIFT_RIDE_WEBHOOK_SECRET'))return new Response('Unauthorized',{status:401});
 try{
  const event=await req.json();const id=event.record?.id;
  if(event.table!=='swiftride_orders'||event.type!=='INSERT'||typeof id!=='string')return deliveryResult('ignored_event','Ignored');
  const {data:ride,error:rideError}=await db.from('swiftride_orders').select('id,status,zone_id').eq('id',id).maybeSingle();
  if(rideError)throw rideError;if(!ride||ride.status!=='requested')return deliveryResult('ride_not_requested','Ride no longer open');
  // This preference survives backgrounding, closing the page and stale GPS.
  const {data:online,error:onlineError}=await db.from('swiftride_driver_online_preferences').select('driver_id').eq('online',true);
  if(onlineError)throw onlineError;
  const {data:quote,error:quoteError}=await db.from('swiftride_pricing_ledger').select('driver_id').eq('ride_id',id).maybeSingle();
  if(quoteError)throw quoteError;
  const {data:zoneWorkers,error:zoneError}=await db.from('swift_worker_zones').select('user_id').eq('zone_id',ride.zone_id);if(zoneError)throw zoneError;
  const zoneIds=new Set((zoneWorkers||[]).map((w:{user_id:string})=>w.user_id));
  const ids=(online||[]).map((d:{driver_id:string})=>d.driver_id).filter((driverId:string)=>zoneIds.has(driverId)&&(!quote||driverId===quote.driver_id));
  if(!ids.length)return deliveryResult('no_online_quoted_driver','No opted-in drivers for this request');
  const {data:approved,error:approvedError}=await db.from('swift_worker_applications').select('user_id').eq('kind','driver').eq('status','approved').in('user_id',ids);
  if(approvedError)throw approvedError;
  console.log(JSON.stringify({event:'swiftride-push-recipients',rideId:id,optedIn:ids.length,quotedDriver:Boolean(quote)}));
  const approvedIds=(approved||[]).map((a:{user_id:string})=>a.user_id);if(!approvedIds.length)return deliveryResult('no_approved_driver','No approved drivers');
  const {data:profiles,error:profileError}=await db.from('profiles').select('id').eq('active',true).in('id',approvedIds);
  if(profileError)throw profileError;
  const {data:busy,error:busyError}=await db.from('swiftride_orders').select('driver_id').in('status',['accepted','arrived','in_progress']);
  if(busyError)throw busyError;
  const busyIds=new Set((busy||[]).map((r:{driver_id:string})=>r.driver_id));
  const available=(profiles||[]).map((p:{id:string})=>p.id).filter((driverId:string)=>!busyIds.has(driverId));
  if(!available.length)return deliveryResult('no_active_free_driver','No free drivers');
  const {data:subs,error:subError}=await db.from('swift_driver_push').select('endpoint,subscription,user_id').in('user_id',available);
  if(subError)throw subError;
  console.log(JSON.stringify({event:'swiftride-push-subscriptions',rideId:id,availableDrivers:available.length,subscriptions:(subs||[]).length}));
  const portal=new URL(env('DRIVER_PORTAL_URL'));portal.hash='rides';if(portal.protocol!=='https:')throw Error('Driver portal must use HTTPS');
  const payload=JSON.stringify({title:'SwiftRide · New ride request',body:'A passenger is waiting. Open your driver page to accept.',url:portal.href,tag:'swiftride-'+id});
  let failures=0,sent=0,skipped=0,expired=0;
  for(let start=0;start<(subs||[]).length;start+=10){await Promise.all((subs||[]).slice(start,start+10).map(async(s:{endpoint:string;subscription:object;user_id:string})=>{
   if(!allowedEndpoint(s.endpoint)){skipped++;return;}
   // Respect a manual opt-out even if it happened after the initial recipient query.
   const {data:preference,error:preferenceError}=await db.from('swiftride_driver_online_preferences').select('online').eq('driver_id',s.user_id).maybeSingle();
   if(preferenceError){failures++;return;}if(!preference?.online){skipped++;return;}
   try{await webpush.sendNotification(s.subscription as Parameters<typeof webpush.sendNotification>[0],payload,{TTL:60});sent++;}
   catch(error){const e=error as {statusCode?:number};console.warn(JSON.stringify({event:'swiftride-push-provider-error',rideId:id,statusCode:e.statusCode??null}));if(e.statusCode===404||e.statusCode===410){expired++;await db.from('swift_driver_push').delete().eq('endpoint',s.endpoint);}else failures++;}
  }));}
  console.log(JSON.stringify({event:'swiftride-push-delivery',rideId:id,sent,failures,skipped,expired}));
  return new Response(JSON.stringify({sent,failures,skipped,expired}),{status:failures?503:200,headers:{'content-type':'application/json'}});
 }catch(error){console.error('Ride push failed',error instanceof Error?error.message:'unknown');return new Response('Push delivery failed',{status:500});}
});
