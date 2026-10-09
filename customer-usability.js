(() => {
 'use strict';
 const update=()=>{const v=window.visualViewport;if(!v)return;document.documentElement.style.setProperty('--swift-viewport-height',v.height+'px');const editing=document.activeElement?.matches('input,textarea,select');document.documentElement.classList.toggle('swift-keyboard-open',!!editing&&window.innerHeight-v.height>120);};
 window.visualViewport?.addEventListener('resize',update);window.visualViewport?.addEventListener('scroll',update);window.addEventListener('resize',update);document.addEventListener('focusout',()=>requestAnimationFrame(update));
 document.addEventListener('focusin',event=>{update();if(!event.target.matches('input,textarea,select'))return;setTimeout(()=>{if(document.activeElement===event.target)event.target.scrollIntoView({block:'nearest',behavior:'smooth'});},180);});update();
 document.addEventListener('DOMContentLoaded',()=>{
  const navigation=window.SwiftNavigation;if(!navigation)return;const original=navigation.back;
  navigation.back=function(){
   const dialog=[...document.querySelectorAll('dialog[open]')].at(-1);
   if(dialog){const close=dialog.querySelector('[data-close],[data-qr-close],#cloClose');if(close){if(!close.disabled)close.click();}else if(dialog.dispatchEvent(new Event('cancel',{cancelable:true})))dialog.close();return true;}
   return original.apply(this,arguments);
  };
 });
 // Dialogs created after the navigation coordinator also support Escape/back and focus restoration.
 document.addEventListener('keydown',e=>{if(e.key!=='Escape'||e.defaultPrevented)return;const dialog=[...document.querySelectorAll('dialog[open]')].at(-1);if(dialog){const close=dialog.querySelector('[data-close],[data-qr-close]');if(close){close.click();e.preventDefault();}}});
})();
