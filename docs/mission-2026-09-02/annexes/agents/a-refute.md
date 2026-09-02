# Réfutation zone (a) — tracker + proxy Velo + masterpage — mission Cooked 02/09/2026

8 constats reçus, 8 recopiés ci-dessous (aucun manquant). Repo local `main` = `e95f3ee` (lecture seule) ;
prod Supabase `mxycmjkeotrycyneacje` (SELECT uniquement, fenêtres ≤ 28 j). Toutes les mesures ci-dessous sont
**miennes**, ré-exécutées le 02/09/2026 entre 15:13 et 15:35 Paris (`now()` prod = 2026-09-02 15:13:44 Paris) —
jamais la preuve recopiée du constat.

---

## Constats reçus (recopie intégrale)

### a-01
```
Titre         Un bot (user_agent = « pc », référent m.baidu.com) vit dans events_human : 13,95 % des pageviews et 17,33 % des sessions sur 28 j
Sévérité      P0
Preuve        [cf. brief — requête 02/09/2026 09:56 Paris : 1 864 pageviews/sessions, 100 % référent m.baidu.com,
              device desktop ; répartition par path = univers pages expertise + hubs ; events_human = events_no_bots
              MINUS noise_sessions MINUS chrome-anchors MINUS doublons, sans filtre de référent spam
              (views.sql:128-146) ; ua_bot (rpcs.sql:4214-4256/4262-4290) ne matche pas l'UA littéral 'pc' ; la
              règle heuristique de bruit exige 0 referrer_hostname ET 0 tick ET 1 pageview ET <10s, ce bot a un
              referrer et ~100s de vie.]
Impact        Sur-compte events_human de +13,95 %/+17,33 % sans le dire ; RPC publiées largement protégées
              (cooked_is_spam_referrer dans 8 corps) ; le trou est exactement là où CLAUDE.md envoie l'analyste.
Récidive      OUI (mémoire reference_baidu_referral_spam.md ; audit-architecture-2026-07-25.md:196 « Majeur »,
              16,7 % ; remède du 25/07 = filtre côté lecture, pas tarissement de la source).
Invariant     (a) Ajouter 'pc' à la taxonomie ua_bot Edge+SQL. (b) Alerte si part de sessions à référent spam
              dans events_human > ~1 %.
Statut        [non recoupé] — pas de contre-vérification externe possible pour du trafic non-Google.
```

### a-02
```
Titre         La couverture page_exit annoncée en Phase 0 (75,4 % ; desktop 60,3 %) est un artefact du bot a-01 : hors bot elle est de 89,0 % (desktop 94,6 %)
Sévérité      P1
Preuve        [cf. brief — requête 02/09/2026 10:04 Paris, events_human 28 j, user_agent<>'pc', GROUP BY
              session_id/path : mobile 6 878→86,5 %, desktop 3 213→94,6 %, tablet 40→82,5 %, pondéré 89,0 %.
              Reconstruction : bot 100 % desktop, 0 page_exit → 3 213×0,946/(3 213+1 864)=59,9 % ≈ 60,3 %
              annoncés. Le mobile (non touché) est identique aux deux mesures.]
Impact        Pas de problème page_exit spécifique au desktop — c'est le device le mieux couvert hors bot ; le
              vrai déficit résiduel est mobile (iOS pagehide).
Récidive      Même mécanisme que a-01, angle différent (parts de trafic vs taux de couverture).
Invariant     Le test a-01 (part spam < 1 %) suffit ; à défaut, décomposer tout taux de couverture par
              device_type ET user_agent/référent avant publication.
Statut        [non recoupé] — recoupé en interne via le témoin mobile, pas contre une source externe.
```

