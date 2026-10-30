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
   if(card.dataset.homeCover===src)continue;card.dataset.homeCover=src;
   cover.querySelector('.home-store-banner')?.remove();card.classList.remove('home-store-has-banner');
   if(!src)continue;
   const img=make('img','home-store-banner');img.alt='';img.loading='lazy';img.decoding='async';img.width=360;img.height=200;
   img.onload=()=>{if(img.isConnected){img.classList.toggle('home-store-artwork',img.naturalWidth/img.naturalHeight>2.15);card.classList.add('home-store-has-banner');}};
   img.onerror=()=>{img.remove();card.classList.remove('home-store-has-banner');};img.src=src;cover.prepend(img);
  }
 }
 window.SwiftHomeStores={update(records){for(const row of records||[])if(row?.category)rows.set(row.category,{...rows.get(row.category),...row});paint();}};
 document.addEventListener('DOMContentLoaded',()=>{
  directory=document.getElementById('shopStoreDirectory');if(!directory)return;
  const heading=directory.querySelector('h2'),subtitle=directory.querySelector(':scope > p');if(heading)heading.textContent='Explore local stores';if(subtitle)subtitle.textContent='Browse menus, discover offers, and shop your local favourites.';
  directory.classList.add('home-store-directory');paint();
  const row=directory.querySelector('.store-directory-row');if(row)new MutationObserver(records=>{if(records.some(r=>r.addedNodes.length))paint();}).observe(row,{childList:true});
 });
})();
