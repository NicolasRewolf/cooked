-- Sprint 37 (09/06/2026) — dédup des clics dupliqués par double-embed
--
-- Découverte audit live 09/06 : le snippet tracker est embarqué 2× dans le
-- Custom Code Wix → 2 instances du script → listeners empilés → events de
-- clic dupliqués à la même seconde. Mesure 28j : cta_phone_click +13,6 %
-- (15/110), cta_anchor_click +8,7 %, booking +3,2 %. form_submit intact
-- (webhook idempotent). Le tracker sprint37 ajoute un garde d'exécution
-- (window.__cookedLoaded) ; cette migration nettoie RÉTROACTIVEMENT dans
-- events_human, même philosophie que anchor_click_exclude_chrome (S35) :
-- donnée dupliquée = bruit, hors base canonique. Raw events intacts (audit).

create or replace view public.events_human
with (security_invoker = true) as
select e.*
from public.events_no_bots e
where not exists (
  select 1 from public.noise_sessions n
  where n.session_id = e.session_id
)
and not (
  e.name = 'cta_anchor_click'
  and public.cooked_is_chrome_anchor(e.props)
)
and not (
  e.name in ('cta_phone_click','cta_booking_click','cta_anchor_click','click_internal','click_outbound')
  and exists (
    select 1 from public.events d
    where d.session_id = e.session_id
      and d.name = e.name
      and d.path is not distinct from e.path
      and date_trunc('second', d.occurred_at) = date_trunc('second', e.occurred_at)
      and (d.props->>'anchor') is not distinct from (e.props->>'anchor')
      and d.id < e.id
  )
);