### a-03
```
Titre         Le CLS n'est mesuré que sur Chromium et n'est jamais émis quand il vaut zéro : tout p75 CLS du site est calculé sur un échantillon censuré
Sévérité      P1
Preuve        [cf. brief — tracker.html:1042-1046 `if (vitals.cls) emitVital(...)` (falsy sur CLS réellement
              nul) ; tracker.html:960 arrondi 2 décimales (1/10 du seuil « bon » 0,1). Prod 02/09 10:10-10:14 :
              CLS n=3 797 dont 1 071 à 0,00 ; Chrome 4 280→3 064 avec CLS (71,6 %), p75 0,160 vs 0,120 avec
              zéros implicites ; Safari 2 289→8 (0,3 %) ; Firefox 594→0 ; Edge 384→337, p75 0,040 vs 0,030.]
Impact        Deux biais opposés invisibles : p75 Chromium surestimé de ~33 % ; le CLS est une métrique
              Chromium-only (38 % des chargements avec LCP n'en produisent jamais) sans être étiquetée comme
              telle ; un p75 Safari sur 8 observations est lisible sans garde-fou.
Récidive      Non traité par les audits antérieurs ; classe voisine (INP muet à seuil 16) déjà rencontrée et
              corrigée par changement de seuil, jamais généralisée.
Invariant     Contrat de lecture : dénominateur + périmètre navigateur + n minimal par percentile CWV (discipline
              des grades A/B/C du CPI). Côté tracker : test jsdom qu'un chargement sans layout shift émette 0
              explicite.
Statut        [non recoupé] — pas de source CrUX/PSI consultée.
```

### a-04
```
Titre         Le batching n'a ni accusé de réception, ni reprise, ni clé d'idempotence : un lot rejeté disparaît sans trace, events critiques compris
Sévérité      P1
Preuve        [cf. brief — tracker.html:422-433 `queue.splice(0,50)` AVANT `transmit(...)` ; tracker.html:405-420
              sendBeacon (retour true ≠ reçu) puis fetch keepalive SANS .then/.catch ; tracker.html:435-442 les
              events CRITICAL (dont cta_phone_click, form-adjacent) flushent immédiatement sans reprise. Rejets
              possibles : http-functions.js:51-57 (403), :66-71 (400 >60 000 car.), :104-107 (500). Aucun
              event_id côté client.]
Impact        Panne silencieuse par construction : un incident proxy/Edge de quelques heures fait disparaître des
              cta_phone_click sans trace ni côté client (file vidée) ni côté serveur (jamais arrivé) ;
              ingest_drops ne voit que ce qui atteint l'Edge.
Récidive      Constaté et explicitement conservé (audit-architecture-2026-07-25.md:204, :295 — arbitrage assumé).
Invariant     À défaut d'un correctif client (remise en file + event_id), alerte de plancher sur le volume horaire
              d'events (l'alerte pipeline mort existe, pas la perte partielle).
Statut        [non recoupé] — aucune perte observée ni chiffrée, le constat porte sur l'absence de mécanisme.
```

### a-05
```
Titre         Le monolithe minifié occupe 14 760 des 15 000 caractères Wix : il ne reste plus la place d'un sprint fonctionnel
Sévérité      P2
Preuve        [cf. brief — tracker.min.html = 14 760 car. (marge 240, 1,6 %) contre WIX_LIMIT=15 000
              (minify-tracker.py:33) ; tracker.test.js:105 `min.length<=15000` passe aujourd'hui. Trajectoire
              rejouée en mémoire sur les révisions git de tracker.html, de 6 586 (07/05) à 14 760 (12/07,
              sprint41), avec deux baisses seulement (sprint38 -601, D9 -245).]
Impact        Budget restant (240 car.) < coût médian d'un sprint (+171 à +956) ; le correctif a-04 et l'émission
              explicite d'un CLS nul (a-03) ne rentrent pas en l'état. Piste non tranchée : loader first-party.
Récidive      Non — dette jamais traitée, repoussée deux fois par refactor.
Invariant     Le garde existe (minify-tracker.py:63-67 exit 2 ; tracker.test.js:105 ; workflow tracker-test.yml).
              Manque un seuil d'alerte anticipé (ex. 14 250, 5 % de marge).
Statut        [non recoupé] — limite Wix 15 000 reprise du repo, pas revérifiée auprès de Wix.
```

