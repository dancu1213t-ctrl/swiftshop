/* Visual feedback only: the existing add handler remains authoritative. */
(()=>{'use strict';
 const running=new Set(),reduced=()=>window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
 function visible(node){if(!node||!node.isConnected)return false;const r=node.getBoundingClientRect();return r.width>0&&r.height>0&&r.bottom>0&&r.top<innerHeight&&r.right>0&&r.left<innerWidth&&getComputedStyle(node).visibility!=='hidden';}
 function source(button){const card=button?.closest?.('.store-product,.product');const img=card?.querySelector('img');if(!img?.complete||!img.naturalWidth||!visible(img))return null;const r=img.getBoundingClientRect();return{src:img.currentSrc||img.src,x:r.left+r.width/2,y:r.top+r.height/2,size:Math.min(100,r.width,r.height)};}
 function fly(from){if(!from||reduced()||document.hidden||!Element.prototype.animate)return;
  const target=[...document.querySelectorAll('#merchantStorePage .store-cart-link,.shop-bottom-nav [data-destination="cart"],#cartBubble')].find(visible);if(!target)return;
  const end=target.getBoundingClientRect();const dx=end.left+end.width/2-from.x,dy=end.top+end.height/2-from.y;
  while(running.size>=2){const oldest=running.values().next().value;running.delete(oldest);oldest.cancel();}
  const ghost=document.createElement('img');ghost.className='swift-cart-flight';ghost.alt='';ghost.setAttribute('aria-hidden','true');ghost.draggable=false;ghost.src=from.src;
  Object.assign(ghost.style,{left:(from.x-from.size/2)+'px',top:(from.y-from.size/2)+'px',width:from.size+'px',height:from.size+'px'});document.body.append(ghost);
  let animation;const clean=()=>{running.delete(animation);ghost.remove();};
  try{animation=ghost.animate([{transform:'translate3d(0,0,0) scale(1)',opacity:.95},{transform:`translate3d(${dx*.45}px,${dy*.35-38}px,0) scale(.72)`,opacity:.9,offset:.48},{transform:`translate3d(${dx}px,${dy}px,0) scale(.12)`,opacity:0}],{duration:520,easing:'cubic-bezier(.25,.7,.3,1)'});running.add(animation);animation.oncancel=clean;animation.onfinish=()=>{clean();if(target.isConnected&&!reduced())target.animate([{opacity:1},{opacity:.72},{opacity:1}],{duration:180});};}catch{clean();}
 }
 const add=window.add;if(typeof add==='function')window.add=function(...args){let from;try{if(!reduced())from=source(args[2]);}catch{}const result=add.apply(this,args);if(result===true&&from){requestAnimationFrame(()=>{try{fly(from);}catch{}});}return result;};
 function stop(){for(const a of [...running])a.cancel();}window.addEventListener('pagehide',stop);document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});
})();
