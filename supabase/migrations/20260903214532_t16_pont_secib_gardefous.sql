-- T-16 (mission 02/09/2026, #117) — pont SECIB : garde-fous avant le premier chiffre.
-- Constats e-01 (P1), c-08, e-03, e-04, e-05/c-07, e-08. Invariant I12. Pré-prod : devis SECIB non signé,
-- aucune préparation de credentials.
--
-- Mesure avant (04/09/2026 00:20 Paris, agrégats seuls) :
--   · crm_prospects : 858 lignes, 0 sans clé (email_norm), 765 personnes distinctes (email_norm),
--     2 doublons (email, minute) — récidive e-04 : l'import CSV ignorait les lignes du webhook.
--   · secib_dossiers : 49 lignes, TOUTES env='test' (bac à sable Septeo), 41/49 sans aucune clé.
--   · pont_prospects_dossiers : 858/858 « non_converti » — la vue ne distinguait pas « rapproché sans
--     dossier » de « irrapprochable », mélangeait les envs, ne priorisait pas l'email sur le téléphone,
--     n'avait pas de borne haute sur « converti », comptait un dossier N fois par email dupliqué.
--   · cooked_normalize_phone_fr('+33 (0)6 12 34 56 78') → '+33061234567' (faux, des deux côtés).
--
-- Changement :
--   1. cooked_normalize_phone_fr v2 : « (0) » après l'indicatif (330…/00330…) ; miroir Python + vecteurs
--      partagés contracts/normalize_vectors.json (Python en CI ingest, SQL en CI prod-drift).
--   2. pont_prospects_dossiers_env(p_env) — UNE implémentation ; la vue pont_prospects_dossiers = env 'prod'
--      (le bac à sable ne se rapproche jamais des vrais prospects). Statuts : non_rapprochable (prospect sans
--      clé) / non_converti / converti (dossier dans [-7 j ; +180 j]) / client_existant (avant) /
--      dossier_ulterieur (après +180 j). Priorité email > téléphone, puis proximité temporelle.
--      personne_key + rang_personne (compter des personnes), rang_dossier (un dossier crédité une fois).
--   3. pont_couverture : part des dossiers et des prospects porteurs d'une clé, par env — à lire AVANT
--      tout taux (règle CLAUDE.md).
--   4. contract-tests : pont_test_jamais_dans_prod (= 0), normalize_phone_vecteurs (= 0 écart),
--      crm_prospects_doublons_email_minute (pas de nouveau doublon au-delà des 2 connus — nettoyage = décision Nicolas).
-- Pas d'index unique fonctionnel (plan) : 2 doublons existants l'empêchent sans DELETE — décision Nicolas.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Normalisation téléphone v2
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cooked_normalize_phone_fr(raw text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select case
    when d = '' then null
    -- T-16 (e-05) : « +33 (0)6 … » / « 00 33 (0)6 … » — le (0) après l'indicatif
    when d like '00330%' and length(d) = 14 then '+33' || substr(d, 6)
    when d like '330%'   and length(d) = 12 then '+33' || substr(d, 4)
    when d like '0033%'  and length(d) = 13 then '+33' || substr(d, 5)
    when d like '33%'    and length(d) = 11 then '+' || d
    when d like '0%'     and length(d) = 10 then '+33' || substr(d, 2)
    when length(d) between 8 and 15 then '+' || d
    else null
  end
  from (select regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g') as d) t
$function$;

GRANT EXECUTE ON FUNCTION public.cooked_normalize_phone_fr(text) TO cooked_ci_ro;
GRANT EXECUTE ON FUNCTION public.cooked_normalize_email(text) TO cooked_ci_ro;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Le pont : une fonction, une vue (prod)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pont_prospects_dossiers_env(p_env text DEFAULT 'prod')
 RETURNS TABLE(prospect_id bigint, prospect_le timestamptz, source text, form_id text, objet text,
               page_source_path text, cooked_aid text, cooked_sid text, nom text, prenom text, email text,
               telephone text, secib_env text, dossier_id integer, dossier_code text, dossier_cree_le timestamptz,
               matiere_libelle text, etat_facturable text, facture_total_ht numeric, statut text,
               delai_jours numeric, cle_match text, personne_key text, rang_personne integer, rang_dossier integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH base AS (
    SELECT p.id AS prospect_id, p.occurred_at AS prospect_le, p.source, p.form_id, p.objet, p.page_source_path,
           p.cooked_aid, p.cooked_sid, p.nom, p.prenom, p.email, p.telephone,
           p.email_norm, p.tel_norm,
           d.env AS secib_env, d.dossier_id, d.code AS dossier_code, d.date_creation AS dossier_cree_le,
           d.matiere_libelle, d.etat_facturable, d.facture_total_ht,
           d.cle_match
    FROM public.crm_prospects p
    LEFT JOIN LATERAL (
      SELECT dd.env, dd.dossier_id, dd.code, dd.date_creation, dd.matiere_libelle, dd.etat_facturable,
             dd.facture_total_ht,
             CASE WHEN p.email_norm IS NOT NULL AND p.email_norm = ANY (dd.client_emails_norm) THEN 'email'
                  ELSE 'telephone' END AS cle_match
      FROM public.secib_dossiers dd
      WHERE dd.env = p_env
        AND ((p.email_norm IS NOT NULL AND p.email_norm = ANY (dd.client_emails_norm))
          OR (p.tel_norm IS NOT NULL AND p.tel_norm = ANY (dd.client_tels_norm)))
      -- priorité : email > téléphone, puis le dossier le plus proche dans le temps
      ORDER BY (p.email_norm IS NOT NULL AND p.email_norm = ANY (dd.client_emails_norm)) DESC,
               abs(extract(epoch FROM dd.date_creation - p.occurred_at))
      LIMIT 1
    ) d ON true
  )
  SELECT b.prospect_id, b.prospect_le, b.source, b.form_id, b.objet, b.page_source_path, b.cooked_aid, b.cooked_sid,
         b.nom, b.prenom, b.email, b.telephone, b.secib_env, b.dossier_id, b.dossier_code, b.dossier_cree_le,
         b.matiere_libelle, b.etat_facturable, b.facture_total_ht,
         CASE
           WHEN b.email_norm IS NULL AND b.tel_norm IS NULL THEN 'non_rapprochable'
           WHEN b.dossier_id IS NULL THEN 'non_converti'
           WHEN b.dossier_cree_le <  b.prospect_le - interval '7 days'   THEN 'client_existant'
           WHEN b.dossier_cree_le <= b.prospect_le + interval '180 days' THEN 'converti'
           ELSE 'dossier_ulterieur'
         END AS statut,
         CASE WHEN b.dossier_id IS NOT NULL
              THEN round(extract(epoch FROM b.dossier_cree_le - b.prospect_le) / 86400.0, 1) END AS delai_jours,
         CASE WHEN b.dossier_id IS NOT NULL THEN b.cle_match END AS cle_match,
         coalesce(b.email_norm, b.tel_norm) AS personne_key,
         row_number() OVER (PARTITION BY coalesce(b.email_norm, b.tel_norm) ORDER BY b.prospect_le, b.prospect_id)::int AS rang_personne,
         CASE WHEN b.dossier_id IS NOT NULL
              THEN row_number() OVER (PARTITION BY b.dossier_id ORDER BY abs(extract(epoch FROM b.dossier_cree_le - b.prospect_le)), b.prospect_id)::int
         END AS rang_dossier
  FROM base b
$function$;

CREATE OR REPLACE VIEW public.pont_prospects_dossiers WITH (security_invoker = true) AS
  SELECT * FROM public.pont_prospects_dossiers_env('prod');

COMMENT ON VIEW public.pont_prospects_dossiers IS
  'Pont SECIB — env prod uniquement (T-16) ; bac à sable : SELECT * FROM pont_prospects_dossiers_env(''test''). PII en clair : service_role seul. Lire pont_couverture avant tout taux ; compter les personnes avec rang_personne = 1, les dossiers avec rang_dossier = 1.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Couverture du rapprochement — à lire avant tout taux
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.pont_couverture WITH (security_invoker = true) AS
  WITH envs AS (SELECT DISTINCT env FROM public.secib_dossiers UNION SELECT 'prod'),
  d AS (
    SELECT env,
           count(*) AS dossiers,
           count(*) FILTER (WHERE coalesce(array_length(client_emails_norm, 1), 0) > 0) AS dossiers_avec_email,
           count(*) FILTER (WHERE coalesce(array_length(client_tels_norm, 1), 0) > 0)   AS dossiers_avec_tel,
           count(*) FILTER (WHERE coalesce(array_length(client_emails_norm, 1), 0) > 0
                              OR coalesce(array_length(client_tels_norm, 1), 0) > 0)     AS dossiers_avec_cle,
           max(synced_at) AS derniere_synchro
    FROM public.secib_dossiers GROUP BY env
  ),
  p AS (
    SELECT count(*) AS prospects,
           count(*) FILTER (WHERE email_norm IS NOT NULL OR tel_norm IS NOT NULL) AS prospects_avec_cle,
           count(DISTINCT coalesce(email_norm, tel_norm)) AS personnes,
           (SELECT count(*) FROM (SELECT 1 FROM public.crm_prospects WHERE email_norm IS NOT NULL
                                  GROUP BY email_norm, date_trunc('minute', occurred_at) HAVING count(*) > 1) x) AS doublons_email_minute
    FROM public.crm_prospects
  )
  SELECT e.env,
         coalesce(d.dossiers, 0) AS dossiers,
         coalesce(d.dossiers_avec_cle, 0) AS dossiers_avec_cle,
         CASE WHEN coalesce(d.dossiers, 0) > 0 THEN round(100.0 * d.dossiers_avec_cle / d.dossiers, 1) END AS dossiers_avec_cle_pct,
         coalesce(d.dossiers_avec_email, 0) AS dossiers_avec_email,
         coalesce(d.dossiers_avec_tel, 0) AS dossiers_avec_tel,
         d.derniere_synchro,
         p.prospects, p.prospects_avec_cle, p.personnes, p.doublons_email_minute,
         CASE WHEN coalesce(d.dossiers, 0) = 0 THEN 'aucun dossier ingéré dans cet env : aucun taux publiable'
              WHEN 100.0 * d.dossiers_avec_cle / d.dossiers < 80 THEN 'couverture < 80 % : tout taux est un plancher, le dire'
              ELSE 'couverture suffisante' END AS lecture
  FROM envs e LEFT JOIN d ON d.env = e.env CROSS JOIN p;

COMMENT ON VIEW public.pont_couverture IS
  'T-16 : part des dossiers SECIB et des prospects porteurs d''une clé de rapprochement, par env. Aucun taux de conversion du pont ne se publie sans cette ligne à côté.';

REVOKE ALL ON FUNCTION public.pont_prospects_dossiers_env(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pont_prospects_dossiers_env(text) TO service_role;
REVOKE ALL ON public.pont_prospects_dossiers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.pont_prospects_dossiers TO service_role;
REVOKE ALL ON public.pont_couverture FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.pont_couverture TO service_role;
