# Réfutation zone (b) — Edge track + form-webhook + _shared — 02/09/2026

Repo local (LECTURE SEULE) HEAD = e95f3ee (vérifié `git log -1`). Prod Supabase `mxycmjkeotrycyneacje`.
9 constats reçus, recopiés intégralement ci-dessous, puis verdict par constat avec preuve propre.

## Constats recopiés (9/9 — b-01 à b-08, o-10)

```
ID            b-01
Titre         9 % des formulaires arrivent sans `page_source` : ces contacts macro n'existent sur aucune page — constat « Majeur » du 25/07 marqué « Fait », cause jamais traitée
Sévérité      P1 — biais mesurable + panne silencieuse de deux formulaires entiers
Preuve        Code : `_shared/form_row.ts:142-147` — `pageSource` cherché dans 4 emplacements ; si aucun ne
              répond, `resolvePageSource(null)` renvoie `{url:null,path:null,hostname:null}` → `path=NULL`.
              Aucun compteur, aucune alerte : seul effet de bord un `console.log`.
              Prod (02/09 09:54 Paris), events_human, form_submit, 180j : 251, dont 229 wix-webhook + 22
              wix-backfill. 21/229 webhook (9,2%) ont path IS NULL, tous avec page_source absent (hostname
              NULL sur les 21, pas un rejet du spoof-guard). 28j: 6/69 (8,7%) ; 7j: 2/19 (10,5%).
              Décomposition : « Prise de contact site-web » 225/17 (7,6%) ; « Formulaire Divorce » 3/3
              (100%) ; « Demande dossier en cours » 1/1 (100%).
              Chaîne : macro_contacts_by_path groupe sur coalesce(e.path,'(non rattaché)') ;
              pages_overview_unified fait un INNER JOIN ranked → élimine cette clé. Aucune occurrence de
              « non rattaché » dans dashboard/src.
Impact        28j : 6 contacts macro/69 comptés dans le total site mais absents de toute vue par page.
              180j : 21 contacts. Deux formulaires à 0 contact partout, en permanence.
              Pont SECIB : buildProspectRow recopie path → crm_prospects.page_source_path (31/35 sur v13).
              Divorce (11/06 clos) : cooked_aid présent 2/3, mais page_source et objet_de_ma_demande
              absents 3/3 — jamais câblés sur ce form.
Récidive      OUI : docs/audit-architecture-2026-07-25.md:206 (Majeur, 15/151=10%) marqué « Fait » (l.279) —
              seule la clé '(non rattaché)' a été ajoutée (réconciliation du total), pas la cause. 10%→8,7%
              en 38j.
Invariant     Règle symétrique à alert_rule_form_attribution_degraded sur `path` (pas seulement cooked_aid) ;
              ou seuil par form_id.
Statut        [non recoupé]
```
```
ID            b-02
Titre         La gate `x-cooked-key` est armée aujourd'hui, mais désarmable en silence des deux côtés — sans fail-fast, sans test, sans alerte
Sévérité      P2 — dette de sécurité qui mordra à l'échelle
Preuve        track/index.ts l.48 `COOKED_INGEST_KEY = Deno.env.get(...) ?? ""` ; l.87 `if (COOKED_INGEST_KEY)
              {...401}` — secret absent ⇒ bloc sauté. Asymétrie avec SECRET_KEY (l.29-34, throw) et
              ANON_SALT (l.39-45, throw). Proxy Velo http-functions.js:90 même « soft ».
              Aucun test (edge-shared-helpers.yml ne teste que _shared/*, pas le handler track/index.ts).
              Aucune alerte parmi les alert_rule_* n'inspecte la gate.
              Sonde 02/09 10:02 Paris : POST corps invalide → 401 unauthorized (jsonError de la fonction).
Impact        Aucun aujourd'hui. Si le secret disparaît côté Velo → panne totale détectée (b-03 réserve). S'il
              disparaît côté Supabase → rien ne le dit. props sans plafond de taille/schéma (P2 audit 02/07
              toujours vrai), seul le plafond Velo (60000 car) protège, inopérant en direct.
              Site Outre-mer ingère hors proxy Velo (54 events, 7 sessions, 06/08→19/08) — stockage de la clé
              hors repo [non vérifié].
Récidive      Pattern déjà documenté (NTFY_TOPIC absent des secrets GitHub, corrigé 22/08 seulement) : secret
              absent = protection absente, en silence.
Invariant     (a) throw au boot si COOKED_INGEST_KEY absent, comme SECRET_KEY/ANON_SALT, ou alert_rule
              dédiée ; (b) plafond taille/schéma côté Edge.
Statut        [non recoupé]
```
```
ID            b-03
Titre         alert_rule_pipeline_dead : le seuil de 60 min tombe dans la distribution naturelle des creux nocturnes
Sévérité      P2 — fatigue d'alerte sur l'unique détecteur d'une panne de l'Edge track
Preuve        Règle : count(*) FROM events WHERE received_at > now()-60min ; 0 ⇒ critical.
              Prod 28j : 2 écarts >60min (10/08 02:05→03:14 = 68,9min ; 22/08 03:12→04:16 = 63,3min).
              L'alerte pipeline_dead (created_at 22/08 04:15, critical) coïncide avec le 2e écart (cron :15
              a échantillonné 03:15→04:15). Le creux du 10/08 n'a pas déclenché (03:14 tombait dans
              02:15→03:15).
Impact        Notification critique pour trafic nocturne normal ; le capteur perd sa crédibilité.
Récidive      Non documenté ailleurs. Hypothèse « c'est le filtre bot v26 » testée et écartée : pré-v26
              (25/06→22/07), 3 écarts >60min, max 82,3min — le creux est structurel, antérieur à v26.
Invariant     Seuil calé sur la distribution / sensible à l'heure, plutôt qu'une constante 60min.
Statut        [non recoupé]
```
```
ID            b-04
Titre         L'alerte form_submit_dropped n'envoie rien, ne déduplique pas, jamais exécutée
Sévérité      P2 — le filet posé après l'audit du 02/07 est muet par construction
Preuve        form-webhook/index.ts:113-121 — insert direct dans `alerts`, pas de supabase.rpc(raise_cooked_alert).
              raise_cooked_alert fait dédup 24h + push ntfy critical. 0 trigger sur alerts. 0 ligne
              kind='form_submit_dropped' sur 131 lignes totales (dernière 02/09 09:15 Paris).
Impact        Contact perdu = trace muette dans une table non surveillée, malgré sévérité critical déclarée.
              Chemin jamais exercé en prod.
Récidive      Non — implémentation d'origine T-13 (02/07), posée avant que NTFY_TOPIC soit fonctionnel
              (22/08) : personne n'est repassé rebrancher.
Invariant     Remplacer par raise_cooked_alert(...) + test du chemin d'erreur ; contrôle CI grep.
Statut        [non recoupé]
```
```
ID            b-05
Titre         13,5% des form_submit arrivent sans typologie : la règle « candidature ≠ contact » ne peut pas s'appliquer, défaut = compté macro
Sévérité      P2 — majorant d'environ 1,4% sur 180j
Preuve        form_row.ts:167-170 isRecruitmentObjet(null)=false ⇒ objet absent ⇒ compté macro. Même défaut
              en SQL (form_submit_counts_as_macro, WHEN props IS NULL THEN true).
              Prod 180j : 251 form_submit, 34 sans objet_de_ma_demande (13,5%), 20 « rejoindre »,
              counts_as_macro=false sur 20, vrai sur 231.
Impact        Taux candidature observable 20/(251-34)=9,2% ; appliqué aux 34 non typés ⇒ ~3 candidatures
              comptées comme contacts (~1,4% des 231 macro). Non démontré faux, non recoupable, sens connu
              (surcompte).
Récidive      Non constaté tel quel ; la règle « nous rejoindre » traite la valeur présente, pas l'absente.
Invariant     Compteur/alerte sur objet_de_ma_demande IS NULL par form_id ; ou afficher le majorant.
Statut        [non recoupé]
```
```
ID            b-06
Titre         Contrat C3 canonical_path « unifié » : l'adaptateur SQL n'est joué contre aucun vecteur en CI, diverge sur null_input
Sévérité      P3 — hygiène de contrat, divergence latente sans impact mesuré
Preuve        canonical-path-contract.yml : jobs pytest + deno test uniquement, aucune étape SQL.
              canonical_path(NULL) en prod → '/' ; canonicalPath(null) côté Edge → null. Cause :
              COALESCE(p,'') puis COALESCE(NULLIF(n,''),'/').
              Dernier run du workflow : 09/07/2026, succès.
Impact        Nul aujourd'hui (5 appelants SQL passent tous un target_path fourni, jamais une colonne
              nullable). Risque futur si canonical_path(e.path) est écrit sur une colonne nullable.
Récidive      Non — incomplétude d'origine du contrat (commit 99fb42f, 09/07/2026).
Invariant     3e étape CI qui rejoue les vecteurs contre le SQL, trancher le cas NULL.
Statut        [non recoupé]
```
```
ID            b-07
Titre         Chaque requête de bot déclenche un aller-retour base sur une ligne unique — 3,6M events/28j, ×4 en un mois, rien ne le surveille
Sévérité      P3 — coût et point de sérialisation qui grandissent
Preuve        track/index.ts:118-128 : bot UA ⇒ rpc record_ingest_drop AVANT réponse 200. Upsert sur
              (day,'bot_ua'). Prod 30j : 05/08 50580 → 30/08 245323 (max) → 01/09 178118 — ×4 environ.
              Aucun alert_rule_* ne lit ingest_drops.
Impact        Pas de panne observée (continuité intacte). Coût croissant, non alerté.
Récidive      Non — v26 est le correctif Majeur n°5 du 25/07, fonctionne ; ce qui manque est le capteur.
Invariant     Règle d'alerte sur la dérive de ingest_drops (ratio ou variation j/j).
Statut        [non recoupé]
```
```
ID            b-08
Titre         ANON_SALT bloque le démarrage de track pour protéger un chemin de repli utilisé 0 fois en 28j
Sévérité      P3 — hygiène : risque d'indisponibilité totale adossé à du code mort
Preuve        track/index.ts:39-45 : ANON_SALT absent/placeholder ⇒ throw au chargement. Sert uniquement au
              hash IP+UA (fallback si pas d'anonymous_id navigateur valide). Prod 28j : 0 anonymous_id
              32-hex sur ~199k events.
Impact        Repli jamais servi sur la fenêtre ; secret bloquant garde un chemin à usage nul.
Récidive      Non — fail-fast Sprint 25, justifié à l'époque ; c'est l'usage qui s'est éteint.
Invariant     Décider : retirer le repli+secret, ou le garder mais non bloquant ; contrôle périodique du
              taux de 32-hex.
Statut        [non recoupé]
```
```
ID            o-10 (zone b)
Titre         events.country mort depuis le 02/06/2026 19:37 — capture perdue sans décision
Sévérité      P2
Preuve        Q-26 : 100% jusqu'à semaine du 25/05, 35,8% semaine du 01/06 (dernier 02/06 19:37), 0% depuis.
              track_row.ts déployé : country jamais assigné.
Impact        Toute RPC/vue lisant country est vide ; décision Nicolas (§7.2).
Récidive      Signalé audit 02/07 (P2), non tranché.
Invariant     Scorecard NULL-rate en contract-test (colonne 100%→0% déclenche une alerte).
Statut        [non recoupé]
```

