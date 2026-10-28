/* Store sections preserve existing catalogue and About controls. */
(()=>{'use strict';
document.addEventListener('DOMContentLoaded',()=>{
 const open=window.openMerchantStore;if(typeof open!=='function')return;let sequence=0;
 const make=(tag,text,cls)=>{const n=document.createElement(tag);if(text)n.textContent=text;if(cls)n.className=cls;return n;};
 window.openMerchantStore=async function(category,...args){
  const ticket=++sequence,page=document.getElementById('merchantStorePage');
  page?.querySelector('.store-section-nav')?.remove();page?.querySelector('.store-location-panel')?.remove();if(page)page.dataset.storeView='menu';
  const result=await open.call(this,category,...args);
  if(ticket!==sequence||!page||page.style.display==='none')return result;
  const search=page.querySelector('.store-search-row'),info=page.querySelector('#storePublicDetails');if(!search)return result;
  const nav=make('nav',null,'store-section-nav');nav.setAttribute('aria-label','Store sections');
  const panel=make('section',null,'store-location-panel');panel.hidden=true;panel.setAttribute('aria-label','Store location');
  const row=window.SwiftStoreInfo?.rows.get(category),lat=Number(row?.latitude),lng=Number(row?.longitude);
  panel.append(make('h2','Location'));
  if(row?.address)panel.append(make('p',row.address));
  if(row?.latitude!=null&&row?.longitude!=null&&Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)<=90&&Math.abs(lng)<=180){
   const frame=make('iframe');frame.title='Store location map';frame.loading='lazy';frame.referrerPolicy='no-referrer-when-downgrade';frame.src='https://maps.google.com/maps?q='+encodeURIComponent(lat+','+lng)+'&z=17&output=embed';panel.append(frame);
   const link=make('a','Open in Google Maps');link.href='https://www.google.com/maps/search/?api=1&query='+encodeURIComponent(lat+','+lng);link.target='_blank';link.rel='noopener noreferrer';panel.append(link);
  }else panel.append(make('p','Map location has not been added yet.'));
  const tabs=[];function select(view){page.dataset.storeView=view;panel.hidden=view!=='location';if(info)info.hidden=view!=='about';for(const b of tabs)b.setAttribute('aria-current',String(b.dataset.view===view));}
  for(const [view,label] of [['menu','Menu/Items'],['about','About'],['location','Location']]){
   if(view==='about'&&!info)continue;const b=make('button',label);b.type='button';b.dataset.view=view;
   b.onclick=()=>{select(view);if(view==='about'){const toggle=page.querySelector('.store-about-toggle');if(toggle?.getAttribute('aria-expanded')==='false')toggle.click();}};tabs.push(b);nav.append(b);
  }
  if(info){info.before(nav);info.after(panel);}else{search.before(nav);nav.after(panel);}select('menu');return result;
 };
});
})();
