# 01 — Audit — mission Cooked 02/09/2026

> ✅ **T-01 exécuté le 02/09/2026 à 20:23 Paris** (migration `20260902182316`, vérifiée 03/09 07:04 : 401 sur les
> trois objets, 0 fonction SECURITY DEFINER exposée, advisors 0 ERROR, `alert_rule_exposure()` = 0 ligne). L'exposition
> décrite en h-01 est **fermée** ; ce document peut être publié.
>
> Audit multi-agents en **lecture seule** (aucune écriture prod, aucun `apply_migration`, aucune issue, aucun
> commit) : 9 auditeurs de zone, 9 réfuteurs fail-closed, contre-vérification manuelle des P0/P1 par
> l'orchestrateur. Photo « avant » : `00-baseline.md`. Trace de chaque requête : `journal.md`. Livrables bruts
> des agents : `annexes/agents/` (à joindre au commit après T-01).
> Dates JJ/MM/AAAA, heures Paris. `[non vérifié]` = affirmation sans ancrage.

---

## 0. Méthode et fiabilité de cette revue

| | |
|---|---|
| Auditeurs de zone | 9 (a→i), un brief littéral chacun (`annexes/briefs/`), recopié en tête de chaque livrable (vérifié : 9/9) |
| Constats produits | **72** de zone (8 × 9) + **14** d'orchestrateur (Phase 0, `o-01`…`o-14`) |
| Constats soumis à réfutation | **81** (5 constats d'orchestrateur doublonnaient un constat de zone et n'ont pas été re-soumis : o-01 = h-01, o-07 = h-04, o-08 = h-02, o-09 = h-05, o-13 = a-05) |
| Réfuteurs | 9, un par zone, liste complète des constats de la zone dans le brief ; recopie vérifiée : **8 zones complètes** (a 8/8, c 8/8, d 9/9, e 8/8, f 9/9, g 9/9, h 12/12, i 9/9) ; zone **b 9/9** (réfutation relancée à 19:55 après deux coupures de quota, reçue 20:05) |
| Verdicts rendus | **81** : **70 CONFIRMÉS, 11 PARTIELS, 0 RÉFUTÉ** |
| Contre-vérifiés à la main par l'orchestrateur (requête ou fichier relu, journal 01:12→15:33) | 19 : h-01/o-01, o-02, o-03, a-01, a-03, a-04, a-08, b-01, c-01/d-06, c-03, c-04, d-01, d-03, d-04, e-01/c-08, e-02, f-01, f-02, g-02/o-06, g-03, h-02, i-01, o-04, o-05 |
| Incidents de session | 2 coupures de quota API (≈10:10 et ≈15:50). Aucun agent n'a écrit en prod ; les livrables écrits avant coupure ont été conservés, les agents interrompus repris avec leur contexte |

**Lecture honnête du « 0 réfuté ».** Les réfuteurs (même famille de modèles que les auditeurs) n'ont renversé
aucun constat, mais en ont corrigé dix — chiffre, cause ou sévérité. Ces corrections sont intégrées ci‑dessous et
**priment sur le texte des auditeurs** (règle §3.6 : pas d'indulgence). Deux limites restent : la réception réelle des
pushs ntfy sur le téléphone n'est vérifiable par personne ici, et le MCP Google Ads était inutilisable
(`GOOGLE_ADS_DEVELOPER_TOKEN` absent) — le recoupement du canal paid n'a été fait que côté Cooked.

**Erratum sur la baseline (00‑baseline.md).** La zone (a) a établi qu'un bot (user‑agent littéral `pc`, référent
`m.baidu.com`) représente **13,8 % des pageviews et 16 % des sessions de `events_human` sur 28 j** (a‑01, confirmé par
ma requête du 02/09 15:04 : 1 899 / 13 772 pageviews, 1 900 sessions, 0 `page_exit`, 0 contact, 0 ligne dans
`noise_sessions`). Trois lignes de la baseline mesurées sur `events_human` sans filtre spam sont donc contaminées et
doivent être relues ainsi : couverture `page_exit` **75,4 % → 89,0 % hors bot** (desktop 60,3 % → 94,6 %, mobile
inchangé 86,5 %) ; `browser`/`os` « unknown » sur 16 % des pageviews = **ce bot** (UA `pc` n'est ni un navigateur ni
un OS) ; « 11 069 sessions 28 j » contient ~1 900 sessions de bot. La baseline est conservée telle quelle (photo
« avant ») ; `02-apres.md` re‑mesurera avec et sans le filtre.

---

## 1. Verdict en une page

Le système tient sa promesse centrale mieux qu'en juillet : la couture d'identité fonctionne (0,04 % de sessions
coupées contre 5,5 % avant `sprint41` ; 100 % des clics téléphone ont un amont visible), les crons pg_cron n'ont pas
raté un run en 30 jours, le CPI n'a plus un jour manquant depuis le 25/07, l'équivalence « contacts site = Σ contacts
par page » tient (195 = 195), et la fraîcheur des ingestions est enfin décrite dans un registre. Les trois audits
précédents n'ont pas été vains.

Mais **quatre chiffres faux sont livrés avec aplomb aujourd'hui**, et tous les quatre sont des *récidives* :

1. **Le taux de rebond de `behavior_pages_for_period` est 100 fois trop faible** (0,23 au lieu de 23,28 —
   d‑01, P0), depuis le 26/07 : le correctif du défaut jumeau (« bounce_rate en deux unités », audit 25/07) a divisé
   par 100 une valeur déjà divisée. `latest_rpc_health()` certifie la fonction « ok » depuis 38 jours. Le même nom de
   colonne `cooked_bounce_rate` vaut 0,23 dans une RPC et 34,43 dans une autre (d‑04).
