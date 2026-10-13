(()=>{'use strict';
const blocked='.hero-promo-image-wrap,.cat-btn,.store-directory-cover,#storePaidAd,.pure-offer-card,.live-offer-card,.offer-card';
const cache=new Map();let aliases={};let queued=false;
async function hash(src){if(!cache.has(src))cache.set(src,crypto.subtle.digest('SHA-256',new TextEncoder().encode(src)).then(buffer=>[...new Uint8Array(buffer)].map(b=>b.toString(16).padStart(2,'0')).join('').slice(0,24)));return cache.get(src);}
async function apply(img){const src=img.getAttribute('src');if(!src||img.closest(blocked)||src.includes('/customer-cutouts-20261012/'))return;const key=await hash(src);const target=aliases[key];if(!target||img.getAttribute('src')!==src)return;img.dataset.originalProductPhoto=src;img.addEventListener('error',()=>{if(img.getAttribute('src')===target){img.dataset.cutoutFailed='true';img.src=src;}},{once:true});if(img.dataset.cutoutFailed)return;img.src=target;img.classList.add('transparent-product-photo');}
function scan(){queued=false;document.querySelectorAll('img[src]').forEach(img=>apply(img).catch(()=>{}));}
function schedule(){if(!queued){queued=true;requestAnimationFrame(scan);}}
fetch('product-cutouts.json?v=20261012').then(r=>{if(!r.ok)throw Error('Unavailable');return r.json();}).then(data=>{aliases=data;scan();new MutationObserver(schedule).observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['src']});}).catch(()=>{});
})();