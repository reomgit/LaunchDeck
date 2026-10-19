// SPDX-License-Identifier: GPL-3.0-only
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../LaunchDeck/Services/CompanionHTML.swift', import.meta.url), 'utf8');
const script = source.match(/<script>([\s\S]*?)<\/script>/)[1];

class Element {
  constructor(tag='div') {
    this.tagName=tag;this.children=[];this.parent=null;this.dataset={};this.listeners={};
    this.style={setProperty:(key,value)=>{this.style[key]=value}};
    const classes=new Set();this.classList={add:x=>classes.add(x),remove:x=>classes.delete(x),toggle:(x,on)=>on?classes.add(x):classes.delete(x)};
    this.value='';this.textContent='';this.disabled=false;
  }
  get isConnected(){return this.root || Boolean(this.parent?.isConnected)}
  append(child){child.parent=this;this.children.push(child)}
  replaceChildren(...children){for(const child of this.children)child.parent=null;this.children=[];children.forEach(child=>this.append(child))}
  remove(){if(this.parent)this.parent.children=this.parent.children.filter(x=>x!==this);this.parent=null}
  setAttribute(name,value){this[name]=value}
  querySelector(selector){return this.children.find(x=>x.className===selector.slice(1))||null}
  addEventListener(event,handler){(this.listeners[event]??=[]).push(handler)}
  async fire(event){for(const handler of this.listeners[event]||[])await handler({preventDefault(){}})}
}

function fixture(overrides={}) {
  return {revision:1,profileID:'profile-a',profileName:'Deck',mode:'Manual',pageID:'page-a',pageName:'Main',model:'virtual',rows:8,columns:8,
    profiles:[{id:'profile-a',name:'Deck'}],controls:[{index:0,row:0,column:0,label:'Pad',action:'Shortcut',color:'#ff0000',enabled:true}],...overrides};
}
function harness({paired=true, snapshot=fixture()}={}) {
  const elements=new Map();const listeners={};const timers=new Map();const calls=[];let now=0,id=0,pendingSnapshots=0,maxPending=0;
  let next=snapshot,fetchHandler=null;
  const document={hidden:false,getElementById(key){if(!elements.has(key)){const element=new Element();element.root=true;elements.set(key,element)}return elements.get(key)},createElement:tag=>new Element(tag),addEventListener(event,handler){(listeners[event]??=[]).push(handler)}};
  const window={addEventListener(event,handler){(listeners[event]??=[]).push(handler)}};
  const context={document,window,localStorage:{getItem:()=>paired?'token-a':null,setItem(){},removeItem(){}},URL:{createObjectURL:()=> 'blob:test',revokeObjectURL(){}},Map,Set,AbortSignal,AbortController,
    Date:class extends Date {static now(){return now}},performance:{now:()=>now},
    setTimeout(callback,delay){const handle=++id;timers.set(handle,{callback,at:now+delay,delay});return handle},clearTimeout:handle=>timers.delete(handle),
    async fetch(path,options){calls.push({path,options,at:now});const isSnapshot=path==='/api/snapshot';if(isSnapshot){pendingSnapshots++;maxPending=Math.max(maxPending,pendingSnapshots)}
      try{if(fetchHandler){const response=await fetchHandler(path,options);if(response)return response}return {ok:true,status:200,json:async()=>path==='/api/pair'?{token:'new-token'}:structuredClone(next)}}finally{if(isSnapshot)pendingSnapshots--}}
  };
  vm.runInNewContext(script,context,{filename:'CompanionHTML.js'});
  async function flush(){for(let count=0;count<30;count++)await Promise.resolve()}
  return {elements,document,calls,timers,flush,get now(){return now},get maxPending(){return maxPending},setSnapshot(value){next=value},setFetch(handler){fetchHandler=handler},
    snapshots(){return calls.filter(x=>x.path==='/api/snapshot')},
    async advance(ms){const target=now+ms;for(let count=0;count<1000;count++){const entry=[...timers].filter(([,t])=>t.at<=target).sort((a,b)=>a[1].at-b[1].at)[0];if(!entry)break;now=entry[1].at;timers.delete(entry[0]);entry[1].callback();await flush()}now=target;await flush()},
    async event(name){for(const handler of listeners[name]||[])handler();await flush()}
  };
}

test('successful press refreshes immediately then polls a bounded burst and returns idle',async()=>{
  const h=harness();await h.flush();assert.equal(h.snapshots().length,1);
  await h.elements.get('deck').children[0].fire('click');await h.flush();
  assert.ok(h.snapshots().length>=2,'press must fetch a fresh frame before the idle timer');
  const pressed=JSON.parse(h.calls.find(x=>x.path==='/api/press').options.body);
  assert.deepEqual(pressed,{index:0,revision:1,pageID:'page-a'});
  await h.advance(67);assert.ok(h.snapshots().length>=3,'press burst should poll at15fps');
  await h.advance(4100);const count=h.snapshots().length;
  const timer=[...h.timers.values()][0];assert.equal(timer.delay,800,'expired burst returns to800ms');
  await h.advance(timer.at-h.now-1);assert.equal(h.snapshots().length,count);
  await h.advance(1);assert.equal(h.snapshots().length,count+1);
});

