(() => {
 'use strict';
 const states=new WeakMap();
 window.SwiftCompletionCards={update(host,info){
  if(!host)return;
  let state=states.get(host);
  if(!state){
   const card=document.createElement('section');card.className='swift-confirmation-card';card.hidden=true;
   card.innerHTML='<div class="swift-confirmation-top"><span aria-hidden="true">✓</span><div><h3></h3><p></p></div></div><div class="swift-confirmation-qr"><canvas aria-label="Private completion QR code"></canvas></div><p class="swift-confirmation-status" role="status"></p><button type="button">Refresh code</button>';
   host.append(card);state={card,key:'',version:0,pending:false,expires:0,retry:0};states.set(host,state);
   card.querySelector('button').onclick=()=>{state.expires=0;state.retry=0;window.SwiftCompletionCards.update(host,state.info);};
  }
  state.info=info;
  if(!info.active){state.card.hidden=true;if(state.key){state.key='';++state.version;}return;}
  state.card.hidden=false;
  const key=info.kind+':'+info.id;
  if(state.key===key&&(state.pending||Date.now()<state.retry||Date.now()<state.expires-30000))return;
  state.key=key;state.pending=true;const version=++state.version;
  const card=state.card,canvas=card.querySelector('canvas'),status=card.querySelector('[role=status]');
  const ride=info.kind==='ride';card.querySelector('h3').textContent=ride?'Your ride confirmation':'Your delivery confirmation';
  card.querySelector('.swift-confirmation-top p').textContent=ride?'At your destination, show this to your driver.':'When your delivery arrives, show this to your runner.';
  canvas.hidden=true;status.textContent='Preparing your private code…';card.querySelector('button').disabled=true;
  (async()=>{
   try{
    const client=typeof customerDataClient!=='undefined'?customerDataClient:null;
    if(!client)throw Error('Sign in to view your code.');
    const {data,error}=await client.rpc('swift_completion_code',{p_kind:info.kind,p_id:info.id,p_access_token:info.token||null}).abortSignal(AbortSignal.timeout(10000));
    if(error)throw error;if(version!==state.version)return;
    if(!data){card.hidden=true;state.retry=Date.now()+10000;return;}
    await window.SwiftQRCode.toCanvas(canvas,data.payload,{width:208,margin:4,errorCorrectionLevel:'M',color:{dark:'#17261fff',light:'#ffffffff'}});
    if(version!==state.version)return;
    canvas.hidden=false;state.expires=Date.parse(data.expiresAt);status.textContent='One-time confirmation · Share only with your assigned '+(ride?'driver':'runner')+'.';
   }catch(e){if(version===state.version){status.textContent='Code could not load. Tap Refresh code to retry.';state.retry=Date.now()+30000;}}
   finally{if(version===state.version){state.pending=false;card.querySelector('button').disabled=false;}}
  })();
 }};
})();
