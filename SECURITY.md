# Sécurité

## Signaler un problème

Contacter **Nicolas Rewolf** directement (pas d'issue publique pour les failles).
Email : via le canal habituel Rewolf Studio / cabinet.

Délai de réponse visé : 48 h ouvrées.

## Ce qui ne doit jamais entrer dans le repo

- Clés Supabase (`sb_secret_*`, `service_role`, tokens `sbp_*`)
- Credentials Google Search Console / Business Profile (service accounts JSON,
  ADC gcloud, `GBP_CREDENTIALS_B64`)
- Identifiants DataForSEO (`DFS_USERNAME`, `DFS_PASSWORD`)
- `FORM_WEBHOOK_SECRET`, `ANON_SALT`
- Fichiers `.env`, `.env.local`, `*credentials*.json`

Le `.gitignore` et la CI limitent les risques ; en cas de fuite accidentelle :
**révoquer / régénérer la clé** côté Supabase / Google / DataForSEO immédiatement.

## Où vivent les secrets

| Secret | Emplacement |
|---|---|
| GSC service account | `~/.claude/gsc-credentials.json` (local) ; `GSC_CREDENTIALS_B64` (GitHub Actions) |
| Supabase service | `SUPABASE_SECRET_KEY` (Vercel, GitHub Actions, Edge Functions) |
| Dashboard allowlist | `DASHBOARD_ALLOWED_EMAILS` (Vercel) |
| Webhook formulaires | `FORM_WEBHOOK_SECRET` (Supabase Edge + Wix Automation) |
| GBP OAuth (ADC utilisateur) | `~/.config/gcloud/application_default_credentials.json` (local) ; `GBP_CREDENTIALS_B64` (GitHub Actions) — reauth Google périodique, cf. `scripts/gbp_ingest.py` |

Modèle sans valeurs : [.env.example](.env.example).

## Surface d'attaque

- **Edge Functions** `track` / `form-webhook` : auth par clé service (proxy Velo)
  et token webhook ; pas d'accès `anon` aux données métier.
- **RPC Postgres** : `REVOKE` public/anon/authenticated ; consommation
  `service_role` uniquement.
- **Dashboard** : magic-link + allowlist emails ; RLS deny-all sur les tables.

## Bonnes pratiques pour les contributeurs

- Ne pas logger de PII (formulaires : champs sensibles strippés Sprint 30).
- Requêtes ad-hoc : **`events_human`**, pas `events` brut (sauf audit filtrage).
- Migrations : pas de secret en dur dans le SQL.
