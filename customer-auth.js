/* Verified email identity restores the same private customer profile on every device. */
(()=>{
 document.addEventListener('DOMContentLoaded',()=>{
 const login=document.getElementById('loginBox');if(!login)return;
 const make=(tag,text)=>{const n=document.createElement(tag);if(text)n.textContent=text;return n;};
 const styles=make('style');styles.textContent='#loginBox #customerAuthModes{display:flex;gap:4px;padding:5px;margin:22px 0 10px;background:#f2f2ec;border:1px solid #e7e8df;border-radius:18px}#loginBox #customerAuthModes button{flex:1;width:auto;margin:0;padding:12px 8px;border:0;border-radius:13px;font:inherit;font-size:14px;font-weight:700;background:transparent!important;color:#6d756c!important;box-shadow:none!important}#loginBox #customerAuthModes button[aria-pressed="true"]{background:#fff!important;color:#252f27!important;box-shadow:0 2px 7px #24332512!important}#loginBox #customerAuthModes button:focus-visible{outline:2px solid #ff7200;outline-offset:2px}#loginBox #customerAuthModeHelp{font-size:13px;line-height:1.5;color:#6d756c;margin:0 0 18px}#loginBox #customerAuthRemember{font-size:12px;line-height:1.5;color:#7c8378;margin:14px 0 0}';document.body.append(styles);
 const modes=make('div');modes.id='customerAuthModes';modes.setAttribute('role','group');modes.setAttribute('aria-label','Sign in or sign up');
 const signIn=make('button','Sign in'),signUp=make('button','Sign up');signIn.id='customerSignIn';signUp.id='customerSignUp';signIn.type=signUp.type='button';modes.append(signIn,signUp);
 const help=make('p');help.id='customerAuthModeHelp';
 const remember=make('p','Stay signed in on this device until you log out.');remember.id='customerAuthRemember';
 const email=make('input');email.type='email';email.id='customerAuthEmail';email.placeholder='Email address';email.autocomplete='email';email.setAttribute('aria-label','Email address');
 const code=make('input');code.id='customerAuthCode';code.placeholder='Email verification code';code.autocomplete='one-time-code';code.inputMode='numeric';code.hidden=true;code.setAttribute('aria-label','Email verification code');
 const password=make('input');password.id='customerAuthPassword';password.type='password';password.placeholder='Your password';password.autocomplete='current-password';password.setAttribute('aria-label','Password');
 const passwordLabel=make('label','Password');passwordLabel.setAttribute('for',password.id);passwordLabel.className='customer-auth-label';
 const confirm=make('input');confirm.id='customerAuthPasswordConfirm';confirm.type='password';confirm.autocomplete='new-password';confirm.placeholder='Repeat your password';confirm.setAttribute('aria-label','Confirm password');
 const confirmLabel=make('label','Confirm password');confirmLabel.setAttribute('for',confirm.id);confirmLabel.className='customer-auth-label';
 const emailLabel=make('label','Email address');emailLabel.setAttribute('for',email.id);emailLabel.setAttribute('class','customer-auth-label');const codeLabel=make('label','Verification code');codeLabel.setAttribute('for',code.id);codeLabel.setAttribute('class','customer-auth-label');codeLabel.hidden=true;
 const status=make('p');status.id='customerAuthStatus';status.setAttribute('role','status');status.setAttribute('aria-live','polite');
 const send=login.querySelector('button[onclick="handleLogin()"]');send.before(modes,help,emailLabel,email,passwordLabel,password,confirmLabel,confirm,codeLabel,code);send.after(status,remember);
 const recover=make('button','Forgot password?');recover.type='button';recover.id='customerAuthRecover';send.after(recover);
 const resend=make('button','Resend code');resend.type='button';resend.id='customerAuthResend';resend.hidden=true;send.after(resend);
 const contacts=document.getElementById('customerContactSetup');contacts.hidden=true;
 email.after(contacts);
 const hero=make('section');hero.id='customerAuthHero';hero.setAttribute('aria-label','Welcome to SwiftShop');
 const brand=make('p','SWIFTSHOP'),headline=make('h1','Your local favourites. One SwiftShop.'),intro=make('p','Shop nearby, get it delivered, or find your next ride. All in one place.');
 brand.className='auth-brand';intro.className='auth-intro';hero.append(brand,headline,intro);login.before(hero);
 const layout=make('style');layout.textContent=`
 #authScreen.auth-screen{min-height:100svh!important;width:100%!important;max-width:none!important;margin:0!important;padding:36px 24px!important;box-sizing:border-box;align-items:center!important;justify-content:center!important;background:#fffaf5!important;gap:0}
 #customerAuthHero{display:none}#authScreen #loginBox{display:block!important;box-sizing:border-box;width:100%!important;max-width:480px!important;margin:0!important;padding:32px!important;text-align:left!important;border-radius:28px!important;background:#fff!important;box-shadow:0 20px 70px #3e27100a!important}
 #authScreen #loginBox h2{font-size:clamp(26px,2.4vw,38px)!important;line-height:1.15!important;letter-spacing:-1px;margin:18px 0 12px!important}#authScreen #loginBox .login-slogan{text-align:left!important;font-size:14px!important;line-height:1.6}
 #authScreen #loginBox input{display:block;width:100%!important;max-width:none!important;box-sizing:border-box;height:54px!important;margin:6px 0 16px!important;padding:0 16px!important;border-radius:14px!important}#authScreen #loginBox label{display:block;text-align:left;font-size:13px;font-weight:600;margin-top:12px}
 #authScreen #loginBox input[hidden],#authScreen #loginBox label[hidden],#authScreen #loginBox button[hidden],#authScreen #loginBox fieldset[hidden]{display:none!important}
 #authScreen #loginBox button{width:100%!important;max-width:none!important;min-height:50px;margin:10px 0 0!important;border-radius:14px!important}#authScreen #loginBox #customerAuthRecover,#authScreen #loginBox #customerAuthChange{background:transparent!important;color:#6b5140!important;box-shadow:none!important;font-size:13px;min-height:36px;padding:8px!important}
 #authScreen #loginBox #customerAuthModes button{background:transparent!important;color:#766b61!important;margin:0!important;min-height:44px!important;padding:10px!important}#authScreen #loginBox #customerAuthModes button[aria-pressed="true"]{background:#fff!important;color:#29211b!important;box-shadow:0 2px 8px #30201012!important}
 #customerAuthStatus{font-size:13px;line-height:1.6;color:#694126;overflow-wrap:anywhere}#authScreen #loginBox .login-steps{font-size:11px!important;margin-top:24px!important;text-align:center}#customerContactSetup{border:0;padding:0;margin:20px 0}
 @media(min-width:900px){#authScreen.auth-screen{display:grid!important;grid-template-columns:minmax(0,1.1fr) minmax(0,1fr);padding:0!important;align-items:stretch!important}#customerAuthHero{display:flex;flex-direction:column;justify-content:center;position:relative;overflow:hidden;padding:clamp(48px,7vw,120px);background:linear-gradient(145deg,#ff6a00,#ff9b40);color:#211f1b;text-align:left;min-height:100svh;box-sizing:border-box}#customerAuthHero::after{content:'';position:absolute;width:580px;height:580px;bottom:-390px;right:-160px;border:70px solid #ffffff28;border-radius:50%;pointer-events:none}#customerAuthHero .auth-brand{font-size:16px;font-weight:800;letter-spacing:4px;margin:0 0 64px}#customerAuthHero h1{font-size:clamp(48px,5vw,84px);line-height:1.04;letter-spacing:-3px;max-width:650px;margin:0 0 28px;color:#211f1b}#customerAuthHero .auth-intro{font-size:clamp(17px,1.4vw,22px);line-height:1.6;max-width:470px;margin:0}#authScreen #loginBox{align-self:center;justify-self:center;max-width:640px!important;width:100%!important;padding:clamp(36px,5vw,80px)!important;background:transparent!important;box-shadow:none!important;border-radius:0!important}}
 @media(max-width:480px){#authScreen.auth-screen{padding:24px 16px!important}#authScreen #loginBox{padding:24px!important}}
 `;layout.textContent=layout.textContent.replace('#authScreen.auth-screen{display:grid!important','#authScreen.auth-screen:not([style*="display: none"]):not([style*="display:none"]){display:grid!important').replaceAll('#authScreen','html.swift-design #authScreen');document.body.append(layout);

 let state='signin',busy=false,pendingEmail='',pendingName='',pendingPhone='',resendAfter=0;
 const name=document.getElementById('userName'),phone=document.getElementById('userPhone');
 name.setAttribute('aria-label','Full name');phone.setAttribute('aria-label','Contact phone number');
 const nameLabel=make('label','Full name'),phoneLabel=make('label','Contact phone number');nameLabel.setAttribute('for',name.id);phoneLabel.setAttribute('for',phone.id);name.before(nameLabel);phone.before(phoneLabel);
 const heading=login.querySelector('h2');
 const change=make('button','Back to sign in');change.type='button';change.id='customerAuthChange';send.after(change);
 const shown=(node,visible)=>{node.hidden=!visible;};
 function render(){
  const credentials=state==='signin'||state==='signup';
  const verification=state==='verify-signup'||state==='verify-recover';
  const newPassword=state==='new-password';
  shown(modes,credentials);shown(contacts,state==='signup'||state==='contact');
  shown(emailLabel,credentials||state==='recover');shown(email,credentials||state==='recover');email.readOnly=false;
  shown(passwordLabel,credentials||newPassword);shown(password,credentials||newPassword);
  shown(confirmLabel,state==='signup'||newPassword);shown(confirm,state==='signup'||newPassword);
  shown(codeLabel,verification);shown(code,verification);shown(recover,state==='signin');shown(resend,verification);
  shown(change,state!=='signin'&&state!=='signup');shown(remember,credentials);
  password.autocomplete=state==='signin'?'current-password':'new-password';
  signIn.setAttribute('aria-pressed',String(state==='signin'));signUp.setAttribute('aria-pressed',String(state==='signup'));
  for(const button of [send,signIn,signUp,recover,resend,change])button.disabled=busy;
  const labels={signin:['Welcome back','Sign in with your email and password.','Sign in'],signup:['Create your account','Your contact details are saved once, during signup.','Create account'],recover:['Reset your password','Enter your account email. We’ll send a code to verify it.','Send code'],'verify-signup':['Verify your email',`Enter the code sent to ${pendingEmail}. Then you’re ready to shop.`,'Verify & continue'],'verify-recover':['Verify your email',`Enter the code sent to ${pendingEmail} to reset your password.`,'Verify code'],'new-password':['Choose a new password','Use at least 8 characters. You’ll use this password on other devices.','Save password & continue'],contact:['Finish your account','This email has no saved delivery contact yet. Complete it once.','Save & continue']};
  const copy=labels[state];if(heading)heading.textContent=copy[0];help.textContent=copy[1];send.textContent=busy?'Please wait…':copy[2];
 }
 function clearDraft(){pendingEmail=pendingName=pendingPhone='';password.value=confirm.value=code.value='';name.value=phone.value='';}
 function chooseMode(next){if(busy)return;clearDraft();state=next;status.textContent='';render();}
 signIn.onclick=()=>chooseMode('signin');signUp.onclick=()=>chooseMode('signup');recover.onclick=()=>chooseMode('recover');
 function validateEmail(){const value=email.value.trim().toLowerCase();email.value=value;if(!email.checkValidity()||!value)throw Error('Enter a valid email address.');return value;}
 function validatePassword(isNew=false){if(!password.value)throw Error('Enter your password.');if(isNew&&password.value.length<8)throw Error('Use at least 8 characters for your password.');if(isNew&&password.value!==confirm.value)throw Error('Passwords do not match.');}
 function readContact(){const n=name.value.trim(),p=phone.value.trim(),digits=p.replace(/\D/g,'');if(!n)throw Error('Enter your full name.');if(!(digits.length===7||/^[1-9]\d{7,14}$/.test(digits)))throw Error('Enter a valid contact number, including country code if outside Belize.');pendingName=n;pendingPhone=p;}
 async function getSession(){const r=await customerDataClient.auth.getSession();if(r.error)throw r.error;return r.data.session;}
 function authScreen(){document.getElementById('appScreen').style.display='none';document.getElementById('authScreen').style.display='flex';}
 async function loadProfile(args={p_name:null,p_phone:null}){const r=await customerDataClient.rpc('swift_customer_profile',args).abortSignal(AbortSignal.timeout(10000));if(r.error)throw r.error;return r.data;}
 async function finish(animate=false){
  let p=await loadProfile();
  if(!p){
   const r=await customerDataClient.rpc('swift_customer_registration_state').abortSignal(AbortSignal.timeout(10000));if(r.error)throw r.error;
   {
    const session=await getSession();const draft=session?.user?.user_metadata?.swift_customer_registration;
    if(!pendingName&&draft){pendingName=String(draft.name||'');pendingPhone=String(draft.phone||'');}
    if(pendingName&&pendingPhone)p=await loadProfile({p_name:pendingName,p_phone:pendingPhone});
   }
  }
  if(!p){state='contact';status.textContent='';render();authScreen();return false;}
  localStorage.setItem('userName',p.name||'Customer');localStorage.setItem('userPhone',p.phone);localStorage.setItem('contactPhone',p.contact_phone||(!String(p.phone).startsWith('account:')?p.phone:''));localStorage.setItem('points',p.points||0);localStorage.setItem('loggedIn','true');customerName=p.name;customerPhone=p.phone;customerEmail=p.email;window.userPhone=p.phone;
  password.value=confirm.value=code.value='';document.documentElement?.classList.remove('swift-awaiting-auth');
  document.getElementById('authScreen').style.display='none';document.getElementById('appScreen').style.display='none';
  if(animate&&window.showSwiftShopWelcome)window.showSwiftShopWelcome(enterApp);else enterApp();return true;
 }
 function errorText(error){if(/invalid login credentials/i.test(error.message))return 'Email or password is incorrect. Try again, or choose Forgot password to set or reset your password.';if(/already registered|user already exists/i.test(error.message))return 'This email already has an account. Choose Sign in, or reset your password.';if(/rate|too many|security purposes/i.test(error.message))return 'Please wait a moment before requesting another email.';return error.message||'Could not connect. Please try again.';}
 window.handleLogin=async()=>{if(busy)return;busy=true;status.textContent='';render();try{
  if(state==='signin'){
   const address=validateEmail();validatePassword();
   const {error}=await customerDataClient.auth.signInWithPassword({email:address,password:password.value});
   if(error){if(error.code==='email_not_confirmed'||/email not confirmed/i.test(error.message)){pendingEmail=address;const r=await customerDataClient.auth.resend({type:'signup',email:address});if(r.error)throw r.error;state='verify-signup';resendAfter=Date.now()+60000;password.value='';return;}throw error;}
   pendingName=pendingPhone='';password.value='';await finish(true);
  }else if(state==='signup'){
   const address=validateEmail();validatePassword(true);
   // A valid existing password always opens that account, even from the signup tab.
   // Authentication, rather than an entered phone number, decides which profile is restored.
   const existing=await customerDataClient.auth.signInWithPassword({email:address,password:password.value});
   if(!existing.error){pendingName=pendingPhone='';password.value=confirm.value='';await finish(true);return;}
   if(existing.error.code==='email_not_confirmed'||/email not confirmed/i.test(existing.error.message)){
    pendingEmail=address;const r=await customerDataClient.auth.resend({type:'signup',email:address});if(r.error)throw r.error;state='verify-signup';resendAfter=Date.now()+60000;password.value=confirm.value='';return;
   }
   if(existing.error.code!=='invalid_credentials'&&!/invalid login credentials/i.test(existing.error.message))throw existing.error;
   readContact();
   const {data,error}=await customerDataClient.auth.signUp({email:address,password:password.value,options:{data:{swift_customer_registration:{name:pendingName,phone:pendingPhone}}}});
   if(error)throw error;if(data?.user?.identities?.length===0)throw Error('This email already has an account. Choose Sign in, or reset your password.');
   pendingEmail=address;password.value=confirm.value='';resendAfter=Date.now()+60000;
   if(data?.session?.user?.email_confirmed_at)await finish(true);else state='verify-signup';
  }else if(state==='recover'){
   const address=validateEmail();const {error}=await customerDataClient.auth.signInWithOtp({email:address,options:{shouldCreateUser:false}});if(error)throw error;pendingEmail=address;state='verify-recover';resendAfter=Date.now()+60000;
  }else if(state==='verify-signup'||state==='verify-recover'){
   const token=code.value.trim();if(!/^\d{6,10}$/.test(token))throw Error('Enter the code from your email.');
   const recovery=state==='verify-recover';const {error}=await customerDataClient.auth.verifyOtp({email:pendingEmail,token,type:'email'});if(error)throw error;code.value='';if(recovery)state='new-password';else await finish(true);
  }else if(state==='new-password'){
   validatePassword(true);const {error}=await customerDataClient.auth.updateUser({password:password.value});if(error)throw error;password.value=confirm.value='';await finish(true);
  }else if(state==='contact'){readContact();await finish(true);}
 }catch(e){status.textContent=errorText(e);}finally{busy=false;render();}};
 resend.onclick=async()=>{if(busy)return;if(Date.now()<resendAfter){status.textContent='Please wait a minute before requesting another code.';return;}busy=true;render();try{const r=state==='verify-signup'?await customerDataClient.auth.resend({type:'signup',email:pendingEmail}):await customerDataClient.auth.signInWithOtp({email:pendingEmail,options:{shouldCreateUser:false}});if(r.error)throw r.error;resendAfter=Date.now()+60000;status.textContent='A new code has been sent. Check your inbox and spam folder.';}catch(e){status.textContent=errorText(e);}finally{busy=false;render();}};
 change.onclick=async()=>{if(busy)return;busy=true;render();try{const r=await customerDataClient.auth.signOut({scope:'local'});if(r.error)throw r.error;clearDraft();state='signin';status.textContent='';}catch(e){status.textContent=errorText(e);}finally{busy=false;render();}};
 for(const input of [email,password,confirm,code,name,phone])input.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();window.handleLogin();}});
 const logout=window.handleLogout;window.handleLogout=async function(...args){if(!window.swiftLogoutConfirmed&&!confirmLogout())return;const r=await customerDataClient.auth.signOut({scope:'local'});if(r.error){alert(r.error.message);return;}document.documentElement?.classList.add('swift-awaiting-auth');clearDraft();state='signin';render();window.swiftLogoutConfirmed=true;return logout.apply(this,args);};
 function confirmLogout(){return window.confirm('Sign out of SwiftShop on this device?');}
 render();
 window.saveProfile=async()=>{try{const result=await customerDataClient.rpc('swift_customer_profile',{p_name:document.getElementById('profileName').value.trim()});if(result.error)throw result.error;localStorage.setItem('userName',result.data.name);localStorage.setItem('userPhone',result.data.phone);document.getElementById('profileDisplayName').textContent=result.data.name;localStorage.setItem('contactPhone',result.data.contact_phone||(!String(result.data.phone).startsWith('account:')?result.data.phone:''));document.getElementById('profilePhone').value=localStorage.getItem('contactPhone');}catch(e){alert(e.message);}};
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

