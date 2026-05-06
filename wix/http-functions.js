// ============================================================
// COOKED — Wix Velo proxy
// ============================================================
// Path in your Wix Studio editor: backend/http-functions.js
// (create the file via Velo "Add file" if it doesn't exist yet)
//
// Exposes:
//   POST    https://www.jplouton-avocat.fr/_functions/track
//   OPTIONS https://www.jplouton-avocat.fr/_functions/track
//
// Wix dev URL (until publish): https://www.jplouton-avocat.fr/_functions-dev/track
//
// Why this proxy:
//   1. Same-origin endpoint  → 100% bypass of adblockers
//   2. The Supabase URL & service-role key stay server-side (never reach the
//      browser).
//
// Required Velo Secrets (Velo sidebar → Secrets Manager):
//   SUPABASE_TRACK_URL       e.g. https://xxxx.supabase.co/functions/v1/track
//   SUPABASE_SERVICE_KEY     the secret_key (sb_secret_…) from Supabase Dashboard
//                            → Settings → API
// ============================================================

import { fetch } from 'wix-fetch';
import { getSecret } from 'wix-secrets-backend';
import { ok, response, badRequest, serverError } from 'wix-http-functions';

const ALLOWED_ORIGIN = 'https://www.jplouton-avocat.fr';

const corsHeaders = {
  'Access-Control-Allow-Origin': ALLOWED_ORIGIN,
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'content-type',
  'Access-Control-Max-Age': '86400',
  'Vary': 'Origin',
};

export function options_track(/* request */) {
  return response({
    status: 204,
    headers: corsHeaders,
    body: '',
  });
}

export async function post_track(request) {
  try {
    // Same-origin sanity check
    const origin = (request.headers && (request.headers.origin || request.headers.referer)) || '';
    if (origin && !origin.startsWith(ALLOWED_ORIGIN)) {
      return response({
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify({ ok: false, error: 'forbidden_origin' }),
      });
    }

    const [supabaseUrl, supabaseKey] = await Promise.all([
      getSecret('SUPABASE_TRACK_URL'),
      getSecret('SUPABASE_SERVICE_KEY'),
    ]);

    const body = await request.body.text();
    if (!body || body.length > 60_000) {
      return badRequest({
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify({ ok: false, error: 'invalid_body' }),
      });
    }

    // Forward client IP & UA so Edge Function can hash/parse them server-side.
    const fwd =
      (request.headers && (
        request.headers['x-forwarded-for'] ||
        request.headers['x-real-ip'] ||
        request.ip
      )) || '';
    const ua = (request.headers && request.headers['user-agent']) || '';

    const upstream = await fetch(supabaseUrl, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'apikey': supabaseKey,
        'authorization': `Bearer ${supabaseKey}`,
        'x-forwarded-for': fwd,
        'user-agent': ua,
      },
      body,
    });

    const text = await upstream.text();

    return response({
      status: upstream.status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      body: text || JSON.stringify({ ok: upstream.ok }),
    });
  } catch (err) {
    console.error('cooked proxy error', err && err.message ? err.message : err);
    return serverError({
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      body: JSON.stringify({ ok: false, error: 'proxy_error' }),
    });
  }
}
