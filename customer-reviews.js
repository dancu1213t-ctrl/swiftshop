(() => {
 'use strict';
 const states=new WeakMap();
 const rpc=async(name,args)=>{const {data,error}=await customerDataClient.rpc(name,args).abortSignal(AbortSignal.timeout(12000));if(error)throw error;return data;};
 const el=(tag,text)=>{const n=document.createElement(tag);if(text)n.textContent=text;return n;};
 window.SwiftReviews={update(host,info){
  if(!host)return;let s=states.get(host);
  if(!s){const card=el('section');card.className='swift-reviews';card.hidden=true;host.append(card);s={card,key:'',version:0};states.set(host,s);}
  if(s.card.parentElement!==host)host.append(s.card);
  if(!info.completed){s.card.hidden=true;s.key='';s.version++;return;}
  s.card.hidden=false;if(s.key===info.id)return;s.key=info.id;const version=++s.version;
  const load=async()=>{s.card.replaceChildren(el('p','Loading feedback…'));s.card.setAttribute('aria-busy','true');try{
   const targets=(await rpc('swift_order_review_targets',{p_id:info.id})).filter(target=>target.kind==='runner');if(version!==s.version)return;
   s.card.replaceChildren(el('h2','How was your runner?'),el('p','Rate your delivery experience with your runner.'));
   for(const target of targets){const block=el('div'),heading=el('h3','Your runner'),group=el('div'),status=el('p'),save=el('button','Save rating');group.className='swift-review-stars';group.setAttribute('role','group');group.setAttribute('aria-label','Your runner rating');status.setAttribute('role','status');save.type='button';save.className='swift-review-save';let busy=false,selected=0,saved=0;
    const valid=value=>{const n=Number(value);return Number.isInteger(n)&&n>=1&&n<=5?n:0;};
    const paint=()=>{for(const b of group.children){b.disabled=busy||!!saved;b.setAttribute('aria-pressed',String(Number(b.dataset.stars)<=selected));}save.hidden=!!saved;save.disabled=busy||!selected;save.textContent=busy?'Saving…':'Save rating';};
    for(let stars=1;stars<=5;stars++){const b=el('button','★');b.type='button';b.dataset.stars=stars;b.setAttribute('aria-label',stars+' of 5 stars');b.onclick=e=>{e.stopPropagation();if(busy||saved)return;selected=stars;status.textContent=stars+' of 5 stars selected';paint();};group.append(b);}
    save.onclick=async e=>{e.stopPropagation();if(busy||saved||!selected)return;busy=true;paint();status.textContent='Saving your feedback…';try{await rpc('swift_submit_order_review',{p_id:info.id,p_kind:target.kind,p_key:target.key,p_stars:selected});const confirmed=await rpc('swift_order_review_targets',{p_id:info.id});if(version!==s.version)return;saved=valid(confirmed.find(item=>item.kind===target.kind&&item.key===target.key)?.stars);if(!saved)throw Error('The server has not confirmed your rating. Please retry.');selected=saved;status.textContent='Thank you · '+saved+' of 5 stars saved';}catch(error){if(version!==s.version)return;status.textContent='Could not confirm your rating. '+(String(error?.message||'Please retry.').slice(0,160));}finally{busy=false;if(version===s.version)paint();}};
    saved=valid(target.stars);selected=saved;status.textContent=saved?'Thank you · '+saved+' of 5 stars saved':'Choose your stars, then tap Save rating';paint();block.append(heading,group,status,save);s.card.append(block);
   }
   if(!targets.length)s.card.replaceChildren(el('p','Your order is complete.'));
  }catch{if(version!==s.version)return;s.card.replaceChildren(el('p','Feedback could not load. Your order is still complete.'));const retry=el('button','Retry feedback');retry.type='button';retry.onclick=load;s.card.append(retry);}finally{if(version===s.version)s.card.removeAttribute('aria-busy');}};load();
 }};
 document.addEventListener('DOMContentLoaded',()=>{
  const profile=document.querySelector('#profileOverlay .profile-card');
  if(profile){const button=el('button','Rate completed orders');button.type='button';button.className='swift-review-history-link';profile.append(button);
   const dialog=el('dialog');dialog.id='swiftReviewDialog';dialog.setAttribute('aria-label','Rate completed orders');dialog.className='swift-review-dialog';const header=el('header'),title=el('h2','Your feedback'),close=el('button','✕');close.type='button';close.dataset.close='';close.setAttribute('aria-label','Close feedback');header.append(title,close);const content=el('div');dialog.append(header,content);document.body.append(dialog);close.onclick=()=>dialog.close();
   const load=async()=>{content.replaceChildren(el('p','Loading completed orders…'));try{const orders=await rpc('swift_completed_review_orders',{});content.replaceChildren();if(!orders.length)content.append(el('p','After your first completed order, you can rate your runner here.'));for(const order of orders){const entry=el('details'),summary=el('summary','Order '+order.id.slice(0,8).toUpperCase()),host=el('div');entry.append(summary,host);entry.ontoggle=()=>{if(entry.open)window.SwiftReviews.update(host,{id:order.id,completed:true});};content.append(entry);}}catch{content.replaceChildren(el('p','Completed orders could not load.'));const retry=el('button','Try again');retry.type='button';retry.onclick=load;content.append(retry);}};
   button.onclick=()=>{dialog.inert=false;if(!dialog.open)dialog.showModal();window.SwiftNavigation?.refresh();load();};
   dialog.addEventListener('close',()=>{window.SwiftNavigation?.refresh();button.focus({preventScroll:true});});
  }

 });
})();
