# Zone (f) — CPI, `cpi_daily`, alertes CPI — passe de RÉFUTATION
Mission Cooked du 02/09/2026, Phase 1. Mode LECTURE SEULE (aucune écriture, aucun
`apply_migration`, aucun appel de fonction qui écrit ; `cpi_compose` IMMUTABLE utilisée en lecture).
Repo `/Users/nicolas/Desktop/Cooked/.claude/worktrees/cooked-architecture-review-c22b77`, HEAD = `e95f3ee`.
Prod Supabase `mxycmjkeotrycyneacje`. Toutes mes requêtes ont été ré-exécutées par moi le **02/09/2026**
entre **15:06 et 15:28 (Paris)**.

**Comptage : 9 constats reçus / 9 recopiés** (f-01 … f-08 + o-11). Livrable valide.

---

# PARTIE 1 — RECOPIE DES 9 CONSTATS REÇUS

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

---

# PARTIE 2 — VERDICTS (ma preuve, ré-exécutée)

Note transversale valable pour tous les chiffres de snapshot : les constats ont été écrits sur le
snapshot `cpi_daily` du **01/09/2026** ; entre-temps le snapshot du **02/09/2026 13:00 Paris** a été
produit (175 pages). Je travaille donc sur le snapshot du 02/09 et l'écart de périmètre jour-à-jour
est signalé à chaque fois. `gsc_last_data_day()` = **30/08/2026** (lag J-3, normal).

---

```
ID        f-01
Verdict   CONFIRMÉ (et plus grave que décrit)
```

**Ma preuve.**

*1. Le code, lu en prod, pas dans le miroir* — `pg_get_functiondef('public.cooked_page_index')`,
02/09/2026 **15:06** Paris. La CTE `mom` du corps prod est bien :

```
mom AS (SELECT g.path, … FROM public.gsc_query_page_daily g
        WHERE g.day > current_date - 2*p_days AND NOT public.gsc_is_branded(g.query) GROUP BY g.path)
```

alors que la CTE `capp` du terme capture lit `public.gsc_path_daily`. Régression tracée par moi aux
deux migrations locales : `supabase/migrations/20260723212008_cpi_fiabilite_opportunite_contact.sql:95-100`
(`FROM public.gsc_path_daily gpd`) → `supabase/migrations/20260725220200_audit_cpi_corrections.sql:89-96`
(`FROM public.gsc_query_page_daily g … NOT public.gsc_is_branded`). Le miroir
`supabase/rpcs.sql:1230-1237` est **à jour** sur cette fonction (4 `now()`, 4 `gsc_is_branded` dans le
corps délimité — comptés par moi sur le fichier et identiques au corps prod) : ce n'est pas une des
2 fonctions périmées du miroir.

*2. La couverture, recalculée par moi* (02/09 **15:07** Paris, snapshot du 02/09, fenêtre 28 j) :

| grade | pages | clics vus (qpd non brandé) | clics réels (path_daily) | global | médiane page |
|---|---|---|---|---|---|
| S | 3 | 302 | 1 064 | 28,4 % | 26,3 % |
| A | 6 | 124 | 623 | 19,9 % | 18,7 % |
| B | 38 | 264 | 1 600 | 16,5 % | **9,8 %** |
| C | 128 | 155 | 1 141 | 13,6 % | 0,0 % |

Ordres de grandeur du constat reproduits (S 28,4 vs 28,6 ; B médiane 9,8 vs 9,8).

*3. Le mécanisme, isolé page par page* (02/09 **15:07** Paris) — je recalcule `c1`, `c0` et le poids
logistique `w = 1/(1+exp(-((c1+c0)-20)/5))` du terme clics :

| page | c1 | c0 | poids du terme clics | clics réels 28 j | 28 j préc. | clics brandés révélés |
|---|---|---|---|---|---|---|
| …indemnisation-accident-moto-motard | 2 | 2 | **3,9 %** | 42 | 34 (+23,5 %) | 0 |
| …indemnisation-passager-accident-route | 1 | 1 | **2,7 %** | 30 | 48 (−37,5 %) | 0 |

Le momentum de ces deux pages est donc porté à ~96-97 % par `avg(position)` **non pondérée** sur la
traîne révélée. Fait établi.

*4. Le test décisif — que le constat n'a pas fait.* J'ai recalculé le momentum **avec la formule prod
exacte** mais alimentée par `gsc_path_daily` (clics complets, site-relatif comme le veut le design),
02/09 **15:27** Paris :

