// COOKED — attribution des formulaires (à coller dans masterPage.js)
// ============================================================================
// Wix Forms V2 ne rend pas les champs cachés dans le DOM de la page publiée
// (vérifié en prod le 11/06/2026) : le tracker ne peut pas les remplir.
// Chaîne d'attribution :
//   tracker (Custom Code)  → expose cooked_aid/cooked_sid en query params
//                            via history.replaceState
//   ce code (masterPage)   → lit wixLocation.query, écrit dans les champs
//                            cachés via setFieldValues() — même rail que le
//                            page_source de public/faq-system.js
//   form-webhook          → conserve les identifiants explicites dans l'événement
//                            pour le rapprochement avec une visite observable
//
// Pré-requis côté éditeur de formulaires : chaque Wix Form doit avoir les
// 2 champs cachés avec pour CLÉ exacte (onglet Avancé) `cooked_aid` et
// `cooked_sid`. Présents sur « Prise de contact site-web » ; ajoutés sur
// « Formulaire Divorce » le 11/06/2026.
// ============================================================================
import wixLocation from 'wix-location';

const COOKED_DEBUG = false; // la CI refuse `= true` pour ne pas exposer les identifiants en console

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

  // T-18 (04/09/2026) : page_source seedé ici aussi (chemin courant, sans query) — pour les
  // formulaires qui ont le champ caché `page_source` sans passer par faq-system.js
  // (« Formulaire Divorce », « Demande dossier en cours » : 100 % sans page_source sur 180 j).
  // Appel séparé : un champ absent ne doit pas faire échouer le seed des ids.
  const pageSource = '/' + ((wixLocation.path || []).join('/'));

  cookedForms().forEach((form) => {
    try {
      form.setFieldValues(values);
    } catch (e) {
      if (COOKED_DEBUG) console.log('[cooked] setFieldValues KO:', e.message);
    }
    try {
      form.setFieldValues({ page_source: pageSource });
    } catch (e) {
      if (COOKED_DEBUG) console.log('[cooked] page_source non seedé (champ absent ?):', e.message);
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
