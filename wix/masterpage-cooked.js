// COOKED Sprint 38 — attribution des formulaires (à coller dans masterPage.js)
// ============================================================================
// Wix Forms V2 ne rend pas les champs cachés dans le DOM de la page publiée
// (vérifié en prod le 11/06/2026) : le tracker ne peut pas les remplir.
// Chaîne retenue, 100 % APIs officielles :
//   tracker (Custom Code)  → expose cooked_aid/cooked_sid en query params
//                            (history.replaceState — URL jamais liée, donc
//                            jamais crawlée : pas d'impact SEO)
//   ce code (masterPage)   → lit wixLocation.query, écrit dans les champs
//                            cachés via setFieldValues() — même rail que le
//                            page_source de public/faq-system.js
//   form-webhook v12       → lit field:cooked_aid / field:cooked_sid (inchangé)
//   form_submits_attributed() → méthode hidden_field (~95 % attendu)
//
// Pré-requis côté éditeur de formulaires : chaque Wix Form doit avoir les
// 2 champs cachés avec pour CLÉ exacte (onglet Avancé) `cooked_aid` et
// `cooked_sid`. Présents sur « Prise de contact site-web » ; ajoutés sur
// « Formulaire Divorce » le 11/06/2026.
// ============================================================================
import wixLocation from 'wix-location';

const COOKED_DEBUG = false; // chaîne vérifiée le 11/06/2026 (1re attribution hidden_field) — T-17 : off ; la CI refuse `= true`

$w.onReady(() => {
  seedCookedIds();
  // Les forms V2 peuvent se rendre après l'onReady : retry court borné.
  let tries = 0;
  const timer = setInterval(() => {
    seedCookedIds();
    if (++tries >= 5) clearInterval(timer);
  }, 2000);
  // Nav SPA : re-seed après le replaceState du tracker sur la nouvelle page.
  wixLocation.onChange(() => setTimeout(seedCookedIds, 500));
});

function seedCookedIds() {
  const q = wixLocation.query || {};
  const aid = q.cooked_aid || null;
  const sid = q.cooked_sid || null;
  if (COOKED_DEBUG) console.log('[cooked] seed — aid:', aid, '| sid:', sid);
  if (!aid && !sid) return; // tracker pas encore passé (ou très vieux navigateur)

  const values = {};
  if (aid) values.cooked_aid = aid;
  if (sid) values.cooked_sid = sid;

  cookedForms().forEach((form) => {
    try {
      form.setFieldValues(values);
    } catch (e) {
      if (COOKED_DEBUG) console.log('[cooked] setFieldValues KO:', e.message);
    }
  });
}

function cookedForms() {
  const out = [];
  // 1. L'ID posé sur les pages expertise / honoraires (cf. faq-system.js).
  try {
    const f = $w('#contactForm');
    if (f && f.id !== undefined) out.push(f);
  } catch (e) {}
  // 2. Tous les forms V2 de la page, par type (ex. Formulaire Divorce).
  ['WixFormsV2', 'Form'].forEach((type) => {
    try {
      const sel = $w(type);
      const arr = Array.isArray(sel) ? sel : (sel && sel.id !== undefined ? [sel] : []);
      arr.forEach((f) => {
        if (!out.some((o) => o.id === f.id)) out.push(f);
      });
    } catch (e) {}
  });
  if (COOKED_DEBUG) console.log('[cooked] forms trouvés:', out.length);
  return out;
}