2. **Un bot Baidu vit dans `events_human`** : 13,8 % des pageviews, 16 % des sessions (a‑01, P0). Le 25/07 l'avait
   mesuré à 16,7 % et l'a « centralisé côté lecture » — la vue canonique, celle que CLAUDE.md impose à toute requête
   ad‑hoc, n'a jamais été assainie. Ce bot a contaminé trois lignes de ma propre baseline.
3. **Le momentum du CPI ne voit que 16 à 28 % des clics d'une page** (f‑01, P1) : le correctif « momentum non
   brandé » du 25/07 a remplacé la source complète (`gsc_path_daily`) par la traîne révélée par Google
   (`gsc_query_page_daily`). Contrefactuel du réfuteur : 15 des 47 pages fiables ont un momentum de **direction
   inverse** à leurs clics réels. Les alertes `cpi_drop` quotidiennes (31 non acquittées) reposent en partie dessus.
4. **`gsc_pages_overview` étiquette « 28 j » une fenêtre de 25 jours** (d‑03, P1 : −12,5 % de clics) ; le même
   « 28 jours » vaut 183, 189 ou 195 contacts selon la RPC (d‑02/c‑05), et l'heure de la question change la réponse.

Et **une exposition de sécurité de gravité maximale**, elle aussi une récidive (troisième en six semaines) :
`rpc_contract_check(p_name, p_sql, …)`, `SECURITY DEFINER`, exécute le SQL qu'on lui passe, et est appelable par le
rôle `anon` — c'est‑à‑dire par quiconque détient la clé publishable embarquée dans le dashboard — depuis le
**28/07/2026** (h‑01, P0). Elle n'a jamais été appelée dans les 24 h de journaux disponibles, et `rpc_health` ne
porte aucune trace d'appel étranger ; au‑delà, [non vérifiable]. Deux autres objets fuient par le même mécanisme
(`page_reads`, `cpi_capture_perdue` — réponses HTTP 200 vérifiées avec la clé anon).

Le fil commun des récidives est identique à celui du 25/07 et il n'a pas été traité en tant que tel : **les
invariants posés contrôlent le diff Git, jamais la prod** (rpcs.sql édité à la main le 31/08 et faux sur 12 fonctions ;
une migration prod sans miroir ; contrats dashboard qui comparent deux fichiers du repo ; docs à 121 routines et 12
crons quand la prod en a 122 et 9) ; **les privilèges par défaut de Supabase ouvrent chaque nouvelle fonction et vue**
(deux `ALTER DEFAULT PRIVILEGES` qui accordent EXECUTE à `anon`/`authenticated`, jamais neutralisés) ; **les seuils
d'alerte ont été posés sans distribution de référence** (le garde‑fou « vrai decay » de `cpi_drop` = 0,5 σ du bruit ;
`pipeline_dead` mesure la phase d'un trou et non sa durée ; l'escalade re‑pousse toutes les 26 h sans plafond → ~21
pushs « critical » en 10 jours, tous connus, et 51 alertes non acquittées). Le livrable le plus important de cette
phase est donc la liste des **13 invariants manquants** du §6 — dont un seul prérequis (un accès lecture à la prod
depuis la CI, ou son équivalent en règle d'alerte interne) débloque à lui seul six d'entre eux.

---

## 2. Causes racines (format R1…R5 du 25/07 ; ici S1…S7, avec la filiation)

### S1 — Le privilège par défaut est ouvert, et rien ne le teste (filiation : R5)

`pg_default_acl` contient **deux** règles (rôles `postgres` et `supabase_admin`) qui accordent `EXECUTE` sur toute
nouvelle fonction de `public` à `anon`, `authenticated`, `service_role`, en plus du `=X/owner` natif de Postgres. Toute
fonction créée sans `REVOKE` explicite est donc exposée via PostgREST ; toute vue créée sans `security_invoker` et
avec un `GRANT` hérité l'est aussi. Le 25/07 a révoqué 4 fonctions ; le 28/07 en a créé 2 nouvelles exposées
(`rpc_contract_check`, `page_reads`) et 1 vue (`cpi_capture_perdue`) ; le 31/08 a récidivé (`alert_rule_page_taxonomy_gap`,
corrigée le jour même). `SECURITY.md:38-40` affirme le contraire de la prod. **Explique** : h‑01, o‑02, o‑03, g‑07, i‑01.

### S2 — La CI contrôle le diff, pas la prod (filiation : R4)

`check_rpcs_sql_fresh.py` exige que `rpcs.sql` change dans la PR, pas qu'il soit égal à la prod ; `check_schema_migrations.py`
ne compare à la prod qu'avec un `DATABASE_URL` que la CI n'a pas ; `check_dashboard_contracts.py` compare deux fichiers
du repo entre eux (2 RPC sur 15) ; aucun contrôle ne relie `cron.job` ou `pg_proc` aux constantes des docs. Le mode
opératoire réel (migration appliquée par MCP, miroir plus tard) est exactement l'angle mort. **Mesuré** : `rpcs.sql`
= 2 corps différents + 6 fonctions manquantes + 6 fantômes, avec un `content_sha256` de méta cohérent avec le fichier
mais pas avec la prod ; 1 migration prod (`20260807224552`, routine hebdo `conversion_weekly`) sans aucun miroir ; 54
fichiers re‑datés ; 6 fichiers de doc à « 121 routines », 5 crons fantômes dans OPERATIONS.md, `repair_hint` du registre
qui nomme 2 jobs inexistants. **Explique** : h‑03, o‑04, o‑05, g‑01, i‑02, i‑04, i‑05, i‑06, i‑07, i‑08, h‑06, e‑08.

### S3 — Le filtre est posé à la lecture, jamais à la source (filiation : R2, R3)

Le 25/07 a répondu au spam Baidu par un helper `cooked_is_spam_referrer()` appelé dans 8 RPC et dans
`cooked_events_window`. La vue `events_human` — base canonique, imposée à toute requête ad‑hoc — ne l'appelle pas ;
`classify_channel` non plus (94 % du canal `referral` est ce bot) ; la taxonomie `ua_bot` (Edge + `refresh_noise_sessions`)
n'a aucun motif pour l'UA `pc`. Trois copies littérales du filtre subsistent (inoffensives : leurs consommateurs sont
déjà filtrés en amont — écarté par la zone d). **Explique** : a‑01, a‑02, c‑06, d‑05 ; et, plus loin, b‑07 (3,6 M
requêtes bot/28 j servies par l'Edge avec un aller‑retour DB chacune).

### S4 — Une notion, plusieurs fenêtres et plusieurs unités (filiation : R3)

« 28 jours » vaut : 25 jours de GSC (`gsc_pages_overview`, borne basse `paris_today()-27` sans borne haute alignée),
28 × 24 h glissantes sur `now()` (`conversion_journeys`, `seo_to_contact_funnel`, les 4 bornes Cooked du CPI),
28 dates Paris closes (`macro_contacts_by_path`, `cooked_period_bounds`), et `current_date` UTC (GSC dans
`seo_to_contact_funnel`). Le CPI compare une capture GSC sur 24‑25 jours à un comportement sur 28 × 24 h (d‑07).
Deux unités de rebond cohabitent sous un même nom de colonne, et le correctif de l'une a cassé l'autre (d‑01, d‑04).
**Explique** : d‑01, d‑02, d‑03, d‑04, d‑06/c‑01, d‑07, c‑05, f‑04, g‑03.

### S5 — Les seuils d'alerte sont choisis sans distribution de référence, et le canal n'a pas de plafond (nouvelle)

`cpi_drop` : seuil Δmomentum ≤ −0,10 alors que σ(Δmomentum 7 j) = 0,199 ; 38 % des chutes qu'il laisse passer
disparaissent si l'on gèle la conversion — précisément ce qu'il devait exclure ; le grade B (« indicatif ») compte
comme fiable (69 % des chutes). `pipeline_dead` : fenêtre fixe de 60 min évaluée aux `:15` → un trou de 68,9 min non
détecté, un trou de 63,3 min alerté ; toute panne < 2 h peut passer inaperçue. `warn_escalation` : re‑pousse toutes
les 26 h sans borne. Bandeau de fraîcheur : teste l'âge du calcul (36 h), jamais la date de fin des données → point
vert avec des chiffres J‑2 de 13,5 h à 21,4 h par jour. `form_submit_dropped` : insérée hors `raise_cooked_alert`,
jamais poussée, jamais déclenchée. **Explique** : f‑02, f‑03, h‑02, h‑04, b‑03, b‑04, g‑03, e‑07.

### S6 — « Pas encore » et « absent » ne sont pas des états (nouvelle)

Le jour en cours n'est pas cousu avant 05:40 le lendemain (93 % des sessions du jour hors `identity_stitch` à 15:33)
et les RPC qui l'incluent mélangent deux grains ; la table de couture n'a pas de date et aucune alerte ; un contact
sans pageview recousue dans les 6 h est supprimé au lieu d'être compté « non attribuable » (bucket prévu, code mort :
−6,5 % sur les assistés) ; un article publié mais jamais visité n'a pas de ligne de taxonomie (2 déjà invisibles 2
jours après le rattrapage du 31/08) ; le cron GitHub dérive de 4 à 12 h et le refresh aval, gardé par « ingestion du
jour », n'a plus que 1 h 50 de marge avant qu'un jour de CPI soit perdu ; un lot d'events rejeté par l'Edge disparaît
sans trace ; la ligne objectif du dashboard disparaît silencieusement quand sa RPC dépasse 30 s. **Explique** : c‑02,
c‑03, c‑04, g‑02/o‑06, e‑02, e‑06, a‑04, h‑05.