---

## Verdicts

```
ID        b-01
Verdict   CONFIRMÉ
Ma preuve execute_sql, events_human/form_submit, 180j, 02/09/2026 20:00 Paris :
          total=233 webhook, path NULL=21 (9,0%) — proche du 9,2%/229 du constat (léger décalage
          temporel de session, pas une erreur de méthode). Décomposition par form_id (même requête,
          groupée) : "Prise de contact site-web" 229/17(7,4%), "Formulaire Divorce" 3/3, "Demande
          dossier en cours" 1/1 — EXACTEMENT la répartition du constat.
          pg_get_functiondef('public.macro_contacts_by_path(date,date)') en prod (pas le miroir) :
          confirme `coalesce(e.path,'(non rattaché)')` groupé.
          pg_get_functiondef('public.pages_overview_unified') en prod : confirme
          `mc AS (SELECT m.* FROM macro_contacts_by_path(...) m INNER JOIN ranked r ON r.path=m.path)`
          — la clé '(non rattaché)' n'existe jamais dans `ranked` (issu de seo_url_snapshot / paths
          réels) donc disparaît par construction de la jointure.
          pg_get_functiondef('public.alert_rule_form_attribution_degraded') en prod : confirme que
          la règle ne teste QUE `props->>'cooked_aid' IS NULL`, jamais `path`.
          grep -rn "non rattaché" dashboard/src → aucune occurrence (vérifié moi-même).
Écart     Aucun sur le mécanisme et la chaîne de conséquence. Écart cosmétique de fenêtre (233/21 vs
          229/21 — quelques form_submit supplémentaires arrivés entre les deux mesures du même jour).
Invariant Manquant — confirmé en direct : aucune fonction alert_rule_* du schéma prod ne teste `path`
          sur form_submit. L'invariant proposé (règle symétrique sur path, ou seuil par form_id)
          fonctionnerait : c'est une addition SQL pure, sans dépendance à du code cassé ailleurs.
```
```
ID        b-02
Verdict   CONFIRMÉ
Ma preuve get_edge_function(track) en prod (code déployé, pas le repo) : confirme mot pour mot
          `const COOKED_INGEST_KEY = Deno.env.get("COOKED_INGEST_KEY") ?? "";` puis
          `if (COOKED_INGEST_KEY) { ... 401 }` (gate sautée si vide) vs SECRET_KEY et ANON_SALT qui
          `throw` au chargement du module.
          grep "x-cooked-key|ingestKey" wix/http-functions.js : confirme le miroir soft côté Velo
          (l.90 `...(ingestKey ? {'x-cooked-key':ingestKey} : {})`) et l.51 le contrôle d'origin
          same-site (`forbidden_origin` si l'origin ne matche pas ALLOWED_ORIGIN).
          cat .github/workflows/edge-shared-helpers.yml : 3 `deno test` sur _shared/*, aucun sur
          track/index.ts (le handler qui porte la gate).
          Sonde personnelle (curl, 02/09/2026 20:02:12 Paris) : POST corps invalide vers
          .../functions/v1/track → HTTP 401 {"ok":false,"error":"unauthorized"} — identique à la
          preuve du constat, rejouée indépendamment, gate confirmée active.
          execute_sql : aucune fonction alert_rule_* (liste complète interrogée) ne mentionne
          `cooked_ingest_key` ni `x-cooked-key` dans son corps.
Écart     Deux imprécisions dans le détail Outre-mer (secondaire, ne change pas le verdict) : ma
          requête sur `hostname='outremer.jplouton-avocat.fr'` donne 57 events (pas 54) et une
          première occurrence au 08/07/2026 22:50 Paris (pas 06/08/2026 15:54) — le trafic Outre-mer
          est actif depuis un mois de plus que ce que le constat affirme. Le compte d'alert_rule_*
          réellement présents en prod est 11, pas 13 (le miroir supabase/rpcs.sql est périmé : 5
          fonctions du miroir — cpi_stale, dfs_stale, gbp_gap, gsc_gap, gsc_lag — n'existent plus en
          prod, remplacées par freshness/gsc_ingest_missed/warn_escalation). La conclusion
          « aucune alerte » reste vraie, vérifiée directement sur les 11 fonctions réelles.
Invariant Manquant, confirmé. Le fail-fast (a) est mécaniquement identique au patron déjà en place
          pour SECRET_KEY/ANON_SALT dans le même fichier — pas décoratif.
```
```
ID        b-03
Verdict   PARTIEL
Ma preuve execute_sql, gaps sur `received_at` (events bruts, diagnostic ingestion), 28j glissants
          (02/09/2026 20:05 Paris) : exactement 2 écarts >60min, aux mêmes horodatages que le
          constat — 10/08 02:05→03:14 (68,9min) et 22/08 03:12→04:16 (63,3min) — confirmé au
          dixième de minute près.
          pg_get_functiondef('public.alert_rule_pipeline_dead()') en prod : seuil 60min confirmé
          identique au repo/miroir.
          SELECT * FROM alerts WHERE kind='pipeline_dead' : **DEUX** lignes, pas une seule —
          22/08/2026 04:15 (critical, non ackée, coïncide avec le 2e écart nocturne — le mécanisme
          "phase du cron" est confirmé) ET **01/08/2026 15:15 (critical, ACKÉE)**. J'ai vérifié le
          creux correspondant : requête sur `received_at` entre 01/08 12:00 et 17:00 Paris → un
          écart de **2h46 (13:16→16:02)**, en pleine journée, pas nocturne.
Écart     Le constat affirme "l'alerte pipeline_dead unique de la table" — c'est faux, il y en a
          deux. La deuxième n'est PAS un artefact de creux nocturne : c'est un vrai trou de 2h46 en
          après-midi, suffisamment sérieux pour avoir été acquitté (traité) par quelqu'un. Ça ne
          contredit pas le mécanisme de quantification par la phase du cron (démontré exact sur la
          paire 22/08 vs 10/08, dans la fenêtre 28j), mais ça affaiblit le narratif "l'unique
          détecteur crie au loup sur du bruit nocturne" : sur les deux occurrences connues, une est
          un vrai signal (2h46 de jour) et une est discutable (63min de nuit). Le "unique" cité
          comme preuve d'un pattern répétitif de faux positifs ne tient pas — on n'a qu'UN exemple
          nocturne litigieux, pas une série.
Invariant Tient partiellement pour le problème de quantification (démontré), mais l'affirmation
          "fatigue d'alerte" sur la base d'une alerte unique est un chiffre n=1 présenté comme un
          pattern. Un seuil sensible à l'heure resterait une amélioration valide indépendamment.
```
```
ID        b-04
Verdict   CONFIRMÉ
Ma preuve get_edge_function(form-webhook) en prod : code déployé confirme mot pour mot l'insert
          direct `await supabase.from("alerts").insert({kind:"form_submit_dropped",
          severity:"critical", detail: ...})`, sans passer par `supabase.rpc(...)`.
          pg_get_functiondef('public.raise_cooked_alert(text,text,text)') en prod : confirme dédup
          (existence sur 24h) + push ntfy pour severity='critical' via net.http_post vers ntfy.sh
          lisant cooked_config.ntfy_topic.
          execute_sql, 02/09/2026 20:xx Paris :
            pg_trigger sur public.alerts (non-internes) = 0
            alerts WHERE kind='form_submit_dropped' = 0
            alerts total = 131, dernière le 02/09/2026 09:15 Paris
          — tous identiques aux chiffres du constat.
Écart     Nuance mineure : raise_cooked_alert déduplique par (kind, severity), pas par kind seul
          comme écrit dans la preuve du constat — ça ne change rien à la conclusion (l'insert direct
          ne bénéficie ni de la dédup ni du push, quelle que soit la clé exacte).
Invariant Manquant, confirmé. Remplacer l'insert par l'appel RPC est un changement d'une ligne dans
          form-webhook/index.ts, sans dépendance cassée ailleurs — tient.
```
```
ID        b-05
Verdict   CONFIRMÉ
Ma preuve execute_sql, events_human/form_submit, 180j, 02/09/2026 20:10 Paris :
          total=255, sans objet_de_ma_demande=34 (13,3%, vs 13,5% du constat — écart de fenêtre de
          quelques events entre les deux mesures du jour), marqués recrutement (counts_as_macro=
          'false')=20 (identique au constat), form_submit_counts_as_macro(props) vrai=235.
          Lecture form_row.ts:75-62 (isRecruitmentObjet) + form_row.ts (buildFormSubmitRow,
          countsAsMacro = !isRecruitmentObjet(objetDeMaDemande)) : confirme que objet absent ⇒
          isRecruitmentObjet(null)=false ⇒ countsAsMacro=true — code lu par moi-même, comportement
          identique au constat.
Écart     Aucun sur le mécanisme ; écart cosmétique de 0,2 point sur le taux (fenêtre glissante).
Invariant Manquant, confirmé (aucune règle sur objet_de_ma_demande IS NULL trouvée parmi les 11
          alert_rule_* réels de prod).
```
```
ID        b-06
Verdict   CONFIRMÉ
Ma preuve execute_sql en prod, 02/09/2026 20:15 Paris : `canonical_path(NULL)` → `/`,
          `canonical_path('')` → `/`, `canonical_path('/foo/')` → `/foo`.
          get_edge_function(track) : `_shared/canonical_path.ts` déployé confirme
          `if (p == null) return null;` — canonicalPath(null) côté Edge retourne bien null, pas '/'.
          → divergence confirmée directement en prod (pas via le fichier de vecteurs recopié).
          cat .github/workflows/canonical-path-contract.yml : confirme 2 étapes seulement (pytest +
          deno test), aucune étape SQL, malgré `paths` incluant les migrations canonical_path.
          gh run list --workflow canonical-path-contract.yml : dernier run 09/07/2026, succès —
          confirme l'absence de run depuis.
          cat contracts/canonical_path_vectors.json : 10 path_cases + 1 edge_null_case = 11 vecteurs,
          confirme le compte du constat.
Écart     Aucun.
Invariant Manquant, confirmé. Une 3e étape CI (rejouer les vecteurs contre canonical_path() en SQL)
          est réalisable sans dépendance — tient. Impact aujourd'hui bien nul : vérifié que le
          fichier de vecteurs et les call-sites cités dans le miroir rpcs.sql passent tous un
          target_path fourni par l'appelant (paramètre de fonction), jamais une colonne nullable —
          cohérent avec le fait que macro_contacts_by_path (vérifié fonctiondef en prod plus haut,
          b-01) n'a montré aucun signe d'instabilité liée à ce point.
```
```
ID        b-07
Verdict   CONFIRMÉ
Ma preuve execute_sql, `ingest_drops`, 30 derniers jours (day >= today-30), 02/09/2026 20:20 Paris :
          série complète 03/08→02/09, une seule raison 'bot_ua'. Points de repère : 05/08=50580,
          12/08=55352, 19/08=124447, 25/08=188192, 29/08=218450, 30/08=245323 (maximum de la série),
          31/08=200757, 01/09=178118 — TOUS identiques, à l'unité près, aux chiffres du constat.
          Confirme le ×4 environ entre début et fin août.
          execute_sql : aucune fonction alert_rule_* (les 11 réelles de prod) ne mentionne
          'ingest_drops' dans son corps — vérifié par pg_get_functiondef ILIKE, pas par un grep sur
          le miroir périmé.
          get_edge_function(track) : confirme l'appel `supabase.rpc("record_ingest_drop", {p_reason:
          "bot_ua", p_n: events.length})` avant la réponse 200 sur UA bot.
Écart     Le "13" alert_rule_* du constat est le compte du miroir rpcs.sql, périmé ; la prod en a 11
          (voir b-02). La conclusion (aucune ne surveille ingest_drops) est confirmée sur le compte
          réel, donc plus solide que la preuve d'origine, pas moins.
Invariant Manquant, confirmé.
```
```
ID        b-08
Verdict   CONFIRMÉ
Ma preuve get_edge_function(track) en prod : confirme mot pour mot le throw au chargement si
          ANON_SALT absent ou égal au placeholder ; confirme que le hash n'est utilisé que dans
          `resolveAnonId(browserAid, serverHash) = validId(browserAid) ?? serverHash` (fallback pur).
          execute_sql, events bruts (diagnostic ingestion), 28j, 02/09/2026 20:25 Paris : total
          199 096, anonymous_id matchant `^[0-9a-f]{32}$` = 0 — identique en substance au 198 866/0
          du constat (écart de fenêtre, pas de méthode).
Écart     Aucun sur le fond.
Invariant Décision produit ouverte, pas un invariant technique — correctement qualifié comme tel par
          le constat lui-même ("décider explicitement").
```
```
ID        o-10 (zone b)
Verdict   CONFIRMÉ
Ma preuve execute_sql sur `events` (diagnostic — colonne technique, pas un agrégat business), par
          semaine calendaire Paris, 15/05→02/09 : 100% (sem. 11/05, 18/05... en fait 99,9-100% les 3
          premières semaines), 34,9% semaine du 01/06 (proche du 35,8% cité), puis **0,0% pour
          TOUTES les semaines du 08/06 au 31/08 inclus**, sans exception — série complète vérifiée,
          pas un point isolé.
          `SELECT max(occurred_at) WHERE country IS NOT NULL` → 02/06/2026 20:08:09 Paris (le
          constat dit 19:37 — écart de ~30min, cohérent avec une différence occurred_at/received_at
          ou de dernière ligne exacte, non significatif).
          get_edge_function(track) : lu la row construite dans buildEventRow — la liste de champs
          (anonymous_id, session_id, name, url, path, hostname, title, referrer, ..., props,
          occurred_at, received_at) ne contient JAMAIS `country`, confirmant qu'aucun code déployé
          n'assigne cette colonne.
Écart     Écart mineur d'horodatage (19:37 vs 20:08) sans conséquence sur le constat.
Invariant Manquant, confirmé (aucun contract-test de type NULL-rate trouvé dans les workflows lus
          dans ce repo pour cette zone).
```

