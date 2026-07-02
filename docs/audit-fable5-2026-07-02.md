# Audit Fable 5 — 02/07/2026 : état du système + cap « Cooked next level »

> Audit multi-agents mené les 01-02/07/2026 : 8 auditeurs de zone (tracker,
> edge, SQL, données live, CPI, dashboard, ops, docs) + vérification
> adversariale de chaque finding P0/P1 + 2 agents de recherche (état de
> l'art externe, gisements internes). **Tout en lecture seule** — aucune
> écriture en prod, aucun fix appliqué. Chaque finding porte une preuve
> (code:ligne ou SQL prod reproduit). Les findings dont la contre-vérification
> adversariale n'a pas pu tourner (limite de session) sont marqués
> **[non recoupé]** — la preuve de l'auditeur existe, mais un second agent
> ne l'a pas reproduite indépendamment.

---

## Verdict global

Le système est **sain dans ses fondations** : Edge Functions déployées =
repo (zéro dérive), CPI prod conforme à sa doc au symbole près, tracker
sprint38 sans bug majeur de capture, dashboard étanche (clé service
server-only, auth fail-closed), 0 trou d'ingestion tracker sur 14j,
migrations en miroir exact repo/prod depuis le 10/06.

Mais l'audit a trouvé **2 P0 confirmés**, **une grappe de P1** dont un
événement en cours (swarm de bots), et **un défaut de conception dans le
protocole de validation CPI à corriger avant le 08/07**.

---

## Les 2 alertes actives — instruites

### `cpi_drop` (29/06 → 01/07, 3 occurrences) → ARTEFACT, pas un decay [non recoupé]

`cpi_daily` a un trou du 22/06 au 28/06 (gel du cron CPI). `cpi_movers`
compare donc le 01/07 au **21/06** (10 jours au lieu de ~7), et la chute
de ~55-60 pts des 4 pages (DDSE, ONIAM, délai-déraisonnable,
abus-de-confiance) est portée à ~90 % par le terme conversion `zv`
(+2,2/+3,0 → −3,0) : des assists sortis d'un coup de la fenêtre 28j
pendant le gel. Le GSC réel de ces pages est **stable** — aucun decay SEO.
C'est précisément le faux positif que la recalibration S39 devait éliminer,
réintroduit par l'écart de 10 jours.

**Action** : acker les alertes id 28, 30, 31 ; ne rien toucher aux 4 pages ;
durcir `cpi_drop` (ignorer ou normaliser si `ecart_jours > 8`, afficher la
part du delta due à `zv` dans le message).

### `form_attribution_degraded` (32 % sans `cooked_aid`) → un formulaire précis [non recoupé]

Sur 14j (17/06→01/07, 46 form_submit) : 9 non attribués, dont **8 avec
TOUS les champs cachés vides (`page_source` inclus)**, concentrés sur
l'objet « Droit et accidents du travail ». Ce n'est ni le tracker ni le
webhook : c'est **l'embed du formulaire de
`/indemnisation-des-victimes/droit-et-accidents-du-travail` qui n'a pas
les 3 champs cachés**. Le 9e cas est le résiduel attendu (~5 %).
Domaine indemnisation = valeur FORTE : ~20 % des contacts form perdent
leur journey.

**Action (Wix, Nicolas)** : ajouter `page_source`, `cooked_aid`,
`cooked_sid` à ce formulaire (même mécanique que le 11/06). Au passage :
le Formulaire Divorce n'a **aucune soumission depuis le 11/06** — la
vérification reste pendante.

---

## P0 — confirmés par vérification adversariale

### P0-1 · Trou GSC systématique au dernier jour de chaque mois **[CONFIRMÉ ×3 agents]**

- **Constat prod** : `2026-05-31` absent des 3 tables `gsc_*` (anti-join
  `generate_series` : seul jour manquant de l'historique) ; `max(day)` =
  29/06 au 02/07 alors que le cron a tourné les 01-02/07 → **le 30/06 est
  en train d'être perdu**.
- **Cause** : `scripts/gsc_common.py:113-128` — `list_months()` fait
  `cursor = end.replace(day=1)` : avec `--months 1`, la fenêtre va du
  **1er du mois de end_date** à end_date (mois calendaire, PAS 30 jours
  glissants). Le run du 02/07 (end 01/07) ne couvre que le 01/07 : plus
  aucun run ne retouche juin. Combiné au lag J-2/J-3 (`dataState:'final'`),
  les 1-2 derniers jours de chaque mois tombent dans le trou. Le
  commentaire du workflow (« ≈30 jours ») confirme le bug vs l'intention.
- **Impact** : tout chiffre GSC sur fenêtre chevauchant une fin de mois
  sous-compte en silence (KPIs mensuels, 28v28, capture CPI, funnel SEO).
  L'alerte `gsc_lag` (basée sur `max(day)`) est structurellement aveugle
  aux trous intérieurs.
- **Fix** :
  1. Backfill immédiat (récupérable, Google garde 16 mois) :
     `python3 scripts/gsc_ingest.py path-query --end-date 2026-06-30 --months 2`
     + idem `query-page` (ou relance manuelle du workflow avec `--months 2`).
  2. Durable : `--months 2` dans `gsc-daily-ingest.yml` (coût API
     négligeable) ou vraie fenêtre glissante (end − 35 j) dans `list_months`.
  3. Check `gsc_gap` (anti-join sur 90 j) dans `cooked_alerts_refresh()`.

### P0-2 · Vue `cpi_gisement` lisible par le rôle `anon` sans authentification **[CONFIRMÉ]**

- **Constat** : advisor Supabase security **level=ERROR** (« SECURITY
  DEFINER view ») + `GRANT SELECT` à `anon`/`authenticated` (absent des
  autres vues) — testé : 166 lignes du snapshot CPI lisibles via PostgREST
  avec la seule clé publishable embarquée dans le dashboard.
- **Impact** : pas de PII, mais scores santé / potentiel / conversion par
  page = intelligence business exposée publiquement.
- **Fix** (migration, 2 lignes) :
  `ALTER VIEW public.cpi_gisement SET (security_invoker = true);`
  `REVOKE ALL ON public.cpi_gisement FROM anon, authenticated;`
  (le dashboard lit via clé service — rien ne casse). En profiter pour
  revoker les grants DML résiduels d'`anon`/`authenticated` et les GRANT
  complets restés sur `dashboard_trend_snapshot`.

---

## P1 — les 7 qui comptent

### P1-1 · Swarm de bots EN COURS depuis ~20/06 : `events` ×2 en 11 jours [non recoupé]

12-15k events bruts/jour début juin → **69 398 le 01/07**, pendant
qu'`events_human` reste stable (~10-11k/j). Taux de filtrage 77-84 %
(vs 15-20 % documenté). Signature : UA desktop Chrome Windows, ~12k
`anonymous_id`/jour, vitals/ticks/exits **sans pageview**. La table
`events` est passée à **1,03 M lignes / ~1 Go**. Les chiffres business
restent propres (le filet tient), mais : (a) c'est la cause vraisemblable
du gel du cron CPI du 22-28/06 (et la récidive des timeouts nocturnes est
mécanique si ça continue) ; (b) rien de tout ça n'est documenté (le README
du 30/06 dit encore « ~390k events », « bruit 15-20 % »).
**Fix** : bloquer en amont (Edge : rejeter/échantillonner les non-pageview
de sessions sans pageview préalable, ou rate-limit Velo), prévoir purge des
events bruts filtrés, documenter le phénomène.

### P1-2 · `refresh_bot_fingerprints` scanne TOUT `events` sans borne temporelle **[CONFIRMÉ]**

À chaque run horaire, full-scan de 1,03 M lignes (11 échecs cron en 7j
avant le fix du 01/07 ; durée +14 %/36h). Chaque échec laisse le bruit non
flaggé ≥1 h — c'est le mécanisme du « faux pic visiteurs » du dashboard.
Avec P1-1, la récidive est garantie. **Fix** : rendre le calcul incrémental
(fingerprints historiques conservés, scan borné aux `anonymous_id` récents).
Correction du vérificateur : une borne naïve `occurred_at >= now()-90d`
serait un no-op aujourd'hui (l'historique < 90 j) — c'est bien
l'incrémental qu'il faut.

