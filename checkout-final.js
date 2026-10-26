(()=>{'use strict';
const point=value=>{if(typeof value!=='string'||!/^\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*$/.test(value))return null;const [lat,lng]=value.split(',').map(Number);return Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)<=90&&Math.abs(lng)<=180?{lat,lng}:null;};
function start(){
const box=document.getElementById('orderBox');if(!box)return;
const make=(tag,text)=>{const e=document.createElement(tag);if(text)e.textContent=text;return e;};
const choices=make('div');choices.className='checkout-choices';document.getElementById('orderHint').after(choices);
const buttons=[];
for(const [id,label] of [['groupEnabled','Group order'],['giftEnabled','Send as a gift']]){
 const input=document.getElementById(id),button=make('button');button.type='button';button.className='checkout-choice';button.setAttribute('aria-controls',input.getAttribute('aria-controls'));
 const icon=input.closest('label').querySelector('svg')?.cloneNode(true);if(icon)button.append(icon);button.append(make('span',label));
 const sync=()=>{button.setAttribute('aria-pressed',String(input.checked));button.setAttribute('aria-expanded',String(input.checked));};
 button.onclick=()=>{input.checked=!input.checked;input.dispatchEvent(new Event('change',{bubbles:true}));buttons.forEach(fn=>fn());render();};input.addEventListener('change',()=>{sync();buttons.forEach(fn=>fn());});buttons.push(sync);sync();choices.append(button);
}
const areaState=document.getElementById('checkoutAreaState'),zone=document.getElementById('deliveryZoneSelect'),gift=document.getElementById('giftEnabled'),giftArea=make('label','Recipient\u2019s delivery area');giftArea.id='checkoutGiftArea';
let normalZone=window.lastCartZone||zone.value;
const areaConfirm=document.getElementById('giftAreaConfirmed').closest('label');areaConfirm.before(giftArea);
function area(){if(gift.checked){giftArea.append(zone);}else{areaState.append(zone);if(window.lastCartZone)zone.value=window.lastCartZone;}giftArea.hidden=!gift.checked;}
gift.addEventListener('change',()=>{if(gift.checked){normalZone=window.lastCartZone||zone.value;}else if(normalZone){zone.value=normalZone;setDeliveryZone(normalZone);}area();});area();
const panel=make('section');panel.className='checkout-route';panel.setAttribute('aria-label','Delivery route preview');const mapNode=make('div');mapNode.id='checkoutRouteMap';mapNode.setAttribute('aria-hidden','true');const caption=make('p');caption.id='checkoutRouteCaption';panel.append(make('h3','Pickup \u2192 Delivery'),mapNode,caption);
const review=box.querySelector('.sq-review');(review||box.querySelector('.submit-track')).before(panel);
let map,objects=[],fingerprint='';
function render(){if(box.style.display==='none'||!box.style.display)return;area();document.getElementById('selectedTipAmount').value='0';
 const destination=gift.checked?point(document.getElementById('giftAddress').value):point(window.lastCartCoords);
 const categories=[...new Set(Object.values(typeof cart==='undefined'?{}:cart).filter(v=>v.q>0).map(v=>String(v.cat||'').toUpperCase()))];
 const stops=categories.map(category=>({category,position:point(typeof storeLocations==='undefined'?null:storeLocations[category])})).filter(v=>v.position);
 const key=JSON.stringify([destination,stops,gift.checked]);if(key===fingerprint&&map)return;fingerprint=key;
 objects.forEach(v=>v.setMap(null));objects=[];
 if(!destination||!stops.length){mapNode.hidden=true;caption.textContent=gift.checked?'Recipient\u2019s address will be confirmed by Dispatch.':'Select your delivery pin in the previous step to preview the route.';return;}
 mapNode.hidden=false;caption.textContent=stops.length>1?'A: Store pickups \xb7 B: Your delivery pin. Direct lines; not driving directions.':'A: Store pickup \xb7 B: Your delivery pin. Direct line; not driving directions.';
 if(!window.google?.maps){mapNode.hidden=true;caption.textContent='Map unavailable. Your selected delivery pin is still saved.';return;}
 if(!map)map=new google.maps.Map(mapNode,{center:destination,zoom:14,disableDefaultUI:true,gestureHandling:'none',keyboardShortcuts:false,clickableIcons:false,draggable:false,scrollwheel:false,disableDoubleClickZoom:true,mapTypeControl:false,fullscreenControl:false});
 const bounds=new google.maps.LatLngBounds();bounds.extend(destination);
 objects.push(new google.maps.Marker({map,position:destination,label:{text:'B',color:'#fff'},clickable:false}));
 stops.forEach((stop,i)=>{bounds.extend(stop.position);objects.push(new google.maps.Marker({map,position:stop.position,label:{text:stops.length>1?'A'+(i+1):'A',color:'#fff'},clickable:false}));objects.push(new google.maps.Polyline({map,path:[stop.position,destination],strokeColor:'#26372d',strokeOpacity:.8,strokeWeight:2,clickable:false,geodesic:true,icons:[{icon:{path:google.maps.SymbolPath.FORWARD_CLOSED_ARROW,scale:2},offset:'70%'}]}));});
 map.fitBounds(bounds,28);google.maps.event.addListenerOnce(map,'idle',()=>{if(map.getZoom()>16)map.setZoom(16);});
}
new MutationObserver(render).observe(box,{attributes:true,attributeFilter:['style']});box.addEventListener('change',render);render();
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
