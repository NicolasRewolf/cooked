-- ============================================================================
-- Pont SECIB — fondations (10/08/2026)
--
-- Décision produit (Nicolas, 10/08/2026) : Cooked reçoit EN CLAIR
-- nom / prénom / email / téléphone des prospects web afin de les rapprocher
-- des dossiers SECIB (réellement ouverts / facturés ou non).
-- Le hachage a été proposé et explicitement refusé — rapprochement lisible.
--
-- Garde-fous techniques :
--   * la PII vit UNIQUEMENT dans crm_prospects + secib_dossiers,
--     RLS deny-all (aucune policy) + REVOKE anon/authenticated :
--     seuls service_role et les rôles admin y accèdent.
--   * events / events_human / RPCs analytics restent 100 % sans PII.
--   * traitement à inscrire au registre RGPD du cabinet + mention dans la
--     politique de confidentialité du site (action Nicolas, cf. session).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Normalisation des clés de matching (immutables : utilisées en colonnes
-- générées). Téléphone : sortie E.164 FR (+33XXXXXXXXX) quand reconnaissable.
-- ---------------------------------------------------------------------------
create or replace function cooked_normalize_email(raw text)
returns text
language sql immutable parallel safe
as $$
  select nullif(lower(regexp_replace(coalesce(raw, ''), '\s', '', 'g')), '')
$$;

comment on function cooked_normalize_email(text) is
  'Pont SECIB — email minuscule sans espaces, NULL si vide. Clé de matching prospect↔dossier.';

