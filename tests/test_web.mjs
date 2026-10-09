import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {webcrypto} from 'node:crypto';
import assert from 'node:assert/strict';
const source = readFileSync(new URL('../web/app.js', import.meta.url), 'utf8');
async function setup({search='',stored={},apiStatus=200,costReport}={}) {
  const elements = new Map();
  const makeElement = () => ({dataset:{},style:{},hidden:false,disabled:false,textContent:'',children:[],append(child){this.children.push(child)},replaceChildren(){this.children=[]},setAttribute(){}});
  const calls = [], navigations = [], storage = new Map(Object.entries(stored));
  const context = {
    document:{hidden:false,createElement:makeElement,getElementById(id){if(!elements.has(id)) elements.set(id,makeElement());return elements.get(id);}},
    location:{origin:'https://controller.example',search,assign(url){navigations.push(url);}},
    history:{replaceState(){}},sessionStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},
    AbortSignal,crypto:webcrypto,TextEncoder,Uint8Array,URLSearchParams,Date,JSON,btoa:s=>Buffer.from(s,'binary').toString('base64'),confirm:()=>false,setInterval(){},
    async fetch(url,options={}){calls.push({url,options});if(url==='config.json')return {ok:true,json:async()=>({api:'https://api.example',clientId:'browser-client',domain:'https://auth.example'})};if(url==='https://api.example/costs' && costReport)return {ok:true,json:async()=>costReport};if(url==='https://auth.example/oauth2/token')return {ok:true,json:async()=>({access_token:'exchanged-token',expires_in:3600})};return {ok:apiStatus===200,status:apiStatus,json:async()=>apiStatus===200?{state:'running'}:{error:'unauthorized'}};}
  };
  await runInNewContext(`(async()=>{${source}\n})()`,context);
  return {elements,calls,navigations,storage};
}
const invalid = await setup({search:'?code=stolen&state=wrong',stored:{oauth:JSON.stringify({state:'expected',verifier:'secret',created:Date.now()})}});
assert.match(invalid.elements.get('message').textContent,/could not be verified/);
assert.equal(invalid.calls.length,1,'invalid OAuth state must never exchange a code');
const login = await setup();
await login.elements.get('signin').onclick();
const url = new URL(login.navigations[0]);
assert.equal(url.searchParams.get('code_challenge_method'),'S256');
assert.equal(url.searchParams.get('redirect_uri'),'https://controller.example/');
assert.equal(url.searchParams.get('code_challenge').length,43);
assert.equal(url.searchParams.get('state'),JSON.parse(login.storage.get('oauth')).state);
const authenticated = await setup({stored:{session:JSON.stringify({token:'test-access-token',expires:Date.now()+60000})}});
assert.equal(authenticated.elements.get('state').textContent,'Server running');
assert.equal(authenticated.elements.get('start').disabled,true);
assert.equal(authenticated.elements.get('stop').disabled,false);
await authenticated.elements.get('stop').onclick();
assert.equal(authenticated.calls.filter(call => call.url.endsWith('/power')).length,0,'cancelled stop must never send a power request');
const rejected = await setup({stored:{session:JSON.stringify({token:'invalid',expires:Date.now()+60000})},apiStatus:401});
assert.equal(rejected.storage.has('session'),false);
assert.equal(rejected.elements.get('controls').hidden,true);
assert.match(rejected.elements.get('message').textContent,/expired/);
const callback = await setup({search:'?code=valid-code&state=expected',stored:{oauth:JSON.stringify({state:'expected',verifier:'test-verifier',created:Date.now()})}});
assert.equal(callback.calls[1].options.body.get('code_verifier'),'test-verifier');
assert.equal(callback.calls[2].options.headers.Authorization,'Bearer exchanged-token');
assert.equal(callback.storage.has('oauth'),false);
assert.equal(callback.elements.get('controls').hidden,false);
const costs = await setup({stored:{session:JSON.stringify({token:'test',expires:Date.now()+60000})},costReport:{status:'ready',message:'provisional',months:[{total:'1.25',daily:[{date:'2026-10-01',amount:'1.5'},{date:'2026-10-02',amount:'-0.25'}],services:[{name:'EC2',amount:'1.25'}]},{total:'0',daily:[],services:[]}]}});
assert.equal(costs.elements.get('costtotal').textContent,'$1.25');
assert.equal(costs.elements.get('costchart').children.length,2);
assert.equal(costs.elements.get('costchart').children[1].className,'costbar negative');
assert.equal(costs.elements.get('costservices').children[0].children[0].textContent,'EC2');
assert.equal(costs.elements.get('costprevious').textContent,'No attributed data');
console.log('Browser checks passed: PKCE, state rejection, authenticated status, stop cancellation, expired session.');
