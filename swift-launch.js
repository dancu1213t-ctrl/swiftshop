/* Decorative cold-launch cover. Never blocks app initialization or input. */
(()=>{'use strict';let seen=false;try{seen=sessionStorage.getItem('swiftshop.launch.v1')==='1';sessionStorage.setItem('swiftshop.launch.v1','1');}catch{}if(seen)return;
const cover=document.createElement('div');cover.id='swiftLaunch';cover.setAttribute('aria-hidden','true');cover.innerHTML='<div class="launch-stage"><span class="launch-word">SwiftShop</span><span class="launch-shapes"><i></i><i></i></span><img class="launch-logo" src="app-icon-192.png" alt="" width="112" height="112"></div>';document.body.prepend(cover);
let done=false;function finish(){if(done)return;done=true;cover.remove();}cover.addEventListener('animationend',e=>{if(e.target===cover)finish();});window.addEventListener('pagehide',finish,{once:true});setTimeout(finish,1800);
})();
