# Cooked — exploitation du socle

Référence du **04/11/2026**. Le produit conserve les événements du site, deux grains Google Search Console et l’inventaire des pages publiées. Les anciens écrans et calculs CPI, SEO, maths, DFS, GBP et CRM/SECIB sont retirés. La future interface est un chantier distinct. Voir [SIMPLIFICATION.md](SIMPLIFICATION.md) et [CONTEXT.md](../CONTEXT.md).

## Flux conservés

```text
Navigateur Wix → proxy Velo → Edge track ──────────────┐
Automatisation Forms Wix → Edge form-webhook ─────────┤
                                                     ↓
                                                  events
                                                     ↓
                           events_main → events_no_bots → events_human
                                                     ↓
                                identity_stitch → cooked_visit_events
                                                     ↓
                                                page_visits

Inventaire Wix complet → page_taxonomy
Google Search Console → gsc_path_daily + gsc_query_page_daily
                        suivi commun : gsc_ingest_batches
```

Le proxy injecte les secrets côté serveur ; ils ne doivent pas être imprimés. Les deux Edge Functions conservent leur authentification existante avec `verify_jwt=false`. Cela ne signifie pas qu’elles acceptent un appel sans leur secret. Le webhook v17 ne réalise plus d’extraction ni d’écriture CRM.

La réception tracker est regroupée dans `_shared/track_delivery.ts` : validation HTTP, traitement du lot, filtrage et attente de l’écriture avant réponse. `track/index.ts` branche uniquement l’environnement et Supabase. Les constructeurs d’événements, règles de comptage et rejets agrégés restent les mêmes ; `track_delivery_test.ts` vérifie cette chaîne sur des requêtes complètes sans base réelle.

## Données conservées

Le catalogue comprend **13 tables, trois vues et 60 routines** publiques (56 Cooked et quatre `unaccent`). Les valeurs contrôlées sont dans [doc_constants.json](../contracts/doc_constants.json) ; les corps exacts dans [rpcs.sql](../supabase/rpcs.sql).

| Tables | Rôle |
|---|---|
| `events` | Événements reçus : pages vues, activité, clics, formulaires et signaux techniques |
| `gsc_path_daily`, `gsc_query_page_daily`, `gsc_ingest_batches` | Totaux Google par page, requêtes révélées par page et état des lots |
| `page_taxonomy` | Inventaire publié, chemins et catégories |
| `identity_stitch` | Rapprochement des identifiants navigateur |
| `bot_fingerprints`, `noise_sessions`, `ingest_drops` | Filtrage partagé et visibilité des rejets |
| `alerts`, `rpc_health`, `freshness_contract`, `cooked_config` | Incidents, contrôles, fraîcheur et paramètres |

Les trois vues sont `events_main`, `events_no_bots` et `events_human`. Elles isolent le site principal puis appliquent les filtres communs. Pour une analyse métier, utiliser `events_human` ou les fonctions de visite, pas les événements bruts.

## Visites et contacts

`refresh_identity_stitch()` reconstruit les correspondances sur l’historique conservé et contrôle la convergence avant de dater la réussite. Son argument historique de durée reste accepté ; il ne limite plus la reconstruction à 90 jours. Les identifiants serveur de repli 32-hex ne servent pas à fusionner des navigateurs.

`cooked_visit_events(début, fin)` segmente l’activité observable à plus de 30 minutes d’écart. Les Web Vitals tardifs ne prolongent pas la visite. L’entrée est sa première page vue, y compris avant la fenêtre du contact. Un formulaire sans identifiants explicites reste non attribué ; aucun rapprochement par simple voisinage temporel ou page future.

`page_visits(début, fin)` renvoie les lignes `page` et une ligne `coverage`. Pour les pages : visites ayant consulté, entrées dans la fenêtre, visites de cette cohorte avec téléphone, formulaire et union, puis taux de l’union. Les actions sont bornées à la clôture. Sans entrée, le taux vaut `NULL`. La couverture porte sur les jours observés et les contacts non attribués, sans garantir une collecte continue à chaque minute.

Les candidatures sont exclues des contacts métier. Un clic téléphone ne prouve pas un appel abouti. La répétition de plusieurs actions dans une visite ne crée pas plusieurs visites ayant contacté. Définition complète et comparaison 90 jours : [playbook](PLAYBOOK-analyse-seo.md).

## Google Search Console

`scripts/gsc_ingest.py` importe uniquement `date × page` et `date × page × requête`. Le premier grain garde les totaux de page ; le second ne contient que les requêtes révélées par Google. Le grain requête/site a été retiré, sans prétendre qu’il était un doublon exact.

