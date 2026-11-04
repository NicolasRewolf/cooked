SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '45s';
-- Même déduplication, recherche indexée du clic plus ancien de la même seconde.
CREATE INDEX IF NOT EXISTS idx_events_click_dedup
ON public.events(session_id,name,date_trunc('second',occurred_at AT TIME ZONE 'UTC'),id)
WHERE name IN ('cta_phone_click','cta_booking_click','cta_anchor_click','click_internal','click_outbound');
CREATE OR REPLACE VIEW public.events_human WITH (security_invoker=true) AS
 SELECT id, anonymous_id, session_id, name, url, path, hostname, title, referrer,
    referrer_hostname, utm_source, utm_medium, utm_campaign, utm_term, utm_content,
    user_agent, device_type, os, browser, viewport_width, viewport_height,
    props, occurred_at, received_at
   FROM events_no_bots e
  WHERE NOT (EXISTS ( SELECT 1
           FROM noise_sessions n
          WHERE n.session_id = e.session_id))
    AND NOT (name = 'cta_anchor_click'::text AND cooked_is_chrome_anchor(props))
    AND NOT ((name = ANY (ARRAY['cta_phone_click'::text, 'cta_booking_click'::text, 'cta_anchor_click'::text, 'click_internal'::text, 'click_outbound'::text]))
      AND (EXISTS ( SELECT 1
           FROM events_main d
          WHERE d.name IN ('cta_phone_click','cta_booking_click','cta_anchor_click','click_internal','click_outbound')
            AND d.session_id = e.session_id AND d.name = e.name
            AND NOT d.path IS DISTINCT FROM e.path
            AND date_trunc('second', d.occurred_at AT TIME ZONE 'UTC') = date_trunc('second', e.occurred_at AT TIME ZONE 'UTC')
            AND NOT (d.props ->> 'anchor'::text) IS DISTINCT FROM (e.props ->> 'anchor'::text)
            AND d.id < e.id)));
