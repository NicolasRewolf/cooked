# Zone (e) — ingestions externes — PASSE DE RÉFUTATION
Mission Cooked du 02/09/2026, Phase 1. Mode LECTURE SEULE (aucune écriture, aucun apply_migration,
aucune fonction qui écrit). Repo `…/cooked-architecture-review-c22b77` (HEAD main e95f3ee),
prod Supabase `mxycmjkeotrycyneacje`. Toutes les heures sont en Europe/Paris.

**Constats reçus : 8. Constats recopiés : 8/8.** Aucun manquant, la liste est valide.

---

# PARTIE 1 — RECOPIE DES 8 CONSTATS REÇUS

## e-01
- **Titre** : Pont SECIB : « non_converti » est un fourre-tout — 84 % des dossiers n'ont aucune clé de rapprochement et rien ne le mesure
- **Sévérité** : P1 panne silencieuse ou biais mesurable
- **Preuve (du constat)** : `pg_get_viewdef('public.pont_prospects_dossiers')` (02/09/2026 10:22) — `CASE WHEN d.dossier_id IS NULL THEN 'non_converti'` derrière un `LEFT JOIN LATERAL` sur email/tél normalisés ; aucun statut ne distingue « rapproché sans dossier » de « impossible à rapprocher », et `cle_match` est NULL dans les deux cas. Agrégats `secib_dossiers` (10/19) : 49 dossiers, 8 avec email normalisé, 0 sans email mais avec tél, 41 sans aucune clé = 84 %. Côté prospects : 853/853 avec email. `scripts/secib_ingest.py:276-291` — `cmd_probe` imprime déjà le taux de clés mais aucun seuil ne bloque un ingest ni une lecture.
- **Impact (du constat)** : le chiffre d'arrivée du pivot SECIB (« quelle part des prospects web ouvre un dossier ») est un plancher inconnu, pas un taux ; au plus 8 dossiers sur 49 rapprochables, les 41 autres remontent « non_converti » qu'ils aient signé ou non. Réserve explicite du constat : ces 49 dossiers sont le bac à sable Septeo (`env='test'`), pas le cabinet Plouton. Ce qui est établi et indépendant du jeu de données : absence de statut « non_rapprochable », d'indicateur de couverture et de seuil de refus.
- **Récidive (du constat)** : non — défaut d'origine des fondations du 10/08/2026 (migration `20260810082433_secib_pont_fondations`), antérieur à aucun des trois audits.
- **Invariant proposé** : statut `non_rapprochable` dans la vue ; entrée freshness/qualité mesurant la part de `secib_dossiers` sans clé, alerte au-delà de ~20 % ; gate interdisant de publier un taux de conversion sans afficher la couverture.

## e-02
- **Titre** : Le cron GitHub des 4 ingestions dérive de 6 à 12 h ; il reste 1 h 50 de marge avant la perte définitive d'un jour de cpi_daily
- **Sévérité** : P1 panne silencieuse ou biais mesurable
- **Preuve (du constat)** : `.github/workflows/gsc-daily-ingest.yml:27` = `"0 6 * * *"`. `gh run list` (02/09 10:02) : 14/08 07:16 ; 15→26/08 entre 06:29 et 06:47 ; 27/08 17:15 UTC (+11 h 15) ; 28/08 18:07 (+12 h 07) ; 29/08 12:11 ; 30/08 11:07 ; 31/08 12:31 ; 01/09 10:59 (échec SA) puis 11:54 (dispatch). Runs de 2-3 min. Même dérive les mêmes jours sur `gbp-daily-ingest` et `dfs-weekly-sync` → cause côté ordonnanceur GitHub. Aval : `cron.job` id 46 = `"0 8-20 * * *"` (UTC) et `cooked_refresh_after_gsc` renvoie `skip: ingestion GSC du jour pas encore arrivée` si `paris_date(v_last_ingest) < v_today_paris`. Commentaire de la fonction : « un jour manqué de cpi_daily est perdu pour toujours ».
- **Impact (du constat)** : CONSTATÉ — les 27 et 28/08 la donnée GSC n'a atterri qu'à 19:17 et 20:09 Paris (dashboard et CPI sur la veille toute la journée de travail) ; trois alertes `gsc_ingest_missed` (27/08 13:15, 28/08 14:15, 31/08 13:15). LATENT — le 28/08 le run finit 1 h 50 avant le dernier tick (20:00 UTC) ; une dérive de +14 h fait franchir le bord, la séquence est sautée, et le lendemain le garde la saute encore : un jour de `cpi_daily` perdu sans rattrapage. Aucun trou à ce jour (09/08→01/09 complet, 157-177 pages/j).
- **Récidive (du constat)** : nouvelle ; l'architecture aval a été calibrée sur « GSC atterrit vers 06:15 UTC », hypothèse fausse depuis le 27/08/2026 et rien ne l'a signalé.
- **Invariant proposé** : étendre le cron 46 au-delà de 20:00 UTC (ex. `0 8-23`) OU remplacer le garde « ingestion du jour » par « ingestion plus récente que le dernier refresh complet » (`cooked_config.last_full_refresh_after_gsc_at` existe déjà) ; plus une alerte sur la marge « fin d'ingestion vs 20:00 UTC » sous 2 h.

## e-03
- **Titre** : Le pont SECIB peut compter le même dossier plusieurs fois : le LATERAL n'impose aucune unicité côté dossier
- **Sévérité** : P2 dette qui mordra à l'échelle
- **Preuve (du constat)** : `pg_get_viewdef` (02/09 10:22) — `FROM crm_prospects p LEFT JOIN LATERAL (… FROM secib_dossiers dd WHERE p.email_norm = ANY(dd.client_emails_norm) OR p.tel_norm = ANY(dd.client_tels_norm) ORDER BY abs(…) LIMIT 1) d ON true`. Une ligne par prospect ; le `LIMIT 1` garantit qu'un prospect ne voit qu'un dossier, rien ne garantit l'inverse. Deux soumissions du même contact rapprochent le même `dossier_id` et produisent deux lignes `statut='converti'`. 853 lignes dans `crm_prospects` pour ~20 formulaires/semaine ; la migration `20260823112604` a dû nettoyer des doublons de contact.
- **Impact (du constat)** : tout comptage naïf (`count(*) FILTER (WHERE statut='converti')`, taux « conversions / prospects ») sur-compte du nombre de re-soumissions ; le comptage juste est `count(DISTINCT dossier_id)`. Aucune documentation, aucun commentaire de vue, aucune RPC ne porte l'avertissement. Ampleur non chiffrable aujourd'hui (49 dossiers de bac à sable, 8 rapprochables).
- **Récidive (du constat)** : non — défaut d'origine (10/08/2026), même piège structurel que la taxonomie macro/micro : un chiffre « conversions » sans grain déclaré.
- **Invariant proposé** : exposer le grain dans le nom (vue sœur par dossier) ou ajouter un rang `row_number` sur `dossier_id` ; test de contrat `count(DISTINCT dossier_id) = count(*) FILTER (statut='converti')`.