Un lot n’est déclaré complet que lorsque ses deux grains ont réussi. Un import partiel ou échoué reste visible dans `gsc_ingest_batches` et ne devient pas une référence complète. La reprise est idempotente. L’import quotidien reprend les deux derniers mois pour absorber les révisions de fin de mois ; le mode de reprise longue reste disponible dans l’aide du script.

```bash
python3 scripts/gsc_ingest.py --help
python3 scripts/gsc_ingest.py --daily
```

Les accès Google utilisent le service account existant, en lecture Search Console. Les identifiants restent hors dépôt ; noms d’environnement dans [.env.example](../.env.example). Aucun ancien recalcul de dashboard n’est attendu après cet import.

Les dates `day` sont celles de GSC, pas des timestamps convertis en Paris. Conserver cette différence lors d’un recoupement avec Cooked. Additionner clics/impressions et pondérer les positions par les impressions ; ne pas attribuer les requêtes masquées ni relier une requête à un formulaire individuel.

## Wix : inventaire et formulaires

Le workflow `wix-taxonomy-sync` valide un inventaire public complet avant une synchronisation transactionnelle de `page_taxonomy`. Il inclut articles, pages statiques et catégories. Une source inaccessible ou incomplète fait échouer le run sans déclarer disparues les pages précédemment connues. `publication_checked_at` date ce contrôle ; l’ancien `updated_at` seul ne prouve pas la publication.

Le webhook v17 exige un identifiant stable de soumission. Il construit l’événement canonique existant, puis répond HTTP 200 après insertion ou doublon `23505`. Une erreur DB ou une réponse réseau incertaine produit HTTP 503 avec `Retry-After: 60`. Les logs et alertes contiennent des libellés fixes et codes bornés, pas le payload ni le message DB brut. L’idempotence permet une reprise ; elle ne garantit pas que Wix la déclenche.

L’attribution Forms utilise les champs cachés `page_source`, `cooked_aid` et `cooked_sid`, alimentés via [masterpage-cooked.js](../wix/masterpage-cooked.js). La collecte conserve les formulaires sans attribution ; ne pas inventer leur entrée.

Le workflow `wix-forms-reconcile` compare les nombres de soumissions Wix confirmées aux événements Cooked, par jour Paris sur une période close. Il utilise `WIX_API_KEY` et publie des écarts agrégés uniquement. Un échec API ou une différence n’entraîne ni réimport automatique ni suppression. La réussite d’un test local ne prouve pas les droits de l’API en production.

## Planification

**6 jobs pg_cron actifs**, horaires UTC. Les quatre anciens jobs de calcul ont été supprimés, pas laissés en attente de réactivation.

| Job | Horaire UTC | Travail |
|---|---|---|
| `refresh-identity-stitch` | `40 3 * * *` | Couture sur l’historique conservé |
| `run_rpc_contract_tests` | `50 3 * * *` | Six contrôles du comptage, après la couture |
| `purge_old_events_monthly` | `0 4 1 * *` | Rétention des événements : 13 mois |
| `cooked-purge-noise-weekly` | `30 4 * * 0` | Bruit bot/noise de plus de 28 jours ; entrées noise de plus de 90 jours |
| `refresh_noise_filters_hourly` | `5 * * * *` | Filtres bots et bruit |
| `cooked-alerts-hourly` | `15 * * * *` | Sources, incidents et résultats des contrôles |

| Workflow GitHub | Déclenchement UTC | Travail |
|---|---|---|
| `wix-taxonomy-sync` | Quotidien 05:00 + manuel | Inventaire publié complet |
| `gsc-daily-ingest` | Quotidien 06:00 + manuel | Deux grains GSC et lot commun |
| `wix-forms-reconcile` | Quotidien 07:10 + manuel | Écarts de comptes Wix/Cooked |
| `prod-drift` | Quotidien 06:20 + CI/manuellement selon workflow | Cohérence dépôt/production |
| `backup-weekly` | Manuel uniquement | Export partiel des tables sources |

Les horaires GitHub ne garantissent pas le début effectif du run. Ne pas exécuter plusieurs reconstructions ou lectures lourdes en parallèle. Un `statement_timeout` doit être posé avant le statement concerné, pas seulement dans le corps d’une fonction déjà lancée.

## Santé du socle

```sql
SELECT * FROM alerts WHERE NOT acked;
SELECT * FROM refresh_pipeline_health();
SELECT * FROM latest_rpc_health();
SELECT status, day_start, day_end, completed_at
FROM gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
```

