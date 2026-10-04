/* Administrator sessions never replace or store the customer's contact identity. */
(()=>{
 let client,verified=false;
 const state={get verified(){return verified;},get client(){return client;},async login(){
  const email=document.getElementById('adminName').value.trim(),password=document.getElementById('adminPhone').value;
  const notice=document.getElementById('adminSessionStatus');notice.textContent='Verifying administrator…';
  try{client||=supabase.createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{storageKey:'swiftshop.secure.admin',persistSession:false,autoRefreshToken:true,detectSessionInUrl:false}});
   const {error}=await client.auth.signInWithPassword({email,password});document.getElementById('adminPhone').value='';if(error)throw error;
   const result=await client.rpc('swift_admin_session').abortSignal(AbortSignal.timeout(10000));if(result.error)throw result.error;if(result.data!==true)throw Error('Administrator access required.');
   verified=true;closeAdminLogin();enterApp();document.getElementById('adminScreen').style.display='block';window.switchAdminTab('products');notice.textContent='';
  }catch(e){verified=false;await client?.auth.signOut();notice.textContent=e.message;}
 },async signout(){verified=false;await client?.auth.signOut();}};
 window.SwiftAdmin=state;
 document.addEventListener('DOMContentLoaded',()=>{
 const email=document.getElementById('adminName');email.type='email';email.placeholder='Administrator email';email.setAttribute('aria-label','Administrator email');
 window.submitAdminLogin=()=>state.login();
 const logout=window.handleLogout;window.handleLogout=async function(...args){await state.signout();return logout.apply(this,args);};
 });
})();

