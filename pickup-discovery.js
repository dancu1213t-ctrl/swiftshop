(() => {
 'use strict';
 const stores=[
 ['A Mart — Trial Farm',18.10060,-88.56176,'Groceries'],["LJ's Grocery — Trial Farm",18.09573,-88.56401,'Groceries'],["Pete's Juice Place",18.08274,-88.56064,'Food & drinks'],['Agricentro',18.07446,-88.56498,'Shops'],['Friendly Store',18.08072,-88.56101,'Groceries'],["Sonny's Shopping",18.07944,-88.56502,'Groceries'],['Zhi Store',18.08060,-88.56106,'Groceries'],["Ana's Grocery Shop",18.06590,-88.56916,'Groceries'],["Conchi's Groceries",18.07175,-88.56206,'Groceries'],["Andson's Supermarket",18.08089,-88.56861,'Groceries'],["Salazar's Grocery",18.06917,-88.56844,'Groceries'],["Tommy's Store",18.06952,-88.56995,'Groceries'],["Elisa's Mini Shop",18.06707,-88.56927,'Groceries'],["The People's Store",18.08026,-88.55962,'Groceries'],["Jasmin's Grocery Shop & Jane's Store",18.07723,-88.56222,'Groceries'],['La Popular Bakery',18.081093,-88.559710,'Food & drinks'],['Nahil Mayab Restaurant',18.077433,-88.563830,'Food & drinks'],['Cocina Sabor',18.067816,-88.571100,'Food & drinks'],["Casa Ricky's",18.082045,-88.564950,'Food & drinks'],['All Day Supermarket',18.06755,-88.57124,'Groceries'],["Luda's Supermarket",18.09105,-88.56121,'Groceries']
,
["Brew & Browse", 18.0952856, -88.563954, "Food & drinks"],
["123 Supermarket", 18.073595, -88.5637757, "Groceries"],
["Beijing Store", 18.0861519, -88.5668981, "Groceries"],
["Sunny's Store", 18.0788495, -88.5604064, "Groceries"],
["Aaron Super Store", 18.0705599, -88.5697348, "Groceries"],
["Maria's Bakeshop & Coffeehouse", 18.0839014, -88.5618305, "Food & drinks"],
["IceBreak", 18.0800852, -88.5600383, "Food & drinks"],
["Aroma Cafe & Lounge", 18.0809427, -88.566806, "Food & drinks"],
["Natural Balance Cafe", 18.0791407, -88.5628426, "Food & drinks"],
["Frozen Orange Walk", 18.0812944, -88.5592334, "Food & drinks"],
["Buddha Lounge", 18.0766647, -88.5632798, "Food & drinks"],
["The Food Court", 18.0826285, -88.5621817, "Food & drinks"],
["Keyos", 18.0790741, -88.562222, "Food & drinks"],
["D's Cakes", 18.0778744, -88.5614679, "Food & drinks"],
["L'Artisan", 18.0794608, -88.5648083, "Food & drinks"],
["Neeya's Backyaad", 18.0859049, -88.5687213, "Food & drinks"],
["La Jungla Restaurant", 18.0855004, -88.5461431, "Food & drinks"],
["SK Restaurant", 18.0703291, -88.569818, "Food & drinks"],
["Spicy Bites", 18.0768571, -88.5631426, "Food & drinks"],
["Tan's Pizza", 18.0759021, -88.5597238, "Food & drinks"],
["The Dinner House", 18.0921243, -88.5611144, "Food & drinks"],
["Snow Lovers Stop", 18.0693479, -88.5699495, "Food & drinks"],
["Gabys Fast Food", 18.0930875, -88.5627393, "Food & drinks"],
["La Fonda Tacos", 18.0734281, -88.5635165, "Food & drinks"],
["The Juice Bar", 18.0801977, -88.5625901, "Food & drinks"],
["Farmer's Daughters", 18.1031737, -88.5655539, "Food & drinks"],
["Orange Wok Restaurant", 18.0810821, -88.5592091, "Food & drinks"],
["Tipsy Lounge & Pub", 18.0834683, -88.5625538, "Food & drinks"],
["Pocket Mobile", 18.0818298, -88.5621737, "Shops"],
["L & R Imports", 18.0822024, -88.5594003, "Shops"],
["Le Mars Emporium", 18.0826606, -88.5639572, "Shops"],
["R.K. Imports", 18.0808828, -88.5602497, "Shops"],
["Jems Quality Imports", 18.0859894, -88.5655441, "Shops"],
["Harry Shop", 18.0772029, -88.5603669, "Shops"],
["Landys Home Center", 18.0712989, -88.569457, "Shops"],
["San Isidro Tiles Bath & Beyond", 18.0792852, -88.5620529, "Shops"],
["The Tile & Stone Center", 18.0754795, -88.5627809, "Shops"],
["Reimers Feed Mill", 18.0655457, -88.5715792, "Shops"],
["Quality Poultry Products", 18.0798786, -88.5622886, "Shops"],
["Gillett's Fresh and Processed Meats", 18.0791608, -88.5630263, "Shops"],
["Panchita's Fruit and Vegetables Shop", 18.0902906, -88.5663828, "Shops"],
["Shuga City Nutrition Outlet", 18.0842472, -88.5710266, "Shops"],
["Rustic Roof", 18.0701767, -88.5558748, "Shops"],
["The Veg Shop", 18.0744292, -88.5650961, "Shops"],
["Dickerson's Supermarket", 18.0838172, -88.5644051, "Groceries"],
["White House Store", 18.084421, -88.564663, "Groceries"],
["sun luck shop", 18.0723527, -88.5617867, "Groceries"],
["Ring Store", 18.072428, -88.5638598, "Groceries"],
["Gifts & Beyond", 18.085022, -88.5596571, "Shops"]
 ].map(([name,lat,lng,category],id)=>({id,name,lat,lng,category}));
 let selected=null,category='All',query='',overlays=[],card,notice;
 const $=id=>document.getElementById(id);
 function el(tag,text,cls){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;}
 function distance(store){if(!dropoffLatLng)return null;const rad=x=>x*Math.PI/180,a=dropoffLatLng,b=store,dlat=rad(b.lat-a.lat),dlng=rad(b.lng-a.lng);return 6371*2*Math.atan2(Math.sqrt(Math.sin(dlat/2)**2+Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(dlng/2)**2),Math.sqrt(1-(Math.sin(dlat/2)**2+Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(dlng/2)**2)));}
 function matches(s){return (category==='All'||s.category===category)&&s.name.toLowerCase().includes(query.toLowerCase());}
 function showCard(s,focus=false){if(typeof innerWidth==='number'&&innerWidth<=600){const area=card.parentElement;area.classList.add('pd-expanded');const expand=area.querySelector('.pd-expand');expand.textContent='Close expanded map';expand.setAttribute('aria-expanded','true');google.maps.event.trigger(pickupMap,'resize');}selected=s;card.hidden=false;card.replaceChildren();const top=el('div',undefined,'pd-card-top'),copy=el('div');copy.append(el('small',s.category+' · Orange Walk'),el('h3',s.name));const close=el('button','×','pd-close');close.type='button';close.setAttribute('aria-label','Close store details');close.onclick=()=>{card.hidden=true;selected=null;drawPins();};top.append(copy,close);card.append(top);
  const km=distance(s);card.append(el('p',km===null?'Choose your drop-off to see distance.':km.toFixed(1)+' km from your drop-off · straight-line distance','pd-distance'));
  card.append(el('p','Arrange your items with this business, then request a SwiftShop pickup. Confirm your items with the store before requesting pickup.','pd-help'));
  const use=el('button','Choose as pickup →','pd-primary');use.type='button';use.onclick=()=>{if(!pickupMap)return;setPickupPoint('pickup',{lat:s.lat,lng:s.lng},s.name);$('pickupType').value=s.category==='Food & drinks'?'Food':'Item';$('pickupSearch').focus({preventScroll:true});document.querySelector('#pickupOrderBox .pickup-route').scrollIntoView({behavior:'smooth',block:'center'});card.hidden=true;const area=card.parentElement;if(area){area.classList.remove('pd-expanded');const expand=area.querySelector('.pd-expand');expand.textContent='Expand map';expand.setAttribute('aria-expanded','false');google.maps.event.trigger(pickupMap,'resize');}document.querySelector('#pickupOrderBox .pickup-route').scrollIntoView({behavior:'smooth',block:'center'});};card.append(use);drawPins();if(focus)card.focus({preventScroll:true});
 }
 function refresh(){drawPins();const count=stores.filter(matches).length;notice.textContent=count?count+' matching locations · Zoom in to see more store names.':'No matching locations. Try another name or category.';}
 function drawPins(){const occupied=[];for(const o of [...overlays].sort((a,b)=>(b.store.id===selected?.id)-(a.store.id===selected?.id))){if(!o.button)continue;const p=o.getProjection()?.fromLatLngToDivPixel(new google.maps.LatLng(o.store.lat,o.store.lng));if(!p)continue;const width=o.button.offsetWidth||150,left=p.x-width/2,top=p.y-18;const box={left,right:left+width,top,bottom:top+36};const overlap=occupied.some(r=>box.left<r.right+8&&box.right+8>r.left&&box.top<r.bottom+8&&box.bottom+8>r.top);const visible=matches(o.store)&&(!overlap||o.store.id===selected?.id);o.button.style.display=visible?'block':'none';o.button.style.left=p.x+'px';o.button.style.top=p.y+'px';o.button.classList.toggle('is-selected',o.store.id===selected?.id);if(visible)occupied.push(box);}}
 function attachPins(){if(!pickupMap||overlays.length)return;class StorePill extends google.maps.OverlayView{constructor(store){super();this.store=store;this.setMap(pickupMap);}onAdd(){this.button=el('button',this.store.name,'pd-map-pill');this.button.type='button';this.button.setAttribute('aria-label','View '+this.store.name);this.button.onclick=()=>showCard(this.store,true);google.maps.OverlayView.preventMapHitsAndGesturesFrom(this.button);this.getPanes().floatPane.append(this.button);}draw(){drawPins();}onRemove(){this.button?.remove();}}overlays=stores.map(s=>new StorePill(s));google.maps.event.addListener(pickupMap,'idle',drawPins);pickupMap.setOptions({styles:[{featureType:'all',elementType:'geometry',stylers:[{color:'#eeeeec'}]},{featureType:'all',elementType:'labels.text.fill',stylers:[{color:'#666666'}]},{featureType:'all',elementType:'labels.text.stroke',stylers:[{color:'#ffffff'}]},{featureType:'poi',stylers:[{visibility:'off'}]},{featureType:'transit',stylers:[{visibility:'off'}]},{featureType:'road',elementType:'geometry',stylers:[{color:'#ffffff'}]},{featureType:'road.highway',elementType:'geometry',stylers:[{color:'#dadad7'}]},{featureType:'water',elementType:'geometry',stylers:[{color:'#ccd9df'}]},{featureType:'landscape.natural',elementType:'geometry',stylers:[{color:'#e6e8e3'}]}],fullscreenControl:false,gestureHandling:'greedy'});refresh();}
 function setup(){const page=$('pickupOrderBox');if(!page)return;page.classList.add('pd-page');const header=page.querySelector('.pickup-heading');header.querySelector('h2').textContent='Your next pickup, nearby.';header.querySelector('p').textContent='Find a local business. Choose A → B. We’ll handle the pickup.';
  const discovery=el('section',undefined,'pd-discovery');discovery.setAttribute('aria-label','Find a pickup business');const bar=el('div',undefined,'pd-toolbar');const input=el('input');input.type='search';input.placeholder='Search local businesses';input.setAttribute('aria-label','Search pickup businesses');input.oninput=()=>{query=input.value;refresh();const found=stores.filter(matches);if(pickupMap&&found.length){const bounds=new google.maps.LatLngBounds();found.forEach(s=>bounds.extend({lat:s.lat,lng:s.lng}));pickupMap.fitBounds(bounds,60);if(found.length===1)pickupMap.setZoom(17);}};bar.append(input);const all=el('button','Show all locations','pd-secondary');all.type='button';all.onclick=()=>{if(!pickupMap){notice.textContent='Map is loading. Please try again shortly.';return;}const bounds=new google.maps.LatLngBounds();stores.filter(matches).forEach(s=>bounds.extend({lat:s.lat,lng:s.lng}));if(stores.some(matches))pickupMap.fitBounds(bounds,48);};bar.append(all);discovery.append(bar);const chips=el('div',undefined,'pd-chips');for(const name of ['All','Groceries','Food & drinks','Shops']){const b=el('button',name);b.type='button';b.setAttribute('aria-pressed',String(name===category));b.onclick=()=>{category=name;for(const c of chips.children)c.setAttribute('aria-pressed',String(c===b));refresh();};chips.append(b);}discovery.append(chips);header.after(discovery);
  const map=$('pickupMap'),mapArea=el('div',undefined,'pd-map-area');map.before(mapArea);mapArea.append(map);notice=el('p','Loading the map… Browse the businesses below while it connects.','pd-map-notice');notice.setAttribute('role','status');mapArea.append(notice);card=el('section',undefined,'pd-store-card');card.hidden=true;card.tabIndex=-1;card.setAttribute('aria-label','Selected pickup business');mapArea.append(card);const expand=el('button','Expand map','pd-expand');expand.type='button';expand.setAttribute('aria-label','Expand pickup map');expand.onclick=()=>{const full=mapArea.classList.toggle('pd-expanded');expand.textContent=full?'Close expanded map':'Expand map';expand.setAttribute('aria-expanded',String(full));google.maps.event.trigger(pickupMap,'resize');};mapArea.append(expand);mapArea.onkeydown=e=>{if(e.key==='Escape'){mapArea.classList.remove('pd-expanded');expand.textContent='Expand map';expand.setAttribute('aria-expanded','false');}};
  refresh();
  const init=window.initPickupMap;window.initPickupMap=function(...args){try{const result=init.apply(this,args);attachPins();return result;}catch(e){notice.textContent='The map could not load. Please retry your connection.';console.error('Pickup map',e);}};
  const setPoint=window.setPickupPoint;window.setPickupPoint=function(...args){const result=setPoint.apply(this,args);refresh();if(selected)showCard(selected);return result;};
  if(pickupMap)attachPins();
 }
 document.readyState==='loading'?document.addEventListener('DOMContentLoaded',setup,{once:true}):setup();
})();
