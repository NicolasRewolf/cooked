# Sécurité

> Réécrit le 03/09/2026 (mission 02/09, T-14, constat i-01) **sur l'état réel de la prod**.
> La version du 07/08/2026 affirmait « pas de PII », « REVOKE sur toute RPC » et « RLS deny-all »
> alors que le pivot SECIB du 10/08 stockait des identités en clair et que deux fonctions
> `SECURITY DEFINER` restaient exécutables par `anon` (corrigé T-01, 02/09/2026).

## Signaler un problème

Contacter **Nicolas Rewolf** directement (pas d'issue publique pour les failles — le dépôt est
**public**). Email : via le canal habituel Rewolf Studio / cabinet. Délai de réponse visé : 48 h ouvrées.

## Données personnelles : où elles sont, où elles ne sont pas

| Objet | PII | Protection | Lecteurs |
|---|---|---|---|
| `crm_prospects` (formulaires Wix → `form-webhook` v13+, backfill 03/2025→08/2026) | **oui, en clair** : nom, prénom, email, téléphone (+ colonnes `*_norm`) — décision produit du 10/08/2026, hachage refusé | RLS deny-all sans policy | `service_role` uniquement (webhook, `scripts/secib_ingest.py`, `wix_forms_import.py`) |
| `secib_dossiers` (API SECIB — bac à sable, 49 lignes `env = 'test'` au 03/09/2026) | **oui, en clair** | RLS deny-all | `service_role` |
| `pont_prospects_dossiers` (vue de rapprochement) | oui (jointure des deux) | vue `security_invoker` sur tables deny-all | `service_role` |
| `events`, `events_human`, RPC analytics, tables `dashboard_*`, `gsc_*`, `cpi_*` | **non** — identifiants aléatoires, IP hachée + sel, `form_submit` sans champs libres ni identité (Sprint 30) | RLS deny-all + `REVOKE` | `service_role` ; le dashboard lit via sa clé service côté serveur |

**Règle absolue** : `crm_prospects` / `secib_dossiers` ne transitent jamais dans une vue analytics,
une RPC `dashboard_*`, un export, un rapport, un journal, une issue, un commit. Le texte libre des
formulaires n'est pas stocké. Cadre RGPD (textes, registre, arbitrages ouverts) :
[docs/rgpd-pont-secib.md](docs/rgpd-pont-secib.md).

## Ce qui ne doit jamais entrer dans le repo

- Clés Supabase (`sb_secret_*`, `service_role`, tokens `sbp_*`), `DATABASE_URL*`
- Credentials Google (service account GSC JSON, ADC gcloud, `GBP_CREDENTIALS_B64`)
- Identifiants DataForSEO, SECIB (`~/.claude/secib-credentials.json`)
- `FORM_WEBHOOK_SECRET`, `ANON_SALT`, `COOKED_INGEST_KEY`, topic ntfy
- Fichiers `.env`, `.env.local`, `*credentials*.json`

En cas de fuite : **révoquer / régénérer** immédiatement (Supabase, Google, DataForSEO, Septeo), puis
rejouer les déploiements qui portent la valeur (Edge, Velo, GitHub Actions, Vercel).

## Où vivent les secrets (inventaire complet au 03/09/2026)

