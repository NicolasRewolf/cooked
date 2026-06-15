-- 16/06/2026 — backfill rétroactif : décode les target_path des click_internal
-- historiques (URL-encodés faute de canonicalPath côté Edge avant le fix v22 du
-- 16/06). Applique exactement la même canonicalisation que l'Edge v22 :
-- canonical_path(url_decode(...)) = decode → NFC → strip trailing slash.
-- Ne cible que les valeurs contenant une séquence %XX (idempotent : après
-- décodage il n'y a plus de %XX, donc rejouer ne re-décode pas).
-- Périmètre vérifié : 143 lignes (03/06→16/06), 0 restant encodé après coup.
-- Seul props.target_path est touché ; href/anchor/placement inchangés
-- (cohérent avec le fix Edge track v22).
UPDATE events
SET props = jsonb_set(props, '{target_path}',
                      to_jsonb(canonical_path(url_decode(props->>'target_path'))))
WHERE name = 'click_internal'
  AND props->>'target_path' ~ '%[0-9A-Fa-f]{2}';
