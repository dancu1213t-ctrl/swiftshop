/* Shared catalogue filters: never mutate the source inventory. */
(()=>{
 const state={min:null,max:null,sort:'recommended'},stores=new Map();
 function forStore(category){if(!stores.has(category))stores.set(category,{min:null,max:null,sort:'recommended'});return stores.get(category);}
 function apply(items,settings=state){const rows=items.filter(item=>{const price=Number(item.price);return Number.isFinite(price)&&(settings.min===null||price>=settings.min)&&(settings.max===null||price<=settings.max);});if(settings.sort==='low')rows.sort((a,b)=>Number(a.price)-Number(b.price));if(settings.sort==='high')rows.sort((a,b)=>Number(b.price)-Number(a.price));if(settings.sort==='name')rows.sort((a,b)=>String(a.name).localeCompare(String(b.name)));return rows;}
 window.SwiftProductFilters={state,apply,forStore};
})();
