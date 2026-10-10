(() => {
  const messages = {
    sent: ['Order sent', 'Your request is waiting for SwiftShop confirmation.'],
    accepted: ['Order accepted', 'SwiftShop has confirmed your request.'],
    preparing: ['Preparing your order', 'Your order is being prepared.'],
    finding_runner: ['Finding your runner', 'We’re arranging a runner for your delivery.'],
    runner_assigned: ['Runner assigned', 'Your runner is getting ready.'],
    on_the_way: ['Your order is on the way', 'Your runner has started the delivery.'],
    delivered: ['Delivered', 'Your delivery is complete.']
  };
  const rideMessages = {
 requested:['Finding your driver','Your SwiftRide request has been sent.'],
 accepted:['Driver on the way','Your driver accepted your SwiftRide request.'],
 arrived:['Your driver has arrived','Your SwiftRide driver is at the pickup point.'],
 in_progress:['Ride started','Your SwiftRide trip is underway.'],
 completed:['Ride completed','You have reached your destination.'],
 cancelled:['Ride cancelled','Your SwiftRide request has been cancelled.']
};
  const scope = () => localStorage.getItem('userPhone') || 'guest';
  const storageKey = () => 'swiftshop.notifications.v1:' + scope();
  const preferenceKey = () => 'swiftshop.notification-preference:' + scope();
  const read = () => { try { return JSON.parse(localStorage.getItem(storageKey()) || '[]'); } catch { return []; } };
  const write = rows => { try { localStorage.setItem(storageKey(), JSON.stringify(rows.slice(0,100))); } catch {} };
  const bell = document.createElement('button'); bell.id = 'deliveryNotificationBell'; bell.type = 'button'; bell.setAttribute('aria-label', 'Notifications');
  bell.innerHTML = '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9"/><path d="M10 21h4"/></svg>';
  const badge = document.createElement('span'); badge.className='dn-badge'; badge.setAttribute('aria-hidden','true'); bell.append(badge);
  const panel = document.createElement('dialog'); panel.id = 'deliveryNotificationInbox';
  panel.innerHTML = '<header><h2>Notifications</h2><button type="button" data-close aria-label="Close notifications">✕</button></header><div class="dn-settings"><button type="button" data-enable>Enable notifications</button><button type="button" data-disable>Turn off notifications</button><p data-status role="status"></p></div><button type="button" data-read-all>Mark all as read</button><div data-list></div>';
  const header = document.getElementById('appScreen')?.querySelector('.header');
  if(header) header.append(bell);
  document.body.append(panel);
  const promotionPreference=()=> 'swiftshop.promotion-push:'+scope();
  const promoLabel=document.createElement('label');promoLabel.className='dn-promotion-preference';const promoOpt=document.createElement('input');promoOpt.type='checkbox';promoOpt.onchange=()=>{localStorage.setItem(promotionPreference(),promoOpt.checked?'on':'off');status(promoOpt.checked?'Promotional phone alerts selected. Enable notifications above if needed.':'Promotional phone alerts turned off.');sync();};const promoText=document.createElement('span');promoText.textContent='Offers and promotions on this phone (optional)';promoLabel.append(promoOpt,promoText);panel.querySelector('.dn-settings').append(promoLabel);
  let deviceToken = null, syncing = false, syncAgain = false, registeredScope = '', pendingOrder = null;
  let mutation = Promise.resolve(),renderedInbox='';
  function mutate(run) { const next = mutation.catch(()=>{}).then(run); mutation=next; return next; }
  function identity() {
    const key = 'swiftshop.push-install.v1';
    let saved; try { saved = JSON.parse(localStorage.getItem(key) || 'null'); } catch {}
    if (!saved) { saved = { id: crypto.randomUUID(), secret: crypto.randomUUID() }; localStorage.setItem(key, JSON.stringify(saved)); }
    return saved;
  }
  function orders() { try { return JSON.parse(localStorage.getItem('swiftshop.live-orders.v1:' + scope()) || '[]'); } catch { return []; } }
  function active() { const screen = document.getElementById('appScreen'); return !!screen && getComputedStyle(screen).display !== 'none'; }
  function render() {
    bell.hidden = !active();promoLabel.hidden=!window.SWIFTSHOP_PROMOTIONS_ENABLED;promoOpt.checked=localStorage.getItem(promotionPreference())==='on';
    const rows = read(); const unread = rows.filter(r => !r.read).length;
    badge.hidden = !unread; badge.textContent = unread > 99 ? '99+' : String(unread);
    bell.setAttribute('aria-label',unread ? `Notifications, ${unread} unread` : 'Notifications');
    panel.querySelector('[data-read-all]').hidden=!unread;
    const host = panel.querySelector('[data-list]');
    const signature=JSON.stringify([scope(),rows]);
    if(signature!==renderedInbox){renderedInbox=signature;host.replaceChildren();
    if (!rows.length) { const text = document.createElement('p'); text.textContent = 'Your order and ride notifications will appear here.'; host.append(text); }
    for (const row of rows) {
      const button = document.createElement('button'); button.type = 'button'; button.className = row.read ? 'dn-item' : 'dn-item dn-unread';button.setAttribute('aria-label',(row.read?'':'Unread: ')+row.title);
      const title = document.createElement('strong'); title.textContent = row.title;
      const body = document.createElement('span'); body.textContent = row.body;
      const time = document.createElement('small'); time.textContent = `${row.kind==='promotion'?'Promotion':(row.kind==='ride'?'Ride':'Order')+' '+row.orderId.slice(0,8).toUpperCase()} · ${new Date(row.time).toLocaleString()}`;
      button.append(title, body, time); button.onclick = async () => {write(read().map(item=>item.id===row.id?{...item,read:true}:item));render(); await openResource({kind:row.kind,promotion_id:row.orderId,ride_id:row.orderId,order_id:row.orderId}); }; host.append(button);
    }
    }
    panel.querySelector('[data-enable]').hidden = !window.SwiftPush;
    panel.querySelector('[data-enable]').textContent=window.SwiftPush?.web?'Enable phone notifications':'Enable notifications';
    panel.querySelector('[data-disable]').hidden = !window.SwiftPush;
  }
  function record(orderId, phase, announce = true, eventId = null, createdAt = null, kind = 'delivery') {
    const catalogue=kind==='ride'?rideMessages:messages;
    if (!catalogue[phase] || !orderId || !active()) return;
    const id = eventId || `${kind==='ride'?'ride:':''}${orderId}:${phase}`; const rows = read();
    if (rows.some(row => row.id === id || (!eventId && row.orderId === orderId && row.phase === phase && (row.kind||'delivery')===kind))) return;
    const local = eventId && rows.find(row => row.id === `${kind==='ride'?'ride:':''}${orderId}:${phase}`);
    if (local) { local.id = eventId; if (createdAt) local.time = createdAt; write(rows); render(); return; }
    const [title, body] = catalogue[phase]; rows.unshift({ id, kind, orderId, phase, title, body, time: createdAt || new Date().toISOString(), read: false }); rows.sort((a,b)=>Date.parse(b.time)-Date.parse(a.time)); write(rows); render();
  }
  async function sync() {
    if (syncing) { syncAgain=true; return; }
    if (!active() || !window.SWIFTSHOP_NOTIFICATION_BACKEND_ENABLED) return;
    syncing = true; const account = scope();
    try {
      const install = identity();
      let subscribed=0;
      if(window.SWIFTSHOP_PROMOTIONS_ENABLED&&deviceToken&&localStorage.getItem(preferenceKey())==='on'){const token=deviceToken;const {error}=await mutate(()=>scope()===account&&active()&&localStorage.getItem(preferenceKey())==='on'?supabaseClient.rpc('register_promotion_device',{p_install_id:install.id,p_install_secret:install.secret,p_platform:token.platform,p_device_token:token.token,p_enabled:localStorage.getItem(promotionPreference())==='on'}).abortSignal(AbortSignal.timeout(10000)):{error:null});if(error)throw error;}
      window.SwiftPromotions?.refresh();
      for (const order of orders().filter(o=>o.registered).slice(0,20)) {
        if (scope() !== account || !active()) break;
        if (deviceToken && localStorage.getItem(preferenceKey()) === 'on') {
          const token = deviceToken;
          const {error} = await mutate(() => {
            if(scope()!==account || !active() || localStorage.getItem(preferenceKey())!=='on') return {error:null};
            return supabaseClient.rpc('register_delivery_device', {p_install_id:install.id,p_install_secret:install.secret,p_order_id:order.id,p_access_token:order.token,p_platform:token.platform,p_device_token:token.liveNotifications ? 'swiftshop-live-v1:'+token.token : token.token}).abortSignal(AbortSignal.timeout(10000));
          });
          if (error) throw error;
          subscribed++;
        }
        if(document.hidden) continue;
        const {data,error} = await supabaseClient.rpc('get_delivery_notifications', {p_order_id:order.id,p_access_token:order.token}).abortSignal(AbortSignal.timeout(10000));
        if (error) throw error;
        if (scope() !== account || !active()) break;
        for (const event of (data || []).slice().reverse()) record(order.id,event.phase,false,event.id,event.created_at);
      }
      if(window.SWIFTSHOP_RIDE_NOTIFICATION_BACKEND_ENABLED && window.SwiftRideNotificationBridge) for(const id of rides()) {
        if(scope()!==account || !active())break;
        if(deviceToken && localStorage.getItem(preferenceKey())==='on') {
          const token=deviceToken;
          await mutate(()=>scope()===account && active() && localStorage.getItem(preferenceKey())==='on' ? window.SwiftRideNotificationBridge.request('register_ride_device',{p_install_id:install.id,p_install_secret:install.secret,p_ride_id:id,p_platform:token.platform,p_device_token:token.liveNotifications ? 'swiftshop-live-v1:'+token.token : token.token}) : Promise.resolve());
          subscribed++;
        }
        if(document.hidden)continue;
        const events=await window.SwiftRideNotificationBridge.request('get_ride_notifications',{p_ride_id:id});
        if(scope()!==account || !active())break;
        for(const event of (events||[]).slice().reverse())record(id,event.phase,false,event.id,event.created_at,'ride');
      }
      if (deviceToken && localStorage.getItem(preferenceKey()) === 'on') status(subscribed ? 'Notifications enabled for your orders and rides.' : 'Permission enabled. Place an order to receive delivery notifications.');
    } catch (error) { if (deviceToken) status('Could not connect notifications. '+(error.message || 'Please try again.')); }
    finally { syncing = false; if(syncAgain) {syncAgain=false;queueMicrotask(sync);} }
  }
  async function revoke() {
    const install = identity();
    const {error} = await mutate(() => supabaseClient.rpc('revoke_delivery_device',{p_install_id:install.id,p_install_secret:install.secret}).abortSignal(AbortSignal.timeout(10000)));
    if (error) throw error;
  }
  const rideKey=()=> 'swiftshop.notification-rides:'+scope();
  const rides=()=>{try{return JSON.parse(localStorage.getItem(rideKey())||'[]');}catch{return [];}};
  window.SwiftRideNotifications={record(id,phase){const ids=rides();if(!ids.includes(id))localStorage.setItem(rideKey(),JSON.stringify([id,...ids].slice(0,20)));record(id,phase,true,null,null,'ride');sync();}};
  let openingResource = false;
  async function openResource(data){
    if(openingResource)return;
    openingResource=true;
    try{
      // Close the existing modal before opening another: avoid overlapping modal inertness.
      if(panel.open)panel.close();
      window.SwiftNavigation?.refresh?.();
      await new Promise(resolve=>requestAnimationFrame(resolve));
      if(data.kind==='promotion'){
        if(!window.SwiftPromotions||await window.SwiftPromotions.open(data.promotion_id)===false)throw Error('This promotion is no longer available.');
      }else if(data.kind==='ride'){
        if(!window.SwiftRideNotificationBridge||await window.SwiftRideNotificationBridge.open(data.ride_id)===false)throw Error('Open SwiftRide to reconnect, or contact support with the ride reference.');
      }else{
        if(!orders().some(order=>order.id===data.order_id)||!window.SwiftLive)throw Error('This order is no longer saved on this device. Contact support with the order reference.');
        window.SwiftLive.openOrder(data.order_id);
      }
      window.SwiftNavigation?.refresh?.();
    }catch(error){openInbox();status(error.message);}
    finally{openingResource=false;}
  }
  window.SwiftDeliveryNotifications = { record, sync, promotions(promos){const liveIds=new Set(promos.map(p=>'promotion:'+p.id));const rows=read().filter(row=>row.kind!=='promotion'||liveIds.has(row.id));for(const p of promos){const id='promotion:'+p.id;if(!rows.some(row=>row.id===id))rows.push({id,kind:'promotion',orderId:p.id,title:p.title,body:p.body,time:p.published_at,read:false});}rows.sort((a,b)=>Date.parse(b.time)-Date.parse(a.time));write(rows);render();} };
  function openInbox(){render();if(!panel.open)panel.showModal();sync();}
  bell.onclick=openInbox;
  window.SwiftDeliveryNotifications.open=openInbox;
  panel.querySelector('[data-read-all]').onclick=()=>{write(read().map(row=>({...row,read:true})));render();};
  panel.querySelector('[data-close]').onclick = () => panel.close();
  const status = text => { panel.querySelector('[data-status]').textContent = text; };
  panel.querySelector('[data-enable]').onclick = async () => { try { if (!window.SWIFTSHOP_NOTIFICATION_BACKEND_ENABLED) throw Error('Delivery notification setup is not complete yet.'); const permission=window.SwiftPush?.web?window.SwiftPush.requestPermission():null; if(permission)await permission; if(localStorage.getItem('swiftshop.push-revoke-pending')) {await revoke();localStorage.removeItem('swiftshop.push-revoke-pending');} registeredScope=scope(); localStorage.setItem(preferenceKey(), 'on'); status('Requesting notification permission…'); await window.SwiftPush.enable(); status('Registering delivery updates…'); await sync(); } catch (e) { localStorage.setItem(preferenceKey(), 'off'); status(e.message); } };
  panel.querySelector('[data-disable]').onclick = async () => { localStorage.setItem(preferenceKey(), 'off'); deviceToken=null; try { await window.SwiftPush.disable(); if(window.SWIFTSHOP_NOTIFICATION_BACKEND_ENABLED) await revoke(); status('Phone notifications turned off on this device.'); } catch { status('Phone alerts stopped locally. Open the app with internet access to finish removing its server subscription.'); localStorage.setItem('swiftshop.push-revoke-pending','true'); } };
  window.addEventListener('swift-push-token', async e => { if(scope()!==registeredScope || !active() || localStorage.getItem(preferenceKey())!=='on') { window.SwiftPush.disable().catch(()=>{}); return; } deviceToken=e.detail; await sync(); });
  window.addEventListener('swift-push-error', e => status(e.detail.message));
  function known(data) { if(data.kind==='promotion')return !!data.promotion_id; if(data.kind==='ride')return rides().includes(data.ride_id); try { return JSON.parse(localStorage.getItem('swiftshop.live-orders.v1:' + scope()) || '[]').some(r => r.id === data.order_id); } catch { return false; } }
  window.addEventListener('swift-delivery-push', e => { const data = e.detail.data || {}; if(data.kind==='promotion'){window.SwiftPromotions?.refresh(true);return;} if (known(data)) { record(data.ride_id||data.order_id, data.phase, true, data.event_id,null,data.kind||'delivery'); sync(); } });
  window.addEventListener('swift-delivery-push-open', e => { const data = e.detail.data || {}; if(data.kind==='promotion'){if(active())openResource(data);else pendingOrder=data;return;} if (known(data)) { if(active()) { record(data.ride_id||data.order_id, data.phase, false, data.event_id,null,data.kind||'delivery'); openResource(data); } else pendingOrder=data; } });
  const screen = document.getElementById('appScreen');
  if (screen) new MutationObserver(() => { render(); if (!active()) { panel.close(); } else { if(pendingOrder && known(pendingOrder)) {openResource(pendingOrder);pendingOrder=null;} resume(); } }).observe(screen, { attributes: true, attributeFilter: ['style','class'] });
  const logout=window.handleLogout;
  if(logout) window.handleLogout=async function(...args) { localStorage.setItem(preferenceKey(),'off'); deviceToken=null; if(window.SwiftPush) { try { await window.SwiftPush.disable(); if(window.SWIFTSHOP_NOTIFICATION_BACKEND_ENABLED) await revoke(); } catch { localStorage.setItem('swiftshop.push-revoke-pending','true'); } } return logout.apply(this,args); };
  async function resume() {
    if(!active()) return;
    if(window.SWIFTSHOP_NOTIFICATION_BACKEND_ENABLED && localStorage.getItem('swiftshop.push-revoke-pending')) { try { await revoke(); localStorage.removeItem('swiftshop.push-revoke-pending'); } catch { return; } }
    if(window.SWIFTSHOP_PUSH_ENABLED && window.SwiftPush && localStorage.getItem(preferenceKey())==='on') { registeredScope=scope(); try { if(!window.SwiftPush.web || (typeof Notification!=='undefined'&&Notification.permission==='granted')) await window.SwiftPush.enable(); } catch (e) {status(e.message);} }
    await sync();
  }
  window.addEventListener('online',resume);
  document.addEventListener('visibilitychange',()=>{if(!document.hidden) resume();});
  setInterval(sync,15000);
  resume();
  render();
})();