### a-06
```
Titre         Le pageview part avant que la page soit prête : title NULL sur 98,8 % des pageviews, et 549 Mo de colonnes url/title que rien ne lit
Sévérité      P2
Preuve        [cf. brief — emitPageview() ligne 466 (synchrone, tôt dans l'IIFE), basePayload():359-377 lit
              document.title ligne 366 ; exposeIds() ligne 1128, à la toute fin. Prod 02/09 10:18 : pageview
              n=11 508 → 98,8 % title NULL / 11,1 % url avec ids ; engagement_tick 0,1 %/99,6 % ; page_exit
              0,7 %/99,2 % ; scroll_depth 0,0 %/99,8 % ; web_vitals 34,1 %/99,5 % (contrôle : 34,1 % de 29 379 =
              10 018 ≈ 10 061 TTFB, le seul vital tôt).]
Impact        events.title inexploitable comme libellé sur le pageview lui-même ; 549 Mo (400 url + 149 title,
              audit 25/07) sur une table déjà saturée, dont 99 % des non-pageview portent les ids via
              exposeIds()/replaceState — question de rétention à trancher ailleurs.
Récidive      Coût de stockage déjà constaté (25/07, resté ouvert) ; la cause d'ordonnancement du title est
              nouvelle.
Invariant     Si on garde title : test de contrat pageview.title NOT NULL (échouerait aujourd'hui à 98,8 %, c'est
              le signal voulu). Si on la supprime : migration nommée + mise à jour track_row.ts.
Statut        [non recoupé] — les volumes 400/149 Mo viennent de l'audit du 25/07, non remesurés (budget connecteur).
```

### a-07
```
Titre         La correction sprint41 — celle qui a réparé 22 % des sessions coupées — n'a aucun test, et les deux fichiers Velo ne sont couverts par rien
Sévérité      P2
Preuve        [cf. brief — suite locale : 29 assertions, TOUT PASSE, source+minifié. Ce qu'elle couvre : garde
              double-embed, classification clics, version stamp, exposition ids, ré-exposition SPA, localStorage
              bloqué dès le départ (pas un wipe en cours de page), format batch, active_ms/duration, taille
              minifié. Ce qu'elle NE couvre PAS : le scénario de wipe-en-cours-de-page de sprint41 (healAid,
              tracker.html:251-257, cache _cachedSid) ; le ré-armement page_exit de sprint40 ; le filtrage chrome
              d'isAN (sprint35) ; tout échec de transmit (mock fetch résout toujours {ok:true}). CI :
              tracker-test.yml ne se déclenche que sur tracker.html/tracker.test.js/minify-tracker.py/lui-même ;
              http-functions.js et masterpage-cooked.js dans aucun workflow. Dernier run Tracker Test : 12/07/2026,
              succès ; le commit f8b42c1 (modifiant http-functions.js) n'a rien déclenché.]
Impact        Pas de chiffre faux aujourd'hui ; risque de retour d'un défaut déjà payé (couture d'identité,
              restatement CPI) à la prochaine refonte du bloc storage.
Récidive      Manque de même nature que celui corrigé le 30/06/2026 (suite ajoutée S38, câblée en CI seulement
              au ménage du 30/06) ; la suite est câblée mais a cessé de suivre le code.
Invariant     Tout correctif tracker qui ferme un défaut mesuré en prod ajoute une assertion qui le reproduit
              (rouge avant / vert après) ; étendre les `paths:` du workflow aux deux fichiers Velo.
Statut        [non recoupé] — constat de couverture, lu dans le code et confirmé par l'exécution de la suite.
```

