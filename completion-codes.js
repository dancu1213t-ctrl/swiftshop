(() => {
 'use strict';
 const states=new WeakMap();
 window.SwiftCompletionCards={update(host,info){
  if(!host)return;
  let state=states.get(host);
  if(!state){
   const card=document.createElement('section');card.className='swift-confirmation-card';card.hidden=true;
   card.innerHTML='<div class="swift-confirmation-top"><span aria-hidden="true">✓</span><div><h3></h3><p></p></div></div><div class="swift-confirmation-qr"><canvas aria-label="Private order QR code"></canvas></div><p class="swift-confirmation-status" role="status"></p><button type="button">Refresh code</button>';
   host.append(card);state={card,key:'',version:0,pending:false,expires:0,retry:0};states.set(host,state);
   card.querySelector('button').onclick=()=>{state.expires=0;state.retry=0;window.SwiftCompletionCards.update(host,state.info);};
  }
  state.info=info;host.querySelector('.swiftpay-live-action')?.remove();
  if(!info.active){state.card.hidden=true;state.key='';state.pending=false;++state.version;return;}
  const key=info.kind+':'+info.id+':'+info.payment;
  if(state.key===key&&(state.pending||Date.now()<state.retry||Date.now()<state.expires-30000))return;
  state.key=key;state.pending=true;const version=++state.version;
  const card=state.card,canvas=card.querySelector('canvas'),status=card.querySelector('[role=status]'),button=card.querySelector('button');
  card.hidden=false;canvas.hidden=true;status.textContent='Checking your payment and preparing your code…';button.disabled=true;
  card.querySelector('h3').textContent='Your order code';card.querySelector('.swift-confirmation-top p').textContent='Loading the correct code for your payment method.';
  (async()=>{
   try{
    const client=typeof customerDataClient!=='undefined'?customerDataClient:null;if(!client)throw Error('Sign in to view your code.');
    const {data:mode,error:modeError}=await client.rpc('swift_customer_payment_mode',{p_kind:info.kind,p_id:info.id}).abortSignal(AbortSignal.timeout(10000));
    if(modeError)throw modeError;if(version!==state.version)return;
    const swiftpay=mode?.swiftpay===true,ride=info.kind==='ride';
    card.querySelector('h3').textContent=swiftpay?'Pay with SwiftPay':ride?'Your ride confirmation':'Your delivery confirmation';
    card.querySelector('.swift-confirmation-top p').textContent=swiftpay?'Your runner enters the invoice amount and scans this payment code.':ride?'At your destination, show this to your driver.':'When your delivery arrives, show this to your runner.';
    const {data,error}=await client.rpc(swiftpay?'swiftpay_payment_code':'swift_completion_code',swiftpay?{p_kind:info.kind,p_id:info.id}:{p_kind:info.kind,p_id:info.id,p_access_token:info.token||null}).abortSignal(AbortSignal.timeout(10000));
    if(error)throw error;if(version!==state.version)return;
    if(data?.paid){status.textContent='SwiftPay payment completed.';state.expires=Date.now()+30000;window.SwiftPay?.refresh();return;}
    if(!data?.payload){status.textContent='Your code is not ready yet. Refresh when delivery or your trip starts.';state.retry=Date.now()+10000;return;}
    if(!data.payload.startsWith(swiftpay?'swiftshop-pay:v1:':'swiftshop-confirm:v1:'))throw Error('Payment code mismatch. Refresh your order before scanning.');
    await window.SwiftQRCode.toCanvas(canvas,data.payload,{width:208,margin:4,errorCorrectionLevel:'M',color:{dark:'#17261fff',light:'#ffffffff'}});
    if(version!==state.version)return;
    canvas.setAttribute('aria-label',swiftpay?'SwiftPay payment QR code':'Delivery or ride completion QR code');canvas.hidden=false;
    state.expires=Date.parse(data.expiresAt)||Date.now()+60000;
    status.textContent=swiftpay?'Invoice BZ$'+(data.amountCents/100).toFixed(2)+' + BZ$0.15 fee. Confirmed payment deducts your balance and completes this request.':'One-time confirmation · Share only with your assigned '+(ride?'driver':'runner')+'.';
   }catch(e){if(version===state.version){canvas.hidden=true;status.textContent=e.message||'Code could not load. Tap Refresh code to retry.';state.retry=Date.now()+10000;}}
   finally{if(version===state.version){state.pending=false;button.disabled=false;}}
  })();
 }};
})();