test('animated frames poll at67ms, then idle snapshots back off to800ms',async()=>{
  const h=harness({snapshot:fixture({animated:true})});await h.flush();
  await h.advance(66);assert.equal(h.snapshots().length,1);
  h.setSnapshot(fixture({animated:false}));await h.advance(1);assert.equal(h.snapshots().length,2);
  await h.advance(799);assert.equal(h.snapshots().length,2);
  await h.advance(1);assert.equal(h.snapshots().length,3);
});

test('color and feedback patches retain button identity and update current press revision',async()=>{
  const h=harness();await h.flush();const button=h.elements.get('deck').children[0];
  h.setSnapshot(fixture({revision:2,feedback:'Done',controls:[{...fixture().controls[0],color:'#00ff00',feedback:'✓'}]}));
  await h.advance(800);assert.equal(h.elements.get('deck').children[0],button);
  assert.equal(button.style['--color'],'#00ff00');assert.equal(button.querySelector('.feedback').textContent,'✓');
  assert.equal(h.elements.get('feedback').textContent,'Done');
  await button.fire('click');assert.equal(JSON.parse(h.calls.find(x=>x.path==='/api/press').options.body).revision,2);
});

test('page and control structure changes rebuild the grid',async()=>{
  const h=harness();await h.flush();let button=h.elements.get('deck').children[0];
  h.setSnapshot(fixture({pageID:'page-b',pageName:'Other'}));await h.advance(800);
  assert.notEqual(h.elements.get('deck').children[0],button);button=h.elements.get('deck').children[0];
  h.setSnapshot(fixture({pageID:'page-b',pageName:'Other',controls:[{...fixture().controls[0],label:'New pad'}]}));await h.advance(800);
  assert.notEqual(h.elements.get('deck').children[0],button);
});

test('pair and profile activation synchronize immediately',async()=>{
  const h=harness({paired:false});await h.flush();await h.elements.get('pair-form').fire('submit');await h.flush();
  assert.equal(h.snapshots().length,1);h.elements.get('profiles').value='profile-a';
  await h.elements.get('profiles').fire('change');await h.flush();assert.equal(h.snapshots().length,2);
});

test('hidden pages back off and repeated pageshow events cannot duplicate in-flight snapshots',async()=>{
  const h=harness({snapshot:fixture({animated:true})});await h.flush();h.document.hidden=true;await h.event('visibilitychange');
  await h.advance(799);assert.equal(h.snapshots().length,1);
  h.document.hidden=false;let resolve;h.setFetch(path=>path==='/api/snapshot'?new Promise(r=>{resolve=r}):null);
  await h.event('visibilitychange');assert.equal(h.snapshots().length,2,'visible page synchronizes immediately');
  await h.event('pagehide');await h.event('pageshow');await h.event('pageshow');await h.advance(200);
  assert.equal(h.maxPending,1);resolve({ok:true,status:200,json:async()=>fixture()});await h.flush();
  h.setFetch(null);await h.flush();await h.advance(800);assert.equal(h.maxPending,1);
  assert.ok(h.timers.size<=1,'only one poll timer survives');
});

test('revoked authentication clears the session and cannot continue sending presses',async()=>{
  const h=harness();await h.flush();h.setFetch(path=>path==='/api/snapshot'?{ok:false,status:401,json:async()=>({error:'revoked'})}:null);
  await h.advance(800);const before=h.calls.length;await h.elements.get('deck').children[0].fire('click');await h.flush();
  assert.equal(h.calls.length,before);assert.equal(h.elements.get('runtime').hidden,true);
});


test('stale press conflicts refresh safely and do not start an animation burst',async()=>{
  const h=harness();await h.flush();h.setSnapshot(fixture({revision:9,pageID:'new-page'}));
  h.setFetch(path=>path==='/api/press'?{ok:false,status:409,json:async()=>({error:'Deck changed. Refresh.'})}:null);
  await h.elements.get('deck').children[0].fire('click');await h.flush();
  assert.equal(h.snapshots().length,2);assert.equal([...h.timers.values()][0].delay,800);
  await h.elements.get('deck').children[0].fire('click');
  const requests=h.calls.filter(x=>x.path==='/api/press');
  assert.equal(JSON.parse(requests[1].options.body).revision,9);
  assert.equal(JSON.parse(requests[1].options.body).pageID,'new-page');
});