create or replace function cooked_normalize_phone_fr(raw text)
returns text
language sql immutable parallel safe
as $$
  select case
    when d = '' then null
    when d like '0033%' and length(d) = 13 then '+33' || substr(d, 5)
    when d like '33%'   and length(d) = 11 then '+' || d
    when d like '0%'    and length(d) = 10 then '+33' || substr(d, 2)
    when length(d) between 8 and 15 then '+' || d
    else null
  end
  from (select regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g') as d) t
$$;

comment on function cooked_normalize_phone_fr(text) is
  'Pont SECIB — téléphone réduit aux chiffres puis E.164 FR (+33…) quand la forme est reconnaissable. Clé de matching prospect↔dossier.';

-- ---------------------------------------------------------------------------
-- crm_prospects — une row par prise de contact web identifiée (source form
-- aujourd''hui ; call viendra du chantier 3CX). Alimentée par form-webhook v13.
-- ---------------------------------------------------------------------------
create table crm_prospects (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null,
  source text not null default 'form' check (source in ('form', 'call', 'autre')),
  form_id text,
  wix_submission_id text,
  objet text,
  page_source_path text,
  cooked_aid text,
  cooked_sid text,
  nom text,
  prenom text,
  email text,
  telephone text,
  email_norm text generated always as (cooked_normalize_email(email)) stored,
  tel_norm text generated always as (cooked_normalize_phone_fr(telephone)) stored,
  fields_keys text[] not null default '{}',
  created_at timestamptz not null default now()
);

comment on table crm_prospects is
  'PII EN CLAIR (décision Nicolas 10/08/2026) — prospects web pour rapprochement SECIB. Accès service_role uniquement (RLS deny-all). Registre RGPD à tenir à jour.';
comment on column crm_prospects.fields_keys is
  'Clés field:* du payload Wix (diagnostic des trous d''extraction) — jamais les valeurs.';

create unique index crm_prospects_wix_submission_uq
  on crm_prospects (wix_submission_id)
  where wix_submission_id is not null;
create index crm_prospects_email_norm_idx on crm_prospects (email_norm);
create index crm_prospects_tel_norm_idx on crm_prospects (tel_norm);

alter table crm_prospects enable row level security;
revoke all on crm_prospects from anon, authenticated;

-- ---------------------------------------------------------------------------
-- secib_dossiers — miroir minimal des dossiers SECIB avec identité du premier
-- client (clés de matching). Alimentée par scripts/secib_ingest.py.
-- env='test' : cabinet bac à sable Septeo ; env='prod' : cabinet Plouton
-- (après signature du devis SECIB+).
-- ---------------------------------------------------------------------------
create table secib_dossiers (
  env text not null default 'test' check (env in ('test', 'prod')),
  dossier_id integer not null,
  code text,
  date_creation timestamptz,
  date_modification timestamptz,
  matiere_id integer,
  matiere_libelle text,
  etat_facturable text,
  type_dossier text,
  is_archive boolean,
  client_personne_id integer,
  client_type text,
  client_nom text,
  client_prenom text,
  client_emails text[] not null default '{}',
  client_telephones text[] not null default '{}',
  client_emails_norm text[] not null default '{}',
  client_tels_norm text[] not null default '{}',
  facture_total_ht numeric,
  premiere_facture date,
  derniere_facture date,
  synced_at timestamptz not null default now(),
  primary key (env, dossier_id)
);

comment on table secib_dossiers is
  'PII EN CLAIR (décision Nicolas 10/08/2026) — dossiers SECIB + identité premier client pour rapprochement prospects. Accès service_role uniquement (RLS deny-all). Ne JAMAIS y stocker davantage que nom/prénom/coordonnées (pas de n° sécu, pas de contenu de dossier).';

create index secib_dossiers_emails_norm_idx
  on secib_dossiers using gin (client_emails_norm);
create index secib_dossiers_tels_norm_idx
  on secib_dossiers using gin (client_tels_norm);
create index secib_dossiers_date_creation_idx
  on secib_dossiers (date_creation);

alter table secib_dossiers enable row level security;
revoke all on secib_dossiers from anon, authenticated;

-- ---------------------------------------------------------------------------
-- pont_prospects_dossiers — LA vue de lecture du pont : chaque prospect avec
-- son meilleur dossier apparié (email prioritaire, sinon téléphone), statut
-- converti / client_existant / non_converti, délai en jours.
-- security_invoker : hérite du RLS deny-all des tables → service_role only.
-- ---------------------------------------------------------------------------
create view pont_prospects_dossiers
with (security_invoker = true) as
select
  p.id              as prospect_id,
  p.occurred_at     as prospect_le,
  p.source,
  p.form_id,
  p.objet,
  p.page_source_path,
  p.cooked_aid,
  p.cooked_sid,
  p.nom,
  p.prenom,
  p.email,
  p.telephone,
  d.env             as secib_env,
  d.dossier_id,
  d.code            as dossier_code,
  d.date_creation   as dossier_cree_le,
  d.matiere_libelle,
  d.etat_facturable,
  d.facture_total_ht,
  case
    when d.dossier_id is null then 'non_converti'
    when d.date_creation >= p.occurred_at - interval '7 days' then 'converti'
    else 'client_existant'
  end as statut,
  case when d.dossier_id is not null
    then round((extract(epoch from (d.date_creation - p.occurred_at)) / 86400.0)::numeric, 1)
  end as delai_jours,
  case
    when p.email_norm is not null and p.email_norm = any (d.client_emails_norm) then 'email'
    when p.tel_norm  is not null and p.tel_norm  = any (d.client_tels_norm)  then 'telephone'
  end as cle_match
from crm_prospects p
left join lateral (
  select dd.*
  from secib_dossiers dd
  where (p.email_norm is not null and p.email_norm = any (dd.client_emails_norm))
     or (p.tel_norm  is not null and p.tel_norm  = any (dd.client_tels_norm))
  order by abs(extract(epoch from (dd.date_creation - p.occurred_at))) asc nulls last
  limit 1
) d on true;

comment on view pont_prospects_dossiers is
  'Pont SECIB — prospects web ↔ meilleur dossier apparié (email > téléphone). statut : converti (dossier ouvert après le contact, tolérance -7 j) / client_existant / non_converti. PII en clair, accès service_role uniquement.';

revoke all on pont_prospects_dossiers from anon, authenticated;
