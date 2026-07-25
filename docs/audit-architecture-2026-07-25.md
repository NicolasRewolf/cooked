# Revue d'architecture Cooked — 25/07/2026

> Revue multi-agents (6 dimensions : ingestion, modèle de données, sémantique
> des RPC, CPI, dashboard, ops/CI), suivie d'une passe de réfutation
> adversariale. 48 constats retenus, tous ancrés (fichier:ligne ou requête prod
> exécutée). Rédigé pour Nicolas, seul mainteneur.

---

## ⚠️ Fiabilité de cette revue — à lire avant d'agir

La passe de réfutation adversariale **a échoué sur 5 dimensions sur 6**, par un
bug du script d'orchestration : la liste des constats n'a pas été interpolée
dans le prompt des réfuteurs. Cinq d'entre eux ont reçu une consigne vide et
l'ont signalé.

Conséquences concrètes sur ce document :

| | |
|---|---|
| Constats produits | 48 (6 finders × 8) |
| Réellement soumis à réfutation | **19** |
| Verdicts rendus | 9 CONFIRMÉ, 7 PARTIEL, **3 RÉFUTÉ** |
| Auto-déclarés « vérifié en prod » par leur auteur | 45 / 48 |
| Contre-vérifiés à la main par l'agent principal | 3 (les plus graves — voir ci-dessous) |

**Les 3 constats réfutés ont été correctement écartés** par la synthèse (ils
figurent en section « Écarté »), mais c'est un heureux hasard, pas le fruit du
dispositif. Traiter les constats de sévérité *moyenne* et *mineure* comme
**non contre-vérifiés** tant qu'une seconde passe n'a pas tourné.

### Contre-vérifications faites à la main (25/07/2026, ~07:00 Paris)

1. **`anon` peut exécuter des fonctions SECURITY DEFINER** — confirmé :
   `has_function_privilege('anon', …, 'EXECUTE')` = `true` sur
   `cooked_refresh_after_gsc`, `dashboard_expertises_kpis`,
   `dashboard_expertises_overview`, `dashboard_expertises_trend`.
   À l'inverse `purge_old_events` et `refresh_seo_url_snapshot` sont bien
   verrouillées — ce n'est donc pas un défaut global mais un `REVOKE` oublié
   sur les fonctions créées après coup.
2. **`/seo` cassé** — confirmé : `pg_get_function_result('dashboard_seo_by_query')`
   renvoie 16 colonnes ; `dashboard/src/data/rpc-schemas.ts:128-149` en exige 20.
   Manquent `clicks_prev` (non-nullable), `position_prev`, `ctr_expected`,
   `opportunity_clicks` → `.parse()` lève, la page rend une erreur.
3. **`cpi_daily` gelé** — confirmé : `max(day)` = 23/07/2026, 2 jours de retard,
   **9 jours manquants** à l'intérieur de la série.

---

## Verdict en une page

Le socle mesure est sérieux : `events_human` comme base canonique unique,
`classify_channel`, `gsc_is_branded`, `cooked_period_bounds`,
`macro_contacts_by_path` — la discipline « un prédicat métier = une fonction
SQL » est réelle et rare. Le CPI est un vrai modèle statistique
(standardisation indirecte, empirical Bayes, momentum relatif au site), validé
à J+28 avec un protocole écrit d'avance, et la doc des pièges d'analyse est
meilleure que ce que produisent la plupart des équipes.

Deux failles structurelles annulent une partie de ce bénéfice.

**(1) Le système ne sait pas qu'il est en panne.** Le refresh échoue toutes les
heures depuis le 24/07/2026, `cpi_daily` est gelé au 23/07,
`latest_rpc_health()` affiche « ok » sur un instantané du 04/07, aucune règle
d'alerte ne lit `cron.job_run_details`, et le canal ntfy n'a **jamais** émis une
seule notification (`net._http_response` = 0 ligne, 0 alerte `critical` depuis
la création de la table). Pendant ce temps le dashboard continue de servir des
chiffres, simplement figés, avec un voyant vert.

**(2) La discipline « une définition = un endroit » s'est arrêtée à mi-chemin.**
Les contacts assistés ont trois implémentations qui divergent de 28 %, le
`bounce_rate` a deux unités dans le contrat RPC publié, le spam Baidu (16,7 %
des visiteurs 28 j — 2 684 / 16 098) est filtré dans 5 RPC dashboard et dans
aucune RPC de niveau site.

