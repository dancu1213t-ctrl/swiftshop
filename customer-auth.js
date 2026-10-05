/* Verified email customers; existing balances require an independently approved claim. */
(()=>{
 document.addEventListener('DOMContentLoaded',()=>{
 const login=document.getElementById('loginBox');if(!login)return;
 const make=(tag,text)=>{const n=document.createElement(tag);if(text)n.textContent=text;return n;};
 const email=make('input');email.type='email';email.id='customerAuthEmail';email.placeholder='Email address';email.autocomplete='email';email.setAttribute('aria-label','Email address');
 const code=make('input');code.id='customerAuthCode';code.placeholder='Email verification code';code.autocomplete='one-time-code';code.inputMode='numeric';code.hidden=true;code.setAttribute('aria-label','Email verification code');
 const emailLabel=make('label','Email address');emailLabel.setAttribute('for',email.id);emailLabel.setAttribute('class','customer-auth-label');const codeLabel=make('label','Verification code');codeLabel.setAttribute('for',code.id);codeLabel.setAttribute('class','customer-auth-label');codeLabel.hidden=true;
 const status=make('p');status.id='customerAuthStatus';status.setAttribute('role','status');status.setAttribute('aria-live','polite');
 const send=login.querySelector('button[onclick="handleLogin()"]');send.textContent='Send email code';send.before(emailLabel,email,codeLabel,code);send.after(status);
 const contacts=document.getElementById('customerContactSetup');contacts.hidden=true;
 let pendingEmail='',pendingName='',pendingPhone='',busy=false;
 function resetContact(){contacts.hidden=true;pendingName='';pendingPhone='';document.getElementById('userName').value='';document.getElementById('userPhone').value='';}
 function authScreen(){document.getElementById('appScreen').style.display='none';document.getElementById('authScreen').style.display='flex';}
 async function finish(animate=false){const result=await customerDataClient.rpc('swift_customer_profile',{p_name:pendingName||null,p_phone:pendingPhone||null}).abortSignal(AbortSignal.timeout(10000));if(result.error)throw result.error;const p=result.data;if(!p){contacts.hidden=false;code.hidden=true;codeLabel.hidden=true;change.hidden=false;send.textContent='Save delivery contact';status.textContent='Email verified. Add your name and phone so stores and drivers can reach you.';document.getElementById('userName').focus();return false;}if(p.claim_required){status.textContent=p.message+' Email dancu1213t@gmail.com, then return here after approval.';send.textContent='Check account approval';return false;}
 localStorage.setItem('userName',p.name||'Customer');localStorage.setItem('userPhone',p.phone);localStorage.setItem('points',p.points||0);localStorage.setItem('loggedIn','true');customerName=p.name;customerPhone=p.phone;customerEmail=p.email;window.userPhone=p.phone;code.value='';code.hidden=true;codeLabel.hidden=true;document.documentElement?.classList.remove('swift-awaiting-auth');if(animate&&window.showSwiftShopWelcome)window.showSwiftShopWelcome(enterApp);else enterApp();return true;}
 window.handleLogin=async()=>{if(busy)return;busy=true;send.disabled=true;try{
 const session=await customerDataClient.auth.getSession();if(session.data.session?.user?.email_confirmed_at){if(!contacts.hidden){pendingName=document.getElementById('userName').value.trim();pendingPhone=document.getElementById('userPhone').value.trim();if(!pendingName||!pendingPhone)throw Error('Enter your name and delivery contact phone.');}await finish(true);return;}
 if(!pendingEmail){if(!email.checkValidity()||!email.value.trim())throw Error('Enter a valid email address.');resetContact();pendingEmail=email.value.trim();const {error}=await customerDataClient.auth.signInWithOtp({email:pendingEmail,options:{shouldCreateUser:true}});if(error){pendingEmail='';throw error;}email.readOnly=true;code.hidden=false;codeLabel.hidden=false;change.hidden=false;send.textContent='Verify & continue';status.textContent='Check your email and enter the verification code.';code.focus();}
 else{const token=code.value.trim();if(!/^\d{6,10}$/.test(token))throw Error('Enter the code from your email.');const {error}=await customerDataClient.auth.verifyOtp({email:pendingEmail,token,type:'email'});if(error)throw error;await finish(true);}
 }catch(e){status.textContent=e.message;}finally{busy=false;send.disabled=false;}};
 const change=make('button','Use another email');change.type='button';change.id='customerAuthChange';change.hidden=true;change.onclick=async()=>{await customerDataClient.auth.signOut();pendingEmail='';resetContact();change.hidden=true;email.readOnly=false;code.hidden=true;codeLabel.hidden=true;code.value='';send.textContent='Send email code';status.textContent='';};send.after(change);
 const logout=window.handleLogout;window.handleLogout=async function(...args){await customerDataClient.auth.signOut();document.documentElement?.classList.add('swift-awaiting-auth');pendingEmail='';resetContact();change.hidden=true;email.readOnly=false;code.hidden=true;codeLabel.hidden=true;send.textContent='Send email code';return logout.apply(this,args);};
 window.saveProfile=async()=>{try{const result=await customerDataClient.rpc('swift_customer_profile',{p_name:document.getElementById('profileName').value.trim()});if(result.error)throw result.error;localStorage.setItem('userName',result.data.name);localStorage.setItem('userPhone',result.data.phone);document.getElementById('profileDisplayName').textContent=result.data.name;document.getElementById('profilePhone').value=result.data.phone;}catch(e){alert(e.message);}};
 const phoneField=document.getElementById('profilePhone');if(phoneField){phoneField.readOnly=true;phoneField.title='Contact support to change the account phone safely.';}
 const restorePanel=document.getElementById('customerSessionRestore');
 async function restoreSession(){
  try{const r=await customerDataClient.auth.getSession();if(r.error)throw r.error;
   if(!r.data.session?.user?.email_confirmed_at){restorePanel.hidden=true;authScreen();return;}
   document.getElementById('authScreen').style.display='none';restorePanel.hidden=false;
   document.getElementById('customerSessionRestoreStatus').textContent='Welcome back';
   document.getElementById('customerSessionRetry').hidden=true;document.getElementById('customerSessionLogout').hidden=true;
   if(await finish(true))restorePanel.hidden=true;else{restorePanel.hidden=true;authScreen();}
  }catch(e){document.getElementById('authScreen').style.display='none';restorePanel.hidden=false;document.getElementById('customerSessionRestoreStatus').textContent='Could not reconnect. Your saved session has not been signed out.';document.getElementById('customerSessionRetry').hidden=false;document.getElementById('customerSessionLogout').hidden=false;}
  finally{document.documentElement?.classList.remove('swift-restoring-auth');}
 }
 document.getElementById('customerSessionRetry').onclick=restoreSession;
 document.getElementById('customerSessionLogout').onclick=async()=>{await window.handleLogout();restorePanel.hidden=true;authScreen();};
 restoreSession();
 });
})();
