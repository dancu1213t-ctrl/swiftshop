/* Administrator sessions never replace or store the customer's contact identity. */
(()=>{
 let client,verified=false,recovery=null;
 function expired(){verified=false;const screen=document.getElementById("adminScreen");if(screen)screen.style.display="none";window.openAdminLogin?.();const n=document.getElementById("adminSessionStatus");if(n)n.textContent="Your Admin session expired. Sign in again to continue.";}
 const authError=e=>e?.code==="42501"||e?.code==="PGRST301"||e?.code==="PGRST302"||e?.status===401||/jwt expired|invalid refresh token|refresh token not found|administrator session required/i.test(e?.message||"");
 async function recover(){if(!recovery)recovery=(async()=>{const r=await client.auth.refreshSession();if(r.error||!r.data?.session)throw Error("Your Admin session expired. Sign in again to continue.");const check=await client.rpc("swift_admin_session").abortSignal(AbortSignal.timeout(10000));if(check.error||check.data!==true)throw Error("Administrator access required.");})().finally(()=>{recovery=null;});try{await recovery;}catch(e){expired();throw e;}}

 const state={get verified(){return verified;},get client(){return client;},async request(run){
   if(!client||!verified)throw Error('Administrator sign-in required.');
   const s=await client.auth.getSession();if(s.error||!s.data?.session){expired();throw Error('Your Admin session expired. Sign in again to continue.');}
   if(s.data.session.expires_at&&s.data.session.expires_at*1000<Date.now()+60000)await recover();
   let result=await run(client);if(result?.error&&authError(result.error)){await recover();result=await run(client);if(result?.error&&authError(result.error)){expired();throw Error('Administrator access could not be verified. Sign in again.');}}
   return result;
  },async login(){
  const email=document.getElementById('adminName').value.trim(),password=document.getElementById('adminPhone').value;
  const notice=document.getElementById('adminSessionStatus');notice.textContent='Verifying administrator…';
  try{client||=supabase.createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{storageKey:'swiftshop.secure.admin',persistSession:false,autoRefreshToken:true,detectSessionInUrl:false}});
   const {error}=await client.auth.signInWithPassword({email,password});document.getElementById('adminPhone').value='';if(error)throw error;
   const result=await client.rpc('swift_admin_session').abortSignal(AbortSignal.timeout(10000));if(result.error)throw result.error;if(result.data!==true)throw Error('Administrator access required.');
   verified=true;document.documentElement?.classList.remove('swift-awaiting-auth');closeAdminLogin();enterApp();document.getElementById('adminScreen').style.display='block';window.switchAdminTab('products');notice.textContent='';
  }catch(e){verified=false;await client?.auth.signOut();notice.textContent=e.message;}
 },async signout(){verified=false;await client?.auth.signOut();}};
 window.SwiftAdmin=state;
 document.addEventListener('DOMContentLoaded',()=>{
 const email=document.getElementById('adminName');email.type='email';email.placeholder='Administrator email';email.setAttribute('aria-label','Administrator email');
 window.submitAdminLogin=()=>state.login();
 const logout=window.handleLogout;window.handleLogout=async function(...args){await state.signout();return logout.apply(this,args);};
 });
})();