| Secret | Protège | Emplacement |
|---|---|---|
| `SUPABASE_SECRET_KEY` (clé service `sb_secret_*`) | toutes les lectures/écritures métier | Vercel (dashboard, serveur seulement), GitHub Actions, Edge Functions, `.env` local des scripts |
| `COOKED_INGEST_KEY` | gate `x-cooked-key` de l'Edge `track` (v27+) — un appel sans la clé est rejeté 401 ; **fail-fast depuis v29 (T-18)** : le boot échoue si le secret manque, la gate ne tourne jamais ouverte ; le proxy Velo répond `ingest_key_missing` (500) plutôt que d'envoyer sans clé | Supabase Edge secrets ; Wix Velo Secrets Manager (`wix/http-functions.js`, `getSecret('COOKED_INGEST_KEY')`) |
| `ANON_SALT` | hachage IP+UA → `anonymous_id` de repli | Supabase Edge secrets (`track`) |
| `ALLOWED_ORIGIN` | garde d'origine du proxy Velo → Edge | Supabase Edge secrets (`track`) |
| `FORM_WEBHOOK_SECRET` | token `?token=` de l'Edge `form-webhook` (Wix Automation) | Supabase Edge secrets ; Wix Automation (URL du webhook) |
| `GSC_CREDENTIALS_B64` / `~/.claude/gsc-credentials.json` | service account `gsc-cooked@rewolf-507310` (Search Console) | GitHub Actions ; local |
| `GBP_CREDENTIALS_B64` / ADC gcloud | OAuth utilisateur Google Business Profile (reauth périodique exigée par Google) | GitHub Actions ; `~/.config/gcloud/application_default_credentials.json` |
| `DFS_USERNAME` / `DFS_PASSWORD` | DataForSEO (`dfs_sync.py`) | GitHub Actions uniquement (absents en local) |
| `DATABASE_URL_RO` | rôle Postgres `cooked_ci_ro` — **lecture seule** (catalogue, `cron.job`, `schema_migrations`, `freshness_contract`, `cooked_config`, EXECUTE sur les 16 RPC `dashboard_*` pour le contrat T-13 ; `statement_timeout` 30 s, `default_transaction_read_only`) | GitHub Actions (prod-drift, rpcs-regenerate) |
| `NTFY_TOPIC` / `cooked_config.ntfy_topic` | canal de push des alertes `critical` et des échecs de workflows | GitHub Actions ; table `cooked_config` (service_role) |
| `DASHBOARD_ALLOWED_EMAILS` | allowlist du dashboard (après magic-link) | Vercel |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` (clé publishable) | flux d'authentification seulement — **ne doit lire aucune donnée** (voir surface d'attaque) | Vercel, navigateur (publique par construction) |
| `WIX_API_KEY` | clé API du compte Wix, permission Blog (lecture) — synchro hebdo `page_taxonomy` (T-15) ; **à créer par Nicolas** (manage.wix.com → API Keys) | GitHub Actions (absent au 04/09/2026 : le workflow `wix-taxonomy-sync` se termine sans écrire tant qu'elle manque) |
| Credentials SECIB (client_credentials, GUID cabinet) | API SECIB — bac à sable Septeo tant que le devis SECIB+ n'est pas signé | `~/.claude/secib-credentials.json` (local) — pas de secret CI tant qu'il n'y a pas d'ingestion prod |

Modèle sans valeurs : [.env.example](.env.example) · dashboard : [dashboard/.env.local.example](dashboard/.env.local.example).

## Surface d'attaque et ce qui la vérifie

- **Ingestion** (`track`) : proxy Velo same-origin → Edge avec clé service + `x-cooked-key` ;
  events hors allow-list rejetés ; bots droppés à l'ingestion (v26+, compteur `ingest_drops`).
  Limite connue : la garde d'origine Velo est forgeable par en-tête et il n'y a pas de rate-limit —
  un burst de `cta_phone_click` forgés est **détecté** (alerte `volume_floor`, contacts sans amont), pas
  bloqué (décision §7.5 de la mission : verrou HMAC avec le loader tracker, T-17).
- **Formulaires** (`form-webhook`) : token dans l'URL, `submissionTime` validé (v11), insert échoué →
  alerte `form_submit_dropped` (v14).
- **Postgres** : RLS activée sans policy sur toutes les tables `public` (`rls_auto_enable()` sur les
  nouvelles) ; **toute fonction `SECURITY DEFINER` est `REVOKE … FROM PUBLIC, anon, authenticated`** —
  `REVOKE … FROM public` seul ne suffit pas (default privileges Supabase : récidives du 25/07 et du 31/08).
  **Invariant I1 (T-01, 02/09/2026)** : `alert_rule_exposure()` liste chaque fonction ou vue lisible par
  `anon`/`authenticated` (cron horaire → alerte `critical`) et `check_prod_drift.py` échoue en CI si
  elle renvoie une ligne. Vues : `security_invoker = true`.
- **Dashboard** (data.rewolf.studio) : magic-link Supabase (`shouldCreateUser: false` depuis T-13 — un
  e-mail hors allowlist ne crée pas de compte) + allowlist `DASHBOARD_ALLOWED_EMAILS` ; toutes les
  lectures passent par la clé service côté serveur (RPC `dashboard_*`, `service_role` only).
- **CI** : le rôle `cooked_ci_ro` ne peut ni écrire ni lire `events`/`crm_prospects`/`secib_dossiers`.
- Sortie de sprint : `get_advisors(security)` → 0 ERROR, chaque WARN listé et justifié.

## Bonnes pratiques pour les contributeurs

- Aucune PII dans les réponses, journaux, issues, commits, PR — compter (`count(*)`), ne pas lister.
- Requêtes ad-hoc : **`events_human`**, pas `events` brut (sauf audit du filtrage, annoncé).
- Migrations : pas de secret en dur ; toute nouvelle fonction se termine par son `REVOKE`/`GRANT` ;
  toute nouvelle table hérite du deny-all (vérifier `rls_auto_enable`).
- Nouveau secret = une ligne dans le tableau ci-dessus **dans la même PR**.
