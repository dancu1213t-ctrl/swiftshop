import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
Deno.serve(async req=>{
 const origin=req.headers.get('origin')||'',allowed=['https://swiftshopow.com','https://www.swiftshopow.com'];
 const headers={'Content-Type':'application/json','Vary':'Origin',...(allowed.includes(origin)?{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'}:{})};
 const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
 if(origin&&!allowed.includes(origin))return reply({error:'Origin denied'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST')return reply({error:'Use POST'},405);
 try{
  const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:req.headers.get('Authorization')||''}},auth:{persistSession:false}});
  const identity=await db.auth.getUser();if(identity.error||!identity.data.user)return reply({error:'Sign in required'},401);
  const a=await db.rpc('swift_admin_portal_access');if(a.error||a.data.role!=='owner')return reply({error:'Only the owner creates area administrators'},403);
  const raw=await req.text();if(raw.length>5000)return reply({error:'Request too large'},413);
  const b=JSON.parse(raw),email=String(b.email||'').trim().toLowerCase(),password=String(b.password||'');
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254)return reply({error:'Enter a valid email'},400);
  const existing=await db.rpc('swift_admin_staff_account',{p_email:email});if(existing.error)throw existing.error;
  if(existing.data.user_id&&!existing.data.managed)return reply({error:'This email already has a personal account. Use a separate admin login email.'},400);
  const service=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
  let uid=existing.data.user_id;
  if(!uid){if(password.length<10||password.length>128)return reply({error:'Use a password with 10–128 characters'},400);const r=await service.auth.admin.createUser({email,password,email_confirm:true,app_metadata:{swift_staff_created_by:identity.data.user.id}});if(r.error)throw r.error;uid=r.data.user.id;}
  else if(password){if(password.length<10||password.length>128)return reply({error:'Use a password with 10–128 characters'},400);const r=await service.auth.admin.updateUserById(uid,{password});if(r.error)throw r.error;}
  const r=await db.rpc('swift_admin_staff_account',{p_email:email,p_user:uid,p_zone:b.zone_id,p_active:b.active!==false});if(r.error)throw r.error;
  return reply({saved:true});
 }catch(e){return reply({error:(e as any)?.message||'Could not save access'},400);}
});