### a-08
```
Titre         Le garde d'origine Velo est fermé mais reste franchissable avec un en-tête forgé, sans rate-limit ; et COOKED_DEBUG est resté à true
Sévérité      P2
Preuve        [cf. brief — http-functions.js:50-57 teste `!origin || !origin.startsWith(ALLOWED_ORIGIN)` (403 sur
              Origin absent, corrige l'hypothèse startsWith-falsy) ; :59-63/:90 charge et transmet
              x-cooked-key. Reste : (a) Origin OU Referer acceptés, forgeables par tout client HTTP ; (b) aucun
              rate-limit, seule borne 60 000 car. + 50 events/lot ; (c) x-cooked-key ajouté PAR le proxy, protège
              l'Edge d'un appel direct, pas /_functions/track. Contre-preuve : 128/128 cta_phone_click avec
              pageview antérieure même session, 28 j. masterpage-cooked.js:22 `COOKED_DEBUG = true` (chaîne
              vérifiée depuis le 11/06/2026) ; lignes 40/51/73 journalisent aid/sid/nb formulaires en console.]
Impact        Le chiffre le plus sensible (contacts macro) reste falsifiable par un tiers lisant le tracker
              minifié ; probabilité faible, impact maximal, aucun contrôle a posteriori. COOKED_DEBUG = mineur
              (bruit console, ids déjà publics du visiteur).
Récidive      Partielle — audit 25/07 classait « Critique », le garde + secret sont bien le correctif acté ; le
              résidu (en-tête forgeable, pas de rate-limit) est un arbitrage assumé, pas un oubli.
Invariant     Détection : alerte `alerts` sur un contact macro sans amont dans la même session (0/128 aujourd'hui,
              seuil bas viable). CI grep interdisant `DEBUG = true` sur `wix/*.js` en branche main.
Statut        [non recoupé] — aucune tentative d'injection faite (lecture seule) ; état réel de COOKED_DEBUG sur
              le masterPage.js PUBLIÉ sur Wix = [non vérifié] (le repo n'est pas le déployé).
```

---

## Verdicts

### a-01
```
ID        a-01
Verdict   CONFIRMÉ
Ma preuve Requête prod exécutée 02/09/2026 ~15:14 Paris (now() prod = 2026-09-02 15:13:44) :
            SELECT count(*) pageviews, count(DISTINCT session_id) sessions FILTER (WHERE user_agent='pc')
            → 1 953 pageviews, 1 953 sessions, 100 % referrer_hostname='m.baidu.com', device_type='desktop'
            (fenêtre `occurred_at >= now() - interval '28 days'`).
            Dénominateur global sur la même fenêtre : 13 807 pageviews / 11 142 sessions (name='pageview').
            → 14,1 % des pageviews, 17,5 % des sessions (vs 13,95 %/17,33 % annoncés — écart dû à la fenêtre
            glissante vs date-anchorée du constat, même ordre de grandeur).
            Code : `supabase/views.sql:128-146` relu — `events_human` = events_no_bots MINUS noise_sessions
            MINUS chrome-anchors MINUS doublons, aucune clause référent. Confirmé en PROD (pas seulement dans
            le fichier local, potentiellement périmé) :
              `SELECT pg_get_viewdef('public.events_human'::regclass,true) ILIKE '%spam%'` → false,
              `... ILIKE '%baidu%'` → false.
            `SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='refresh_noise_sessions'` (PROD, pas le
            fichier) → contient `ua_bot`, ne matche PAS le littéral `'pc'` (`ILIKE '%''pc''%'` → false).
Écart     Chiffres légèrement différents (14,1/17,5 % vs 13,95/17,33 %) par effet de fenêtre glissante — même
          conclusion, même ordre de grandeur, aucune remise en cause de la sévérité.
Invariant Tient. (a) est un fix mécanique simple (ajouter un motif à une taxonomie déjà consultée à l'ingestion
          ET dans refresh_noise_sessions — vérifié en prod, pas juste dans un fichier potentiellement périmé).
          (b) est une détection réelle (alerte sur ratio), pas une prévention — utile mais n'empêche pas
          l'écriture des lignes, contrairement à (a).
```

### a-02
```
ID        a-02
Verdict   CONFIRMÉ
Ma preuve Requête prod 02/09/2026 ~15:20 Paris, events_human 28 j (`occurred_at >= now() - interval '28 days'`),
          `user_agent <> 'pc'`, GROUP BY session_id, path (device_type = max par paire) :
            mobile  n=7 243 → 86,8 % avec page_exit
            desktop n=3 761 → 95,3 %
            tablet  n=49    → 85,7 %
          Même requête SANS exclure le bot, desktop seul : n=5 714 → 62,7 % (vs 60,3 % Phase 0 — écart de
          fenêtre, même mécanisme).
          → Reproduction indépendante de l'écart : desktop hors bot (95,3 %) très supérieur à desktop avec bot
          (62,7 %) ; mobile, non touché par le bot, reste le device le moins bien couvert des trois une fois le
          bot retiré (86,8 % < 95,3 % desktop) — confirme que le vrai déficit résiduel est mobile, pas desktop.
Écart     Valeurs numériques légèrement différentes (86,8/95,3/85,7 vs 86,5/94,6/82,5 annoncés) par effet de
          fenêtre glissante vs date-anchorée — direction et conclusion identiques.
Invariant Tient pour la partie « le test a-01 suffit » (un ratio spam < 1 % dans events_human aurait empêché ce
          chiffre de sortir tel quel). La recommandation additionnelle (décomposer systématiquement par device
          ET user_agent avant publication) est une discipline de playbook, pas un gate technique — décorative
          tant qu'elle n'est pas codifiée dans un script/test.
```

### a-03
```
ID        a-03
Verdict   CONFIRMÉ
Ma preuve Code relu : `wix/tracker.html:960` — `Math.round(value*100)/100` (arrondi 2 décimales) ; `:1044` —
          `if (vitals.cls) emitVital('CLS', vitals.cls)` (falsy sur zéro réel) ; `:1028` —
          `durationThreshold: 40` pour INP.
          Requête prod 02/09/2026 ~15:25 Paris, events_human 28 j, `user_agent<>'pc'` :
            web_vitals par métrique : CLS n=3 940 (1 114 à valeur exactement 0, soit 28,3 %), INP n=7 178 (0
            zéro), LCP n=8 846 (0 zéro), TTFB n=10 390 (0 zéro).
          Décomposition par navigateur (paires session×path avec un LCP) :
            Chrome  n=4 434 → 3 174 avec CLS = **71,6 %** (identique au chiffre du constat)
            Safari  n=2 359 → **8** avec CLS = 0,34 % (n identique au constat)
            Firefox n=609   → **0** avec CLS (identique au constat)
            Edge    n=397   → 348 avec CLS = 87,7 %
          p75 CLS Chrome, paires porteuses d'un LCP : `percentile_cont(0.75)` sur les valeurs observées =
          **0,16** ; même percentile en réintégrant un CLS implicite de 0 pour les LCP sans CLS
          (`COALESCE(cls_val,0)`) = **0,12** → reproduction EXACTE du ratio de surestimation ~33 % annoncé
          (0,16/0,12).
Écart     Aucun sur le mécanisme ni sur les ordres de grandeur (Chrome 71,6 % et p75 0,16/0,12 reproduits à
          l'identique ; Safari/Firefox aux mêmes n). Légers écarts de volumes bruts (fenêtre glissante).
Invariant Manquant aujourd'hui (aucun test jsdom n'émet de CLS=0 explicite, aucune RPC ne porte un n minimal ou
          un périmètre navigateur) mais techniquement solide : un test jsdom vérifiant l'émission d'un 0 explicite
          fermerait le trou à la source, et un contrat de lecture avec dénominateur/n minimal est la même
          discipline que les grades A/B/C du CPI déjà en place ailleurs — pas décoratif si implémenté.
```

### a-04
```
ID        a-04
Verdict   CONFIRMÉ
Ma preuve Code relu, lignes exactes : `wix/tracker.html:422-424` —
            `function flushQ() { if (!queue.length) return; var batch = queue.splice(0, 50);
             transmit(JSON.stringify({ events: batch }));` — la file est bien vidée avant l'appel à transmit.
          `:405-420` — `transmit(body)` : `navigator.sendBeacon(...)` puis, en repli,
            `fetch(ENDPOINT, {method:'POST', keepalive:true, headers:{...}, body})` sans `.then`/`.catch` —
            confirmé, aucune lecture du statut HTTP, aucune gestion de rejet de promesse.
          `:395` — `CRITICAL = ' pageview page_exit cta_phone_click cta_booking_click cta_anchor_click
            click_internal click_outbound '` ; `:435-442` `send()` déclenche `flushQ()` immédiat si le nom est
            dans CRITICAL — confirmé, `cta_phone_click` emprunte le même chemin sans reprise.
          `wix/http-functions.js:51` (403 forbidden_origin), `:66` (400 si body > 60 000 car.), `:106` (500
            proxy_error) — les 3 points de rejet cités existent bien.
          Aucun `event_id` généré côté client (grep sur `tracker.html` : aucune occurrence d'un identifiant
          d'event distinct de anonymous_id/session_id).
Écart     Aucun — le code lu ligne à ligne confirme exactement la mécanique décrite (splice avant transmit,
          fetch sans callback, flush immédiat des critiques, 3 codes de rejet possibles).
Invariant Manquant. L'alerte « pipeline mort » (`cooked_alerts_refresh`, confirmée dans le registre freshness
          via 00-baseline.md) détecte 0 event/60min, pas une perte partielle (ex. -30 % du volume horaire
          habituel) — c'est exactement le mode de défaillance du batching, non couvert aujourd'hui.
```

### a-05
```
ID        a-05
Verdict   CONFIRMÉ
Ma preuve Reproduction indépendante du pipeline `minify-tracker.py` (jsmin) dans le scratchpad, SANS écrire dans
          le repo (aucun fichier `wix/tracker.min.html` créé/modifié) :
            source_len = 48 936 ; minified_len = **14 760** ; WIX_LIMIT = 15 000 ; marge = **240** (1,6 %).
          Spot-check de la trajectoire historique en rejouant jsmin sur 4 révisions git (`git show <rev>:
          wix/tracker.html`, aucun fichier écrit) : 5aab72a→14 649, 1ebe8fd→14 048, db3717d→13 823,
          b2c3caf→14 760 — les 4 valeurs reproduisent EXACTEMENT la table du constat.
          `scripts/minify-tracker.py:33` `WIX_LIMIT = 15_000`, `:63-67` `sys.exit(2)` si dépassement —
          confirmé par lecture. `tests/tracker.test.js:105` `ok(min.length <= 15000, ...)` — confirmé.
Écart     Aucun — reproduction exacte au caractère près, y compris sur 4 points de la trajectoire historique.
Invariant Tient pour le garde existant (exit 2 + assertion + CI, tous relus et confirmés aux lignes citées).
          Le seuil d'alerte anticipé proposé (ex. 14 250) n'existe pas encore mais est un simple changement de
          constante dans un mécanisme déjà fonctionnel — pas décoratif, immédiatement actionnable.
```

### a-06
```
ID        a-06
Verdict   CONFIRMÉ
Ma preuve Requête prod 02/09/2026 ~15:30 Paris, events_human 28 j, `user_agent <> 'pc'`, par nom d'event
          (`pct_title_null` / `pct_url_avec_ids` via `url ILIKE '%cooked_aid%'`) :
            pageview        n=11 878 → 98,8 % / 11,0 %
            engagement_tick n=97 965 →  0,1 % / 99,6 %
            page_exit       n=15 038 →  0,7 % / 99,2 %
            scroll_depth    n=10 956 →  0,1 % / 99,8 %
            web_vitals      n=30 358 → 34,1 % / 99,5 %
            cta_phone_click n=125    →  0,0 % / 100,0 %
          Reproduction quasi exacte du tableau du constat (pageview 98,8 % identique ; web_vitals 34,1 %
          identique ; page_exit 0,7 % identique ; engagement_tick 0,1 % identique).
          Code : `wix/tracker.html:466` `emitPageview()` appelé de façon synchrone tôt dans l'IIFE ; `:359-377`
          `basePayload()` lit `document.title` (`:366`) ; `:1128` `exposeIds()` en toute fin d'IIFE — ordre
          confirmé par lecture.
Écart     Aucun sur le mécanisme ni les pourcentages (reproduction quasi identique, écarts de arrondi <0,1 pt).
Invariant Manquant aujourd'hui (aucun test de contrat sur `pageview.title`). La proposition (test de contrat SI
          on garde la colonne, migration nommée SI on la supprime) est cohérente avec la règle du projet
          « un fix = une migration nommée » — pas décoratif si l'une des deux branches est exécutée, mais
          aujourd'hui ni l'une ni l'autre n'existe : le statu quo perdurera sans décision explicite.
```

### a-07
```
ID        a-07
Verdict   CONFIRMÉ (avec une inexactitude mineure de date, sans effet sur le fond)
Ma preuve Suite rejouée dans une copie scratchpad (jamais dans le repo) : lecture intégrale de
          `tests/tracker.test.js` (110 lignes) — confirme la couverture décrite (garde double-embed, 4 classes
          de clics, version stamp, exposition ids en query params, ré-exposition SPA, localStorage bloqué DÈS
          LE DÉPART (bloc `blockLocalStorage`, PAS un wipe en cours de page), format batch, active_ms/duration
          sur horloge simulée, taille du minifié). Le mock réseau (`window.fetch=function(u,o){...
          return Promise.resolve({ok:true})}`) résout TOUJOURS `{ok:true}` — confirmé, aucun scénario d'échec
          de transmit.
          `grep -n "healAid|_cachedSid" wix/tracker.html` → `healAid` défini `:251-257`, `_cachedSid` `:239` —
          aucune occurrence de ces symboles dans `tests/tracker.test.js` : le scénario de wipe-en-cours-de-page
          de sprint41 n'est effectivement jamais exercé.
          `.github/workflows/tracker-test.yml` lu en entier : `paths:` = `wix/tracker.html`,
          `tests/tracker.test.js`, `scripts/minify-tracker.py`, lui-même. `grep -l "http-functions|
          masterpage-cooked" .github/workflows/*.yml` → aucun résultat, confirmé : ces 2 fichiers ne sont dans
          les `paths:` d'aucun workflow.
          `gh run list --workflow=tracker-test.yml --limit 5` → dernier run 2026-07-12T20:27:41Z (12/07/2026
          22:27 Paris), succès — date confirmée.
          `git log --oneline -- wix/http-functions.js` → seuls `f8b42c1` et `ca50f26` touchent ce fichier ;
          `git show f8b42c1` → **`Date: Sat Jul 25 21:16:10 2026 +0200`**, PAS le 28/07/2026 annoncé par le
          constat.
Écart     Une seule inexactitude : le constat date le commit `f8b42c1` du 28/07/2026, il est en réalité du
          25/07/2026 (21:16 Paris). Le fond de l'affirmation (ce commit modifie `http-functions.js`, le
          workflow ne l'aurait de toute façon pas déclenché car le fichier n'est dans aucun `paths:`) reste
          exact quelle que soit la date exacte.
Invariant Manquant. Aucune assertion ne reproduit les 3 derniers correctifs majeurs (sprint39/40/41) ; aucun
          workflow ne surveille les fichiers Velo. La règle de contribution proposée (1 fix = 1 assertion
          rouge-avant/verte-après) est calquée sur une règle déjà en vigueur côté SQL (CLAUDE.md) — cohérente,
          pas décorative si adoptée, mais rien ne la fait respecter mécaniquement aujourd'hui (pas de gate CI).
```

### a-08
```
ID        a-08
Verdict   CONFIRMÉ
Ma preuve Code relu : `wix/http-functions.js:50` `const origin = (request.headers && (request.headers.origin ||
          request.headers.referer)) || '';` `:51` `if (!origin || !origin.startsWith(ALLOWED_ORIGIN))` → confirmé,
          `Origin` OU `Referer` acceptés, tous deux des en-têtes qu'un client HTTP quelconque pose librement ;
          absence d'en-tête → 403 (corrige bien l'hypothèse startsWith-sur-falsy, comme le dit le constat
          lui-même). `:66` limite à 60 000 caractères, aucune autre limite de débit/IP/session dans ce fichier
          (109 lignes lues en entier). `x-cooked-key` ajouté `:90` par le proxy lui-même, donc protège l'appel
          Velo→Edge, pas le public→Velo.
          `wix/masterpage-cooked.js:22` — `const COOKED_DEBUG = true; // passer à false une fois la chaîne
          vérifiée` — ligne exacte confirmée ; `:40`, `:51`, `:73` journalisent bien aid/sid/nb formulaires.
          Requête prod 02/09/2026 ~15:32 Paris, events_human 28 j (fenêtre glissante, donc 125 et non 128
          clics) :
            125 `cta_phone_click`, 125 avec une `pageview` antérieure (`occurred_at <=`) dans la même session
            → 125/125 = 100 %, aucun signe d'injection à cette date — cohérent avec le 128/128 du constat
            (différence de fenêtre uniquement).
Écart     Aucun sur le fond ; le nombre 125 vs 128 s'explique entièrement par la fenêtre glissante vs
          date-anchorée (même conclusion : 100 % avec amont).
Invariant Tient pour la détection proposée (alerte sur contact macro sans amont dans la même session — le
          mécanisme d'alertes existe déjà et peut porter une règle supplémentaire). Le grep CI anti-`DEBUG=true`
          est mécaniquement solide s'il est ajouté, mais n'existe pas aujourd'hui. Le franchissement lui-même
          (en-tête forgé) reste un fait de code non démontré en conditions réelles — cohérent avec le statut
          [non recoupé] du constat, que je confirme : aucune tentative d'injection n'a été faite (interdit en
          lecture seule).
```

---

## Synthèse

- a-01 · CONFIRMÉ · bot Baidu confirmé en prod (14,1 %/17,5 % ma fenêtre) + views.sql/rpcs.sql prod sans filtre.
- a-02 · CONFIRMÉ · desktop hors bot = 95,3 % (mieux couvert), déficit réel = mobile ; reproduction indépendante.
- a-03 · CONFIRMÉ · Chrome 71,6 %, Safari n=8, Firefox n=0, p75 0,16→0,12 reproduits à l'identique.
- a-04 · CONFIRMÉ · splice avant transmit, fetch sans callback, flush critique immédiat — code relu ligne à ligne.
- a-05 · CONFIRMÉ · 14 760/15 000 (marge 240) reproduit au caractère près, trajectoire historique vérifiée sur 4 points.
- a-06 · CONFIRMÉ · title NULL 98,8 % pageview reproduit à l'identique, ordonnancement du code confirmé.
- a-07 · CONFIRMÉ (1 date fausse : f8b42c1 = 25/07, pas 28/07, sans effet sur le fond) · couverture de test et paths CI confirmés.
- a-08 · CONFIRMÉ · garde Origin/Referer forgeable + COOKED_DEBUG=true confirmés ligne à ligne ; 125/125 amont (fenêtre différente de 128/128, même conclusion).

Recopiés/reçus : 8/8. Aucun constat non testable — les 8 ont reçu une preuve indépendante (requête prod
ré-exécutée avec horodatage Paris, ou fichier:ligne relu par moi, ou reproduction locale hors-repo du pipeline
de minification). Aucun constat n'est réfuté ni partiel : les 8 tiennent tels quels, aux écarts de fenêtre
temporelle près (jamais de sens contraire) et à une seule date de commit erronée (a-07, sans conséquence sur le
diagnostic). Aucune action d'écriture, aucune fonction sensible appelée, aucune PII lue au-delà des structures/
agrégats déjà présents dans les constats eux-mêmes.