| page | grade | momentum prod (qpd) | momentum si path_daily | clics réels 28 j → | 28 j préc. |
|---|---|---|---|---|---|
| …la-préméditation-… | B | **1,31 (↗)** | **0,75 (↘)** | 47 | 119 (−60 %) |
| …indemnisation-accident-moto-motard | B | **0,79 (↘)** | **1,40 (↗)** | 42 | 34 (+24 %) |
| …indemnisation-passager-accident-route | B | 1,07 | 1,17 | 30 | 48 |

Et sur toute la population fiable (47 pages S/A/B du snapshot du 02/09, 02/09 **15:27** Paris) :
**15 pages sur 47 (31,9 %) ont un momentum dont la direction est INVERSE** de celle du momentum
recalculé sur les clics complets ; écart moyen |Δmm| = 0,214 sur un facteur borné à [0,71 ; 1,40],
écart max 0,69, `corr(mm_prod, mm_complet) = 0,338`.

*5. Le fait aval* — j'ai relu le texte émis, pas le résumé du constat (02/09 **15:20** Paris) :
alerte **id 131**, 01/09 20:15 Paris, `critical` : « Escalade … 1 page(s) fiable(s) en vrai decay …
`/post/indemnisation-accident-moto-motard` (66→49, zvΔ-1.6 momΔ-0.12) ». Cette page a bien gagné
**+24 % de clics organiques réels** entre les deux fenêtres.

**Écart au constat.**
- Le fond, les lignes de code, l'ordre de grandeur de la couverture et le cas moto : **exacts**.
- **Une faiblesse de raisonnement dans le constat** : il présente « clics réels en hausse de 21 % »
  comme preuve suffisante que le momentum ment. C'en est une pour la page moto, mais pas en général —
  le momentum est **site-relatif par construction** (`− ln((s1+50)/(s0+50))`), et les clics du site
  ont chuté (`s1/s0 = 0,560` sur `gsc_path_daily`, mes chiffres du 02/09 15:27, dont ~3 jours de lag
  GSC en fin de fenêtre courante) : une page qui perd 37 % pendant que le site perd 44 % **doit**
  avoir un momentum > 1. C'est le cas de la page « passager », que le constat range à tort parmi les
  preuves. La preuve solide est le contrefactuel à formule constante, que j'ai construit (point 4).
- **Le constat sous-estime le défaut** : il ne décrit que le faux **↘**. Le défaut est
  **bidirectionnel**, et le faux **↗** est pire parce qu'il n'alerte jamais : `/post/la-préméditation-…`
  a perdu **60 % de ses clics réels** (119 → 47) et le CPI la badge **↗ 1,31**. Sur 47 pages fiables,
  1 sur 3 est mal orientée.
- Chiffre à corriger : `corr(cpi, momentum)` = **0,496** sur le snapshot du 02/09 (175 pages), pas
  0,485 sur 177 — même conclusion.
- La part grade B des chutes (69/100) est **exacte** (vérifiée en partie f-02).

**Invariant.** Le plancher de couverture proposé **tient** et aurait attrapé les deux pages
(couverture 3-5 %), mais il est **incomplet sur deux points** : (i) il ne couvre pas le faux ↗, qui
ne passe par aucune alerte — il faut un test sur l'**accord de direction** entre `momentum` et un
momentum témoin recalculé sur `gsc_path_daily` (ma requête du point 4 est ce test, elle coûte une
seconde) ; (ii) la clause « refuser un `cpi_drop` dont les clics `gsc_path_daily` montent » est
correcte mais doit être formulée **en relatif au site**, sinon elle produira des faux négatifs les
mois où le site entier baisse. Le correctif de fond est ailleurs et il existe déjà dans la même
fonction : la CTE `cap` retire le brandé des totaux `gsc_path_daily` en utilisant la **fraction
brandée révélée par qpd** (`capb`) — appliquer ce même patron à `mom` rend le filtre brandé ET la
couverture complète, sans nouvelle source. Le constat ne le voit pas et propose seulement un
garde-fou.

---

```
ID        f-02
Verdict   CONFIRMÉ
```

**Ma preuve.**

*1. La règle, lue en prod* — `pg_get_functiondef('public.alert_rule_cpi_drop')`, 02/09 **15:08**
Paris. Le prédicat est mot pour mot :
`statut='present' AND fiable AND delta_cpi <= -15 AND coalesce(ecart_jours,99) <= 8
AND (coalesce(delta_momentum,0) <= -0.10 OR coalesce(delta_zc,0) <= -0.5)`, et le message émis dit
littéralement « en vrai decay sur ~7j (fenêtre ≤8j, **volatilité conversion exclue**) ».

*2. Bruit du Δmomentum à 7 j — mon recompute* (paires (page, jour) vs jour−7 dans `cpi_daily`,
01/08 → 02/09, grade S/A/B **aux deux dates**, 02/09 **15:09** Paris) :

