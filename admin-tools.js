(()=>{'use strict';
// The inherited markup nests this screen inside #appScreen. The tools shell
// hides customer screens, so the management root must be its own body child.
const managementRoot=document.getElementById('adminScreen');
if(managementRoot){managementRoot.firstElementChild?.classList.add('admin-tools-legacy-header');managementRoot.lastElementChild?.classList.add('admin-tools-content');document.body.append(managementRoot);}
const notice=document.createElement('p');notice.id='portalToolNotice';notice.textContent='Opening management tools…';document.body.append(notice);let ready=false,routing=0,areaHost;
function parameters(){return Object.fromEntries(new URLSearchParams(location.hash.slice(1)));}
async function route(){if(!ready)return;const ticket=++routing,{tab='products',category,zone=''}=parameters();document.getElementById('adminScreen').style.display='block';document.getElementById('pureOffersAdminPage')?.style.setProperty('display','none');if(areaHost)areaHost.hidden=true;
 const r=await window.SwiftAdmin.client.rpc('swift_region_context').abortSignal(AbortSignal.timeout(15000));if(r.error)throw r.error;if(ticket!==routing)return;const stores=r.data.stores||[];
 window.SwiftAdminToolScope={zone,categories:new Set(stores.filter(s=>!zone||s.zone_id===zone).map(s=>s.category))};
 for(const id of ['adminProdCategory','adminInventoryFilter','adStore']){const select=document.getElementById(id);if(!select)continue;for(const s of stores)if(![...select.options].some(o=>o.value===s.category))select.add(new Option(s.name,s.category));for(const o of select.options){if(!o.value||o.value==='ALL')continue;const registered=stores.find(s=>s.category===o.value);o.hidden=!!zone&&(registered?registered.zone_id!==zone:zone!=='orange-walk');o.disabled=o.hidden;}if(select.selectedOptions[0]?.disabled)select.value=[...select.options].find(o=>o.value&&!o.disabled)?.value||'';}
 if(tab==='areas'){document.querySelectorAll('.admin-tab-content').forEach(n=>n.style.display='none');if(!areaHost){areaHost=document.createElement('div');areaHost.id='portalAreaTools';document.querySelector('#adminScreen>.admin-tools-content').append(areaHost);await window.SwiftOnboarding.mount(areaHost,window.SwiftAdmin.client);}if(ticket!==routing)return;areaHost.hidden=false;const tabs=areaHost.querySelector('.region-tabs');[...tabs?.children||[]].find(b=>b.textContent==='Service areas')?.click();return;}
 if(tab==='offers'){document.querySelector('.po-admin-entry')?.click();return;}
 const dynamic={merchantRequests:'Requests',accounts:'Account requests',broadcasts:'Announcements'};
 if(dynamic[tab]){[...document.querySelectorAll('.admin-tab-btn')].find(b=>b.textContent.trim()===dynamic[tab])?.click();}
 else window.switchAdminTab(tab==='wallet'?'users':tab);
 if(category){await window.SwiftAdminStores?.editItems(category);if(ticket!==routing)return;const filter=document.getElementById('adminInventoryFilter');if(filter&&![...filter.options].some(o=>o.value===category))filter.add(new Option(category,category));}
}
async function boot(){if(window.parent===window){location.replace('admin.html');return;}try{await window.SwiftAdmin.resume();ready=true;document.documentElement.dataset.portalAuthorized='true';notice.remove();await route();}catch(e){document.documentElement.dataset.portalAuthorized='false';notice.textContent='Your admin session ended. Return to the portal and sign in again.';window.parent.postMessage({type:'swift-admin-expired'},location.origin);}}
window.addEventListener('hashchange',()=>route().catch(e=>{notice.textContent=e.message;document.body.append(notice);}));window.addEventListener('swift-store-publication-changed',()=>window.parent.postMessage({type:'swift-admin-published'},location.origin));
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();