### P1-3 · Protocole de validation CPI J+28 : cible primaire biaisée vers l'échec — **à figer AVANT le 08/07** [non recoupé]

La cible « Spearman(CPI_t0, Δcontacts) > 0,3 » utilise un change-score
(c_fut − c_pas) mécaniquement **anti-corrélé** au CPI : `zv` est construit
sur les mêmes contacts que c_pas → régression vers la moyenne. Mesuré au
t0=10/06 : Spearman(score, c_pas)=+0,49, Spearman(score, Δ)=**−0,43**.
Tel quel, le test du 08/07 conclura « échec » et la grille recommandera de
baisser le poids conversion **pour une mauvaise raison**. Par ailleurs le
gel 22-28/06 ne casse PAS la validation (t0 intact, cibles calculées hors
`cpi_daily`), et §0/§5 passent aujourd'hui sans erreur.
**Fix** : avant le 08/07, remplacer la cible primaire par le **niveau
futur** c_fut (normalisé), garder le Δ en descriptif, pré-déclarer les
seuils de la branche « test sous-puissant » (86 % de ties déjà mesurés).
Deux P2 liés : §3 calibration déclarée PASSE alors que « écart médian
< 20 % » échoue ; `cpi_gisement.convertit = (zv > 0)` badge 62 pages à
0 conversion.

