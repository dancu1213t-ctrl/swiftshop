(()=>{'use strict';
const point=value=>{if(typeof value!=='string'||!/^\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*$/.test(value))return null;const [lat,lng]=value.split(',').map(Number);return Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)<=90&&Math.abs(lng)<=180?{lat,lng}:null;};
// Quadratic arc in Mercator space; endpoints stay at the saved pins.
function routeArc(a,b){
 const project=p=>({x:p.lng/360,y:Math.log(Math.tan(Math.PI/4+Math.max(-85,Math.min(85,p.lat))*Math.PI/360))/(2*Math.PI)});
 const inverse=p=>({lng:p.x*360,lat:(2*Math.atan(Math.exp(p.y*2*Math.PI))-Math.PI/2)*180/Math.PI});
 const start=project(a),end=project(b);if(end.x-start.x>.5)end.x-=1;if(end.x-start.x<-.5)end.x+=1;
 const dx=end.x-start.x,dy=end.y-start.y,control={x:(start.x+end.x)/2-dy*.26,y:(start.y+end.y)/2+dx*.26};
 const path=Array.from({length:49},(_,i)=>{const t=i/48,u=1-t;return inverse({x:u*u*start.x+2*u*t*control.x+t*t*end.x,y:u*u*start.y+2*u*t*control.y+t*t*end.y});});
 path[0]=a;path[path.length-1]=b;return path;
}
function pickupPoint(category){
 if(typeof storePickupCoordinates==='function')return point(storePickupCoordinates(category));
 const rows=window.SwiftStoreInfo?.rows;
 const row=rows&&[...rows.values()].find(r=>String(r.category||'').trim().toUpperCase()===String(category).trim().toUpperCase());
 const saved=row?.latitude!=null&&row?.longitude!=null?point(String(row.latitude)+','+String(row.longitude)):null;
 return saved||point(typeof storeLocations==='undefined'?null:storeLocations[category]);
}
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
let map,objects=[],fingerprint='',routeBounds,frameRequest;
function frame(){cancelAnimationFrame(frameRequest);frameRequest=requestAnimationFrame(()=>{if(!map||!routeBounds||!mapNode.clientWidth||!mapNode.clientHeight||box.style.display==='none')return;google.maps.event.trigger(map,'resize');map.fitBounds(routeBounds,{top:64,right:48,bottom:44,left:48});});}
new ResizeObserver(frame).observe(mapNode);
function render(){if(box.style.display==='none'||!box.style.display)return;area();document.getElementById('selectedTipAmount').value='0';
 const destination=gift.checked?point(document.getElementById('giftAddress').value):point(window.lastCartCoords);
 const categories=[...new Set(Object.values(typeof cart==='undefined'?{}:cart).filter(v=>v.q>0).map(v=>String(v.cat||'').toUpperCase()))];
 const stops=window.SwiftOfferPickups?window.SwiftOfferPickups.points(typeof cart==='undefined'?{}:cart,c=>{const p=pickupPoint(c);return p?p.lat+','+p.lng:'';}):categories.map(category=>({category,position:pickupPoint(category)})).filter(v=>v.position);
 const key=JSON.stringify([destination,stops,gift.checked]);if(key===fingerprint&&map){frame();return;}fingerprint=key;
 objects.forEach(v=>v.setMap(null));objects=[];routeBounds=null;
 if(!destination||!stops.length){mapNode.hidden=true;caption.textContent=gift.checked?'Recipient\u2019s address will be confirmed by Dispatch.':'Select your delivery pin in the previous step to preview the route.';return;}
 mapNode.hidden=false;caption.textContent=stops.length>1?'A: Store pickups  \u00b7  B: Delivery':'A: Store pickup  \u00b7  B: Delivery';
 if(!window.google?.maps){mapNode.hidden=true;caption.textContent='Map unavailable. Your selected delivery pin is still saved.';return;}
 if(!map)map=new google.maps.Map(mapNode,{center:destination,zoom:14,maxZoom:16,styles:[{featureType:'poi',stylers:[{visibility:'off'}]},{featureType:'transit',stylers:[{visibility:'off'}]}],disableDefaultUI:true,gestureHandling:'none',keyboardShortcuts:false,clickableIcons:false,draggable:false,scrollwheel:false,disableDoubleClickZoom:true,mapTypeControl:false,fullscreenControl:false});
 const bounds=new google.maps.LatLngBounds();bounds.extend(destination);
 objects.push(new google.maps.Marker({map,position:destination,label:{text:'B',color:'#fff'},clickable:false}));
 stops.forEach((stop,i)=>{
  const path=routeArc(stop.position,destination);path.forEach(p=>bounds.extend(p));
  objects.push(new google.maps.Marker({map,position:stop.position,label:{text:stops.length>1?'A'+(i+1):'A',color:'#fff'},clickable:false}));
  objects.push(new google.maps.Polyline({map,path,strokeColor:'#25372d',strokeOpacity:.9,strokeWeight:3,clickable:false,geodesic:false}));
 });
 routeBounds=bounds;frame();
}
new MutationObserver(render).observe(box,{attributes:true,attributeFilter:['style']});box.addEventListener('change',render);render();
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