La surveillance conserve **15 règles d'alerte** et cinq sources de fraîcheur : `gsc_path_daily`, `gsc_query_page_daily`, `form_submit`, `cta_phone_click`, `page_taxonomy`. La couture a ses contrôles dédiés. Les règles horaires lisent les résultats des contrôles nocturnes, sans relancer leurs sondes lourdes à chaque passage.

`refresh_pipeline_health()` résume la réception des événements et les lots GSC ; ce n’est pas un certificat global de justesse des données. Pour un résultat métier, lire aussi l’inventaire, les bornes de couverture et les contrôles concernés. Consulter les seuils courants dans `freshness_contract` et les corps SQL, sans les recopier dans plusieurs guides.

Une alerte datée peut être historique. Acquitter seulement une cause vérifiée ou un périmètre explicitement retiré. Les contacts sans amont, champs Forms absents et différences de comptes restent visibles ; un acquittement ne reconstitue pas les données manquantes.

## Déploiement

Les migrations sont le journal DDL. Les miroirs `supabase/rpcs.sql` et `supabase/views.sql` servent à lire l’état courant, pas à recréer seuls une base complète. Ne pas prétendre qu’une restauration ou un bootstrap est validé sans l’avoir exécuté et contrôlé.

Après livraison SQL : régénérer les miroirs et leurs métadonnées, vérifier les privilèges, les contrôles pertinents et les advisors. Les tables restent protégées par RLS, les vues par `security_invoker` et les fonctions métier par des droits explicites. Voir [CONTRIBUTING.md](../CONTRIBUTING.md) et [SECURITY.md](../SECURITY.md).

Pour les Edge, conserver les secrets déjà configurés et les modules `_shared` :

```bash
supabase functions deploy track --no-verify-jwt
supabase functions deploy form-webhook --no-verify-jwt
```

Le CLI doit viser le projet Cooked. Déploiements de référence : **track v32 / Supabase 42** le 04/11/2026 ; **form-webhook v17 / Supabase 26** le 04/11/2026. Comparer le bundle distant au code livré. Une réponse 401 ou 405 vérifie une garde HTTP, pas la réception complète d’un formulaire. Aucun faux contact de production pour tester.

Le tracker source est **sprint43**, déployé et reçu le 20/10/2026. Avant collage Wix :

```bash
python3 scripts/minify-tracker.py --copy
```

Le script impose la limite Wix de 15 000 caractères. Le minifié est un artefact, `wix/tracker.html` reste la source. Après mise à jour du Custom Code, comparer le HTML public au minifié et vérifier la réception de la version sur trafic réel. D’anciens onglets peuvent continuer à émettre l’ancienne version. Ne pas publier des brouillons Wix sans rapport avec le tracker.

Le dashboard conserve Supabase Auth, l’allowlist et une page de transition. Il n’utilise plus de clé service pour lire des métriques. Configuration et build : [dashboard/README.md](../dashboard/README.md).

## Conservation et sauvegarde

La simplification ne change pas les durées de rétention des sources : purge mensuelle des événements de plus de 13 mois, purge du bruit de plus de 28 jours et nettoyage des entrées noise de plus de 90 jours. Une durée serveur n’expire pas automatiquement l’identifiant du navigateur.

Le workflow `backup-weekly` est manuel. Il exporte `events`, les deux tables GSC, `page_taxonomy` et `alerts` vers des fichiers CSV compressés, avec artifact GitHub de 90 jours. Il ne sauvegarde ni tout le schéma, ni les rôles, ni l’authentification, ni les secrets ; ce n’est pas une restauration complète. Son existence ne prouve pas qu’un export récent a réussi. Le backup externe a été décliné le 02/07/2026 ; ne pas le réactiver ou le reproposer hors décision de Nicolas.

Les secrets restent hors dépôt et ne doivent jamais apparaître dans les commandes partagées, URLs copiées ou logs. Le retrait CRM n’efface pas les contraintes de confidentialité des anciennes sauvegardes ou archives privées. Les règles de [SECURITY.md](../SECURITY.md) restent applicables ; ses inventaires historiques doivent être lus avec leur date.

## En cas d’écart

Localiser la source et la période avant de recalculer : réception, filtre, couture, lot GSC ou inventaire Wix. Comparer les comptes agrégés et les dates ; éviter d’extraire des identités ou du contenu de formulaire. Une absence de données reste inconnue tant que sa cause n’est pas établie.

Les archives [RELIABILITY.md](RELIABILITY.md), [HISTORY-sprints.md](HISTORY-sprints.md) et les [audits](README.md) expliquent les incidents antérieurs. Elles ne prescrivent plus de relancer un calcul CPI, CRM ou snapshot retiré.
