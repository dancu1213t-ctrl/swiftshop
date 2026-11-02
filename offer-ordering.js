(() => {
 'use strict';
 const make=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
 const button=(text,fn)=>{const n=make('button',text);n.type='button';n.onclick=fn;return n;};
 const money=c=>'BZ$'+(c/100).toFixed(2);
 const cents=value=>{const n=Number(value);if(!Number.isFinite(n)||n<0||n>10000||Math.abs(n*100-Math.round(n*100))>.00001)throw Error('Prices must be between 0 and 10,000 with at most two decimals.');return Math.round(n*100);};
 const label=s=>{s=String(s||'').trim();if(!s||s.length>80)throw Error('Option names must contain 1–80 characters.');return s;};
 let page,editor,optionsHost,groupsHost,current=null,sending=false;
 function input(value,placeholder,type='text'){const n=make('input');n.type=type;n.value=value??'';n.placeholder=placeholder;n.setAttribute('aria-label',placeholder);if(type==='number'){n.min='0';n.step='.01';}return n;}
 function optionRow(host,value={}){const row=make('div',undefined,'oo-edit-row');const name=input(value.label,'Option name'),price=input(value.price_cents===undefined?'':value.price_cents/100,'Price (BZD)','number');row.append(name,price,button('Remove',()=>row.remove()));row.dataset.optionId=value.id||crypto.randomUUID();host.append(row);}
 function groupRow(value={}){const box=make('section',undefined,'oo-edit-group'),name=input(value.label,'Group name, e.g. Sauces'),min=input(value.min??0,'Minimum selections','number'),max=input(value.max??1,'Maximum selections','number');min.step=max.step='1';const heading=make('div',undefined,'oo-edit-row');heading.append(name,button('Remove group',()=>box.remove()));const limits=make('div',undefined,'oo-edit-limits');limits.append(make('span','Minimum'),min,make('span','Maximum'),max);const rows=make('div',undefined,'oo-group-choices');box.dataset.groupId=value.id||crypto.randomUUID();box.append(heading,limits,rows,button('Add choice +',()=>optionRow(rows)));groupsHost.append(box);for(const v of value.choices||[])optionRow(rows,v);}
 function write(config={}){optionsHost.replaceChildren();groupsHost.replaceChildren();for(const v of config.options||[])optionRow(optionsHost,v);for(const v of config.groups||[])groupRow(v);editor.querySelector('[data-order-enabled]').checked=!!config.enabled;}
 function read(){if(!editor.querySelector('[data-order-enabled]').checked)return {enabled:false,options:[],groups:[]};const parse=host=>[...host.children].map(row=>({id:row.dataset.optionId,label:label(row.children[0].value),price_cents:cents(row.children[1].value)}));const options=parse(optionsHost);if(!options.length||options.length>40)throw Error('Add between 1 and 40 priced options.');const groups=[...groupsHost.children].map(box=>{const limits=box.querySelectorAll('.oo-edit-limits input'),choices=parse(box.querySelector('.oo-group-choices')),min=Number(limits[0].value),max=Number(limits[1].value);if(!choices.length||choices.length>40||!Number.isInteger(min)||!Number.isInteger(max)||min<0||max<min||max<1||max>choices.length)throw Error('Each extras group needs choices and valid minimum/maximum selections.');return {id:box.dataset.groupId,label:label(box.querySelector('input').value),min,max,choices};});if(groups.length>12)throw Error('Use at most 12 extras groups.');return {enabled:true,options,groups};}
 function mount(form){if(editor)return;editor=make('section',undefined,'oo-editor');editor.innerHTML='<h3>Order options</h3><label class="oo-enable"><input type="checkbox" data-order-enabled> Allow customers to order this offer</label><p>Set the prices shown on your artwork. Customers choose quantities for multiple items and extras.</p><h4>Sizes or main options</h4><div data-order-options></div><h4>Extras and customizations</h4><div data-order-groups></div>';optionsHost=editor.querySelector('[data-order-options]');groupsHost=editor.querySelector('[data-order-groups]');optionsHost.after(button('Add priced option +',()=>optionRow(optionsHost)));groupsHost.after(button('Add extras group +',()=>groupRow()));form.querySelector('.po-form-fields').insertBefore(editor,form.querySelector('.po-form-actions'));}
 function configValid(c){return c?.enabled&&Array.isArray(c.options)&&c.options.length&&c.options.every(o=>typeof o.id==='string'&&Number.isSafeInteger(o.price_cents)&&o.price_cents>=0)&&Array.isArray(c.groups);}
 function close(){page.style.display='none';document.getElementById('promoPage').style.display='block';window.SwiftNavigation?.refresh();}

 function categoryAnimation(offer){const drawings={
 Grocery:'<path fill="#e95027" d="M10 28h44l-6 28H16z"/><path stroke="#19864f" stroke-width="9" d="M20 29V15m8 14V10"/><rect x="33" y="9" width="9" height="24" rx="4" fill="#f4bb29"/><path fill="#63bfe8" d="m44 15 9 3-5 16-9-3z"/>',
 Pizza:'<path fill="#ffd65a" d="m13 54 9-43 35 26z"/><path d="m22 11 35 26" stroke="#d88c35" stroke-width="9" stroke-linecap="round"/><g fill="#e84537"><circle cx="30" cy="26" r="5"/><circle cx="24" cy="40" r="4"/><circle cx="41" cy="36" r="4"/></g>',
 Sushi:'<rect x="9" y="24" width="46" height="23" rx="6" fill="#fff0d8"/><path fill="#f94561" d="M9 24q22-25 46 0v10H9z"/><path fill="#172e22" d="M28 14h12v34H28z"/>',
 Burgers:'<path fill="#ed9535" d="M10 27q2-30 44 0zM10 44h44q0 15-22 15T10 44"/><path stroke="#258b46" stroke-width="7" d="m10 33 10 3 12-4 12 4 10-3"/><path stroke="#783729" stroke-width="9" d="M12 42h40"/>',
 'Fast Food':'<path stroke="#ffc83c" stroke-width="6" d="M20 37 16 10m12 27V6m8 31 5-29m3 31 9-23"/><path fill="#f53e49" d="m12 29 42 4-7 26H19z"/>',
 Coffee:'<ellipse cx="30" cy="49" rx="27" ry="7" fill="#e3aa66"/><path fill="#dd680c" d="M10 20h37v22q-2 14-18 14T10 42z"/><ellipse cx="29" cy="20" rx="19" ry="9" fill="#663317"/><ellipse cx="29" cy="21" rx="15" ry="5" fill="#ffe1a1"/><path fill="none" stroke="#dd680c" stroke-width="7" d="M48 25q20 0 8 19h-9"/>',
 Gifts:'<path fill="#138951" d="M9 23h46v35H9z"/><path fill="#ffbc4b" d="M27 23h10v35H27z"/><path fill="none" stroke="#ffbc4b" stroke-width="5" d="M32 23Q7 3 18 8q12-3 14 15Q57 3 46 8q-12-3-14 15"/>',
 Pharmacy:'<rect x="12" y="12" width="40" height="45" rx="10" fill="#2d9e77"/><path stroke="#fff" stroke-width="8" d="M32 23v23M20 35h24"/>',
 Desserts:'<ellipse cx="32" cy="35" rx="24" ry="17" fill="#d69a48"/><g fill="#65351f"><circle cx="20" cy="30" r="3"/><circle cx="37" cy="27" r="3"/><circle cx="30" cy="42" r="3"/><circle cx="46" cy="37" r="3"/></g>',
 Breakfast:'<g fill="#edb653" stroke="#c7872e" stroke-width="2"><ellipse cx="32" cy="44" rx="24" ry="10"/><ellipse cx="32" cy="35" rx="24" ry="10"/><ellipse cx="32" cy="26" rx="24" ry="10"/></g><rect x="26" y="19" width="12" height="8" rx="2" fill="#fff0a1"/>',
 Mexican:'<path fill="#ffce52" d="M7 49q1-53 50 0z"/><path fill="#864222" d="M15 44q3-32 34 0z"/><path stroke="#269850" stroke-width="7" d="m16 34 7 7 7-12 9 10 8-4"/>',
 American:'<rect x="8" y="23" width="49" height="24" rx="12" fill="#edab47"/><path stroke="#b84727" stroke-width="12" stroke-linecap="round" d="m16 28 33 13"/><path stroke="#ffc63c" stroke-width="3" d="m18 27 6 9 9-3 5 10 8-2"/>',
 Wings:'<path fill="#d86d19" d="M15 19q22-12 27 8t-20 23Q4 42 15 19"/><path stroke="#f4ddc0" stroke-width="8" stroke-linecap="round" d="m40 40 12 11"/>',
 BBQ:'<ellipse cx="32" cy="46" rx="28" ry="9" fill="#e6ae50"/><path fill="#963f25" d="m8 26 41-9 8 23-41 10z"/><path stroke="#e99062" stroke-width="4" d="m18 25 5 19m7-22 5 19m7-22 5 19"/>',
 Italian:'<ellipse cx="32" cy="38" rx="28" ry="18" fill="#efce92"/><g fill="none" stroke="#e74834" stroke-width="4"><ellipse cx="32" cy="37" rx="21" ry="12"/><ellipse cx="32" cy="37" rx="13" ry="7"/></g><path fill="#16874f" d="m35 20 12-12 2 13z"/>',
 Asian:'<path fill="#df4134" d="M7 30h50q-4 29-25 29T7 30"/><ellipse cx="32" cy="30" rx="25" ry="12" fill="#ffe4a5"/><path fill="none" stroke="#d5a24d" stroke-width="3" d="M15 30q12-17 15 0t18 0M20 34q13-13 27 0"/><path stroke="#70552e" stroke-width="3" d="m39 5 10 29M49 3 5 30"/>'};
 drawings.Japanese=drawings.Sushi;const tags=(offer.tags||[]).filter(t=>Object.hasOwn(drawings,t));const name=tags.length?tags[Math.floor(Math.random()*tags.length)]:Object.hasOwn(drawings,offer.category)?offer.category:null;if(!name)return null;if(name==='Wings'){const plate=make('div',undefined,'oo-wings-plate');plate.setAttribute('aria-hidden','true');plate.innerHTML='<svg viewBox="0 0 140 100" focusable="false"><ellipse cx="70" cy="78" rx="49" ry="8" fill="#17261c" opacity=".08"/><ellipse cx="70" cy="64" rx="55" ry="22" fill="#fff4e4" stroke="#ddd1be" stroke-width="2"/><ellipse cx="70" cy="61" rx="44" ry="15" fill="#ffe7c4"/><g class="oo-wing"><path d="M33 57 Q23 48 35 38 Q44 33 53 43 L60 54 Q48 65 33 57" fill="#c96923" stroke="#9d4415" stroke-width="2"/><path d="M37 43 Q45 39 51 46" fill="none" stroke="#f8ae55" stroke-width="4" stroke-linecap="round"/></g><g class="oo-wing oo-wing-two"><path d="M58 60 Q47 50 62 37 Q74 31 83 44 L88 58 Q75 69 58 60" fill="#d87828" stroke="#9d4415" stroke-width="2"/><path d="M64 42 Q72 36 78 45" fill="none" stroke="#ffb963" stroke-width="4" stroke-linecap="round"/></g><g class="oo-wing oo-wing-three"><path d="M89 58 Q80 48 92 39 Q105 36 113 47 Q117 55 107 61 Z" fill="#bd5c20" stroke="#9d4415" stroke-width="2"/><path d="M94 43 Q102 39 108 48" fill="none" stroke="#f7a950" stroke-width="4" stroke-linecap="round"/></g><g fill="none" stroke="#cf9d6d" stroke-width="2" stroke-linecap="round"><path class="oo-steam" d="M48 29 Q41 22 48 15"/><path class="oo-steam oo-steam-two" d="M72 25 Q65 18 72 10"/><path class="oo-steam oo-steam-three" d="M98 29 Q91 22 98 15"/></g><path d="M48 65l6-4 5 4-6 3zM86 66l5-3 4 3-4 3z" fill="#478845"/></svg>';return plate;}const n=make('div',undefined,'oo-category-animation');n.dataset.category=name;n.setAttribute('aria-hidden','true');n.innerHTML='<svg viewBox="0 0 84 84" focusable="false"><ellipse cx="42" cy="73" rx="28" ry="5" fill="#203526" opacity=".08"/><g class="oo-category-art" transform="translate(10 5)">'+drawings[name]+'</g><g class="oo-category-spark" fill="#e8ac53"><path d="M73 15l2 5 5 2-5 2-2 5-2-5-5-2 5-2z"/></g></svg>';return n;}
 function open(offer){
 current=offer;window.SwiftCartDraft?.prepare();page.replaceChildren();
 const c=offer.order_config,top=make('div',undefined,'oo-top');top.append(button('← Offers',close));
 const img=make('img');img.src=offer.image_url;img.alt=offer.title;
 const content=make('div',undefined,'oo-content');content.append(make('small',offer.pickup_name||(offer.is_general?'SwiftShop':offer.category)),make('h1',offer.title));
 if(offer.description)content.append(make('p',offer.description));
 const layout=make('div',undefined,'oo-layout'),art=make('div',undefined,'oo-image');art.append(img);layout.append(art,content);page.append(top,layout);page.style.display='block';page.scrollTop=0;window.SwiftNavigation?.refresh();
 if(!configValid(c)){content.append(make('p','Ordering options have not been added to this offer yet.','oo-note'));return;}
 const counts=new Map(),controls=new Map(),totals=make('div',undefined,'oo-totals'),error=make('p',undefined,'oo-error');error.setAttribute('role','status');
 const descriptors=c.options.map(o=>({...o,key:'main:'+o.id,kind:'main'}));
 for(const g of c.groups)for(const o of g.choices)descriptors.push({...o,key:'extra:'+g.id+':'+o.id,kind:'extra',group:g});
 function change(d,value){
  const n=Number(value);
  if(!Number.isInteger(n)||n<0||n>100){error.textContent='Enter a whole quantity from 0 to 100.';return false;}
  if(d.group&&n>0&&!counts.get(d.key)&&descriptors.filter(x=>x.group?.id===d.group.id&&(counts.get(x.key)||0)>0).length>=d.group.max){error.textContent='Choose up to '+d.group.max+' different items in '+d.group.label+'.';return false;}
  counts.set(d.key,n);error.textContent='';paint();return true;
 }
 function quantityRow(d,host){
  counts.set(d.key,0);const row=make('div',undefined,'oo-item-row'),copy=make('div',undefined,'oo-item-copy');
  copy.append(make('strong',d.label),make('small',d.price_cents?money(d.price_cents)+' each':'Included'));
  const stepper=make('div',undefined,'oo-item-stepper'),field=input(0,'Quantity for '+d.label,'number');field.step='1';field.min='0';field.max='100';field.inputMode='numeric';
  const minus=button('−',()=>change(d,(counts.get(d.key)||0)-1)),plus=button('+',()=>change(d,(counts.get(d.key)||0)+1));
  minus.setAttribute('aria-label','Decrease '+d.label);plus.setAttribute('aria-label','Increase '+d.label);
  field.oninput=()=>{if(field.value==='')return;if(!change(d,field.value))field.value=counts.get(d.key)||0;};
  field.onchange=()=>{if(!change(d,field.value||0))field.value=counts.get(d.key)||0;};
  controls.set(d.key,{row,field,minus,plus});stepper.append(minus,field,plus);row.append(copy,stepper);host.append(row);
 }
 const mains=make('fieldset');mains.append(make('legend','Choose your items'),make('p','Set a quantity for each item you want.','oo-note'));descriptors.filter(d=>d.kind==='main').forEach(d=>quantityRow(d,mains));content.append(mains);
 for(const g of c.groups){const box=make('fieldset');box.append(make('legend',g.label),make('p',(g.min?'Choose at least '+g.min:'Optional')+' · up to '+g.max+' different items','oo-note'));descriptors.filter(d=>d.group?.id===g.id).forEach(d=>quantityRow(d,box));content.append(box);}
 const add=button('Add to cart',addSelection);add.className='oo-add';content.append(totals,error,add);
 function paint(){
  for(const [key,x] of controls){const q=counts.get(key)||0;x.field.value=q;x.minus.disabled=q===0;x.plus.disabled=q===100;x.row.classList.toggle('oo-item-selected',q>0);}
  const subtotal=descriptors.reduce((s,d)=>s+d.price_cents*(counts.get(d.key)||0),0),other=Object.values(cart).reduce((s,i)=>s+Math.round(i.p*100)*i.q,0);
  totals.replaceChildren();for(const [name,value] of [['Selected items',subtotal],...(other?[['Already in cart',other]]:[])]){const r=make('div');r.append(make('span',name),make('strong',money(value)));totals.append(r);}
  totals.append(make('small','Delivery is calculated once in your cart.'));add.textContent='Add to cart · '+money(subtotal);add.disabled=sending||!descriptors.some(d=>d.kind==='main'&&(counts.get(d.key)||0)>0);
 }
 async function addSelection(){
  if(sending)return;window.SwiftCartDraft?.prepare();const chosen=descriptors.filter(d=>(counts.get(d.key)||0)>0);
  if(!chosen.some(d=>d.kind==='main')){error.textContent='Choose at least one main item.';return;}
  sending=true;paint();error.textContent='Checking offer…';
  try{
   const {data,error:err}=await supabaseClient.from('swift_store_offers').select('*').eq('id',offer.id).maybeSingle();if(err)throw err;
   if(!data||!data.published||Date.parse(data.starts_at)>Date.now()||(data.ends_at&&Date.parse(data.ends_at)<=Date.now())||JSON.stringify(data.order_config)!==JSON.stringify(c))throw Error('This offer changed or ended. Reopen it for the current options.');
   if(!['Snack','Drink','Household','Hygiene','Vegetables','Treats'].includes(offer.category)){const check=await supabaseClient.from('stores').select('is_open').eq('category',offer.category).maybeSingle();if(check.error||check.data?.is_open!=='yes')throw Error('This store is closed or its availability could not be confirmed.');}
   if(Object.values(cart).some(i=>i.offer_id===offer.id&&i.offer_quantity_mode!=='individual'))throw Error('Remove the older version of this offer from your cart, then add your items again.');
   const next=Object.assign(Object.create(null),cart),safe=s=>String(s).replace(/[<>&"']/g,'').slice(0,180);
   for(const d of chosen){
    const name=safe(offer.title)+' · '+(d.group?safe(d.group.label)+': ':'')+safe(d.label)+' ['+offer.id.slice(0,8)+':'+d.id.slice(0,8)+']',old=next[name],q=(old?.q||0)+counts.get(d.key);
    if(old&&(old.cat!==offer.category||Math.round(old.p*100)!==d.price_cents))throw Error('Remove the older version of this item from your cart first.');
    if(q>100)throw Error('A maximum of 100 of each item can be added.');
    next[name]={q,p:d.price_cents/100,w:null,cat:offer.category,offer_id:offer.id,offer_quantity_mode:'individual',offer_option_id:d.kind==='main'?d.id:null,offer_extra_group_id:d.group?.id||null,offer_extra_choice_id:d.kind==='extra'?d.id:null,offer_choices:[],...(data.pickup_lat!=null&&data.pickup_lng!=null?{offer_pickup:{lat:Number(data.pickup_lat),lng:Number(data.pickup_lng),name:data.pickup_name||offer.category}}:{})};
   }
   for(const g of c.groups){const n=new Set(Object.values(next).filter(i=>i.offer_id===offer.id&&i.offer_extra_group_id===g.id).map(i=>i.offer_extra_choice_id)).size;if(n<g.min||n>g.max)throw Error('Choose '+g.min+'–'+g.max+' different items in '+g.label+'.');}
   if(Object.keys(next).length>100)throw Error('Your cart can hold up to 100 different items.');
   cart=next;total=Object.values(cart).reduce((s,i)=>s+Math.round(i.p*100)*i.q,0)/100;
   update();window.updateCartBubble();window.renderCartPanel();page.style.display='none';document.getElementById('promoPage').style.display='none';window.openCart();
  }catch(e){error.textContent=e.message||'Could not add your items. Try again.';}
  finally{sending=false;paint();}
 }
 paint();
 }
 window.SwiftOfferOrdering={mount,read,write,open};
 document.addEventListener('DOMContentLoaded',()=>{page=make('section',undefined,'oo-page');page.id='pureOfferOrderPage';page.style.display='none';document.body.append(page);});
})();
