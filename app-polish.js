(() => {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const ids = ['authScreen','cartPanel','orderBox','tacoOrderBox','pickupOrderBox','requestRideBox','profileOverlay','customerRidePanel','customerLiveOrder','merchantStorePage','deliveryNotificationInbox','promoPage','favouritesPage','orderHistoryPage','savedAddressesPage','suggestOverlay','locationModal','foodMapScreen','leaderBoardScreen','creditPurchaseScreen','creditConfirmScreen','adminScreen','imageOverlay','spinWheelModal','rewardChoiceModal'];
  function visible(element) {
    if(element.hidden || (element.tagName==='DIALOG' && !element.open)) return false;
    const style=getComputedStyle(element);
    return style.display!=='none' && style.visibility!=='hidden' && !!element.getClientRects().length;
  }
  function wire() {
    for(const id of ids) {
      const element=document.getElementById(id);
      if(!element || element.dataset.swiftPolished) continue;
      element.dataset.swiftPolished='true';
      let wasVisible=visible(element), animation=null;
      new MutationObserver(()=>{
        const now=visible(element);
        if(!now)animation?.cancel();
        if(now && !wasVisible && !reduced.matches && element.animate) {
          animation?.cancel();
          // Opacity preserves existing slide positions, map bounds and scroll locks.
          animation=element.animate([{opacity:0},{opacity:1}],{duration:210,easing:'cubic-bezier(.22,1,.36,1)'});
        }
        wasVisible=now;
      }).observe(element,{attributes:true,attributeFilter:['style','class','hidden','open']});
    }
  }
  wire();
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',wire,{once:true});
})();
