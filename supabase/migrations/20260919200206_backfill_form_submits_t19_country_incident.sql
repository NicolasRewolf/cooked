-- Incident T-19 (04-19/09/2026) : le bundle form-webhook v23 écrivait
-- encore events.country après la suppression de cette colonne. Le prospect
-- CRM était inséré avant l'événement analytics, ce qui permet de reconstruire
-- les form_submit sans relire ni recopier aucune PII.
--
-- Périmètre gelé : de la migration T-19 au déploiement du webhook v24
-- (19/09/2026 19:47:06 UTC). Les submission_id Wix réels sont la seule clé
-- de réconciliation ; aucune déduplication temporelle ou par email.

DO $$
DECLARE
  v_start CONSTANT timestamptz := TIMESTAMPTZ '2026-09-03 22:00:00+00';
  v_end   CONSTANT timestamptz := TIMESTAMPTZ '2026-09-19 19:47:06+00';
  v_source_count integer;
  v_uuid_count integer;
  v_existing_count integer;
  v_inserted_count integer;
  v_final_count integer;
  v_macro_count integer;
  v_recruitment_count integer;
  v_pii_leak_count integer;
BEGIN
  SELECT
    count(*),
    count(*) FILTER (
      WHERE p.wix_submission_id ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    )
  INTO v_source_count, v_uuid_count
  FROM public.crm_prospects p
  WHERE p.source = 'form'
    AND p.occurred_at >= v_start
    AND p.occurred_at < v_end;

  IF v_source_count <> 33 OR v_uuid_count <> 33 THEN
    RAISE EXCEPTION
      'Backfill form_submit T-19 annulé : attendu 33 prospects / 33 UUID Wix, trouvé % / %',
      v_source_count, v_uuid_count;
  END IF;

  SELECT count(*)
  INTO v_existing_count
  FROM public.crm_prospects p
  JOIN public.events e
    ON e.name = 'form_submit'
   AND e.props ->> 'submission_id' = p.wix_submission_id
  WHERE p.source = 'form'
    AND p.occurred_at >= v_start
    AND p.occurred_at < v_end;

  INSERT INTO public.events (
    anonymous_id,
    session_id,
    name,
    url,
    path,
    hostname,
    title,
    referrer,
    referrer_hostname,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    user_agent,
    device_type,
    os,
    browser,
    viewport_width,
    viewport_height,
    props,
    occurred_at,
    received_at
  )
  SELECT
    'webhook-' || p.wix_submission_id,
    'webhook-' || p.wix_submission_id,
    'form_submit',
    CASE
      WHEN p.page_source_path IS NULL THEN NULL
      ELSE 'https://www.jplouton-avocat.fr' ||
        CASE
          WHEN left(p.page_source_path, 1) = '/' THEN p.page_source_path
          ELSE '/' || p.page_source_path
        END
    END,
    p.page_source_path,
    CASE
      WHEN p.page_source_path IS NULL THEN NULL
      ELSE 'www.jplouton-avocat.fr'
    END,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    'Wix-Automation-Webhook',
    'server',
    NULL,
    NULL,
    NULL,
    NULL,
    jsonb_build_object(
      'form_id', coalesce(nullif(btrim(p.form_id), ''), 'wix-form-webhook'),
      'submission_id', p.wix_submission_id,
      'page_source', p.page_source_path,
      'objet_de_ma_demande', p.objet,
      'counts_as_macro',
        public.form_submit_counts_as_macro(
          jsonb_build_object('objet_de_ma_demande', p.objet)
        ),
      'cooked_aid', p.cooked_aid,
      'cooked_sid', p.cooked_sid,
      'capture_source', 'wix-backfill',
      'payload_meta', jsonb_build_object(
        'backfill', 'incident T-19 form-webhook v23 (04-19/09/2026)',
        'source', 'crm_prospects'
      )
    ),
    p.occurred_at,
    p.created_at
  FROM public.crm_prospects p
  WHERE p.source = 'form'
    AND p.occurred_at >= v_start
    AND p.occurred_at < v_end
    AND NOT EXISTS (
      SELECT 1
      FROM public.events e
      WHERE e.name = 'form_submit'
        AND e.props ->> 'submission_id' = p.wix_submission_id
    )
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_inserted_count = ROW_COUNT;

  SELECT
    count(*),
    count(*) FILTER (WHERE public.form_submit_counts_as_macro(e.props)),
    count(*) FILTER (WHERE NOT public.form_submit_counts_as_macro(e.props)),
    count(*) FILTER (
      WHERE e.props ?| ARRAY[
        'nom', 'prenom', 'email', 'telephone', 'message'
      ]
    )
  INTO
    v_final_count,
    v_macro_count,
    v_recruitment_count,
    v_pii_leak_count
  FROM public.crm_prospects p
  JOIN public.events e
    ON e.name = 'form_submit'
   AND e.props ->> 'submission_id' = p.wix_submission_id
  WHERE p.source = 'form'
    AND p.occurred_at >= v_start
    AND p.occurred_at < v_end;

  IF v_inserted_count <> 33 - v_existing_count
     OR v_final_count <> 33
     OR v_macro_count <> 27
     OR v_recruitment_count <> 6
     OR v_pii_leak_count <> 0 THEN
    RAISE EXCEPTION
      'Backfill form_submit T-19 annulé : existing %, inserted %, final %, macro %, recrutement %, PII %',
      v_existing_count,
      v_inserted_count,
      v_final_count,
      v_macro_count,
      v_recruitment_count,
      v_pii_leak_count;
  END IF;

  INSERT INTO public.annotations (day, kind, label, paths)
  SELECT
    DATE '2026-09-19',
    'autre',
    'Incident form-webhook T-19 : 33 form_submit du 05 au 18/09 rétablis depuis crm_prospects (27 contacts macro, 6 candidatures), sans PII. Les indicateurs de conversion de cette période sont restatés à la hausse ; ce rattrapage ne représente pas une hausse de demande le 19/09.',
    NULL
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.annotations a
    WHERE a.day = DATE '2026-09-19'
      AND a.label LIKE 'Incident form-webhook T-19 : 33 form_submit%'
  );
END $$;
