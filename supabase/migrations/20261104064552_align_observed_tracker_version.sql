-- Le HTML public et toutes les pages vues des dernières 24 h ont été vérifiés
-- le 04/11/2026 : sprint43. Ne pas écraser une version attendue plus récente.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.cooked_config WHERE key='expected_tracker_version' AND value='sprint42')
     AND (SELECT e.props->>'_v' FROM public.events e
          WHERE e.name='pageview' AND e.occurred_at>=now()-interval '24 hours'
          GROUP BY e.props->>'_v' ORDER BY count(*) DESC LIMIT 1)='sprint43' THEN
    UPDATE public.cooked_config SET value='sprint43',updated_at=now()
      WHERE key='expected_tracker_version' AND value='sprint42';
    UPDATE public.alerts SET acked=true
      WHERE NOT acked AND kind='tracker_drift'
        AND detail LIKE '%majoritaire 24h = sprint43, attendu sprint42%';
  END IF;
END $$;
