# Cooked — exploitation du socle

Référence du **04/11/2026**. Le produit conserve les événements du site, deux grains Google Search Console et l’inventaire des pages publiées. Les anciens écrans et calculs CPI, SEO, maths, DFS, GBP et CRM/SECIB sont retirés. L’extension du tableau ajoute entrées, contacts, taux, comparaison et détail Google à la demande ; ses lecteurs SQL sont déployés et les vérifications sont suivies dans le [changelog](../CHANGELOG.md). Voir [SIMPLIFICATION.md](SIMPLIFICATION.md) et [CONTEXT.md](../CONTEXT.md).

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
events_human + page_taxonomy + cooked_visit_events → page_view_counts → tableau privé
Google Search Console → gsc_path_daily + gsc_query_page_daily
                        suivi commun : gsc_ingest_batches
                        → page_query_counts → requêtes d'une page à la demande
```

Le proxy injecte les secrets côté serveur ; ils ne doivent pas être imprimés. Les deux Edge Functions conservent leur authentification existante avec `verify_jwt=false`. Cela ne signifie pas qu’elles acceptent un appel sans leur secret. Le webhook v17 ne réalise plus d’extraction ni d’écriture CRM.

La réception tracker est regroupée dans `_shared/track_delivery.ts` : validation HTTP, traitement du lot, filtrage et attente de l’écriture avant réponse. `track/index.ts` branche uniquement l’environnement et Supabase. Les constructeurs d’événements, règles de comptage et rejets agrégés restent les mêmes ; `track_delivery_test.ts` vérifie cette chaîne sur des requêtes complètes sans base réelle.

## Données conservées

Le catalogue vérifié en production comprend **13 tables, trois vues et 62 routines** publiques (58 Cooked et quatre `unaccent`). Les valeurs contrôlées sont dans [doc_constants.json](../contracts/doc_constants.json) ; les corps exacts livrés dans [rpcs.sql](../supabase/rpcs.sql).

| Tables | Rôle |
|---|---|
| `events` | Événements reçus : pages vues, activité, clics, formulaires et signaux techniques |
| `gsc_path_daily`, `gsc_query_page_daily`, `gsc_ingest_batches` | Totaux Google par page, requêtes révélées par page et état des lots |
| `page_taxonomy` | Inventaire publié, chemins et catégories |
| `identity_stitch` | Rapprochement des identifiants navigateur |
| `bot_fingerprints`, `noise_sessions`, `ingest_drops` | Filtrage partagé et visibilité des rejets |
| `alerts`, `rpc_health`, `freshness_contract`, `cooked_config` | Incidents, contrôles, fraîcheur et paramètres |

Les trois vues sont `events_main`, `events_no_bots` et `events_human`. Elles isolent le site principal puis appliquent les filtres communs. Pour une analyse métier, utiliser `events_human` ou les fonctions de visite, pas les événements bruts.

## Tableau éditorial

`page_view_counts(p_days)` accepte 30, 60 ou 90 jours Paris clos, avec 90 par défaut. Son JSON conserve les champs des vues et ajoute les entrées, visites avec téléphone, formulaire, union et taux, ainsi que les mêmes mesures dans `previous`. Chaque `pageview` humain compte une vue ; la jointure avec `page_taxonomy` conserve les pages à zéro. Les bornes, la couverture et les événements non attribués sont séparés pour chaque période ; la date de vérification de l’inventaire reste commune. Le calcul lit directement les sources, sans nouvelle table, cache, snapshot ou planification.

Le calcul des vues regroupe les chemins bruts avant de les normaliser, puis additionne les variantes d’une même URL canonique. Il reste indépendant des visites pour préserver notamment les règles des chemins absents et de la couverture. L’index partiel `idx_events_main_pageviews_cover` couvre les pages vues du site principal ; les exclusions bots/bruit restent celles de `events_human`. La reconstruction `cooked_visit_events` est appelée une seule fois sur les deux périodes ; chaque cohorte ne compte que ses actions avant sa clôture. Aucun résultat n’est mémorisé entre les lectures. Le délai REST de 30 secondes reste un plafond propre à chaque lecteur, sans modifier les délais globaux. Mesurer via l’API réelle et dans le navigateur ; contre-vérifier les deux fenêtres avec `page_visits` et les anciennes vues avant de conclure à une livraison correcte.

Cet index se construit avec `CREATE INDEX CONCURRENTLY` pour laisser les écritures actives. Le connecteur de migrations l’enveloppe dans une transaction, incompatible avec ce mode : exécuter son fichier par `supabase db query --linked --file <migration>`, vérifier `indisvalid` et `indisready`, puis enregistrer le fichier réellement appliqué avec `supabase migration repair --linked --status applied <version>`. Les deux commandes ciblent le projet lié indiqué dans `supabase/.temp/project-ref`.

Expertises regroupe les types `hub` et `expertise`. Articles contient les `post` hors catégorie `ressource` ; Ressources et notions juridiques contient les `post` de cette catégorie. Les deux ensembles sont disjoints. Toutes conserve aussi les autres types de pages. La catégorie provient de l’inventaire Wix existant, sans liste d’articles dupliquée dans le dashboard.

Le changement de type filtre les lignes déjà reçues dans le navigateur. L’API History native conserve le filtre dans l’URL et l’historique, sans navigation serveur. Un changement de période demande une nouvelle lecture du tableau. Les requêtes Google sont chargées seulement à l’ouverture du détail d’une page, sans précharger toutes les pages ni les périodes.

Le serveur vérifie la session et l’allowlist avec `requireUser` avant tout appel, y compris le détail Google. Le module `server-only` utilise `SUPABASE_SECRET_KEY` pour obtenir les mesures agrégées ; cette clé n’est pas transmise au navigateur. Une erreur de lecture reste une erreur et une couverture partielle est signalée. Les contacts inconnus ne sont pas répartis artificiellement entre les pages ; les petits volumes restent lisibles à côté des taux.

## Visites et contacts

`refresh_identity_stitch()` reconstruit les correspondances sur l’historique conservé et contrôle la convergence avant de dater la réussite. Son argument historique de durée reste accepté ; il ne limite plus la reconstruction à 90 jours. Les identifiants serveur de repli 32-hex ne servent pas à fusionner des navigateurs.

`cooked_visit_events(début, fin)` segmente l’activité observable à plus de 30 minutes d’écart. Les Web Vitals tardifs ne prolongent pas la visite. L’entrée est sa première page vue, y compris avant la fenêtre du contact. Un formulaire sans identifiants explicites reste non attribué ; aucun rapprochement par simple voisinage temporel ou page future.

Le calcul conserve tout l’amont historique, mais les tris de segmentation transportent seulement les identifiants, événements, heures et chemins nécessaires. Les autres attributs sont rejoints ensuite. Chaque chemin distinct est normalisé une fois ; le canal est classifié une fois par tuple distinct de sources. Les parcours sont construits uniquement pour les contacts retournés, à partir des pages déjà vues au moment de l’action. `work_mem='32MB'` est limité à cette fonction, sans réglage global ni stockage supplémentaire. Ces optimisations réduisent le travail sans changer le découpage des visites ou l’attribution.

`page_visits(début, fin)` renvoie les lignes `page` et une ligne `coverage`. Pour les pages : visites ayant consulté, entrées dans la fenêtre, visites de cette cohorte avec téléphone, formulaire et union, puis taux de l’union. Les actions sont bornées à la clôture. Sans entrée, le taux vaut `NULL`. La couverture porte sur les jours observés et les contacts non attribués, sans garantir une collecte continue à chaque minute.

Les candidatures sont exclues des contacts métier. Un clic téléphone ne prouve pas un appel abouti. La répétition de plusieurs actions dans une visite ne crée pas plusieurs visites ayant contacté. Définition complète et comparaison 90 jours : [playbook](PLAYBOOK-analyse-seo.md).

## Google Search Console

`page_query_counts(p_path, p_days)` lit une seule page canonique pour deux fenêtres de 30, 60 ou 90 jours. La fin est le dernier jour réellement présent dans `gsc_path_daily` et `gsc_query_page_daily`, antérieur à aujourd’hui. Si un lot couvre la date, son dernier état doit être complet et attester les deux grains ; un état ou manifeste absent dans un lot existant ne passe pas ce contrôle. En revanche, les jours sans lot historique restent observés : le registre n’existait pas au début de la collecte. Ce n’est ni la fin déclarée du lot ni nécessairement hier. La couverture compte ces jours communs à l’échelle du site, sans certifier la complétude historique. Un lot incomplet plus récent exclut les jours qu’il peut avoir écrasés ; les anciens manifestes complets à trois sources restent valables pour les deux grains conservés.

La réponse contient les clics actuels/précédents et les positions pondérées par les impressions pour l’union des requêtes des deux fenêtres, sans limite biaisée aux premières requêtes actuelles. Le tri est l’écart absolu de clics décroissant, puis les clics actuels décroissants et la requête. Une absence donne zéro clic observé et une position inconnue, pas une preuve d’absence de demande. Sans jour commun disponible, les quatre bornes sont nulles, les couvertures à zéro et la liste vide ; le détail l’explique. Les dates Google restent affichées séparément de celles du tableau Cooked.

`scripts/gsc_ingest.py` importe uniquement `date × page` et `date × page × requête`. Le premier grain garde les totaux de page ; le second ne contient que les requêtes révélées par Google. Le grain requête/site a été retiré, sans prétendre qu’il était un doublon exact.

Un lot n’est déclaré complet que lorsque ses deux grains ont réussi. Un import partiel ou échoué reste visible dans `gsc_ingest_batches` et ne devient pas une référence complète. La reprise est idempotente. L’import quotidien reprend les deux derniers mois pour absorber les révisions de fin de mois ; le mode de reprise longue reste disponible dans l’aide du script.

```bash
python3 scripts/gsc_ingest.py --help
python3 scripts/gsc_ingest.py all --daily
```

Les accès Google utilisent le service account existant, en lecture Search Console. Les identifiants restent hors dépôt ; noms d’environnement dans [.env.example](../.env.example). Aucun ancien recalcul de dashboard n’est attendu après cet import.

Les dates `day` sont celles de GSC, pas des timestamps convertis en Paris. Conserver cette différence lors d’un recoupement avec Cooked. Additionner clics/impressions et pondérer les positions par les impressions ; ne pas attribuer les requêtes masquées ni relier une requête à un formulaire individuel.

## Wix : inventaire et formulaires

Le workflow `wix-taxonomy-sync` valide un inventaire public complet avant une synchronisation transactionnelle de `page_taxonomy`. Il inclut articles, pages statiques et catégories. Une source inaccessible ou incomplète fait échouer le run sans déclarer disparues les pages précédemment connues. `publication_checked_at` date ce contrôle ; l’ancien `updated_at` seul ne prouve pas la publication.

À chaque passage, tous les articles sont paginés puis rapprochés des sous-sitemaps et des routes publiées. Les pages hors sitemap sont vérifiées sur le site. Un nouvel article entre même sans visite. L’import quotidien peut être lancé manuellement via le même workflow ; la publication Wix ne déclenche pas de synchronisation immédiate.

Un seul format est accepté : l’objet complet `{pages, observed_at, counts}`, également utilisable avec `--from-file`. Les anciens tableaux de catégories et fichiers texte sont refusés. Les pages disparues restent dans la base avec `is_published=false` ; leur historique n’est pas supprimé.

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
| `backup-manual` | Manuel uniquement | Export partiel des tables sources |

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

`refresh_pipeline_health()` résume la réception des événements, les données GSC par page et les lots GSC ; ce n’est pas un certificat global de justesse des données. Il lit les seuils Google dans le contrat actif `gsc_path_daily` et réutilise la règle existante pour un lot incomplet. Un contrat absent ou désactivé est signalé par `gsc_freshness_contract_unavailable`, sans état sain implicite. Les délais de réception et d’exécution des imports gardent leurs règles distinctes.

`alert_rule_freshness()` conserve le contrôle des cinq sources et des trous de série. Ces contrôles ne sont pas tous exécutés par le résumé du pipeline. Pour un résultat métier, lire aussi l’inventaire, les bornes de couverture et les contrôles concernés. Consulter les seuils courants dans `freshness_contract` et les corps SQL, sans les recopier dans plusieurs guides.

Une alerte datée peut être historique. Acquitter seulement une cause vérifiée ou un périmètre explicitement retiré. Les contacts sans amont, champs Forms absents et différences de comptes restent visibles ; un acquittement ne reconstitue pas les données manquantes.

## Déploiement

Les migrations sont le journal DDL. Les miroirs `supabase/rpcs.sql` et `supabase/views.sql` servent à lire l’état courant, pas à recréer seuls une base complète. Ne pas prétendre qu’une restauration ou un bootstrap est validé sans l’avoir exécuté et contrôlé.

Après livraison SQL : régénérer les miroirs et leurs métadonnées, vérifier les privilèges, les contrôles pertinents et les advisors. Les tables restent protégées par RLS, les vues par `security_invoker` et les fonctions métier par des droits explicites. Voir [CONTRIBUTING.md](../CONTRIBUTING.md) et [SECURITY.md](../SECURITY.md).

Pour les Edge, conserver les secrets déjà configurés et les modules `_shared` :

```bash
supabase functions deploy track --project-ref mxycmjkeotrycyneacje
supabase functions deploy form-webhook --project-ref mxycmjkeotrycyneacje
```

Le projet distant est explicite dans ces commandes. [supabase/config.toml](../supabase/config.toml) conserve `verify_jwt=false` pour ces deux réceptions, qui vérifient leurs clés dédiées. Livraison du **04/11/2026 à 11:05 Paris** : **track v32 / Supabase 43** et **form-webhook v17 / Supabase 27**. Les douze fichiers des deux bundles distants sont identiques aux sources. Les gardes GET répondent 405 ; vingt événements réels sprint43 ont été reçus après cette livraison. Comparer le bundle distant au code livré. Une réponse 401 ou 405 vérifie une garde HTTP, pas la réception complète d’un formulaire. Aucun faux contact de production pour tester.

Le tracker **sprint44** a été livré dans le Custom Code Wix, révision 35, le **04/11/2026 à 11:06 Paris**, avec les mêmes paramètres. Le HTML public sans cache contient exactement le minifié de 14 480 caractères. À 11:07, l’URL racine servait encore sprint43 depuis son cache ; la propagation était en cours. La réception est confirmée : 37 événements réels sprint44 entre 11:06:55 et 11:08:52 Paris. Pour préparer le code Wix :

```bash
python3 scripts/minify-tracker.py --copy
```

Le script impose la limite Wix de 15 000 caractères. Le minifié est un artefact, `wix/tracker.html` reste la source. Après mise à jour du Custom Code, comparer le HTML public au minifié et vérifier la réception de la version sur trafic réel. D’anciens onglets peuvent continuer à émettre l’ancienne version. Ne pas publier des brouillons Wix sans rapport avec le tracker.

Le dashboard conserve Supabase Auth et l’allowlist. Son lecteur serveur réutilise `SUPABASE_SECRET_KEY`, déjà configurée dans Vercel pour production et preview. La présence de cette clé ou un build local ne prouve pas la livraison du tableau. Configuration et vérification : [dashboard/README.md](../dashboard/README.md).

## Conservation et sauvegarde

La simplification ne change pas les durées de rétention des sources : purge mensuelle des événements de plus de 13 mois, purge du bruit de plus de 28 jours et nettoyage des entrées noise de plus de 90 jours. Une durée serveur n’expire pas automatiquement l’identifiant du navigateur.

Le workflow `backup-manual` est manuel. Il exporte `events`, les deux tables GSC, `page_taxonomy` et `alerts` vers des fichiers CSV compressés, avec artifact GitHub de 90 jours. Il ne sauvegarde ni tout le schéma, ni les rôles, ni l’authentification, ni les secrets ; ce n’est pas une restauration complète. Son existence ne prouve pas qu’un export récent a réussi. Le backup externe a été décliné le 02/07/2026 ; ne pas le réactiver ou le reproposer hors décision de Nicolas.

Les secrets restent hors dépôt et ne doivent jamais apparaître dans les commandes partagées, URLs copiées ou logs. Le retrait CRM n’efface pas les contraintes de confidentialité des anciennes sauvegardes ou archives privées. Les règles de [SECURITY.md](../SECURITY.md) restent applicables ; la suppression d’une intégration ne prouve pas la révocation de ses anciens accès.

## En cas d’écart

Localiser la source et la période avant de recalculer : réception, filtre, couture, lot GSC ou inventaire Wix. Comparer les comptes agrégés et les dates ; éviter d’extraire des identités ou du contenu de formulaire. Une absence de données reste inconnue tant que sa cause n’est pas établie.

Les [guides maintenus](README.md) décrivent le socle courant. Les anciens audits et recettes restent dans [l’historique Git](https://github.com/NicolasRewolf/cooked/tree/b6aa6370b9041763814bc0b1253182ece2694772/docs) ; leurs commandes ne décrivent pas le fonctionnement actuel.
