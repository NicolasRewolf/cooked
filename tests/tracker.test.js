#!/usr/bin/env node
// Cooked — suite de tests du tracker (Sprint 37).
// Usage : npm i jsdom && node tests/tracker.test.js
// Teste SOURCE (wix/tracker.html) et MINIFIÉ (wix/tracker.min.html) :
//   1. execution guard (double-embed → 1 seul event par action)
//   2. classification des clics (phone/booking/internal/outbound)
//   3. seeding des champs cachés cooked_aid/cooked_sid (immédiat + tardif)
//   4. localStorage bloqué → aid stable via sessionStorage
//   5. batching : format {events:[…]}, critiques immédiats, gain réseau,
//      exactitude active_ms / duration (horloge simulée 120 s)
const { JSDOM, VirtualConsole } = require('jsdom');
const fs = require('fs');
const path = require('path');
let failures = 0;
const ok = (cond, label) => { console.log((cond ? '  ✅ ' : '  ❌ ') + label); if (!cond) failures++; };

function makeDom(opts = {}) {
  const vc = new VirtualConsole(); vc.on('error', () => {});
  const dom = new JSDOM(`<!DOCTYPE html><body>
    <form><input name="cooked_aid"><input name="cooked_sid"><input name="email"></form>
    <a id="tel" href="tel:+33500000000">T</a>
    <a id="bkg" href="/honoraires-rendez-vous">R</a>
    <a id="int" href="/autre-page">I</a>
    <a id="out" href="https://example.com/x">O</a>
  </body>`, { url: 'https://www.jplouton-avocat.fr/article-test', pretendToBeVisual: true, runScripts: 'dangerously', virtualConsole: vc });
  const w = dom.window;
  w.eval(`window.__SENT=[];navigator.sendBeacon=undefined;
    window.fetch=function(u,o){window.__SENT.push(JSON.parse(o.body));return Promise.resolve({ok:true});};
    window.PerformanceObserver=undefined;`);
  if (opts.blockLocalStorage)
    w.eval(`Object.defineProperty(window,'localStorage',{get(){throw new Error('blocked');}});`);
  if (opts.mockClock)
    w.eval(`window.__NOW=1000000;Date.now=function(){return window.__NOW;};
      window.__intervals=[];const o=window.setInterval;
      window.setInterval=function(fn,ms){window.__intervals.push({fn,ms});return o(fn,1e9);};`);
  return w;
}
const wait = ms => new Promise(r => setTimeout(r, ms));
const events = w => w.__SENT.flatMap(b => b.events || []);

async function suite(label, js) {
  console.log('— ' + label);
  // 1+2+3 : garde, clics, champs
  let w = makeDom();
  w.eval(js); w.eval(js); // double-embed simulé
  ['tel','bkg','int','out'].forEach(id =>
    w.document.getElementById(id).dispatchEvent(new w.MouseEvent('click', { bubbles: true, cancelable: true })));
  await wait(150);
  let ev = events(w);
  const counts = ev.reduce((a,e)=>{a[e.name]=(a[e.name]||0)+1;return a;},{});
  ok(counts.pageview === 1, 'garde : 1 pageview malgré 2 exécutions');
  ok(counts.cta_phone_click === 1 && counts.cta_booking_click === 1
    && counts.click_internal === 1 && counts.click_outbound === 1, 'clics : 4 classes, 1 event chacune');
  ok(ev.every(e => e.props._v && /^sprint\d+$/.test(e.props._v)), 'version stamp présent');
  const aid = w.document.querySelector('input[name="cooked_aid"]').value;
  ok(aid.length >= 8 && aid === ev[0].anonymous_id, 'cooked_aid rempli == aid des events');
  ok(w.document.querySelector('input[name="cooked_sid"]').value.length >= 8, 'cooked_sid rempli');
  ok(w.document.querySelector('input[name="email"]').value === '', 'champs utilisateur intacts');
  ok(w.__SENT.every(b => Array.isArray(b.events)), 'tous les POST au format {events:[…]}');
  // form tardif via focusin
  const late = w.document.createElement('form');
  late.innerHTML = '<input name="cooked_aid" id="la"><input id="msg">';
  w.document.body.appendChild(late);
  w.document.getElementById('msg').dispatchEvent(new w.FocusEvent('focusin', { bubbles: true }));
  await wait(50);
  ok(w.document.getElementById('la').value.length >= 8, 'form rendu tardivement rempli via focusin');

  // 4 : localStorage bloqué
  w = makeDom({ blockLocalStorage: true });
  w.eval(js);
  w.document.getElementById('tel').dispatchEvent(new w.MouseEvent('click', { bubbles: true, cancelable: true }));
  await wait(150);
  ev = events(w);
  const aids = [...new Set(ev.map(e => e.anonymous_id))];
  ok(aids.length === 1, 'localStorage bloqué : aid unique (sessionStorage)');
  ok(aids[0] === w.sessionStorage.getItem('_ckd_aid'), 'aid persisté en sessionStorage');

  // 5 : batching, horloge simulée 120 s d'activité continue
  w = makeDom({ mockClock: true });
  w.eval(js);
  w.eval(`const t1=window.__intervals.find(i=>i.ms===1000),
    t10=window.__intervals.find(i=>i.ms===10000),
    t30=window.__intervals.find(i=>i.ms===30000);
    for(let s=1;s<=120;s++){window.__NOW+=1000;
      window.dispatchEvent(new Event('mousemove'));t1.fn();
      if(s%10===0)t10.fn();if(s%30===0)t30.fn();}
    window.dispatchEvent(new Event('pagehide'));`);
  await wait(100);
  ev = events(w);
  const ticks = ev.filter(e => e.name === 'engagement_tick');
  const exit = ev.find(e => e.name === 'page_exit');
  ok(ticks.reduce((a,t)=>a+t.props.active_ms,0) === 120000, 'active_ms exact (120 000 ms)');
  ok(exit && exit.props.duration_seconds === 120, 'page_exit duration exact (120 s)');
  ok(w.__SENT.length < ev.length, `batching effectif (${w.__SENT.length} POST pour ${ev.length} events)`);
}

(async () => {
  const read = f => fs.readFileSync(path.join(__dirname, '..', f), 'utf8').match(/<script>([\s\S]*)<\/script>/)[1];
  await suite('SOURCE  wix/tracker.html', read('wix/tracker.html'));
  if (fs.existsSync(path.join(__dirname, '..', 'wix/tracker.min.html'))) {
    const min = fs.readFileSync(path.join(__dirname, '..', 'wix/tracker.min.html'), 'utf8');
    ok(min.length <= 15000, `minifié ≤ 15 000 chars (${min.length})`);
    await suite('MINIFIÉ wix/tracker.min.html', min.match(/<script>([\s\S]*)<\/script>/)[1]);
  }
  console.log(failures ? `\n${failures} ÉCHEC(S)` : '\nTOUT PASSE');
  process.exit(failures ? 1 : 0);
})();
