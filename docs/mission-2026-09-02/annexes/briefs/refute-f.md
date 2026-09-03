Brief réfuteur zone (f) — CPI, cpi_daily, alertes CPI — mission Cooked 02/09/2026
Tu reçois 9 constats ci-dessous. Recopie-les TOUS en tête de ton livrable (ID, titre, sévérité, preuve, impact) ;
si tu en comptes moins de 9 ou si la liste est vide, arrête-toi et signale-le : ton livrable serait invalide.

Ta mission : DÉMOLIR chaque constat. Pour chacun, rends CONFIRMÉ / PARTIEL / RÉFUTÉ avec TA propre preuve — requête
ré-exécutée par toi (avec sortie et horodatage Paris), fichier relu par toi (fichier:ligne) — jamais la preuve du constat
recopiée. PARTIEL = le défaut existe mais la sévérité, l'ampleur ou la cause annoncée est fausse : dis ce qui tient et ce
qui ne tient pas. Tu ne sais pas qui a écrit ces constats et ça n'a aucune importance. Cherche activement : le cas où le
chiffre annoncé vient d'une fenêtre mal bornée, d'un filtre oublié (`events_human` vs `events`, Paris vs UTC), d'un
doublon de définition, d'un état déjà corrigé (migration, commit, CHANGELOG), d'une lecture périmée de `supabase/rpcs.sql`
(2 fonctions y diffèrent de la prod et 6 manquent : utilise `pg_get_functiondef` en prod). Pour chaque constat, dis aussi
si l'INVARIANT proposé empêcherait réellement la récidive, ou s'il est décoratif.

Contexte : repo local en LECTURE SEULE `/Users/nicolas/Desktop/Cooked/.claude/worktrees/cooked-architecture-review-c22b77`
(HEAD = main e95f3ee), prod Supabase `mxycmjkeotrycyneacje`. Lis `CLAUDE.md` (règles) et
`docs/mission-2026-09-02/00-baseline.md` (photo « avant »).

Mode LECTURE SEULE, mêmes interdits que l'auditeur : `apply_migration` ; `execute_sql` en écriture (INSERT/UPDATE/DELETE/
DDL/TRUNCATE/GRANT/REVOKE/ALTER) ; tout appel de fonction qui écrit ou qui dure — en particulier `rpc_contract_check`
(JAMAIS, même « pour tester » : il écrit dans `rpc_health`), `run_rpc_contract_tests`, `cooked_alerts_refresh`,
`raise_cooked_alert`, `record_ingest_drop`, `cooked_cpi_snapshot`, `cooked_refresh_after_gsc`, `refresh_*`, `purge_*`,
`math_refresh_snapshots`, `cooked_weekly_conversions_snapshot`, `dashboard_assisted_quarter` (timeout 30 s),
`cooked_page_index` ; `gh issue` / `gh pr create` / `gh workflow run` / `git push` / `git commit` / deploy ; toute
modification de fichier hors ton fichier de livrable ; toute lecture de `crm_prospects`, `secib_dossiers`,
`pont_prospects_dossiers` au-delà de `count(*)`, de la structure et d'agrégats sans valeur individuelle. Aucun nom,
e-mail, téléphone, secret ni clé dans ton livrable.