## e-04
- **Titre** : wix_forms_import.py est aveugle aux lignes du webhook : un ré-import recrée les doublons corrigés le 23/08 par un DELETE sans invariant
- **Sévérité** : P2 dette qui mordra à l'échelle
- **Preuve (du constat)** : `scripts/wix_forms_import.py:170-186` — `existing` est chargé avec `.like("wix_submission_id","wiximport-%")`, donc une soumission déjà captée par le webhook v13 (vrai `submissionId` Wix) n'y figure jamais ; son empreinte `wiximport-`+sha1 (lignes 112-125) est nécessairement absente → INSERT (ligne 190, insert only). `supabase/migrations/20260823112604_dedup_crm_prospects_import_vs_webhook.sql:1-10` : exactement cet incident, déjà survenu (7 soumissions du 10-11/08 réinsérées) ; le correctif est un DELETE one-shot corrélé à ±2 s, pas une contrainte. Recoupement `events_human` vs `crm_prospects` par semaine (02/09 10:12) : 27/07 11/0/11/0 ; 03/08 20/0/19/+1 ; 10/08 23/9/14/0 ; 17/08 9/0/9/0 ; 24/08 23/23/0/0 ; 31/08 3/3/0/0 → aucun doublon aujourd'hui, et l'import CSV est vivant (il a rattrapé les pannes webhook des semaines du 03/08 et du 17/08).
- **Impact (du constat)** : latent, pas actif ; mais l'outil qui déclenche le défaut est celui qu'on rejoue à chaque panne webhook. Un export Wix couvrant une période déjà captée (ex. 24/08→31/08 : 26 soumissions) insérerait 26 prospects en double, gonflant `crm_prospects` et le dénominateur de tout taux de conversion du pont. L'écart +1 de la semaine du 03/08 n'a pas été décomposé (compatible avec une soumission sans identité, écartée par `build_row`) — [non recoupé].
- **Récidive (du constat)** : OUI — survenu le 23/08/2026, corrigé par DELETE, cause racine intacte 10 jours plus tard.
- **Invariant proposé** : index unique fonctionnel sur `crm_prospects` (occurred_at à la seconde, email_norm) indépendant du préfixe d'empreinte ; à défaut charger `existing` sans filtre `.like` et comparer sur l'identité normalisée.