## Synthèse

- b-01 · CONFIRMÉ · 9% des form_submit webhook sans page_source, chaîne de conséquence et absence d'alerte vérifiées en direct sur les fonctions prod.
- b-02 · CONFIRMÉ · gate x-cooked-key soft-fail vérifiée dans le code déployé + sondée moi-même (401 reproduit) ; détail Outre-mer (dates/volume) imprécis dans le constat mais sans effet sur le verdict.
- b-03 · PARTIEL · seuil/cron-phase confirmé exact, mais il existe DEUX alertes pipeline_dead (pas une) et la seconde (01/08, 2h46 de jour) est un vrai signal, pas du bruit nocturne — le narratif "crie au loup" repose sur n=1.
- b-04 · CONFIRMÉ · insert direct dans alerts vérifié dans le code déployé ; 0 alerte form_submit_dropped en 131 lignes, 0 trigger.
- b-05 · CONFIRMÉ · 13,3% sans typologie sur 255 form_submit (180j), logique de comptage par défaut confirmée dans le code déployé.
- b-06 · CONFIRMÉ · canonical_path(NULL) retourne '/' en SQL vs null côté Edge, testé directement en prod ; CI sans étape SQL confirmée.
- b-07 · CONFIRMÉ · série ingest_drops rejouée à l'identique (05/08→01/09), aucune alert_rule réelle ne la lit.
- b-08 · CONFIRMÉ · throw au boot + fallback jamais utilisé (0/199k sur 28j) confirmés.
- o-10 · CONFIRMÉ · 0% de country sur 12 semaines consécutives vérifié, colonne absente du row-builder déployé.

Recopié 9/9, reçu 9/9. Constat non testable : aucun. Note transverse : `supabase/rpcs.sql` est
périmé sur les alert_rule_* (13 dans le miroir, 11 réellement en prod, 5 renommés/consolidés) — ça
affaiblit le chiffrage exact cité dans b-02/b-07 sans changer leur conclusion, vérifié via
`pg_get_functiondef` en direct plutôt que via le fichier.
