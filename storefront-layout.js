/* Navigation shortcuts use the existing About disclosure and product controls. */
(()=>{'use strict';
document.addEventListener('DOMContentLoaded',()=>{
 const open=window.openMerchantStore;if(typeof open!=='function')return;
 window.openMerchantStore=async function(...args){
  const result=await open.apply(this,args),page=document.getElementById('merchantStorePage');
  if(!page||page.style.display==='none')return result;
  page.querySelector('.store-section-nav')?.remove();
  const search=page.querySelector('.store-search-row'),info=page.querySelector('#storePublicDetails');
  if(!search)return result;
  const nav=document.createElement('nav');nav.className='store-section-nav';nav.setAttribute('aria-label','Store sections');
  const menu=document.createElement('button');menu.type='button';menu.textContent='Menu';menu.setAttribute('aria-current','true');
  const about=document.createElement('button');about.type='button';about.textContent='About';about.setAttribute('aria-current','false');
  if(info)info.hidden=true;
  function select(which){if(info)info.hidden=which!==about;menu.setAttribute('aria-current',String(which===menu));about.setAttribute('aria-current',String(which===about));}
  menu.onclick=()=>{select(menu);const toggle=page.querySelector('.store-about-toggle');if(toggle?.getAttribute('aria-expanded')==='true')toggle.click();search.scrollIntoView({block:'start',behavior:'smooth'});};
  about.onclick=()=>{select(about);const toggle=page.querySelector('.store-about-toggle');if(toggle?.getAttribute('aria-expanded')==='false')toggle.click();info?.scrollIntoView({block:'start',behavior:'smooth'});};
  nav.append(menu);if(info){nav.append(about);info.before(nav);}else search.before(nav);
  return result;
 };
});
})();
