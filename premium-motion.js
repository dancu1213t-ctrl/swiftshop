(() => {
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  if(!('IntersectionObserver' in window))return;
  const seen=new WeakSet();
  const observer=new IntersectionObserver(entries=>{
    for(const entry of entries){
      if(!entry.isIntersecting)continue;
      observer.unobserve(entry.target);
      if(!reduced.matches && entry.target.animate)entry.target.animate([{opacity:.35},{opacity:1}],{duration:240,easing:'cubic-bezier(.22,1,.36,1)'});
    }
  },{threshold:.08});
  const selector='.product,.store-product,.store-directory-card,.shopping-list-card';
  function scan(root){
    if(!(root instanceof Element))return;
    const cards=[...(root.matches(selector)?[root]:[]),...root.querySelectorAll(selector)];
    for(const card of cards){if(seen.has(card))continue;seen.add(card);observer.observe(card);}
  }
  function start(){
    for(const id of ['appScreen','merchantStorePage','orderHistoryPage','favouritesPage']){
      const root=document.getElementById(id);if(!root)continue;scan(root);
      new MutationObserver(entries=>{for(const entry of entries)for(const node of entry.addedNodes)scan(node);}).observe(root,{childList:true,subtree:true});
    }
    document.querySelector('.shop-bottom-nav')?.addEventListener('click',event=>{
      if(reduced.matches)return;
      const icon=event.target.closest('button')?.querySelector('svg');
      icon?.animate?.([{transform:'scale(.88)'},{transform:'scale(1)'}],{duration:220,easing:'cubic-bezier(.22,1,.36,1)'});
    });
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
