/* A welcome reveal only after an explicitly completed customer sign-in. */
(()=>{
 let cleanup=null;
 window.showSwiftShopWelcome=(openHome)=>{
  cleanup?.();
  const cover=document.getElementById('swiftLoginReveal');
  if(!cover||window.matchMedia('(prefers-reduced-motion: reduce)').matches){openHome();return;}
  cover.hidden=false;
  cover.classList.add('active');
  const app=document.getElementById('appScreen');
  let timer;
  cleanup=()=>{clearTimeout(timer);cover.hidden=true;cover.classList.remove('active');if(app)app.inert=false;cleanup=null;};
  try{openHome();if(app)app.inert=true;timer=setTimeout(()=>cleanup?.(),1500);}
  catch(error){cleanup();throw error;}
 };
})();
