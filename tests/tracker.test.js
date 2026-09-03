#!/usr/bin/env node
// Cooked — suite de tests du tracker (Sprint 38).
// Usage : npm i jsdom && node tests/tracker.test.js
// Teste SOURCE (wix/tracker.html) et MINIFIÉ (wix/tracker.min.html) :
//   1. execution guard (double-embed → 1 seul event par action)
//   2. classification des clics (phone/booking/internal/outbound)
//   3. exposition des ids en query params (?cooked_aid/&cooked_sid via
//      replaceState) au boot + ré-exposition après nav SPA — Sprint 38 :
//      Wix Forms V2 ne rend pas les champs cachés dans le DOM, le pont
//      vers les forms est masterPage.js (wixLocation.query → setFieldValues)
//   4. localStorage bloqué → aid stable via sessionStorage
//   5. batching : format {events:[…]}, critiques immédiats, gain réseau,
//      exactitude active_ms / duration (horloge simulée 120 s)
//   6. T-17 (mission 02/09/2026) — les trois correctifs mesurés en prod ont
//      leur assertion : wipe de storage en cours de page (sprint41), page_exit
//      ré-armé au retour d'onglet (sprint40), chrome Cookiebot hors anchor
//      (sprint35) ; et CLS = 0 émis quand l'observer est attaché (sprint42)
const { JSDOM, VirtualConsole } = require('jsdom');
const fs = require('fs');
const path = require('path');
let failures = 0;
const ok = (cond, label) => { console.log((cond ? '  ✅ ' : '  ❌ ') + label); if (!cond) failures++; };

function makeDom(opts = {}) {
  const vc = new VirtualConsole(); vc.on('error', () => {});
  const dom = new JSDOM(`<!DOCTYPE html><body>
    <a id="tel" href="tel:+33500000000">T</a>
    <a id="bkg" href="/honoraires-rendez-vous">R</a>
    <a id="int" href="/autre-page">I</a>
    <a id="out" href="https://example.com/x">O</a>
    <div id="CybotCookiebotDialog"><a id="cb" href="#accept">Tout accepter</a></div>
    <a id="anc" href="#formulaire">Demander un RDV</a>
  </body>`, { url: 'https://www.jplouton-avocat.fr/article-test', pretendToBeVisual: true, runScripts: 'dangerously', virtualConsole: vc });
  const w = dom.window;
  w.eval(`window.__SENT=[];navigator.sendBeacon=undefined;
    window.fetch=function(u,o){window.__SENT.push(JSON.parse(o.body));return Promise.resolve({ok:true});};
    window.PerformanceObserver=undefined;`);
  if (opts.vitals)
    w.eval(`window.PerformanceObserver=function(cb){this.observe=function(o){if(o.type!=='layout-shift')throw new Error('unsupported');};this.disconnect=function(){};};`);
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
  const u1 = new w.URL(w.location.href);
  const aid = u1.searchParams.get('cooked_aid') || '';
  ok(aid.length >= 8 && aid === ev[0].anonymous_id, 'cooked_aid exposé en query == aid des events');
  ok((u1.searchParams.get('cooked_sid') || '').length >= 8, 'cooked_sid exposé en query');
  ok(u1.pathname === '/article-test', 'path inchangé par replaceState');
  ok(w.__SENT.every(b => Array.isArray(b.events)), 'tous les POST au format {events:[…]}');
  // nav SPA : la query est ré-exposée sur la nouvelle URL (hook pushState → onPMC)
  w.eval(`history.pushState({}, '', '/page-suivante');`);
  await wait(80);
  const u2 = new w.URL(w.location.href);
  ok(u2.pathname === '/page-suivante'
    && u2.searchParams.get('cooked_aid') === aid, 'nav SPA : ids ré-exposés sur la nouvelle URL');
  ok(events(w).filter(e => e.name === 'pageview').length === 2, 'nav SPA : pageview émis, pas de boucle replaceState');

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

  // 6a : sprint41 — wipe de storage EN COURS de page : sid et aid survivent (auto-réparation)
  w = makeDom();
  w.eval(js);
  w.document.getElementById('tel').dispatchEvent(new w.MouseEvent('click', { bubbles: true, cancelable: true }));
  await wait(80);
  const before = events(w).find(e => e.name === 'cta_phone_click');
  w.localStorage.clear();
  w.document.getElementById('tel').dispatchEvent(new w.MouseEvent('click', { bubbles: true, cancelable: true }));
  await wait(80);
  const after = events(w).filter(e => e.name === 'cta_phone_click')[1];
  ok(after && after.session_id === before.session_id, 'sprint41 : wipe de storage → même sid (blob ré-écrit, pas re-minté)');
  ok(after && after.anonymous_id === before.anonymous_id
    && w.localStorage.getItem('_ckd_aid') === before.anonymous_id, 'sprint41 : wipe de storage → aid conservé et ré-écrit (healAid)');

  // 6b : sprint40 — page_exit ré-armé au retour d'onglet (masquer / revenir / masquer → 2 page_exit)
  w = makeDom();
  w.eval(js);
  w.eval(`window.__hidden=false;Object.defineProperty(document,'hidden',{get:function(){return window.__hidden;},configurable:true});`);
  w.eval(`window.__hidden=true;document.dispatchEvent(new Event('visibilitychange'));
    window.__hidden=false;document.dispatchEvent(new Event('visibilitychange'));
    window.__hidden=true;document.dispatchEvent(new Event('visibilitychange'));`);
  await wait(80);
  ok(events(w).filter(e => e.name === 'page_exit').length === 2, 'sprint40 : page_exit ré-armé au retour d\'onglet (2 page_exit)');

  // 6c : sprint35 — un clic dans le dialog Cookiebot n'est pas un cta_anchor_click ; une vraie ancre l'est
  w = makeDom();
  w.eval(js);
  ['cb','anc'].forEach(id =>
    w.document.getElementById(id).dispatchEvent(new w.MouseEvent('click', { bubbles: true, cancelable: true })));
  await wait(80);
  const anchors = events(w).filter(e => e.name === 'cta_anchor_click');
  ok(anchors.length === 1 && anchors[0].props.target_section === 'formulaire', 'sprint35 : chrome Cookiebot exclu, ancre réelle comptée');

  // 6d : sprint42 — CLS = 0 émis quand l'observer layout-shift est attaché ; rien sans observer
  w = makeDom({ vitals: true });
  w.eval(js);
  w.eval(`window.dispatchEvent(new Event('pagehide'));`);
  await wait(80);
  const cls = events(w).filter(e => e.name === 'web_vitals' && e.props.metric === 'CLS');
  ok(cls.length === 1 && cls[0].props.value === 0, 'sprint42 : CLS = 0 émis explicitement (observer attaché)');
  w = makeDom();
  w.eval(js);
  w.eval(`window.dispatchEvent(new Event('pagehide'));`);
  await wait(80);
  ok(events(w).filter(e => e.name === 'web_vitals' && e.props.metric === 'CLS').length === 0, 'sans PerformanceObserver : aucun CLS (métrique Chromium-only, jamais un faux 0)');
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
