# Réfutation zone (c) — identité, sessions, attribution
Mission Cooked du 02/09/2026 — Phase 1, passe de réfutation fail-closed, LECTURE SEULE.
Prod `mxycmjkeotrycyneacje` ; repo local HEAD = main e95f3ee.
Toutes mes requêtes ont tourné entre **02/09/2026 15:03 et 15:15 (Paris)**.
Constats reçus : **8** — recopiés : **8**.

---

## 1. Recopie intégrale des 8 constats reçus

```
ID            c-01
Titre         seo_to_contact_funnel divise toujours un numérateur recousu par un dénominateur
              en session brute, sur trois fenêtres différentes — non corrigé depuis le 25/07
Sévérité      P1
Preuve        pg_get_functiondef('public.seo_to_contact_funnel(integer)') — prod, 02/09/2026 09:56 :
                • dénominateur `entries` : `select distinct on (e.session_id) … from events_human
                  where name='pageview' and occurred_at > now() - make_interval(days => days_back)`
                  → grain SESSION BRUTE, aucun `identity_stitch`, fenêtre glissante UTC.
                • numérateur `conv`  : `from public.conversion_journeys(days_back)`
                  → grain VISITEUR RECOUSU (v2 du 12/07, migration 20260712203935).
                • fenêtre GSC `gsc` / `topq` : `where g.day > current_date - days_back`
                  → `current_date` = date SERVEUR (UTC), borne stricte `>` = 27 jours,
                  et aucun alignement sur `gsc_last_data_day()` (= 29/08/2026, J-4).
              Constat identique documenté : docs/audit-architecture-2026-07-25.md:139
              et :203 (« Majeur | seo_to_contact_funnel divise un numérateur recousu par un
              dénominateur en session brute, sur 3 fenêtres différentes … contact_rate_pct
              structurellement écrasé »).
Impact        `contact_rate_pct` (colonne de sortie de la RPC) est structurellement sous-estimé :
              le dénominateur compte les visites coupées plusieurs fois, le numérateur une seule.
              Ordre de grandeur de l'effet de couture sur la fenêtre courante : sur 122
              `cta_phone_click` (28 j), 64 (52 %) proviennent de visiteurs recousus à ≥ 2 sessions
              (requête « taille_composante » ci-dessous) — le dénominateur, lui, ne recoud rien.
              S'y ajoute un décalage de fenêtre : les 4 derniers jours (30/08 → 02/09) ont des
              entrées Cooked mais zéro impression GSC, ce qui gonfle encore le dénominateur du
              ratio impressions→contacts.
Récidive      OUI. Signalé le 25/07/2026 (audit architecture, rang « Majeur », cause racine R3
              « une notion métier, plusieurs implémentations, aucun test d'équivalence »).
              Absent du plan de correction exécuté (docs/plan-correction-audit-2026-07-02.md
              couvre l'audit du 02/07, pas celui du 25/07). 39 jours sans correction.
Invariant     Un test SQL de CI qui compare, sur la même fenêtre, `count(distinct session_id)`
              et `count(distinct visitor_key)` des entrées organiques et échoue si une RPC
              publie un ratio dont numérateur et dénominateur n'ont pas le même grain ;
              + interdiction de `current_date` dans `supabase/migrations/*.sql`
              (grep de CI, au même titre que la règle `occurred_at::date`).
Statut        [non recoupé]
```

```
ID            c-02
Titre         La couture d'identité n'a ni horodatage ni alerte de fraîcheur : si le cron 03:40
              meurt, tout le système retombe en silence au comportement d'avant le 12/07
Sévérité      P1
Preuve        pg_get_functiondef('public.refresh_identity_stitch(integer)') — prod, 02/09 09:54 :
              la fonction fait `DELETE FROM identity_stitch;` puis `INSERT … SELECT`.
              information_schema : `identity_stitch(kind text, key text, visitor_key text)`
              — **aucune colonne de date**. Le registre `freshness_contract` ne peut donc pas
              la couvrir (13 sources inscrites, `identity_stitch` absente — baseline §2.4).
              Les trois consommateurs dégradent en silence :
                • assisted_contacts_by_entry_path : `COALESCE(st.visitor_key,'sid:'||e.session_id)`
                • conversion_journeys            : `coalesce(ss.visitor_key, sa.visitor_key,
                                                    'sid:'||coalesce(c.session_id,…))`
              → pas d'erreur, pas de NULL, juste des chiffres qui redeviennent faux.
              Cron : `SELECT jobname, schedule, active FROM cron.job` → `refresh-identity-stitch`,
              `40 3 * * *`, actif, dernier succès **02/09/2026 05:40 Paris**. La seule règle qui
              le surveille est `alert_rule_cron_failed` (échec du dernier run, 7 j) : un job
              *désactivé* ou *supprimé* ne déclenche rien.
Impact        Le correctif du 12/07/2026 corrigeait ~22 % de sessions coupées et ~95 % des
              `cta_phone_click` sans amont visible. Sa perte est indétectable par les réflexes
              de démarrage de session (`alerts`, `refresh_pipeline_health()`, `gsc_last_data_day()`)
              — aucun des trois ne regarde la couture.
              Effet de bord mesuré, même cause (réécriture intégrale quotidienne) :
              `pg_relation_size('identity_stitch')` = **24 Mo** de heap (204 o/ligne, ~94 o utiles)
              mais `pg_indexes_size` = **124 Mo** pour 122 133 lignes, soit ~1 016 o d'index par
              ligne sur deux btree de clés courtes → ~110 Mo de gonflement d'index jamais
              récupéré (0 tuple mort, 41 autovacuum, aucun VACUUM manuel). 4e objet de la base
              (2 379 Mo), sur une instance dont le disque a saturé le 24/07.
Récidive      Le mode de défaillance « panne silencieuse d'un pipeline » est le thème du
              programme résilience 1→3→2 (chantier 1 livré le 23/08 : registre
              `freshness_contract`, ADR-0002). La couture n'y a pas été inscrite — précisément
              parce que la table n'a pas de colonne de date.
Invariant     Ajouter `refreshed_at timestamptz` (ou une ligne dans `freshness_contract` alimentée
              par le cron) et une règle `alert_rule_freshness` sur `identity_stitch` avec un seuil
              de 30 h ; plus un contrat de non-régression : « % de sessions J-1 présentes dans
              identity_stitch = 100 % » testé par `run_rpc_contract_tests`.
Statut        [non recoupé]
```

```
ID            c-03
Titre         Le compte « contacts assistés » perd 12 contacts macro sur 183 (6,6 %) sans aucun
              bucket de réconciliation — et le bucket `(non rattaché)` prévu est du code mort
Sévérité      P1
Preuve        Requête (prod, 02/09/2026 09:53 Paris) :
                SELECT (SELECT sum(contacts) FROM assisted_contacts_by_entry_path(
                          paris_today()-27, paris_today()))                       AS assisted,
                       (… WHERE entry_path='(non rattaché)')                      AS non_rattache,
                       count phone / form macro / form macro AVEC cooked_sid|aid  FROM events_human;
              → assisted_total_28j = **171**, non_rattache = **NULL (0 ligne)**,
                phone_28j = 122, form_macro_28j = 61, form_macro_avec_id_28j = **49**.
              Total site sur la même fenêtre : `macro_contacts_by_path(28)` = **183** = 122 + 61.
              171 = 122 + 49 **exactement** → les 12 contacts manquants sont les formulaires macro
              sans `cooked_sid` ni `cooked_aid`, écartés par la clause
              `AND COALESCE(e.props->>'cooked_sid', e.props->>'cooked_aid') IS NOT NULL`
              (pg_get_functiondef, prod 02/09 09:52).
              Le bucket de secours est inatteignable : `_ce` est construit par
              `FROM _ct c JOIN LATERAL (… LIMIT 1) lp ON true LEFT JOIN _ventry v` — le
              `JOIN LATERAL` est un INNER JOIN (un contact sans pageview recousue dans les 6 h
              est **supprimé**, pas bucketé), et `_ventry` couvre par construction tous les
              couples (vk, visit_n) de `_pvseg`, donc `v.entry_path` n'est jamais NULL et le
              `COALESCE(v.entry_path,'(non rattaché)')` ne s'exécute jamais. Vérifié : 0 ligne.
Impact        La colonne « contacts assistés » du dashboard et la ligne objectif trimestre
              rapportent 171 là où le site en compte 183 : **−6,6 %**, sans ligne de
              réconciliation ni message. À comparer avec `macro_contacts_by_path`, qui expose
              lui un bucket `(non rattaché)` peuplé (6 formulaires à `path` NULL) — deux
              conventions opposées pour la même famille de chiffres.
              Le risque structurel est plus large que la mesure : le jour où un contact n'a plus
              de pageview recousue dans les 6 h (couture morte — cf. c-02, ou visite > 6 h avant
              l'appel), il disparaît du total sans laisser de trace. Aujourd'hui : 0 cas.
Récidive      Partielle. L'audit du 25/07 (:139) relevait la variante symétrique
              (« macro_contacts_by_path exige path IS NOT NULL et site_macro_counts non,
              15 formulaires, 10 % ») : **celle-là est corrigée** (bucket `(non rattaché)`,
              écart Σ pages vs site = 0). La même classe de défaut a survécu sur la voie
              « assistés », qui n'avait pas été mesurée.
Invariant     Contrat testé en CI : `Σ assisted_contacts_by_entry_path(w) + contacts_exclus
              = site_macro_counts(w)` avec `contacts_exclus` publié comme une ligne
              `(non attribuable)` de la RPC, et transformation du `JOIN LATERAL … ON true`
              en `LEFT JOIN LATERAL` pour que le bucket devienne réellement atteignable.
Statut        [non recoupé]
```

```
ID            c-04
Titre         Le grain d'identité change au milieu du jour en cours : 54,3 % des sessions
              d'aujourd'hui sont hors couture à 10 h, mais 0 % de celles de J-1
Sévérité      P1
Preuve        Requête (prod, 02/09/2026 09:57 Paris ; lecture de `events` brut assumée —
              diagnostic de topologie d'identité, pas un chiffre business) :
                sessions distinctes par jour Paris (5 j) ⋈ identity_stitch(kind='sid') :
                28/08 : 311 sessions, 0 hors couture (0,0 %)
                29/08 : 401,  0 (0,0 %)
                30/08 : 388,  0 (0,0 %)
                31/08 : 561,  0 (0,0 %)
                01/09 : 508,  0 (0,0 %)
                **02/09 : 138 sessions, 75 hors couture (54,3 %)**
              Cause : `refresh-identity-stitch` tourne à `40 3 * * *` UTC = 05:40 Paris ;
              toute session postérieure attend le lendemain.
              Les consommateurs retombent alors sur `'sid:'||session_id` (cf. c-02).
Impact        Tout chiffre qui inclut le jour en cours mélange deux grains dans un même total :
                • `cooked_period_bounds(…, 'live')` → `n_end = paris_today()` (vérifié :
                  rolling_28/live = 06/08 → 02/09) ;
                • `dashboard_assisted_quarter()` → `q_end := public.paris_today()` (corps prod) ;
                • `macro_contacts_by_path(28)` → `paris_today()-27 → paris_today()`.
              Conséquence : sur la journée en cours, les revenants sont sous-comptés et la page
              d'entrée attribuée est celle de la session brute, pas de la visite recousue —
              exactement le biais que la couture du 12/07 corrige pour tous les autres jours.
              Le dashboard est partiellement protégé (lens `live_j1`, fin J-1) ; `site_kpis_compare`
              et le compteur d'objectif trimestriel ne le sont pas.
Récidive      Nouvelle formulation d'un défaut de la même famille que
              project_dashboard_currentday_bot_race (faux pic « jour en cours ») : le jour en
              cours n'a pas les mêmes propriétés que les autres et n'est jamais traité comme tel.
Invariant     Soit exclure J du calcul (`live_j1` partout où un grain recousu est requis), soit
              exposer dans la sortie un drapeau `grain_partiel_jour_courant`. Test de CI :
              `assisted_contacts_by_entry_path(J, J)` ne doit pas être publiée sans mention.
Statut        [non recoupé]
```

```
ID            c-05
Titre         Trois définitions de « 28 jours » cohabitent pour le même chiffre de contacts
              (183 / 192 / 196) ; conversion_journeys et form_submits_attributed utilisent une
              fenêtre `now()` glissante, contre la règle dure « fenêtre Paris » de CLAUDE.md
Sévérité      P2
Preuve        Requête unique (prod, 02/09/2026 09:53 Paris) :
                macro_contacts_by_path(28)                              = **183**
                macro_contacts_by_path(paris_today()-27, paris_today()) = **183**
                macro_contacts_by_path(paris_today()-28, paris_today()) = **196**
                site_macro_counts(paris_today()-27, paris_today())      = **183**
                site_macro_counts(paris_today()-28, paris_today())      = **196**
                conversion_journeys(28)                                 = **192**
                events_human macro sur `occurred_at > now()-28 days`    = **192**
                contacts macro du jour J-28 (06/08 exclu du 28 j)       = **13**
              Corps prod : `conversion_journeys` et `form_submits_attributed` filtrent par
              `e.occurred_at > now() - make_interval(days => days_back)` — fenêtre glissante
              ancrée sur l'heure d'exécution ; `macro_contacts_by_path` / `site_macro_counts`
              filtrent par `public.paris_date(e.occurred_at)` — jours calendaires Paris.
              `cooked_period_bounds('rolling_28', 'live')` = 06/08 → 02/09 = **28 jours**,
              cohérent avec `macro_contacts_by_path(28)`.
Impact        `conversion_journeys(28)` (192) dépasse `macro_contacts_by_path(28)` (183) de
              **9 contacts (+4,9 %)**, et l'écart **varie avec l'heure à laquelle on interroge**
              (à minuit il tend vers 0, à 23 h vers un jour entier ≈ 6-7 contacts). Deux réponses
              données le même jour à quelques heures d'intervalle ne sont pas reproductibles.
              `seo_to_contact_funnel` hérite du problème : son numérateur (conversion_journeys)
              et son dénominateur (`entries`, aussi en `now()`) sont sur la fenêtre glissante,
              mais sa brique GSC est en `current_date` UTC (cf. c-01).
              **Correction à la baseline** : la baseline (§2.2, Q-20) conclut que
              « `macro_contacts_by_path(28)` (overload days_back, fenêtre 28 j au lieu de 29)
              = 182 : les deux overloads n'ont pas la même fenêtre ». C'est inexact — les deux
              overloads sont **identiques** (183 = 183 sur la fenêtre J-27→J, l'overload entier
              n'étant qu'un `SELECT` de l'overload date). L'écart 182/195 venait de la fenêtre
              **29 jours** écrite à la main dans la requête Q-20, pas d'une divergence en prod.
Récidive      Même cause racine R3 que c-01 (audit 25/07, :128-143) : plusieurs implémentations
              d'une notion, aucun test d'équivalence.
Invariant     Faire passer `conversion_journeys` / `form_submits_attributed` /
              `seo_to_contact_funnel` par `cooked_period_bounds` (comme les 8 autres appelants
              de `macro_contacts_by_path`), et un test de CI qui échoue si deux RPC publiées
              renvoient des totaux de contacts macro différents pour la même étiquette de période.
Statut        [non recoupé]
```

```
ID            c-06
Titre         classify_channel ignore le prédicat anti-spam : 94 % du canal `referral` est du
              trafic Baidu connu comme spam (13,9 % de tous les pageviews de events_human)
Sévérité      P2
Preuve        Requête (prod, 02/09/2026 09:59 Paris), pageviews `events_human`,
              fenêtre J-27 → J = 06/08 → 02/09 :
                total pageviews                    13 369
                canal referral                      1 984
                dont `m.baidu.com`                  **1 864** (1 864 sessions distinctes)
                referral hors Baidu                   120
                organic_google 5 859 · paid 1 884 · direct 1 362 · social 362 · organic_other 287
                · gmb 187 · organic_ai 77 · NULL (referrer interne) 1 367
              `pg_get_functiondef('public.classify_channel(text,text,text,text)')` : aucune
              référence à `cooked_is_spam_referrer`. La vue `events_human` ne filtre pas Baidu
              non plus (les 1 864 sessions y sont bien présentes).
Impact        Toute ventilation par canal qui n'appelle pas explicitement
              `cooked_is_spam_referrer` présente 1 984 pageviews de « referral » dont seulement
              120 sont réels : le canal est **faux d'un facteur 16,5**. Le dénominateur
              « sessions » du site est gonflé de 1 864 sessions sur 28 j.
              `seo_to_contact_funnel.entries` ne filtre pas le spam (le canal Baidu étant
              `referral`, son `organic_entries` n'est pas touché, mais toute évolution du
              classement le contaminerait).
              Écarts de taxonomie mineurs, mesurés sur la même fenêtre : `utm_source` est testé
              en **égalité exacte** (`lower(utm_source) in ('chatgpt.com','openai',…)`) alors que
              le referrer est testé en `ilike '%…%'` → `utm_source='copilot.com'` tombe en
              `referral` (1 pv) ; `kagi.com` (1), `yandex.ru` (2), `youcare.world` (1),
              `search.ccleanerbrowser.com` (2) → `referral` au lieu de `organic_other` ;
              `lnkd.in` (3), `go.bsky.app` (1) → `referral` au lieu de `social`. Total ≤ 11 pv.
Récidive      OUI, partielle. Le filtre Baidu a été « centralisé » le 25/07 (annotation posée,
              helper `cooked_is_spam_referrer`), mais la baseline relève encore **3 copies
              littérales** `referrer_hostname IS DISTINCT FROM 'm.baidu.com'`
              (rpcs.sql:1765, :3779, :3985) et le classificateur de canal reste aveugle.
              Le sujet est documenté depuis reference_baidu_referral_spam.md.
Invariant     Faire de `classify_channel` le point unique : renvoyer `'spam'` quand
              `cooked_is_spam_referrer(ref)` est vrai, et un test de CI qui échoue si
              `count(*) FROM events_human WHERE classify_channel(...)='referral'
              AND cooked_is_spam_referrer(referrer_hostname)` > 0.
Statut        [non recoupé]
```

```
ID            c-07
Titre         La normalisation téléphone casse sur le format français le plus courant
              `+33 (0)6 …` ; le miroir Python est strictement identique, donc les deux côtés
              partagent le défaut
Sévérité      P2
Preuve        Requête de test avec **valeurs fictives uniquement** (prod, 02/09/2026 10:05 Paris) :
                '06 12 34 56 78'          → +33612345678   ✅
                '+33 6 12 34 56 78'       → +33612345678   ✅
                '00 33 6 12 34 56 78'     → +33612345678   ✅
                '+590 690 12 34 56'       → +590690123456  ✅ (DOM-TOM)
                '+262 692 12 34 56'       → +262692123456  ✅
                espace insécable U+00A0 et espace fine U+202F → correctement supprimés ✅
                **'+33 (0)6 12 34 56 78'  → +330612345678  ❌** (attendu +33612345678)
                **'0033 (0)6 12 34 56 78' → +00330612345678 ❌** (préfixe 00 conservé)
                **'06 12 34 56 78 poste 12' → +061234567812 ❌** (E.164 invalide, commence par +0)
                **'612345678' (9 chiffres) → +612345678    ❌** (attendu +33612345678)
              Cause : `cooked_normalize_phone_fr` réduit à `[^0-9]` puis teste des longueurs ;
              `+33(0)6…` fait 12 chiffres → tombe dans la branche fourre-tout
              `when length(d) between 8 and 15 then '+' || d`.
              Miroir Python `scripts/secib_ingest.py:83-96` : mêmes quatre branches, mêmes
              longueurs, même fourre-tout → **le miroir est fidèle** (aucune divergence
              SQL/Python trouvée, y compris sur les espaces Unicode : Postgres `\s` supprime
              U+00A0 comme le fait `re.sub(r"\s", …)` en Python).
              Côté e-mail : `cooked_normalize_email` ne fait que « supprimer les espaces +
              minuscules ». Les sous-adresses `+tag` et les points Gmail ne sont **pas**
              normalisés (`contact+tag@example.com` et `j.e.a.n@gmail.com` restent tels quels) —
              choix défendable (matching strict), mais non documenté comme tel.
Impact        Aucun aujourd'hui : `secib_dossiers` contient 49 lignes, **toutes `env='test'`**,
              et `pont_prospects_dossiers` renvoie 853 lignes toutes en `statut='non_converti'`
              / `cle_match = NULL` (0 rapprochement). Le défaut mordra au premier ingest prod :
              un prospect qui écrit `+33 (0)6 …` dans le formulaire Wix et dont le dossier SECIB
              porte `06 …` ne se rejoindront jamais — faux négatif silencieux sur le taux de
              conversion prospect→dossier, la mesure même que le pont existe pour produire.
Récidive      Non — première mesure de ces fonctions (créées le 10/08/2026,
              migration `20260810082433_secib_pont_fondations`).
Invariant     Un fichier de vecteurs de test partagé (JSON) rejoué par les deux implémentations
              en CI — le patron existe déjà pour le branded GSC
              (`contracts/branded_query_vectors.json`, Arch #2) ; plus une assertion
              `tel_norm ~ '^\+[1-9][0-9]{7,14}$'` en contrainte CHECK sur `crm_prospects`.
Statut        [non recoupé]
```

```
ID            c-08
Titre         pont_prospects_dossiers : l'environnement SECIB n'est pas filtré, la priorité
              « email > téléphone » documentée n'est pas implémentée, et le statut « converti »
              n'a pas de borne haute
Sévérité      P2
Preuve        `pg_get_viewdef('public.pont_prospects_dossiers')` — prod, 02/09/2026 10:10 :
              (a) `FROM crm_prospects p LEFT JOIN LATERAL (SELECT … FROM secib_dossiers dd
                  WHERE p.email_norm = ANY(dd.client_emails_norm) OR p.tel_norm = ANY(…)
                  ORDER BY abs(EXTRACT(epoch FROM dd.date_creation - p.occurred_at)) LIMIT 1)`
                  → **aucune clause sur `dd.env`**. Aujourd'hui `SELECT env, count(*) FROM
                  secib_dossiers GROUP BY 1` → `test : 49` (une seule valeur).
              (b) CLAUDE.md : « Lecture du pont : vue `pont_prospects_dossiers` (email norm >
                  tél E.164 …) ». Le `ORDER BY` du LATERAL trie **uniquement** par proximité
                  temporelle ; `cle_match` rapporte `'email'` avant `'telephone'` *a posteriori*
                  sur le dossier déjà choisi. La priorité documentée n'existe pas dans le choix.
              (c) `CASE WHEN d.date_creation >= (p.occurred_at - '7 days') THEN 'converti'` :
                  borne **basse** de 7 jours, **aucune borne haute**. `delai_jours` peut valoir
                  plusieurs centaines.
              (d) `SELECT count(*), count(DISTINCT email_norm) FROM crm_prospects`
                  → 853 lignes / **760** e-mails distincts → **93 lignes (10,9 %) sont des
                  soumissions répétées de la même personne**. Le pont étant prospect-driven
                  (853 lignes en sortie = 853 lignes en entrée), un `count(*) WHERE
                  statut='converti'` comptera la même personne autant de fois qu'elle a rempli
                  le formulaire.
              Compléments (agrégats seuls) : `crm_prospects` = 853 lignes, 100 % avec
              `email_norm`, 852/853 avec `tel_norm`, 0 `tel_norm` hors forme E.164,
              **150/853 (17,6 %) avec `cooked_aid`**, source unique `form`,
              répartition par année : 2018 : 1 · 2025 : 322 · 2026 : 530.
Impact        Latent, mais il se déclenchera exactement au moment où le pont deviendra utile
              (swap des credentials SECIB prod) :
                • (a) les 49 dossiers du cabinet de démo Septeo resteront dans le pool de
                  rapprochement et pourront s'apparier à de vrais prospects ;
                • (b) un dossier apparié par téléphone mais plus proche dans le temps l'emportera
                  sur un dossier apparié par e-mail — l'inverse de la règle écrite ;
                • (c) un dossier ouvert 18 mois après un formulaire comptera « converti », et
                  `crm_prospects` remonte jusqu'à 2018 : la sur-attribution est structurelle ;
                • (d) le taux de conversion sera surévalué de ~11 % par les doublons.
              Enfin, seuls **17,6 %** des prospects portent un `cooked_aid` : le croisement
              « prospect × comportement web », raison d'être annoncée du pont, ne sera possible
              que sur un sixième des lignes.
              Point de vigilance de lecture : aujourd'hui la vue affiche **853 non_converti /
              0 converti**. Ce n'est pas un taux de conversion nul, c'est un côté droit vide —
              rien dans la vue ne le signale.
Récidive      Non — fondations livrées le 10/08/2026, jamais auditées depuis.
Invariant     `WHERE dd.env = 'prod'` (ou un paramètre d'environnement explicite) dans la vue ;
              `ORDER BY (p.email_norm = ANY(dd.client_emails_norm)) DESC, abs(…)` pour matérialiser
              la priorité documentée ; une borne haute paramétrée sur `converti` ; une colonne
              `personne_key` (email_norm) pour dédupliquer les comptages ; et un test de CI qui
              échoue si `secib_dossiers` contient des lignes `env <> 'prod'` visibles dans la vue.
Statut        [non recoupé]
```

---

## 2. Réfutation constat par constat

### c-01 — seo_to_contact_funnel : numérateur recousu / dénominateur en session brute

```
ID        c-01
Verdict   PARTIEL
```

**Ma preuve.** `pg_get_functiondef('public.seo_to_contact_funnel(integer)'::regprocedure)` ré-exécuté
en prod le **02/09/2026 à 15:03 (Paris)**. Le corps que j'ai lu contient bien, mot pour mot :

- `entries` : `select distinct on (e.session_id) … from public.events_human e where e.name='pageview'
  and e.occurred_at > now() - make_interval(days => days_back) order by e.session_id, e.occurred_at`
  — **aucune jointure `identity_stitch`**, aucun filtre spam ;
- `conv` : `from public.conversion_journeys(days_back) j` ;
- `gsc` et `topq` : `where g.day > current_date - days_back`.

Vérifications complémentaires que j'ai faites moi-même (même connexion, 15:03-15:04 Paris) :

| Contrôle | Ma valeur |
|---|---|
| `current_setting('TimeZone')` de la base | **UTC** (donc `current_date` = date serveur UTC : confirmé) |
| `conversion_journeys` cite `identity_stitch` | **true** |
| `conversion_journeys` utilise `now() - make_interval` | **true** |
| `min(day) → max(day)` de `gsc_path_daily where day > current_date - 28` | **06/08/2026 → 30/08/2026** |
| `gsc_last_data_day()` | **30/08/2026** |
| `paris_today()` / `current_date` | 02/09/2026 / 2026-09-02 |

Mesure du **grain**, ma requête (15:05 Paris), fenêtre `now() - 28 jours`, entrées organiques
(première pageview par session, `classify_channel(...) like 'organic%'`), jointure `identity_stitch` :

```
organic_sessions = 5 870 | organic_visiteurs_recousus = 5 383 | inflation du dénominateur = 8,3 %
```

Et la mesure citée par le constat, que je reproduis exactement (15:12 Paris) :
`phone_28j = 122`, dont **64 (52,5 %)** rattachés à un `visitor_key` portant ≥ 2 `session_id`.

Récidive : `git log -S'seo_to_contact_funnel' -- supabase/migrations` → dernière migration touchant le
corps = `20260609190500_sprint37_seo_to_contact_funnel.sql` ; les deux occurrences postérieures
(`20260712203935`, `20260727215805`) ne la redéfinissent pas (mention en commentaire seulement).
`docs/audit-architecture-2026-07-25.md:203` porte bien la ligne « Majeur | `seo_to_contact_funnel`
divise un numérateur recousu par un dénominateur en session brute ». **Non corrigé depuis le 25/07 :
confirmé** (39 jours).

**Écart.** Le défaut, sa cause et sa récidive tiennent intégralement. Trois éléments de quantification
ne tiennent pas :

1. **Le « 52 % » n'est pas la magnitude du biais du ratio.** Il mesure la part des contacts venant de
   visiteurs multi-sessions — vrai (je le reproduis) mais hors sujet comme ordre de grandeur du
   dénominateur. Le dénominateur réellement gonflé l'est de **8,3 %** (5 870 vs 5 383) : `contact_rate_pct`
   agrégé est sous-estimé d'environ **8 %** en relatif, pas d'un facteur deux. Le vrai dommage n'est pas
   scalaire mais **allocatif** : le numérateur est attribué à la page d'entrée de la *visite recousue*
   (parfois vieille de plusieurs jours) tandis que le dénominateur répartit les mêmes personnes sur
   plusieurs paths — l'erreur par page peut donc dépasser 8 % dans les deux sens, et le constat ne le dit
   pas.
2. **« borne stricte `>` = 27 jours » est faux.** `day > current_date - 28` → premier jour retenu 06/08,
   dernier 02/09 = **28 jours calendaires**, exactement la fenêtre de `cooked_period_bounds('rolling_28','live')`.
   Le vrai problème n'est pas la largeur nominale mais que seuls **25 jours portent de la donnée GSC**
   (06/08 → 30/08).
3. **`gsc_last_data_day()` = 30/08/2026 (J-3)**, pas 29/08 (J-4), et ce sont donc **3** jours sans
   impression (31/08, 01/09, 02/09), pas 4. Détail, mais le constat annonce un chiffre non vérifié.

Sévérité P1 : je la maintiens, non pour l'ampleur (8 %) mais parce que la RPC publie un ratio dont les
deux membres n'ont ni le même grain ni la même fenêtre, sans aucune mention — c'est la classe d'erreur
que la règle absolue de CLAUDE.md interdit.

**Invariant.** *Tient à moitié.* L'interdiction de `current_date` dans les migrations est un vrai garde-fou,
mécanisable par grep de CI, et fermerait la brique GSC. En revanche, « comparer `count(distinct session_id)`
et `count(distinct visitor_key)` » ne détecte rien par soi-même : ces deux nombres diffèrent *toujours*
(8,3 % ici) sans que ce soit un défaut. Ce qui empêcherait la récidive, c'est un test qui inspecte le
**grain déclaré de chaque membre du ratio** — en pratique : faire passer `entries` par la même jointure
`identity_stitch` que `conversion_journeys` et asserter en CI que `sum(organic_entries)` de la RPC est égal
au nombre de **visites recousues** organiques de la fenêtre. Sous sa forme actuelle l'invariant est
décoratif ; sous cette forme il tient.

---

### c-02 — la couture d'identité n'a ni horodatage ni alerte de fraîcheur

```
ID        c-02
Verdict   CONFIRMÉ
```

**Ma preuve.** Prod, **02/09/2026 15:05-15:07 (Paris)**.

`pg_get_functiondef('public.refresh_identity_stitch(integer)'::regprocedure)` — j'ai lu le corps entier.
Il construit des tables temporaires `_st_pairs` → `_st_l0…_st_l3` (label propagation alternée sid→aid→sid),
puis :

```sql
DELETE FROM identity_stitch;
INSERT INTO identity_stitch (kind, key, visitor_key)
  SELECT 'sid', s, lbl FROM _st_l3 UNION ALL SELECT 'aid', a, lbl FROM _st_a3;
```

`information_schema.columns` : `identity_stitch` = **`kind text, key text, visitor_key text`** — aucune
colonne de date, confirmé sur ma propre lecture.

`freshness_contract` (13 lignes) — j'ai listé les sources moi-même :
`cpi_daily, crm_prospects, cta_phone_click, dashboard_resources_snapshot, dfs_keyword_volume, form_submit,
gbp_daily, gsc_path_daily, gsc_query_daily, gsc_query_page_daily, math_visit_sequences_snapshot,
secib_dossiers, seo_url_snapshot`. **`identity_stitch` en est absente** : confirmé.

Couverture par les alertes — mon propre balayage :

```sql
select count(*) filter (where pg_get_functiondef(p.oid) ilike '%identity_stitch%') …
from pg_proc … where proname like 'alert_rule%' or proname in ('refresh_pipeline_health','cooked_alerts_refresh')
→ 0
```

**Zéro** des 11 règles d'alerte, ni `refresh_pipeline_health`, ni `cooked_alerts_refresh` ne mentionne la
couture. J'ai ensuite lu `alert_rule_cron_failed()` en entier : sa clause est
`WHERE j.active AND d.status = 'failed' AND d.start_time > now() - interval '7 days'` — un job **désactivé**
(`j.active` faux) ou **supprimé** (plus de ligne dans `cron.job`) ne produit rien, et un job dont le dernier
run a réussi mais qui ne tourne plus non plus. Le constat est exact.

Cron : `refresh-identity-stitch`, `40 3 * * *`, `active = true`, dernier succès **02/09/2026 05:40 (Paris)**.

Volumétrie, mes chiffres : `count(*) = 122 133`, `pg_relation_size = 24 MB`, `pg_indexes_size = **124 MB**`.
Le ratio index/heap de 5,2 sur deux btree de clés courtes est bien anormal ; je n'ai pas ré-audité les
compteurs autovacuum ni le classement des objets de la base (`[non vérifié]` sur « 4e objet, 2 379 Mo »).

**Écart.** Aucun sur le fond. Deux nuances : (1) le `DELETE` n'est pas qualifié (`DELETE FROM identity_stitch`,
sans `public.`) — sans importance, mais c'est pourquoi un test naïf sur `%delete from public.identity_stitch%`
renvoie faux ; (2) j'ajoute un mode de défaillance que le constat ne nomme pas et qui aggrave son point :
la fonction **vide la table avant de la reremplir dans la même transaction** ; si la source `events` ne
renvoie rien (purge, filtre trop strict, régression de `anonymous_id !~ '^[0-9a-f]{32}$'`), la couture
devient **vide sans erreur** et le cron est marqué `succeeded`. Le seul garde-fou proposé (fraîcheur) ne
détecterait même pas ce cas-là.

**Invariant.** *Tient, mais incomplet.* `refreshed_at` + ligne dans `freshness_contract` + seuil 30 h ferme
bien le scénario « cron mort » (le registre existe déjà et est le patron du chantier 1 du 23/08). Il ne
ferme pas le scénario « couture vide ou tronquée alors que le cron a réussi » : il faut y ajouter un
contrôle de **volume** (ex. `count(*) FROM identity_stitch WHERE kind='sid'` ≥ 80 % de la veille), et le
second contrat proposé (« % de sessions J-1 présentes = 100 % ») est le bon — c'est d'ailleurs exactement
la mesure qui rend c-04 visible.

---

### c-03 — les contacts assistés perdent les formulaires sans identifiant ; bucket `(non rattaché)` mort

```
ID        c-03
Verdict   CONFIRMÉ
```

**Ma preuve.** Une seule requête, prod, **02/09/2026 15:08 (Paris)**, fenêtre `paris_today()-27 → paris_today()`
(06/08 → 02/09) :

```
assisted_total        = 174        (sum(contacts) de assisted_contacts_by_entry_path)
bucket '(non rattaché)' = 0 ligne
macro_contacts_by_path(28) = 186
phone                 = 122
form_macro            = 64
form_macro_avec_id    = 52
```

**122 + 52 = 174 exactement** — l'identité annoncée par le constat se reproduit sur mes propres chiffres.
Manque : **186 − 174 = 12 = 64 − 52**, soit **6,5 %** du total site.

J'ai ensuite lu le corps de `assisted_contacts_by_entry_path(date,date)` en entier
(`pg_get_functiondef`, 15:09 Paris). Les trois mécanismes annoncés y sont, vérifiés par moi :

1. branche `form_submit` du CTE `_ct` : `… AND public.form_submit_counts_as_macro(e.props)
   AND COALESCE(e.props->>'cooked_sid', e.props->>'cooked_aid') IS NOT NULL` → les 12 formulaires sans
   identifiant sont écartés **avant** tout bucket ;
2. `_ce` : `FROM _ct c JOIN LATERAL (SELECT s.vk, s.visit_n FROM _pvseg s WHERE s.vk = c.vk AND s.t <= c.t
   AND c.t - s.t <= interval '6 hours' ORDER BY s.t DESC LIMIT 1) lp ON true` — c'est bien un **INNER**
   join latéral : un contact sans pageview recousue dans les 6 h disparaît sans trace ;
3. `_ventry` est construite par `SELECT vk, visit_n, (array_agg(path ORDER BY t))[1] FROM _pvseg GROUP BY vk, visit_n` :
   elle couvre par construction **tout** couple `(vk, visit_n)` que `lp` peut produire, puisque `lp` est lui-même
   tiré de `_pvseg`. Donc `v.entry_path` n'est jamais NULL et `COALESCE(v.entry_path,'(non rattaché)')`
   est **du code mort**. Constat empirique concordant : 0 ligne `(non rattaché)`, et 174 = 122 + 52 signifie
   que le LATERAL n'a aujourd'hui écarté **aucun** contact.

Convention opposée sur la voie sœur, mesurée par moi : `macro_contacts_by_path(28)` **expose** un bucket
`path = '(non rattaché)'` peuplé de **6** contacts. Deux conventions pour la même famille de chiffres :
confirmé.

**Écart.** Aucun sur la mécanique ni sur la classe de défaut. Les valeurs absolues ont bougé de quelques
unités entre 09:53 et 15:08 (171/183 → 174/186) — normal, la fenêtre inclut le jour en cours ; le taux de
perte est stable (6,6 % → 6,5 %) et l'identité `assisted = phone + form_avec_id` est exacte aux deux heures.
Note de méthode : mon comptage `form_macro` utilise `form_submit_counts_as_macro(props)` (le prédicat de
la prod) et non un filtre `ilike '%rejoindre%'` fait à la main ; il retombe sur `122 + 64 = 186 =
macro_contacts_by_path(28)`, ce qui recoupe les deux voies.

**Invariant.** *Tient.* Le contrat « Σ assistés + exclus = site » est vérifiable en CI, se calcule en une
requête, et échouerait dès aujourd'hui (174 + 0 ≠ 186) — c'est la marque d'un bon invariant : il est rouge
avant le correctif. Le passage `JOIN LATERAL … ON true` → `LEFT JOIN LATERAL` est nécessaire pour rendre
le bucket atteignable, mais **ne suffit pas** : il faut aussi lever la clause `cooked_sid/cooked_aid IS NOT NULL`,
sinon les 12 formulaires restent éliminés en amont du bucket et le contrat continue d'échouer. À préciser
dans la remédiation, sans quoi la moitié du correctif serait posée pour rien.

---

### c-04 — le grain d'identité change au milieu du jour en cours

```
ID        c-04
Verdict   CONFIRMÉ (et sous-estimé)
```

**Ma preuve.** Ma requête, prod, **02/09/2026 15:12 (Paris)**, sur **`events_human`** (le constat, lui,
lisait `events` brut ; je préfère la vue canonique — la conclusion est la même et le chiffre est celui que
verront les analyses business). Sessions distinctes par jour Paris, `session_id NOT LIKE 'webhook-%'`,
jointure `identity_stitch(kind='sid')` :

| Jour | Sessions | Hors couture | % | dont `anonymous_id` 32-hex (exclu par conception) |
|---|---|---|---|---|
| 29/08/2026 | 375 | 0 | 0,0 % | 0 |
| 30/08/2026 | 357 | 0 | 0,0 % | 0 |
| 31/08/2026 | 519 | 0 | 0,0 % | 0 |
| 01/09/2026 | 475 | 0 | 0,0 % | 0 |
| **02/09/2026** | **274** | **212** | **77,4 %** | 0 |

La colonne de droite écarte l'objection évidente : ces sessions ne sont pas absentes parce que le
`anonymous_id` serait le fallback serveur 32-hex exclu volontairement par `refresh_identity_stitch`
— aucune n'est dans ce cas. Elles sont absentes **parce que le cron n'a pas encore tourné**.

Cause confirmée par ma lecture directe : `cron.job` → `refresh-identity-stitch`, `40 3 * * *` (UTC), dernier
succès **02/09/2026 05:40 Paris**. Toute session postérieure à 05:40 attend le lendemain.

Consommateurs, mes propres lectures (15:13 Paris) :

- `cooked_period_bounds('rolling_28','live')` → **06/08/2026 → 02/09/2026** (inclut J) ;
  `('rolling_28','live_j1')` → **05/08/2026 → 01/09/2026** (exclut J) ;
- `pg_get_functiondef('public.dashboard_assisted_quarter()')` contient bien `paris_today()`
  (lecture du texte seule — je n'ai **pas exécuté** la fonction, interdite par le brief) ;
- `macro_contacts_by_path(integer)` : j'ai lu le corps, c'est littéralement
  `SELECT m.* FROM public.macro_contacts_by_path(public.paris_today() - (days_back - 1), public.paris_today())`
  → il inclut J.

**Écart.** Le défaut est **plus marqué** que ce que le constat annonce : 77,4 % à 15 h contre 54,3 % mesuré
à 10 h — attendu, la proportion croît toute la journée depuis 05:40 Paris. Le constat sous-estime donc, il
n'exagère pas. Deux précisions à sa rédaction : (1) le titre parle de « 0 % de celles de J-1 » — exact, je
le reproduis sur 4 jours ; (2) ce n'est pas « toute session postérieure » à 03:40 mais à **05:40 Paris**
(le constat le dit correctement dans la cause, pas dans le titre).

Sévérité P1 : justifiée, parce que le mélange de grains est **invisible** dans la sortie et qu'il touche
`macro_contacts_by_path(28)`, c'est-à-dire la métrique business remontée au client.

**Invariant.** *Tient, avec une réserve.* Basculer sur `live_j1` partout où un grain recousu est requis est
la solution propre et le mécanisme existe déjà (`cooked_period_bounds` sait le faire, c'est le lens du
dashboard depuis Arch #1) — donc le correctif est un changement d'appel, pas une invention. Le drapeau
`grain_partiel_jour_courant` est une seconde ligne acceptable. En revanche « test de CI :
`assisted_contacts_by_entry_path(J, J)` ne doit pas être publiée sans mention » est **décoratif** : la CI
ne peut pas savoir ce qu'un agent « publie » dans une réponse. Ce qui tient, c'est un test qui échoue si
une RPC de contacts renvoie une fenêtre dont `n_end = paris_today()` alors qu'elle joint `identity_stitch` —
condition mécanisable, elle.

---

### c-05 — trois définitions de « 28 jours » ; `now()` glissant contre la règle « fenêtre Paris »

```
ID        c-05
Verdict   PARTIEL
```

**Ma preuve.** Une requête unique, prod, **02/09/2026 15:10 (Paris)** :

```
macro_contacts_by_path(28)                              = 186
macro_contacts_by_path(paris_today()-27, paris_today()) = 186     ← identiques
macro_contacts_by_path(paris_today()-28, paris_today()) = 199     ← 29 jours
macro_contacts_by_path(28) où path='(non rattaché)'     = 6
conversion_journeys(28)                                 = 189
events_human macro sur occurred_at > now()-28 days      = 189     ← identiques
contacts macro du seul jour J-28 (05/08)                = 13
```

Corps lus par moi (15:04 et 15:14 Paris) :
`conversion_journeys(integer)` et `form_submits_attributed(integer)` contiennent
`now() - make_interval` et **ne contiennent pas** `paris_date` ;
`macro_contacts_by_path(integer)` est un simple `SELECT` de l'overload date, avec
`paris_today() - (days_back - 1) → paris_today()`.

Donc : **deux définitions de fenêtre coexistent bel et bien** pour la même notion de contact macro —
calendaire Paris d'un côté, glissante `now()` de l'autre — et `conversion_journeys(28) = 189 ≠
macro_contacts_by_path(28) = 186` sur la même étiquette « 28 jours ». Le cœur du constat tient, et sa
correction à la baseline (les deux overloads de `macro_contacts_by_path` sont identiques) est **exacte** :
je le vérifie moi-même, 186 = 186, et le corps de l'overload entier l'explique.

**Écart.** Trois points.

1. **« Trois définitions » est une de trop.** Il n'y en a que **deux** en prod : calendaire Paris
   (`paris_date`) et glissante (`now()`). Le troisième chiffre (196 chez eux, 199 chez moi) n'est pas une
   définition de la prod : c'est l'overload date appelé à la main sur **29** jours — le constat le
   reconnaît d'ailleurs lui-même dans son bloc « correction à la baseline », ce qui rend son propre titre
   contradictoire.
2. **Le sens de la dérive horaire est inversé.** Le constat écrit « à minuit il tend vers 0, à 23 h vers un
   jour entier ». C'est le contraire : la fenêtre glissante `now()-28 j` déborde sur la **fin de J-28**,
   part qui *rétrécit* au fil de la journée. Vérification par les faits : écart mesuré **+9** à 09:53 puis
   **+3** à 15:10 le même jour — l'écart **décroît**. Le défaut est réel (non-reproductibilité intra-journée),
   sa description est fausse.
3. Chiffres absolus décalés (183/192 → 186/189) : simple effet du jour en cours, sans conséquence.

Sévérité P2 : d'accord. L'écart est de 1,6 % ce jour-là (3/186) et peut atteindre un jour de contacts en
début de journée ; c'est un problème de reproductibilité, pas de justesse grossière.

**Invariant.** *Tient.* Faire passer les trois RPC par `cooked_period_bounds` supprime la seconde définition
au lieu de la documenter — c'est le bon niveau (le driver existe déjà et 8 appelants l'utilisent). Le test
« deux RPC publiées ne doivent pas renvoyer des totaux de contacts macro différents pour la même étiquette
de période » est mécanisable et serait rouge aujourd'hui (189 vs 186). Un ajout utile, dans l'esprit du
grep `occurred_at::date` déjà en CI : interdire `now() - make_interval` dans les migrations qui définissent
une RPC de contacts.

---

### c-06 — `classify_channel` ignore le prédicat anti-spam

```
ID        c-06
Verdict   CONFIRMÉ
```

**Ma preuve.** Ma requête, prod, **02/09/2026 15:11 (Paris)** — pageviews `events_human`, fenêtre
`paris_today()-27 → paris_today()` (06/08 → 02/09), canal par `classify_channel(referrer_hostname,
utm_source, utm_medium, 'www.jplouton-avocat.fr')`, spam par `cooked_is_spam_referrer(referrer_hostname)` :

```
total pageviews            13 529
canal 'referral'            1 987
dont spam (helper prod)     1 867   → 93,96 % du canal ; 1 867 sessions distinctes
referral réel                 120   → facteur 16,6
part du spam sur tous les pv  13,8 %
classify_channel cite 'spam' : false
```

J'ai ensuite lu `pg_get_functiondef('public.classify_channel(text,text,text,text)')` en entier
(15:14 Paris) : aucune référence à `cooked_is_spam_referrer` ni à Baidu, la dernière branche est bien
`else 'referral'`. Et `cooked_is_spam_referrer(text)` que j'ai lu vaut
`p_hostname IS NOT NULL AND p_hostname IN ('m.baidu.com', 'baidu.com')`.

Les écarts de taxonomie mineurs sont structurellement exacts, vérifiés sur le corps que j'ai lu :
la liste `utm_source` de la branche `organic_ai` est bien en **égalité exacte**
(`lower(utm_source) in ('chatgpt.com','openai','perplexity','perplexity.ai','claude.ai','gemini','copilot')`)
alors que les referrers sont testés en `ilike '%…%'` ; `kagi`, `yandex`, `youcare`, `ccleaner` sont absents
de `organic_other` ; `lnkd.in` et `bsky` absents de `social`. Je n'ai pas recompté les volumes unitaires de
ces cas (`[non vérifié]` sur « ≤ 11 pv »), sans incidence : c'est un ordre 3 par rapport à Baidu.

Récidive — je l'ai vérifiée **en prod** plutôt que dans `supabase/rpcs.sql` (que le brief signale comme
périmé) :

```sql
select proname from pg_proc … where prosrc like '%m.baidu.com%' and proname <> 'cooked_is_spam_referrer'
→ dashboard_article_detail, refresh_dashboard_expertises_snapshots, refresh_dashboard_snapshots
```

**Trois** routines portent encore le littéral, en prod, comme annoncé. Aucune vue n'en porte.

**Écart.** Aucun sur le fond ; mes chiffres reproduisent les leurs à 1 % près (dérive du jour en cours).
Deux ajouts de ma part qui renforcent le constat : (1) les 3 copies littérales ne testent que
`m.baidu.com` alors que le helper couvre **aussi `baidu.com`** — les copies sont donc strictement plus
faibles que la source unique, ce que le constat ne relève pas ; (2) j'ai confirmé sur ma propre lecture du
corps de `seo_to_contact_funnel` (c-01) que son CTE `entries` n'appelle pas `cooked_is_spam_referrer`,
alors que `assisted_contacts_by_entry_path` le fait (`AND NOT public.cooked_is_spam_referrer(e.referrer_hostname)`,
lu par moi) : deux RPC voisines, deux politiques opposées sur le même bruit.

**Invariant.** *Tient, sous condition.* Le test de CI proposé est exact et serait rouge aujourd'hui
(1 867 lignes). Mais faire renvoyer `'spam'` par `classify_channel` est un **changement de contrat**
qui vaut restatement : la valeur `referral` perd 94 % de son volume, et tout appelant qui énumère les
canaux en dur doit être revu. Le CPI n'est pas touché (ses composantes filtrent `organic%`), la home non
plus, mais il faut poser une annotation le jour J — exactement comme pour `classify_channel` v2 (utm IA)
et v3 (GMB). Sans cette annotation, l'invariant crée le faux « decay » que le projet passe son temps à
démentir. À noter dans la remédiation, sinon le correctif reproduit la classe de problème qu'il corrige.

---

### c-07 — normalisation téléphone : `+33 (0)6 …` casse, miroir Python fidèle

```
ID        c-07
Verdict   CONFIRMÉ
```

**Ma preuve.** Ma requête de test, prod, **02/09/2026 15:14 (Paris)**, **valeurs fictives uniquement**
(aucune donnée de `crm_prospects` n'a été lue pour ce test) :

| Entrée fictive | `cooked_normalize_phone_fr` | forme E.164 ? |
|---|---|---|
| `06 12 34 56 78` | `+33612345678` | ✅ |
| `+33 6 12 34 56 78` | `+33612345678` | ✅ |
| `00 33 6 12 34 56 78` | `+33612345678` | ✅ |
| `06.12.34.56.78` | `+33612345678` | ✅ |
| `tel : 06 12 34 56 78` | `+33612345678` | ✅ |
| `+590 690 12 34 56` | `+590690123456` | ✅ |
| **`+33 (0)6 12 34 56 78`** | **`+330612345678`** | ✅ *forme valide, numéro faux* |
| **`0033 (0)6 12 34 56 78`** | **`+00330612345678`** | ❌ |
| **`06 12 34 56 78 poste 12`** | **`+061234567812`** | ❌ |
| **`612345678`** | **`+612345678`** | ✅ *forme valide, numéro faux* |

Les quatre échecs annoncés se reproduisent **à l'identique**. Cause confirmée par ma lecture du corps
(`pg_get_functiondef`, 15:14 Paris) : réduction à `regexp_replace(…, '[^0-9]', '', 'g')` puis quatre
branches de longueur, la dernière étant le fourre-tout `when length(d) between 8 and 15 then '+' || d`.
`+33(0)6…` fait 12 chiffres → fourre-tout.

Miroir Python relu par moi : **`scripts/secib_ingest.py:83-96`** — `normalize_phone_fr` a les mêmes quatre
branches, dans le même ordre, avec les mêmes longueurs (`0033`+13, `33`+11, `0`+10, puis `8 ≤ len ≤ 15`) et
le même retour `None` final. **Le miroir est fidèle** : confirmé, aucune divergence.

J'ai testé la seule divergence plausible que le constat écarte sans la mesurer — le traitement des espaces
Unicode par `\s` côté Postgres, qui dépend du ctype et n'est pas garanti d'inclure U+00A0 :

```
cooked_normalize_email('Test⍽Fictif@Example.com') avec U+00A0 → 'testfictif@example.com' (22 car.) ✅
idem avec U+202F (espace fine insécable)                      → 'testfictif@example.com'          ✅
```

Postgres se comporte donc bien comme `re.sub(r"\s", …)` de Python 3 sur ces deux caractères. La conclusion
du constat tient, et elle tient maintenant sur une mesure et non sur une présomption.

Impact — mes agrégats (15:15 Paris, **aucune valeur individuelle lue**) : `secib_dossiers` = **49 lignes,
toutes `env='test'`** ; `pont_prospects_dossiers` = **856 lignes, toutes `statut='non_converti'`**. Le
défaut est donc bien latent aujourd'hui.

**Écart.** Aucun. Une précision utile pour la remédiation : `crm_prospects` compte **0** `tel_norm` hors
forme `^\+[1-9][0-9]{7,14}$` (856 lignes, 855 avec téléphone) — autrement dit le stock actuel *passerait*
la contrainte proposée alors qu'il contient probablement déjà des `+33 0…`. Voir l'invariant.

**Invariant.** *À moitié décoratif.* Les vecteurs de test partagés en CI sont la bonne réponse et le patron
existe déjà (`contracts/branded_query_vectors.json`, Arch #2) — cette moitié tient et attraperait les
quatre cas. La contrainte `CHECK (tel_norm ~ '^\+[1-9][0-9]{7,14}$')` est en revanche **inopérante sur le
cas principal** : `+330612345678` (issu de `+33 (0)6 …`) satisfait ce motif tout en étant un numéro faux,
et `+612345678` aussi. Elle n'attraperait que les deux cas déjà exclus par `+0…`. Un invariant qui laisse
passer le défaut qui motive le constat est décoratif ; le contrôle utile est un motif **français**
(`^\+33[1-9][0-9]{8}$` pour les numéros métropolitains) appliqué dans les vecteurs, pas une forme E.164
générique.

---

### c-08 — `pont_prospects_dossiers` : env non filtré, priorité non implémentée, `converti` sans borne haute

```
ID        c-08
Verdict   CONFIRMÉ
```

**Ma preuve.** `pg_get_viewdef('public.pont_prospects_dossiers'::regclass, true)` — prod, **02/09/2026
15:15 (Paris)**, lu intégralement par moi. Les quatre points sont dans le texte que j'ai sous les yeux :

**(a) aucun filtre d'environnement.** Le LATERAL est :
`FROM secib_dossiers dd WHERE p.email_norm IS NOT NULL AND (p.email_norm = ANY (dd.client_emails_norm))
OR p.tel_norm IS NOT NULL AND (p.tel_norm = ANY (dd.client_tels_norm)) ORDER BY (abs(EXTRACT(epoch FROM
dd.date_creation - p.occurred_at))) LIMIT 1` — **`dd.env` n'apparaît nulle part** dans le prédicat ; `env`
est seulement remonté en sortie sous l'alias `secib_env`. Ma mesure : `secib_dossiers` → **`test : 49`**,
valeur unique. (Précision de lecture : la précédence `AND`/`OR` donne bien `(A AND B) OR (C AND D)`, la
sémantique voulue — il n'y a pas de bug de parenthésage à ajouter au constat.)

**(b) la priorité « email > téléphone » n'existe pas dans le choix.** `ORDER BY abs(EXTRACT(epoch FROM
dd.date_creation - p.occurred_at))` — proximité temporelle **seule**. `cle_match` est un `CASE` calculé
*après coup* sur le dossier déjà retenu (`WHEN p.email_norm = ANY (d.client_emails_norm) THEN 'email'
WHEN p.tel_norm = ANY (d.client_tels_norm) THEN 'telephone'`). CLAUDE.md annonce pourtant « email norm >
tél E.164 » : l'écart doc/implémentation est réel.

**(c) `converti` sans borne haute.** `CASE WHEN d.dossier_id IS NULL THEN 'non_converti' WHEN
d.date_creation >= (p.occurred_at - '7 days'::interval) THEN 'converti' ELSE 'client_existant' END` —
borne basse à −7 jours, **rien** au-dessus ; `delai_jours` est un simple `epoch/86400` non borné.

**(d) doublons de personnes.** Mes agrégats (aucune valeur individuelle) : `crm_prospects` = **856** lignes
pour **763** `email_norm` distincts → **93 lignes (10,9 %)** sont des soumissions répétées. La vue est
prospect-driven (`FROM crm_prospects p LEFT JOIN LATERAL …`, un dossier au plus par prospect) : **856 lignes
en sortie pour 856 en entrée**, vérifié. Un `count(*) WHERE statut='converti'` comptera donc la même
personne autant de fois qu'elle a rempli le formulaire.

Compléments mesurés par moi : 855/856 avec `tel_norm`, **0** `tel_norm` hors forme E.164,
**153/856 = 17,9 %** avec `cooked_aid`, `pont_prospects_dossiers` = 856 lignes **toutes `non_converti`**.

**Écart.** Aucun sur le fond ; les valeurs ont bougé de 853 → 856 prospects (3 nouveaux formulaires dans la
journée), 760 → 763 e-mails distincts, 150 → 153 `cooked_aid` (17,6 % → 17,9 %). Le taux de doublons
(10,9 %) et le taux de couverture `cooked_aid` (~18 %) sont identiques. Je n'ai pas revérifié la
répartition par année (`[non vérifié]` sur « 2018 : 1 · 2025 : 322 · 2026 : 530 ») : elle n'est pas
nécessaire au verdict, le point (c) tenant du seul fait qu'aucune borne haute n'existe.

Sévérité P2 : justifiée — le défaut est **entièrement latent** (côté droit vide, 49 dossiers de démo, 0
rapprochement) et se déclenchera au swap des credentials SECIB prod. C'est un défaut à corriger *avant*
que le pont serve, pas un chiffre faux livré aujourd'hui.

**Invariant.** *Tient — c'est le mieux construit des huit.* Les quatre remèdes sont chacun une ligne de SQL
et adressent chacun un point mesuré : `WHERE dd.env = 'prod'` ; `ORDER BY (p.email_norm = ANY(...)) DESC,
abs(…)` pour matérialiser la priorité documentée ; borne haute paramétrée sur `converti` ; `personne_key`
pour la déduplication. Le test de CI (« échouer si des lignes `env <> 'prod'` sont visibles dans la vue »)
est rouge aujourd'hui et le resterait tant que le pool de démo est là : bon invariant. Deux réserves :
(1) filtrer `env='prod'` rendra la vue **vide** jusqu'au swap des credentials — il faut que le tableau de
bord distingue « 0 rapprochement » de « côté droit absent », sinon on remplace un piège de lecture par un
autre (le constat le signale d'ailleurs comme point de vigilance sans le porter dans l'invariant) ;
(2) la borne haute est un **choix métier** (quel délai formulaire→dossier reste attribuable ?) qui appartient
à Nicolas, pas à la CI : l'invariant doit exiger qu'elle soit *paramétrée et documentée*, pas fixer une valeur.

---

## 3. Note de méthode

- Aucune écriture : uniquement `SELECT` / `WITH … SELECT` et lectures de définitions
  (`pg_get_functiondef`, `pg_get_viewdef`, `information_schema`, `cron.job`). Aucune fonction interdite
  appelée — `dashboard_assisted_quarter()` et `cooked_page_index()` ont été **lues**, jamais exécutées ;
  `assisted_contacts_by_entry_path` n'a été appelée que sur 28 jours.
- Aucune PII : `crm_prospects`, `secib_dossiers` et `pont_prospects_dossiers` n'ont été interrogées qu'en
  `count(*)`, `count(distinct)`, agrégats par `env`/`statut` et structure. Les tests de normalisation
  n'utilisent que des valeurs fictives.
- Toutes les mesures de trafic passent par `events_human`, y compris pour c-04 où le constat d'origine
  lisait `events` brut.
- Un seul fichier écrit : le présent livrable.
