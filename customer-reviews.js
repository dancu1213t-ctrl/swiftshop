(() => {
 'use strict';
 const states=new WeakMap();
 const rpc=async(name,args)=>{const {data,error}=await customerDataClient.rpc(name,args).abortSignal(AbortSignal.timeout(12000));if(error)throw error;return data;};
 const el=(tag,text)=>{const n=document.createElement(tag);if(text)n.textContent=text;return n;};
 window.SwiftReviews={update(host,info){
  if(!host)return;let s=states.get(host);
  if(!s){const card=el('section');card.className='swift-reviews';card.hidden=true;host.append(card);s={card,key:'',version:0};states.set(host,s);}
  if(!info.completed){s.card.hidden=true;s.key='';s.version++;return;}
  s.card.hidden=false;if(s.key===info.id)return;s.key=info.id;const version=++s.version;
  const load=async()=>{s.card.replaceChildren(el('p','Loading feedback…'));s.card.setAttribute('aria-busy','true');try{
   const targets=await rpc('swift_order_review_targets',{p_id:info.id});if(version!==s.version)return;
   s.card.replaceChildren(el('h2','How was your order?'),el('p','Rate each store and your runner separately.'));
   for(const target of targets){const block=el('div'),heading=el('h3',target.kind==='runner'?'Your runner':target.key),group=el('div'),status=el('p');group.className='swift-review-stars';group.setAttribute('role','group');group.setAttribute('aria-label',heading.textContent+' rating');status.setAttribute('role','status');let busy=false;
    const paint=stars=>{for(const b of group.children){b.disabled=!!stars;b.setAttribute('aria-pressed',String(Number(b.dataset.stars)<=stars));}status.textContent=stars?'Thank you · '+stars+' of 5 stars saved':'Choose a star rating';};
    for(let stars=1;stars<=5;stars++){const b=el('button','★');b.type='button';b.dataset.stars=stars;b.setAttribute('aria-label',stars+' of 5 stars');b.onclick=async()=>{if(busy)return;busy=true;for(const item of group.children)item.disabled=true;status.textContent='Saving your feedback…';try{await rpc('swift_submit_order_review',{p_id:info.id,p_kind:target.kind,p_key:target.key,p_stars:stars});target.stars=stars;paint(stars);}catch{paint(null);status.textContent='Could not save. Choose your rating to retry.';}finally{busy=false;}};group.append(b);}
    paint(target.stars);block.append(heading,group,status);s.card.append(block);
   }
   if(!targets.length)s.card.replaceChildren(el('p','Your order is complete.'));
  }catch{if(version!==s.version)return;s.card.replaceChildren(el('p','Feedback could not load. Your order is still complete.'));const retry=el('button','Retry feedback');retry.type='button';retry.onclick=load;s.card.append(retry);}finally{if(version===s.version)s.card.removeAttribute('aria-busy');}};load();
 }};
 document.addEventListener('DOMContentLoaded',()=>{
  const profile=document.querySelector('#profileOverlay .profile-card');
  if(profile){const button=el('button','Rate completed orders');button.type='button';button.className='swift-review-history-link';profile.append(button);
   const dialog=el('dialog');dialog.id='swiftReviewDialog';dialog.className='swift-review-dialog';const header=el('header'),title=el('h2','Your feedback'),close=el('button','✕');close.type='button';close.dataset.close='';close.setAttribute('aria-label','Close feedback');header.append(title,close);const content=el('div');dialog.append(header,content);document.body.append(dialog);close.onclick=()=>dialog.close();
   const load=async()=>{content.replaceChildren(el('p','Loading completed orders…'));try{const orders=await rpc('swift_completed_review_orders',{});content.replaceChildren();if(!orders.length)content.append(el('p','After your first completed order, you can rate the store and runner here.'));for(const order of orders){const entry=el('details'),summary=el('summary','Order '+order.id.slice(0,8).toUpperCase()),host=el('div');entry.append(summary,host);entry.ontoggle=()=>{if(entry.open)window.SwiftReviews.update(host,{id:order.id,completed:true});};content.append(entry);}}catch{content.replaceChildren(el('p','Completed orders could not load.'));const retry=el('button','Try again');retry.type='button';retry.onclick=load;content.append(retry);}};
   button.onclick=()=>{dialog.inert=false;dialog.showModal();load();};
  }
  const original=window.openMerchantStore;if(!original)return;let version=0;
  window.openMerchantStore=async function(category){const stamp=++version,result=original.apply(this,arguments);await result;if(stamp!==version)return result;const parent=document.querySelector('#merchantStorePage .store-header-meta');if(!parent)return result;parent.querySelector('.swift-real-rating')?.remove();const label=el('span','Loading ratings…');label.className='swift-real-rating';parent.append(label);try{const summary=await rpc('swift_rating_summary',{p_kind:'store',p_key:category});if(stamp!==version)return result;label.textContent=summary.count?'★ '+summary.average+' · '+summary.count+' verified order '+(summary.count===1?'rating':'ratings'):'No customer ratings yet';}catch{label.remove();}return result;};
 });
})();
