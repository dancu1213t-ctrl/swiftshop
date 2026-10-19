(()=>{'use strict';
const root=document.documentElement;let active=null,frame=0,lastInput=null,pointerInFlight=false,revealPending=false;
const panelFor=e=>e instanceof Element?e.closest('#customerRidePanel,#pickupOrderBox'):null;
const field=e=>e instanceof Element&&e.matches('input:not([type=button]):not([type=submit]):not([type=checkbox]):not([type=radio]):not([type=hidden]),textarea');
function layout(){frame=0;const panel=panelFor(document.activeElement);const mobile=matchMedia('(max-width:700px)').matches;
if(pointerInFlight&&active&&!field(document.activeElement))return;
if(!mobile||!panel||!field(document.activeElement)){if(active){active.classList.remove('swift-location-editing');active=null;}lastInput=null;root.classList.remove('swift-location-search','swift-pickup-search');return;}
if(active&&active!==panel)active.classList.remove('swift-location-editing');active=panel;active.classList.add('swift-location-editing');root.classList.toggle('swift-location-search',panel.id!=='pickupOrderBox');root.classList.toggle('swift-pickup-search',panel.id==='pickupOrderBox');
const v=window.visualViewport,top=v?v.offsetTop:0,height=v?v.height:innerHeight;
root.style.setProperty('--location-view-top',top+'px');root.style.setProperty('--location-view-height',height+'px');
const input=document.activeElement,r=input.getBoundingClientRect();if(input!==lastInput||revealPending){const safe=parseFloat(getComputedStyle(panel).paddingTop)||16,upper=top+safe,lower=top+height-64;if(r.top<upper)panel.scrollTop+=r.top-upper;else if(r.bottom>lower)panel.scrollTop+=r.bottom-lower;revealPending=false;}lastInput=input;
const rect=input.getBoundingClientRect(),space=Math.max(0,Math.min(240,top+height-rect.bottom-12));
for(const list of document.querySelectorAll('.pac-container')){if(getComputedStyle(list).display==='none')continue;list.style.setProperty('position','fixed','important');list.style.setProperty('top',Math.max(top,rect.bottom+4)+'px','important');list.style.setProperty('left',Math.max(8,rect.left)+'px','important');list.style.setProperty('width',Math.min(rect.width,innerWidth-16)+'px','important');list.style.setProperty('max-height',space+'px','important');list.dataset.swiftLocationPosition='true';}}
function queue(){if(!frame)frame=requestAnimationFrame(layout);}
function restore(){if(panelFor(document.activeElement)&&field(document.activeElement))return;for(const list of document.querySelectorAll('.pac-container[data-swift-location-position]')){for(const p of ['position','top','left','width','max-height'])list.style.removeProperty(p);delete list.dataset.swiftLocationPosition;}}
document.addEventListener('pointerdown',e=>{if(active&&!field(e.target))pointerInFlight=true;},true);
const finishPointer=()=>{pointerInFlight=false;requestAnimationFrame(()=>{layout();restore();});};
document.addEventListener('pointerup',finishPointer,true);document.addEventListener('pointercancel',finishPointer,true);
document.addEventListener('focusin',()=>{revealPending=true;layout();queue();},true);document.addEventListener('focusout',()=>requestAnimationFrame(()=>{layout();restore();}),true);
window.visualViewport?.addEventListener('resize',()=>{revealPending=true;queue();});window.visualViewport?.addEventListener('scroll',queue);window.addEventListener('resize',queue);
document.addEventListener('input',queue,true);document.addEventListener('scroll',()=>{if(active)queue();},true);
new MutationObserver(()=>{if(active)queue();}).observe(document.body,{childList:true,subtree:true});
const style=document.createElement('style');style.textContent=`
@media(max-width:700px){
/* Pickup needs one scroll surface; nested fixed ancestors clip on iOS. */
html.swift-pickup-search{overflow:hidden!important}
html.swift-pickup-search body{position:relative!important;top:0!important;bottom:auto!important;height:auto!important;min-height:0!important;overflow:hidden!important}
html.swift-pickup-search #appScreen{position:static!important;transform:none!important;overflow:visible!important}
html.swift-pickup-search body #pickupOrderBox.swift-location-editing{position:fixed!important;inset:auto 0 auto!important;top:var(--location-view-top,0px)!important;bottom:auto!important;width:100%!important;height:var(--location-view-height,100dvh)!important;max-height:var(--location-view-height,100dvh)!important;min-height:0!important;margin:0!important;padding:calc(16px + env(safe-area-inset-top,0px)) 16px 24px!important;box-sizing:border-box!important;transform:none!important;translate:none!important;animation:none!important;overflow:auto!important;overscroll-behavior:contain!important;-webkit-overflow-scrolling:touch;touch-action:pan-y!important;scroll-behavior:auto!important;z-index:70000!important;border:0!important;border-radius:0!important;background:#fff!important}
html.swift-pickup-search #pickupOrderBox .pd-map-area{display:none!important}
html.swift-pickup-search .shop-bottom-nav{display:none!important}
html.swift-pickup-search #pickupOrderBox input,html.swift-pickup-search #pickupOrderBox textarea{font-size:16px!important}
html.swift-pickup-search .pac-container{z-index:70010!important;overflow-y:auto!important;overscroll-behavior:contain;box-sizing:border-box;border-radius:12px}
html.swift-pickup-search .pac-item{min-height:42px;line-height:42px;font-size:12px}

/* Existing page navigation locks body with a negative top. iOS clips fixed
   descendants to that displaced body when its keyboard opens. Neutralize the
   lock only during editing; the original inline position is restored on blur. */
html.swift-location-search{height:100%!important;min-height:100%!important;overflow:hidden!important}
html.swift-location-search body{position:fixed!important;top:0!important;left:0!important;right:0!important;bottom:0!important;width:100%!important;height:100%!important;max-height:none!important;min-height:0!important;margin:0!important;overflow:visible!important;background:#fff!important}
html.swift-location-search body #appScreen{position:static!important;overflow:visible!important;transform:none!important;min-height:0!important;height:0!important}
html.swift-location-search body #appScreen>:not(#pickupOrderBox){visibility:hidden!important;pointer-events:none!important}
html.swift-location-search body #appScreen #pickupOrderBox{visibility:visible!important;pointer-events:auto!important}
html.swift-location-search body #pickupOrderBox.swift-location-editing{clip:auto!important;clip-path:none!important;contain:none!important}
html.swift-location-search body #customerRidePanel .cr-shell{height:auto!important;max-height:none!important;min-height:0!important;overflow:visible!important}

html.swift-location-search body #customerRidePanel.swift-location-editing,html.swift-location-search body #pickupOrderBox.swift-location-editing{position:fixed!important;inset:auto 0 auto 0!important;top:var(--location-view-top,0px)!important;height:var(--location-view-height,100dvh)!important;max-height:var(--location-view-height,100dvh)!important;min-height:0!important;width:100%!important;max-width:none!important;margin:0!important;box-sizing:border-box!important;transform:none!important;translate:none!important;animation:none!important;z-index:70000!important;overflow-x:hidden!important;overflow-y:auto!important;background:#fff!important;padding:16px 16px 24px!important;overscroll-behavior:contain;touch-action:pan-y!important;-webkit-overflow-scrolling:touch;scroll-behavior:auto!important;scroll-padding:16px 0 64px!important}
html.swift-location-search #shopStoreDirectory,html.swift-location-search #heroPromoSlider,html.swift-location-search .shop-bottom-nav{visibility:hidden!important;pointer-events:none!important}
html.swift-location-search .swift-location-editing .sd-ride-map,html.swift-location-search .swift-location-editing #crMap,html.swift-location-search .swift-location-editing #pickupMap,html.swift-location-search .swift-location-editing .pd-map-area{display:none!important}
html.swift-location-search #customerRidePanel .cr-shell{display:block!important;padding:0!important;margin:0!important}
html.swift-location-search #customerRidePanel #crForm{display:block!important;padding:12px!important;margin:0!important}
html.swift-location-search #customerRidePanel .cr-header{padding:0!important;margin:0 0 12px!important}
html.swift-location-search .pac-container{z-index:70010!important;overflow-y:auto!important;overscroll-behavior:contain;box-sizing:border-box;border-radius:12px;box-shadow:0 6px 24px #0002}
html.swift-location-search .pac-item{min-height:42px;line-height:42px;font-size:12px}
html.swift-location-search .swift-location-editing input{font-size:16px!important}
}`;document.head.append(style);
})();