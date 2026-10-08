/* Shared catalogue filters: never mutate the source inventory. */
(()=>{
 const state={min:null,max:null,sort:'recommended'};
 function apply(items){const rows=items.filter(item=>{const price=Number(item.price);return Number.isFinite(price)&&(state.min===null||price>=state.min)&&(state.max===null||price<=state.max);});if(state.sort==='low')rows.sort((a,b)=>Number(a.price)-Number(b.price));if(state.sort==='high')rows.sort((a,b)=>Number(b.price)-Number(a.price));if(state.sort==='name')rows.sort((a,b)=>String(a.name).localeCompare(String(b.name)));return rows;}
 window.SwiftProductFilters={state,apply};
})();