## e-05
- **Titre** : cooked_normalize_phone_fr (et son miroir Python) casse la forme « +33 (0)6 … » : même numéro, deux clés différentes
- **Sévérité** : P2 dette qui mordra à l'échelle
- **Preuve (du constat)** : prod 02/09 10:15 — `'+33 (0)6 12 34 56 78'` → `'+330612345678'`, `'06 12 34 56 78'` → `'+33612345678'`, `'00 33 (0)6 12 34 56 78'` → `'+00330612345678'` (pas de l'E.164). Miroir Python `scripts/secib_ingest.py:83-97` : cascade identique (`if d.startswith("33") and len(d)==11` raté à 12 chiffres, puis fourre-tout `8 <= len(d) <= 15`). Le miroir est FIDÈLE : défaut partagé, pas divergence de contrat. `scripts/wix_forms_import.py:41` importe la même fonction.
- **Impact (du constat)** : aujourd'hui NUL, dit explicitement. Prod 02/09 10:17 sur `crm_prospects` : 853 prospects, 853 avec email, 0 sans email, 0 téléphone contenant `(0)`, 0 non normalisable, 27 (3,2 %) hors forme `+33XXXXXXXXX`. Le téléphone n'est jamais la clé unique côté prospects. Risque entièrement prospectif : saisie libre du formulaire Wix, forme « +33 (0)6 » courante, produira un faux « non_converti » silencieux face à un dossier SECIB sans email.
- **Récidive (du constat)** : non — normalisation d'origine (migration `20260810082433`), vecteurs « indicatif + (0) » jamais couverts.
- **Invariant proposé** : ajouter au contrat SQL/Python les vecteurs `'+33 (0)6…'` et `'00 33 (0)…'` avec la règle « après extraction des chiffres, un 0 qui suit l'indicatif 33 est un préfixe national à retirer » ; verser ces vecteurs dans le harnais existant de la zone (c).

## e-06
- **Titre** : page_taxonomy n'a toujours aucune synchro automatisée : un article publié le 31/08 est déjà invisible, 2 jours après la migration de rattrapage
- **Sévérité** : P2 dette qui mordra à l'échelle
- **Preuve (du constat)** : aucun code de synchro — `grep -rn "wixapis" scripts/ docs/ .github/` → 0 résultat (02/09 10:04) ; `blog/v3/posts` seulement dans CLAUDE.md. Aucun cron, aucune entrée dans `freshness_contract` (13 sources, `page_taxonomy` absente, vérifié 09:55). `supabase/migrations/20260831090540_page_taxonomy_sync_wix_et_alerte_gap.sql:1-20` énonce la cause racine (« les mécanismes qui créent des lignes ne regardent que les paths DÉJÀ VUS dans events_human ») et upserte 12 lignes à la main. Prod 02/09 10:28, `/post/` vus sur 30 j avec les filtres structurels de la règle d'alerte et sans ligne `page_taxonomy` : 6 vues, 1re vue 31/08/2026 — `/post/histoire-artan-engagement-grands-traumatises`. L'alerte `page_taxonomy_gap` ne sonne pas : elle exige `v_n >= 3`. Aucune alerte de ce type sur 20 jours.
- **Impact (du constat)** : l'article est invisible de l'onglet Articles Ressources, de `content_performance` et du suivi du contrat éditorial — exactement le préjudice de la migration du 31/08 (5 ressources invisibles deux mois). Le seuil « ≥ 5 vues/30 j » ajoute un angle mort permanent. Ampleur d'aujourd'hui : 1 article, non gonflée.
- **Récidive (du constat)** : OUI et rapidement — constat du 30/08, correctif manuel le 31/08, rechute observable dès le 02/09. Le correctif a traité le stock, l'alerte détecte tardivement, personne ne produit le flux.
- **Invariant proposé** : `scripts/wix_taxonomy_sync.py` (patron gsc/gbp) + cron GitHub, source de vérité = la LISTE PUBLIÉE de l'API Wix et non les paths déjà vus ; plus une entrée `page_taxonomy` dans `freshness_contract`.

## e-07
- **Titre** : Les filtres structurels de alert_rule_page_taxonomy_gap laissent passer 11 non-articles : la prochaine alerte désignera des URL de recadrage d'image
- **Sévérité** : P3 hygiène
- **Preuve (du constat)** : `pg_get_functiondef('alert_rule_page_taxonomy_gap')` (02/09 09:53) — exclusions `%/preview/%`, `https?://`, `[ÃÂ]`, `%`, `length(path) <= 140`. Prod 02/09 10:28 : les 12 `/post/` sans ligne `page_taxonomy` qui passent ces filtres, dont 11 ne sont pas des articles — 8 × `/post/fp_0.50_0.50/d05c9e_<hex32>` (point focal d'image Wix, 1 vue chacune), 1 × `/post/Y29udHIlQz` (fragment base64), 1 × slug réel + parenthèse parasite, 1 × slug tronqué. Aucun ne dépasse 2 vues/30 j, donc aucun n'atteint le seuil ≥ 5.
- **Impact (du constat)** : (1) faux positif à venir — il suffit qu'un de ces paths franchisse 5 vues/30 j pour compter dans le `v_n >= 3` et qu'une alerte réclame une synchro Wix en désignant des URL de recadrage d'image, l'alerte perdant sa crédibilité au moment où elle devrait être crue ; (2) bruit de dénominateur — toute énumération `/post/%` qui reprend ces filtres (et la règle est le modèle de référence) hérite de la fuite. Le motif `fp_0.50_0.50/` est reconnaissable et absent des filtres.
- **Récidive (du constat)** : non — filtres écrits le 31/08/2026 (T-19) contre une autre famille de bruit ; la famille « point focal » n'avait pas été vue.
- **Invariant proposé** : exclure `path !~ '/fp_[0-9.]+_[0-9.]+/'` et ajouter une règle positive « slug d'article » (pas de segment après `/post/<slug>`) ; couvrir ces vecteurs dans `scripts/c2_alerts_contract.sql`.

## e-08
- **Titre** : La CI d'ingestion ne teste ni GBP, ni SECIB, ni l'import Wix — et son filtre `paths:` ne se déclenche même pas quand on les modifie
- **Sévérité** : P2 dette qui mordra à l'échelle
- **Preuve (du constat)** : `ls tests/` (02/09 09:52) — `test_canonical_path_contract.py`, `test_cooked_store.py`, `test_dfs_common.py`, `test_gsc_common.py`, `tracker.test.js` : 5 fichiers, aucun pour `gbp_ingest.py` (455 lignes), `secib_ingest.py` (323), `wix_forms_import.py` (196). `.github/workflows/python-ingest-contract.yml:5-23` — le déclencheur ne liste que `gsc_common.py`, `dfs_common.py`, `cooked_store.py`, `cooked_path.py` et leurs tests ; un commit qui ne touche que les trois scripts ci-dessus ne déclenche aucun job : ni test, ni lint, ni import-check. 974 lignes de Python qui écrivent en prod, dont les deux scripts qui manipulent la PII en clair, sans barrière CI.
- **Impact (du constat)** : aucune régression connue, mais c'est le trou par lequel passent e-04 et e-05 — ni l'un ni l'autre n'a de test possible faute de cible. Les fonctions les plus testables sont pures et sans credentials : `normalize_phone_fr` / `normalize_email` (`secib_ingest:76-97`), `build_row` et les `clean_*` (`wix_forms_import:49-138`), `_trim_unconsolidated` et `_to_store_rows` (`gbp_ingest:300-327`).
- **Récidive (du constat)** : non, mais extension non faite — le workflow porte le commentaire « C7 — pures GSC/DFS + cooked_store (sans credentials prod) » et a été étendu à `cooked_path.py` ; les trois scripts ajoutés depuis (gbp 28/07, secib et wix_forms 10/08) n'ont jamais été raccrochés.
- **Invariant proposé** : étendre `paths:` à `scripts/*.py` (ou supprimer le filtre) et ajouter `tests/test_secib_ingest.py`, `tests/test_wix_forms_import.py`, `tests/test_gbp_ingest.py` sur les fonctions pures.

---

# PARTIE 2 — VERDICTS (preuve ré-exécutée par moi)

```
ID        e-01
Verdict   CONFIRMÉ (structure) — écart sur la lecture de la sévérité « aujourd'hui »
```
**Ma preuve.**
1. `pg_get_viewdef('public.pont_prospects_dossiers'::regclass, true)` — exécutée 02/09/2026 15:03 Paris.
   Sortie (extraits littéraux) : `CASE WHEN d.dossier_id IS NULL THEN 'non_converti'::text WHEN d.date_creation >= (p.occurred_at - '7 days'::interval) THEN 'converti'::text ELSE 'client_existant'::text END AS statut` ;
   `CASE WHEN p.email_norm IS NOT NULL AND (p.email_norm = ANY (d.client_emails_norm)) THEN 'email' WHEN p.tel_norm IS NOT NULL AND (p.tel_norm = ANY (d.client_tels_norm)) THEN 'telephone' ELSE NULL END AS cle_match`.
   → Trois statuts seulement, aucun `non_rapprochable`. `cle_match` est NULL aussi bien pour « pas de dossier » que pour « dossier sans clé ». Le constat décrit exactement la vue en prod.
2. Agrégats `secib_dossiers` (aucune valeur individuelle), 02/09/2026 15:03 Paris :
   `n_dossiers 49 | avec_email 8 | avec_tel 5 | aucune_cle 41 | n_env 1 | env = 'test'`.
   → 41/49 = **83,7 %** sans aucune clé (le « 84 % » du constat est juste). Nuance de ma mesure : 5 dossiers portent un téléphone, tous inclus dans les 8 qui portent déjà un email (49 − 41 = 8 rapprochables). Le « 0 sans email mais tél » du constat est donc exact, mais il masque que le téléphone n'ajoute aucune couverture — ce qui renforce le constat plutôt qu'il ne l'affaiblit.
3. Lecture de la vue elle-même, 02/09/2026 15:04 Paris :
   `n_lignes_vue 856 | lignes_avec_dossier 0 | cle_match_null 856 | n_statuts 1 | statuts 'non_converti'`.
   → **Aujourd'hui la vue rapproche zéro dossier sur 856 prospects.** Le plafond réel n'est pas « au plus 8 » : c'est 0. Le fourre-tout est total.
4. `scripts/secib_ingest.py:276-291` relu : `cmd_probe` imprime `Clés de matching : email …/…, téléphone …/…, au moins une …/…` et se termine par `(probe = lecture seule, aucune écriture Supabase)`. Aucun `raise`, aucun seuil, aucune écriture d'un indicateur de couverture. `cmd_ingest` (ligne 294+) ne consomme pas ce calcul.
5. Recherche des consommateurs, repo : `grep -rln "pont_prospects_dossiers"` → `CHANGELOG.md`, `CLAUDE.md`, `docs/HISTORY-sprints.md`, `supabase/views.sql`, `supabase/migrations/20260810082433…`, `scripts/secib_ingest.py`. **Aucune RPC, aucun code dashboard.**

**Écart.** Le défaut structurel est confirmé sans réserve, et il est même plus marqué que dit (0 rapprochement, pas 8). Deux écarts sur la sévérité :
- P1 est présenté comme « biais mesurable ». Aujourd'hui il n'y a rien à biaiser : `env='test'` uniquement, 0 ligne convertie, **aucun consommateur automatisé** (ni RPC, ni dashboard). Le seul canal de fuite est une requête ad-hoc écrite par un humain ou un agent. C'est un **P1 à l'activation prod**, pas un P1 actif — distinction utile pour l'ordonnancement des correctifs.
- Le constat écrit « 853/853 ont un email » côté prospects ; ma mesure au 02/09 15:03 donne 855 (puis 856 une minute plus tard). Simple dérive d'horloge, le webhook ingère en continu — aucune conséquence.

**Invariant.** *Tient, à une réserve près.* Le statut `non_rapprochable` et l'indicateur de couverture empêchent bien la récidive du chiffre trompeur. La brique existe déjà : `freshness_contract` contient **13 sources dont `secib_dossiers`, mais désactivée** (`enabled = false`, vérifié 02/09 15:07) — l'invariant se réduit donc à réactiver cette entrée en lui ajoutant un critère de couverture, pas à construire un registre. En revanche le « gate de mise en prod » (refuser de publier un taux sans afficher la couverture) est **décoratif tant qu'aucun consommateur n'existe** : il n'y a rien à gater. Il devient indispensable le jour où une RPC ou le dashboard lit la vue — c'est à ce moment-là qu'il faut le poser, et le poser AVANT le premier consommateur.

```
ID        e-02
Verdict   CONFIRMÉ
```
**Ma preuve.**
1. `.github/workflows/gsc-daily-ingest.yml:24-28` relu : `on: schedule: - cron: "0 6 * * *"`, précédé du commentaire `# 06:00 UTC quotidien (= 07:00 ou 08:00 Paris selon DST). # GSC publie typiquement les données J-3 vers 03:00 UTC.` → l'hypothèse de calibration est bien écrite dans le repo.
2. `gh run list --workflow gsc-daily-ingest.yml --limit 18` (createdAt → updatedAt), exécutée 02/09/2026 15:04 Paris. Sortie brute (UTC) :
   `17/08 06:43 · 18/08 06:34 · 19/08 06:35 · 20/08 06:37 · 21/08 06:37 · 22/08 06:31 · 23/08 06:32 · 24/08 06:47 · 25/08 06:37 · 26/08 06:39` puis
   `27/08 17:15:05 → 17:17:14 · 28/08 18:07:40 → 18:09:42 · 29/08 12:11 · 30/08 11:07 · 31/08 12:31 · 01/09 10:59 (schedule, failure) · 01/09 11:54 (workflow_dispatch, success) · 02/09 10:29:36 → 10:30:58 (schedule, success)`.
   → Dérive confirmée au chiffre près, y compris les durées de 2-3 min. **Élément neuf : la dérive n'est pas résorbée** — le run du 02/09 est parti à 10:29 UTC, soit +4 h 29.
3. `cron.job` complet, 02/09/2026 15:04-15:08 Paris — un seul job aval : `jobid 46 | "0 8-20 * * *" | active | SET statement_timeout='2400s'; SELECT public.cooked_refresh_after_gsc();`. Aucun job `30 7 * * *` : la mention de CLAUDE.md est de la documentation périmée, le mécanisme réel est le retry horaire.
4. `pg_get_functiondef('public.cooked_refresh_after_gsc()')` relue en entier. Points de contrôle : `SELECT max(ingested_at) INTO v_last_ingest FROM public.gsc_path_daily;` puis `IF v_last_ingest IS NULL OR public.paris_date(v_last_ingest) < v_today_paris THEN RETURN 'skip: ingestion GSC du jour pas encore arrivée';` ; `v_steps` = `cooked_cpi_snapshot` en tête puis les 3 refresh dashboard ; commentaire `-- CPI en PREMIER : un jour manqué de cpi_daily est perdu pour toujours (cooked_page_index lit now())`. Le garde et l'ordonnancement sont exactement ceux décrits.
5. Complétude de `cpi_daily` sur 25 jours (08/08 → 02/09), 02/09/2026 15:05 Paris : `jours_attendus 25 | jours_presents 25 | jours_manquants NULL | min_pages 157 | max_pages 177`. **Aucun trou**, et le 02/09 est déjà produit (le run de 10:29 UTC a été rattrapé par le tick de 11:00 UTC).
6. `alerts` sur 21 jours, 02/09/2026 15:07 Paris : `gsc_ingest_missed` warn le **27/08 13:15**, **28/08 14:15**, **31/08 13:15** (Paris) — les trois alertes annoncées, aux minutes près, toutes `acked = false`.

**Écart : aucun sur le fond.** Trois précisions.
- La marge annoncée est exacte : run terminé le 28/08 à 18:09:42 UTC, dernier tick à 20:00 UTC → **1 h 50 min 18 s**. Le raisonnement « +14 h de dérive fait franchir le bord » est arithmétiquement correct.
- J'ajoute la démonstration que le constat laisse implicite : si l'ingestion atterrit après 20:00 UTC mais avant minuit Paris, `paris_date(v_last_ingest)` vaut le jour même ; le lendemain à 08:00 UTC ce même `v_last_ingest` est strictement antérieur à `v_today_paris` → `skip`. La séquence ne rejoue jamais pour la journée sautée, et `cooked_cpi_snapshot` n'écrit que la ligne du jour courant. La perte est bien définitive. (Cas symétrique bénin : une ingestion entre 22:00 et 00:00 UTC porte une date Paris de J+1 et passe le garde le lendemain.)
- Les 29 et 30/08 n'ont pas déclenché d'alerte alors que la dérive était de +5/6 h : le seuil de la règle tombe vers 13:15 Paris et les ingestions ont atterri à 14:11 et 13:07 Paris. La détection est donc partielle — elle ne voit que les retards extrêmes, pas la dérive. Ce point renforce le constat.

**Invariant.** *Tient — et l'une des deux branches est nettement supérieure.* Étendre le cron à `0 8-23` ne fait que déplacer le bord (une dérive de +18 h le franchirait). Remplacer le garde par « ingestion plus récente que le dernier refresh complet » supprime le bord : j'ai vérifié que `cooked_config.last_full_refresh_after_gsc_at` est déjà lu par la fonction (`v_last_complete`) et déjà écrit en fin de séquence réussie — la comparaison `v_last_ingest > v_last_complete` suffit et rend la séquence rattrapable le lendemain matin. C'est la branche à retenir ; elle ne coûte qu'une condition. L'alerte de marge est un bon complément mais reste secondaire une fois le bord supprimé.

```
ID        e-03
Verdict   PARTIEL — le défaut structurel tient ; « ampleur non chiffrable » est faux, je la chiffre
```
**Ma preuve.**
1. Même `pg_get_viewdef` qu'en e-01 (02/09/2026 15:03 Paris). Le `LEFT JOIN LATERAL … LIMIT 1 … ON true` est bien là, sans `DISTINCT ON` côté dossier, sans colonne de rang. La vue est bien à grain prospect.
2. **Chiffrage de l'exposition**, 02/09/2026 15:04 Paris, sur `crm_prospects` (agrégats seuls) :
   `emails_distincts 763 | emails_multi_soumissions 80 | lignes_concernees 173 | max_soumissions_par_email 3`.
   → 80 contacts ont soumis plusieurs fois ; **173 lignes sur 856 (20,2 %) portent un `email_norm` partagé avec au moins une autre ligne**. Si l'un de ces contacts ouvre un dossier, la vue produit 2 (voire 3) lignes `converti` pour un seul dossier. Le facteur de sur-comptage attendu sur la population dupliquée est ≈ 2,16 (173/80).
3. État actuel du sur-comptage, même horodatage : `lignes_converti 0 | dossiers_distincts_converti 0`. Le piège est armé mais n'a encore rien produit.
4. Consommateurs : identique à e-01 — aucune RPC, aucun composant dashboard ne lit la vue.

**Écart.** Deux, dont un substantiel.
- Le constat écrit « ampleur non chiffrable aujourd'hui » en la liant au bac à sable SECIB. C'est un raisonnement du mauvais côté de la jointure : l'ampleur du sur-comptage ne dépend pas du nombre de dossiers, mais du **taux de re-soumission côté prospects**, qui est mesurable dès maintenant et vaut **20,2 % des lignes**. Le constat sous-vend son propre point.
- Le constat invoque la migration `20260823112604` comme preuve que « les re-soumissions existent ». C'est un mauvais témoin : cette migration nettoie des doublons **import CSV vs webhook** (même soumission comptée deux fois), pas des re-soumissions d'un même contact. Ce sont deux phénomènes distincts — le vrai témoin est le chiffre du point 2 ci-dessus, que le constat n'a pas produit.

**Invariant.** *Tient, avec une correction sur le test de contrat.* La vue sœur par dossier ou la colonne de rang règlent le problème. En revanche le test proposé — `count(DISTINCT dossier_id) <= count(*) FILTER (statut='converti')` avec égalité attendue — est **inerte aujourd'hui** : les deux membres valent 0 et le test passera en vert indéfiniment sur le bac à sable, donnant une fausse assurance jusqu'au jour du basculement en prod. Il faut le doubler d'un test qui ne dépend pas de SECIB : `count(*) = count(DISTINCT email_norm)` sur les lignes rapprochées, ou plus simplement un test qui échoue si une valeur de `dossier_id` non nulle apparaît sur plus d'une ligne. Formulé ainsi, il mordrait dès la première donnée réelle.

```
ID        e-04
Verdict   CONFIRMÉ
```
**Ma preuve.**
1. `scripts/wix_forms_import.py` relu, lignes 100-196. Chaîne complète du défaut :
   - ligne ~110-118 : `if not (nom or prenom or email or telephone): return None` puis `fingerprint = hashlib.sha1("|".join([date, (email or "").lower(), telephone or "", nom or "", prenom or ""]).encode()).hexdigest()[:20]` ;
   - ligne ~123 : `"wix_submission_id": "wiximport-" + fingerprint` ;
   - lignes ~166-180 : `.select("wix_submission_id").like("wix_submission_id", "wiximport-%")` en boucle de pagination, alimentant `existing` ;
   - ligne ~182 : `todo = [r for r in rows if r["wix_submission_id"] not in existing]` ;
   - ligne ~186 : `client.table("crm_prospects").insert(chunk).execute()` — **`insert`, pas `upsert`**.
   → Une ligne posée par le webhook porte le vrai `submissionId` Wix, n'entre jamais dans `existing`, et son empreinte `wiximport-…` n'existe par construction nulle part. L'INSERT est inévitable. Le constat décrit le code exactement.
2. `supabase/migrations/20260823112604_dedup_crm_prospects_import_vs_webhook.sql:1-10` relue : en-tête « l'import CSV du 23/08/2026 (rattrapage de la panne webhook) a réinséré sous empreinte 'wiximport-…' 7 soumissions du 10-11/08 déjà capturées par le webhook v13 », puis un `DELETE … USING … WHERE b.wix_submission_id LIKE 'wiximport-%' AND a.wix_submission_id NOT LIKE 'wiximport-%' AND abs(extract(epoch FROM (a.occurred_at - b.occurred_at))) < 2;`. One-shot, aucune contrainte créée.
3. Index réellement présents sur `crm_prospects`, 02/09/2026 15:07 Paris : `crm_prospects_pkey (id)`, `crm_prospects_wix_submission_uq` — UNIQUE sur `wix_submission_id` — , `crm_prospects_email_norm_idx`, `crm_prospects_tel_norm_idx` (ces deux derniers **non uniques**). → La seule unicité en base porte sur la colonne qui, précisément, diffère entre les deux voies d'entrée. Aucun garde-fou d'identité. Point décisif que le constat affirme sans le prouver : je le prouve.
4. Recoupement `events_human` (`name='form_submit'`) vs `crm_prospects`, par semaine Paris, 42 jours, 02/09/2026 15:07 Paris — colonnes `form_submit / webhook / import_csv / écart` :
   `20/07 : 2 / 0 / 2 / 0` — `27/07 : 13 / 0 / 13 / 0` — `03/08 : 20 / 0 / 19 / +1` — `10/08 : 23 / 9 / 14 / 0` — `17/08 : 9 / 0 / 9 / 0` — `24/08 : 23 / 23 / 0 / 0` — `31/08 : 6 / 6 / 0 / 0`.
   → Reproduction fidèle. Aucun doublon en base aujourd'hui ; la bascule webhook du 24/08 est nette ; l'import CSV a bien couvert seul les semaines du 03/08 et du 17/08.

**Écart.** Aucun sur le fond. Deux différences de chiffres, toutes deux explicables et sans conséquence :
- semaine du 27/07 : je lis 13/0/13, le constat 11/0/11 — bord de fenêtre (mon `now() - 42 jours` remonte plus haut dans la semaine que le sien) ;
- semaine du 31/08 : je lis 6/6, le constat 3/3 — trois soumissions arrivées entre son horodatage (10:12) et le mien (15:07). Le webhook est vivant, ce qui est une bonne nouvelle en soi.
- L'écart +1 de la semaine du 03/08 : je n'ai pas cherché à le décomposer non plus (il faudrait ouvrir le contenu des soumissions, donc de la PII). Je le laisse **[non recoupé]**, comme le constat — honnêteté maintenue.

**Invariant.** *Tient, et c'est le seul des huit qui ferme vraiment la porte.* L'index unique fonctionnel sur `(occurred_at à la seconde, email_norm)` est exécutable par la base, indépendant de la voie d'entrée, et il aurait rejeté les 7 lignes du 23/08. Deux réserves opérationnelles à porter au plan : (a) l'INSERT du script devrait alors devenir un `upsert … on_conflict` sous peine de faire planter l'import entier au premier doublon ; (b) **le DELETE correctif de la migration du 23/08 est lui-même dangereux** — il ne corrèle sur aucune identité, seulement sur un écart de ±2 s entre une ligne import et une ligne webhook quelconques. Rejoué un jour de forte affluence, il supprimerait des prospects **différents** soumis dans la même fenêtre de 2 s. Le constat ne le relève pas ; c'est une raison de plus de remplacer ce patron par une contrainte.

```
ID        e-05
Verdict   CONFIRMÉ
```
**Ma preuve.**
1. Prod, 02/09/2026 15:03 Paris — six vecteurs passés à `public.cooked_normalize_phone_fr` en une requête :
   `'+33 (0)6 12 34 56 78'` → **`+330612345678`** (12 chiffres) ;
   `'06 12 34 56 78'` → `+33612345678` ;
   `'+33 6 12 34 56 78'` → `+33612345678` ;
   `'00 33 (0)6 12 34 56 78'` → **`+00330612345678`** ;
   `'0033 6 12 34 56 78'` → `+33612345678` ;
   `'+33.(0)6.12.34.56.78'` → **`+330612345678`**.
   → Le même abonné produit deux clés différentes selon la saisie, et la forme `00 33 (0)…` sort un `+00…` qui n'est pas de l'E.164. Je confirme les trois sorties du constat et j'ajoute deux vecteurs (séparateurs points, `0033` propre) qui montrent que le défaut est bien porté par le `(0)`, pas par les séparateurs.
2. `scripts/secib_ingest.py:76-97` relu. En-tête ligne 70-72 : `# Normalisation — MIROIR STRICT des fonctions SQL cooked_normalize_email / cooked_normalize_phone_fr (migration 20260810082433…). # Toute évolution doit se faire des deux côtés.` Cascade : `if d.startswith("0033") and len(d)==13 → "+33"+d[4:]` ; `if d.startswith("33") and len(d)==11 → "+"+d` ; `if d.startswith("0") and len(d)==10 → "+33"+d[1:]` ; `if 8 <= len(d) <= 15 → "+"+d`. Avec `(0)`, les chiffres extraits sont `33` + 10 chiffres = 12 → aucune branche spécifique ne mord, le fourre-tout final produit `+330612345678`. **Le miroir est fidèle au défaut** : c'est bien un défaut partagé, pas une divergence de contrat. Le constat a raison de le dire, et c'est un point de rigueur à son crédit.
3. Impact mesuré, prod 02/09/2026 15:03 Paris, `crm_prospects`, agrégats seuls :
   `n_prospects 855 | avec_email_norm 855 | avec_tel_norm 854 | saisie_avec_0_parenthese 0 | tel_non_normalisable 0 | tel_hors_forme_fr 27 | sans_aucune_cle 0`.
   → 0 saisie `(0)` dans le stock, 27/855 = **3,2 %** hors forme `+33XXXXXXXXX`, et **100 % des prospects ont un email** : le téléphone n'est jamais la clé de secours nécessaire. L'impact d'aujourd'hui est bien nul, comme le dit le constat.

**Écart : aucun.** Le constat est exact sur le défaut, exact sur le miroir, exact sur l'impact nul, et il le dit lui-même sans le gonfler. J'ajoute une seule précision qui déplace légèrement la cible : la forme `00 33 (0)…` produit `+00330612345678`, qui n'est pas seulement « une autre clé » mais une valeur **hors format E.164** stockée telle quelle dans une colonne présentée comme normalisée — c'est un défaut de type, pas seulement de collision, et il mérite un test dédié à part du vecteur `(0)`.

**Invariant.** *Tient, à condition d'être versé au bon endroit.* Ajouter les vecteurs au harnais de contrat empêche la régression **une fois la règle corrigée**, mais l'invariant tel qu'écrit ne corrige rien par lui-même : il faut d'abord réécrire la cascade (retirer un `0` national suivant l'indicatif `33`, et refuser au lieu de préfixer `+` quand la chaîne ne ressemble à aucun format connu). Deuxième condition, dirimante : le harnais doit tourner **des deux côtés du miroir**. Or le miroir Python vit dans `scripts/secib_ingest.py`, qui — voir e-08 que je confirme — n'est déclenché par aucun workflow CI. Tant que e-08 n'est pas corrigé, la moitié Python de cet invariant est **décorative**. Les deux constats doivent être traités ensemble, dans cet ordre : e-08 puis e-05.

```
ID        e-06
Verdict   CONFIRMÉ — et l'ampleur annoncée est sous-estimée : 2 articles réels, pas 1
```
**Ma preuve.**
1. Repo, 02/09/2026 15:06 Paris : `grep -rn "wixapis" scripts/ .github/ docs/` → **0 résultat**. `grep -rln "blog/v3/posts"` sur `*.py *.yml *.md *.ts` (hors node_modules) → **`CLAUDE.md` seulement**. Aucun script, aucun workflow, aucun artefact exécutable. Confirmé.
2. `freshness_contract`, prod 02/09/2026 15:07 Paris : `n_sources 13 | n_actives 12` — `cpi_daily, crm_prospects, cta_phone_click, dashboard_resources_snapshot, dfs_keyword_volume, form_submit, gbp_daily, gsc_path_daily, gsc_query_daily, gsc_query_page_daily, math_visit_sequences_snapshot, secib_dossiers(désactivée), seo_url_snapshot`. **`page_taxonomy` absente.** Le compte de 13 du constat est exact ; j'ajoute que l'une des 13 est désactivée.
3. `supabase/migrations/20260831090540_page_taxonomy_sync_wix_et_alerte_gap.sql:1-22` relue. Elle énonce : « Au 30/08/2026 l'API déclare 433 posts publiés (62 ressource + 371 classique) ; page_taxonomy n'en connaissait que 426, dont 58 ressource seulement » et « CAUSE. Les mécanismes qui créent des lignes ne regardent que les paths DÉJÀ VUS dans events_human ». Elle nomme les 5 ressources manquantes et leurs dates. Le constat cite fidèlement.
4. `pg_get_functiondef('alert_rule_page_taxonomy_gap')`, 02/09/2026 15:05 Paris : `HAVING count(*) FILTER (WHERE e.name='pageview') >= 5` puis `IF v_n >= 3 THEN … CASE WHEN v_n >= 10 THEN 'critical' ELSE 'warn' END`. Les deux seuils annoncés sont exacts.
5. Ma ré-exécution de la requête d'écart (filtres identiques à ceux de la règle, **sans** le seuil de 5 vues), `events_human` 30 jours, 02/09/2026 15:05 Paris → **12 paths**, tous sans aucune ligne dans `page_taxonomy`. En tête : `/post/histoire-artan-engagement-grands-traumatises`, **6 vues, 1re vue le 31/08/2026**. Article réel, publié après la passe manuelle du 31/08, déjà sans catégorie — et sous le seuil `v_n >= 3`, donc muet. Confirmé.
6. `alerts` sur 21 jours (02/09/2026 15:07 Paris) : **aucune ligne `page_taxonomy_gap`**. Confirmé.
7. **Élément neuf.** J'ai vérifié la nature de deux des 12 paths que le constat classe en bruit, en comparant les chaînes complètes (02/09/2026 15:06 Paris) :
   - dans `events_human` : `/post/accident-de-la-circulation-indemnisation-à-hauteur-de-2-millions-d-euros-pour-une-victime-tétraplégique` — **longueur 109** ;
   - dans `page_taxonomy` : `/post/accident-de-la-circulation-indemnisation-à-hauteur-de-2-millions-d-euros-pour-une-victime-tétraplég` — **longueur 105**, `category = 'classique'`, `theme = 'indemnisation victimes'`, `source = 'slug_heuristic'`.
   → La ligne de taxonomie porte un path **tronqué à 105 caractères** ; le path réellement visité, complet, n'a **aucune ligne**. Ce n'est donc pas du bruit : c'est un **deuxième article réel invisible**, et sa ligne de taxonomie existante est adossée à une URL qui n'existe pas.
   (Contre-exemple pour la rigueur : `/post/contrôle-coercitif-reconnaître-agir)` avec parenthèse finale est bien du bruit — la version propre existe en base en double, `…reconnaître-agir` en `ressource/wix_api` et `…reconnaitre-agir` sans accent en `classique/slug_heuristic`.)

**Écart.** Le constat est exact sur tout ce qu'il avance, mais **sous-estime son ampleur d'un facteur 2** : il annonce « 1 article », j'en compte **2** (histoire-artan + accident-de-la-circulation…tétraplégique). Le second est plus grave que le premier, parce qu'il ne se présente pas comme un trou : une ligne existe, elle a l'air correcte, elle est simplement accrochée à un path tronqué. Un rattrapage qui se contente de lister les paths « sans ligne » le verra ; un rattrapage qui compte les articles « ayant une catégorie » le manquera. Cette famille de défaut — path tronqué en base de référence — n'est nommée nulle part et je ne sais pas d'où vient la troncature ; je la signale comme **[non recoupé quant à sa cause]**, le fait lui-même étant établi par les deux longueurs ci-dessus.

**Invariant.** *Tient, et c'est le seul correctif de fond des huit.* Le renversement de la source de vérité (liste publiée de l'API Wix → base, au lieu de trafic → base) supprime la cause racine que la migration du 31/08 décrit sans l'implémenter, et il rend caducs les deux angles morts : le seuil de 5 vues et le seuil de 3 articles. L'entrée `page_taxonomy` dans `freshness_contract` est le bon complément et coûte une ligne, le registre existant étant opérationnel. Une condition à ajouter au cahier des charges du script : il doit **réconcilier les paths existants** (détecter qu'une ligne pointe vers un path absent de la liste publiée), sinon la ligne tronquée du point 7 survivra à la synchro et le second article restera invisible.

```
ID        e-07
Verdict   PARTIEL — la fuite de filtre est réelle, mais le décompte est faux : 10 non-articles, pas 11
```
**Ma preuve.**
1. `pg_get_functiondef('alert_rule_page_taxonomy_gap')`, 02/09/2026 15:05 Paris — bloc d'exclusions relu littéralement :
   `AND e.path NOT LIKE '%/preview/%'` · `AND e.path !~ 'https?://'` · `AND e.path !~ '[ÃÂ]'` · `AND e.path !~ '%'` · `AND length(e.path) <= 140`, commentés `-- mêmes exclusions structurelles que refresh_page_taxonomy_heuristic (T-19)`. Les cinq exclusions annoncées sont exactes, et **aucune ne vise un motif de média**.
2. Ma ré-exécution (mêmes filtres, seuil de vues retiré), 02/09/2026 15:05 Paris — 12 paths, avec vues sur 30 j et première vue :
   `/post/histoire-artan-engagement-grands-traumatises` — 6 vues, 31/08 ;
   `/post/contrôle-coercitif-reconnaître-agir)` — 2 vues, 08/08 ;
   `/post/accident-de-la-circulation-…-victime-tétraplégique` — 2 vues, 14/08 ;
   `/post/Y29udHIlQz` — 2 vues, 19/08 ;
   **8 × `/post/fp_0.50_0.50/d05c9e_<hex32>~mv2.png`** — 1 vue chacun, entre le 12 et le 14/08.
   → Les 8 URL de point focal d'image Wix sont confirmées, ainsi que le fragment base64. Le motif `fp_0.50_0.50/` est bien reconnaissable et absent des filtres.
3. Qualification des deux paths litigieux — voir e-07 point 7 de ma preuve e-06, mêmes requêtes, 02/09/2026 15:06 Paris. Résultat : `…reconnaître-agir)` est bien du bruit (la version propre est catégorisée) ; `…victime-tétraplégique` (109 car.) est **un article réel** dont seule une variante tronquée (105 car.) figure en taxonomie.

**Écart.** Trois, dont un qui change le décompte du titre.
- **« 11 non-articles » est faux : ils sont 10.** Le path que le constat qualifie de « slug tronqué » est en réalité le path **complet** ; c'est la ligne de `page_taxonomy` qui est tronquée. Le constat a inversé le sens de la troncature — vraisemblablement parce qu'il a lu une sortie elle-même tronquée à l'affichage (je suis tombé dans le même piège à ma première requête, avec un `left(path,70)` : c'est en re-tirant les chaînes complètes avec leur longueur que le sens s'inverse). Ce path relève de e-06, pas de e-07.
- Par conséquent le titre surestime légèrement le bruit et sous-estime le vrai gap. Le fond du constat — les filtres laissent passer une famille de bruit non prévue, dominée par les URL de recadrage — reste entièrement vrai, et 8 des 12 paths sont bien des images.
- Sévérité P3 : je la confirme, et j'ajoute l'argument qui la borne. Les 8 URL de point focal ont **1 vue chacune sur 30 jours** ; il en faudrait 5 pour compter. Le scénario de faux positif exige que trois de ces paths franchissent 5 vues simultanément, ce que leur nature (ressource image appelée une fois) rend improbable. Le risque réel est moins l'alerte trompeuse que le **bruit de dénominateur** dans toute énumération qui recopie ces filtres — c'est-à-dire le second effet cité par le constat, qui est le plus solide des deux.

**Invariant.** *Tient pour la partie exclusion, incomplet pour le reste.* L'exclusion `path !~ '/fp_[0-9.]+_[0-9.]+/'` traite exactement la famille observée. La règle positive « pas de segment supplémentaire après `/post/<slug>` » est meilleure encore : elle aurait attrapé les 8 URL d'image **et** toute famille future de sous-ressource, sans énumérer les motifs — c'est la version à retenir, l'exclusion par motif étant une rustine par nature toujours en retard d'une famille. En revanche l'invariant **ne traite ni le fragment base64 ni la variante à parenthèse**, qui passent les deux règles ; et il ne dit rien du path tronqué en base révélé ci-dessus. Verser ces vecteurs dans `scripts/c2_alerts_contract.sql` est utile mais reste un test de non-régression : il fige le comportement, il ne produit pas la liste juste.

```
ID        e-08
Verdict   CONFIRMÉ
```
**Ma preuve.**
1. `ls tests/`, 02/09/2026 15:03 Paris : `test_canonical_path_contract.py`, `test_cooked_store.py`, `test_dfs_common.py`, `test_gsc_common.py`, `tracker.test.js`. **5 fichiers**, aucun ne vise gbp/secib/wix_forms. Confirmé.
2. `wc -l` sur les trois scripts, même horodatage : `secib_ingest.py 323` · `wix_forms_import.py 196` · `gbp_ingest.py 455` — **total 974**. Les trois volumes et le total du constat sont exacts au chiffre près.
3. `.github/workflows/python-ingest-contract.yml:1-23` relu. En-tête : `# C7 — pures GSC/DFS + cooked_store (sans credentials prod).` Déclencheur `pull_request.paths` : `scripts/gsc_common.py`, `scripts/dfs_common.py`, `scripts/cooked_store.py`, `scripts/cooked_path.py`, `tests/test_gsc_common.py`, `tests/test_dfs_common.py`, `tests/test_cooked_store.py`, le workflow lui-même. `push.paths` (branche main) : `scripts/gsc_common.py`, `scripts/dfs_common.py`, `scripts/cooked_store.py`, `tests/test_*_common.py`, `tests/test_cooked_store.py`.
   → **Aucune mention de `gbp_ingest.py`, `secib_ingest.py`, `wix_forms_import.py`.** Un commit qui ne touche qu'eux ne déclenche aucun job. Confirmé.
4. Balayage de tous les workflows (`grep -rn "scripts/"` hors lignes `run:`, 02/09/2026 15:03 Paris) pour chercher une couverture ailleurs : `canonical-path-contract.yml` → `scripts/cooked_path.py` ; `tracker-test.yml` → `scripts/minify-tracker.py` ; `sql-contracts.yml` → les 4 `check_*.py` ; `python-ingest-contract.yml` → les 4 déjà cités. Les 10 workflows du repo sont : backup-weekly, canonical-path-contract, dashboard-contract, dfs-weekly-sync, edge-shared-helpers, gbp-daily-ingest, gsc-daily-ingest, python-ingest-contract, sql-contracts, tracker-test.
   → **Aucun workflow, sur les dix, ne référence les trois scripts autrement que pour les exécuter en production** (`gbp-daily-ingest.yml` les lance, il ne les teste pas). Le constat dit « ce workflow » ; je vais plus loin et je confirme sur l'ensemble du repo.
5. Étape de test du workflow (`python-ingest-contract.yml:36-47`) : `pip install pytest -r scripts/requirements-gsc.txt` puis `python3 -m pytest tests/test_gsc_common.py tests/test_dfs_common.py tests/test_cooked_store.py -q`. Aucune autre étape.

**Écart.** Aucun sur le fond, deux nuances.
- « ni test, ni lint, ni import-check » est vrai pour les trois scripts, mais la formule laisse croire que les scripts couverts, eux, bénéficient d'un lint et d'un import-check. Ce n'est pas le cas : le workflow ne fait que lancer trois fichiers de tests (point 5). Le déficit est donc plus uniforme que ne le suggère la phrase — il n'y a de lint nulle part.
- Détail relevé en passant, hors périmètre du constat : `test_canonical_path_contract.py` n'apparaît **ni** dans les `paths` de `python-ingest-contract.yml`, **ni** dans sa commande pytest ; il est couvert par `canonical-path-contract.yml`, qui se déclenche sur `scripts/cooked_path.py` et sur le test lui-même. La couverture existe, mais l'éclatement des déclencheurs entre deux workflows est précisément le mécanisme qui a permis l'oubli des trois scripts — argument supplémentaire pour la branche « supprimer le filtre `paths:` » de l'invariant.

**Invariant.** *Tient, et c'est un prérequis d'autres constats.* Étendre `paths:` à `scripts/*.py` — ou supprimer le filtre, ce qui est plus robuste puisqu'aucun oubli n'est alors possible — ferme la cause racine ; le coût est un job de quelques secondes sur des PR qui ne le concernent pas. Les cibles proposées sont les bonnes : je confirme par lecture que `normalize_phone_fr` / `normalize_email` (`secib_ingest.py:76-97`) et `build_row` (`wix_forms_import.py:100-135`) sont **pures, sans I/O, sans credentials** — `build_row` ne fait que lire un `dict` et calculer un sha1. Elles sont testables en l'état, sans refactor. Deux dépendances à noter dans l'ordonnancement : e-05 ne peut pas être verrouillé côté Python sans e-08, et e-04 ne peut pas avoir de test de non-régression sans e-08. **e-08 est donc le premier domino des trois.**

---

# PARTIE 3 — OBSERVATION HORS CONSTATS (zone e, incident actif)

Aucun des 8 constats ne le mentionne, et c'est le seul incident **en cours** que j'aie croisé dans la zone :

- `gbp_daily`, prod 02/09/2026 15:08 Paris : `dernier_jour_gbp = 20/08/2026`, **lag 13 jours**.
- `alerts` : `gbp_daily_stale` en `warn` quotidien depuis le 28/08 au moins, **escaladé en `critical` le 02/09 à 01:15**, toutes `acked = false`.
- Le pipeline GBP est donc mort depuis ~13 jours. La détection, elle, fonctionne (l'alerte de fraîcheur existe et a escaladé) — ce qui manque est la réaction. Le mode de défaillance attendu pour ce cron est la reauth ADC utilisateur, déjà survenue du 30/07 au 04/08/2026.
- À vérifier par qui reprendra : aucun chiffre GBP ne doit être livré tant que `max(day)` n'est pas revenu à J-4.

---

# PARTIE 4 — TABLEAU DE SYNTHÈSE

| ID | Verdict | Ce qui tient / ce qui ne tient pas | Invariant |
|---|---|---|---|
| e-01 | CONFIRMÉ | Structure exacte ; 0 rapprochement (pas 8) ; P1 latent, pas actif — aucun consommateur | tient (entrée freshness existe, désactivée) ; gate décoratif tant qu'il n'y a pas de consommateur |
| e-02 | CONFIRMÉ | Dérive, garde, marge 1h50, 3 alertes, cpi_daily complet : tout vérifié ; dérive non résorbée au 02/09 | tient — branche « marqueur last_full_refresh » nettement supérieure à l'extension d'horaire |
| e-03 | PARTIEL | Défaut structurel réel ; « ampleur non chiffrable » faux → 173/856 lignes (20,2 %) à email dupliqué ; mauvais témoin invoqué | tient, mais le test proposé est inerte (0=0) — le doubler d'un test indépendant de SECIB |
| e-04 | CONFIRMÉ | Code, migration, recoupement hebdo : tout reproduit ; j'ajoute la preuve d'index (seule unicité = wix_submission_id) | tient — le meilleur des huit ; + passer l'INSERT en upsert et retirer le DELETE ±2 s, dangereux |
| e-05 | CONFIRMÉ | 3 sorties reproduites + 3 vecteurs ajoutés ; miroir Python fidèle au défaut ; impact nul aujourd'hui | tient **si** e-08 est fait d'abord — sinon la moitié Python est décorative |
| e-06 | CONFIRMÉ | Aucune synchro, absente de freshness_contract, alerte muette : tout vérifié ; **2 articles invisibles, pas 1** | tient — seul correctif de fond ; ajouter la réconciliation des paths déjà en base |
| e-07 | PARTIEL | Fuite de filtre réelle (8 URL d'image) ; **10 non-articles, pas 11** — la troncature était inversée | exclusion tient ; la règle positive est supérieure ; ne couvre ni le base64 ni la parenthèse |
| e-08 | CONFIRMÉ | 5 tests, 974 lignes non couvertes, `paths:` vérifié sur les 10 workflows du repo | tient — **premier domino** : e-04 et e-05 en dépendent |

**Conditions de lecture.** Toutes les mesures prod ont été prises entre 15:03 et 15:08 Paris le 02/09/2026, en SELECT seul. `events_human` a été utilisée pour tout comptage de trafic et de `form_submit` ; `events` brute n'a jamais été interrogée. `crm_prospects`, `secib_dossiers` et `pont_prospects_dossiers` n'ont été lues qu'en agrégats — aucun nom, e-mail, téléphone ni identifiant individuel ne figure dans ce document. Aucune fonction écrivante n'a été appelée (ni `rpc_contract_check`, ni `cooked_alerts_refresh`, ni aucun `refresh_*`). Aucun fichier du repo n'a été modifié.
