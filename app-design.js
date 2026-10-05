/* Presentation only: reuse existing controls, listeners, IDs, and data. */
(() => {
  'use strict';
  const paths={cookie:'<path d="M20 12a5 5 0 0 1-6-8 9 9 0 1 0 6 8Z"/><circle cx="8" cy="9" r="1"/><circle cx="7" cy="15" r="1"/><circle cx="13" cy="16" r="1"/><circle cx="11" cy="12" r="1"/>',bag:'<path d="M5 7h14l1 14H4L5 7Z"/><path d="M8 8V6a4 4 0 0 1 8 0v2"/>',pickup:'<path d="M3 9h18l-2 12H5L3 9Z"/><path d="m7 9 5-7 5 7M9 13v4m6-4v4"/>',car:'<path d="m5 7 2-4h10l2 4 2 3v8H3v-8l2-3Zm0 0h14M3 13h18M5 18v3m14-3v3"/><path d="M6 10h2m8 0h2"/>',offers:'<path d="m3 12 9-9h8v8l-9 10-8-9Z"/><circle cx="16" cy="7" r="1"/>',clock:'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',pin:'<path d="M19 10c0 5-7 12-7 12S5 15 5 10a7 7 0 1 1 14 0Z"/><circle cx="12" cy="10" r="2"/>',heart:'<path d="M20 5a5 5 0 0 0-8 1 5 5 0 0 0-8-1c-4 5 3 10 8 14 5-4 12-9 8-14Z"/>',arrow:'<path d="M5 12h14m-5-5 5 5-5 5"/>',cup:'<path d="M4 8h12v6a6 6 0 0 1-12 0V8Zm12 1h2a3 3 0 1 1 0 6h-2M3 21h15M7 2v3m5-3v3"/>',food:'<path d="M5 2v7m4-7v7M3 2v4a4 4 0 0 0 8 0V2M7 10v12M18 2c-3 3-3 8 0 9h3V2h-3Zm0 9v11"/>',leaf:'<path d="M20 3C4 2 2 12 8 17c6 5 13-3 12-14ZM5 21 16 9"/>',phone:'<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 18h4"/>',shirt:'<path d="m8 3-6 4 3 5 2-1v10h10V11l2 1 3-5-6-4c0 4-8 4-8 0Z"/>',image:'<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="2"/><path d="m3 17 6-6 4 4 3-3 5 5"/>',chat:'<path d="M21 11a9 9 0 0 1-9 9H3l2-5a9 9 0 1 1 16-4Z"/><path d="M8 9h8M8 13h5"/>',plus:'<path d="M12 4v16M4 12h16"/>'};
  function icon(name){const e=document.createElementNS('http://www.w3.org/2000/svg','svg');e.setAttribute('viewBox','0 0 24 24');e.setAttribute('aria-hidden','true');e.setAttribute('focusable','false');e.classList.add('sd-icon');e.innerHTML=paths[name]||paths.bag;return e;}
  function el(tag,cls){const e=document.createElement(tag);e.className=cls;return e;}
  function prependIcon(button,name){if(!button||button.querySelector('svg'))return;button.prepend(icon(name));}
  function markImage(img){
    if(img.dataset.designImage)return;img.dataset.designImage='true';
    const fail=()=>{
      if(img.closest('.gm-style'))return;
      img.classList.add('sd-image-unavailable');
      const parent=img.closest('.hero-promo-image-wrap,.store-directory-cover,.cat-btn,.product-img-wrap,.store-product,.media-card');
      if(!parent)return;
      parent.classList.add('sd-missing-image');
      if(parent.querySelector(':scope > .sd-image-fallback'))return;
      const fallback=el('span','sd-image-fallback');fallback.setAttribute('aria-hidden','true');
      const text=parent.closest('.store-directory-card')?.querySelector('strong')?.textContent?.replace('✓','').trim();
      if(text){fallback.textContent=text.split(/\s+/).slice(0,2).map(w=>w[0]).join('').toUpperCase();}
      else {const category=(parent.querySelector('img')?.alt||'').toLowerCase();fallback.append(icon(parent.matches('.hero-promo-image-wrap')?'bag':parent.matches('.cat-btn')?(category.includes('snack')?'cookie':category.includes('drink')?'cup':category.includes('vegg')?'leaf':category.includes('pickup')?'food':category.includes('clean')?'pickup':'bag'):'image'));}
      parent.append(fallback);
    };
    img.addEventListener('error',fail);
    img.addEventListener('load',()=>{img.classList.remove('sd-image-unavailable');const parent=img.parentElement;parent?.classList.remove('sd-missing-image');parent?.querySelector(':scope > .sd-image-fallback')?.remove();});
    if(img.complete&&!img.naturalWidth)fail();
  }
  function enhanceCards(root){
    for(const category of root.querySelectorAll('.cat-btn')){
      if(category.dataset.designKeyboard)continue;
      category.dataset.designKeyboard='true';category.setAttribute('role','button');category.tabIndex=0;
      category.addEventListener('keydown',event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();category.click();}});
    }
    for(const card of root.querySelectorAll('.store-directory-card')){
      if(card.querySelector('.store-directory-cover'))continue;
      const img=card.querySelector('img');if(!img)continue;
      const cover=el('span','store-directory-cover');img.before(cover);cover.append(img);
      markImage(img);
      const small=card.querySelector('small');if(small){for(const node of small.childNodes)if(node.nodeType===3)node.textContent=node.textContent.replace(/\s*[→➔]\s*$/,'');small.append(icon('arrow'));}
    }
    for(const img of root.querySelectorAll('.hero-promo-image-wrap img,.cat-btn img,.product-img-wrap img,.store-product>img,.media-card>img')){if(img.closest('.media-card')&&!img.alt)img.alt=img.closest('.media-card').querySelector('h4')?.textContent||'Featured item';markImage(img);}
    for(const button of root.querySelectorAll('.filter-btn'))button.setAttribute('aria-label','Filter products');
  }
  function start(){
    const app=document.getElementById('appScreen');if(!app)return;
    document.documentElement.classList.add('swift-design');
    const login=document.getElementById('loginBox');
    if(login){
      const logo=el('img','sd-login-logo');logo.src='apple-touch-icon.png';logo.alt='SwiftShop';login.prepend(logo);
      for(const [id,text,autocomplete] of [['userName','Full name','name'],['userPhone','Phone number','tel']]){
        const input=document.getElementById(id);if(!input)continue;
        const label=el('label','sd-login-label');label.htmlFor=id;label.textContent=text;input.before(label);input.setAttribute('autocomplete',autocomplete);
      }
    }
    const header=app.querySelector('.header'),title=document.getElementById('title');
    if(title){title.textContent='SwiftShop';const brand=el('div','sd-brand');const logo=el('img','sd-brand-mark');logo.src='favicon.png';logo.alt='';title.before(brand);brand.append(logo,title);}
    const slogan=header?.querySelector(':scope > p');if(slogan){slogan.textContent='';const greeting=el('strong','sd-home-greeting');greeting.textContent='What’s the plan?';const detail=el('span','sd-home-subtitle');detail.textContent='Local favourites. Everyday essentials. Your next ride.';slogan.append(greeting,detail);}
    const balanceValue=document.getElementById('userBalance'),balance=balanceValue?.parentElement;
    if(header&&balance&&balanceValue){
      balance.classList.add('sd-header-balance');balance.removeAttribute('style');
      const label=el('span','sd-balance-label');label.textContent='Balance';
      const amount=el('strong','sd-balance-amount');amount.append(balanceValue,document.createTextNode(' BZD'));
      balance.replaceChildren(label,amount);header.append(balance);
    }
    const location=header?.querySelector('.header-saved-location');if(location)location.prepend(icon('pin'));
    const hero=app.querySelector('.hero-section'),row=app.querySelector('.hero-toggle-row'),search=app.querySelector('.hero-search-wrapper');
    if(hero&&row&&search){hero.prepend(search);search.after(row);}
    const toggles=row?.querySelectorAll('.toggle-btn');
    toggles?.forEach((b,i)=>{
      // Existing delivery mode code reads textContent. SVG adds no label text.
      b.querySelector('img')?.remove();prependIcon(b,['bag','pickup','car'][i]);
      b.style.setProperty('--sd-pill-index',i);
      b.addEventListener('click',()=>b.scrollIntoView({behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'auto':'smooth',block:'nearest',inline:'nearest'}));
    });
    if(row){const quick=el('div','sd-quick-actions');quick.setAttribute('aria-label','Shopping shortcuts');row.after(quick);
      for(const node of [...row.children])if(!node.classList.contains('toggle-box'))quick.append(node);
      const live=document.getElementById('customerTrackButton');if(live){live.textContent='Live order';prependIcon(live,'clock');if(!quick.contains(live))quick.append(live);}
      const rideChip=document.getElementById('customerRideChip');if(rideChip)quick.append(rideChip);
      const offers=quick.querySelector('.hero-live-promos');prependIcon(offers,'offers');
    }
    const group=app.querySelector('.hero-group-order');if(group&&header){group.classList.add('sd-header-group');header.append(group);}
    app.querySelector('.feature-title')?.remove();document.querySelector('.media-section')?.remove();
    const directory=document.getElementById('shopStoreDirectory'),categories=app.querySelector('.store-navigation-wrapper');
    if(directory){const h=directory.querySelector('h2');if(h)h.textContent='Explore local stores';if(categories)categories.before(directory);}
    app.querySelectorAll('.main-tab-btn').forEach((b,i)=>{
      for(const node of b.childNodes)if(node.nodeType===3)node.textContent=node.textContent.replace(/^\s*(🛒|🍲|☕|👗|🔌)\s*/, '');
      prependIcon(b,['bag','food','cup','shirt','phone'][i]);
    });
    const profile=document.querySelector('#profileOverlay .profile-card');
    if(profile){
      const top=profile.querySelector('.profile-top'),points=profile.querySelector('.gamification-box'),services=profile.querySelector('.profile-services');
      if(top&&points){top.after(points);const stats=profile.querySelector('.stats-grid');if(stats)points.after(stats);if(services&&stats)stats.after(services);}
      profile.querySelector('.sd-profile-extras')?.remove();
      app.querySelector('.suggest-btn')?.remove();app.querySelector('.promote-btn')?.remove();header?.querySelector('.social-follow')?.remove();
      for(const b of profile.querySelectorAll('.profile-services-grid button')){
        if(b.querySelector('svg,.menu-icon'))continue;
        const txt=b.textContent.toLowerCase(),wrap=el('span','menu-icon');wrap.setAttribute('aria-hidden','true');wrap.append(icon(txt.includes('favourite')?'heart':txt.includes('history')?'clock':'pin'));b.prepend(wrap);
        for(const n of b.childNodes)if(n.nodeType===3)n.textContent=n.textContent.replace(/^\s*♡\s*/,'');
      }
      const badge=profile.querySelector('.level-badge');if(badge)badge.setAttribute('title','Your current shopper reward level');
    }
    const ride=document.getElementById('customerRidePanel');
    if(ride){
      const map=document.getElementById('crMap'),header=ride.querySelector('.cr-header');
      if(map&&header){
        const stage=el('div','sd-ride-map');header.after(stage);stage.append(map);
        const caption=el('span','sd-map-loading');caption.textContent='Loading your map…';caption.setAttribute('aria-hidden','true');map.append(caption);
        const form=document.getElementById('crForm');
        if(form){const sync=()=>{stage.hidden=form.hidden;};sync();new MutationObserver(sync).observe(form,{attributes:true,attributeFilter:['hidden']});}
      }
      prependIcon(document.getElementById('crGPS'),'pin');prependIcon(document.getElementById('crRequest'),'car');
      const locations=ride.querySelector('.cr-locations');locations?.classList.add('sd-route-fields');
      // Keep live progress and the driver first; the same fare receipt follows the actions.
      const receipt=document.getElementById('crTrackingFare'),actions=ride.querySelector('.cr-track-actions');
      if(receipt&&actions)actions.after(receipt);
    }
    enhanceCards(document);
    new MutationObserver(entries=>{for(const entry of entries)for(const node of entry.addedNodes)if(node.nodeType===1){if(node.matches('img'))markImage(node);enhanceCards(node);}}).observe(app,{childList:true,subtree:true});
    const merchant=document.getElementById('merchantStorePage');if(merchant)new MutationObserver(entries=>{for(const entry of entries)for(const node of entry.addedNodes)if(node.nodeType===1){if(node.matches('img'))markImage(node);enhanceCards(node);}}).observe(merchant,{childList:true,subtree:true});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