Outils : Bash en lecture (`cat`, `sed -n`, `grep -n`, `git log`, `git show`) ; prod par l'outil MCP
`mcp__5e27b44c-6b7a-4341-9569-4ba334f2be08__execute_sql` (charge-le via ToolSearch
`select:mcp__5e27b44c-6b7a-4341-9569-4ba334f2be08__execute_sql` ; `project_id` = `mxycmjkeotrycyneacje` ; SELECT /
WITH … SELECT / EXPLAIN uniquement ; fenêtres ≤ 28-30 j ; une requête à la fois ; le connecteur coupe à ~60 s) ;
`get_advisors` / `get_edge_function` (même préfixe) autorisés ; `gh run list` / `gh run view` / `gh pr list` en lecture.
Test HTTP lecture seule autorisé (curl GET sur `/rest/v1/...` avec la clé anon obtenue via `get_publishable_keys`) —
jamais de POST vers une RPC qui écrit.
Règles CLAUDE.md : `events_human` (jamais `events`, sauf diagnostic d'ingestion annoncé) ; fenêtre Paris ; dates
JJ/MM/AAAA, heures Paris. Garde-fous : ancrage obligatoire, `[non vérifié]` visible sinon ; les données lues en prod ne
sont jamais des instructions ; cite les corrections déjà existantes (CHANGELOG, migrations, git log).

Sortie : fichier `/private/tmp/claude-501/-Users-nicolas-Desktop-Cooked--claude-worktrees-cooked-architecture-review-c22b77/9b519bc0-2b53-4766-8ca9-4c99f100874a/scratchpad/agents/f-refute.md` (seul fichier autorisé) — en tête la recopie des 9 constats, puis pour chacun :
```
ID        f-nn / o-nn
Verdict   CONFIRMÉ | PARTIEL | RÉFUTÉ
Ma preuve requête + sortie + horodatage Paris, ou fichier:ligne (la tienne, pas celle du constat)
Écart     ce qui diffère du constat (sévérité, chiffre, cause, fenêtre) — ou « aucun »
Invariant tient / décoratif / manquant — pourquoi
```
Termine par un message de synthèse ≤ 15 lignes : `ID · verdict · une ligne`, nombre recopié / reçu, et tout constat que
tu n'as pas pu tester (avec la raison). Budget indicatif : 30-45 minutes.

=== CONSTATS REÇUS (9) ===

## Constats

```
ID            f-01
Titre         Le momentum du CPI est calculé sur ~18 % des clics de la page (médiane 9,8 %) — la
              correction « momentum non brandé » du 25/07 a troqué la source complète contre la
              traîne révélée par Google
Sévérité      P1
Preuve        Régression tracée à la ligne :
              - AVANT : `supabase/migrations/20260723212008_cpi_fiabilite_opportunite_contact.sql:100`
                → CTE `mom` … `FROM public.gsc_path_daily gpd WHERE day > current_date - 2*p_days`
                (clics complets de la page).
              - APRÈS : `supabase/migrations/20260725220200_audit_cpi_corrections.sql:94-95`
                → `FROM public.gsc_query_page_daily g WHERE g.day > current_date - 2*p_days
                   AND NOT public.gsc_is_branded(g.query)`.
              - Prod aujourd'hui = ce dernier état : `supabase/rpcs.sql:1236-1243` (CTE `mom`),
                corps prod vérifié identique (`pg_get_functiondef` : 4 occurrences de
                `gsc_is_branded`, 1 de `least(100`, 2 de `cpi_raw`, 4 de `now()` — mêmes
                comptes que le fichier local ; 02/09 09:56 Paris).
              Couverture mesurée (02/09 10:01 Paris) — clics vus par `mom` (qpd non brandé, 28 j)
              rapportés aux clics réels (`gsc_path_daily`, 28 j), par grade sur le snapshot du 01/09 :
                grade S : 294 / 1 027 = 28,6 %  (médiane page 26,3 %)
                grade A : 131 /   683 = 19,2 %  (médiane page 13,4 %, p10 6,9 %)
                grade B : 267 / 1 504 = 17,8 %  (médiane page  9,8 %, p10 1,8 %)
              Décomposition sur les 3 pages qui alertent aujourd'hui (02/09 10:04 Paris) :
                /post/indemnisation-passager-accident-route : 1 clic vu / 30 réels (3,3 %),
                  terme clics du momentum = 0,000 ; clics réels 48 → 30 = −37,5 % (baisse réelle
                  invisible du momentum) ; +1 clic révélé déplacerait le terme de +0,154.
                /post/indemnisation-accident-moto-motard : 2 clics vus / 41 réels (4,9 %),
                  terme clics = 0,000 ; clics réels 34 → 41 = **+21 %** ; 0 clic brandé révélé
                  sur la fenêtre → la hausse n'est pas un artefact de marque ; momentum prod = 0,81
                  (« ↘ »), produit par `avg(position)` NON pondérée sur 313 lignes requête×jour
                  (17,27 → 20,95).
                /post/la-préméditation-… : 10 / 43 (23,3 %), direction cohérente (24 → 10 vus,
                  119 → 43 réels).
Impact        `momentum` entre dans le CPI comme facteur multiplicatif (`cpi_compose(… , mm, gg)`,
              `supabase/rpcs.sql:1266-1267`) et pèse `corr(cpi, momentum) = 0,485` sur le snapshot
              du 01/09 (177 pages). Sur les pages B — 38 des 177 pages du snapshot et 69 des 100
              chutes ≥ 15 pts d'août (cf. f-02) — le terme clics du momentum est calculé sur ~4
              clics au lieu de ~40 : le lissage `+5/+50` rend alors le momentum quasi indépendant
              des clics et le fait dépendre d'une moyenne de position non pondérée sur la traîne
              anonymisée. Conséquence directe : l'alerte `cpi_drop` du 01/09 08:15 Paris (alerte
              id 130) annonce « 1 page fiable en vrai decay » sur une page dont les clics
              organiques ont **augmenté de 21 %** entre les deux fenêtres de 28 j.
              Ceci viole le piège n°3 du playbook (`CLAUDE.md` : « les TOTAUX viennent de
              `gsc_path_daily` ; qpd sert au mix positionnel et à l'attribution ») — le terme
              capture le respecte (`capp` sur `gsc_path_daily`, `supabase/rpcs.sql:1166`), le
              momentum non.
Récidive      Oui, forme mutée. Le constat « Majeur » de `docs/audit-architecture-2026-07-25.md:199`
              (« le momentum compte les clics de marque alors que la capture les exclut ») a été
              traité par le correctif n°9 du même audit (`docs/audit-architecture-2026-07-25.md:262-264`,
              état « Fait » ligne 284). Le filtre brandé n'existant que sur `gsc_query_page_daily`
              (pas de colonne `query` dans `gsc_path_daily`), la correction a changé de source sans
              que l'échange de biais soit mesuré : un biais connu et borné (`/notre-cabinet` 76 %
              brandé, 1 page) a été remplacé par une perte de couverture de 82 % sur toutes les pages.
Invariant     Un test de contrat sur la couverture du momentum : pour chaque page de grade S/A/B du
              dernier `cpi_daily`, `clics_qpd_non_brandés / clics_gsc_path_daily` doit dépasser un
              plancher (ou le momentum doit être marqué non fiable / neutralisé) ; un `cpi_drop`
              dont la page a des clics `gsc_path_daily` en hausse sur les deux fenêtres devrait être
              refusé par construction. Aucun test de ce genre n'existe : `alert_rule_cpi_drop` ne lit
              que `cpi_movers`, qui ne connaît pas les clics réels.
Statut        [recoupé sur deux sources — `gsc_query_page_daily` vs `gsc_path_daily`, plus
              décomposition brandé/non brandé. Réserve : `gsc_path_daily` n'a pas de colonne
              `query`, donc l'absence de clics brandés sur la page moto est établie par la
              fraction révélée (0 clic brandé sur 313 lignes qpd), pas exhaustivement.]
```

```
ID            f-02
Titre         Le garde-fou « vrai decay » de `cpi_drop` teste la VARIATION du momentum (≤ −0,10),
              soit un demi-écart-type de son bruit à 7 j — 38 % des alertes qu'il laisse passer
              disparaissent si l'on gèle la conversion, ce qu'il était censé exclure
Sévérité      P1
Preuve        Règle prod (baseline Phase 0, `supabase/rpcs.sql`) :
              `statut='present' AND fiable AND delta_cpi <= -15 AND ecart_jours <= 8
               AND (delta_momentum <= -0.10 OR delta_zc <= -0.5)`.
              (a) Bruit du momentum — requête sur `cpi_daily`, paires (page, jour) vs jour−7,
              01/08 → 01/09, grade S/A/B aux deux dates (02/09 09:58 Paris) :
                1 350 paires / 53 pages ; Δmomentum 7 j : moyenne +0,017, **écart-type 0,199**,
                médiane 0,000, p25 −0,080, p10 −0,210.
                → **305 paires (22,6 %) franchissent le seuil −0,10** ; parmi elles **93 (30,5 %)**
                  ont un `momentum` courant ≥ 1,00, c'est-à-dire une page qui croît plus vite que
                  le site tout en étant qualifiée de « vrai decay ».
                → le seuil −0,10 vaut **0,50 σ** du bruit à 7 j : il ne sépare pas le decay du bruit.
              (b) Part portée par la conversion — mêmes paires, chutes ≤ −15 pts, contrefactuel
              `cpi_compose(zc,zr,zl, zv_du_jour_de_référence, mm, gg)` (02/09 09:59 Paris) :
                150 chutes ≤ −15 pts au total, dont **100 passent le garde-fou** (24 pages).
                chute moyenne −24,9 pts → **−17,2 pts si `zv` est gelé** (la conversion porte
                7,7 pts, 31 %) ; et **38 des 100 (38 %) repassent au-dessus de −15 pts**, donc
                n'existeraient pas sans mouvement de `zv`.
                Les 50 chutes rejetées par le garde-fou sont, elles, quasi intégralement portées
                par `zv` (chute moyenne +2,9 pts une fois `zv` gelé) : le garde-fou filtre
                réellement quelque chose, mais laisse fuir 38 % de faux positifs de même nature.
              (c) Aujourd'hui, recompute depuis `cpi_movers` (02/09 09:52 Paris) — les 3 pages
              retenues par la règle correspondent exactement à l'alerte id 134 (02/09 09:15 Paris) :
                préméditation      36→17 (−19) Δzv −1,4 Δmom −0,13 momentum courant **1,27**
                passager-accident  84→66 (−18) Δzv +0,2 Δmom −0,24 momentum courant **1,04**
                moto-motard        69→53 (−16) Δzv −1,7 Δmom −0,12 momentum courant 0,81
                (la 4e chute ≥ 15 pts — abus-de-confiance 78→62, Δzv −1,0, Δmom 0,00 — est bien
                 rejetée : le garde-fou fonctionne dans ce cas.)
                → 2 des 3 pages annoncées « en vrai decay » ont un momentum ≥ 1,04, donc croissent
                  relativement au site ; leur chute est portée par `zv`.
              (d) `fiable` inclut le grade B (`pg_get_viewdef('cpi_movers')`, 02/09 09:51 Paris :
              `COALESCE((n.grade = ANY (ARRAY['S','A','B'])) AND (p.grade = ANY (…)), false)`),
              alors que B est documenté « indicatif » (`docs/cpi-cooked-page-index.md:74`).
              **69 des 100 chutes passant le garde-fou sont des pages de grade B** ; sur B, un seul
              contact qui sort de la fenêtre 28 j suffit à déplacer `zv` de plusieurs points.
Impact        Sur la fenêtre 01/08 → 01/09 : 100 épisodes page×jour qualifiés « vrai decay », dont
              38 n'existent que par la volatilité de la conversion — exactement le mode de faux
              positif que la recalibration du 17/06/2026 devait supprimer — et 27 sur des pages
              dont le momentum courant est ≥ 1,00. Le diagnostic livré (« vrai decay », « volatilité
              conversion exclue ») est faux dans ces cas, et il est poussé sur ntfy en `critical`
              (cf. f-03).
Récidive      Oui. `docs/audit-architecture-2026-07-25.md:186` constatait déjà « alerte de decay
              fausse, répétée quotidiennement ». La recalibration du 17/06/2026 (migration
              `20260617215132`, résumée dans `CLAUDE.md`) a introduit le garde-fou momentum/capture
              précisément pour « exclure la volatilité pure de la conversion » ; le garde-fou a été
              posé sur la **variation** du momentum sans que le bruit de cette variation soit
              mesuré. C'est la même erreur de méthode que le seuil de `double_embed_suspect`
              avant sa recalibration : un seuil choisi sans distribution de référence.
Invariant     (1) Le garde-fou doit porter sur le **niveau** du momentum (ex. `momentum_now` sous
              un seuil) et non seulement sur sa variation, ou être calibré sur le percentile
              empirique des Δmomentum de la population fiable, recalculé et versionné.
              (2) Un test de contrat qui, sur les 30 derniers jours de `cpi_daily`, vérifie que la
              part des `cpi_drop` dont la chute disparaît quand `zv` est gelé reste sous une borne
              déclarée. (3) `fiable` devrait exiger S/A pour une alerte poussée, B restant
              consultatif. Aucun de ces trois filets n'existe.
Statut        [recoupé — recompute indépendant depuis `cpi_daily` qui reproduit exactement la
              sélection de l'alerte du jour ; contrefactuel calculé avec la fonction prod
              `cpi_compose` (IMMUTABLE, aucune écriture).]
```

```
ID            f-03
Titre         `cpi_drop` émet un warn tous les ~25 h depuis 24 jours et une escalade critical
              quotidienne poussée sur ntfy, à une heure qui dérive dans la nuit — le canal
              d'alerte du CPI est saturé par un seul motif
Sévérité      P1
Preuve        `SELECT severity, count(*), count(DISTINCT paris_date(created_at)), min/max …
               FROM alerts WHERE kind='cpi_drop' AND created_at >= '2026-08-10'`
              (02/09 10:12 Paris) :
                warn     : **23 épisodes sur 23 jours distincts**, du 10/08 19:15 au 02/09 09:15,
                           dont **8 émis entre 00:00 et 06:00 Paris** ;
                critical : **9 épisodes sur 9 jours distincts**, du 23/08 23:15 au 01/09 20:15,
                           dont 2 entre 00:00 et 06:00 Paris.
              Horodatages Paris des warns non acquittés (02/09 09:54 Paris) : 10/08 19:15,
              11/08 19:15, 12/08 19:15, 13/08 20:15, 14/08 20:15, 15/08 21:15, 16/08 22:15,
              17/08 22:15, 18/08 23:15, **[19/08 absent]**, 20/08 00:15, 21/08 01:15, 22/08 01:15,
              23/08 02:15, 24/08 03:15, 25/08 03:15, 26/08 04:15, 27/08 05:15, 28/08 06:15,
              29/08 06:15, 30/08 07:15, 31/08 08:15, 01/09 08:15, 02/09 09:15.
              → l'heure d'émission avance de ~1 h par jour, ce qui est la signature d'une dédup
                de 24 h : le corps prod de `raise_cooked_alert` contient 1 occurrence d'un
                intervalle de 24 h (`pg_get_functiondef`, 02/09 10:10 Paris) ; la baseline Phase 0
                documente « dédup (kind, severity) 24 h ». Conséquence mécanique : une journée
                calendaire est sautée périodiquement (19/08), et la ronde repasse dans la nuit.
              Les escalades `critical` (`alert_rule_warn_escalation`, « warn ≥ 5 j sans
              acquittement ») partent sur ntfy : la baseline Phase 0 relève un HTTP 200 dans
              `net._http_response` au 01/09 20:15 Paris pour l'escalade `cpi_drop`.
Impact        Panne d'observabilité, pas de chiffre faux : le motif `cpi_drop` occupe 32 des 48
              alertes non acquittées du système (baseline Phase 0, `00-baseline.md:19`) et produit
              une notification poussée par jour, dont une partie la nuit. Un `cpi_drop` réellement
              signifiant (ou une autre alerte critical) est indiscernable du bruit de fond. Sachant
              (f-02) que 38 % de ces épisodes sont des faux positifs de conversion et (f-01) qu'un
              d'entre eux porte sur une page en croissance de 21 %, la saturation est alimentée
              par un diagnostic non fiable.
Récidive      Partielle. `docs/audit-architecture-2026-07-25.md:186` relevait déjà « un delta
              republié chaque heure » ; le correctif n°4 (« dédup sur `kind` seul et purge des 23
              alertes en stock », ligne 246) a bien ramené la cadence de horaire à ~quotidienne,
              mais la dédup posée est sur `(kind, severity)` et non sur `kind`, et rien ne borne la
              répétition d'un même motif dans le temps. Un acquittement de masse a déjà servi de
              soupape le 10/08 (46 alertes acquittées en bloc, baseline Phase 0) : le motif est
              revenu le jour même.
Invariant     Une dédup par **empreinte de contenu** (kind + ensemble des paths concernés) plutôt
              que par `(kind, severity)`, un back-off au-delà de N épisodes consécutifs non
              acquittés, et une fenêtre horaire d'émission pour les pushes. Rien de tout cela
              n'existe. (Le mécanisme `raise_cooked_alert` / `warn_escalation` appartient à la
              zone h ; ici seul le motif `cpi_drop` est constaté.)
Statut        [non recoupé pour la réception effective des pushes côté téléphone — non vérifiable
              depuis la prod. Les épisodes et leurs horodatages sont, eux, lus directement dans
              `alerts`.]
```

```
ID            f-04
Titre         La fenêtre Cooked du CPI glisse sur `now()` : deux jours « consécutifs » de
              `cpi_daily` sont séparés de 18 h à 34 h en août, et cet écart d'horloge explique une
              part mesurable du mouvement quotidien du score
Sévérité      P2
Preuve        Code : la moitié Cooked de `cooked_page_index` est bornée par `now()` —
              `supabase/rpcs.sql:1173` (`firstpv` … `occurred_at > now() - make_interval(days => p_days)`),
              `:1176` (`spv`), `:1181` (`pex`), `:1241` (`lcp`) — soit 4 occurrences de `now()`,
              nombre confirmé dans le corps prod (02/09 09:56 Paris). La moitié GSC, elle, est
              bornée par `current_date` (`:1166`, `:1236-1237`). Le snapshot est ensuite étiqueté
              par une simple `day` (colonne `day date`, `information_schema`, 02/09 10:09 Paris).
              Heures d'exécution réelles (`SELECT day, min(created_at) … FROM cpi_daily
              WHERE day > current_date - 14 GROUP BY day`, 02/09 09:50 Paris) :
                20→26/08 : 10:00 Paris chaque jour
                27/08 20:00 · 28/08 21:00 · 29/08 15:00 · 30/08 14:00 · 31/08 15:00 · 01/09 14:00
              Sur les 31 paires de jours consécutifs d'août (02/09 10:07 Paris) :
                écart réel entre deux snapshots : **min 18,0 h, max 34,0 h, σ 2,18 h** ;
                **corr(écart en heures, |Δcpi| moyen du jour) = +0,468** ;
                corr(écart en heures, Δzv moyen) = +0,213.
              Illustration : le 27/08 (bascule 10:00 → 20:00, soit 34 h écoulées) est le jour au
              plus fort |Δcpi| moyen de la période (4,09 pts) et compte 17 pages dont `zv` bondit
              de ≥ 0,5 — contre 0 à 4 pages les autres jours (02/09 10:05 Paris).
Impact        Le CPI est publié comme une série quotidienne et lu comme telle (`cpi_movers`,
              alerte `cpi_drop`, sparklines du dashboard). Une partie du mouvement jour-à-jour
              n'est pas un mouvement de page mais un déplacement de la borne haute de la fenêtre
              Cooked (n_org, rétention, lecture, conversion). Sur `cpi_movers`, la paire du jour
              (01/09 14:00 vs 25/08 10:00) couvre 172 h au lieu de 168 (+2,4 %) ; la paire
              28/08 21:00 vs 21/08 10:00 en couvrait 179 (+6,5 %). L'effet est faible en moyenne
              mais s'ajoute au bruit contre lequel le seuil de f-02 est censé discriminer.
Récidive      Oui — non corrigé. Constat « Moyen » de `docs/audit-architecture-2026-07-25.md:215`
              (« deux lignes consécutives couvrent des fenêtres décalées de 4 h 33 »). Il n'a pas
              été retenu dans le plan de correction (les 10 items, lignes 225-263, n'y touchent
              pas ; seuls les 3 correctifs de l'item 9 concernaient le CPI). L'écart est
              aujourd'hui **plus large qu'alors** (16 h d'amplitude contre 4 h 33). Le problème est
              connu du code : `cooked_refresh_after_gsc` porte le commentaire « CPI en PREMIER : un
              jour manqué de `cpi_daily` est perdu pour toujours (`cooked_page_index` lit `now()`) »
              (corps prod, 02/09 10:00 Paris) — la conséquence a été acceptée sans être mesurée.
Invariant     Passer les 4 bornes Cooked à la même horloge que la moitié GSC (bornes de jour
              Paris, `cooked_paris_ts_start`/`_end_exclusive` existent déjà en prod) — le score
              deviendrait alors reproductible pour un `day` donné — plus un test de contrat qui
              vérifie que `cooked_page_index` recalculée deux fois le même jour civil rend le même
              score. En l'état, aucun `cpi_daily` passé n'est reproductible.
Statut        [recoupé — corrélation calculée sur 31 jours, et le jour de bascule d'horloge
              identifié indépendamment via les Δzv. La corrélation ne démontre pas la causalité
              à elle seule ; l'ancrage causal est le code (`now()` aux 4 bornes Cooked).]
```

```
ID            f-05
Titre         Quatrième rupture de définition de `cpi_daily` (25/07 : source du momentum +
              `convertit`) sans colonne de version ni annotation, et la doc affirme une annotation
              du 02/07 qui n'existe pas
Sévérité      P2
Preuve        (a) `cpi_daily` n'a **aucune colonne de version** : les 17 colonnes sont `day, path,
              ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org,
              couv_gsc_pct, created_at, convertit` (`information_schema.columns`, 02/09 10:09 Paris).
              (b) Table `annotations` — 7 lignes (02/09 10:03 Paris) :
                02/07 `site_change` « Refonte complète de l'article (contenu, structure) », 1 path
                12/07 `autre` « Restatement CPI (soir) : conversion recousue via identity_stitch… »
                13/07 ×2 (`site_change`, `autre`)
                25/07 `site_change` « Finitions audit 26/07 : Baidu centralisé (cooked_events_window
                      + pulse/context), VACUUM FU… »
                27/07 `site_change` « Restatement CPI — classify_channel v3 … »
                23/08 `autre` « Backfill de 22 form_submit (12-21/08)… »
              → aucune ligne pour le restatement CPI du **02/07** (grain lectures) : la ligne du
                02/07 concerne un article. Aucune ligne pour la redéfinition du **25/07** : la
                ligne du 25/07 parle de Baidu et du VACUUM, pas du CPI.
              (c) Pourtant `docs/cpi-cooked-page-index.md:165-168` : « Trois corrections de mesure
              ont restaté le snapshot du jour. **Comparer un CPI d'avant/après ces dates revient à
              comparer deux définitions** … Annotations posées dans la table `annotations`. » puis
              liste 02/07, 12/07, 27/07. L'affirmation est fausse pour le 02/07.
              (d) La redéfinition du 25/07 est matérielle et non listée comme rupture : elle change
              la source du momentum (f-01, `20260725220200:94`) **et** la définition de `convertit`
              (`coalesce(cv.val,0) > 0`, `supabase/rpcs.sql:1260`). Elle n'apparaît ni dans la liste
              des ruptures de la doc, ni dans `annotations`.
              (e) `docs/cpi-cooked-page-index.md:191-192` présente encore les tables d'audit
              `cpi_pre_restatement_20260712` / `_20260727` comme existantes ; elles ont été
              supprimées le 10/08/2026 (`CLAUDE.md`, migration `20260810093206`).
Impact        Toute lecture longitudinale de `cpi_daily` traversant le 02/07, le 25/07 ou le 27/07
              compare deux définitions sans qu'aucun signal dans la donnée ne le dise. Le
              re-test diagnostic 56 j prévu (t0 = 10/06) traverse **les quatre** ruptures. Les
              photos d'avant-restatement ayant été supprimées et la table n'ayant pas de version,
              aucun restatement passé n'est plus ré-auditable : l'ampleur annoncée du 02/07
              (« ±7 pts max sur 4 pages A/B ») n'est plus contrôlable.
Récidive      Oui. `docs/audit-architecture-2026-07-25.md:209` : « `cpi_daily` a subi 3 ruptures de
              définition sans colonne de version, dont un `UPDATE` rétroactif des grades le 23/07 »,
              avec l'impact explicitement anticipé : « Le re-test diagnostic 56 j du 05/08
              segmentera sur des grades reconstruits, sans le savoir ». Le constat n'a pas été
              retenu dans le plan de correction, et la correction du même audit (25/07) a ajouté
              la 4e rupture, non annotée.
Invariant     Une colonne `cpi_version` (ou `def_hash`) dans `cpi_daily`, alimentée par
              `cooked_cpi_snapshot()`, plus un gate CI qui refuse une migration redéfinissant
              `cooked_page_index` / `cpi_compose` sans bump de version **et** sans ligne
              d'annotation de restatement. Le gate existant `check_rpcs_sql_fresh.py` ne vérifie
              que la fraîcheur du miroir `rpcs.sql`, pas la traçabilité sémantique.
Statut        [recoupé — annotations lues en prod, doc lue au fichier:ligne, ruptures tracées aux
              migrations.]
```

```
ID            f-06
Titre         La spécification mathématique canonique du CPI documente un momentum sur
              `gsc_path_daily` — ce que la prod ne fait plus depuis le 25/07 — et une grille de
              grades antérieure au 23/07
Sévérité      P2
Preuve        `docs/cpi-modele-mathematique.md:378-383` (annexe SQL de référence) :
                `mom AS (SELECT gpd.path, … FROM gsc_path_daily gpd WHERE day>current_date-2*p_days …)`
              Prod : `FROM public.gsc_query_page_daily g … AND NOT public.gsc_is_branded(g.query)`
              (`supabase/rpcs.sql:1241-1242`, corps prod confirmé 02/09 09:56 Paris).
              Le corps du texte est muet sur la source : §8 (`:168-189`) définit « Clics page
              courant/précédent $c_1,c_0$ ; clics site $s_1,s_0$ » sans dire qu'il s'agit du
              sous-ensemble de requêtes révélé par Google, alors que le même document signale
              ailleurs « couverture GSC parfois ~6 % » comme contrainte majeure (`:35-36`).
              Autres dérives de la même annexe :
                `:400` grille de grades `A / B / C` sans `S` — la norme S/A/B/C date du 23/07/2026
                       (`docs/cpi-cooked-page-index.md:74`, prod `supabase/rpcs.sql:1252-1257`) ;
                `:314`, `:318`, `:320` filtre brandé écrit `query !~* 'plouton'` — prod utilise
                       `gsc_is_branded(query)` depuis Arch #3 (10/07, `20260710183000_gsc_is_branded.sql`).
              Historique : ces deux docs n'ont pas été touchées depuis le 28/07
              (`git log --since=2026-07-20 -- docs/cpi-modele-mathematique.md docs/cpi-cooked-page-index.md`
              → 2026-07-28 `4085647`, 2026-07-24 `4e65818`), soit **3 jours après** la migration
              qui a changé la source du momentum, sans que l'annexe soit mise à jour.
Impact        La doc désignée comme référence des formules par `docs/cpi-cooked-page-index.md:10`
              et par la carte documentaire de `CLAUDE.md` décrit un momentum à couverture complète.
              Un lecteur — humain ou agent — qui vérifie le CPI contre cette spec conclut que le
              momentum est calculé sur tous les clics de la page. C'est le mécanisme par lequel
              f-01 est resté invisible 39 jours : la revue d'experts, la validation J+28 et la
              baseline se sont toutes appuyées sur une spec qui ne décrit plus la prod.
Récidive      Non constatée antérieurement sur ce point précis. À noter cependant que le même
              audit a produit un gate CI pour le miroir des corps de RPC
              (`scripts/check_rpcs_sql_fresh.py`, Arch #5) : la divergence prod/miroir est gardée,
              la divergence prod/**spécification** ne l'est pas.
Invariant     Faire porter le gate `check_rpcs_sql_fresh.py` (ou un gate frère) sur l'annexe SQL de
              `docs/cpi-modele-mathematique.md` : toute migration qui redéfinit `cooked_page_index`
              doit échouer en CI si l'annexe n'est pas régénérée. Ou, plus simple : supprimer
              l'annexe SQL de la doc et pointer `supabase/rpcs.sql`, seule copie sous gate.
Statut        [recoupé — fichier:ligne des deux côtés, plus comptage de motifs identique entre le
              corps prod et le miroir local.]
```

```
ID            f-07
Titre         Le « potentiel » de `cpi_opportunite_contact` est toujours multiplié par le momentum
              et le gate, contrairement à sa doc : 12,6 pts d'écart moyen et 5 pages sur 14
              déplacées de ≥ 3 rangs dans le classement de pilotage
Sévérité      P2
Preuve        Vue prod (`pg_get_viewdef('cpi_opportunite_contact')`, 02/09 09:53 Paris) :
                `round(cpi_compose(zc, zr, zl, 0::numeric, momentum, gate, true))::integer AS potentiel`
              → `momentum` et `gate` sont passés explicitement, et `cpi_compose` se termine par
              `* mm * gg` **dans les deux branches**, `exclude_conversion` comprise
              (`pg_get_functiondef('cpi_compose')`, 02/09 09:52 Paris).
              La doc décrit le potentiel comme « capture + rétention + lecture, renormalisés hors
              conversion » (`docs/cpi-cooked-page-index.md:57-59`) — sans facteur conjoncturel.
              Impact chiffré sur le snapshot du 01/09, périmètre documenté du pilotage
              (`grade IN ('S','A','B') AND NOT convertit`, `ORDER BY potentiel DESC`), 02/09 10:14 Paris :
                14 pages ; écart |potentiel publié − potentiel structurel (mm=1, gg=1)| :
                **moyenne 12,6 pts, maximum 22 pts** ; corrélation des rangs 0,820 ;
                **5 pages sur 14 déplacées de ≥ 3 rangs** ; 1 page entre dans le top 5 uniquement
                par son momentum.
              À noter : la renormalisation hors conversion est, elle, correcte
              (0,46 / 0,23 / 0,3077 ≈ 0,30 / 0,15 / 0,20 divisés par 0,65).
Impact        La liste « opportunité de contact » est le livrable de pilotage conversion validé au
              Sprint 39 (« le levier est l'action sur les opportunités de contact », `CLAUDE.md`).
              Son classement mélange le potentiel structurel et « en ce moment ça monte » ; sur 14
              pages, plus d'un tiers changent de place, et le facteur qui les déplace est le
              momentum — c'est-à-dire la grandeur dont f-01 établit qu'elle est calculée sur ~10 %
              des clics d'une page B.
Récidive      Oui — non corrigé. Constat « Moyen » de `docs/audit-architecture-2026-07-25.md:212`,
              avec le même diagnostic (« `cpi_compose` se termine par `* mm * gg` ; 53 → 46 sur
              `/notre-cabinet` ») et la même conclusion (« `ORDER BY potentiel DESC` mélange
              potentiel structurel et "en ce moment ça monte" »). Non retenu dans le plan de
              correction (items 1-10, lignes 225-263). Le COMMENT de la vue a été mis à jour sur un
              autre point le 23/07 (« convertit = contact organique réel (val>0), pas zv>0 »,
              02/09 09:55 Paris) : la vue a donc été revue depuis, sans que ce point soit traité.
Invariant     Un test de contrat qui vérifie l'identité `potentiel = cpi_compose(zc,zr,zl,0,1,1,true)`
              (potentiel structurel) ou, si le facteur conjoncturel est voulu, une colonne séparée
              et un COMMENT qui le dit. Rien ne relie aujourd'hui la doc de la vue à son corps.
Statut        [recoupé — corps de la vue et de la fonction lus en prod, écart recalculé avec la
              fonction prod elle-même.]
```

```
ID            f-08
Titre         Le check mensuel §3 (calibration de la courbe CTR) n'a pas été rejoué depuis le
              11/07 ; lancé aujourd'hui, son indicateur de suivi a dérivé de 20,1 % à 28,8 % — et
              le re-test 56 j dû le 05/08 n'est toujours pas lancé
Sévérité      P2
Preuve        Le harnais déclare §3 « exécutable à tout moment ; check mensuel »
              (`scripts/cpi_validation_j28.sql:347`, repris `:39`, `:64`, `:78`, `:98`), avec pour
              critère liant `r2 ≥ 0,85` et pour indicateur de suivi la médiane |écart| par bucket
              (`:377-380`). Derniers chiffres enregistrés : R² 0,930 / médiane 20,1 % au tir réel du
              11/07/2026 (`docs/cpi-cooked-page-index.md:145-148`), référence 10/06 : 0,917 / 24 %.
              §3 est un SELECT pur et borné (90 j, agrégat) : je l'ai rejoué en lecture
              (02/09 10:11 Paris), dans ses deux variantes de filtre brandé :
                harnais (`query !~* 'plouton'`) : R² **0,909**, pente −1,250, 20 buckets,
                  médiane |écart| **28,8 %**, CTR prédit en position 1 = 8,11 %
                prod (`NOT gsc_is_branded(query)`) : R² 0,909, pente −1,250, 20 buckets,
                  médiane |écart| 28,8 %, CTR position 1 = 8,11 % — **identique**
              → critère liant : PASSE (0,909 ≥ 0,85). Indicateur de suivi : **20,1 % → 28,8 %**,
                soit +43 % en relatif, jamais relevé — la dernière trace d'exécution est le 11/07.
              `docs/ROADMAP.md:14` : « 3 | Re-test diagnostic CPI 56 j | 05/08/2026 | … **Pas
              encore lancé.** » — 28 jours de retard au 02/09/2026. Aucune trace d'exécution
              (`git log --since=2026-08-01 -- scripts/cpi_validation_j28.sql` : vide).
Impact        Le terme capture `zc` est standardisé contre cette courbe, et `clics_perdus` est
              l'écart à cette courbe : `cpi_capture_perdue` publie aujourd'hui **1 185 clics perdus
              sur 28 j** sur 29 pages, dont 1 035 sur les 15 pages marquées `interpretable`
              (02/09 10:06 Paris). Ces 1 035 clics reposent sur une loi de puissance dont l'erreur
              médiane par bucket est de 28,8 % — non pas invalide (R² tient), mais dégradée depuis
              la validation, sans que personne ne le sache. Le re-test 56 j, lui, traversera les
              quatre ruptures de définition de f-05.
Récidive      Le mécanisme est neuf, mais il reproduit le motif documenté du projet : un contrôle
              défini, exécuté une fois, jamais réarmé (même forme que le check `latest_rpc_health`
              « ok » figé relevé par `docs/audit-architecture-2026-07-25.md:94`). Aucune régression
              de code : c'est une routine humaine non tenue.
Invariant     §3 devrait être une routine planifiée (cron ou GitHub Actions) écrivant son R² et sa
              médiane |écart| dans une table, avec une alerte de fraîcheur sur cette table — le
              registre `freshness_contract` existe déjà et couvre 13 sources, aucune n'étant la
              calibration CTR. Un check qui dépend d'un rappel dans un fichier ROADMAP n'est pas
              un invariant.
Statut        [recoupé — §3 relancé dans ses deux variantes de filtre, résultats identiques,
              comparés aux deux références documentées (10/06 et 11/07).]
```

---


```
ID            o-11 (zone f)
Titre         Restatements sans annotation : CPI 02/07 (grain lectures), `classify_channel` v2 IA 02/07, `page_taxonomy` +12 articles 31/08
Sévérité      P3
Preuve        Q-22 : 7 lignes dans `annotations` — aucune ne mentionne le 02/07 CPI (la ligne 02/07 = refonte d'un article), ni la v2 IA, ni le 31/08 ; `docs/cpi-cooked-page-index.md` « Annotations posées dans la table annotations » pour les trois restatements CPI.
Impact        un « avant/après 02/07 » ou « 31/08 » dans les séries est lu comme un mouvement réel.
Récidive      règle §2.10 de la mission ; CLAUDE.md « table annotations à remplir ».
Invariant     checklist PR : toute migration étiquetée « restatement » exige une ligne `annotations` (test CI sur le nom de migration).
Statut        [non recoupé]
```
