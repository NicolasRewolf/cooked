# Sécurité

**Périmètre mis à jour le 04/11/2026.** Le socle conserve événements pseudonymes, sources Google par page, inventaire Wix et contrôles. Les tables CRM/SECIB, les anciennes métriques et leurs lecteurs ont été retirés ; le webhook v17 écrit uniquement l’événement analytique filtré. Les obligations de confidentialité des anciennes sauvegardes et archives privées subsistent.

## Signaler un problème

Contacter Nicolas Rewolf par le canal habituel Rewolf Studio / cabinet. Ne pas ouvrir d’issue publique pour une faille : le dépôt est public. Délai de réponse visé : 48 heures ouvrées.

## Données et accès

| Périmètre | Nature | Accès |
|---|---|---|
| Événements et couture | Identifiants pseudonymes persistants et activité du site ; les champs d’identité et le texte libre de formulaire ne doivent pas être copiés dans l’événement | RLS, rôles techniques autorisés et filtres communs |
| GSC et inventaire Wix | Mesures agrégées par page/requête et contenu publié | Rôles techniques autorisés |
| Alertes et contrôles | Comptes, codes et états techniques ; pas de payload personnel ni message DB brut | Rôles techniques autorisés |
| Dashboard | Session et allowlist ; page de transition sans lecture de métriques métier | Supabase Auth, utilisateur autorisé |

Un identifiant aléatoire ou une IP hachée ne démontre pas l’anonymat. `localStorage._ckd_aid` n’a pas d’expiration propre ; la rétention serveur ne l’expire pas. L’absence de cookies ne suffit pas à établir une exemption de consentement. Les finalités, informations publiées, accès et durées doivent être évalués ensemble ; voir les [conditions CNIL](https://www.cnil.fr/fr/cookies-solutions-pour-les-outils-de-mesure-daudience).

La catégorie Wix `ESSENTIAL` a été conservée lors de la correction du 20/10/2026, à la demande de Nicolas de maintenir la collecte. Cette décision technique et le retrait CRM ne certifient ni l’exemption ni la conformité du traitement. Les anciens arbitrages sont conservés, datés, dans [rgpd-pont-secib.md](docs/rgpd-pont-secib.md).

## Secrets interdits dans le dépôt et les sorties

Ne jamais committer ou imprimer les clés Supabase, tokens d’accès, URLs de connexion, credentials Google/Wix, secrets Edge, topic ntfy, fichiers `.env` ou `*credentials*.json`. Les identifiants des intégrations retirées restent confidentiels ; la suppression du code ne prouve pas leur révocation externe.

En cas de fuite : révoquer ou régénérer le secret auprès du service concerné, puis mettre à jour les déploiements qui le portent. Ne pas recopier la valeur compromise dans une issue, un rapport ou un log.

| Nom | Usage conservé | Emplacement attendu |
|---|---|---|
| `SUPABASE_SECRET_KEY` | Écritures/lectures techniques serveur | Edge, GitHub Actions, environnement local privé ; plus nécessaire à la page de transition |
| `COOKED_INGEST_KEY` | Gate `x-cooked-key` de `track` | Secrets Edge et Wix Velo |
| `ANON_SALT` | Repli de hachage IP + UA | Secrets Edge `track` |
| `ALLOWED_ORIGIN` | Garde d’origine du proxy | Secrets Edge |
| `FORM_WEBHOOK_SECRET` | Authentification de l’automatisation Forms | Secrets Edge et URL privée de l’automatisation Wix |
| `GSC_CREDENTIALS_B64` / `GSC_CREDENTIALS_PATH` | Lecture Search Console | GitHub Actions / fichier local hors dépôt |
| `WIX_API_KEY` | Rapprochement des soumissions Forms | GitHub Actions ; l’inventaire public n’en dépend pas |
| `DATABASE_URL_RO` | Catalogue et contrôles via `cooked_ci_ro` | GitHub Actions ou environnement privé |
| `SUPABASE_DB_URL` | Export manuel de sauvegarde | GitHub Actions, si configuré |
| `NTFY_TOPIC` / `cooked_config.ntfy_topic` | Notifications d’incident | GitHub Actions / configuration protégée |
| `DASHBOARD_ALLOWED_EMAILS` | Allowlist après authentification | Vercel |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Authentification uniquement ; clé publique par construction | Vercel et navigateur |

Modèles sans valeurs réelles : [.env.example](.env.example), [dashboard/.env.local.example](dashboard/.env.local.example). Ne pas afficher leur équivalent privé pour vérifier une configuration.

## Protections existantes et limites

- **Tracker.** Proxy Velo → Edge avec clé serveur et gate `x-cooked-key`, fail-fast si le secret manque. Allowlist des événements, filtre bots avant insertion, rejets agrégés dans `ingest_drops`. La garde d’origine Velo est forgeable par en-tête et il n’existe pas de limite de débit bloquante : les alertes ne sont pas une preuve d’authenticité de chaque événement.
- **Formulaires.** Secret dans l’URL, identifiant stable obligatoire et constructeur d’événement filtré. v17 répond 200 après insertion ou doublon `23505`, 503 sur erreur DB/réseau. Aucun nom, email, téléphone, texte libre ou message DB brut dans les logs/alertes. L’idempotence permet la reprise sans prouver que Wix l’exécutera.
- **Rapprochement Wix.** Comptes confirmés agrégés par jour Paris, sans contenu personnel dans les sorties. Écart ou API inaccessible déclenche un échec ; aucune réimportation automatique.
- **Postgres.** RLS sur les tables métier, vues `security_invoker`, fonctions métier avec `REVOKE` pour `PUBLIC`, `anon`, `authenticated`, puis droits explicites nécessaires. `alert_rule_exposure()` et `check_prod_drift.py` contrôlent l’exposition. `REVOKE FROM PUBLIC` seul ne couvre pas les droits explicites hérités des anciens déploiements.
- **Dashboard.** Magic-link avec `shouldCreateUser: false`, allowlist et validation des destinations de callback. Les anciens lecteurs RPC et la clé service côté dashboard ont été retirés. L’authentification ne donne pas accès aux tables métier.
- **CI.** `cooked_ci_ro` reste un rôle de lecture technique ; il n’a pas vocation à lire les payloads d’événements ni à écrire. Les privilèges sont vérifiés avec le catalogue, pas déduits de son nom.

## Règles de contribution

Aucune donnée personnelle dans les réponses, journaux, issues, commits, PR ou captures : compter et agréger plutôt que lister les soumissions. Les analyses métier lisent `events_human` ; l’usage d’`events` brut est réservé au diagnostic explicite.

Chaque nouvelle fonction métier porte ses droits dans sa migration ; une nouvelle table doit garder la protection RLS attendue. Les secrets ne figurent jamais dans les migrations. Après un changement de privilèges, vérifier l’exposition réelle. Les advisors Supabase complètent ce contrôle sans remplacer la lecture des droits.

Documenter un nouveau secret seulement si une fonctionnalité autorisée en a besoin. Ce ménage ne crée ni nouvelle authentification ni nouvelle procédure de collecte. [OPERATIONS.md](docs/OPERATIONS.md) décrit la rétention et les limites du backup manuel.