Le reste — disque plein, timeouts, drift du repo — découle de deux choix
d'architecture initiaux qui ont atteint leur limite d'échelle : **écrire tout
puis filtrer à la lecture**, et **faire du repo un miroir manuel de la prod**.

---

## Les causes racines

### R1 — Une transaction unique, aucune surveillance d'exécution

`cooked_refresh_after_gsc()` enchaîne 4 `PERFORM` dans un seul corps plpgsql,
sans `EXCEPTION` par étape, avec `cooked_cpi_snapshot()` en **dernier**. Toute
erreur d'une étape dashboard annule la transaction entière et le CPI — qui ne
dépend d'aucune des trois — n'est jamais écrit. Aucune des 9 `alert_rule_*` ne
lit `cron.job_run_details`, aucune ne surveille `max(day)` de `cpi_daily`.

Explique : le cron 46 en échec horaire ; le job 2 (la transaction du
contract-test est annulée, donc rien n'est écrit dans `rpc_health`, d'où le
« ok » du 04/07 qui persiste) ; les trous de `cpi_daily` ; l'alerte `cpi_drop`
qui republie chaque jour le même delta figé (23/07 vs 16/07) ;
`refresh_pipeline_health` qui ne regarde qu'un cron sur 9 ; et les 23 alertes
non acquittées — la dédup de `raise_cooked_alert` exige `NOT acked`, donc
**acquitter ré-arme l'alerte au tick suivant** : acquitter est puni, le canal
meurt.

Empire mécaniquement : chaque nouveau refresher ajouté à la séquence augmente
la probabilité que le CPI ne sorte pas, et un jour de CPI manqué est
**définitivement perdu** (`cooked_page_index` n'a pas de paramètre de date de
fin, elle lit `now()`).

### R2 — Écrire d'abord, filtrer ensuite

`events_human` = `events_main` MINUS `bot_fingerprints` MINUS `noise_sessions`
MINUS chrome-anchors MINUS doublons. Le filtre est un empilement d'anti-joins
évalué à chaque lecture. Mesuré : `count(*)` sur 2 jours d'`events_human` =
**10 718 ms**, 556 152 buffers, et le planner estime **1 ligne pour 18 302** —
donc tout plan qui joint `events_human` à autre chose part en nested loop
dimensionné pour une ligne. Extrapolé à 28 jours : ~120 s, exactement le
timeout de `site_context_export`.

