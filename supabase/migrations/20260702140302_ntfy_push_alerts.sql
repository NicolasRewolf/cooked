-- T-11 (audit 02/07/2026) — alertes push vers téléphone via ntfy.sh.
-- Quand raise_cooked_alert INSÈRE réellement (pas dédupliqué) une alerte
-- severity='critical' ET que cooked_config.ntfy_topic est non-vide, POSTer le
-- detail via pg_net vers ntfy.sh (publication JSON native : topic + message
-- dans le body, car ntfy N'A PAS de header pour le message).
-- INERTE tant que ntfy_topic est vide (placeholder '' ci-dessous). Le POST ne
-- peut JAMAIS faire échouer la fonction ni changer son retour (0/1) : bloc
-- BEGIN/EXCEPTION imbriqué, l'insert de l'alerte prime. pg_net async → 0 latence.
-- Vérifié : pg_net 0.20.0 activé (net.http_post), raise_cooked_alert renvoie
-- 1 puis 0 (dédup préservée), aucun POST tant que topic vide.

CREATE EXTENSION IF NOT EXISTS pg_net;

-- Placeholder vide = inerte. Nicolas activera via :
--   UPDATE public.cooked_config SET value='<topic>', updated_at=now() WHERE key='ntfy_topic';
INSERT INTO public.cooked_config (key, value)
VALUES ('ntfy_topic', '')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.raise_cooked_alert(p_kind text, p_sev text, p_detail text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_topic text;
begin
  -- Dédup : identique à l'existant, comportement inchangé.
  if exists (
    select 1 from public.alerts
    where kind = p_kind and not acked
      and created_at > now() - interval '24 hours'
  ) then
    return 0;
  end if;

  insert into public.alerts (kind, severity, detail) values (p_kind, p_sev, p_detail);

  -- Push ntfy : uniquement sur un VRAI insert + severity critical + topic non-vide.
  -- Entièrement défensif : toute erreur est avalée, l'alerte reste posée, retour = 1.
  if p_sev = 'critical' then
    begin
      select nullif(btrim(value), '') into v_topic
      from public.cooked_config where key = 'ntfy_topic';

      if v_topic is not null then
        perform net.http_post(
          url     := 'https://ntfy.sh/',
          body    := jsonb_build_object(
                       'topic',    v_topic,
                       'title',    'Cooked : alerte critique',
                       'message',  left(coalesce(p_detail, p_kind), 4000),
                       'priority', 5,
                       'tags',     jsonb_build_array('rotating_light')
                     ),
          headers := '{"Content-Type": "application/json"}'::jsonb
        );
      end if;
    exception when others then
      null; -- ne jamais laisser le push casser l'alerte
    end;
  end if;

  return 1;
end;
$function$;

revoke execute on function public.raise_cooked_alert(text,text,text) from public, anon, authenticated;
grant  execute on function public.raise_cooked_alert(text,text,text) to service_role;
