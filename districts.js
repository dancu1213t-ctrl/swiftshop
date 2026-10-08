(() => {
  'use strict';
  const names=['Belize','Cayo','Corozal','Orange Walk','Stann Creek','Toledo'];
  const state={district:localStorage.getItem('swift.district')||'Orange Walk',stores:[],loaded:false,enabled:false,pin:null};
  if(!names.includes(state.district))state.district='Orange Walk';
  let pending=null,version=0;
  const client=()=>customerDataClient;
  async function rpc(name,args){const {data,error}=await client().rpc(name,args).abortSignal(AbortSignal.timeout(15000));if(error)throw error;return data;}
  const allowed=category=>state.loaded&&state.enabled&&state.stores.some(s=>s.category===category);
  async function load(pin=state.pin){
    const own=++version;
    state.loaded=false;
    const result=await rpc('swift_district_catalogue',{p_district:state.district,p_lat:pin?.lat??null,p_lng:pin?.lng??null});
    if(own!==version)return state;
    state.stores=result.stores||[];state.enabled=result.enabled;state.loaded=true;state.pin=pin;
    draw();return state;
  }
  function ensure(){if(state.loaded)return Promise.resolve(state);if(pending)return pending;pending=load().finally(()=>pending=null);return pending;}
  function message(text){const n=document.getElementById('districtNotice');if(n)n.textContent=text;}
  async function change(district){
    if(!names.includes(district))throw Error('Choose a Belize district.');
    if(typeof cart!=='undefined'&&Object.keys(cart).length&&district!==state.district){if(!confirm('Changing district clears your current cart. Continue?'))return false;cart={};total=0;update();updateCartBubble();}
    state.district=district;state.pin=null;state.loaded=false;localStorage.setItem('swift.district',district);window.lastCartCoords='';
    message('Loading stores in '+district+'…');
    await load(null);await refreshProducts();window.dispatchEvent(new CustomEvent('swift-district-changed',{detail:{district}}));return true;
  }
  async function refreshProducts(){if(typeof getProducts==='function'){allProducts=await getProducts();if(typeof render==='function')await render();}}
  async function setPin(lat,lng){
    if(!Number.isFinite(lat)||!Number.isFinite(lng))throw Error('Choose a valid map pin.');
    const district=await rpc('swift_district_at',{p_lat:lat,p_lng:lng});if(!district)throw Error('Choose a location within Belize.');
    if(district!==state.district&&!await change(district))return false;
    await load({lat,lng});window.lastCartCoords=lat+','+lng;await refreshProducts();
    document.getElementById('districtSelect').value=district;
    message('Delivering to '+district+' · '+lat.toFixed(5)+', '+lng.toFixed(5));return true;
  }
  function draw(){
    const select=document.getElementById('districtSelect');if(select)select.value=state.district;
    for(const n of document.querySelectorAll('[data-store-category]'))n.hidden=!allowed(n.dataset.storeCategory);
    const list=document.getElementById('districtStoreList');if(!list)return;
    list.replaceChildren();
    for(const s of state.stores){const b=document.createElement('button');b.type='button';b.className='district-store';
      const name=document.createElement('strong');name.textContent=s.store_name||s.category;
      const note=document.createElement('small');note.textContent=(s.is_open==='yes'?'Open':'Closed')+(s.distance_km!=null?' · '+Number(s.distance_km).toFixed(1)+' km away':' · '+state.district);
      b.append(name,note);b.onclick=()=>window.openMerchantStore?.(s.category);list.append(b);
    }
    message(!state.enabled?'Service is paused in '+state.district:state.stores.length?state.stores.length+' stores in '+state.district+'. Set your delivery pin to check coverage.':'No approved stores here yet. Check back soon.');
  }
  async function validate(snapshot){
    await ensure();const raw=String(snapshot.customer_location||'');const match=raw.match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
    if(!match)throw Error('Set an exact delivery pin using Deliver to. For gifts, enter the recipient’s coordinates.');
    const district=await rpc('swift_district_at',{p_lat:Number(match[1]),p_lng:Number(match[2])});
    if(district!==state.district)throw Error('The delivery pin is outside your selected district. Update Deliver to first.');
    if(snapshot.items.some(i=>!allowed(i.category)))throw Error('Remove items from stores outside this district before ordering.');
    snapshot.district=district;return snapshot;
  }
  window.SwiftDistrict={state,names,ensure,allowed,change,setPin,validate};
  document.addEventListener('DOMContentLoaded',async()=>{
    const section=document.createElement('section');section.id='districtDelivery';section.className='district-delivery';
    section.innerHTML='<div class="district-delivery-top"><label>Deliver to<select id="districtSelect" aria-label="Delivery district"></select></label><button type="button" id="districtGps">Use my location</button><button type="button" id="districtPin">Set map pin</button><button type="button" id="storeApplyOpen">List your store</button></div><p id="districtNotice" role="status">Loading your district…</p><div id="districtStoreList" class="district-store-list"></div>';
    const target=document.querySelector('#appScreen .store-navigation-wrapper');if(target)target.before(section);else document.getElementById('appScreen')?.prepend(section);
    const select=document.getElementById('districtSelect');for(const name of names)select.add(new Option(name,name));select.value=state.district;
    select.onchange=async()=>{select.disabled=true;try{await change(select.value);}catch(e){message(e.message);}finally{select.disabled=false;select.value=state.district;}};
    document.getElementById('districtGps').onclick=()=>{message('Locating your delivery pin…');navigator.geolocation.getCurrentPosition(p=>setPin(p.coords.latitude,p.coords.longitude).catch(e=>message(e.message)),()=>message('Location could not be read. Use Set map pin.'),{enableHighAccuracy:true,timeout:15000});};
    const dialog=document.createElement('dialog');dialog.id='districtPinDialog';dialog.innerHTML='<form id="districtPinForm"><h2>Your delivery pin</h2><p>Use the exact latitude and longitude from your map pin.</p><label>Latitude<input name="lat" type="number" step="any" min="-90" max="90" required></label><label>Longitude<input name="lng" type="number" step="any" min="-180" max="180" required></label><p role="alert"></p><div><button type="button" data-close>Cancel</button><button type="submit">Save delivery pin</button></div></form>';document.body.append(dialog);
    const mapBox=document.createElement('div');mapBox.style.cssText='height:280px;width:100%;border-radius:12px;margin:12px 0';mapBox.setAttribute('aria-label','Choose your delivery location on the map');dialog.querySelector('h2').after(mapBox);
    let pinMap,pinMarker;const centres={'Orange Walk':{lat:18.078,lng:-88.563},Belize:{lat:17.504,lng:-88.196},Corozal:{lat:18.394,lng:-88.388},Cayo:{lat:17.251,lng:-88.759},'Stann Creek':{lat:16.97,lng:-88.23},Toledo:{lat:16.2,lng:-88.9}};
    function showPinMap(){if(!window.google?.maps){mapBox.textContent='Map unavailable. You can enter coordinates below.';return;}const position=state.pin||centres[state.district];if(!pinMap){pinMap=new google.maps.Map(mapBox,{center:position,zoom:14,streetViewControl:false,mapTypeControl:false});pinMarker=new google.maps.Marker({map:pinMap,position,draggable:true});const choose=point=>{pinMarker.setPosition(point);dialog.querySelector('[name=lat]').value=point.lat();dialog.querySelector('[name=lng]').value=point.lng();};pinMap.addListener('click',e=>choose(e.latLng));pinMarker.addListener('dragend',e=>choose(e.latLng));}else{pinMap.setCenter(position);pinMarker.setPosition(position);}dialog.querySelector('[name=lat]').value=position.lat;dialog.querySelector('[name=lng]').value=position.lng;}
    document.getElementById('districtPin').onclick=()=>{dialog.showModal();showPinMap();};dialog.querySelector('[data-close]').onclick=()=>dialog.close();
    dialog.querySelector('form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget,b=f.querySelector('[type=submit]');b.disabled=true;try{if(await setPin(Number(f.elements.lat.value),Number(f.elements.lng.value)))dialog.close();}catch(err){f.querySelector('[role=alert]').textContent=err.message;}finally{b.disabled=false;}};
    const application=document.createElement('dialog');application.id='districtStoreApply';application.innerHTML='<form><h2>List your store on SwiftShop</h2><p>Sign in with your verified customer email first. Your store appears after SwiftShop approves it.</p><label>Store name<input name="store" maxlength="100" required></label><label>District<select name="district" required></select></label><label>Address<input name="address" maxlength="300" required></label><label>Contact phone<input name="phone" type="tel" minlength="7" maxlength="30" required></label><label>Store latitude<input name="lat" type="number" step="any" required></label><label>Store longitude<input name="lng" type="number" step="any" required></label><label>Delivery radius (km)<input name="radius" type="number" min="0.1" max="200" step="0.1" value="5" required></label><p role="alert"></p><div><button type="button" data-close>Cancel</button><button type="submit">Submit for approval</button></div></form>';document.body.append(application);
    for(const name of names)application.querySelector('select').add(new Option(name,name));document.getElementById('storeApplyOpen').onclick=()=>{application.querySelector('select').value=state.district;application.showModal();};application.querySelector('[data-close]').onclick=()=>application.close();
    application.querySelector('form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget,b=f.querySelector('[type=submit]'),notice=f.querySelector('[role=alert]');b.disabled=true;try{await rpc('swift_store_apply',{p_name:f.elements.store.value,p_district:f.elements.district.value,p_address:f.elements.address.value,p_phone:f.elements.phone.value,p_lat:Number(f.elements.lat.value),p_lng:Number(f.elements.lng.value),p_radius:Number(f.elements.radius.value)});f.reset();notice.textContent='Application received. SwiftShop will review your store.';}catch(err){notice.textContent=err.message;}finally{b.disabled=false;}};
    const open=window.openMerchantStore;if(open)window.openMerchantStore=async function(category){await ensure();if(!allowed(category)){message('This store does not serve your selected district.');return;}return open.apply(this,arguments);};
    const add=window.add;if(add)window.add=function(...args){if(!allowed(cat)){message('Choose a store in your delivery district.');return;}return add.apply(this,args);};
    try{await ensure();draw();}catch(e){message('Stores could not load: '+e.message);}
  });
})();
