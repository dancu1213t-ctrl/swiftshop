/* One presentation lifecycle. Never delay clicks, navigation, prices or payments. */
(() => {
  'use strict';
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  const ids=['authScreen','cartPanel','orderBox','pickupOrderBox','requestRideBox','profileOverlay','customerRidePanel','customerLiveOrder','merchantStorePage','deliveryNotificationInbox','promoPage','favouritesPage','orderHistoryPage','savedAddressesPage','locationModal','foodMapScreen','leaderBoardScreen','creditPurchaseScreen','creditConfirmScreen','adminScreen','imageOverlay','swiftProductDetails','productPhotoDialog','pureOfferOrderPage','swiftPayPage','swiftCreditTransferDialog','swiftPayStoreDialog','swiftPayPaymentDialog','catalogueFilterDialog','pharmacyStoreChooser','swiftOrderInstructions','swiftOrderChat','swiftDeliveryFeeInfo'];
  const wired=new WeakSet();
  function visible(el){
    if(el.hidden||(el.tagName==='DIALOG'&&!el.open))return false;
    if(el.id==='cartPanel'&&!['0','0px'].includes(el.style.bottom))return false;
    const style=getComputedStyle(el);
    return style.display!=='none'&&style.visibility!=='hidden'&&!!el.getClientRects().length;
  }
  function wire(el){
    if(!el||wired.has(el))return;wired.add(el);
    let shown=visible(el),animation;
    new MutationObserver(()=>{
      const now=visible(el);
      if(!now){animation?.cancel();animation=null;}
      if(now&&!shown&&!reduced.matches&&!document.hidden&&el.animate){
        animation?.cancel();
        // Opacity only: never replace centering transforms or force map/layout resizes.
        animation=el.animate([{opacity:.65},{opacity:1}],{duration:160,easing:'cubic-bezier(.2,.8,.2,1)'});
      }
      shown=now;
    }).observe(el,{attributes:true,attributeFilter:['style','class','hidden','open']});
  }
  function scan(root){if(root.nodeType!==1)return;for(const el of [root,...root.querySelectorAll('[id]')])if(ids.includes(el.id))wire(el);}
  function clear(host){if(!host)return;host.querySelectorAll(':scope > .swift-skeleton-card').forEach(n=>n.remove());host.removeAttribute('aria-busy');}
  function show(host){
    if(!host||host.querySelector(':scope > .swift-skeleton-card'))return;
    host.setAttribute('aria-busy','true');const fragment=document.createDocumentFragment();
    for(let i=0;i<6;i++){
      const card=document.createElement('div');card.className='swift-skeleton-card';card.setAttribute('aria-hidden','true');
      for(const cls of ['swift-skeleton-photo','swift-skeleton-line','swift-skeleton-line short','swift-skeleton-action']){const piece=document.createElement('span');piece.className=cls;card.append(piece);}
      fragment.append(card);
    }
    host.replaceChildren(fragment);
  }
  window.SwiftLoading={show,clear};
  function start(){
    ids.forEach(id=>wire(document.getElementById(id)));
    // New dialogs are appended directly to body; ignore all descendant text changes.
    new MutationObserver(records=>{for(const record of records)for(const node of record.addedNodes)scan(node);}).observe(document.body,{childList:true});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
