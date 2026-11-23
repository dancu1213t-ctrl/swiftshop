import { createClient } from 'npm:@supabase/supabase-js@2.117.2';
const allowed = new Set(['https://swiftshopow.com','https://www.swiftshopow.com']);
export async function handler(req: Request) {
 const origin=req.headers.get('origin')||'';
 const headers={'Content-Type':'application/json','Vary':'Origin',...(allowed.has(origin)?{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'}:{})};
 const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
 if(origin&&!allowed.has(origin))return reply({error:'Origin is not allowed'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({error:'Use POST'},405);
 let created:string|null=null,service:any;
 try {
  const token=req.headers.get('Authorization')||'';
  if(!/^Bearer .+/.test(token))return reply({error:'Administrator sign-in required'},401);
  const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!;
  const db=createClient(url,anon,{global:{headers:{Authorization:token}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:authError}=await db.auth.getUser();
  if(authError||!identity.user)return reply({error:'Administrator sign-in required'},401);
  const access=await db.rpc('swift_admin_portal_access');
  if(access.error)return reply({error:'Admin portal access required'},403);
  if(Number(req.headers.get('content-length')||0)>1800000)return reply({error:'Choose smaller images'},413);
  const text=await req.text();if(text.length>1800000)return reply({error:'Choose smaller images'},413);
  const body=JSON.parse(text),id=String(body.request_id||'');
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))return reply({error:'Invalid store request'},400);
  const lookup=await db.rpc('swift_admin_quick_lookup',{p_id:id});if(lookup.error)throw lookup.error;
  if(lookup.data.category)return reply({category:lookup.data.category,email:lookup.data.email});
  const email=String(body.email||'').trim().toLowerCase(),password=String(body.password||'');
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254)return reply({error:'Enter a valid merchant login email'},400);
  if(password.length<10||password.length>128)return reply({error:'Use a password with 10–128 characters'},400);
  service=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  let uid=lookup.data.user_id;
  if(uid){
   if(lookup.data.email!==email)return reply({error:'This attempt already created '+lookup.data.email+'. Keep that login email when retrying.'},400);
   const updated=await service.auth.admin.updateUserById(uid,{password});if(updated.error)throw updated.error;
  }else{
   const result=await service.auth.admin.createUser({email,password,email_confirm:true,app_metadata:{swift_admin_store_request:id,swift_admin_created_by:identity.user.id}});
   if(result.error)return reply({error:result.error.message},400);
   uid=result.data.user.id;created=uid;
  }
  const result=await db.rpc('swift_admin_quick_store',{p_id:id,p_user:uid,p_data:body.store});
  // Keep the newly created login on a failed response. The same request ID
  // recovers it on retry without risking deletion after an ambiguous commit.
  if(result.error)throw result.error;
  created=null;return reply({category:result.data,email});
 }catch(error){
  // A transport failure can follow a committed database write. Never delete an
  // account here: retrying the same request recovers the published store.
  return reply({error:error instanceof Error?error.message:(error as any)?.message||'Could not publish. Please try again.'},400);
 }
}
if(import.meta.main)Deno.serve(handler);

