/* Homepage presentation only. Reuses cards, navigation handlers and existing storefront reads. */
(()=>{'use strict';
 const rows=new Map();let directory;
 const safe=value=>typeof value==='string'&&/^(https?:\/\/|data:image\/(?:png|jpe?g|webp|gif);base64,)/i.test(value)?value:'';
 const make=(tag,cls)=>{const n=document.createElement(tag);n.className=cls;return n;};
 function paint(){
  if(!directory)return;
  for(const card of directory.querySelectorAll('.store-directory-card[data-store-category]')){
   const category=card.dataset.storeCategory;
   let cover=card.querySelector('.store-directory-cover');const logo=cover?.querySelector('img:not(.home-store-banner)')||card.querySelector('img');
   if(!cover&&logo){cover=make('span','store-directory-cover');logo.before(cover);cover.append(logo);}if(!cover)continue;
   if(logo){logo.classList.add('home-store-logo');logo.loading='lazy';logo.decoding='async';}
   card.classList.add('home-store-card');
   if(!card.querySelector('.home-store-category')){
    const source=[...document.querySelectorAll('.cat-btn[onclick]')].find(n=>(n.getAttribute('onclick')||'').includes("setCategory('"+category+"'"));
    const group=source?.closest('.category-panel')?.id.replace('panel-','');
    const tab=[...document.querySelectorAll('.main-tab-btn[onclick]')].find(n=>(n.getAttribute('onclick')||'').includes("switchMainTab('"+group+"'"));
    const label=/pharmacy/i.test(category)?(document.getElementById('homePharmacyButton')?.textContent?.trim()||'Pharmacy'):tab?.textContent?.replace(/^[^A-Za-z]+/,'').trim();
    if(label){const text=make('span','home-store-category');text.textContent=label;card.append(text);}
   }
   const src=safe(rows.get(category)?.cover_image);
   if(card.dataset.homeCover===src&&(!src||cover.querySelector('.home-store-banner')))continue;card.dataset.homeCover=src;
   cover.querySelector('.home-store-banner')?.remove();card.classList.remove('home-store-has-banner');
   if(!src)continue;
   const img=make('img','home-store-banner');img.alt='';img.loading='lazy';img.decoding='async';img.width=360;img.height=200;
   img.onload=()=>{if(img.isConnected){img.classList.toggle('home-store-artwork',img.naturalWidth/img.naturalHeight>2.15);card.classList.add('home-store-has-banner');}};
   img.onerror=()=>{img.remove();delete card.dataset.homeCover;card.classList.remove('home-store-has-banner');};img.src=src;cover.prepend(img);
  }
 }
 const pending=new Set(),loaded=new Map();let retryTimer=null;
 async function loadCovers(force=false){
  if(!directory)return;
  await Promise.resolve(window.SwiftRegions?.ready).catch(()=>{});
  const categories=[...new Set([...directory.querySelectorAll('[data-store-category]')].map(c=>c.dataset.storeCategory).filter(c=>!window.SwiftRegions||window.SwiftRegions.allowed(c)))].filter(c=>!pending.has(c)&&(force||Date.now()-(loaded.get(c)||0)>60000));
  const client=typeof customerDataClient!=='undefined'?customerDataClient:typeof supabaseClient!=='undefined'?supabaseClient:null;
  if(!client||!categories.length)return;
  categories.forEach(c=>pending.add(c));
  const batches=[];for(let i=0;i<categories.length;i+=3)batches.push(categories.slice(i,i+3));
  let failed=false;
  async function worker(){while(batches.length){const group=batches.shift();try{
   const result=await client.from('merchant_storefronts').select('category,cover_image').in('category',group).abortSignal(AbortSignal.timeout(30000));
   if(result.error)throw result.error;
   for(const record of result.data||[])rows.set(record.category,{...rows.get(record.category),...record});
   group.forEach(c=>loaded.set(c,Date.now()));paint();
  }catch{failed=true;}finally{group.forEach(c=>pending.delete(c));}}}
  await Promise.all([worker(),worker()]);
  if(failed&&!retryTimer)retryTimer=setTimeout(()=>{retryTimer=null;if(document.visibilityState!=='hidden')loadCovers();},5000);
 }
 window.SwiftHomeStores={update(records){for(const row of records||[])if(row?.category)rows.set(row.category,{...rows.get(row.category),...row});paint();loadCovers();}};
 document.addEventListener('DOMContentLoaded',()=>{
  directory=document.getElementById('shopStoreDirectory');if(!directory)return;
  const heading=directory.querySelector('h2'),subtitle=directory.querySelector(':scope > p');if(heading)heading.textContent='Explore local stores';if(subtitle)subtitle.textContent='Browse menus, discover offers, and shop your local favourites.';
  directory.classList.add('home-store-directory');paint();loadCovers();
  const row=directory.querySelector('.store-directory-row');if(row)new MutationObserver(records=>{if(records.some(r=>r.addedNodes.length)){paint();loadCovers();}}).observe(row,{childList:true});
  window.addEventListener('swift-region-change',()=>{paint();loadCovers();});
  window.addEventListener('swift-store-publication-changed',()=>loadCovers(true));window.addEventListener('online',()=>loadCovers());window.addEventListener('swift-customer-session-ready',()=>loadCovers());document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')loadCovers();});
 });
})();
