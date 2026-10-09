const $ = id => document.getElementById(id);
let config, token, expires = 0, busy = false;
const redirect = `${location.origin}/`;
const encode = bytes => btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
const random = () => encode(crypto.getRandomValues(new Uint8Array(32)));
function message(text = '') { $('message').textContent = text; }
function buttons(state) {
  $('start').disabled = busy || state !== 'stopped';
  $('stop').disabled = busy || state !== 'running';
  $('refresh').disabled = busy;
}
function signedOut() {
  token = undefined; sessionStorage.removeItem('session');
  $('signin').hidden = false; $('controls').hidden = true; $('costpanel').hidden = true;
  $('state').textContent = 'Sign in to view status';
  $('indicator').dataset.state = '';
  $('detail').textContent = 'Use the email and password from your invitation.';
}
async function request(path, options = {}) {
  if (!token || Date.now() >= expires) { signedOut(); throw new Error('Your session expired. Please sign in again.'); }
  const response = await fetch(config.api + path, {...options, signal: AbortSignal.timeout(20000), headers: {Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'}});
  if (response.status === 401) { signedOut(); throw new Error('Your session expired. Please sign in again.'); }
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || `Request failed (${response.status}).`);
  return body;
}
async function refresh() {
  if (busy || !token) return;
  busy = true; buttons();
  try {
    const result = await request('/state');
    $('state').textContent = ({running:'Server running',stopped:'Server stopped',pending:'Server starting',stopping:'Server stopping'})[result.state] || result.state;
    $('indicator').dataset.state = result.state;
    $('detail').textContent = result.state === 'running' ? 'Select the Brazil exit node in Tailscale. VPN readiness is not checked here.' : 'Start the server when you need your Brazil connection.';
    message();
  } catch (error) { message(error.message); }
  finally { busy = false; buttons($('indicator').dataset.state); }
}
$('signin').onclick = async () => {
  $('signin').disabled = true;
  try {
    const verifier = random(), state = random();
    sessionStorage.setItem('oauth', JSON.stringify({verifier, state, created: Date.now()}));
    const challenge = encode(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
    const params = new URLSearchParams({client_id:config.clientId,response_type:'code',scope:'openid email profile',redirect_uri:redirect,state,code_challenge:challenge,code_challenge_method:'S256'});
    location.assign(`${config.domain}/oauth2/authorize?${params}`);
  } catch (error) { message(error.message); $('signin').disabled = false; }
};
$('signout').onclick = () => {
  signedOut(); sessionStorage.removeItem('oauth');
  location.assign(`${config.domain}/logout?${new URLSearchParams({client_id:config.clientId,logout_uri:redirect})}`);
};
$('refresh').onclick = refresh;
for (const [id, action] of [['start','on'],['stop','off']]) $(id).onclick = async () => {
  if (busy || (action === 'off' && !confirm('Stop the Brazil server? Everyone using this exit node will be disconnected.'))) return;
  busy = true; buttons(); message();
  try { const result = await request('/power', {method:'POST',body:JSON.stringify({action})}); $('indicator').dataset.state = result.state; }
  catch (error) { message(error.message); return; }
  finally { busy = false; buttons($('indicator').dataset.state); }
  await refresh();
};
async function init() {
  $('signin').disabled = true;
  try {
    const response = await fetch('config.json', {cache:'no-store', signal:AbortSignal.timeout(15000)});
    if (!response.ok) throw new Error('Controller configuration could not be loaded.');
    config = await response.json();
    const params = new URLSearchParams(location.search);
    history.replaceState({}, '', redirect);
    if (params.has('error')) { sessionStorage.removeItem('oauth'); throw new Error(params.get('error_description') || params.get('error')); }
    if (params.has('code')) {
      const pending = JSON.parse(sessionStorage.getItem('oauth') || 'null');
      sessionStorage.removeItem('oauth');
      if (!pending || pending.state !== params.get('state') || Date.now() - pending.created > 600000) throw new Error('Sign-in could not be verified. Please sign in again.');
      const response = await fetch(`${config.domain}/oauth2/token`, {signal:AbortSignal.timeout(20000),method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'authorization_code',client_id:config.clientId,code:params.get('code'),redirect_uri:redirect,code_verifier:pending.verifier})});
      const result = await response.json();
      if (!response.ok || !result.access_token) throw new Error('Sign-in could not be completed. Please try again.');
      sessionStorage.setItem('session', JSON.stringify({token:result.access_token,expires:Date.now()+result.expires_in*1000}));
    }
    const saved = JSON.parse(sessionStorage.getItem('session') || 'null');
    if (saved && saved.expires > Date.now()) {
      token = saved.token; expires = saved.expires;
      $('signin').hidden = true; $('controls').hidden = false;
      await refresh();
      if (token) { $('costpanel').hidden = false; await loadCosts(); }
    } else signedOut();
  } catch (error) { message(error.message); }
  finally { $('signin').disabled = !config; }
}
let costReport;
const money = value => Number(value).toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 4});
async function loadCosts() {
  $('costrefresh').disabled = true;
  try {
    const report = await request('/costs');
    costReport = report;
    $('costmessage').textContent = report.message || 'Billing report is pending.';
    $('costupdated').textContent = report.generatedAt ? `Snapshot: ${new Date(report.generatedAt).toLocaleString()}. AWS billing may lag 24 hours or longer.` : '';
    $('costcoverage').textContent = report.coverage || 'No project total is available yet.';
    $('costdata').hidden = report.status !== 'ready';
    if (report.status !== 'ready') return;
    const [current, previous] = report.months;
    $('costtotal').textContent = `$${money(current.total)}`;
    $('costprevious').textContent = previous.services.length ? `$${money(previous.total)}` : 'No attributed data';
    $('costchart').replaceChildren();
    const maximum = Math.max(...current.daily.map(day => Math.abs(Number(day.amount))), 0.000001);
    for (const day of current.daily) {
      const bar = document.createElement('div');
      bar.className = 'costbar' + (Number(day.amount) < 0 ? ' negative' : '');
      bar.style.height = `${Math.max(2, Math.abs(Number(day.amount)) / maximum * 100)}%`;
      bar.title = `${day.date}: $${money(day.amount)}`;
      bar.setAttribute('role', 'img'); bar.setAttribute('aria-label', bar.title);
      $('costchart').append(bar);
    }
    $('costservices').replaceChildren();
    for (const service of current.services) {
      const row = document.createElement('tr');
      for (const text of [service.name, money(service.amount)]) {
        const cell = document.createElement('td'); cell.textContent = text; row.append(cell);
      }
      $('costservices').append(row);
    }
  } catch (error) { $('costmessage').textContent = error.message; $('costdata').hidden = true; }
  finally { $('costrefresh').disabled = false; }
}
$('costrefresh').onclick = loadCosts;
$('costexport').onclick = () => {
  if (!costReport || costReport.status !== 'ready') return;
  const rows = [['Date','Currency','Unblended cost (Project tag only)'], ...costReport.months.flatMap(month => month.daily.map(day => [day.date, 'USD', day.amount]))];
  const csv = rows.map(row => row.map(value => `"${String(value).replaceAll('"','""')}"`).join(',')).join('\r\n');
  const url = URL.createObjectURL(new Blob([csv], {type:'text/csv'}));
  const link = document.createElement('a'); link.href = url; link.download = 'brazil-project-costs.csv'; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};
await init();
setInterval(() => { if (!document.hidden) refresh(); }, 10000);
