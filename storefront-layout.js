/* Store sections preserve existing catalogue and About controls. */
(()=>{'use strict';
document.addEventListener('DOMContentLoaded',()=>{
 const open=window.openMerchantStore;if(typeof open!=='function')return;let sequence=0,disposeMap=()=>{};
 const make=(tag,text,cls)=>{const n=document.createElement(tag);if(text)n.textContent=text;if(cls)n.className=cls;return n;};
 window.openMerchantStore=async function(category,...args){
  disposeMap();disposeMap=()=>{};const ticket=++sequence,page=document.getElementById('merchantStorePage');
  page?.querySelector('.store-section-nav')?.remove();page?.querySelector('.store-location-panel')?.remove();if(page)page.dataset.storeView='menu';
  const result=await open.call(this,category,...args);
  if(ticket!==sequence||!page||page.style.display==='none')return result;
  const search=page.querySelector('.store-search-row'),info=page.querySelector('#storePublicDetails');if(!search)return result;
  const nav=make('nav',null,'store-section-nav');nav.setAttribute('aria-label','Store sections');
  const panel=make('section',null,'store-location-panel');panel.hidden=true;panel.setAttribute('aria-label','Store location');
  const row=window.SwiftStoreInfo?.rows.get(category),lat=Number(row?.latitude),lng=Number(row?.longitude);let showMap=()=>{};
  panel.append(make('h2','Location'));
  if(row?.address)panel.append(make('p',row.address));
  if(row?.latitude!=null&&row?.longitude!=null&&Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)<=90&&Math.abs(lng)<=180){
   const host=make('div',null,'store-branded-map');host.setAttribute('aria-label','Store location map');panel.append(host);let map=null,marker=null;
   const logo=page.querySelector('.store-avatar img')?.src,name=page.querySelector('h1')?.textContent||'Store';
   const styles=[
    {elementType:'geometry',stylers:[{color:'#eeece6'}]},
    {elementType:'labels.text.fill',stylers:[{color:'#424740'}]},
    {elementType:'labels.text.stroke',stylers:[{color:'#f7f6f1'}]},
    {featureType:'poi',stylers:[{visibility:'off'}]},
    {featureType:'transit',stylers:[{visibility:'off'}]},
    {featureType:'landscape.man_made',elementType:'geometry',stylers:[{color:'#e5e3dc'}]},
    {featureType:'landscape.natural',elementType:'geometry',stylers:[{color:'#e6e9df'}]},
    {featureType:'poi.park',elementType:'geometry',stylers:[{visibility:'on'},{color:'#d7dfcc'}]},
    {featureType:'road',elementType:'geometry.fill',stylers:[{color:'#ffffff'}]},
    {featureType:'road',elementType:'geometry.stroke',stylers:[{color:'#b6bab1'},{weight:1}]},
    {featureType:'road',elementType:'labels.text.fill',stylers:[{color:'#52584e'}]},
    {featureType:'road.highway',elementType:'geometry.fill',stylers:[{color:'#d3d5cc'}]},
    {featureType:'water',elementType:'geometry',stylers:[{color:'#b8ced2'}]}
   ];
   showMap=()=>requestAnimationFrame(()=>{
    if(ticket!==sequence||panel.hidden||map)return;
    if(!window.google?.maps?.Map){const retry=make('button','Reload map');retry.type='button';retry.onclick=showMap;host.replaceChildren(make('p','Map unavailable. Please reconnect and try again.'),retry);return;}
    try{host.replaceChildren();const point={lat,lng};map=new google.maps.Map(host,{center:point,zoom:17,styles,mapTypeControl:false,streetViewControl:false,fullscreenControl:false,zoomControl:true,gestureHandling:'cooperative',clickableIcons:false});
     class StoreLogo extends google.maps.OverlayView{
      onAdd(){this.node=make('div',null,'store-map-logo');this.node.setAttribute('role','img');this.node.setAttribute('aria-label',name+' location');if(logo){const img=make('img');img.src=logo;img.alt='';img.onerror=()=>{img.remove();this.node.textContent=name.trim().slice(0,1);};this.node.append(img);}else this.node.textContent=name.trim().slice(0,1);this.getPanes().floatPane.append(this.node);}
      draw(){const p=this.getProjection().fromLatLngToDivPixel(new google.maps.LatLng(point));if(this.node&&p){this.node.style.left=p.x+'px';this.node.style.top=p.y+'px';}}
      onRemove(){this.node?.remove();}
     }
     marker=new StoreLogo();marker.setMap(map);disposeMap=()=>{marker?.setMap(null);if(map)google.maps.event.clearInstanceListeners(map);map=null;};
    }catch{map=null;host.replaceChildren(make('p','Map unavailable. Use Open in Google Maps below.'));}
   });
   const link=make('a','Open in Google Maps');link.href='https://www.google.com/maps/search/?api=1&query='+encodeURIComponent(lat+','+lng);link.target='_blank';link.rel='noopener noreferrer';panel.append(link);
  }else panel.append(make('p','Map location has not been added yet.'));
  const tabs=[];function select(view){page.dataset.storeView=view;panel.hidden=view!=='location';if(view==='location')showMap();if(info)info.hidden=view!=='about';for(const b of tabs)b.setAttribute('aria-current',String(b.dataset.view===view));}
  for(const [view,label] of [['menu','Menu/Items'],['about','About'],['location','Location']]){
   if(view==='about'&&!info)continue;const b=make('button',label);b.type='button';b.dataset.view=view;
   b.onclick=()=>{select(view);if(view==='about'){const toggle=page.querySelector('.store-about-toggle');if(toggle?.getAttribute('aria-expanded')==='false')toggle.click();}};tabs.push(b);nav.append(b);
  }
  if(info){info.before(nav);info.after(panel);}else{search.before(nav);nav.after(panel);}select('menu');return result;
 };
});
})();