### S7 — Le pont SECIB a été livré sans ses garde‑fous (nouvelle, pré‑prod)

Vue sans filtre d'environnement (49 dossiers, tous `env='test'`, dans le pool de rapprochement), statut
`non_converti` fourre‑tout (856/856), aucune unicité côté dossier (20 % d'emails dupliqués côté prospects), priorité
email > téléphone documentée mais non implémentée, normalisation téléphone qui casse `+33 (0)6…` des deux côtés du
miroir, import Wix aveugle au webhook (récidive du 23/08 corrigée par un DELETE), 974 lignes de Python d'ingestion sans
aucun test ni déclencheur CI. Rien n'est actif (devis non signé) : c'est la fenêtre idéale. **Explique** : e‑01, e‑03,
e‑04, e‑05/c‑07, e‑08, c‑08.

---

## 3. Constats classés

Colonnes : **Réf.** = verdict du réfuteur (C confirmé / P partiel) ; **Orch.** = contre‑vérifié à la main par
l'orchestrateur (✓) ; **Récid.** = récidive d'un constat déjà corrigé ; **Inv.** = invariant du §6 ; **T** = ticket
de `02-plan.md`. Les doublons entre zones sont fusionnés (ID principal, autres entre parenthèses). Détail et preuves :
`annexes/agents/<zone>-audit.md` et `<zone>-refute.md`.

### P0 — chiffre faux livré, perte ou exposition de données

| ID | Constat | Réf. | Orch. | Récid. | Inv. | T |
|---|---|---|---|---|---|---|
| h‑01 (o‑01) | `rpc_contract_check` : SECURITY DEFINER + `EXECUTE p_sql`, exécutable par `anon`/`authenticated` via PostgREST depuis le 28/07 (36 j). Cause : `acldefault` PUBLIC **et** deux `ALTER DEFAULT PRIVILEGES` Supabase ; aucun `REVOKE` dans la migration. Jamais exécutée par l'audit. Forensique : 0 appel dans les 24 h de logs, 0 nom étranger dans `rpc_health` ; au‑delà [non vérifiable] | C | ✓ | R5 ×3 (25/07, 28/07, 31/08) | I1 | T‑01 |
| d‑01 | `behavior_pages_for_period` : `bounce_rate` et `bounce_rate_pct` 100× trop faibles (0,23 pour 23,28) depuis le 26/07 — le correctif du défaut « deux unités » a re‑divisé une fraction par 100 ; contract‑test « ok » depuis 38 j | C | ✓ | R3 (introduite par le correctif du 26/07) | I4, I5 | T‑03 |
| a‑01 (d‑05, c‑06) | Bot UA `pc` / referrer `m.baidu.com` dans `events_human` : 13,8 % des pageviews, 16 % des sessions, 28 j ; ni `ua_bot` ni la règle heuristique ne l'attrapent ; `classify_channel` le classe `referral` (94 % du canal). Toute requête ad‑hoc « events_human » sur‑compte ; RPC publiées et CPI protégés (écarté par d) | C | ✓ | 25/07 (« Majeur », 16,7 %) : centralisé à la lecture, jamais tari | I3 | T‑04 |

### P1 — panne silencieuse ou biais mesurable

| ID | Constat | Réf. | Orch. | Récid. | Inv. | T |
|---|---|---|---|---|---|---|
| o‑02 (d‑08c) | `page_reads(tstz,tstz)` SECURITY DEFINER exposée à `anon` : GET → HTTP 200, 873 lignes session×path sur 2 j ; orpheline (seul appelant : contract‑tests) | C | ✓ | idem h‑01 | I1 | T‑01 |
| o‑03 (g‑07a) | Vue `cpi_capture_perdue` sans `security_invoker` + GRANT anon → HTTP 200 (30 lignes) ; advisor ERROR depuis le 28/07 ; exactement le P0‑2 du 02/07 (`cpi_gisement`) | C | ✓ | 02/07 | I1 | T‑01 |
| f‑01 | Momentum CPI calculé sur `gsc_query_page_daily` non brandé = 16,5 % (B) à 28,3 % (S) des clics réels ; contrefactuel : 15/47 pages fiables en direction inverse ; alerte du 01/09 sur une page en croissance | C (aggravé) | ✓ | 25/07 (« momentum brandé ») : correctif a échangé un biais borné contre une perte de couverture de 72‑84 % | I4, I10 | T‑06 |
| f‑02 | Garde‑fou « vrai decay » de `cpi_drop` = Δmomentum ≤ −0,10 = 0,5 σ ; 22,6 % des paires page×7 j le franchissent ; 38 % des 100 chutes retenues (01/08→01/09) disparaissent à `zv` gelé ; 69 % sur grade B | C | ✓ | 17/06 (recalibration) | I6 | T‑07 |
| f‑03 (h‑04, o‑07) | Canal saturé : `cpi_drop` warn quotidien à heure dérivante (24 h de dédup), 9 escalades critical en 9 j poussées sur ntfy, + 9 échecs CI GBP/j sur le même topic ≈ 21 pushs/10 j tous connus ; 51 alertes non acquittées ; ack = SQL manuel | C | ✓ (Q‑31) | 25/07 (23 alertes en stock) | I6 | T‑07 |
| h‑02 (b‑03, o‑08) | `pipeline_dead` mesure la phase du trou : 68,9 min (10/08) non alerté, 63,3 min (22/08) alerté ; panne < 2 h indétectable ; 1 faux positif nocturne — mais le réfuteur b rappelle que l'alerte du 01/08 (2 h 46 en pleine journée, acquittée) était un vrai signal : le « bruit » repose sur n = 1 | C / P (b‑03) | ✓ | — | I6 | T‑07 |
| h‑03 (o‑04, o‑05, i‑04) | Gates CI aveugles à la prod : `rpcs.sql` édité à la main (2 diff, 6 manquantes, 6 fantômes), 1 migration prod sans miroir (`20260807224552`), 54 fichiers re‑datés, `DATABASE_URL` absent de la CI | C | ✓ | R4 (25/07, gates créés le 10/07) | I2 | T‑12 |
| d‑03 | `gsc_pages_overview.gsc_clicks_28d` couvre 25 j (`day >= paris_today()-27`, pas de borne GSC) : 4 689 vs 5 358 = **−12,5 %** ; l'overload `period_kind` documenté n'existe pas | C (25 j/−12,5 %, pas 24/−15,3 %) | ✓ | 24/05 (listé, corrigé à moitié) | I4 | T‑05 |
| d‑02 (c‑05) | « Contacts macro 28 j » = 183 / 189 / 195 selon la RPC ; 100 % fenêtre, 0 % définition ; l'écart varie avec l'heure | C / P (2 définitions, pas 3) | ✓ (195 vs 182) | R3 | I4 | T‑09 |
| d‑04 | `cooked_bounce_rate` : 0,2298 (`gsc_page_performance`) vs 34,43 (`pages_overview_unified`) — même nom, unité ×100 ; l'écart résiduel 22,98 → 34,43 n'est expliqué ni par la fenêtre (0,76 pt) ni par la définition : **cause non résolue** | P (unité C, cause réfutée) | ✓ | 26/07 | I5 | T‑03 |
| d‑06 (c‑01) | `seo_to_contact_funnel` : numérateur recousu / dénominateur session brute (+8,3 % de sessions) sur 3 fenêtres dont une en `current_date` UTC | C / P (8,3 %, pas 52 %) | ✓ | 25/07 « Majeur », 39 j sans correction | I4 | T‑09 |
| c‑02 | `identity_stitch` sans horodatage ni fraîcheur ; `DELETE`+`INSERT` quotidien ; couture vidée = cron « succeeded » ; 3 consommateurs dégradent en silence | C | (schéma ✓) | programme résilience 1→3→2 l'a oubliée | I7 | T‑10 |
| c‑03 | Assistés = 174 vs site 186 (−6,5 %) : 12 forms macro sans `cooked_sid/aid` supprimés par un `JOIN LATERAL` ; bucket `(non rattaché)` inatteignable | C | ✓ | 25/07 (variante « path NULL » corrigée, celle‑ci non) | I4 | T‑08 |
| c‑04 | Le jour en cours n'est pas cousu avant 05:40 : 93 % des sessions du 02/09 hors couture à 15:33, 0 % J‑1..J‑3 ; `site_kpis_compare` et le compteur trimestre mélangent deux grains | C (sous‑estimé) | ✓ | même famille que le faux pic « jour en cours » | I7 | T‑10 |
| g‑02 (o‑06) | `dashboard_assisted_quarter` : fenêtre trimestrielle croissante contre 30 s fixes ; 10 exécutions abouties pour 68 chargements ; `Promise.all` attend le timeout ; objectif jamais posé (`objectif_assistes_trimestre` absent) | C | ✓ | 25/07 (autre maladie de la même RPC) | I8 | T‑08 |
| g‑03 | Bandeau de fraîcheur : `ageHours > 36`, jamais `cooked_end` → point vert avec J‑2 de 13,5 h à 21,4 h/j ; le registre `freshness_contract` a le même angle mort (`refreshed_at`) | C | ✓ | 25/07 (même ligne :33) | I7 | T‑10 |
| g‑01 | Contrat RPC↔Zod : 2/15 RPC, compare deux fichiers du repo, jamais la prod ; 5 RPC de la home sans `catch` | C (aggravé : `rpc-schemas.ts` hors `paths:`) | (2/15 ✓) | 25/07 (`/seo` cassé 15 j) | I2, I8 | T‑13 |
| e‑01 | Pont SECIB : `non_converti` fourre‑tout (856/856), 41/49 dossiers sans clé, aucune couverture mesurée — pré‑prod | C | ✓ | — | I12 | T‑16 |
| e‑02 | Cron GitHub dérive de +4 à +12 h (27/08→02/09) ; refresh aval gardé par « ingestion du jour », dernier tick 20:00 UTC : 1 h 50 de marge avant un jour de `cpi_daily` perdu sans rattrapage | C | ✓ | — | I9 | T‑11 |
| a‑02 | Couverture `page_exit` : 89 % hors bot (desktop 94,6 %, mobile 86,5 %) — le déficit est mobile, pas desktop ; corrige la baseline et la mémoire projet | C | ✓ | — | I3 | T‑04 |
| a‑03 | CLS censuré : jamais émis quand nul, Chromium seul (Safari 8 mesures, Firefox 0) → p75 Chrome surestimé 33 %, « p75 site » inexistant | C | ✓ | — | I11 | T‑17 |
| a‑04 | Batching sans accusé, sans reprise, sans idempotence : lot rejeté = perdu sans trace, contacts compris | C | ✓ | 25/07 « conservé sous cette forme » (arbitrage) | I6 (plancher) | T‑17 |
| b‑01 | 8,7 % des `form_submit` (22/254 sur 180 j) sans `page_source` → invisibles par page (`pages_overview_unified` : INNER JOIN) ; « Formulaire Divorce » 3/3, « Demande dossier en cours » 1/1 ; aucune alerte (`form_attribution_degraded` ne regarde que `cooked_aid`) | C | ✓ | 25/07 « Majeur » marqué Fait (symptôme traité) | I4 | T‑18 |
| i‑01 | `SECURITY.md` (07/08) antérieur au pivot PII : « REVOKE sur toute RPC », « RLS deny‑all », « pas de PII » — trois affirmations démenties ; `COOKED_INGEST_KEY`, `NTFY_TOPIC`, SECIB absents du tableau des secrets | C | ✓ | 25/07 | I1, I13 | T‑14 |
| i‑02 | L'orchestrateur `cooked_refresh_after_gsc` (et sa garde « ingestion du jour ») n'existe dans aucun doc vivant ; 5 crons supprimés documentés avec horaires | C | ✓ (Q‑04) | 02/07, 13/07 | I13 | T‑14 |

### P2 — dette qui mordra à l'échelle

| ID | Constat | Réf. | Inv. | T |
|---|---|---|---|---|
| o‑04 / i‑04 | `rpcs.sql` non régénéré (en‑tête « 10/08 », méta 31/08) — voir h‑03 | C | I2 | T‑12 |
| o‑05 / i‑06 | Routine hebdo `conversion_weekly` (705 lignes, 17 semaines) sans migration ni doc | C | I2, I13 | T‑12, T‑14 |
| d‑07 | CPI : capture GSC 24‑25 j vs comportement 28 × 24 h ; momentum c1 (24 j) vs c0 (28 j) | C | I4 | T‑05 |
| f‑04 | Bornes Cooked du CPI sur `now()` : fenêtres décalées 18‑34 h selon l'heure du run ; effet quotidien non établi (corr 0,46 → 0,14 hors jours de bascule) | P | I10 | T‑05 |
| f‑05 (o‑11) | 4 ruptures de définition de `cpi_daily` sans colonne de version ; 02/07 et 25/07 sans annotation ; photos supprimées | C | I10 | T‑20 |
| f‑06 | `docs/cpi-modele-mathematique.md` décrit un momentum sur `gsc_path_daily` (faux depuis le 25/07) | C | I13 | T‑14 |
| f‑07 | `potentiel` de `cpi_opportunite_contact` multiplié par momentum × gate : 7/16 pages déplacées ≥ 3 rangs | C | I4 | T‑06 |
| f‑08 | Check mensuel §3 non rejoué : R² 0,910 (passe), médiane écart 27,4 % (20,1 % au 11/07) ; re‑test 56 j en retard de 28 j | C | I10 | T‑20 |
| c‑08 | Pont : pas de filtre `env`, priorité email > tél non implémentée, `converti` sans borne haute, 10,9 % d'emails dupliqués | C | I12 | T‑16 |
| e‑03 | Pont : un dossier peut être compté N fois (20,2 % des prospects ont un email dupliqué, 80 contacts) | P (ampleur chiffrée) | I12 | T‑16 |
| e‑04 | `wix_forms_import.py` aveugle au webhook : récidive garantie du doublon du 23/08 | C | I12 | T‑16 |
| e‑05 (c‑07) | `cooked_normalize_phone_fr` + miroir Python : `+33 (0)6…` → `+3306…` ; impact nul aujourd'hui (100 % emails) | C | I12 | T‑16 |
| e‑06 | `page_taxonomy` sans synchro automatisée : 2 articles publiés invisibles 2 j après le rattrapage (dont un path tronqué à 105 chars en base) ; alerte seuil 3 muette | C (aggravé) | I7 | T‑15 |
| e‑08 | CI d'ingestion : ni GBP, ni SECIB, ni import Wix testés ; `paths:` ne se déclenche pas sur ces scripts | C | I2, I12 | T‑16 |
| h‑05 (o‑09) | `cooked_refresh_after_gsc` sans durée par étape ; pic 2 166 s/2 400 (05/08) **mais tendance descendante depuis le 17/08** (titre « 90 % » faux au présent) | P | I9 | T‑11 |
| h‑06 | `freshness_contract.repair_hint` : 2 hints sur 13 nomment des jobs inexistants (pas 5) — consigne née fausse le 23/08 | P | I13 | T‑14 |
| h‑07 | `identity_stitch` : 123 MB d'index pour 24 MB de heap ; tables GSC à 10‑13 % de tuples morts | C | — | T‑19 |
| g‑04 | 31 champs Zod non‑nullables sur des colonnes prod nullables → un NULL fait tomber la page | C | I8 | T‑13 |
| g‑05 | Issue #45 fermée le 30/08 sans action (processus, pas donnée) | C (sévérité généreuse) | — | T‑14 |
| g‑06 | `signInWithOtp` sans `shouldCreateUser:false` (25/07, non corrigé) ; risque non matérialisé (1 compte) | C (P2 haut) | — | T‑13 |
| a‑05 (o‑13) | Tracker minifié 14 760 / 15 000 : plus la place d'un sprint | C | I11 | T‑17, §7.1 |
| a‑06 | Pageview envoyée avant `document.title` (98,8 % NULL) ; `url`+`title` ≈ 213 + 60 MB jamais lus (re‑mesure h, ≈ 2× moins que le 25/07) | C | — | §7.3 |
| a‑07 | Le correctif `sprint41` n'a aucun test ; fichiers Velo hors de toute CI | C | I11 | T‑17 |
| a‑08 | Garde d'origine Velo fail‑closed mais forgeable par en‑tête, sans rate‑limit ; `COOKED_DEBUG=true` | C | I6 (détection) | T‑17, §7.5 |
| b‑02 | Gate `x-cooked-key` armée (401 vérifié deux fois) mais désarmable en silence (`?? ""`), sans fail‑fast ni test | C | I1 | T‑18 |
| b‑04 | `form_submit_dropped` insérée hors `raise_cooked_alert` : pas de push, pas de dédup, 0 exécution sur 131 alertes | C | I6 | T‑18 |
| b‑05 | 13,3 % des `form_submit` (180 j) sans typologie, comptés macro par défaut | C | — | T‑18 |
| o‑10 | `events.country` vide depuis le 02/06 : suppression **délibérée** (commit `3ba987d` du 03/06, zone b), 0 consommateur — décision, pas régression | C | — | §7.2 |
| i‑03 | `CONTEXT.md` et les 2 ADR référencés par aucun index de lecture | C | I13 | T‑14 |
| i‑05 / o‑12 | Nombre de routines à 4 valeurs (104/105/121/122) ; constantes périmées dans 6 fichiers | C | I13 | T‑14 |
| i‑07 | `ROADMAP.md` : #4 « issue #19 ouverte » (fermée 30/08), #3/#9 échéances passées sans trace, #5 GBP « réparé » alors que la série s'arrête au 20/08 | C | I13 | T‑14 |
| d‑08 | Doublons : overloads `macro_contacts_by_path` / `gsc_top_queries_for_path` à fenêtres divergentes, `page_reads` ×2, vue vestige `gsc_path_metrics_28d` (0 consommateur) | C | — | T‑19, §7.4 |

### P3 — hygiène

| ID | Constat | Réf. | T |
|---|---|---|---|
| e‑07 | Filtres de `alert_rule_page_taxonomy_gap` laissent passer 10 non‑articles (URL de recadrage Wix `fp_0.50_0.50/`) | P (10, pas 11) | T‑15 |
| h‑08 | Vestige `events_vacuum_full_scheduled`, 4 contrats SQL jamais exécutés, `updated_at` non maintenu neutralisant la grâce 48 h de `tracker_drift` | C | T‑19 |
| g‑07 | `dashboard/README` : « la clé publishable ne lit aucune donnée métier » (faux : 873 lignes), `dashboard_check_stale()` et crons `refresh-dashboard-*` inexistants | C (aggravé) | T‑14 |
| g‑08 | Fiche article jusqu'à 34 s : budget SQL 45 s > patience ; cause = coût de `dashboard_article_detail`, pas la période par défaut | P (cause) | T‑13 |
| i‑08 | Constantes chiffrées périmées (lag GSC « J‑2 normal » vs J‑3/J‑4, `page_taxonomy` 56 vs 63, tests 85 vs 92…) ; ligne « contacts/28 j » non recoupée par le réfuteur | C | T‑14 |
| o‑14 | `classify_channel` ignore `gclid` : 19 entrées/28 j à `gclid` hors `paid` — **16 sont `gmb`, 3 `direct`, 0 organique** : chevauchement paid/GMB, pas fuite vers l'organique | P (impact réfuté) | T‑09 |
| b‑06, b‑07, b‑08 | Contrat C3 : `canonical_path(NULL)` SQL `'/'` vs TS `null` (CI SQL jamais jouée depuis le 09/07) ; `record_ingest_drop` = 1 aller‑retour DB par requête bot (3,6 M/28 j, ×4 en un mois, aucune règle ne le lit) ; `ANON_SALT` bloque le boot pour un repli utilisé 0/199 k | C | T‑18, T‑19 |

---

## 4. Constats écartés (avec preuve, par les auditeurs ou les réfuteurs)

- **« La définition du contact macro n'est pas unique »** — FAUX : `site_macro_counts` = Σ `macro_contacts_by_path` = 195
  sur fenêtre alignée (Phase 0 Q‑20 ; zone d). Seules les fenêtres divergent (d‑02).
- **« Le spam Baidu contamine les contacts macro et le CPI »** — FAUX : 0 contact sur 1 899 pageviews de bot ; le
  canal `referral` ne matche pas `organic%` (zone d).
- **« Les 3 copies littérales du filtre Baidu créent un écart »** — FAUX : leurs consommateurs lisent
  `cooked_events_window`, déjà filtré (zone d) ; le réfuteur c note qu'elles sont plus faibles que le helper
  (`m.baidu.com` seul) — hygiène, pas chiffre.
- **« Il reste des `occurred_at::date` dans les corps prod »** — FAUX : 0 occurrence (zone d). Règle C6 tenue.
- **« `page_reads` est redondante avec `dashboard_article_detail` »** — FAUX (grain session×path distinct) ; elle
  est orpheline, pas redondante (zone d).
- **« 12 articles manquent dans `page_taxonomy` »** — chiffre brut trompeur : 10 non‑articles + 2 articles réels
  (zones e et réfuteur e).
- **« `dfs_sync.py` sort en code 0 à 100 % d'échec »** (02/07) — CORRIGÉ (T‑12 du plan du 02/07 ; zone e).
- **« `cpi_daily_stale` sonne chaque matin avant 10:00 »** — RÉFUTÉ : 0 alerte sur 17 j (zone e).
- **« Les `gsc_ingest_missed` des 27, 28, 31/08 sont de fausses alertes »** — RÉFUTÉ : les ingestions sont bien
  arrivées après 13:15 Paris (e‑02) ; mais ces alertes ne se referment jamais.
- **« Des credentials ont pu être committés »** — RIEN TROUVÉ (`git log -S`, zone e).
- **« `alert_rule_freshness` exécute du SQL stocké en table = surface d'exécution arbitraire »** — écarté : la table
  n'est pas exposée (RLS, aucun grant) (zone e).
- **Dashboard** : libellés « contacts » / « assistés » exacts et distincts ; clé service jamais dans le bundle
  (`server-only`) ; allowlist fail‑closed ; Zod = prod pour les 15 RPC aujourd'hui ; `periods.ts` cohérent ; le
  dashboard n'a PAS besoin des grants anon sur `cpi_capture_perdue`/`page_reads` (zone g) → T‑01 ne casse rien.
- **Ops** : les steps `notify-failure` notifient bien (réponse ntfy dans le log du run 33496669273 du 01/09) ;
  aucun `oneshot-*` dans `cron.job` ; `expected_tracker_version` = `sprint41` (non périmé) ; les 6 advisors
  `search_path` hors `paris_*` sont des fonctions SQL pures inlinables — justifiés (zone h) ; `events.url`/`title`
  re‑mesurés ≈ 213 MB / 60 MB (pas 400/149 : le chiffre du 25/07 n'est plus vrai) ; `noise_sessions` a un TTL
  fonctionnel (zone h, méthode 1 et 2 concordantes).
- **« Le garde d'origine Velo est falsy sans en‑tête »** (25/07) — CORRIGÉ le 25/07 (`!origin ||`, fail‑closed) ;
  reste forgeable par en‑tête (a‑08).
- **« La CI GitHub coupe les crons après 60 j sans commit »** — risque nul aujourd'hui (commits hebdomadaires).

## 5. Non vérifiable dans cette session (et pourquoi)

- Réception effective des pushs ntfy sur le téléphone de Nicolas (hors prod ; seul `net._http_response` HTTP 200 est
  visible, 6 h de TTL).
- Appels externes à `rpc_contract_check` avant les 24 h de logs (rétention) ; `rpc_health` n'a pas de nom étranger.
- Côté Google Ads du recoupement paid (MCP sans `GOOGLE_ADS_DEVELOPER_TOKEN`) ; côté Cooked : 1 472 entrées paid /
  28 j, 80,5 % avec `gclid`.
- Reproductibilité effective du CPI (appel de `cooked_page_index` interdit : timeout MCP) ; contrefactuels calculés
  avec `cpi_compose` (IMMUTABLE) sur `cpi_daily`.
- Exhaustivité du brandé au niveau `gsc_path_daily` (pas de colonne `query`).
- Décomposition de l'écart +1 form de la semaine du 03/08 (exigerait de lire des soumissions = PII).
- Cause de la troncature à 105 caractères d'un path dans `page_taxonomy` (fait établi, cause non).
- Cause des 11 points d'écart résiduel de `cooked_bounce_rate` entre `gsc_page_performance` et le snapshot (d‑04) :
  ni la fenêtre ni la définition — à instruire dans T‑03.

---

## 6. Invariants manquants — le livrable de cette phase

Chaque invariant ferme une classe de récidive, pas un constat. **Prérequis commun à I2, I8 (durée), I13 : un accès
lecture seule à la prod depuis la CI** (secret `DATABASE_URL_RO` sur un rôle `SELECT`‑only) — ou, à défaut, une règle
d'alerte interne qui fait la même comparaison depuis la base (le canal `alerts` existe déjà).

| # | Invariant | Forme | Ferme |
|---|---|---|---|
| **I1** | **Aucune fonction SECURITY DEFINER exécutable par `anon`/`authenticated`, aucune vue sans `security_invoker` avec GRANT** : `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated` (rôles `postgres` ET `supabase_admin`), + règle `alert_rule_exposure()` (SQL sur `pg_proc`/`pg_class`, critical) + le même test en CI | migration + règle d'alerte + CI | h‑01, o‑02, o‑03, g‑07, i‑01, b‑02 |
| **I2** | **La prod est comparée à la prod, quotidiennement** : job CI planifié (pas seulement sur PR) qui recalcule `content_sha256` de `pg_get_functiondef` (= méta), l'ensemble `schema_migrations` (= fichiers), `pg_get_function_result` des 15 `dashboard_*` (= JSON de contrat régénéré), `cron.job` (= docs) | CI + rôle lecture | h‑03, o‑04, o‑05, g‑01, i‑02, i‑04, i‑06, h‑06, e‑08 |
| **I3** | **Part de sessions à referrer spam dans `events_human` < 1 %** (contract‑test + alerte) ; UA `pc` et referrers spam dans la taxonomie `ua_bot` (Edge + `refresh_noise_sessions`) ; `classify_channel` renvoie `spam` | migration + contract‑test | a‑01, a‑02, c‑06, d‑05 |
| **I4** | **Tests d'équivalence « une notion = un chiffre »** dans `run_rpc_contract_tests` (12 proposés par la zone d) : `site_macro_counts` = Σ `macro_contacts_by_path` = `conversion_journeys` sur fenêtre étiquetée ; Σ assistés + non attribuables = site ; `gsc_pages_overview.gsc_clicks_28d` = Σ 28 jours GSC ; CPI capture et comportement sur la même fenêtre ; numérateur et dénominateur d'un ratio au même grain | contract‑tests | d‑01, d‑02, d‑03, d‑06, d‑07, c‑03, c‑05, b‑01, f‑07 |
| **I5** | **Contrat d'unités** : toute colonne `*_pct` ∈ [0,100], toute colonne `*_rate` ∈ [0,1], vérifié par contract‑test sur chaque RPC publiée ; un même nom de colonne = une même unité | contract‑test | d‑01, d‑04 |
| **I6** | **Tout seuil d'alerte porte sa distribution de référence** (percentile mesuré, daté, versionné) ; `pipeline_dead` sur l'âge du dernier event ou relatif à l'heure ; `cpi_drop` sur le niveau du momentum + grade B consultatif ; escalade bornée (≤ 2 pushs par épisode) ; kinds éditoriaux jamais critical ; alerte de plancher de volume ; `form_submit_dropped` via `raise_cooked_alert` | migrations + test de rejeu sur 30 j | f‑02, f‑03, h‑02, h‑04, b‑03, b‑04, a‑04, a‑08 |
| **I7** | **La fraîcheur se mesure sur la donnée, pas sur le calcul** : `freshness_contract` lit `max(cooked_end)`, pas `max(refreshed_at)` ; `identity_stitch` a un `refreshed_at` et une ligne au registre ; `page_taxonomy` aussi ; le bandeau teste `paris_today() - cooked_end` | migration + composant | g‑03, c‑02, c‑04, e‑06 |
| **I8** | **Les 15 RPC `dashboard_*` sont sous contract‑test avec budget de durée** (`rpc_health` + alerte), et la home rend un état visible quand une RPC échoue | migration + code | g‑02, g‑04, g‑08 |
| **I9** | **Le refresh aval ne dépend pas de l'heure de la CI** : garde « ingestion plus récente que le dernier refresh complet » (marqueur existant) + plage de cron élargie ; durée par étape journalisée + alerte à 80 % du budget | migration | e‑02, h‑05 |
| **I10** | **Restatement = annotation + version** : colonne `cpi_version` dans `cpi_daily`, checklist de PR (toute migration redéfinissant `cooked_page_index`/`cpi_compose` sans annotation échoue), bornes Cooked du CPI sur des jours Paris (reproductible) | migration + CI | f‑01, f‑04, f‑05, o‑11, f‑08 |
| **I11** | **Tracker** : CI rouge sous 500 chars de marge ; une assertion jsdom par défaut corrigé (sprint39/40/41) ; CLS = 0 émis explicitement ; `COOKED_DEBUG` interdit en CI | tests + CI | a‑03, a‑05, a‑07, a‑08 |
| **I12** | **Pont SECIB** : `WHERE env = 'prod'` paramétré ; statut `non_rapprochable` + indicateur de couverture, refus de publier un taux sans lui ; unicité par dossier ; vecteurs téléphone partagés SQL/Python ; unicité fonctionnelle sur `crm_prospects` ; tests + `paths:` CI sur les 3 scripts | migration + tests + CI | e‑01, e‑03, e‑04, e‑05, c‑07, c‑08, e‑08 |
| **I13** | **Docs vérifiées mécaniquement** : `contracts/doc_constants.json` (versions, routines, crons, seuils, comptes) + `check_docs_constants.py` ; orphan‑check des `.md` ; règle « toute constante mesurée porte sa date » ; SECURITY.md aligné sur I1 | CI | i‑01…i‑08, f‑06, h‑06, g‑07, o‑12 |

---

## 7. Décisions à Nicolas (posées groupées dans `02-plan.md` §7)

Loader tracker (§7.1) ; colonne `country` (§7.2 — suppression délibérée du 03/06, 0 consommateur) ; rétention
`url`/`title` (§7.3 — ≈ 273 MB re‑mesurés) ; consolidation de l'API SQL et dépréciations (§7.4 — `page_reads` ×2,
`gsc_path_metrics_28d`, overloads) ; anti‑forge `cta_phone_click` (§7.5 — détection par alerte plutôt que verrou) ;
cadence `engagement_tick` (§7.6 — rien à trancher, aucun constat) ; restatements (§7.7 — momentum, fenêtres CPI,
bot Baidu, bounce) ; GBP / SECIB (§7.8).
