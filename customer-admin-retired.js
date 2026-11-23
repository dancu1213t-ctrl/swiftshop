/* Customer entry does not initialize or restore an administrator session. */
(()=>{'use strict';
window.SwiftAdmin={verified:false,client:null,request:async()=>{throw Error('Administration has moved to the separate admin portal.');},signout:async()=>{}};
function retire(){document.getElementById('adminMenuButton')?.remove();document.querySelectorAll('.po-admin-entry,[onclick="openAdminPortal()"],[onclick="openAdminLogin()"]').forEach(n=>n.remove());for(const id of ['adminScreen','adminLoginBox']){const n=document.getElementById(id);if(n){n.hidden=true;n.inert=true;n.setAttribute('aria-hidden','true');}}window.openAdminPortal=()=>{};window.openAdminLogin=()=>{};}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>queueMicrotask(retire),{once:true});else retire();window.addEventListener('load',retire,{once:true});
})();

