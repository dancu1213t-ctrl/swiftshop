(()=>{
if(window.SwiftPush||window.Capacitor?.isNativePlatform?.())return;
const key='BKTjfXsnMNAs70x7eD-NAHRDDfq4ldiKx4WdFm4Wp6Rb3r3vtYYxa2u1WKCbBJkKX2W7u2FuLGgJnUIff6aRN9Y';
const apple=/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
const home=()=>navigator.standalone===true||matchMedia('(display-mode: standalone)').matches;
let pending=null;
function emit(name,detail){window.dispatchEvent(new CustomEvent(name,{detail}));}
window.SwiftPush={web:true,requestPermission(){
if(apple&&!home())throw Error('Open SwiftShop from its Home Screen icon. In Safari, tap Share → Add to Home Screen first.');
if(!('Notification'in window))throw Error('Phone alerts require iOS 16.4 or later and the Home Screen app.');
return Notification.permission==='granted'?Promise.resolve('granted'):Notification.permission==='denied'?Promise.resolve('denied'):Notification.requestPermission();
},async enable(){
if(apple&&!home())throw Error('Open SwiftShop from its Home Screen icon. In Safari, tap Share → Add to Home Screen first.');
if(!isSecureContext||!('Notification'in window)||!('serviceWorker'in navigator)||!('PushManager'in window))throw Error('Phone alerts require an iPhone Home Screen app on iOS 16.4 or later, or a supported browser.');
if(pending)return pending;
const permission=window.SwiftPush.requestPermission();
pending=(async()=>{if(await permission!=='granted')throw Error('Notifications are blocked. On iPhone, open Settings → Notifications → SwiftShop and allow notifications.');
const reg=await navigator.serviceWorker.register('/customer-push-sw.js',{scope:'/'});await navigator.serviceWorker.ready;
let subscription=await reg.pushManager.getSubscription();
if(!subscription){const raw=atob(key.replace(/-/g,'+').replace(/_/g,'/'));subscription=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:Uint8Array.from(raw,c=>c.charCodeAt(0))});}
const token={platform:'web',token:JSON.stringify(subscription.toJSON())};emit('swift-push-token',token);return token;})();
try{return await pending;}finally{pending=null;}
},async disable(){const reg=await navigator.serviceWorker.getRegistration('/');const sub=await reg?.pushManager.getSubscription();if(sub)await sub.unsubscribe();}};
navigator.serviceWorker?.addEventListener('message',e=>{if(e.data?.type==='customer-push')emit('swift-delivery-push',{data:e.data.data});if(e.data?.type==='customer-push-open')emit('swift-delivery-push-open',{data:e.data.data});});
const params=new URLSearchParams(location.hash.slice(1));const open=params.get('push');if(open){try{const data=JSON.parse(open);let attempts=0;const deliver=()=>{const screen=document.getElementById('appScreen');if(screen&&!screen.hidden&&getComputedStyle(screen).display!=='none'){emit('swift-delivery-push-open',{data});return;}if(++attempts<120)setTimeout(deliver,500);};setTimeout(deliver,500);}catch{}}
})();