Explique : 84 % de bruit stocké (~28 000 sessions HeadlessChrome / 2 j, que le
motif `%headless%` de `refresh_noise_sessions` sait déjà reconnaître à partir
d'un UA que l'Edge tient en main **au moment de l'INSERT**) ; les 2 431 Mo de
la table `events` ; l'absence de VACUUM ; `cooked_events_window` qui
matérialise `SELECT e.*` deux fois en grain `human` (~3 Go de `pgsql_tmp`, avec
`temp_file_limit = -1`, donc débordement disque au lieu d'erreur de requête) ;
les index jamais scannés ; et la fiche article à 51 s en `rolling_90` — sa
période **par défaut**.

Empire : +65-85 k lignes/jour, dont 62 % d'octets que personne ne lit
(`url` 400 Mo, `title` 149 Mo sur 90 j, jamais référencés par une RPC).

### R3 — Une notion métier, plusieurs implémentations, aucun test d'équivalence

La discipline du prédicat unique n'a été appliquée qu'aux notions dont
quelqu'un a remarqué la divergence. Partout ailleurs, les définitions ont été
recopiées puis ont dérivé.

Explique : contacts assistés = 3 moteurs (`dashboard_assisted_quarter` en
session brute, **−28 %** à fenêtre identique) ; `bounce_rate` en 2 unités ;
Baidu filtré dans 5 RPC sur 11 ; `macro_contacts_by_path` exige
`path IS NOT NULL` et `site_macro_counts` non (15 formulaires, 10 %, comptent
dans le total site et dans aucun tableau par page) ; `seo_to_contact_funnel`
qui divise un numérateur en visite recousue par un dénominateur en session
brute ; le webhook formulaire qui n'appelle pas `canonicalPath` alors que le
tracker si.

**C'est la seule cause racine qui produit directement un chiffre faux livré
avec aplomb** — le défaut que le projet a érigé en règle absolue.

### R4 — Le repo n'est plus la source de vérité

`scripts/check_rpcs_sql_fresh.py` ne se déclenche que si une PR **modifie un
fichier de `supabase/migrations/`**. Or le mode de travail réel est
`apply_migration` via MCP, fichier miroir committé plus tard — ou jamais. Le
gate est structurellement aveugle à la seule défaillance qui compte. Il ne
compare jamais le `content_sha256` qu'il stocke pourtant, et ne regarde aucun
`CREATE VIEW`.

Explique : 168 migrations prod vs 117 fichiers ; 2 RPC de prod absentes de
`rpcs.sql` (dont `cooked_refresh_after_gsc`, la fonction actuellement en
panne) ; `views.sql` qui décrit `events_human` bâtie sur `events` alors que la
prod la bâtit sur `events_main` ; `OPERATIONS.md` qui liste 4 crons supprimés ;
`CLAUDE.md` qui annonce un cron CPI `30 7 * * *` qui n'existe plus ; et `/seo`
cassé depuis le 10/07 sans que rien ne le voie.

**Cas d'école dans cette catégorie** : la régression `paris_date` (corrigée le
25/07, migration `20260725045430`). Le repo contenait un avertissement écrit
« NE JAMAIS ajouter SET search_path » ; une remédiation en masse de l'advisor
Supabase l'a fait quand même, directement en prod ; le miroir `rpcs.sql` a
enregistré la régression sans que rien ne la signale. Coût mesuré : plan à
495 118 au lieu de 1,79 sur `events`, index de 18 Mo à 0 scan.

### R5 — La surface d'exposition n'a jamais été un invariant testé

`SECURITY.md:36` prescrit `REVOKE public/anon/authenticated` sur toute RPC.
Rien ne le vérifie. Vérifié en prod : `cooked_refresh_after_gsc` et les 3
`dashboard_expertises_*` sont SECURITY DEFINER **et exécutables par `anon`**.
Côté ingestion, l'Edge `track` est en `verify_jwt=false` sans secret
applicatif, et le garde d'origine du proxy Velo
(`if (origin && !origin.startsWith(...))`) est falsy pour une requête **sans**
en-tête `Origin` — donc contournable en curl.

---

## Constats classés

| Sév. | Constat | Ancrage | Impact concret |
|---|---|---|---|
| Critique | Le snapshot CPI est la 4e étape d'une transaction unique : une panne dashboard l'annule, et `cpi_daily` se troue sans réparation possible | `cooked_refresh_after_gsc` = 4 PERFORM sans EXCEPTION ; `max(day)` = 23/07, 9 jours manquants | Le score de priorisation éditoriale est mort depuis 2 jours, personne n'est prévenu, et les jours perdus le sont pour toujours |
| Critique | Aucune alerte ne surveille l'exécution des crons ni la fraîcheur de `cpi_daily` ; `alert_rule_cpi_drop` republie chaque heure un delta calculé sur une série gelée | 0 `alert_rule_*` ne contient `job_run_details` ni `cpi_daily` ; alerte id 56 du 24/07 « vrai decay » sur 23/07 vs 16/07 | Diagnostic de decay faux, répété quotidiennement, sur des pages qui n'ont pas bougé |
| Critique | `latest_rpc_health()` affiche `ok` sur 8 RPC à partir du run du 04/07 ; les contract-tests échouent depuis 21 jours et n'écrivent rien en cas d'échec | `cron.job_run_details` jobid 2 : dernier succès 04/07 ; `rpc_health.checked_at` = 04/07 | Le réflexe prescrit par CONTRIBUTING.md donne un feu vert explicite à une régression de contrat |
| Critique | Le canal d'alerte critique n'a jamais fonctionné : 0 push ntfy jamais émis, 0 alerte `critical` jamais insérée | `net._http_response` = 0 ligne ; `alerts` = 0 ligne `critical` ; `form-webhook/index.ts:85-90` insert direct | Une macro-conversion perdue pendant un incident base ne produit aucune notification et Wix reçoit un 200 |
| Critique | 4 fonctions SECURITY DEFINER exécutables par `anon`, dont l'orchestrateur de refresh | **contre-vérifié** : `has_function_privilege('anon',…)` = true | Perf des 14 pages expertise lisible sans auth ; refresh lourd déclenchable à distance sur une base saturée |
| Critique | L'Edge `track` accepte les écritures sans secret (`verify_jwt=false`) et le garde d'origine du proxy Velo est contournable sans en-tête `Origin` | `list_edge_functions` ; `wix/http-functions.js:49-56` | Injection de `cta_phone_click` dans `events_human` → chiffre de contacts macro remonté au client falsifiable |
| Critique | `/seo` cassé depuis le 10/07/2026 : la RPC a perdu 4 colonnes que le schéma Zod exige | **contre-vérifié** : 16 colonnes retournées vs 20 exigées (`rpc-schemas.ts:128-149`) | Onglet entier en page d'erreur, 15 jours sans détection, `GisementsPanel` code mort |
| Critique | `cooked_events_window` matérialise `SELECT e.*` deux fois en grain `human` (~3 Go de `pgsql_tmp`) avec `temp_file_limit = -1` | `rpcs.sql:674-707` ; poids 90 j = 1 586 Mo dont 127 Mo réellement lus | Cause directe du « No space left on device » du 24/07 ; menace aussi les INSERT du tracker et le WAL |
| Critique | Le repo n'est plus la source de vérité DDL : 21 migrations non committées, 2 RPC de prod absentes, gate CI qui ne peut pas les voir | `check_rpcs_sql_fresh.py` : `if not migrations: return 0` | `supabase db push` depuis le repo produit une base sans refresh ni snapshot CPI |
| Majeur | Trois moteurs d'attribution des contacts assistés : le compteur d'objectif sous-compte de 28 % | `dashboard_assisted_quarter` en session brute vs `refresh_dashboard_resources_assisted` v2 recousu ; 38 vs 53 | L'objectif trimestriel qui pilote le contrat éditorial affichera ~72 % du réel |
| Majeur | Deux unités pour `bounce_rate` dans le contrat publié, sans distinction de nom ni de type | max 1,0000 (`behavior_pages_for_period`) vs 100,00 (`seo_url_snapshot`) ; `rpcs.sql:366` vs `:4295` | Comparaison page/site fausse d'un facteur 100, sans aucun signal |
| Majeur | Le spam Baidu (16,7 % des visiteurs 28 j) est exclu par 5 filtres copiés-collés et par aucune RPC de niveau site | 2 684 / 16 098 visiteurs ; absent de `site_kpis_compare`, `site_pulse`, `pages_overview_unified`, `site_context_export`, `refresh_seo_url_snapshot` | Toute part « X / trafic site » sous-estimée de ~17 % |
| Majeur | Le CPI affiché dans le tableau est celui de la veille de celui de la fiche article | 110 lignes du snapshot = `cpi_daily` du 22/07, 84 diffèrent du 23/07 | Même page, même période, deux scores (jusqu'à 30 pts, 10 grades divergents) |
| Majeur | `zv > 0` sans aucune conversion : pour une page à contribution nulle, `zv` n'est qu'une fonction décroissante de `n_org` | migration `20260723212008:77` et `:155` ; cycliste-renversé : zv +0,5, 0 phone / 0 form sur 28 j | « Contribue aux contacts plus que ses pairs » sur une page qui n'a produit aucun contact |
| Majeur | Le momentum du CPI compte les clics de marque alors que la capture les exclut | `20260723212008:95-101` (CTE `mom`, pas de `gsc_is_branded`) ; `/notre-cabinet` 76 % branded | L'alerte du 24/07 « vrai decay » sur `/notre-cabinet` est un mouvement de requêtes « plouton » |
| Majeur | `events_human` coûte 10,7 s pour 2 jours et casse l'estimation de cardinalité d'un facteur 18 000 | `EXPLAIN ANALYZE` : 10 718 ms, « rows=1 » pour 18 302 réelles | Cause du timeout de `site_context_export` et de la lenteur de toutes les RPC lourdes |
| Majeur | Aucun filtre bot à l'ingestion : ~28 000 sessions headless / 2 j écrites puis jetées à la lecture | `refresh_noise_sessions` fait `%headless%` a posteriori ; `track_row.ts:59-79` lit déjà l'UA | 84 % du volume, cause de fond du disque plein |
| Majeur | La fiche article met 51 s à sa période par défaut, au-delà de son propre `statement_timeout` de 45 s | `explain analyze dashboard_article_detail(…, 'rolling_90')` = 51 433 ms ; `periods.ts:12` | Un clic sur une ligne du tableau = attente puis page d'erreur générique |
| Majeur | `seo_to_contact_funnel` divise un numérateur recousu par un dénominateur en session brute, sur 3 fenêtres différentes | `rpcs.sql:4319-4327` vs `:4334-4341` vs `:4346` | `contact_rate_pct` structurellement écrasé |
| Majeur | En cas d'erreur Edge, le lot d'events est détruit sans trace : file vidée avant l'envoi, réponse HTTP jamais lue, aucune clé d'idempotence | `tracker.html:405-433` (`splice` avant `transmit`) ; `track/index.ts:133-137` | Un jour de contacts téléphoniques peut disparaître, et rien dans le système ne le dit |
| Majeur | `refresh_dashboard_resources_assisted` porte un `statement_timeout=300s` en `proconfig` qui écrase les 2400 s du cron | `pg_proc.proconfig` ; migration `20260712182539` ne touche que le cron | Le bump de timeout du 12/07 n'a jamais pris effet |
| Majeur | 15 contacts macro (10 % des formulaires) ont `path` NULL : comptés dans le total site, invisibles par page | `macro_contacts_by_path` : `WHERE e.path IS NOT NULL` vs `site_macro_counts` sans filtre | Somme du tableau ≠ tuile site ; le « Formulaire Divorce » apparaît à 0 partout |
| Majeur | `NTFY_TOPIC` n'existe pas dans les secrets GitHub : les steps `notify-failure` des 3 workflows sont inertes par conception | `gh secret list` → 4 secrets ; `OPERATIONS.md` affirme l'inverse | Un échec d'ingestion GSC est totalement silencieux et fait tomber dashboard + CPI en cascade |
| Majeur | `views.sql` décrit faussement `events_human` (bâtie sur `events` au lieu d'`events_main`) et ignore 4 vues sur 9 | `views.sql:114-133` vs `pg_get_viewdef` prod | Un agent conclut qu'il faut cloisonner une vue déjà cloisonnée |
| Majeur | `cpi_daily` a subi 3 ruptures de définition sans colonne de version, dont un `UPDATE` rétroactif des grades le 23/07 | `20260723212008:249-252` ; 16 pages en grade `S` au 15/06 alors que S n'existe que depuis le 23/07 | Le re-test diagnostic 56 j du 05/08 segmentera sur des grades reconstruits, sans le savoir |
| Moyen | 2,7 % des `click_internal` pointent vers des paths accentués inexistants (tracker met `target_path` en minuscules, `path` non) | 56/2 101 orphelins sur 60 j ; `tracker.html:612-615` | Attribution de nav interne fausse sur les pages indemnisation |
| Moyen | Le terme booking du CPI n'est crédité que si le clic a lieu sur la page d'entrée : 24 % des clics RDV organiques ignorés | `20260723212008:68` (`b.path = o.path`) ; 52/216 sur 28 j | Le goulot documenté du site est invisible du score censé piloter la conversion |
| Moyen | Le « potentiel » de `cpi_opportunite_contact` est multiplié par momentum et gate, contrairement à la doc et au COMMENT de la vue | `cpi_compose` se termine par `* mm * gg` ; 53 → 46 sur `/notre-cabinet` | `ORDER BY potentiel DESC` mélange potentiel structurel et « en ce moment ça monte » |
| Moyen | Le seuil de péremption de 36 h laisse afficher des chiffres vieux de 2 jours avec un point vert | `FreshnessBanner.tsx:33` et `dashboard_check_stale()` ; alerte posée 34,5 h après le décrochage | Toute la journée du 24/07 : KPI arrêtés au 22/07, voyant vert |
| Moyen | `cpi` est écrêté à 100, `cpi_raw` non, et `cpi_movers` travaille sur la valeur écrêtée | `20260723212008:127-128` ; `cpi_raw` max 115, 7 pages écrêtées le 16/07 | Une page championne perd 15 % de score avec delta = 0, puis chute « brutalement » 7 jours trop tard |
| Moyen | La fenêtre Cooked du CPI glisse sur `now()` alors que le snapshot est étiqueté par une date | `created_at` des snapshots entre 07:30 et 15:17 UTC | Deux lignes consécutives couvrent des fenêtres décalées de 4 h 33 |
| Moyen | `events.url` (400 Mo) et `events.title` (149 Mo) ne sont lus par aucune RPC ; `url` transporte `cooked_aid`/`cooked_sid` (98,4 %) et les `gclid`/`gbraid` Ads, 400 jours | `grep '\burl\b' rpcs.sql` | ~500 Mo morts sur la table qui a saturé le disque, + identifiants publicitaires tiers persistés |
| Moyen | `signInWithOtp` sans `shouldCreateUser:false` sur un `/login` public | `login/page.tsx:23-26` | Un scanner épuise le quota d'e-mails Supabase et verrouille le seul chemin d'accès |
| Moyen | La revendication « cookieless, RGPD-exempt » ne tient pas : `_ckd_aid` n'expire jamais, s'auto-répare, et est rattaché à une personne identifiée via le champ caché | `tracker.html:162-199`, `:251-257` ; `form_row.ts:152-155` | Décision business à trancher, pas un bug — mais l'écart code/doc porte un risque juridique |
| Mineur | Le webhook formulaire n'appelle pas `canonicalPath` (path brut pourcent-encodé) | `form_row.ts:65-83` vs `track_row.ts:155` ; 0 ligne concernée aujourd'hui | Préventif : le jour où un formulaire atterrit sur un slug accentué, la page reste à 0 contact |
| Mineur | Autovacuum jamais passé sur les tables GSC réécrites chaque jour | `autovacuum_count` = 0, 153 539 tuples morts sur `gsc_query_daily` | Un vacuum de plusieurs centaines de Mo se déclenchera pendant la fenêtre de refresh |
| Mineur | `backup-weekly.yml` ne peut pas s'exécuter (`SUPABASE_DB_URL` absent) ; la config Wix Automations n'est versionnée nulle part | `gh secret list` ; 2 runs, 2 échecs | Un bouton de secours qui échoue en 20 s est pire que pas de bouton |

---

## Ce que je ferais dans l'ordre

1. **Aujourd'hui, 1-2 h — arrêter l'hémorragie de `pgsql_tmp`.** Dans
   `cooked_events_window` : remplacer les deux `SELECT e.*` par une liste
   explicite de 12 colonnes, fusionner les deux passes du grain `human` en un
   seul `CREATE TEMP TABLE`, et poser
   `ALTER ROLE postgres SET temp_file_limit='2GB'`. Débloque le cron 46, donc
   le dashboard **et** le CPI, en divisant par ~6 l'empreinte temporaire.
   Ne pas le faire : le refresh reste mort et le disque reste au bord.
2. **30 min — désolidariser le CPI.** Découper les 4 `PERFORM` de
   `cooked_refresh_after_gsc` en blocs `BEGIN … EXCEPTION` séparés, et passer
   `cooked_cpi_snapshot()` en **premier**. Effet de bord bienvenu : la
   divergence tableau/fiche disparaît par construction.
3. **1 h — fermer les portes.** Migration
   `REVOKE ALL … FROM PUBLIC, anon, authenticated` sur les 4 fonctions, secret
   partagé `x-cooked-key` entre le proxy Velo et l'Edge `track` (401 sinon), et
   garde d'origine du proxy rendu fermant.
4. **1 h — rendre l'observabilité honnête.** `alert_rule_cron_failed` générique
   + `alert_rule_cpi_stale` + `latest_rpc_health()` qui renvoie `stale` au-delà
   de 48 h + `gh secret set NTFY_TOPIC` + **un test réel du push**. Puis dédup
   sur `kind` seul et purge des 23 alertes en stock.
5. **2-3 h — filtrer les bots à l'ingestion.** `isBotUa(ua)` dans
   `_shared/track_row.ts`, avec un compteur `ingest_drops(day, reason, n)` pour
   l'auditabilité. Puis `DELETE` du bruit > 7 j par lots + `VACUUM`.
   Validation : `count(*) FROM events_human` sur 7 j doit être identique au
   chiffre près avant/après.
6. **2 h — réparer `/seo` et poser le filet.** Restaurer les 4 colonnes de
   `dashboard_seo_by_query`, puis `scripts/check_dashboard_contracts.py` en CI
   qui compare `pg_get_function_result()` aux clés des schémas Zod.
7. **1/2 j — une seule définition des contacts assistés.** Extraire
   `assisted_contacts_by_entry_path(start,end)` et la faire appeler par
   `refresh_dashboard_resources_assisted` **et** `dashboard_assisted_quarter`.
   Traiter au passage les 15 formulaires à `path` NULL (clé `'(non rattaché)'`).
8. **1 h — les deux divergences bon marché.** `bounce_rate_pct` partout +
   `cooked_is_spam_referrer()` posé dans `cooked_events_window` plutôt que
   recopié 5 fois. Annoncer le restatement (−16,7 % de visiteurs 28 j) et poser
   une ligne dans `annotations`.
9. **1/2 j — les 3 corrections CPI qui changent un verdict.**
   `convertit := val > 0` ; momentum sur clics non-brandés ; `CpiHealthPanel`
   qui n'affiche les 4 axes que si `grade <> 'C'`.
10. **2 h — resynchroniser le repo.** Exporter les migrations manquantes depuis
    `schema_migrations.statements`, régénérer `rpcs.sql` et `views.sql`,
    ajouter la vérification du `content_sha256` au gate, et un job CI quotidien
    qui compare `schema_migrations` à `ls supabase/migrations`.

---

## État d'exécution (25/07/2026 soir)

| # | Correctif | État |
|---|-----------|------|
| 1 | Disque / refresh trop lourd | **Fait** — optimisation `cooked_events_window` ; `temp_file_limit` **impossible** sur Supabase managé |
| 2 | CPI désolidarisé | **Fait** (PR #79) |
| 3 | Sécurité (portes + `x-cooked-key`) | **Fait** — Wix + Supabase, verrou actif |
| 4 | Alertes / surveillance honnête | **Fait** (PR #78) |
| 5 | Bots + purge | **Fait** — **VACUUM FULL** planifié **26/07/2026 à 04:00** Paris |
| 6 | `/seo` + CI | **Fait** |
| 7 | Contacts assistés | **Fait** |
| 8 | Baidu + bounce | **Fait** — `cooked_events_window` + pulse/context/seo_pages |
| 9 | Corrections CPI | **Fait** |
| 10 | Repo aligné prod | **Fait** — migrations + `rpcs.sql` + gates CI |

**Finitions 26/07/2026** : migration `20260726023000_audit_finitions.sql` en prod.

---

## Ce que j'ai écarté (vérifié, non problématique)

- **Duplication d'events du tracker** : 0,12 % (pageview) / 0,09 % (page_exit)
  sur 7 j. Le problème n'est pas la duplication mais l'absence de clé
  d'idempotence — conservé sous cette forme.
- **Pollution du CPI par le paid** : toutes les composantes filtrent
  `organic%`, Baidu est classé `referral` par `classify_channel`. Le CPI est
  propre sur les deux points.
- **RLS des tables snapshot** : deny-all correct, `anon` ne peut pas lire les
  tables `dashboard_*`. Le trou est uniquement dans les fonctions SECURITY
  DEFINER.
- **Allowlist du dashboard** : fail-closed (`proxy.ts:44-49`) + `requireUser()`
  en défense en profondeur sur les 4 pages. **Réfuté.**
- **Clé service dans le bundle navigateur** : impossible par construction
  (`import "server-only"` + variable sans préfixe `NEXT_PUBLIC_`). **Réfuté.**
- **Open redirect via le paramètre `next`** : `safeNext` (`redirect.ts:6-16`)
  couvre `//`, `\\` et l'absence de `/` initial, appliqué aux deux extrémités
  du flux. **Réfuté.**
- **Bandeau de fraîcheur aveugle** : `FreshnessBanner.tsx:29-47` détecte bien
  le gel et le rend en rouge prioritaire. **Réfuté** — seul le seuil de 36 h
  est trop laxiste (conservé en sévérité moyenne).
- **`cta_booking_click` orphelins** : 0 sur 829. Le problème de `target_path`
  accentué est spécifique à `click_internal`.
- **Déduplication du webhook formulaire** : l'index unique partiel
  `events_form_submit_submission_id_uniq` fonctionne, les retries Wix ne créent
  pas de doublons.
- **Backup externe** : décision explicite du 02/07/2026, non re-litigée. Seul
  point retenu : la doc annonce un bouton déclenchable, le workflow échoue en
  20 s.
