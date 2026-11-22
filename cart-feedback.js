/* Visual feedback only: the existing add handler remains authoritative. */
(()=>{'use strict';
 const running=new Set(),arrivals=new Set(),reduced=()=>window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
 function visible(node){if(!node||!node.isConnected)return false;const r=node.getBoundingClientRect();return r.width>0&&r.height>0&&r.bottom>0&&r.top<innerHeight&&r.right>0&&r.left<innerWidth&&getComputedStyle(node).visibility!=='hidden';}
 function source(button){const card=button?.closest?.('.store-product,.product');const img=card?.querySelector('img');if(!img?.complete||!img.naturalWidth||!visible(img))return null;const r=img.getBoundingClientRect();return{src:img.currentSrc||img.src,x:r.left+r.width/2,y:r.top+r.height/2,size:Math.min(100,r.width,r.height)};}
 function arrive(target,x,y){
  if(!target.isConnected||reduced()||document.hidden)return;
  while(arrivals.size>=2){const oldest=arrivals.values().next().value;arrivals.delete(oldest);oldest.cancel();}
  const ring=document.createElement('span');ring.className='swift-cart-arrival';ring.setAttribute('aria-hidden','true');Object.assign(ring.style,{left:(x-18)+'px',top:(y-18)+'px'});(target.closest('dialog[open]')||document.body).append(ring);
  let animation;const clean=()=>{arrivals.delete(animation);ring.remove();};try{animation=ring.animate([{transform:'scale(.4)',opacity:.65},{transform:'scale(1.5)',opacity:0}],{duration:260,easing:'cubic-bezier(.16,1,.3,1)'});arrivals.add(animation);animation.onfinish=clean;animation.oncancel=clean;}catch{clean();}
 }
 function fly(from){if(!from||reduced()||document.hidden||!Element.prototype.animate)return;
  const target=[...document.querySelectorAll('#swiftBudgetMeals .bm-footer .bm-cart-link,#swiftBudgetMeals .bm-header .bm-cart-link,#merchantStorePage .store-cart-link,.shop-bottom-nav [data-destination="cart"],#cartBubble')].find(visible);if(!target)return;
  const end=target.getBoundingClientRect(),x=end.width>160?end.right-32:end.left+end.width/2,y=end.top+end.height/2;const dx=x-from.x,dy=y-from.y;
  while(running.size>=2){const oldest=running.values().next().value;running.delete(oldest);oldest.cancel();}
  const ghost=document.createElement('img');ghost.className='swift-cart-flight';ghost.alt='';ghost.setAttribute('aria-hidden','true');ghost.draggable=false;ghost.src=from.src;
  Object.assign(ghost.style,{left:(from.x-from.size/2)+'px',top:(from.y-from.size/2)+'px',width:from.size+'px',height:from.size+'px'});(target.closest('dialog[open]')||document.body).append(ghost);
  let animation;const clean=()=>{running.delete(animation);ghost.remove();};
  // Sample a single cubic curve: lift, glide, then settle into the cart.
  const frames=[],direction=dx<0?-1:1;
  for(let i=0;i<=24;i++){const t=i/24,u=1-t,px=3*u*u*t*(dx*.12)+3*u*t*t*(dx*.85)+t*t*t*dx,py=3*u*u*t*Math.min(-52,dy*.15-70)+3*u*t*t*(dy*.75-38)+t*t*t*dy,scale=t<.16?1+.06*Math.sin(t/.16*Math.PI):1-.9*Math.pow((t-.16)/.84,.85),tilt=direction*Math.sin(t*Math.PI)*-7;frames.push({transform:`translate3d(${px}px,${py}px,0) rotate(${tilt}deg) scale(${scale})`,opacity:t<.76?1:Math.max(0,(1-t)/.24),offset:t});}
  try{animation=ghost.animate(frames,{duration:520,easing:'cubic-bezier(.22,.61,.36,1)'});running.add(animation);animation.oncancel=clean;animation.onfinish=()=>{clean();arrive(target,x,y);};}catch{clean();}
 }
 const add=window.add;if(typeof add==='function')window.add=function(...args){let from;try{if(!reduced())from=source(args[2]);}catch{}const result=add.apply(this,args);if(result===true&&from){requestAnimationFrame(()=>{try{fly(from);}catch{}});}return result;};
 function stop(){for(const a of [...running,...arrivals])a.cancel();}window.addEventListener('pagehide',stop);document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});
})();