```
1 394 paires / 53 pages · moyenne +0,017 · écart-type 0,197 · médiane 0,000 · p10 −0,210
310 paires (22,2 %) franchissent −0,10 ; 95 d'entre elles (30,6 %) ont un momentum courant ≥ 1,00
```

Le seuil −0,10 vaut donc **0,51 σ** du bruit à 7 j. Confirmé.

*3. Contrefactuel « `zv` gelé » avec la fonction prod* (`cpi_compose`, IMMUTABLE ; aucune écriture),
02/09 **15:09** Paris :

```
153 chutes ≤ −15 pts ; 100 passent le garde-fou (24 pages) ; 69 de ces 100 sont de grade B
chute moyenne des 100 : −24,9 pts → −17,2 pts si zv est gelé
38 des 100 (38,0 %) repassent au-dessus de −15 pts → n'existeraient pas sans mouvement de zv
27 des 100 portent sur une page dont le momentum courant est ≥ 1,00
les 53 chutes rejetées par le garde-fou : +2,8 pts en moyenne une fois zv gelé (le garde-fou filtre bien)
```

Tous les chiffres du constat reproduits à ±3 près (l'écart vient de ma fenêtre qui inclut le 02/09).

*4. `fiable` inclut B* — `pg_get_viewdef('public.cpi_movers')`, 02/09 15:08 Paris :
`COALESCE((n.grade = ANY (ARRAY['S','A','B'])) AND (p.grade = ANY (ARRAY['S','A','B'])), false)`.
Et `docs/cpi-cooked-page-index.md:74` (relu par moi) : « B = indicatif ». Confirmé.

**Écart au constat.**
- (a), (b), (d) : reproduits, **aucun écart de fond**.
- (c) **n'est plus reproductible et le résultat s'inverse aujourd'hui.** À 15:09 Paris, `cpi_movers`
  compare 02/09 vs 26/08 et contient 3 chutes ≥ 15 pts, dont **aucune ne passe le garde-fou**
  (Δmom +0,01 / +0,16 / 0,00 ; Δzc 0,0 / +0,2 / −0,1) — les trois sont portées par `zv`
  (Δzv −3,7 / −2,2 / −1,0) et sont **correctement rejetées**. Le garde-fou fait donc son travail sur
  la photo du jour ; l'observation (c) du constat portait sur l'appariement 01/09 vs 25/08. Cela ne
  réfute pas (b) — 38 % de fuite mesurés sur 153 chutes d'un mois — mais cela montre que le taux de
  faux positifs **varie fortement d'un jour à l'autre**, et qu'un instantané à 3 pages n'est pas une
  preuve. Le constat s'appuie sur (c) pour dramatiser ; seul (b) porte la démonstration.
- L'alerte du jour citée par le constat (id 134, 02/09 09:15) existe et son texte, que j'ai relu,
  liste bien préméditation (36→17) et passager-accident (84→66) : elle a été émise avant le snapshot
  du 02/09 13:00, sur l'appariement de la veille. Aucune contradiction, mais toute lecture de
  `cpi_movers` **change de sens dans la journée** (voir f-04).

**Invariant.** Les trois filets proposés **tiennent** et sont bien absents (j'ai vérifié :
`alert_rule_cpi_drop` ne lit que `cpi_movers`, et `cpi_movers` n'expose aucun clic). Réserve sur (1) :
faire porter le garde-fou sur le **niveau** du momentum ne vaut que si le momentum est juste — or
f-01 établit que sa direction est fausse sur 1 page fiable sur 3. Poser (1) avant de réparer f-01
**empire le diagnostic** : on filtrerait sur une grandeur mal orientée. Ordre correct : f-01 d'abord,
(2) et (3) tout de suite (ils ne dépendent pas du momentum), (1) après.

---

```
ID        f-03
Verdict   CONFIRMÉ
```

**Ma preuve** — requête sur `alerts`, `kind='cpi_drop'`, `created_at >= '2026-08-10'`, horodatages
convertis en Paris, 02/09 **15:10** Paris :

```
warn     : 23 épisodes / 23 jours distincts · 10/08 19:15 → 02/09 09:15 · 8 entre 00:00 et 06:00 · 23 non acquittés
critical :  9 épisodes /  9 jours distincts · 23/08 23:15 → 01/09 20:15 · 2 entre 00:00 et 06:00 ·  9 non acquittés
```

Liste complète des warns que j'ai extraite (02/09 **15:13** Paris) : 10/08 19:15 | 11/08 19:15 |
12/08 19:15 | 13/08 20:15 | 14/08 20:15 | 15/08 21:15 | 16/08 22:15 | 17/08 22:15 | 18/08 23:15 |
**[19/08 absent]** | 20/08 00:15 | 21/08 01:15 | 22/08 01:15 | 23/08 02:15 | 24/08 03:15 |
25/08 03:15 | 26/08 04:15 | 27/08 05:15 | 28/08 06:15 | 29/08 06:15 | 30/08 07:15 | 31/08 08:15 |
01/09 08:15 | 02/09 09:15. **Écart moyen entre deux warns = 24,64 h** (calculé par moi) — la dérive
de ~1 h/jour et le saut du 19/08 sont mécaniquement expliqués. Le corps prod de `raise_cooked_alert`
contient bien une occurrence d'un intervalle `24 hour` (test `pg_get_functiondef … LIKE '%24 hour%'`
= 1, même requête).

**Écart au constat.** Un seul, de dénominateur : le motif `cpi_drop` occupe aujourd'hui **32 des 51**
alertes non acquittées (et non 32/48 — la baseline Phase 0 a vieilli de 3 alertes). La part reste
~63 %. Je n'ai pas vérifié la réception ntfy (hors portée lecture prod), comme le constat l'annonce.

**Invariant.** L'empreinte de contenu **tient** et corrigerait le vrai défaut (répétition d'un motif
identique) ; le back-off et la fenêtre horaire **tiennent** aussi. Mais l'invariant est **mal placé
dans la hiérarchie** : la cause première de la saturation n'est pas la dédup, c'est qu'une règle
produit un positif quasi tous les jours (f-01/f-02). Une dédup par empreinte n'aurait rien changé ici
— les paths concernés **changent** d'un jour à l'autre, donc l'empreinte change et l'alerte
repartirait quand même. Sur ce point précis l'invariant proposé est **décoratif** ; c'est le back-off
sur « N épisodes consécutifs non acquittés » qui porterait l'effet.

