/* Read-only explanation of the existing server quote. */
(()=>{'use strict';let dialog,rows,total,note;
function make(tag,text){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;}
const money=c=>'BZ$'+(Number(c||0)/100).toFixed(2);
function init(){dialog=make('dialog');dialog.id='swiftDeliveryFeeInfo';dialog.setAttribute('aria-labelledby','deliveryFeeInfoTitle');
 const head=make('header'),title=make('h2','Delivery Fee info'),close=make('button','×');title.id='deliveryFeeInfoTitle';close.type='button';close.setAttribute('aria-label','Close delivery fee info');close.onclick=()=>dialog.close();head.append(title,close);
 rows=make('dl');const summary=make('div');summary.className='delivery-fee-info-total';total=make('strong');summary.append(make('span','Delivery total'),total);note=make('p');const done=make('button','Got it');done.type='button';done.className='delivery-fee-info-done';done.onclick=()=>dialog.close();dialog.append(head,rows,summary,note,done);document.body.append(dialog);
 dialog.addEventListener('click',e=>{if(e.target!==dialog)return;const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close();});
 document.addEventListener('click',e=>{if(!e.target.closest('[data-delivery-fee-info]'))return;show();});}
function show(){const q=window.SwiftRegions?.breakdown?.(),zone=q?.zone_id||window.SwiftRegions?.zone||'orange-walk',fee=Math.round(Number(window.getCartDeliveryFee?.()||0)*100);rows.replaceChildren();const row=(label,cents)=>{const n=make('div');n.append(make('dt',label),make('dd',money(cents)));rows.append(n);};
 if(zone==='orange-walk'){row('Base delivery',q?.base_fee_cents??450);const nearby=Number(q?.nearby_extra_stops||0),cross=Number(q?.cross_town_extra_stops||0);if(nearby)row(nearby+' nearby extra pickup'+(nearby===1?'':'s'),nearby*150);if(cross)row(cross+' cross-town extra pickup'+(cross===1?'':'s'),cross*200);note.textContent='Extra pickup: BZ$1.50 nearby or BZ$2 over 3 km between pickup pins. Your final drop-off is included.';}
 else{row('Delivery',fee);note.textContent='Your fee follows this service area’s approved distance rates. Your final drop-off is included.';}
 total.textContent=money(fee);if(!dialog.open)dialog.showModal();window.SwiftNavigation?.refresh();}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();