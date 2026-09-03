# Réfutation — zone (g) dashboard : contrats RPC ↔ Zod, fraîcheur, sémantique affichée
Mission Cooked du 02/09/2026 · Phase 1 · passe de réfutation fail-closed · LECTURE SEULE
Repo `…/cooked-architecture-review-c22b77` HEAD = `e95f3ee` (main) · prod Supabase `mxycmjkeotrycyneacje` (PostgreSQL 17.6)
Toutes mes mesures : **02/09/2026, entre 15:06 et 15:20 heure de Paris**.

**Constats reçus : 9 · recopiés : 9** (g-01…g-08 + o-06). Livrable valide.

---

# 1. Recopie intégrale des 9 constats reçus

```
ID            g-01
Titre         Le gate CI « contrat RPC dashboard » ne parle jamais à la prod, et ne couvre que 2 RPC sur 15 : la panne qu'il a été créé pour empêcher reste entièrement ouverte
Sévérité      P1
Preuve        · scripts/check_dashboard_contracts.py:44-61 — la boucle compare `contracts/dashboard_rpc_columns.json`
                aux clés Zod extraites par regex de `dashboard/src/data/rpc-schemas.ts`. Aucune connexion
                Postgres, aucun `DATABASE_URL`, aucun `pg_get_function_result` dans le fichier
                (73 lignes, lues intégralement). Le docstring:4 affirme pourtant que le JSON est la
                « source canonique des colonnes SQL attendues » — rien ne vérifie cette canonicité.
              · contracts/dashboard_rpc_columns.json — 2 entrées : `dashboard_seo_by_query`,
                `dashboard_honoraires_funnel`. `RPC_TO_SCHEMA` (script:19-22) mappe les 2 mêmes.
              · Prod 02/09 09:51 : 15 RPC `dashboard_*` → couverture 2/15 (13 %).
              · dashboard/src/data/rpc-schemas.test.ts:22-52 — les fixtures sont écrites à la main
                (`resourceRowFixture`). Les 92 tests vitest (`grep -c "it("` sur dashboard/src = 92)
                ne touchent aucune RPC réelle : `admin.rpc` n'apparaît que dans call-rpc.ts:41,57.
              · .github/workflows/dashboard-contract.yml — ne lance QUE `npm test` (vitest). Le script
                Python tourne dans sql-contracts.yml:49-52, déclenché sur `supabase/migrations/**`.
Impact        Une migration qui renomme, supprime ou réordonne une colonne d'une RPC dashboard passe
              les deux workflows au vert. Le contrat Zod (`callRpc` → `schema.safeParse`, call-rpc.ts:44-45)
              lève alors `RpcValidationError` à la première requête utilisateur → error.tsx (message
              générique, aucun détail). Aucune alerte : `alerts` n'a pas de règle dashboard, et les
              seuls consommateurs des RPC dashboard sont les pages Next (aucun contract-test SQL :
              `latest_rpc_health()` couvre 12 RPC, aucune `dashboard_*` — baseline Q-03).
              Sur les 13 RPC non couvertes, 5 sont dans le Promise.all de la home sans `catch`
              (app/page.tsx:51-64) → la page entière tombe, pas une cellule.
Récidive      OUI, et par construction. Le gate est né du constat n°2 de l'audit du 25/07/2026
              (docs/audit-architecture-2026-07-25.md:41-42 : « /seo cassé — confirmé :
              pg_get_function_result('dashboard_seo_by_query') renvoie 16 colonnes ;
              rpc-schemas.ts:128-149 en exige 20 »), page morte ~15 jours. La colonne manquante
              venait de la PROD. Le remède mis en place (CHANGELOG.md:279-280, « Arch #6 ») compare
              deux fichiers du repo entre eux : il est structurellement incapable de détecter
              l'écart qui a causé l'incident. Aujourd'hui prod = 20 colonnes = Zod = JSON (vérifié
              02/09 09:51) — l'alignement est réel, le filet ne l'est pas.
Invariant     Un générateur `scripts/generate_dashboard_contracts.py` qui écrit le JSON DEPUIS la prod
              pour les 15 RPC (`pg_get_function_result` pour les TABLE ; `information_schema.columns`
              de la table cible pour les `SETOF <table>` ; liste des clés `jsonb_build_object` pour les
              4 jsonb), sur le patron de `scripts/generate_rpcs_sql.py` ; puis en CI, `check_dashboard_contracts.py`
              compare Zod ↔ JSON commité (déjà fait) ET le workflow échoue si le JSON régénéré diffère
              du JSON commité (patron `check_rpcs_sql_fresh.py`, Arch #5). Ajouter les 15 RPC dans
              `run_rpc_contract_tests` pour que `latest_rpc_health()` les voie.
Statut        [non recoupé]
```

```
ID            g-02
Titre         `dashboard_assisted_quarter` : fenêtre trimestrielle croissante contre un statement_timeout fixe de 30 s — 10 exécutions complétées pour 68 chargements de la home, et l'objectif qu'elle affiche n'existe pas
Sévérité      P1
Preuve        · Corps prod (`pg_get_functiondef`, 02/09 09:52) : `q_start := date_trunc('quarter', paris_today())`,
                `q_end := paris_today()` → au 02/09 la fenêtre est **01/07 → 02/09 = 64 jours**, et elle
                grandit d'un jour par jour jusqu'au 30/09. `SET statement_timeout TO '30s'` (proconfig).
                Le corps appelle `assisted_contacts_by_entry_path(q_start, q_end)`.
              · Phase 0 (02/09 01:31) : « canceling statement due to statement timeout » dans
                `CREATE TEMP TABLE _pvk` (baseline §2.2, Q-21).
              · `extensions.pg_stat_statements`, `stats_since` = **23/07/2026 17:17** pour toutes les
                entrées PostgREST de la home (mesure 02/09 09:57) :
                  dashboard_resources_overview  68 appels
                  dashboard_resources_assisted  68 appels
                  dashboard_resources_trend     68 appels
                  dashboard_resources_cohorts   68 appels (mean 346 ms, max 1 331 ms)
                  dashboard_annotations         83 appels (= 68 home + 15 fiches article)
                  dashboard_assisted_quarter    **10 appels** (mean 444 ms, **max 1 088 ms**)
                Les 6 partent du même `Promise.all` (app/page.tsx:51-64) : 68 chargements de home,
                10 exécutions de `dashboard_assisted_quarter` enregistrées. Aucune exécution
                enregistrée n'approche les 30 s (max 1,1 s) → les appels manquants ne sont pas lents,
                ils n'aboutissent pas. (Hypothèse portée : `pg_stat_statements` ne comptabilise pas
                une instruction annulée par timeout — non re-vérifiée sur cette version PG.)
              · Décomposition (garde-fou 5) : `assisted_contacts_by_entry_path(paris_today()-28, paris_today())`
                mesurée le 02/09 à 09:58 → **3,56 s**, 49 paths, 183 contacts. La fenêtre trimestrielle
                est 2,3× plus longue ; le coût observé en Phase 0 (> 30 s) est donc **sur-linéaire**,
                cohérent avec un `CREATE TEMP TABLE` de pageviews.
              · `cooked_config` (02/09 09:59) ne contient que 4 clés : `events_vacuum_full_scheduled`,
                `expected_tracker_version`, `last_full_refresh_after_gsc_at`, `ntfy_topic`.
                **`objectif_assistes_trimestre` est absente** → `target` = NULL en permanence →
                ObjectiveLine.tsx:11,25-30 rend « objectif à fixer », jamais de barre ni de %.
Impact        (a) La ligne « Contacts nourris par les articles » disparaît sans bruit : app/page.tsx:60-63
              `catch` → `console.error` → `return null`, et page.tsx:76 `{quarter && …}`. Le seul
              indicateur de pilotage du contrat éditorial (4 articles/mois) est absent de la home
              dans ~85 % des chargements depuis le 23/07, sans que rien ne le signale.
              (b) `Promise.all` attend le plus lent : chaque chargement de home paye les ~30 s du
              timeout avant d'afficher quoi que ce soit (les 5 autres RPC répondent en < 1,4 s).
              (c) Même quand elle répond, la ligne ne peut pas afficher d'objectif : la clé n'existe pas.
              Le compteur affiché reste juste ; c'est une panne d'affichage, pas un chiffre faux.
Récidive      Partielle. Le 25/07 le constat portait sur une AUTRE maladie de la même RPC (« Trois moteurs
              d'attribution des contacts assistés : le compteur d'objectif sous-compte de 28 % »,
              docs/audit-architecture-2026-07-25.md:194), corrigée par la migration
              `20260725220100_audit_assisted_contacts_unified` (CHANGELOG.md:273-276) qui l'a justement
              branchée sur `assisted_contacts_by_entry_path` — c'est-à-dire sur la fonction coûteuse.
              La croissance de la fenêtre n'a jamais été traitée : la RPC est rapide début juillet et
              morte fin septembre, puis ressuscite le 01/10. Le cycle se rejouera à chaque trimestre.
Invariant     (1) Un contract-test dans `run_rpc_contract_tests` qui appelle `dashboard_assisted_quarter()`
              et échoue au-delà d'un budget (p. ex. 5 s) → `rpc_health` → alerte `rpc_health` existante.
              (2) Ou : snapshoter la valeur trimestrielle comme les autres (table `dashboard_*_snapshot`,
              rafraîchie par `cooked_refresh_after_gsc`) au lieu de la calculer à chaque affichage.
              (3) Le `catch` de page.tsx:60 doit rendre un état visible (« objectif indisponible »)
              plutôt que rien : un composant qui disparaît est indiscernable d'un composant absent.
Statut        [non recoupé]
```

```
ID            g-03
Titre         Le bandeau de fraîcheur note l'ÂGE du snapshot (36 h) et jamais la date de fin des données : point vert avec des chiffres J-2 pendant ~14 h par jour, et jusqu'à 21 h les 27-28/08
Sévérité      P1
Preuve        · dashboard/src/components/FreshnessBanner.tsx:29-34 :
                  `ageHours = (Date.now() - refreshedAt)/3600000` ; `staleSnapshot = !live && ageHours > 36`.
                Le seul autre test est `gscLate = lag > 3` (ligne 5,34), qui porte sur Google.
                La date de fin des données Cooked (`cookedEnd`) n'entre dans AUCUN test de sévérité :
                elle n'apparaît qu'à la ligne 61-74, dans la branche déjà verte (`dot = "bg-up"`, ligne 58).
              · État réel au moment de l'audit (requête 02/09 09:51 sur `dashboard_resources_snapshot`) :
                  `max(refreshed_at)` = **01/09/2026 14:00**, `cooked_end` = **31/08/2026**,
                  `gsc_end` = 29/08, 63 lignes par `window_kind`.
                Calcul du composant à 09:51 le 02/09 : ageHours = 19 → 19 ≤ 36 → **point vert** ;
                `dayGap('2026-08-31','2026-09-02')` (lib/dates.ts:31-38) = 2 → phrase
                « Données site jusqu'au 31/08 (il y a 2 j) » — **verte**.
              · Heure de fin du rafraîchissement réel, 14 derniers jours
                (`cron.job_run_details` × `cron.job`, job `cooked-refresh-after-gsc`, runs > 60 s ;
                requête 02/09 ~09:58, heures Paris) :
                  19→26/08 : 10:22-10:30   27/08 : **20:26**   28/08 : **21:26**
                  29/08 : 15:26   30/08 : 14:25   31/08 : 15:26   01/09 : 14:26
                Donc le 28/08, de 00:00 à 21:26 (21 h 26), le dashboard a servi le snapshot du 27/08
                20:26 : `cooked_end` = 26/08 = **J-2**, âge 24,6 h → **point vert**. Sur les 7 derniers
                jours, la fenêtre « vert + J-2 » va de 14 h à 21 h par jour.
              · Le garde-fou serveur a le même angle mort : `freshness_contract` (lu 02/09 09:59),
                source `dashboard_resources_snapshot`, `last_point_sql` =
                `SELECT public.paris_date(max(refreshed_at)) FROM public.dashboard_resources_snapshot`,
                warn 1 j / critical 3 j. Il mesure lui aussi la date du CALCUL, jamais la date de FIN
                des données. Un refresh quotidien qui produit du J-2 ne le déclenchera jamais.
Impact        Les 5 KPI de la home et des expertises (visiteurs, pages vues, contacts, clics, affichages)
              et les 63 lignes du tableau portent une fenêtre `cooked_start → cooked_end` décalée d'un
              jour de plus que ce que le libellé par défaut promet. Le seuil de 36 h est calibré pour
              détecter une PANNE de cron ; il ne détecte pas un cron qui tourne tard. La conséquence
              est un chiffre juste attribué à la mauvaise fenêtre — exactement le mode de défaillance
              que la règle absolue du projet cible. Ordre de grandeur non chiffré ici (il faudrait
              comparer le snapshot J-2 aux `events_human` du jour manquant) : [non vérifié].
Récidive      OUI, identique et à la même ligne. docs/audit-architecture-2026-07-25.md:213 —
              « Moyen | Le seuil de péremption de 36 h laisse afficher des chiffres vieux de 2 jours
              avec un point vert | FreshnessBanner.tsx:33 et dashboard_check_stale() ; alerte posée
              34,5 h après le décrochage | Toute la journée du 24/07 : KPI arrêtés au 22/07, voyant
              vert ». Le fichier porte toujours `ageHours > 36` **à la ligne 33**. Le seul changement
              depuis est la phrase « (il y a N j) » de la branche verte (ligne 64-68) : le texte est
              devenu honnête, le SIGNAL est resté vert. Et le témoin cité par l'audit,
              `dashboard_check_stale()`, a depuis disparu de la prod (cf. g-07) : le registre
              `freshness_contract` du 23/08 l'a remplacé — avec le même angle mort.
Invariant     Une seule règle, appliquée aux deux endroits :
              `paris_today() - cooked_end >= 2` ⇒ état « attention » (orange), pas vert.
              Côté serveur : une entrée `freshness_contract` dont `last_point_sql` lit
              `max(cooked_end)` et non `max(refreshed_at)` — le registre du 23/08 sait déjà exprimer
              une source par requête, c'est une ligne à ajouter, pas un mécanisme à écrire.
Statut        [non recoupé]
```

```
ID            g-04
Titre         31 champs du contrat Zod exigent une valeur non nulle sur des colonnes prod nullables : un seul NULL fait tomber la page entière, sans alerte
Sévérité      P2
Preuve        · `information_schema.columns` (02/09 09:51) : dans `dashboard_resources_snapshot`,
                **seules 3 colonnes sur 34 sont NOT NULL** (`window_kind`, `path`, `refreshed_at`) ;
                dans `dashboard_kpis_snapshot`, 2 sur 22 (`window_kind`, `refreshed_at`).
              · Confrontées à `dashboard/src/data/rpc-schemas.ts` :
                – resourceRowSchema (lignes 20-57) exige une valeur non nulle sur **13** colonnes
                  nullables : `unique_visitors`, `pageviews` (l.24-25), `gsc_clicks`, `gsc_impressions`
                  (l.28-29), `contacts`, `booking_intent` (l.36-37), `confidence` (l.41,
                  `z.enum(["S","A","B","C"])` sur une colonne `text NULL`), `unique_visitors_prev`,
                  `gsc_clicks_prev` (l.42-43), `cooked_start`/`cooked_end`/`gsc_start`/`gsc_end` (l.52-55).
                – resourceKpisSchema (l.60-87) : **18** colonnes nullables exigées non nulles
                  (`label_fr`, les 4 bornes, `is_partial`, les 10 compteurs `*_n`/`*_prev`,
                  `current_day_partial`, `no_prev_baseline`).
                – Même profil sur `dashboard_expertises_snapshot` / `_kpis_snapshot`.
                – articleDetailSchema:259 `grade: z.enum(["S","A","B","C"])` non nullable, alors que
                  `cpi_daily.grade` est `text NULL` et que la valeur vient de `to_jsonb(c) - 'created_at'`
                  (corps prod de `dashboard_article_detail`), c'est-à-dire de la ligne brute.
              · État actuel : **aucun NULL** (requête 02/09 09:51 : `uv_null`…`bounds_null` = 0 sur les
                126 lignes des deux `window_kind` ; `cpi_daily` : 0 `grade` NULL, 0 `cpi` NULL, grades
                observés {A,B,C,S}). Le contrat tient par la discipline du refresher
                (`COALESCE(ct.contacts,0)`, refresh_dashboard_snapshots ligne 79), pas par le schéma.
              · Amplificateur : sur les 6 RPC de la home, **une seule** est protégée
                (app/page.tsx:60-63, `dashboard_assisted_quarter`). Les 5 autres et les 2 RPC de
                l'article, de `/seo`, de `/expertises` n'ont aucun `catch` → `RpcValidationError`
                (call-rpc.ts:45) remonte à error.tsx : « Impossible de charger les données ».
Impact        Latent, pas actif. Le jour où un `LEFT JOIN` sans COALESCE est ajouté au refresher, ou
              qu'un `page_taxonomy` sans thème produit un `confidence` NULL, la page ne dégrade pas
              une cellule : elle disparaît. Et rien ne prévient — cf. g-01 (aucune alerte dashboard).
Récidive      Non documentée comme telle. L'audit du 25/07 a traité l'écart de NOMS de colonnes
              (constat n°2), pas la nullabilité. C'est la même faille d'un cran plus fin.
Invariant     Deux options, une seule à choisir : (a) `NOT NULL DEFAULT 0` sur les compteurs des tables
              snapshot (le refresher les COALESCE déjà, la migration est sans risque de données) ;
              (b) `.nullable()` côté Zod + rendu « — » dans les cellules. Dans les deux cas, un
              contract-test qui parse **une ligne prod réelle** avec le schéma Zod — c'est le seul test
              qui aurait attrapé l'incident /seo de juillet ET celui-ci.
Statut        [non recoupé]
```

```
ID            g-05
Titre         L'issue #45 (fiche article : deux métriques de contact mélangées) a été fermée le 30/08 sans qu'aucune de ses deux actions ne soit faite
Sévérité      P2
Preuve        · `gh issue view 45` : state CLOSED, `closedAt` = 2026-08-30T20:45:55Z = **30/08/2026 22:45 Paris**.
                Action 1 du corps : « Fiche : afficher **les deux** métriques distinctement
                (« contacts sur la page » ET « contacts assistés / page d'entrée ») ».
                Action 2 : « Dédup : neutraliser les taps téléphone dupliqués à la même minute ».
              · Fiche article aujourd'hui : `dashboard/src/app/article/[slug]/page.tsx:101-107` — un seul
                KPI de contact, « Contacts assistés », alimenté par `detail.assisted?.n`. Aucun KPI
                « contacts sur la page ».
              · La donnée n'existe même pas dans le contrat : `articleDetailSchema` (rpc-schemas.ts:223-274)
                n'a pas de champ de contacts on-page, et le corps prod de `dashboard_article_detail`
                (`pg_get_functiondef`, 02/09 09:52) n'appelle jamais `macro_contacts_by_path` — sa clé
                `assisted` lit `dashboard_resources_assisted_snapshot`.
              · Aucun commit entre les deux dates ne touche le dashboard :
                `git log --name-only --since=2026-08-29 --until=2026-09-01` → 30/08 = `4ccd342`
                (`.mcp.json` seul), 31/08 = `baa3230` (taxonomie Wix, migrations + docs).
                Le vocabulaire distinct de la fiche date de bien avant (`git log -S'Contacts assistés'`
                → `78662af`, vague A).
              · #19 et #45 sont fermées à **une seconde d'intervalle** (20:45:54Z / 20:45:55Z) : fermeture
                en lot, pas résolution.
Impact        L'écart décrit par l'issue (liste = 2, fiche = 0 pour le même article) reste visible tel
              quel. Les libellés, eux, sont exacts et distincts — c'est ce qui empêche de classer ce
              constat plus haut : le lecteur attentif peut comprendre, mais l'issue promettait de ne
              plus l'exiger de lui. Le point 2 (dédup des taps même-minute) n'a laissé aucune trace :
              ni migration, ni ligne CHANGELOG, ni décision produit écrite — alors que l'issue exigeait
              explicitement « décision produit requise avant de toucher la source unique des contacts macro ».
Récidive      Sans objet (première occurrence), mais c'est un défaut de PROCESSUS : le tracker d'issues
              ne reflète plus l'état du code. ROADMAP.md porte encore « issue #19 ouverte » (baseline §1)
              alors qu'elle est fermée — l'erreur va dans les deux sens.
Invariant     Ne fermer une issue que depuis un commit qui la référence (`Closes #45`), ou en écrivant
              dans le commentaire de fermeture pourquoi elle est abandonnée. Un `gh issue close` nu
              ne laisse aucune trace exploitable six semaines plus tard.
Statut        [non recoupé]
```

```
ID            g-06
Titre         `signInWithOtp` toujours sans `shouldCreateUser:false` — constat « Moyen » du 25/07 non corrigé, aux lignes exactes citées par l'audit, et le garde-fou compensatoire n'est que documenté
Sévérité      P2
Preuve        · `dashboard/src/app/login/page.tsx:23-26` :
                  `await supabase.auth.signInWithOtp({ email: email.trim(), options: { emailRedirectTo: redirect } })`
                Aucune option `shouldCreateUser`.
              · `docs/audit-architecture-2026-07-25.md:217` : « Moyen | `signInWithOtp` sans
                `shouldCreateUser:false` sur un `/login` public | `login/page.tsx:23-26` | Un scanner
                épuise le quota d'e-mails Supabase et verrouille le seul chemin d'accès ». Même
                fichier, **mêmes lignes**, 39 jours plus tard.
              · `/login` est publique par conception (proxy.ts:8,19-21 — `PUBLIC_PREFIXES` inclut
                `/login`), et le formulaire appelle directement l'API Supabase avec la clé publishable
                (login/page.tsx:16-19) : le gate `DASHBOARD_ALLOWED_EMAILS` n'intervient qu'APRÈS la
                connexion, il ne filtre pas l'envoi d'OTP.
              · Le seul garde-fou est une consigne dans `dashboard/README.md:172-174` : « OBLIGATOIRE —
                Auth → Sign In / Providers → Email : désactiver "Allow new users to sign up" ».
                Son état réel dans le projet Supabase est **[non vérifié]** : le vérifier exigerait une
                tentative d'inscription, c'est-à-dire une écriture — interdite par le mode de cet audit.
Impact        Pas de chiffre faux. Risque de disponibilité : le magic-link est le SEUL chemin d'accès
              au dashboard ; un épuisement du quota d'e-mails du projet le ferme pour Nicolas aussi.
              Risque secondaire : création de comptes `auth.users` non sollicités (sans accès aux données —
              l'allowlist tient, proxy.ts:50-58 + auth.ts:29).
Récidive      Non corrigé depuis le 25/07/2026. Le plan de correction d'audit ne l'a pas repris
              (`docs/plan-correction-audit-2026-07-02.md` est antérieur ; aucun T-nn ne le cite).
Invariant     `shouldCreateUser: false` dans le code (défense en profondeur : indépendant d'un réglage
              de console qu'aucun test ne peut voir) + un test vitest sur l'objet d'options passé.
Statut        [non recoupé]
```

```
ID            g-07
Titre         Trois affirmations du dashboard sur son propre socle sont démenties par la prod : la clé publishable « ne lit AUCUNE donnée métier », `dashboard_check_stale()` existe, et des crons `refresh-dashboard-*` tournent
Sévérité      P3
Preuve        (a) `dashboard/.env.local.example:9-10` : « Clé anon/publishable (publique, sûre côté
                navigateur — **ne lit AUCUNE donnée métier : RLS deny-all**) » ; `dashboard/README.md:162`
                dit la même chose en tableau (« flux auth uniquement | oui (sûr, RLS deny-all) »).
                La baseline de Phase 0 (§1, annexe B, 02/09 01:29) a mesuré le contraire avec la clé
                `anon` : `GET /rest/v1/cpi_capture_perdue?select=path,grade&limit=1` → **HTTP 200, 1 ligne** ;
                `GET /rest/v1/rpc/page_reads?p_from=…&p_to=…` → **HTTP 200, 1 ligne** (session × path × dwell).
                L'affirmation du dashboard est la raison pour laquelle personne ne va vérifier les grants.
            (b) `dashboard_check_stale()` n'existe plus en prod : `pg_proc WHERE proname LIKE 'dashboard%'`
                (02/09 09:51) renvoie 15 fonctions, sans elle. Elle survit dans `supabase/rpcs.sql`
                (baseline §1 : « 6 dans le fichier absentes de prod », dont `dashboard_check_stale`) et
                dans `docs/audit-architecture-2026-07-25.md:213` comme témoin de fraîcheur.
                `extensions.pg_stat_statements` garde la trace de **732 appels** (`stats_since` 23/07
                11:30, mean 9 ms) : elle a bien tourné, puis a disparu avec son cron.
            (c) `freshness_contract.repair_hint` pour `dashboard_resources_snapshot` (lu 02/09 09:59) :
                « Vérifier les jobs pg_cron **refresh-dashboard-*** (04:00-04:16 UTC) et
                cooked-refresh-after-gsc ». Les 9 jobs prod (baseline Q-04) n'en contiennent aucun de
                ce nom ; `OPERATIONS.md:462-480` liste de même `refresh-dashboard-snapshots`,
                `refresh-dashboard-expertises`, `refresh-dashboard-assisted`, `dashboard-stale-check`
                comme actifs. Le seul rafraîchisseur réel est `cooked-refresh-after-gsc`.
Impact        Aucune donnée fausse. Coût : la consigne de réparation envoyée à celui qui reçoit l'alerte
              de fraîcheur le renvoie vers des objets qui n'existent pas ; et la phrase (a) est
              exactement celle qui a permis à l'exposition anon de passer inaperçue.
Récidive      La dérive `rpcs.sql` ↔ prod est un constat récurrent (baseline §1 : fichier édité à la
              main le 31/08 au lieu d'être régénéré, 2 corps divergents, 6 manquants, 6 en trop).
              Le générateur existe (`scripts/generate_rpcs_sql.py`) et le gate CI aussi (Arch #5) —
              ils n'ont pas empêché l'édition manuelle.
Invariant     (a) corriger la phrase et la faire porter par le contrôle réel (zone h : REVOKE) ;
              (b)/(c) un check CI qui compare le `repair_hint` / la doc des crons à `cron.job` — ou,
              plus simple et plus solide : que `freshness_contract.repair_hint` cite un nom de job
              contraint par une FK logique vérifiée par la règle d'alerte elle-même.
Statut        [non recoupé]
```

```
ID            g-08
Titre         La fiche article peut faire attendre 34 s : période par défaut `rolling_90`, `statement_timeout` de 45 s côté SQL, aucun budget côté Next
Sévérité      P3
Preuve        · `dashboard/src/lib/periods.ts:12` : `parsePeriod(value, fallback: Period = "rolling_90")`.
                La fiche article l'appelle sans surcharge (`app/article/[slug]/page.tsx:35`) : un clic
                depuis le tableau sans `?period=` ouvre la fenêtre 90 jours.
              · `dashboard_article_detail` : `proconfig = {search_path=public, statement_timeout=45s}`
                (02/09 09:51).
              · `extensions.pg_stat_statements` (02/09 09:57, `stats_since` 23/07/2026 17:22) sur l'appel
                PostgREST de `dashboard_article_detail` : **15 appels, moyenne 3 220 ms, max 33 850 ms**,
                min 34 ms. Sur la même période, `dashboard_intervention_effect` : 15 appels, moy. 43 ms.
              · `call-rpc.ts:36-47` : `admin.rpc()` sans `AbortSignal` ni budget de temps ; la seule
                politique « soft » (callRpcTrend, l.55-73) ne couvre que les tendances. Un dépassement
                du timeout SQL remonte en `RpcError` → error.tsx.
Impact        Latence, pas de chiffre faux. 34 s d'attente sur un clic de tableau, sans indication autre
              que le squelette de chargement (page.tsx:195-210). Le budget SQL (45 s) est plus long que
              la patience d'un utilisateur ; la marge restante est de 11 s.
Récidive      OUI, atténuée. docs/audit-architecture-2026-07-25.md:202 — « Majeur | La fiche article met
              51 s à sa période par défaut, au-delà de son propre statement_timeout de 45 s |
              explain analyze dashboard_article_detail(…, 'rolling_90') = 51 433 ms ; periods.ts:12 |
              Un clic sur une ligne du tableau = attente puis page d'erreur générique ». Le dépassement
              du timeout n'apparaît plus dans l'échantillon (max 33,9 s < 45 s), mais **`periods.ts:12`
              est inchangé** et la marge reste faible. Aucun invariant n'a été posé : la prochaine
              croissance de `cpi_daily` (la clé `cpi_series` lit tout l'historique du path, sans borne
              de fenêtre — corps prod) repassera au-dessus.
Invariant     Un contract-test de DURÉE (pas seulement de forme) sur les 3 RPC lourdes
              (`dashboard_article_detail`, `dashboard_honoraires_funnel` — moy. 5 412 ms / max 12 006 ms
              mesurée, `dashboard_seo_by_query` — moy. 3 080 ms), intégré à `run_rpc_contract_tests` et
              donc à `latest_rpc_health()` / l'alerte `rpc_health`.
Statut        [non recoupé]
```

```
ID            o-06 (zone c / g)
Titre         `dashboard_assisted_quarter()` dépasse son `statement_timeout=30s` sur le trimestre en cours ; la ligne objectif du dashboard est masquée en silence
Sévérité      P1
Preuve        `EXPLAIN (ANALYZE) SELECT public.dashboard_assisted_quarter()` 02/09 01:31 Paris → `ERROR 57014 canceling statement due to statement timeout` dans `CREATE TEMP TABLE _pvk` de `assisted_contacts_by_entry_path(q_start=01/07, q_end=02/09)` ; `pg_proc.proconfig` = `statement_timeout=30s` ; `dashboard/src/app/page.tsx:61` `console.error("dashboard_assisted_quarter KO — ligne objectif masquée")`.
Impact        tuile/ligne objectif trimestriel absente sans alerte (aucun contract-test ne couvre les `dashboard_*`) ; la fenêtre grandit chaque jour jusqu'au 30/09.
Récidive      `fix_assisted_quarter_perf_et_timeout` (03/07) puis unification 25/07 (`assisted_contacts_by_entry_path`) — la fonction unifiée est plus lourde que le calcul session brute qu'elle remplace.
Invariant     contract-test des 16 `dashboard_*` (rows ≥ 1, durée < timeout) dans `run_rpc_contract_tests` + alerte `rpc_health`.
Statut        [non recoupé]
```

---

# 2. Verdicts

## g-01 — Gate CI « contrat RPC dashboard » aveugle à la prod, 2/15

```
ID        g-01
Verdict   CONFIRMÉ (et aggravé)
```

**Ma preuve.**

*Fichier, relu intégralement (73 lignes) :* `scripts/check_dashboard_contracts.py`. Le corps de `main()` (l.44-69) ne fait que `json.loads(CONTRACT.read_text())` (l.45) et `SCHEMAS.read_text()` (l.46) puis compare deux ensembles Python. Aucune occurrence de `psycopg`, `DATABASE_URL`, `pg_get_function_result` dans le fichier. `RPC_TO_SCHEMA` (l.19-22) contient exactement 2 entrées : `dashboard_seo_by_query` → `seoQueryRowSchema`, `dashboard_honoraires_funnel` → `honorairesFunnelSchema`. Le docstring l.4 dit bien « source canonique des colonnes SQL attendues ».

*`contracts/dashboard_rpc_columns.json` :* 2 clés, 20 colonnes pour `dashboard_seo_by_query`, 9 pour `dashboard_honoraires_funnel`.

*Prod, 02/09/2026 15:07 Paris* — `SELECT proname … FROM pg_proc … WHERE proname LIKE 'dashboard%'` → **15 fonctions** : `dashboard_annotations`, `dashboard_article_detail`, `dashboard_assisted_quarter`, `dashboard_expertises_kpis`, `dashboard_expertises_overview`, `dashboard_expertises_trend`, `dashboard_honoraires_funnel`, `dashboard_intervention_effect`, `dashboard_resources_assisted`, `dashboard_resources_cohorts`, `dashboard_resources_kpis`, `dashboard_resources_overview`, `dashboard_resources_trend`, `dashboard_seo_by_query`, `dashboard_seo_kpis`. **Couverture 2/15 = 13,3 %.**

*Alignement actuel, prod 02/09 15:07 :* `pg_get_function_result` → `dashboard_seo_by_query` = **20 colonnes**, `dashboard_honoraires_funnel` = **9 colonnes**. Identiques au JSON commité. Le constat a raison sur les deux tableaux : l'alignement est réel aujourd'hui, le filet ne l'est pas.

*Tests :* `grep -rn --include='*.ts' --include='*.tsx' "\bit(" dashboard/src | wc -l` → **92**. `grep -rn "\.rpc(" dashboard/src` → **2 occurrences seulement**, `call-rpc.ts:41` et `call-rpc.ts:57`. `dashboard/src/data/rpc-schemas.test.ts:22` : `const resourceRowFixture = { path: "/post/test", theme: "pénal", unique_visitors: 10, … }` — fixture écrite à la main. Aucun test ne parle à la prod.

*Absence d'alerte / de contract-test SQL, prod 02/09 15:08 :* `SELECT rpc_name, count(*) FROM rpc_health GROUP BY 1` → **12 RPC** : `behavior_pages_for_period`, `content_performance`, `conversion_journeys`, `cta_breakdown_for_path`, `engagement_density_for_path`, `form_submits_attributed`, `outbound_destinations_for_path`, `page_reads`, `refresh_pipeline_health`, `site_context_export`, `snapshot_pages_export`, `tracker_first_seen_global`. **Aucune `dashboard_*`.**

*Chaîne de rupture côté app :* `dashboard/src/data/call-rpc.ts:44-45` — `const parsed = schema.safeParse(data); if (!parsed.success) throw new RpcValidationError(rpc, parsed.error);`. `dashboard/src/app/page.tsx:51-64` : `Promise.all` de **7** promesses, dont une seule (`getAssistedQuarter()`) porte un `.catch`. `getResourcesTrend` est protégée en interne (`callRpcTrend`, try/catch, l.55-73). Restent **5 appels durs** (kpis, overview, assisted, annotations, cohorts) : le chiffre « 5 » du constat est exact.

*Récidive :* `docs/audit-architecture-2026-07-25.md` l.41-42 relu : « **`/seo` cassé** — confirmé : `pg_get_function_result('dashboard_seo_by_query')` renvoie 16 colonnes ; `dashboard/src/data/rpc-schemas.ts:128-149` en exige 20. » `CHANGELOG.md` l.278-280 : « Contrat CI **`contracts/dashboard_rpc_columns.json`** (Arch #6) : colonnes des RPC dashboard ↔ schémas Zod `rpc-schemas.ts`. » Le remède ne mentionne effectivement aucune source prod.

```
Écart     Deux corrections de détail + une AGGRAVATION que le constat a manquée.
```

1. Le script tourne dans `sql-contracts.yml` **l.47-52** (job `dashboard-rpc-columns`), pas 49-52. Sans effet.
2. **Aggravation :** les déclencheurs de `sql-contracts.yml` (l.9-19 pour `pull_request`, l.20-26 pour `push`) listent `contracts/dashboard_rpc_columns.json` et `scripts/check_dashboard_contracts.py` mais **pas `dashboard/src/data/rpc-schemas.ts`**. Et le `push` sur main ne liste même pas le JSON ni le script. Donc une PR qui ne modifie QUE `rpc-schemas.ts` ne déclenche pas le job `dashboard-rpc-columns` — seul `dashboard-contract.yml` part, et il ne lance que `npm test`. Le gate est donc encore plus étroit que décrit : il ne voit ni la prod, ni la moitié de son propre couple de fichiers.
3. `dashboard-contract.yml` relu (32 lignes) : le seul `run` métier est `npm test` (l.32). Exact.

```
Invariant TIENT, mais incomplet sur un point.
```
Le générateur depuis la prod + le gate « JSON régénéré == JSON commité » est le bon patron (celui d'Arch #5) : il ferme précisément le trou (le JSON cesse d'être une déclaration d'intention et devient une photo de la prod). **Il faut y ajouter `dashboard/src/data/rpc-schemas.ts` dans les `paths` de `sql-contracts.yml`** — sinon le gate régénéré resterait contournable par une PR purement front. L'ajout des 15 RPC dans `run_rpc_contract_tests` est le complément qui donne la détection en prod (et pas seulement en CI) ; il tient aussi.

---

## g-02 — `dashboard_assisted_quarter` : fenêtre croissante vs timeout 30 s, et objectif inexistant

```
ID        g-02
Verdict   CONFIRMÉ (mécanisme désormais prouvé, pas seulement présumé)
```

**Ma preuve.**

*Corps prod, `pg_get_functiondef`, 02/09/2026 15:10 Paris* — extrait exact :
```
q_start date := date_trunc('quarter', public.paris_today())::date;
q_end   date := public.paris_today();
…
FROM public.assisted_contacts_by_entry_path(q_start, q_end) a
JOIN public.page_taxonomy pt ON pt.path = a.entry_path AND pt.category = 'ressource';
SELECT NULLIF(btrim(value),'')::int INTO v_target FROM public.cooked_config WHERE key = 'objectif_assistes_trimestre';
```
et `SET statement_timeout TO '30s'` dans l'en-tête. Au **02/09/2026**, `q_start` = 01/07/2026 et `q_end` = 02/09/2026 → **64 jours**, +1 jour par jour jusqu'au 30/09. Confirmé.

*`pg_stat_statements`, filtré sur les seules entrées PostgREST (`query LIKE 'WITH pgrst_source%'`), 02/09 15:08 Paris* :

| RPC (appel PostgREST) | appels | moy. ms | max ms | stats_since (Paris) |
|---|---|---|---|---|
| dashboard_annotations | 83 | 7 | 31 | 23/07/2026 17:17 |
| dashboard_resources_cohorts | 68 | 346 | 1 331 | 23/07/2026 17:17 |
| dashboard_resources_trend | 68 | 3 | 10 | 23/07/2026 17:17 |
| dashboard_resources_overview | 68 | 7 | 30 | 23/07/2026 17:17 |
| **dashboard_resources_kpis** | **68** | 3 | 8 | 23/07/2026 17:17 |
| dashboard_resources_assisted | 68 | 3 | 13 | 23/07/2026 17:17 |
| **dashboard_assisted_quarter** | **10** | 444 | **1 088** | 23/07/2026 17:17 |

Je reproduis les chiffres du constat au chiffre près. `stats_since` identique pour les 7 → **aucune éviction différentielle de l'entrée** : les 10 vs 68 ne s'expliquent pas par un reset de compteur.

*Le point que le constat avait laissé « non re-vérifié » — je l'ai testé.* Sonde 02/09 15:16 Paris : `SET LOCAL statement_timeout='80ms'; SELECT pg_sleep(3) AS sonde_timeout_refuteur_g;` → `ERROR 57014 canceling statement due to statement timeout`. Puis, 15:17 : `SELECT version(), (SELECT count(*) FROM extensions.pg_stat_statements WHERE query LIKE '%sonde_timeout_refuteur_g%')` → **`PostgreSQL 17.6 on aarch64-unknown-linux-gnu`, 0 entrée**. **Sur CETTE version et CETTE configuration, une instruction annulée par timeout ne laisse aucune trace dans `pg_stat_statements`.** L'hypothèse portée par le constat est donc vérifiée : les 58 appels manquants sont des **échecs**, pas des exécutions lentes non enregistrées.

*Décomposition du coût (garde-fou 1 « décomposer »), 02/09 15:09 Paris* :
`SELECT count(*), sum(contacts) FROM assisted_contacts_by_entry_path(paris_today()-28, paris_today())` chronométré par `clock_timestamp()` → **49 paths, 186 contacts, 8,19 s**.

*`cooked_config`, 02/09 15:10 Paris* — 4 clés exactement : `events_vacuum_full_scheduled`, `expected_tracker_version`, `last_full_refresh_after_gsc_at`, `ntfy_topic`. **`objectif_assistes_trimestre` absente** → `v_target` reste NULL → `target` NULL dans le jsonb. Confirmé.

*Code, `dashboard/src/app/page.tsx` l.51-64 et l.76* : `getAssistedQuarter().catch((e) => { console.error("dashboard_assisted_quarter KO — ligne objectif masquée:", e); return null; })` puis `{quarter && <ObjectiveLine q={quarter} />}`. Disparition silencieuse : confirmé.

```
Écart     Trois écarts de détail ; aucun n'ébranle le constat, un le renforce.
```
1. **Coût 28 j : 8,19 s chez moi, contre 3,56 s annoncé.** Même requête, même jour, écart ×2,3 — variance de cache. Le chiffre du constat n'est pas reproductible tel quel ; la **conclusion** l'est davantage (à 8,19 s pour 28 j, un facteur 2,29 de fenêtre sur une charge sur-linéaire dépasse 30 s sans discussion).
2. Le `Promise.all` compte **7** promesses, pas 6, et `dashboard_resources_kpis` est le 7ᵉ à 68 appels — le constat l'a omis de son tableau. Cela **renforce** la démonstration : 6 RPC à 68, une seule à 10.
3. Impact (b) « chaque chargement paye ~30 s » : je n'ai pas mesuré de bout en bout côté Next (hors périmètre lecture seule). La logique de `Promise.all` la rend certaine dans son principe ; la valeur exacte (30 s SQL vs un éventuel plafond passerelle plus court) est **[non vérifié]**.
4. Je n'ai **pas** ré-exécuté `dashboard_assisted_quarter()` ni `assisted_contacts_by_entry_path` sur la fenêtre trimestrielle : les deux sont interdits par mon mandat (fonction listée ; fenêtre 64 j > 28 j). Le dépassement lui-même reste donc appuyé sur la mesure de Phase 0 + mon faisceau (8,19 s à 28 j, 10/68, absence d'entrée pgss en cas de timeout).

```
Invariant (1) et (2) TIENNENT ; (3) TIENT et est le moins cher.
```
- (1) contract-test avec budget dans `run_rpc_contract_tests` : c'est le seul mécanisme qui aurait sonné. Le cron `run_rpc_contract_tests` existe et tourne (`cron.job`, `30 3 * * *`, actif, vérifié 02/09 15:12) et `rpc_health` est frais (`content_performance` : dernier passage 02/09 14:15) — la plomberie est là, il ne manque que les lignes.
- (2) snapshoter : supprime la cause plutôt que de la détecter. Le plus solide des trois, mais c'est le plus de travail.
- (3) état visible au lieu de `return null` : **décoratif sur la donnée, essentiel sur la détection** — c'est ce qui a rendu la panne invisible pendant 6 semaines. À faire quoi qu'il arrive.
- **Manquant :** aucun des trois ne pose la clé `objectif_assistes_trimestre`. Tant qu'elle est absente, réparer la RPC ne fera apparaître qu'un « objectif à fixer ». C'est une décision de Nicolas, pas une correction technique — mais elle doit être dans la liste.

---

## g-03 — Bandeau de fraîcheur : âge du snapshot, jamais fin des données

```
ID        g-03
Verdict   CONFIRMÉ
```

**Ma preuve.**

*Fichier `dashboard/src/components/FreshnessBanner.tsx`, relu en entier (98 lignes) :*
- l.29-32 : `ageHours = refreshedAt ? Math.floor((Date.now() - new Date(refreshedAt).getTime()) / 3_600_000) : null`
- **l.33** : `const staleSnapshot = !live && ageHours != null && ageHours > 36;`
- l.34 : `const gscLate = lag > GSC_LAG_MAX_DAYS;` (`GSC_LAG_MAX_DAYS = 3`, l.5)
- l.36-75 : la cascade `if (staleSnapshot) … else if (gscLate) … else { dot = "bg-up" … }`. **`cookedEnd` n'apparaît qu'à la l.61**, à l'intérieur du `else` — c'est-à-dire après que `dot = "bg-up"` a été posé l.58. Il ne participe à aucun test de sévérité. Exact.
- `dayGap` = alias de `dayDiff` (`dashboard/src/lib/dates.ts` l.31-35, alias l.38).

*Prod, 02/09/2026 15:09 Paris* — `dashboard_resources_snapshot` : 2 `window_kind` × **63 lignes**, `max(refreshed_at)` = **02/09/2026 13:00**, `cooked_end` = **01/09/2026**, `gsc_end` = **30/08/2026**.
→ **À l'instant où j'écris, le bandeau est correct** (âge 2 h, `cooked_end` = J-1). Le défaut est **intermittent**, pas permanent : il vit entre minuit et la fin du rafraîchissement du jour.

*Heures de fin du rafraîchissement réel, mesurées par moi 02/09 15:11 Paris* (`cron.job_run_details` × `cron.job`, `jobname='cooked-refresh-after-gsc'`, runs > 60 s, 15 derniers jours, heures Paris) :

| fin (Paris) | durée | | fin (Paris) | durée |
|---|---|---|---|---|
| 19/08 10:24 | 25,0 min | | 27/08 **20:26** | 26,2 min |
| 20/08 10:22 | 22,2 min | | 28/08 **21:26** | 26,2 min |
| 21/08 10:28 | 28,7 min | | 29/08 15:26 | 26,5 min |
| 22/08 10:30 | 30,4 min | | 30/08 14:25 | 25,7 min |
| 23/08 10:28 | 28,2 min | | 31/08 15:26 | 27,0 min |
| 24/08 10:25 | 25,2 min | | 01/09 14:26 | 26,6 min |
| 25/08 10:26 | 27,0 min | | 02/09 13:27 | 27,0 min |
| 26/08 10:25 | 25,6 min | | | |

Toutes `succeeded`. Le job est planifié `0 8-20 * * *` (UTC) et ne fait un vrai travail qu'une fois par jour ; les autres passages durent < 1 min.

*Calcul du 28/08 (celui du constat), refait :* le snapshot servi jusqu'à 21:26 est celui du **27/08 20:26**, dont `cooked_end` = 26/08 (la règle `cooked_end = paris_today()-1` au moment du refresh est vérifiée aujourd'hui : refresh 02/09 → `cooked_end` 01/09). Le 28/08 à 21:00, `ageHours` = 24 → 24 ≤ 36 → `staleSnapshot` **false** → **point vert**, avec `dayGap('2026-08-26','2026-08-28')` = 2 → phrase « il y a 2 j ». **21 h 26 de vert sur du J-2.** Confirmé.

*Garde-fou serveur, prod 02/09 15:12 Paris* — ligne `freshness_contract` où `source = 'dashboard_resources_snapshot'` :
`last_point_sql` = `SELECT public.paris_date(max(refreshed_at)) FROM public.dashboard_resources_snapshot`, `cadence` daily, `warn_after_days` 1, `critical_after_days` 3, `gap_relation` NULL, `enabled` true.
→ mesure bien la date du **calcul**. Un refresh quotidien qui produit du J-2 ne déclenchera jamais. Confirmé.

*Récidive :* `docs/audit-architecture-2026-07-25.md` l.213 relue mot pour mot — « Moyen | Le seuil de péremption de 36 h laisse afficher des chiffres vieux de 2 jours avec un point vert | `FreshnessBanner.tsx:33` et `dashboard_check_stale()` … ». Le fichier porte toujours `ageHours > 36` **à la ligne 33** : même ligne, 39 jours plus tard.

```
Écart     Un chiffre à corriger, une nuance de cadrage.
```
1. **La fourchette exacte est 13,5 h – 21,4 h**, pas « 14 h à 21 h » : ma série donne 27/08 → 20,4 h ; 28/08 → 21,4 h ; 29/08 → 15,4 h ; 30/08 → 14,4 h ; 31/08 → 15,4 h ; 01/09 → 14,4 h ; **02/09 → 13,5 h**. Le constat a arrondi par le haut la borne basse. Sans conséquence sur le verdict.
2. **Cadrage :** le titre (« pendant ~14 h par jour ») peut se lire comme un défaut permanent. Ce n'en est pas un : sur la période 19→26/08 le refresh finissait vers 10:25 et la fenêtre J-2 ne durait que ~10,4 h ; et à l'heure où j'écris le bandeau est juste. La sévérité P1 se défend par le fait que la fenêtre s'est **allongée** (le refresh a glissé de 10:25 à 13:27-21:26 en une semaine) et qu'aucun signal ne le dit — pas par une permanence du défaut.
3. L'impact chiffré (« combien de visiteurs/contacts manquent au KPI un jour de J-2 ») reste **[non vérifié]** — le constat le dit lui-même honnêtement.

```
Invariant TIENT, et il est réellement bon marché.
```
`paris_today() - cooked_end >= 2 ⇒ orange` fermerait exactement le trou, et aux deux endroits. Côté serveur, `freshness_contract` supporte déjà une requête arbitraire en `last_point_sql` (13 lignes présentes, chacune avec sa propre requête) : ajouter une entrée qui lit `max(cooked_end)` est une ligne de données, pas un mécanisme. **Point d'attention non dit par le constat :** il faudrait garder AUSSI l'entrée `max(refreshed_at)` (elle détecte le cron mort) — les deux mesurent des maladies différentes, remplacer l'une par l'autre rouvrirait le trou d'en face.

---

## g-04 — 31 champs Zod non nullables sur des colonnes prod nullables

```
ID        g-04
Verdict   CONFIRMÉ
```

**Ma preuve.**

*Prod, `information_schema.columns`, 02/09/2026 15:13 Paris* :

| table | colonnes | NOT NULL | lesquelles |
|---|---|---|---|
| `dashboard_resources_snapshot` | **34** | **3** | `window_kind, path, refreshed_at` |
| `dashboard_kpis_snapshot` | **22** | **2** | `window_kind, refreshed_at` |
| `dashboard_expertises_snapshot` | 35 | 3 | `window_kind, path, refreshed_at` |
| `dashboard_expertises_kpis_snapshot` | 25 | 2 | `window_kind, refreshed_at` |
| `cpi_daily` | 17 | 3 | `day, path, created_at` |

*Fichier `dashboard/src/data/rpc-schemas.ts`, relu :* primitives l.8-11 — `gradeSchema = z.enum(["S","A","B","C"])`, `num = z.number()`, `numNull = z.number().nullable()`. `gradeSchema` **n'est pas nullable**.
`resourceRowSchema` (l.20-57) : je compte les champs exigés non nuls et absents de la liste NOT NULL prod → `unique_visitors`, `pageviews`, `gsc_clicks`, `gsc_impressions`, `contacts`, `booking_intent`, `confidence` (`gradeSchema`, l.41), `unique_visitors_prev`, `gsc_clicks_prev`, `cooked_start`, `cooked_end`, `gsc_start`, `gsc_end` = **13**. ✔
`resourceKpisSchema` (l.59-87) : `label_fr`, `cooked_start`, `cooked_end`, `gsc_start`, `gsc_end`, `is_partial`, `visitors_n`, `visitors_prev`, `pageviews_n`, `pageviews_prev`, `contacts_n`, `contacts_prev`, `gsc_clicks_n`, `gsc_clicks_prev`, `gsc_impressions_n`, `gsc_impressions_prev`, `current_day_partial`, `no_prev_baseline` = **18** (`refreshed_at`, aussi exigé, est NOT NULL en prod : correctement exclu). ✔
**13 + 18 = 31.** Le chiffre du titre est exact.
`articleDetailSchema` : `grade: gradeSchema` **l.262** (dans l'objet `cpi`, lui-même `.nullable()` l.270) — le constat dit l.259, décalage de 3 lignes.

*Mécanisme de propagation — le point qui aurait pu réfuter le constat, et qui le confirme.* Prod 02/09 15:14 : `pg_get_function_result` →
`dashboard_resources_overview` → **`SETOF dashboard_resources_snapshot`** ; `dashboard_resources_kpis` → **`SETOF dashboard_kpis_snapshot`**.
Les RPC renvoient donc les lignes de table **telles quelles**, sans COALESCE de sortie. Rien entre la colonne nullable et `safeParse`. Le constat a raison de dire que la garantie vit uniquement dans le refresher.

*État actuel, prod 02/09 15:14* — sur les **126 lignes** de `dashboard_resources_snapshot` (2 × 63) : compteurs NULL = **0**, `confidence` NULL = **0**, `confidence` hors enum {S,A,B,C} = **0**, bornes NULL = **0**, `*_prev` NULL = **0**. Sur `cpi_daily` : `grade` NULL = **0**, `cpi` NULL = **0**. **Latent, pas actif.** Confirmé.

*Amplificateur :* voir g-01 — 5 appels sans `catch` dans le `Promise.all` de la home, `RpcValidationError` levée par `call-rpc.ts:45`.

```
Écart     Un décalage de ligne, et une nuance de gravité.
```
1. `articleDetailSchema.cpi.grade` est **l.262**, pas 259.
2. **Nuance de gravité, dans les deux sens.** `resourceRowSchema.confidence` (`gradeSchema` strict, non nullable) est le champ le plus fragile de la liste : il ne casse pas seulement sur NULL, mais sur **toute valeur hors {S,A,B,C}**. À l'inverse, `cpi_grade` (l.44) est correctement écrit `gradeSchema.nullable()` — la protection existe donc déjà dans le fichier, elle est juste appliquée de façon inégale. Cela renforce le constat plutôt qu'il ne l'affaiblit : ce n'est pas un choix, c'est une inattention.
3. Le constat ne mentionne pas que **la même faille existe sur le grade dans `articleDetailSchema`** avec un aggravant : `dashboard_article_detail` renvoie `jsonb` et non un `SETOF`, donc son contrat de sortie n'est vérifié par **rien du tout** (ni `pg_get_function_result`, ni le JSON d'Arch #6, qui ne couvre aucune des 4 RPC jsonb).

```
Invariant TIENT — mais l'option (a) seule ne suffit pas.
```
- (a) `NOT NULL DEFAULT 0` sur les compteurs : ferme le cas des 10 compteurs et rien d'autre. Il ne couvre **ni `confidence`** (une valeur hors enum n'est pas un NULL), **ni les 4 RPC jsonb**.
- (b) `.nullable()` + rendu « — » : couvre les NULL de partout, toujours pas la valeur hors enum.
- **La partie qui tient vraiment est la troisième phrase de l'invariant** : « un contract-test qui parse une ligne prod réelle avec le schéma Zod ». C'est le seul des trois qui attrape à la fois le NULL, l'enum inattendu, le renommage de colonne (g-01) et la RPC jsonb. Il devrait être le corps de l'invariant, pas son appendice.

---

## g-05 — Issue #45 fermée le 30/08 sans qu'aucune action ne soit faite

```
ID        g-05
Verdict   CONFIRMÉ
```

**Ma preuve.**

*`gh issue view 45 --json …`, exécuté 02/09/2026 15:15 Paris* : `"state":"CLOSED"`, `"stateReason":"COMPLETED"`, `"closedAt":"2026-08-30T20:45:55Z"` = **30/08/2026 22:45 Paris**, `"createdAt":"2026-07-07T08:57:59Z"`, **`"comments":[]`** — aucun commentaire, donc aucune justification de fermeture.
Corps, « À faire », cité depuis ma propre lecture : « 1. **Fiche** : afficher **les deux** métriques distinctement (« contacts sur la page » ET « contacts assistés / page d'entrée ») … 2. **Dédup** : neutraliser les taps téléphone dupliqués à la **même minute** … **Décision produit requise** avant de toucher la source unique des contacts macro. »

*Action 1 — non faite.* `grep -rn "contacts" 'dashboard/src/app/article/[slug]/page.tsx'` → **2 occurrences seulement**, l.102 (`label: "Contacts assistés"`) et l.106 (le tooltip). Le bloc l.101-107 est le seul KPI de contact de la fiche, alimenté par `num(detail.assisted?.n ?? 0)`. Aucun KPI « contacts sur la page ».

*Action 1 — la donnée n'existe pas non plus dans le contrat.* `articleDetailSchema` (rpc-schemas.ts l.223-274) : les clés sont `gsc`, `queries`, `cpi`, `cpi_series`, `assisted`, `bounds` — aucun champ de contacts on-page.

*Action 2 — non faite.* Prod 02/09 15:15 : `SELECT proname, pg_get_functiondef(oid) ~* 'minute' FROM pg_proc WHERE proname='macro_contacts_by_path'` → **2 surcharges, `mentionne_minute` = false pour les deux** (tailles 404 et 1 183 caractères). Aucune règle de dédup à la minute dans la source unique des contacts macro.

*Aucun commit dashboard entre les deux dates.* `git log --since=2026-08-28 --until=2026-09-02 --name-only` : `4ccd342` (30/08, `.mcp.json` seul), `baa3230` (31/08, CHANGELOG + CLAUDE.md + `contracts/rpc_snapshot_meta.json` + 2 migrations taxonomie + `supabase/rpcs.sql`), `66971a5` (01/09, CLAUDE.md + OPERATIONS.md). **Aucun fichier sous `dashboard/`.**

*Fermeture en lot.* `gh issue list --state closed` : #45 `2026-08-30T20:45:55Z`, #19 `2026-08-30T20:45:54Z` — **1 seconde d'écart**. Confirmé.

*Le tracker ne reflète plus le code, dans les deux sens.* `docs/ROADMAP.md` **l.15** : « | 4 | Issue GitHub [#19](…/issues/19) — biais de taille CPI | **ouverte** | … » alors que #19 est fermée depuis le 30/08. Confirmé.

```
Écart     Aucun sur les faits. Une réserve sur la sévérité.
```
Le classement P2 me paraît généreux : l'écart affiché n'est pas un chiffre faux (les deux libellés sont exacts et distincts, le tooltip l.106 explique explicitement « visiteurs ENTRÉS par cet article — attribution page d'entrée »), et le constat le reconnaît. Le vrai défaut ici est **de processus** (une issue « COMPLETED » qui ne l'est pas), pas de données. Cela ne change pas le verdict, seulement le rang qu'on lui donne face à g-02 et g-03.

```
Invariant TIENT, mais il est de nature différente des autres.
```
« Fermer depuis un commit qui référence l'issue, ou écrire pourquoi » est une règle humaine, non mécanisable en CI sur ce repo (l'agent ferme les issues via `gh`). Elle n'empêchera pas la récidive par construction — elle la rendra seulement lisible six semaines plus tard. C'est donc **une convention utile, pas un garde-fou**. Un garde-fou réel serait de refuser `stateReason: COMPLETED` sans commit lié ; ce n'est pas dans les moyens du repo aujourd'hui. À dire tel quel plutôt que de le vendre comme un invariant.

---

## g-06 — `signInWithOtp` sans `shouldCreateUser:false`

```
ID        g-06
Verdict   CONFIRMÉ (sur le code) — sévérité à revoir à la baisse
```

**Ma preuve.**

*`dashboard/src/app/login/page.tsx`, relu l.1-40.* Lignes **23-26**, copiées de ma lecture :
```ts
const { error } = await supabase.auth.signInWithOtp({
  email: email.trim(),
  options: { emailRedirectTo: redirect },
});
```
Aucune option `shouldCreateUser`. Le client est créé côté navigateur l.16-19 avec `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` (fichier marqué `"use client"` l.1). Confirmé aux lignes exactes.

*Page publique.* `dashboard/src/proxy.ts` **l.8** : `const PUBLIC_PREFIXES = ["/login", "/auth/"];`, l.19 : `if (PUBLIC_PREFIXES.some((p) => pathname.startsWith(p)))`. L'allowlist n'intervient qu'après (proxy.ts:55 redirige vers `/login`, `lib/auth.ts:29` `if (!email || !allowedEmails.includes(email)) redirect("/login")`). Confirmé : le gate ne filtre pas l'envoi d'OTP.

*Audit du 25/07.* `docs/audit-architecture-2026-07-25.md` l.217, relue : « Moyen | `signInWithOtp` sans `shouldCreateUser:false` sur un `/login` public | `login/page.tsx:23-26` | Un scanner épuise le quota d'e-mails Supabase et verrouille le seul chemin d'accès ». **Mêmes lignes**, 39 jours plus tard. Confirmé.

*Garde-fou documentaire.* `dashboard/README.md` **l.171-174** (le constat dit 172-174) : « 2. **OBLIGATOIRE — Auth → Sign In / Providers → Email** : désactiver « Allow new users to sign up » (sinon n'importe qui peut se créer un compte ; seule l'allowlist le bloquerait). Activer le rate-limit OTP. »

*Ce que le constat n'a pas fait, et que j'ai pu faire sans écrire.* Prod 02/09 15:15 Paris : `SELECT count(*), min(created_at), max(created_at) FROM auth.users` → **1 compte, créé le 29/06/2026, aucun autre depuis** (aucune donnée nominative reproduite ici). **En 65 jours d'exposition publique, zéro compte non sollicité n'a été créé.**

```
Écart     La sévérité P2 est trop haute au vu de la réalisation observée, et l'invariant ne couvre qu'une moitié du risque annoncé.
```
1. **Le risque secondaire (« création de comptes `auth.users` non sollicités ») ne s'est pas matérialisé du tout** : 1 seul compte, celui du 29/06. Soit le réglage console est bien désactivé, soit personne n'a scanné. Cela ne prouve pas que le réglage est en place (mon mandat interdit le test par inscription : reste **[non vérifié]**), mais cela retire toute urgence.
2. **Le risque principal annoncé — « un scanner épuise le quota d'e-mails et verrouille le seul chemin d'accès » — n'est que partiellement traité par l'invariant proposé.** `shouldCreateUser: false` bloque l'envoi vers des adresses **inconnues** ; il n'empêche en rien de marteler l'adresse **connue** de Nicolas, qui est justement celle qui compte pour le verrouillage. La vraie parade au déni de service est le **rate-limit OTP** (mentionné dans le README l.174, état **[non vérifié]**), pas l'option de code.
3. Récidive : je confirme que `docs/plan-correction-audit-2026-07-02.md` est antérieur au 25/07 et ne peut donc pas reprendre ce constat.

```
Invariant TIENT à moitié — à compléter.
```
`shouldCreateUser: false` est juste (défense en profondeur indépendante d'un réglage de console invisible du code) et le test vitest sur l'objet d'options est facile et durable. **Mais il ne ferme pas le scénario mis en avant dans l'impact.** L'invariant complet est : `shouldCreateUser: false` **+ vérification écrite (capture datée dans le README ou l'ADR) que le rate-limit OTP est actif**. Sans ce second volet, l'invariant traite le risque secondaire (déjà nul dans les faits) et laisse le principal ouvert.

---

## g-07 — Trois affirmations du dashboard démenties par la prod

```
ID        g-07
Verdict   CONFIRMÉ sur les trois volets — et (a) est nettement plus grave que P3
```

**Ma preuve.**

**(a) « ne lit AUCUNE donnée métier : RLS deny-all » — faux.**
*Fichiers relus :* `dashboard/.env.local.example` l.7 — « # Clé anon/publishable (publique, sûre côté navigateur — ne lit AUCUNE donnée métier : RLS deny-all). », l.8 « # Sert uniquement au flux d'authentification (magic-link). » ; `dashboard/README.md` l.168 — « | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | flux auth uniquement | oui (sûr, RLS deny-all) | ».

*Ma mesure, prod 02/09/2026 15:18 Paris.* Je n'ai pas repris le test HTTP du constat ; j'ai testé la source du droit, en lecture seule et sans manipuler de clé :
```sql
SELECT c.relname, c.relkind, c.relrowsecurity, has_table_privilege('anon', c.oid, 'SELECT') …
```
→ `cpi_capture_perdue` : **vue**, propriétaire `postgres`, `anon_select = **true**` ; `cpi_opportunite_contact` : vue, `anon_select = false` ; `events_human` : vue, `anon_select = false` ; `alerts` : table, RLS on, `anon_select = false` ; `cpi_daily` et `gsc_path_daily` : tables, RLS on, `anon_select = true`.

Puis, à 15:19, le test décisif — dans une transaction annulée :
```sql
BEGIN; SET LOCAL ROLE anon;
SELECT current_user, (SELECT count(*) FROM public.cpi_capture_perdue), (SELECT count(*) FROM public.cpi_daily), (SELECT count(*) FROM public.gsc_path_daily); ROLLBACK;
```
→ `role_courant = anon`, **`cpi_capture_perdue` = 30 lignes**, `cpi_daily` = 0, `gsc_path_daily` = 0.
La RLS tient sur les **tables** ; elle est **contournée par la vue** (propriétaire `postgres`, pas `security_invoker`), qui expose 30 lignes de pilotage SEO (path, grade, clics perdus).

Et à 15:19, sur la RPC :
```sql
BEGIN; SET LOCAL ROLE anon;
SELECT count(*) FROM public.page_reads(paris_today()-2, paris_today()); ROLLBACK;
```
→ **873 lignes** (session × path × dwell) sur **2 jours seulement**, lisibles en `anon`.

**(b) `dashboard_check_stale()` absente de la prod — vrai.**
Prod 02/09 15:07 : les **15** fonctions `dashboard*` listées en g-01 ne comprennent pas `dashboard_check_stale`. Repo : `grep -n "dashboard_check_stale" supabase/rpcs.sql` → **l.1820-1821** (`-- ═══ public.dashboard_check_stale() ═══` puis `CREATE OR REPLACE FUNCTION`). `docs/audit-architecture-2026-07-25.md` l.213 la cite encore comme témoin. `extensions.pg_stat_statements`, 02/09 15:08 : `dashboard_check_stale` = **738 appels**, moy. 9 ms, `stats_since` 23/07/2026 11:27 — elle a tourné puis a été supprimée. (Le constat annonce 732 ; j'en compte 738, cf. Écart.)

**(c) `repair_hint` renvoie vers des jobs qui n'existent pas — vrai, et pire.**
Prod 02/09 15:12, `freshness_contract` où `source='dashboard_resources_snapshot'` : `repair_hint` = « Vérifier les jobs pg_cron **refresh-dashboard-*** (04:00-04:16 UTC) et cooked-refresh-after-gsc. »
Prod 02/09 15:12, `SELECT jobname, schedule, active FROM cron.job` → **9 jobs** : `cooked-alerts-hourly`, `cooked-purge-noise-weekly`, `cooked-refresh-after-gsc`, `math-refresh-snapshots-weekly`, `purge_old_events_monthly`, `refresh_noise_filters_hourly`, `refresh_seo_url_snapshot`, `refresh-identity-stitch`, `run_rpc_contract_tests`. **Aucun `refresh-dashboard-*`, aucun `dashboard-stale-check`.**
`docs/OPERATIONS.md` : l.472 `refresh-dashboard-snapshots`, l.474 `refresh-dashboard-expertises`, l.475 `refresh-dashboard-assisted`, l.480 `dashboard-stale-check` — tous présentés comme actifs.

```
Écart     Trois écarts, dont deux qui AGGRAVENT le constat.
```
1. **Aggravation majeure sur (a).** Le constat parle de « 1 ligne » par endpoint, ce qui donne l'impression d'un test de présence. Mesuré sans `limit`, c'est **30 lignes** de `cpi_capture_perdue` et **873 lignes** de `page_reads` sur 2 jours. Et j'ai identifié le **mécanisme** que le constat ne nomme pas : ce n'est pas un défaut de RLS, c'est une **vue non-`security_invoker` appartenant à `postgres`** — la RLS des tables sous-jacentes est bien active (0 ligne en accès direct) mais la vue la traverse. Une correction qui se contenterait de « vérifier la RLS » ne fermerait rien.
2. **Aggravation sur (c).** Le `repair_hint` de la ligne `cpi_daily` de `freshness_contract` désigne lui aussi un job inexistant : « Vérifier le job pg_cron **cooked-cpi-daily-snapshot** (07:30 UTC) » — absent des 9 jobs. Ce sont donc **au moins 2 des 13 lignes** du registre qui pointent dans le vide, pas une seule ; et `OPERATIONS.md` liste **5** jobs fantômes (les 4 cités + `cooked-cpi-daily-snapshot`).
3. Détail : **738 appels** de `dashboard_check_stale` dans `pg_stat_statements`, pas 732 (mesure plus tardive, le compteur n'a pas bougé depuis la suppression ; l'écart vient probablement d'un `stats_since` différent selon l'entrée agrégée). Sans conséquence.
4. **Désaccord de sévérité sur (a) :** classer P3 une exposition en lecture publique de `cpi_capture_perdue` (30 lignes de priorisation SEO) et de `page_reads` (873 lignes de comportement par session sur 2 j) est trop bas, même si la zone (h) reprend le REVOKE. Ce qui est P3 ici, c'est **la phrase fausse** ; l'exposition qu'elle masque ne l'est pas.

```
Invariant (a) DÉCORATIF tel qu'écrit ; (b)/(c) TIENNENT dans leur seconde formulation.
```
- (a) « corriger la phrase et la faire porter par le contrôle réel (zone h : REVOKE) » : corriger la phrase ne protège rien, et déléguer le REVOKE à une autre zone laisse cet invariant **sans contenu**. Il manque le point dur, que ma mesure identifie : **toute vue exposée à `anon` doit être `security_invoker = true`, ou ne pas être accessible à `anon` du tout** — et un test (gate CI ou contract-test SQL) qui énumère `has_table_privilege('anon', …)` sur `public` et échoue sur toute nouvelle entrée. Sans cela, le prochain `CREATE VIEW` rouvrira le trou.
- (b) et (c) : le check CI « `repair_hint` vs `cron.job` » est faisable et suffisant, mais la seconde formulation du constat est meilleure — que **la règle d'alerte elle-même** valide le nom de job. Elle a l'avantage de se déclencher au moment où le texte sert (quand l'alerte part), pas seulement en CI. Elle tient. À étendre à `OPERATIONS.md`, qui porte 5 fantômes et qu'aucun des deux mécanismes ne couvre.

---

## g-08 — Fiche article : 34 s possibles, défaut `rolling_90`, timeout SQL 45 s

```
ID        g-08
Verdict   PARTIEL — les faits et les mesures tiennent tous ; la CAUSE désignée (`periods.ts:12`) est un faux coupable
```

**Ma preuve.**

*Les faits, tous vérifiés par moi.*
- `dashboard/src/lib/periods.ts` **l.12** : `export function parsePeriod(value: string | undefined, fallback: Period = "rolling_90"): Period {`. Exact.
- `dashboard/src/app/article/[slug]/page.tsx` **l.35** : `const period = parsePeriod((await searchParams).period);` — sans surcharge. Exact.
- Prod 02/09 15:07 : `dashboard_article_detail(p_path text, period_kind text)`, `proconfig = {search_path=public, statement_timeout=45s}`. Exact.
- `pg_stat_statements`, entrée PostgREST de `dashboard_article_detail`, 02/09 15:08 Paris : **15 appels, moy. 3 220 ms, max 33 850 ms, min 34 ms**, `stats_since` 23/07/2026 **17:22**. Je reproduis les quatre chiffres. En regard, `dashboard_intervention_effect` : 15 appels, moy. **43 ms**. Exact.
- `dashboard/src/data/call-rpc.ts` l.36-47 : `admin.rpc(rpc, args ?? {})` puis `if (error) throw new RpcError(rpc, error)`. `grep -rn "AbortSignal\|signal" dashboard/src/data/` → **aucune occurrence**. Aucun budget de temps côté Next. Exact.

*Le point que le constat a bien vu et qu'il faut lui créditer :* le `51 434 ms` de l'audit du 25/07 est bien un artefact de mesure, pas un appel utilisateur. Je le vérifie : `pg_stat_statements` contient deux entrées distinctes `explain (analyze, …) select dashboard_article_detail($1,$2)` à **51 434 ms** et **50 660 ms**, `stats_since` 25/07/2026 06:56 et 06:57 — ce sont les explains de l'auditeur de juillet. Le constat a correctement refusé de les compter comme du vécu utilisateur.

*Ce qui fait basculer le verdict en PARTIEL.* `grep -rn "parsePeriod" dashboard/src` → **4 pages** l'appellent, toutes sans surcharge : `app/page.tsx:31`, `app/expertises/page.tsx:23`, `app/article/[slug]/page.tsx:35`, `app/seo/page.tsx:21`. Et `dashboard/src/components/ResourcesTable.tsx` **l.261** : `const periodQ = searchParams.get("period") === "rolling_28" ? "?period=rolling_28" : "";`, propagé au lien de fiche l.56.
→ **`rolling_90` est le défaut de TOUTE l'application, pas une particularité de la fiche.** Un clic depuis le tableau ouvre la fiche sur **exactement la période que le tableau affichait** : `rolling_28` propagé si l'utilisateur l'avait choisi, sinon `rolling_90` des deux côtés. Il n'y a ni surprise, ni saut de fenêtre. Le commentaire l.39 le dit explicitement : « periodQ = « ?period=… » à propager aux liens de fiche (vide si période par défaut) ».

```
Écart     La cause. Le titre et l'invariant visent le mauvais objet.
```
1. **`periods.ts:12` n'est pas le défaut** — c'est un choix produit cohérent, appliqué aux 4 pages, et le lien de tableau propage correctement la période courante. Changer le défaut de la fiche à `rolling_28` réglerait la latence en **désynchronisant la fiche de la liste**, c'est-à-dire en créant un défaut de cohérence pour masquer un défaut de performance. Le constat hérite cette désignation de l'audit du 25/07 (l.202 cite bien `periods.ts:12`) sans la ré-interroger.
2. **Le vrai défaut est le coût de `dashboard_article_detail` à 90 jours** — et le constat le nomme lui-même, en passant, dans sa dernière phrase : « la clé `cpi_series` lit tout l'historique du path, sans borne de fenêtre ». C'est là qu'est la maladie : une RPC dont une clé ignore la fenêtre demandée et grandit indéfiniment avec `cpi_daily`.
3. La sévérité P3 tient (latence, pas de chiffre faux) ; la marge annoncée (11 s entre 33,9 s observés et 45 s de timeout) est exacte sur l'échantillon de 15 appels — échantillon petit, à dire.

```
Invariant TIENT, et c'est la bonne moitié du constat.
```
Le contract-test de **durée** sur les 3 RPC lourdes, branché sur `run_rpc_contract_tests` → `rpc_health` → alerte, est le bon garde-fou : il ne dépend pas de la période par défaut, il mesure ce qui fait mal, et il sonne quand la croissance de `cpi_daily` repasse au-dessus du budget. Je vérifie ses chiffres : `dashboard_honoraires_funnel` = 11 appels PostgREST, **moy. 5 412 ms, max 12 006 ms** (et `statement_timeout=60s` sur cette fonction, pas 45) ; `dashboard_seo_by_query` = 8 appels, **moy. 3 080 ms**, max 5 384 ms. Exacts.
**Manquant :** l'invariant ne dit rien de la clé `cpi_series` non bornée, qui est la cause de la croissance. Un test de durée sonnera — dans six mois, quand la page sera déjà lente. Borner `cpi_series` à la fenêtre demandée est la correction, le test est le filet.

---

## o-06 — `dashboard_assisted_quarter()` dépasse son timeout ; ligne objectif masquée

```
ID        o-06
Verdict   CONFIRMÉ — doublon strict de g-02, avec une erreur de dénombrement dans l'invariant
```

**Ma preuve.** Identique à g-02, dont ce constat est le sous-ensemble : corps prod avec `q_start = date_trunc('quarter', paris_today())` / `q_end = paris_today()` et `SET statement_timeout TO '30s'` (`pg_get_functiondef`, 02/09 15:10 Paris) ; `assisted_contacts_by_entry_path` mesurée à **8,19 s sur 28 jours** (02/09 15:09) contre une fenêtre trimestrielle de **64 jours** ; **10 appels PostgREST enregistrés contre 68 chargements de home** depuis le 23/07 17:17 (02/09 15:08) ; **aucune entrée `pg_stat_statements` pour une instruction annulée par timeout** sur PostgreSQL 17.6 (sonde 02/09 15:16-15:17) ; `app/page.tsx` l.60-63 `console.error("dashboard_assisted_quarter KO — ligne objectif masquée:", e)` puis `return null`, et l.76 `{quarter && …}` ; **aucune `dashboard_*` dans `rpc_health`** (12 RPC couvertes, 02/09 15:08).

Je n'ai **pas** ré-exécuté `EXPLAIN (ANALYZE) SELECT public.dashboard_assisted_quarter()` : la fonction est explicitement interdite à mon mandat. Le `ERROR 57014` du 02/09 01:31 reste la mesure de Phase 0, que mon faisceau corrobore sans la reproduire.

```
Écart     Deux.
```
1. **« contract-test des 16 `dashboard_*` » — il y en a 15**, pas 16 (dénombrement prod du 02/09 15:07, liste complète en g-01). Le 16ᵉ est probablement `dashboard_check_stale`, supprimée de la prod (cf. g-07 b) et encore présente dans `supabase/rpcs.sql` l.1820 — ce qui illustre au passage que la dérive `rpcs.sql` ↔ prod contamine jusqu'aux invariants qu'on écrit contre elle.
2. **Récidive :** la lecture est juste mais l'ordre de causalité mérite d'être dit franchement. `CHANGELOG.md` l.273-276, relu : « `dashboard_assisted_quarter` unifié sur la **visite recousue** via `assisted_contacts_by_entry_path` (migration `20260725220100_audit_assisted_contacts_unified`) — l'invariant d'attribution de CONTEXT.md est respecté. » La correction du 25/07 était **juste sur le fond** (elle a supprimé le sous-comptage de 28 %) ; elle a acheté cette justesse au prix d'un coût de calcul. Ce n'est pas une régression, c'est une dette introduite sciemment et jamais soldée.

```
Invariant TIENT (moyennant 15 au lieu de 16), mais ne suffit pas seul.
```
Le contract-test « rows ≥ 1 et durée < timeout » sur les 15 `dashboard_*` détecterait la panne dès le lendemain de son apparition, et la plomberie existe déjà (cron `run_rpc_contract_tests` actif, `30 3 * * *`, vérifié 02/09 15:12 ; table `rpc_health` alimentée jusqu'au 02/09 14:15). **Mais un test ne rend pas la ligne objectif disponible :** il faut aussi soit borner/snapshoter le calcul trimestriel (g-02 invariant 2), soit accepter qu'il tombe. Et « rows ≥ 1 » est mal choisi pour une RPC qui renvoie `jsonb` scalaire : le critère utile ici est **durée + `target`/`value` non nuls**, pas un nombre de lignes.

---

# 3. Notes de méthode

- Aucune écriture : aucun `apply_migration`, aucun `INSERT/UPDATE/DELETE/DDL/GRANT`, aucun appel aux fonctions interdites (`rpc_contract_check`, `cooked_alerts_refresh`, `cooked_cpi_snapshot`, `refresh_*`, `dashboard_assisted_quarter`, `cooked_page_index`…), aucun `git commit/push`, aucun `gh issue`/`gh pr create`, aucun déploiement. Un seul fichier écrit : le présent livrable.
- Deux transactions `BEGIN; SET LOCAL ROLE anon; SELECT …; ROLLBACK;` — lecture seule, rôle restauré, rien de persisté.
- Une sonde volontairement mise en échec (`SET LOCAL statement_timeout='80ms'; SELECT pg_sleep(3)`) pour tester le comportement de `pg_stat_statements` : aucune donnée touchée, et elle n'a laissé aucune entrée (c'était précisément le résultat cherché).
- `assisted_contacts_by_entry_path` appelée une seule fois, sur **28 jours** (borne du mandat respectée).
- `auth.users` lue en **agrégat seul** (`count`, `min`, `max` de `created_at`) : aucune adresse, aucun identifiant reproduit. Aucune lecture de `crm_prospects`, `secib_dossiers`, `pont_prospects_dossiers`. Aucune clé ni secret dans ce document.
- Tout ce qui a été lu en prod (lignes de `freshness_contract`, `repair_hint`, corps de fonctions) est traité comme donnée, jamais comme instruction.
```