---

```
ID        f-04
Verdict   PARTIEL
```

**Ma preuve.**

*1. Le code* — corps prod de `cooked_page_index` (02/09 15:06 Paris) : exactement **4** occurrences
de `now()`, toutes du côté Cooked (`firstpv`, `spv`, `pex`, `lcp`), contre `current_date` du côté GSC
(`fit`, `capq`, `capb`, `capp`, `mom`). Compté indépendamment sur le miroir :
`awk '/FUNCTION public.cooked_page_index/,/^\$function\$/' supabase/rpcs.sql | grep -c "now()"` = **4**.
La table est étiquetée par un simple `day date` (17 colonnes listées en f-05). Fait établi.

*2. Les heures d'exécution réelles* (`min(created_at)` par `day`, 02/09 **15:14** Paris) :
20→26/08 10:00 · **27/08 20:00** · 28/08 21:00 · 29/08 15:00 · 30/08 14:00 · 31/08 15:00 ·
01/09 14:00 · 02/09 13:00 (Paris).

*3. Les écarts* (33 paires de jours consécutifs, 31/07 → 02/09) : **min 18,0 h, max 34,0 h,
σ 2,12 h** ; `corr(écart_h, |Δcpi| moyen)` = **+0,457** ; `corr(écart_h, Δzv moyen)` = +0,214 ;
pic de |Δcpi| = **4,09 pts le 27/08**, avec **17 pages** dont `zv` bondit de ≥ 0,5.

*4. Le contrôle adverse que le constat n'a pas fait* (02/09 **15:20** Paris) — je retire les deux
jours de bascule d'horloge (27/08, 28/08) et je recalcule :

```
corr(écart_h, |Δcpi| moyen) : 0,457 sur 33 jours  →  0,139 sur 31 jours
σ de l'écart hors bascule : 1,16 h (au lieu de 2,12 h)
|Δcpi| moyen des 23 jours à ~24 h d'écart : 2,79 pts
```