### P1-4 · `page_exit` jamais ré-armé après retour d'onglet **[CONFIRMÉ]**

`tracker.html:934` : `visibilitychange hidden → flushExit()` pose
`exitSent=true` ; le retour visible (l.410) ne le reset jamais. Visiteur
qui masque l'onglet puis revient lire → dwell/max_scroll figés au premier
masquage. Prod (22-28/06) : ~10-13 % des pages engagées ont de l'activité
jamais reflétée (perte stricte ≥60 s d'active_ms : 3,2 %). Biaise vers le
bas les médianes de lecture consommées par le CPI (rétention ≥15 s) et le
dashboard (percentile par event, sans max par session×path).
**Fix** : ré-armer `exitSent=false` au retour visible ; vérifier que les
RPCs dashboard prennent `max(duration)` par session×path.

### P1-5 · Aucun backup hors Supabase [non recoupé]

`events` (1,03 M rows, ~1 Go) = **seule copie au monde** de la donnée
comportementale ; GSC > 16 mois non re-téléchargeable ; purge 400j
programmée sans archive (≈ juin 2027). Zéro pg_dump/COPY dans les
workflows et les crons. **Fix** : workflow GitHub hebdo → `COPY … CSV.gz`
des tables `events`, `gsc_*`, `cpi_daily`, `page_taxonomy`, `annotations`
vers un stockage externe (B2/R2, coût ~0) ; export préalable à toute purge.

### P1-6 · Monitoring pull-only : une panne d'ingestion de plusieurs jours est invisible **[CONFIRMÉ]**

`raise_cooked_alert` = INSERT dans `alerts`, aucun canal push ; le
workflow GSC n'a pas de step `if: failure()` ; GitHub coupe les workflows
cron après 60 j sans commit. Si aucune session n'est ouverte pendant une
semaine, personne ne voit rien. **Fix minimal** : step `if: failure()` →
webhook (ntfy.sh / mail) dans les 2 workflows + `pg_net.http_post` pour
les alertes `critical`.

### P1-7 · Edge `track` : `occurred_at` client accepté sans clamp **[CONFIRMÉ]**

336 events / 19 sessions déjà datés dans le mauvais jour calendaire
(horloges clients cassées ; 102 events > 24 h dans le passé en juin).
Viole la règle dure timezone du projet à petite échelle. **Fix** (déjà
spécifié dans l'audit du 10/06, jamais appliqué) : clamp à
`received_at ± 48 h` + `props.clock_clamped=true` ; valider aussi
`submissionTime` dans form-webhook (P2 lié : les drops d'insert non-23505
partent en 200 silencieux — alerter au lieu d'avaler).

### Dashboard (2 P1 d'affichage)

- **Dernier point des séries figé sur ~1/4 de journée** **[CONFIRMÉ]** :
  le refresh de 10:15 fige le jour en cours (84 vs 340 visiteurs le
  01/07) → faux effondrement quotidien de ~75 % en fin de courbe + KPI
  28j comparant 27 jours pleins + ¼ vs 28 pleins. **Fix** : ancrer le
  lens live sur J-1.
- **Bandeau de fraîcheur chroniquement ambre** [non recoupé] : seuil
  `lag > 2` alors que le lag GSC structurel observé est J-3 → fatigue
  d'alerte. **Fix** : seuil aligné sur les alertes (>3) + corriger le
  « lag J-2 normal » de CLAUDE.md.

---

## P2 — inventaire (détail chez les auditeurs, fixes une ligne)

**Mesure/SQL** : `classify_channel` classe NULL les redirections
`r.search.yahoo.com` (self-host testé en sous-chaîne d'URL — tester le
hostname) ; pattern social `'%t.co%'` trop large ; détection bot
journalière groupée en date UTC (pas Paris) ; `proconfig
statement_timeout` inopérants sur 5 fonctions (faux filet — seuls les SET
côté commande cron protègent) ; ~31 % des sessions `events_human` sans
pageview (règle « compter pageview-only » à généraliser) ; référence
playbook « Cooked = 2,4× clics GSC » → ratio site-wide réel **1,19×**
(fenêtre alignée 16-29/06), le 2,4× ne vaut que page-level.

**Tracker/Wix** : budget minifié 14 048/15 000 (93,7 % — passer à terser
ou au loader externe avant le prochain sprint) ; `COOKED_DEBUG=true` en
prod dans masterPage + re-seed SPA en un seul tir 500 ms ;
`cooked_aid/sid` persistent dans l'historique navigateur (3 058 entrées
re-portent un id en query) ; 4 tests jsdom manquants sur les
comportements déjà mordus (anchor chrome, page_exit, session).

**Edge** : parité `canonical_path` — le commentaire Deno prétend que le
SQL décode, c'est faux ; `props` sans limite de taille/schéma par event ;
proxy Velo : origin contournable + pas de rate-limit (dégradé de P1 → P2
par le vérificateur : les macro-contacts form sont protégés server-side,
mais l'anti-forge phone reste l'item P0 dépriorisé de la roadmap).

**Ingestion** : `fetch_gsc` sans retry (→ `.execute(num_retries=3)`) ;
`dfs_sync` sort en code 0 même à 100 % d'échec + aucune alerte
`dfs_stale` ; pas de détection continue de désynchronisation tracker
repo ↔ Wix live (check `_v` majoritaire dans `cooked_alerts_refresh`).

**Docs (à resynchroniser en un lot)** : README « ~390k events » (réel
1,03 M) et « bruit 15-20 % » (réel 84 % depuis le swarm) ; **CLAUDE.md
« Google Ads : MCP non connecté » → il est CONNECTÉ (5 customer IDs
listés le 01/07)** ; OPERATIONS décrit l'état d'avant les fixes du 30/06
(timeouts, crons — 8 en prod pas 6) ; contradiction « ~10 contacts/mois »
vs « ~130/mois » vs ~173 macro/28j mesurés ; routine git « bundle »
périmée (le push direct marche, PRs #11/#12) ; paragraphe orphelin cassé
dans CLAUDE.md ; HISTORY s'arrête au 30/06 ; **régression silencieuse
`events.country`** : peuplée du 06/05 au 02/06 puis plus rien (la roadmap
dit « toujours NULL » — faux), à dater et trancher ; dashboard et
masterpage-cooked.js absents de la procédure de redémarrage sinistre.

---

## Recherche — « Cooked next level »

### Corrections de mesure qui sont aussi des features (fort impact / petit effort)

1. **`classify_channel` v2 — canal IA fiabilisé** : sous-comptage prouvé
   ~35 % (37 sessions `utm_source=chatgpt.com` + 14 `perplexity` avec
   referrer NULL classées « direct » sur 90j). Fix : tester `utm_source`
   + ajouter grok.com, meta.ai, chat.mistral.ai, deepseek. Rétroactif
   gratuit. Le canal est petit (~0,4 %) mais croît vite (+206 % YoY
   les referrals ChatGPT, Semrush) — le fiabiliser tant qu'il est petit.
2. **Croiser Google Ads × Cooked via le MCP (déjà connecté)** : coût et
   CPA par campagne d'Adrien × ~1 800 entrées paid/28j × macro-contacts.
   La brique manquante documentée du contexte business — dispo sans rien
   construire. Prérequis : identifier le bon customer ID parmi les 5.
3. **Premier usage de `click_internal`** (capté depuis S36, jamais
   exploité) : quels liens/placements portent le pont post → expertise
   (le levier n° 1 du gisement). + BUG P2 découvert au passage :
   `target_path` garde la variante accentuée du href (33 clics
   `/victimes-de-délits…` vs 35 non accentués → NFC ne suffit pas, il
   faut normaliser à l'ingestion et backfiller).
4. **« Dernier pas avant contact »** depuis `conversion_journeys` (jamais
   analysé) : la page charnière des parcours convertis = où renforcer.
5. **Canal push pour les alertes** (rejoint P1-6) : ntfy.sh/mail — cohérent
   avec le mono-canal de travail.

### Chantiers moyens

- **Perf mobile Wix** : 45/52 pages A/B du CPI sont gatées LCP, la home
  au plancher — un fix perf côté Wix Studio débloque le score de tout le
  site (et c'est du levier conversion, pas du modèle).
- **Sentinelle d'indexation** (URL Inspection API, quota 2 000/j, service
  account existant) : détecter désindexation/canonical drift AVANT la
  chute de trafic — complément amont de `cpi_drop`.
- **GBP Performance API** (CALL_CLICKS quotidiens) : ferme l'angle mort
  GMB sans cookie ni changement site. Prérequis : OAuth au profil du
  cabinet. Palier au-dessus : numéro de substitution statique sur la
  fiche (Dexem ~34 €/mois) — décision business.
- **Rapport GSC « Generative AI performance »** (lancé le 03/06/2026,
  UI seulement, rollout progressif) : vérifier si la propriété l'a reçu.
- **CausalImpact (BSTS) sur `gsc_path_daily`** piloté par la table
  `annotations` (0 ligne aujourd'hui — la remplir est le prérequis) :
  mesurer l'effet d'une réécriture/passage TV avec contrefactuel, au
  niveau clics (jamais contacts). Seule stat nouvelle jugée crédible —
  tout le reste (MMM, survival) : NO-GO à ~10 contacts/mois.

### Gros chantier optionnel (décision business)

- **Offline conversion import vers Google Ads** : capturer
  `gclid/wbraid/gbraid` (absents du tracker aujourd'hui —
  `tracker.html:216-220`) et uploader les macro-contacts via la **Data
  Manager API** (les uploads OCI sont migrés hors Google Ads API classique
  depuis le 15/06/2026). RGPD : PAS d'exemption CNIL possible (finalité
  pub) → capture conditionnée au consentement marketing Cookiebot +
  Consent Mode v2. Écarter « enhanced conversions for leads » (exige la
  PII que Cooked strippe by design). Bénéfice réel mais volume faible
  (~10 macro/mois) : à discuter avec Adrien avant d'investir.

### Verdicts négatifs (pour mémoire)

llms.txt : aucun acteur majeur ne le consomme (Google l'a confirmé le
15/06/2026) — ne rien faire. CrUX : redondant avec le field data maison,
garder en contre-vérification origin-level mensuelle au mieux. MMM light /
survival analysis : NO-GO au volume actuel.

---

## Plan proposé (par vagues, une chose à la fois)

| Vague | Contenu | Nature |
|---|---|---|
| **1. Stopper les pertes** (aujourd'hui) | Backfill GSC `--months 2` + fix fenêtre cron + check `gsc_gap` ; migration `cpi_gisement` (security_invoker + revoke) ; acker les 3 `cpi_drop` | 2 fixes + 1 ack |
| **2. Avant le 08/07** | Figer la cible primaire du protocole J+28 (niveau futur, pas Δ) + seuils pré-déclarés | 1 décision méthodo |
| **3. Fiabilité** | Bot fingerprints incrémental + endiguement du swarm à l'ingestion ; backup hebdo hors Supabase ; push d'alertes | 3 chantiers courts |
| **4. Mesure** | page_exit ré-armé ; clamp horloge Edge ; classify_channel v2 (IA + Yahoo + t.co) ; lot docs (README/CLAUDE/OPERATIONS) | 1 sprint tracker+SQL |
| **5. Next level** | Google Ads × Cooked (MCP) ; click_internal + dernier-pas ; sentinelle indexation ; GBP calls ; annotations + CausalImpact | exploration produit |

**Actions qui n'appartiennent qu'à Nicolas (Wix)** : champs cachés du
formulaire « accidents du travail » ; test du Formulaire Divorce ;
(plus tard) perf mobile et ponts de conversion sur le gisement.

---

*Généré par l'audit multi-agents du 01-02/07/2026 (27 agents, findings
P0/P1 contre-vérifiés sauf mention [non recoupé]). Sources détaillées :
transcripts du workflow `cooked-audit-next-level`.*