/* Read-only explanation of the existing server quote. */
(()=>{'use strict';let dialog,rows,total,note;
function make(tag,text){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;}
const money=c=>'BZ$'+(Number(c||0)/100).toFixed(2);
function init(){dialog=make('dialog');dialog.id='swiftDeliveryFeeInfo';dialog.setAttribute('aria-labelledby','deliveryFeeInfoTitle');
 const head=make('header'),title=make('h2','Delivery Fee info'),close=make('button','×');title.id='deliveryFeeInfoTitle';close.type='button';close.setAttribute('aria-label','Close delivery fee info');close.onclick=()=>dialog.close();head.append(title,close);
 rows=make('dl');const summary=make('div');summary.className='delivery-fee-info-total';total=make('strong');summary.append(make('span','Delivery total'),total);note=make('p');const done=make('button','Got it');done.type='button';done.className='delivery-fee-info-done';done.onclick=()=>dialog.close();dialog.append(head,rows,summary,note,done);document.body.append(dialog);
 dialog.addEventListener('click',e=>{if(e.target!==dialog)return;const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close();});
}
function show(){const q=window.SwiftRegions?.breakdown?.(),zone=q?.zone_id||window.SwiftRegions?.zone||'orange-walk',fee=Math.round(Number(window.getCartDeliveryFee?.()||0)*100);rows.replaceChildren();const row=(label,cents)=>{const n=make('div');n.append(make('dt',label),make('dd',money(cents)));rows.append(n);};
 if(zone==='orange-walk'){row('Base delivery',q?.base_fee_cents??450);const nearby=Number(q?.nearby_extra_stops||0),cross=Number(q?.cross_town_extra_stops||0);if(nearby)row(nearby+' nearby extra pickup'+(nearby===1?'':'s'),nearby*150);if(cross)row(cross+' cross-town extra pickup'+(cross===1?'':'s'),cross*200);note.textContent='Extra pickup: BZ$1.50 nearby or BZ$2 over 3 km between pickup pins. Your final drop-off is included.';}
 else{row('Delivery',fee);note.textContent='Your fee follows this service area’s approved distance rates. Your final drop-off is included.';}
 total.textContent=money(fee);if(!dialog.open)dialog.showModal();window.SwiftNavigation?.refresh();}
document.addEventListener('click',e=>{if(!e.target.closest('[data-delivery-fee-info]'))return;if(!dialog)init();show();});
})();