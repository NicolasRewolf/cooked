-- T-17 (audit 02/07/2026) — backfill des variantes ACCENTUÉES de
-- click_internal.target_path. L'href du site est parfois accentué alors que le
-- path réel (vu en pageview) ne l'est pas ; canonical_path (Edge) fait
-- decode+NFC mais ne translittère PAS é→e. Backfill des 8 paires UNIVOQUES
-- (accenté → path pageview réel confirmé, 98 clics events_human). Les 91 autres
-- target_path accentués (221 clics) n'ont AUCUN pageview jumeau → pas de vérité
-- terrain, laissés tels quels. Pour joindre target_path aux paths en général :
-- unaccent() des deux côtés (piège documenté dans le playbook, T-18).
-- Vérifié : restant_8_accentes=0, cible victimes-de-delits consolidée à 70 clics.
CREATE EXTENSION IF NOT EXISTS unaccent;

UPDATE public.events e
SET props = jsonb_set(e.props, '{target_path}', to_jsonb(v.pv_target))
FROM (VALUES
  ('/indemnisation-des-victimes/victimes-de-délits-ou-crimes',       '/indemnisation-des-victimes/victimes-de-delits-ou-crimes'),
  ('/défense-pénale/droit-pénal',                                     '/defense-penale/droit-penal'),
  ('/blog/categories/médias',                                        '/blog/categories/medias'),
  ('/défense-pénale/violences-conjugales-et-féminicides',            '/defense-penale/violences-conjugales-et-feminicides'),
  ('/post/contrôle-coercitif-reconnaître-agir',                      '/post/contrôle-coercitif-reconnaitre-agir'),
  ('/blog/categories/violences-conjugales-féminicides',              '/blog/categories/violences-conjugales-feminicides'),
  ('/défense-pénale/trafic-de-stupéfiant',                           '/defense-penale/trafic-de-stupefiant'),
  ('/blog/categories/trafic-de-stupéfiants',                         '/blog/categories/trafic-de-stupefiants')
) v(accente, pv_target)
WHERE e.name = 'click_internal' AND e.props->>'target_path' = v.accente;