**Écart au constat.** Le **défaut de code** (4 bornes `now()`, snapshot non reproductible pour un
`day` donné) et l'**amplitude** (18-34 h) sont confirmés au chiffre près. La **quantification de
l'impact est fausse** : la corrélation +0,468 annoncée (+0,457 chez moi) est portée par **2 points de
levier sur 33** ; une fois les deux jours de bascule retirés, elle tombe à **0,139**, c'est-à-dire
rien, et la dispersion résiduelle de l'écart n'est que de 1,16 h (±5 % d'une journée). Le titre du
constat — « cet écart d'horloge **explique une part mesurable du mouvement quotidien du score** » —
n'est donc **pas établi** : ce qui est établi, c'est qu'un **changement d'heure de cron** (+10 h d'un
coup) produit un jour de mouvement anormal. Le sous-jacent quotidien est du bruit d'horloge
négligeable devant le bruit du score (2,79 pts/jour en régime stable). La sévérité **P2 se justifie
par la non-reproductibilité**, pas par la contamination du mouvement quotidien.
Note complémentaire : le constat écrit « la paire du jour (01/09 14:00 vs 25/08 10:00) couvre 172 h » ;
à 15:14 Paris la paire courante est 02/09 13:00 vs 26/08 10:00, soit **171 h**. Détail, mais qui
illustre que ces chiffres bougent dans la journée.

**Invariant.** L'alignement des 4 bornes sur les bornes de jour Paris **tient**, et il est **moins
coûteux que le constat ne le suggère** : j'ai vérifié que `cooked_paris_ts_start` et
`cooked_paris_ts_end_exclusive` existent déjà (`supabase/rpcs.sql:1418` et `:1428`). En revanche le
second filet — « un test de contrat qui vérifie que `cooked_page_index` recalculée deux fois le même
jour civil rend le même score » — est **impraticable en l'état** : `cooked_page_index(28)` est
justement la fonction que la mission interdit d'appeler pour cause de durée (timeout constaté en
ad-hoc, cf. mémoire projet). Ce test ne peut pas vivre en CI ; il doit être un job planifié qui
compare deux exécutions, ou être remplacé par un test statique (« aucune borne `now()` dans le corps
de `cooked_page_index` »), qui lui est instantané et gratuit. Sous cette forme l'invariant tient ;
sous la forme proposée il est décoratif.

---

```
ID        f-05
Verdict   CONFIRMÉ
```

**Ma preuve** (une seule requête, 02/09 **15:20** Paris) :

*(a)* `information_schema.columns` sur `cpi_daily` → 17 colonnes :
`day, path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org,
couv_gsc_pct, created_at, convertit`. Nombre de colonnes matchant `version|def_hash|revision` :
**0**. Confirmé.

*(b)* `annotations` → **7 lignes**, que j'ai lues :
02/07/2026 [site_change] « Refonte complète de l'article (contenu, structure) » ·
12/07/2026 [autre] « Restatement CPI (soir) : conversion recousue via identity_stitch… » ·
13/07/2026 [site_change] suppression d'une ressource · 13/07/2026 [autre] surveillance maturation SEO ·
25/07/2026 [site_change] « Finitions audit 26/07 : Baidu centralisé… » ·
27/07/2026 [site_change] « Restatement CPI — classify_channel v3… » ·
23/08/2026 [autre] backfill de 22 `form_submit`.
→ **aucune ligne pour le restatement CPI du 02/07**, **aucune pour la redéfinition du 25/07**.
Confirmé.

*(c)* Relu par moi : `docs/cpi-cooked-page-index.md:163-165` — « Trois corrections de mesure ont
restaté le snapshot du jour. **Comparer un CPI d'avant/après ces dates revient à comparer deux
définitions** … Annotations posées dans la table `annotations`. » suivi de la liste 02/07 / 12/07 /
27/07 (`:167` et suivantes). L'affirmation est **fausse pour le 02/07**. Confirmé.

*(d)* La rupture du 25/07 est double et je l'ai vérifiée aux deux endroits : source du momentum
(`20260725220200:89-96`, cf. f-01) **et** `convertit` = `coalesce(cv.val, 0) > 0` dans le corps prod
(fin de la CTE `scored`). Confirmé.

*(e)* `SELECT count(*) FROM pg_tables WHERE tablename LIKE 'cpi_pre_restatement%'` → **0**, alors que
`docs/cpi-cooked-page-index.md:190-191` écrit encore « Tables d'audit : `cpi_pre_restatement_20260712`
(à supprimer ~19/07/2026), `cpi_pre_restatement_20260727` (à supprimer ~03/08/2026) ». Confirmé — et
`docs/ROADMAP.md` ligne 2 acte pourtant la suppression au 10/08/2026 : les deux documents se
contredisent.

**Écart au constat.** Aucun sur le fond. Deux détails de numérotation : la citation (c) est aux
lignes **163-165** (pas 165-168) et (e) aux lignes **190-191** (pas 191-192) de mon exemplaire à
HEAD `e95f3ee`. Nuance de formulation : la phrase de (e) est rédigée comme une **consigne de purge à
venir** (« à supprimer ~19/07 »), pas comme une affirmation d'existence — c'est de la doc périmée,
pas une fausse affirmation, ce qui est un cran moins grave que (c).

