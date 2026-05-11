// COOKED — masterPage.js
// =====================================================================
// Captures Wix Form submissions site-wide and fires a `form_submit` event
// to the Cooked tracking pipeline (same /_functions/track endpoint as
// tracker.html).
//
// Where to paste this:
//   Wix Studio → Code → Page Code → masterPage.js
//   (or merge into your existing masterPage.js if you already have one)
//
// What this does:
//   - On every page load, finds every Wix Form on the page
//   - Attaches `onWixFormSubmitted` handler to each
//   - When a form is successfully submitted (validation passed), sends a
//     `form_submit` event to the same Velo proxy used by tracker.html
//   - Reuses the session_id from sessionStorage (set by tracker.html)
//     so the form_submit ties back to the visitor's session
//
// What this does NOT do:
//   - Does NOT capture failed submissions / validation errors
//     (Wix's onWixFormSubmitted only fires on success — exactly what we want)
//   - Does NOT capture form field values (privacy-first, only metadata)
//   - Does NOT depend on specific form IDs — works for any Wix Form added
//     to any page
//
// Privacy:
//   - No form field values are captured. Only: form ID, page path,
//     session_id (already managed by tracker.html), timestamp.
//   - Same RGPD-exempt posture as the rest of Cooked.

$w.onReady(() => {
  // Iterate over every component on the page and find those that expose
  // the `onWixFormSubmitted` API. This works for Wix Forms V1 and V2
  // without needing to hardcode form IDs.
  const candidates = [
    'Form',           // Wix Forms generic type
    'WixForms',       // legacy
    'StyledFormView'  // Wix Studio
  ];

  let attached = 0;
  candidates.forEach((selector) => {
    let elements;
    try {
      elements = $w(selector);
    } catch (e) {
      return;
    }
    if (!elements) return;
    const list = Array.isArray(elements) ? elements : [elements];
    list.forEach((el) => {
      if (el && typeof el.onWixFormSubmitted === 'function') {
        try {
          el.onWixFormSubmitted((event) => emitFormSubmit(el, event));
          attached++;
        } catch (e) {
          // silent — element may not support the hook
        }
      }
    });
  });

  // Fallback: attach via DOM-level submit listener if no Wix Form was
  // found through the API. Works for custom HTML forms embedded via
  // Wix Custom Code.
  if (attached === 0) {
    try {
      document.querySelectorAll('form').forEach((form) => {
        form.addEventListener('submit', () => {
          emitFormSubmit({ id: form.id || form.name || 'html-form' }, null);
        });
      });
    } catch (e) {
      // silent
    }
  }
});

function emitFormSubmit(form, event) {
  try {
    const payload = {
      name: 'form_submit',
      url: location.href,
      path: location.pathname || '/',
      title: document.title || null,
      referrer: document.referrer || null,
      occurred_at: new Date().toISOString(),
      viewport_width: window.innerWidth || 0,
      viewport_height: window.innerHeight || 0,
      utm_source: getUtm('utm_source'),
      utm_medium: getUtm('utm_medium'),
      utm_campaign: getUtm('utm_campaign'),
      utm_term: getUtm('utm_term'),
      utm_content: getUtm('utm_content'),
      props: {
        form_id: (form && form.id) ? String(form.id) : 'unknown',
        page_source: location.pathname || '/'
      }
    };

    // Reuse tracker.html's session_id (set in sessionStorage as `_ckd`)
    try {
      const raw = sessionStorage.getItem('_ckd');
      if (raw) {
        const s = JSON.parse(raw);
        if (s && s.id) payload.session_id = s.id;
      }
    } catch (e) {
      // session_id will be rejected by the Edge Function but other
      // tracking continues — fail safe
    }

    if (!payload.session_id) {
      // tracker.html should have set this; if not, skip the event
      // (the Edge Function rejects events without session_id anyway)
      return;
    }

    const body = JSON.stringify(payload);

    // Prefer sendBeacon — survives page unload (e.g. form submit redirects)
    if (navigator.sendBeacon) {
      try {
        const blob = new Blob([body], { type: 'application/json' });
        if (navigator.sendBeacon('/_functions/track', blob)) return;
      } catch (e) {}
    }

    fetch('/_functions/track', {
      method: 'POST',
      keepalive: true,
      headers: { 'content-type': 'application/json' },
      body
    });
  } catch (e) {
    // never let tracking break the form submission UX
  }
}

function getUtm(key) {
  try {
    const params = new URLSearchParams(location.search);
    return params.get(key) || null;
  } catch (e) {
    return null;
  }
}
