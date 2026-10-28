/* Shared pickup rendering for cart previews and existing checkout routes. */
(()=>{'use strict';const valid=p=>p&&typeof p.lat==='number'&&typeof p.lng==='number'&&Number.isFinite(p.lat)&&Number.isFinite(p.lng)&&Math.abs(p.lat)<=90&&Math.abs(p.lng)<=180;
function point(value){if(typeof value!=='string')return null;const p=value.split(',').map(Number);return p.length===2&&p.every(Number.isFinite)&&Math.abs(p[0])<=90&&Math.abs(p[1])<=180?{lat:p[0],lng:p[1]}:null;}
function points(items,fallback){const result=[],seen=new Set();for(const item of Object.values(items||{})){if(!(item.q>0))continue;const saved=item.offer_id&&valid(item.offer_pickup)?item.offer_pickup:null,position=saved||point(fallback(item.cat));if(!position)continue;const key=position.lat+','+position.lng;if(seen.has(key))continue;seen.add(key);result.push({category:saved?.name||item.cat,position:{lat:position.lat,lng:position.lng}});}return result;}
window.SwiftOfferPickups={points,routes(items,destination){return points(items,c=>storePickupCoordinates(c)).map(s=>'https://www.google.com/maps/dir/?api=1&origin='+s.position.lat+','+s.position.lng+'&destination='+encodeURIComponent(destination));}};
})();