**Invariant.** `cpi_version`/`def_hash` **tient** : c'est le seul filet qui rendrait la série
auto-descriptive, et il est de coût nul (une colonne alimentée par le snapshot). Le gate CI proposé
**tient partiellement** : refuser une migration qui redéfinit `cooked_page_index`/`cpi_compose` sans
bump de version est vérifiable mécaniquement ; exiger « une ligne d'annotation » ne l'est pas depuis
la CI (la CI ne voit pas la prod, et poser la ligne est un acte d'exécution, pas de merge). La partie
« annotation » doit donc être une étape de la procédure de déploiement, pas un gate — sinon elle sera
contournée comme l'a été le 25/07. J'ai vérifié que `scripts/check_rpcs_sql_fresh.py` existe et ne
porte que sur la fraîcheur du miroir : le constat dit vrai.

---

```
ID        f-06
Verdict   CONFIRMÉ
```

**Ma preuve** — grep ciblé sur mon exemplaire à HEAD `e95f3ee` (02/09 **15:07** Paris) :

```
docs/cpi-modele-mathematique.md:383 :  FROM gsc_path_daily gpd WHERE day>current_date-2*p_days GROUP BY gpd.path),
docs/cpi-modele-mathematique.md:400 :  CASE WHEN x.n_org>=100 … THEN 'A' WHEN x.n_org>=30 … THEN 'B' ELSE 'C' END grade
docs/cpi-modele-mathematique.md:314/318/320 :  query !~* 'plouton'  /  g.query !~* 'plouton'  /  query ~* 'plouton'
```

Face à quoi le corps prod (02/09 15:06 Paris) porte `FROM public.gsc_query_page_daily g … AND NOT
public.gsc_is_branded(g.query)` pour `mom`, la grille **S/A/B/C** (`n_org>=200 AND e>=40 → 'S'` en
tête), et `gsc_is_branded` partout. `docs/cpi-cooked-page-index.md:74`, relu : « S = très fiable
(n_org≥200, E≥40) · A … · B = indicatif · C = insuffisant ».

`git log --date=short --since=2026-07-20 -- docs/cpi-modele-mathematique.md docs/cpi-cooked-page-index.md`
(exécuté par moi) → **2026-07-28 `4085647`** et **2026-07-24 `4e65818`**, rien après. La migration qui
a changé la source du momentum est du **25/07** : la doc a bien été touchée **3 jours après** sans que
l'annexe soit reprise.

**Écart au constat.** Le numéro de ligne de la CTE `mom` : elle commence à **:379** et le `FROM`
fautif est à **:383** (le constat annonce « :378-383 », donc juste). Rien d'autre. Le lien de
causalité avancé (« c'est le mécanisme par lequel f-01 est resté invisible 39 jours ») est une
hypothèse plausible mais **non démontrée** — le constat ne produit aucune trace d'un lecteur trompé ;
je ne peux ni la confirmer ni l'infirmer. Le fait matériel (spec ≠ prod sur 3 points) est, lui, établi.

**Invariant.** La seconde branche — **supprimer l'annexe SQL et pointer `supabase/rpcs.sql`** —
**tient** et est nettement supérieure : j'ai vérifié que `scripts/check_rpcs_sql_fresh.py` ne
contient aucune référence à `docs/cpi-modele-mathematique.md` ni au mot « annexe », et étendre un gate
de fraîcheur à un bloc de code recopié dans un `.md` suppose de le régénérer automatiquement — soit
exactement le mécanisme qui a déjà échoué. Une copie sous gate vaut mieux que deux. La première
branche est réalisable mais fragile.

---

```
ID        f-07
Verdict   CONFIRMÉ
```

**Ma preuve.**

*1. Les deux corps, lus en prod* (02/09 **15:08** Paris).
`pg_get_viewdef('public.cpi_opportunite_contact')` :
`round(cpi_compose(zc, zr, zl, 0::numeric, momentum, gate, true))::integer AS potentiel` — `momentum`
et `gate` sont bien passés.
`pg_get_functiondef('public.cpi_compose')` : la fonction se termine par `))) * mm * gg;` **en dehors**
du `CASE`, donc dans les deux branches, `exclude_conversion` comprise. Confirmé.
Poids de la branche `exclude_conversion` : `0.46*zc + 0.23*zr + (0.20/0.65)*zl` — j'ai refait la
division : 0,30/0,65 = 0,4615 ; 0,15/0,65 = 0,2308 ; 0,20/0,65 = 0,3077. La renormalisation est
**correcte**, comme le dit le constat.

*2. La doc* — `docs/cpi-cooked-page-index.md:57-59`, relu : « sépare le *potentiel* (capture +
rétention + lecture, renormalisés hors conversion) du badge *conversion réalisée* ». Aucun facteur
conjoncturel mentionné. Le `COMMENT` de la vue (02/09 15:08 Paris) ne parle que de `convertit`.

*3. Mon chiffrage** sur le snapshot du **02/09** (périmètre documenté : `grade IN ('S','A','B') AND
NOT convertit`, `ORDER BY potentiel DESC`), 02/09 **15:09** Paris :

```
16 pages · écart |potentiel publié − potentiel structurel (mm=1, gg=1)| : moyenne 11,6 pts, max 20 pts
corrélation des rangs 0,732 · 7 pages sur 16 déplacées de ≥ 3 rangs · momentum de 0,71 à 1,40
```

**Écart au constat.** Aucun sur le fond ; les chiffres sont ceux du jour (16 pages / 11,6 / 20 /
0,732 / 7-sur-16 chez moi contre 14 / 12,6 / 22 / 0,820 / 5-sur-14 la veille). L'effet est donc
**stable et plutôt plus fort** aujourd'hui : près d'une page sur deux du classement de pilotage est
déplacée de ≥ 3 rangs par un facteur que la doc ne mentionne pas. Je n'ai pas vérifié la
sous-affirmation « 1 page entre dans le top 5 uniquement par son momentum » (non recoupée, sans
incidence sur le verdict).

**Invariant.** Le test de contrat `potentiel = cpi_compose(zc,zr,zl,0,1,1,true)` **tient** : il est
exact, instantané, sans appel à la fonction lourde, et il aurait été rouge dès le premier jour.
C'est le meilleur invariant du lot. Réserve utile : tant que f-01 n'est pas corrigé, retirer `mm` du
potentiel **améliore doublement** le livrable (on retire un facteur hors-doc **et** un facteur mal
orienté sur 1 page sur 3).

---

```
ID        f-08
Verdict   CONFIRMÉ
```

**Ma preuve.**

*1. Le harnais, relu* : `scripts/cpi_validation_j28.sql:347` — « §3 — CALIBRATION DE LA COURBE CTR
(exécutable à tout moment ; **check mensuel**) » ; `:376-380` — « CRITÈRE LIANT : r2_global ≥ 0,85
(réf. 10/06/2026 : 0,917 ; auj. 0,930) » et « SUIVI (non liant, T-07) : médiane |ecart_pct| …
(auj. **20,1 %**, 10/06 : 24 %) ». Le §3 est bien un `SELECT` pur (90 j, agrégé sur 20 buckets).

*2. Mon ré-exécution en lecture*, 02/09 **15:08** Paris, dans les deux variantes de filtre brandé :

| variante | R² | pente | buckets | médiane abs(écart) | CTR prédit pos. 1 |
|---|---|---|---|---|---|
| harnais (`query !~* 'plouton'`) | **0,910** | −1,254 | 20 | **27,4 %** | 8,12 % |
| prod (`NOT gsc_is_branded(query)`) | **0,910** | −1,254 | 20 | **27,4 %** | 8,12 % |

Critère liant : **PASSE** (0,910 ≥ 0,85). Indicateur de suivi : **20,1 % (11/07) → 27,4 %
(02/09)**, soit **+36 % en relatif**, jamais relevé.

*3. Le retard* : `docs/ROADMAP.md`, ligne 3 du tableau, relue par moi — « Re-test diagnostic CPI 56 j
| **05/08/2026** | … **Pas encore lancé.** » → **28 jours de retard** au 02/09/2026.
`git log -- scripts/cpi_validation_j28.sql` (exécuté par moi) : dernier commit **13/07/2026**
(`8d44fc1`), rien depuis.

*4. L'aval* : `cpi_capture_perdue` publie aujourd'hui (02/09 **15:20** Paris) **1 170 clics perdus
sur 30 pages**, dont **1 032 sur les 16 pages `interpretable`**.

**Écart au constat.** Un seul, mineur et de convention de calcul : ma médiane est **27,4 %**, celle du
constat 28,8 %. L'explication est dans le harnais lui-même (`:371-373`) : il arrondit `ecart_pct` à
l'entier **par bucket** avant lecture, alors que j'ai pris la médiane des écarts continus. Même
verdict, même ordre de grandeur, conclusion identique : **le critère liant passe, l'indicateur de
suivi a dérivé d'un tiers sans que personne ne l'ait vu**. Chiffres du jour pour `cpi_capture_perdue`
(1 170 / 30 / 1 032 / 16) au lieu de ceux de la veille (1 185 / 29 / 1 035 / 15).

**Invariant.** Il **tient**, et j'ai vérifié le point sur lequel il repose : `freshness_contract`
contient bien **13 lignes** (02/09 **15:28** Paris) — `cpi_daily`, `crm_prospects`, `cta_phone_click`,
`dashboard_resources_snapshot`, `dfs_keyword_volume`, `form_submit`, `gbp_daily`, `gsc_path_daily`,
`gsc_query_daily`, `gsc_query_page_daily`, `math_visit_sequences_snapshot`, `secib_dossiers`,
`seo_url_snapshot` — **aucune n'est la calibration CTR** (la seule ligne matchant « cpi » surveille la
fraîcheur du snapshot `cpi_daily`, pas la calibration). Le registre existe donc déjà et l'ajout est du
même patron que les 13 autres : l'invariant est réaliste, pas décoratif. Une réserve : le registre
surveille des **fraîcheurs** (`max(day)`), pas des **valeurs** ; y loger le R² et la médiane suppose
soit une table dédiée dont on surveille la fraîcheur, soit une extension du registre. À dire
explicitement au moment de l'implémenter.

---

```
ID        o-11 (zone f)
Verdict   CONFIRMÉ
```

**Ma preuve** — même lecture de `annotations` que f-05(b), 02/09 **15:20** Paris : **7 lignes**, dont
le contenu intégral est reproduit plus haut. Aucune ne porte sur :
- le **restatement CPI du 02/07** (grain lectures) — la seule ligne du 02/07 est un `site_change`
  « Refonte complète de l'article (contenu, structure) » sur 1 path ;
- `classify_channel` **v2 (détection IA par utm_source)** du 02/07 — aucune occurrence ;
- la synchro `page_taxonomy` du **31/08** (+12 articles, migration `20260831090540` citée dans
  `CLAUDE.md`) — la ligne la plus récente de la table est du **23/08** (backfill de `form_submit`).

En face, `docs/cpi-cooked-page-index.md:165` affirme « Annotations posées dans la table
`annotations` » pour les trois restatements CPI listés. Faux pour le 02/07 (vrai pour 12/07 et 27/07,
que j'ai retrouvés dans la table).

**Écart au constat.** Aucun sur les faits. Une nuance de qualification : les trois éléments ne sont
pas de même nature. Le CPI 02/07 et `classify_channel` v2 sont de vrais **restatements** (la donnée
passée change de sens). La synchro `page_taxonomy` du 31/08 **n'a pas restaté de série** : elle a
ajouté des lignes de taxonomie pour 12 articles jusque-là absents — ce qui **change la composition
des agrégats par catégorie** (`content_performance`, onglet Articles Ressources) sans modifier
aucune valeur historique. C'est une rupture de **périmètre**, pas de **définition**. La ranger sous
le même label affaiblit le constat ; les deux méritent une annotation, pour des raisons différentes.
Sévérité P3 : correcte.

**Invariant.** Tel qu'écrit — « test CI sur le **nom** de migration » — il est **décoratif**, et le
projet en a déjà la preuve : la rupture du 25/07 (f-05) est arrivée par une migration nommée
`audit_cpi_corrections`, qui ne contient pas le mot « restatement » et serait passée à travers le
filet. Un gate sur un nom de fichier est contournable par inadvertance. L'invariant utile est celui
de f-05 : **bump de `cpi_version` obligatoire dès que `cooked_page_index` ou `cpi_compose` est
redéfinie** (détectable mécaniquement dans le diff, pas dans le nom), la ligne `annotations` étant
alors une étape de la procédure de déploiement. À fusionner avec f-05 plutôt qu'à instruire à part.

---

# PARTIE 3 — CE QUE JE N'AI PAS PU TESTER

| Point | Raison |
|---|---|
| f-03 — réception effective des pushes ntfy | Non observable depuis la prod ; le constat l'annonçait déjà comme non recoupé. Je confirme les épisodes et leurs horodatages, pas leur arrivée sur le téléphone. |
| f-01 — exhaustivité de l'absence de clics brandés sur la page moto | `gsc_path_daily` n'a pas de colonne `query` : 0 clic brandé **révélé** ne prouve pas 0 clic brandé réel. Même réserve que le constat. Sans incidence : le contrefactuel de mon point 4 n'en dépend pas. |
| f-04 — reproductibilité effective de `cooked_page_index` | Vérifier « deux exécutions le même jour donnent le même score » exigerait d'appeler `cooked_page_index(28)`, explicitement interdit (durée). Établi par le code seul. |
| f-06 — « c'est ainsi que f-01 est resté invisible 39 jours » | Affirmation causale sur le comportement de lecteurs passés, non vérifiable dans le repo ni en prod. |
| f-07 — « 1 page entre dans le top 5 uniquement par son momentum » | Non recoupé (aurait exigé d'exposer des paths de pilotage ligne à ligne ; l'agrégat suffit au verdict). |
| f-02 (c) / f-01 — alerte « id 130 » | J'ai lu les alertes **131** (01/09 20:15, critical, page moto) et **134** (02/09 09:15, warn, 3 pages) ; je n'ai pas ouvert l'id 130 individuellement. La substance est établie par 131 et 134. |

