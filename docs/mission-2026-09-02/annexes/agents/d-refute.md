# Réfutation zone (d) — sémantique des RPC et vues — mission Cooked 02/09/2026

Mode LECTURE SEULE. Aucune écriture, aucun appel de fonction qui écrit ou qui dure
(`cooked_page_index`, `cooked_cpi_snapshot`, `rpc_contract_check`, `refresh_*` : jamais appelés — leurs corps
ont été lus par `pg_get_functiondef`, jamais exécutés).

**Constats reçus : 9. Constats recopiés : 9.** (d-01…d-08 + o-14)

## Ancrage temporel de MA passe

Toutes mes mesures : **02/09/2026, entre 15:14 et 15:34 Paris**. État prod à 15:14 :

| Repère | Valeur |
|---|---|
| `now()` Paris | 02/09/2026 15:14 |
| `current_setting('TimeZone')` | **UTC** |
| `paris_today()` | 02/09/2026 |
| `gsc_last_data_day()` | **30/08/2026** |

⚠️ **Décalage assumé avec les constats** : ils ont été mesurés le 02/09 vers 09:5x–10:0x Paris, quand
`gsc_last_data_day()` valait 29/08. L'ingestion GSC du jour l'a passé à 30/08 vers 12:30. Les fenêtres `gsc`/`cross`
ont donc glissé d'un jour entre leur mesure et la mienne, et le déficit GSC est passé de 4 à 3 jours. **Aucun
verdict ne change**, mais plusieurs chiffres bougent — c'est précisément ce que démontrent d-02, d-03 et d-07 :
ces chiffres sont fonction de l'heure de lecture. Je le signale à chaque fois.

---

# Recopie intégrale des 9 constats reçus

## d-01
```
ID            d-01
Titre         behavior_pages_for_period renvoie un bounce_rate 100× trop faible sur ses DEUX colonnes
Sévérité      P0 chiffre faux livré
Preuve        Producteur — supabase/rpcs.sql:4971-4972 (seo_pages_overview) :
                bounce_rate     = round(100.0*bounce/entry / 100.0, 4)   → fraction 0–1
                bounce_rate_pct = round(100.0*bounce/entry,        2)   → pourcentage 0–100
              Consommateur — supabase/rpcs.sql:626,629-630 (behavior_pages_for_period) :
                base AS (SELECT * FROM public.seo_pages_overview(date_from, date_to))
                coalesce(round(b.bounce_rate / 100.0, 4), 0),   -- colonne bounce_rate
                coalesce(round(b.bounce_rate,        2), 0),    -- colonne bounce_rate_pct
              La fraction 0–1 est redivisée par 100, et la colonne annoncée « _pct » reçoit la fraction.
              Vérifié en prod le 02/09/2026 à 10:05 Paris, fenêtre paris_today()-7 → paris_today()-1 :
                /                       254 sess  spo 0.2328 / 23.28   bpp 0.0023 / 0.23
                /honoraires-rendez-vous 119 sess  spo 0.2000 / 20.00   bpp 0.0020 / 0.20
                /notre-cabinet           84 sess  spo 0.1594 / 15.94   bpp 0.0016 / 0.16
Impact        Les deux colonnes de bounce sont fausses d'un facteur 100 sur toutes les pages et toutes les
              fenêtres, depuis le 26/07/2026 (38 jours). Un lecteur de bounce_rate_pct = 0,23 conclut
              « 0,23 % de rebond » au lieu de 23,28 %. Atténuation : aucun consommateur hors contract-tests.
              Aggravant : latest_rpc_health() la déclare `ok` — le filet CERTIFIE un chiffre 100× faux.
Récidive      OUI — régression introduite PAR le correctif du défaut jumeau, à 4 h 30 d'intervalle.
              • 25/07 22:00 migration 20260725220000:123-178 ajoute bounce_rate_pct, CORRECT à cette date.
              • 26/07 02:30 migration 20260726023000:395-476 redéfinit seo_pages_overview (0–1 + _pct) sans
                retoucher behavior_pages_for_period. Contrat producteur cassé silencieusement.
Invariant     Le contract-test ne teste qu'un nombre de lignes, jamais une valeur. Invariant qui aurait mordu :
              assertion de VALEUR bornée par colonne (`*_pct` ⇒ 0≤v≤100 ET max(v)>1) + test d'équivalence
              producteur↔consommateur.
Statut        [non recoupé] — absence de consommateur héritée de l'inventaire Phase 0.
```

## d-02
```
ID            d-02
Titre         « Contacts macro sur 28 jours » se calcule sur trois fenêtres différentes : 183, 193 ou 195
Sévérité      P1 biais mesurable
Preuve        Définition unique, mais chaque RPC choisit sa fenêtre. Bornes prod 02/09 09:58 Paris :
                live      06/08→02/09  28 j  ← inclut le jour EN COURS, partiel
                live_j1   05/08→01/09  28 j
                gsc/cross 02/08→29/08  28 j
              Qui utilise quoi : cross → pages_overview_unified, top_contact_pages ; live_j1 → refresh_dashboard_* ;
              live → cooked_pages_snapshot, site_kpis_compare ; (28) → gsc_pages_overview = macro_contacts_by_path(28)
              = paris_today()-27 → paris_today() = identique à `live`.
              Chiffres site, même RPC site_macro_counts : cross 193 / live_j1 195 / live 183.
              Décomposition jour par jour : live = 195 − 13 + 1 = 183 ✓ ; cross = 195 − 21 + 19 = 193 ✓.
              Réconciliation exacte : écart 100 % imputable à la fenêtre, 0 % à la définition.
Impact        Le seul chiffre désigné « métrique business » vaut 183, 193 ou 195 selon la RPC : amplitude
              12 contacts = 6,6 %. Aucune sortie ne dit sur quelle fenêtre elle porte. Pire cas `live`
              (site_kpis_compare) : troque un jour PLEIN contre le jour EN COURS partiel → mécaniquement le
              plus bas le matin, converge jusqu'à minuit. Deux lectures à 6 h d'intervalle = deux chiffres.
Récidive      Partielle — Arch #1 (10/07, PRs #60-61) devait supprimer les fenêtres copiées ; a converti le
              dashboard mais laissé site_kpis_compare et cooked_pages_snapshot sur `live`.
Invariant     (1) exposer n_start/n_end sur toute RPC de période ; (2) test d'équivalence site_macro_counts
              = Σ macro_contacts_by_path sur les 4 lens ; (3) interdire rolling_28 sur le lens live
              (n_end ≤ paris_today()-1).
Statut        [non recoupé] — arithmétique exacte, pas de recoupement avec conversion_weekly.
```

## d-03
```
ID            d-03
Titre         gsc_pages_overview.gsc_clicks_28d ne couvre que 24 jours (−15,3 %) — récidive du 24/05/2026
Sévérité      P1 biais mesurable
Preuve        rpcs.sql:2637 : FROM gsc_path_daily WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - 27
              Pas de borne haute, pas d'alignement sur gsc_last_data_day(). Lag J-4 → 24 jours de données.
              Mesuré 02/09 09:59 Paris : fenêtre RPC 06/08→29/08 = 24 j, 4 548 clics ; fenêtre alignée
              02/08→29/08 = 28 j, 5 370 clics ; vue vestige gsc_path_metrics_28d = 4 755 clics.
              Écart −822 clics = −15,3 %. Trois valeurs pour la même notion : 4 548 / 4 755 / 5 370.
              Même défaut sur gsc_top_queries_for_path(path, days_back, max).
Impact        Colonne nommée _28d qui sous-compte de 15,3 %. Tri par clicks_total DESC → le classement
              « top pages SEO » peut basculer. Une ligne mélange TROIS fenêtres (GSC 24 j, snapshot nocturne,
              contacts 28 j live). Doc : OPERATIONS.md:291 documente gsc_pages_overview(period_kind, max_rows)
              alors que la signature prod est (max_rows integer) — le paramètre promis n'existe pas.
Récidive      OUI — data-quality-audit-2026-05-24.md:104 listait déjà cette RPC ; correctif appliqué à MOITIÉ
              (le -27 est là, la borne haute jamais ajoutée). cooked_period_bounds(...,'gsc') branché partout
              ailleurs, jamais ici.
Invariant     Test CI statique : aucune fonction lisant gsc_*_daily ne contient de borne littérale ; seule
              source autorisée = cooked_period_bounds(...,'gsc'|'cross'). Balayage : 6 fonctions non conformes.
              Plus test d'équivalence Σ gsc_pages_overview.gsc_clicks_28d = Σ gsc_path_daily.clicks.
Statut        [non recoupé] — total site, pas de décomposition page par page.
```

## d-04
```
ID            d-04
Titre         cooked_bounce_rate : même nom de colonne, deux unités et deux valeurs selon la RPC
Sévérité      P1 biais mesurable
Preuve        Mesuré 02/09 10:04 Paris, /honoraires-rendez-vous :
                gsc_page_performance(path,'rolling_28').cooked_bounce_rate = 0.2342
                pages_overview_unified('rolling_28').cooked_bounce_rate    = 34.43
                gsc_pages_overview(500).cooked_bounce_rate_28d             = 34.43
                seo_url_snapshot.bounce_rate_28d                           = 34.43
              Origine : gsc_page_performance → seo_pages_overview (0–1) ; les autres → seo_url_snapshot (0–100).
              Deux défauts superposés : (a) l'unité — facteur 100 sous le MÊME nom ; (b) la valeur — après
              remise à l'échelle 23,42 % ≠ 34,43 %, 11 points d'écart, parce que gsc_page_performance recalcule
              sur le lens cross tandis que le snapshot porte la fenêtre now_ts - 28 days du rebuild de 05:00.
              La définition du rebond est identique partout (pages_viewed=1 ET durée<10 s).
Impact        Un rapport juxtapose « 0,23 » et « 34,43 » pour la même notion, sans savoir lequel fait référence.
              seo_pages_overview et site_context_export montrent le bon patron (deux colonnes) ; les trois RPC
              de lecture page n'ont pas été alignées.
Récidive      OUI — défaut « bounce_rate : deux unités » de l'audit du 25/07, censé clos par la migration
              20260726023000 qui a corrigé les deux RPC site et laissé les trois RPC de lecture PAGE dehors.
Invariant     Convention imposée par test CI : *_pct si 0–100, *_ratio si 0–1, nom nu interdit. Plus le test
              de valeur de d-01. Plus l'équivalence gsc_page_performance = pages_overview_unified.
Statut        [non recoupé] — une seule page ; les 11 points attribués à la fenêtre par lecture du code,
              non par recalcul.
```

## d-05
```
ID            d-05
Titre         Le filtre anti-spam n'existe pas dans events_human : 19 % des « visiteurs » 28 j, jusqu'à 98,7 % sur une page
Sévérité      P1 biais mesurable
Preuve        Deux implémentations de périmètre différent : (a) cooked_events_window applique
              NOT (name='pageview' AND cooked_is_spam_referrer(referrer_hostname)) aux grains clean et human ;
              (b) la vue events_human (views.sql:128-146) filtre bots, bruit, chrome-anchors, doublons —
              mais PAS le spam. Toute RPC qui lit events_human en direct compte le spam.
              25 RPC listées sans filtre spam (behavior_pages_for_period, content_performance,
              conversion_journeys, cooked_page_index, macro_contacts_by_path, site_macro_counts, …).
              Volume prod 02/09 09:53 Paris, 05/08→01/09 : pageviews 13 772 dont spam 1 899 = 13,8 % ;
              visiteurs 10 009 dont spam 1 899 = 19,0 %.
              Par nom d'event : engagement_tick 19 210 · pageview 1 899 · web_vitals 1 895 · page_exit 0 · scroll 0.
              Par page : ressources-et-notions-juridiques 148/150 = 98,7 % ; droit-de-la-famille 103/105 = 98,1 % ;
              indemnisation-des-victimes 143/152 = 94,1 % ; mentions-legales 93/105 = 88,6 % ;
              trafic-de-stupefiant 119/145 = 82,1 % ; droit-criminel 96/117 = 82,1 % ;
              proces-criminel 95/253 = 37,5 % ; notre-cabinet 110/450 = 24,4 %.
Impact        Jusqu'à 10× le trafic humain réel. Les 19 210 ticks ≈ 16 % des ticks de la fenêtre et gonflent
              tout agrégat de temps passé. Nuance : seo_url_snapshot et les refresh dashboard passent par
              cooked_events_window et sont PROPRES ; le risque porte sur la lecture ad-hoc, mode d'usage
              principal de Cooked. Évolution : le spam n'est plus « 0 engagement » (~10 ticks/session).
Récidive      OUI — migration 20260726023000:4 « Baidu : filtre central dans cooked_events_window » : le
              correctif a centralisé le filtre dans la procédure de fenêtrage, PAS dans la vue de base.
Invariant     (a) porter le filtre dans events_human, ou (b) l'assumer dehors + test CI interdisant
              FROM events_human sans cooked_is_spam_referrer. Plus alerte de volume (>20 % sur 7 j) et
              test d'équivalence events_human filtré = cooked_events_window('human').
Statut        [non recoupé] — la qualification « spam » de ces 1 899 sessions est héritée du projet.
```

## d-06
```
ID            d-06
Titre         seo_to_contact_funnel : contact_rate_pct divise un numérateur et un dénominateur incomparables
Sévérité      P1 biais mesurable
Preuve        Corps prod lu par pg_get_functiondef, 02/09 ~10:02 Paris. Trois fenêtres, deux notions d'identité :
                entries : FROM events_human … occurred_at > now() - make_interval(days => days_back),
                          DISTINCT ON (e.session_id) → une entrée par SESSION BRUTE
                conv    : FROM conversion_journeys(days_back) → un contact par VISITEUR RECOUSU
                gsc     : WHERE g.day > current_date - days_back → current_date évalué en UTC
                sortie  : round(100.0 * contacts / nullif(organic_entries,0), 2)
              current_setting('TimeZone') = UTC (mesuré) : les CTE gsc et topq sont bornées sur la date UTC,
              pas Paris. Et sans alignement gsc_last_data_day() → 24 jours de GSC (mécanique de d-03).
Impact        Ratio dont le numérateur est compté sur le visiteur recousu et le dénominateur sur la session
              brute : le taux est structurellement sous-estimé du taux de fragmentation résiduel. Faible
              aujourd'hui (0,04 %) mais la RPC est lue sur des fenêtres historiques où il valait 5,53 %.
              Les colonnes gsc_* portent 24 jours face à des organic_entries sur 28 jours.
              Effet sur contact_rate_pct NON quantifié (appel coûteux interdit).
Récidive      Désalignement déjà signalé par l'audit du 25/07 (« 3 fenêtres différentes ») — connu et non
              corrigé, 39 jours. La partie « session brute vs visiteur recousu » n'est documentée nulle part :
              l'héritage du 12/07 a réparé le numérateur et laissé le dénominateur sur l'ancienne notion.
Invariant     (1) Interdire current_date et now() nus : seules paris_today()/paris_date()/cooked_period_bounds
              autorisées (2 fonctions avec current_date, 8 avec now() AT TIME ZONE brut).
              (2) Un ratio publié doit avoir numérateur et dénominateur sur la MÊME fenêtre et la MÊME clé
              d'identité ; à défaut exposer les deux comptes bruts.
Statut        [non recoupé] — effet chiffré NON mesuré.
```

## d-07
```
ID            d-07
Titre         cooked_page_index compose une capture GSC sur 24 jours avec un comportement Cooked sur 28×24 h
Sévérité      P2 dette qui mordra à l'échelle
Preuve        Corps de cooked_page_index(p_days) — deux familles de bornes dans le même score :
                côté GSC (current_date, UTC) : :1158 fit day > current_date - 90 ; :1163 capq ; :1165 capb ;
                  :1166 capp day > current_date - p_days ; :1231-1232 mom c1 / c0
                côté Cooked (now()) : :1170 firstpv ; :1173 spv ; :1181 page_exit ; :1239 lcp
                  … occurred_at > now() - make_interval(days => p_days)
              Avec p_days=28 et lag J-4 : bornes GSC = 24 jours (4 548 clics vs 5 370 alignés), bornes Cooked
              = 28×24 h pleines. Asymétrie du momentum : c1 sur 24 jours réels, c0 sur 28 jours pleins.
Impact        Le CPI compose zc sur 24 jours et zr/zl sur 28 jours. Le clics_perdus de cpi_capture_perdue est
              une perte sur 24 jours présentée comme une perte sur 28 jours (~14 % de sous-estimation).
              Atténuation : le momentum est normalisé par le site, donc un biais uniforme se compense
              largement ; capq/capp partagent la même borne donc zc est interne cohérent. Défaut d'ÉTIQUETTE
              et de comparabilité entre composantes, pas erreur de calcul dans chaque terme → P2.
Récidive      Non trouvée comme telle. Même famille que d-03 : borne GSC brute non alignée, corrigée ailleurs.
Invariant     Même test CI que d-03 ; plus un contrôle dans cooked_cpi_snapshot refusant d'écrire si le nombre
              de jours GSC couverts ≠ p_days, ou le journalisant en colonne.
Statut        [non recoupé] — effet page par page NON mesuré (appel de cooked_page_index interdit).
```

## d-08
```
ID            d-08
Titre         Quatre paires de doublons sémantiques : overloads à fenêtres divergentes et vestiges
Sévérité      P2 dette qui mordra à l'échelle
Preuve        Signatures relevées en prod (pg_proc + pg_get_functiondef), 02/09 ~10:07 Paris.
              (a) macro_contacts_by_path ×2 — même type de retour, fenêtres différentes :
                  (days_back) → paris_today()-(days_back-1) → paris_today() = inclut le jour EN COURS
                  (start_date, end_date) → bornes explicites
                  Appelé sous la forme (28) par gsc_pages_overview:2656 uniquement ; 183 vs 195 selon la forme.
              (b) gsc_top_queries_for_path ×2 : (days_back) non aligné GSC, (p_period_kind) aligné via
                  cooked_period_bounds. L'appel ('/x', 28, 20) choisit silencieusement le mauvais.
              (c) page_reads ×2 — (p_days) SECURITY INVOKER délègue à (p_from,p_to) qui est SECURITY DEFINER
                  et exécutable par anon. Grain session×path qui n'existe nulle part ailleurs →
                  NON redondante sémantiquement ; sans consommateur hors contract-tests ; lit events_human
                  sans filtre spam.
              (d) Vue gsc_path_metrics_28d (views.sql:201-203) : fenêtre de 29 jours nominaux, non alignée GSC,
                  pour une vue nommée _28d. 4 755 clics contre 4 548 et 5 370. Consommateurs : aucun dans le
                  code, 2 mentions documentaires. Candidat DROP net.
Impact        Pas de chiffre faux en propre — (a) et (b) sont les VECTEURS de d-02 et d-03, (c) une surface
              d'API inutilisée et exposée, (d) une troisième valeur qui ne sert à personne. 118 routines dont
              3 sans consommateur et 7 consommées uniquement par les contract-tests. Chaque overload à fenêtre
              divergente est un piège d'appel ad-hoc.
Récidive      ROADMAP-sprint38-handoff.md:234 acte dès le sprint 38 que gsc_path_metrics_28d a « 0 dépendant
              en prod ». Toujours là. Pour page_reads, privilège PUBLIC jamais révoqué.
Invariant     Budget « pas de nouvelle RPC sans en déprécier une » rendu exécutable en gate CI ; interdire deux
              surcharges de même nom dont les fenêtres ne dérivent pas de cooked_period_bounds ; forme à
              privilégier : bornes explicites / p_period_kind, jamais days_back.
Statut        [non recoupé] — absence de consommateur fondée sur un grep du repo.
```

## o-14
```
ID            o-14 (zone d)
Titre         `classify_channel` ignore `gclid`/`gbraid`/`wbraid` : 18 entrées sur 28 j portent un `gclid` et sont classées hors `paid`
Sévérité      P3
Preuve        Q-35 (02/09 09:54 Paris, events_human, 1re pageview de session, 05/08→01/09) : paid = 1 472,
              dont 1 185 avec gclid ; non_paid_avec_gclid = 18 ; corps classify_channel : aucun test sur url/gclid.
Impact        1,2 % des clics Ads classés direct/organique — négligeable aujourd'hui, mais même famille de défaut
              que le GMB (27/07) et l'IA (02/07) : le canal dépend du seul utm_*.
Récidive      pattern classify_channel v2 (02/07, utm_source IA) et v3 (27/07, GMB).
Invariant     vecteurs de test contracts/channel_vectors.json (referrer, utm, url → canal) rejoués en contract-test.
Statut        [non recoupé]
```

---

# Verdicts

---

```
ID        d-01
Verdict   CONFIRMÉ
```

**Ma preuve — mesure.** 02/09/2026 15:16 Paris, appel unique des deux RPC sur `paris_today()-7 → paris_today()-1`
(26/08 → 01/09) :

| path | sessions | spo.bounce_rate | spo.bounce_rate_pct | bpp.bounce_rate | bpp.bounce_rate_pct |
|---|---|---|---|---|---|
| `/` | 223 | 0.2293 | 22.93 | 0.0023 | **0.23** |
| `/post/durée-de-la-garde-à-vue-…` | 147 | 0.1769 | 17.69 | 0.0018 | **0.18** |
| `/post/itt-pénale-définition-en-2025` | 116 | 0.1207 | 12.07 | 0.0012 | **0.12** |
| `/droit-des-contrats…/droit-assurances-…` | 105 | 0.6200 | 62.00 | 0.0062 | **0.62** |
| `/honoraires-rendez-vous` | 99 | 0.1842 | 18.42 | 0.0018 | **0.18** |

**Ma preuve — corps prod** (`pg_get_functiondef`, pas `rpcs.sql`) :

- `behavior_pages_for_period(timestamptz,timestamptz)` — signature de sortie déclare bien
  `bounce_rate numeric, bounce_rate_pct numeric`, et le corps contient exactement :
  `coalesce(round(b.bounce_rate / 100.0, 4), 0),` puis `coalesce(round(b.bounce_rate, 2), 0),`
- `seo_pages_overview(timestamptz,timestamptz)` :
  `coalesce(round((100.0 * ee.bounce_count / nullif(ee.entry_count,0))::numeric / 100.0, 4), 0) AS bounce_rate,`
  `coalesce(round((100.0 * ee.bounce_count / nullif(ee.entry_count,0))::numeric, 2), 0) AS bounce_rate_pct,`

Le producteur rend bien 0–1 sur `bounce_rate` ; le consommateur le redivise par 100 et remplit sa colonne
`_pct` avec la fraction. **La double erreur est reproduite au caractère près.**

**Ma preuve — chronologie de récidive.** `grep -ln` sur `supabase/migrations/` : la dernière migration qui
**redéfinit** `behavior_pages_for_period` est `20260725220000_audit_spam_referrer_and_site_kpis.sql` ; les trois
occurrences postérieures (`20260727215029`, `20260727220006`, `20260728102500`) ne la redéfinissent pas — elles
l'**enregistrent comme cible de contract-test**. `seo_pages_overview` n'est redéfinie que dans
`20260726023000_audit_finitions.sql`. La séquence « producteur changé 4 h 30 après le consommateur, consommateur
non retouché » est donc exacte.

**Ma preuve — le filet certifie le faux.** `latest_rpc_health()` au 02/09/2026 :

```
rpc_name                   status  rows_returned  duration_ms  checked_at (UTC)
behavior_pages_for_period  ok      306            4103         2026-09-02 03:30:00  → 05:30 Paris
```

Et le test enregistré est, mot pour mot (`20260728102500_rpc_contract_check_helper.sql:96-97`) :
`select count(*) from public.behavior_pages_for_period(now() - interval '7 days', now())`.
**Un `count(*)`. Aucune valeur n'est regardée.** Le constat est exact.

**Écart** — deux, tous deux mineurs et défavorables au constat sur la forme, favorables sur le fond :
1. Les valeurs diffèrent (23,28 → 22,93 sur `/`) : fenêtre glissante, 5 h plus tard. Sans effet.
2. Le constat écrit « `latest_rpc_health()` la déclare ok » comme une aggravation. C'est vrai, mais j'ajoute
   ceci : `seo_pages_overview` et `gsc_pages_overview` ne sont **pas du tout** dans `rpc_health` (ma requête
   filtrée sur les trois noms n'a rendu qu'une ligne). Le filet est donc plus étroit encore que décrit.

**Invariant : tient, avec une réserve d'implémentation.** L'assertion de valeur (`*_pct` ⇒ `0 ≤ v ≤ 100` **ET**
`max(v) > 1`) aurait mordu ici : `max(bounce_rate_pct) = 0,62` sur ma fenêtre, donc `max > 1` échoue. La clause
`max(v) > 1` est indispensable — sans elle, `0 ≤ 0,23 ≤ 100` passe. Le second volet (équivalence
producteur↔consommateur, tolérance 0) est le plus solide : il attrape la classe entière, pas ce cas.
**Réserve** : `max(v) > 1` produira un faux positif sur une RPC légitimement à zéro (page sans rebond, fenêtre
vide) — il faut le conditionner à un échantillon non vide, ce que le constat dit déjà.

---

```
ID        d-02
Verdict   CONFIRMÉ (cause exacte ; amplitude annoncée périmée par construction)
```

**Ma preuve — bornes.** 02/09/2026 15:18 Paris, `cooked_period_bounds('rolling_28', lens)` :

| lens | n_start | n_end | n_days |
|---|---|---|---|
| live | 06/08/2026 | **02/09/2026** | 28 |
| live_j1 | 05/08/2026 | 01/09/2026 | 28 |
| gsc | 03/08/2026 | 30/08/2026 | 28 |
| cross | 03/08/2026 | 30/08/2026 | 28 |

`live` inclut bien le jour en cours, partiel. Les bornes `gsc`/`cross` ont glissé d'un jour depuis le constat
(ingestion GSC de 12:30).

**Ma preuve — les trois valeurs.** Même RPC `site_macro_counts`, trois fenêtres, 02/09 15:19 Paris :

| fenêtre | phone | forms | macro |
|---|---|---|---|
| live 06/08→02/09 | 124 | 64 | **188** |
| live_j1 05/08→01/09 | 128 | 67 | **195** |
| cross 03/08→30/08 | 124 | 71 | **195** |

**Ma preuve — la dérive intra-journalière, mesurée.** Le constat mesure `live` = **183** à 09:58 Paris. Je mesure
`live` = **188** à 15:19 Paris. **Même fenêtre calendaire (06/08→02/09), même RPC, +5 contacts en 5 h 20.**
C'est la démonstration directe et indépendante du point central du constat : « deux lectures du même KPI à 6 h
d'intervalle donnent deux chiffres ». Je l'ai obtenue sans le vouloir, en re-mesurant plus tard dans la journée.

**Ma preuve — l'overload `(28)`.** 02/09 15:20 Paris :

```
Σ macro_contacts_by_path(28)                      = 188
Σ macro_contacts_by_path('2026-08-06','2026-09-02') = 188   (= live)
Σ macro_contacts_by_path('2026-08-05','2026-09-01') = 195   (= live_j1)
```

`macro_contacts_by_path(28)` est bien identique au lens `live`, jour en cours partiel compris — donc
`gsc_pages_overview`, son unique appelant sous cette forme, publie des contacts sur une fenêtre différente de
celle du dashboard. Et E4 (`site_macro_counts` = Σ `macro_contacts_by_path`) passe : 188 = 188, 195 = 195.

**Écart** — un seul, et il n'affaiblit pas le constat :
- **L'amplitude « 12 contacts = 6,6 % » ne tient pas comme chiffre stable.** Chez moi c'est 188 / 195 / 195,
  soit 7 contacts = 3,6 %. Et `cross` est passé de 193 à 195 parce que sa fenêtre a glissé d'un jour. Le
  triplet annoncé (183/193/195) est une photo à 09:58, pas une propriété du système. **Ce qui est stable, c'est
  le mécanisme** : trois fenêtres nommées « 28 j », dont une qui bouge toute la journée. Livrer « amplitude
  12 contacts » comme un chiffre serait reproduire le défaut que le constat dénonce.

**Invariant : (1) et (3) tiennent, (2) est décoratif.**
- (1) exposer `n_start`/`n_end` : **tient** — c'est la seule mesure qui rend le défaut visible au lecteur, et
  elle est déjà implémentée ailleurs (le patron existe), donc non spéculative.
- (3) `n_end ≤ paris_today() - 1` pour tout `rolling_%` : **tient et mord** — c'est le seul invariant qui
  supprime la dérive intra-journalière que j'ai mesurée (+5 en 5 h). C'est le plus fort des trois.
- (2) équivalence `site_macro_counts` = Σ `macro_contacts_by_path` : **décoratif ici**. Il passe déjà sur les
  quatre lens (je l'ai vérifié : 188=188, 195=195). Il protège contre une régression de *définition*, qui n'est
  pas le défaut de d-02 — le constat le reconnaît d'ailleurs (« écart 100 % imputable à la fenêtre »). Utile,
  mais il n'aurait jamais sonné pour d-02.

---

```
ID        d-03
Verdict   CONFIRMÉ (cause exacte ; le −15,3 % est un chiffre du jour, pas une constante)
```

**Ma preuve — corps prod.** `pg_get_functiondef('public.gsc_pages_overview(integer)')`, lignes filtrées :

```
    FROM gsc_path_daily
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - 27
  ORDER BY g.clicks_total DESC, g.impressions_total DESC
```

Aucune borne haute, aucun appel à `gsc_last_data_day()` ni `cooked_period_bounds`. Le tri par
`clicks_total DESC` est confirmé.

**Ma preuve — signature.** `pg_proc` : `gsc_pages_overview(integer)`. **Il n'existe pas d'overload
`period_kind`.** L'appelant ne peut donc pas aligner la fenêtre. Et `docs/OPERATIONS.md:291` documente bien
`` `gsc_pages_overview(period_kind, max_rows)` `` — j'ai relu la ligne. **Le contrat documenté n'existe pas en
prod.**

**Ma preuve — mesure.** 02/09/2026 15:22 Paris :

| | jours | clics |
|---|---|---|
| fenêtre réellement utilisée (`day >= paris_today()-27`) | **25** | **4 689** |
| fenêtre 28 j alignée GSC (03/08→30/08) | 28 | **5 358** |
| `Σ gsc_pages_overview(2000).gsc_clicks_28d` | — | **4 689** |
| vue `gsc_path_metrics_28d` (`clicks_total`) | — | **4 896** |

Écart de la colonne `_28d` : 4 689 − 5 358 = **−669 clics = −12,5 %**. Et `Σ gsc_pages_overview.gsc_clicks_28d`
= 4 689 exactement = la fenêtre tronquée : **E7 échoue, comme annoncé.** Trois valeurs coexistent bien pour
« clics GSC 28 j » : 4 689 / 4 896 / 5 358.

**Écart** — sur le chiffre, pas sur le défaut :
- Le constat annonce **24 jours et −15,3 %**. Je mesure **25 jours et −12,5 %**. Raison : `gsc_last_data_day()`
  est passé de 29/08 à 30/08 entre les deux mesures. **Le déficit est le lag Google, donc il respire entre
  −11 % et −15 % au fil de la semaine.** Annoncer « −15,3 % » comme la taille du défaut serait un chiffre daté
  livré sans sa fenêtre — exactement le travers dénoncé. Le défaut, lui, est permanent : la borne haute
  manquante garantit que la fenêtre ne contient jamais 28 jours de données.
- Le constat dit « −822 clics » ; c'était vrai à 09:59, ce n'est plus vrai à 15:22.

**Invariant : tient sur le principe, mais la formulation du test est FAUSSE et produirait des faux positifs.**
J'ai rejoué le balayage moi-même (02/09 15:33 Paris) : les fonctions lisant `gsc_*_daily` **sans** passer par
`cooked_period_bounds` sont au nombre de **15**, pas 6 :

`alert_rule_gsc_ingest_missed`, `cooked_page_index`, `cooked_refresh_after_gsc`, `dashboard_intervention_effect`,
`dashboard_resources_cohorts`, `dfs_keywords_to_sync`, `gsc_last_data_day`, `gsc_page_daily_series`,
`gsc_pages_overview`, `gsc_path_metrics`, `gsc_top_queries_for_path`, `refresh_dashboard_expertises_snapshots`,
`refresh_dashboard_snapshots`, `refresh_pipeline_health`, `seo_to_contact_funnel`.

Plusieurs sont **légitimes** et casseraient le test tel qu'écrit : `gsc_last_data_day()` doit lire le max de
`day` sans borne (c'est sa définition) ; `gsc_path_metrics(from,to)` reçoit ses bornes en paramètre ; les deux
`refresh_dashboard_*` passent par `cooked_snapshot_window`, qui appelle `cooked_period_bounds` en interne — le
test naïf ne les voit pas. **L'invariant doit donc être : « toute fonction lisant `gsc_*_daily` dérive ses
bornes soit de ses paramètres, soit de `cooked_period_bounds`/`cooked_snapshot_window` », avec une liste
blanche explicite.** Sous cette forme il tient et attrape d-03, d-06 et d-07. Sous la forme du constat
(« aucun littéral de date », 6 fonctions), il est faux. E7 (équivalence des sommes), lui, est exact et mord
directement.

---

```
ID        d-04
Verdict   PARTIEL — le défaut d'unité est CONFIRMÉ ; la cause annoncée des 11 points est RÉFUTÉE
```

**Ma preuve — les quatre valeurs.** 02/09/2026 15:24 Paris, `/honoraires-rendez-vous` :

| source | colonne | valeur |
|---|---|---|
| `gsc_page_performance(path,'rolling_28')` | `cooked_bounce_rate` | **0.2298** |
| `pages_overview_unified('rolling_28',2000)` | `cooked_bounce_rate` | **34.43** |
| `gsc_pages_overview(2000)` | `cooked_bounce_rate_28d` | 34.43 |
| `seo_url_snapshot` | `bounce_rate_28d` | 34.43 |

**Le volet (a) est confirmé sans réserve** : deux RPC publiées, une colonne du même nom `cooked_bounce_rate`,
0.2298 contre 34.43. Facteur 100 et aucune convention de nommage pour l'annoncer.

**Ma preuve — la cause des 11 points, recalculée.** Le constat attribue l'écart résiduel (23 % vs 34 %) à la
différence de fenêtre, « par lecture du code, non par recalcul ». **J'ai fait le recalcul, et il l'infirme.**
02/09 15:26 Paris, `seo_pages_overview` appelée sur les deux fenêtres, même page :

| fenêtre | `bounce_rate_pct` |
|---|---|
| lens `cross` 03/08→30/08 (celle de `gsc_page_performance`) | **22.98** |
| `now() - 28 days → now()` (celle du rebuild `seo_url_snapshot`) | **22.22** |

**Changer de fenêtre déplace le chiffre de 0,76 point, pas de 11.** La fenêtre n'explique donc quasiment rien de
l'écart 22,98 → 34,43. La cause annoncée est fausse.

**Ma preuve — ce n'est pas non plus la définition.** J'ai relu le corps de `refresh_seo_url_snapshot()` : le
rebond y est calculé
`case when ss.pages_viewed=1 and extract(epoch from (ss.session_end-ss.session_start))<10 then 1 else 0 end`
et le taux `100.0*ee.bounce_count/nullif(ee.entry_count,0)` — **formule et dénominateur identiques** à
`seo_pages_overview`. Le constat a raison sur ce point : la métrique ne diverge pas.

**Ma preuve — la cause réelle (partielle).** Ce qui diffère entre les deux sources, c'est la **population
d'events** : le snapshot est construit via `cooked_events_window` (spam filtré, cf. d-05), `seo_pages_overview`
lit `events_human` brut (spam inclus). Mesuré 02/09 15:28 Paris sur les sessions touchant
`/honoraires-rendez-vous`, fenêtre 03/08→30/08 :

| | sessions | dont rebonds (1 pv, < 10 s) |
|---|---|---|
| non-spam | 362 | 24 |
| spam | **96** | 13 |

**21 % des sessions touchant cette page sont du spam**, et elles ne rebondissent qu'à 13,5 % — parce que leurs
~10 `engagement_tick` (cf. d-05) étirent la durée de session au-delà de 10 s. Elles entrent donc au dénominateur
sans entrer au numérateur : **le spam dilue mécaniquement le taux de rebond de toute RPC lisant `events_human`
en direct**, ce qui va dans le bon sens (22,98 non filtré < 34,43 filtré). C'est cohérent, mais ma mesure est
au grain « session touchant la page » et non « session entrée sur la page » (`entry_count`) : elle ne referme
pas l'écart au chiffre près. **Je ne prétends donc pas avoir prouvé la cause — j'ai prouvé que ce n'est pas la
fenêtre**, et je désigne d-05 comme le candidat principal, à confirmer.

**Écart** — sévérité maintenue P1, mais :
1. Cause des 11 points : **fausse**. Ce n'est pas la fenêtre (0,76 pt mesuré).
2. Conséquence de fond que le constat manque : d-04 et d-05 ne sont pas indépendants. Aligner les fenêtres —
   le correctif que le constat suggère implicitement — **ne réconcilierait pas les deux chiffres**. Il faut
   traiter le filtre spam.
3. Valeur `gsc_page_performance` : 0.2342 chez eux, 0.2298 chez moi (recalcul live, fenêtre glissée). Le
   snapshot, lui, est resté à 34.43 — normal, il date du rebuild nocturne.

**Invariant : la convention de nommage tient, l'équivalence proposée est mal spécifiée.**
- Convention `*_pct` / `*_ratio` + interdiction du nom nu : **tient**, et c'est le cœur du volet (a).
- E2 (`gsc_page_performance.cooked_bounce_rate ×100` = `pages_overview_unified.cooked_bounce_rate`,
  **tolérance 0**) : **irréalisable en l'état.** Mes mesures montrent que même à unité corrigée et fenêtre
  identique, les deux valeurs divergent pour une raison de population (spam) ; et le snapshot étant nocturne,
  une tolérance 0 échouerait en permanence même après correction de l'unité. Le test livrerait un rouge
  chronique, donc ignoré. Il faut soit une tolérance explicite, soit — mieux — le faire porter sur deux
  sources **construites sur le même chemin d'events**. En l'état : **décoratif, voire nuisible.**

---

```
ID        d-05
Verdict   CONFIRMÉ (et l'ampleur est sous-estimée par le constat)
```

**Ma preuve — la vue.** Test direct sur la définition prod, 02/09 15:29 Paris :

```
position('cooked_is_spam_referrer' IN pg_get_viewdef('public.events_human')) = 0
longueur de la définition                                                    = 1086 caractères
```

**Zéro occurrence.** La vue `events_human` ne filtre pas le spam. Confirmé sur la définition prod, pas sur
`views.sql`.

**Ma preuve — le périmètre, compté en prod.** Requête sur `pg_proc` : routines dont le corps contient
`events_human`, **sans** `cooked_is_spam_referrer` **et sans** `cooked_events_window` : **29**.
Le constat en listait 25. **Le périmètre réel est plus large que le constat ne le dit.**

**Ma preuve — volume.** 02/09/2026 15:30 Paris, `events_human`, fenêtre Paris 05/08→01/09 (28 j, = `live_j1`) :

| | total | dont spam | part |
|---|---|---|---|
| pageviews | 13 772 | 1 899 | **13,79 %** |
| visiteurs (`DISTINCT anonymous_id`) | 10 119 | 1 900 | **18,8 %** |

Reproduction exacte sur les pageviews (13 772 / 1 899, au chiffre près). Sur les visiteurs je trouve 10 119
contre 10 009 annoncés — écart de 1,1 %, sans effet sur la conclusion (19 %).

**Ma preuve — décomposition par event** (sessions ayant une pageview spam, même fenêtre) :

```
engagement_tick 19 210 · pageview 1 899 · web_vitals 1 895 · page_exit 0 · scroll_depth 0
```

Identique au chiffre près. **La mémoire projet (« 1 session / 1 anon, 0 engagement ») est bien périmée** :
~10,1 ticks par session. Un filtre heuristique fondé sur l'absence d'engagement ne les attraperait plus. Le
constat a raison de le signaler, et ce point a une conséquence qu'il ne tire pas : c'est ce qui empêche ces
sessions d'être comptées comme des rebonds — voir d-04.

**Ma preuve — par page** (`pageview`, 05/08→01/09, pages ≥ 100 vues) :

| path | pv | spam | % |
|---|---|---|---|
| `/blog/categories/ressources-et-notions-juridiques` | 150 | 148 | **98,7** |
| `/blog/categories/droit-de-la-famille` | 105 | 103 | 98,1 |
| `/indemnisation-des-victimes` | 152 | 143 | 94,1 |
| `/mentions-legales` | 105 | 93 | 88,6 |
| `/defense-penale/trafic-de-stupefiant` | 145 | 119 | 82,1 |
| `/blog/categories/droit-criminel` | 117 | 96 | 82,1 |

**Identique ligne à ligne au constat.** Sur la page catégorie « ressources », 150 vues affichées pour **2 vues
humaines**.

**Écart** — un seul, en défaveur du constat : le périmètre est de **29 routines et non 25**, et la liste du
constat omet donc des consommateurs. Tout le reste est reproduit à l'identique.

**Invariant : tient, et l'option (a) est la seule qui ferme réellement le trou.**
- (a) porter le filtre dans `events_human` : **tient**. C'est le seul correctif qui protège les 29 routines
  d'un coup **et** la lecture ad-hoc — or CLAUDE.md désigne l'ad-hoc comme le mode d'usage principal. Un test CI
  ne protège pas une requête tapée à la main dans une session.
- (b) test CI statique interdisant `FROM events_human` sans filtre : **partiellement décoratif** — il régit le
  code committé, pas les requêtes ad-hoc, c'est-à-dire pas le risque principal identifié par le constat
  lui-même. Contradiction interne du constat, à trancher en faveur de (a).
- L'alerte de volume (> 20 % sur 7 j) : **utile mais ne mordrait pas aujourd'hui** — je mesure 13,79 % sur
  28 j, sous le seuil proposé. Le constat le dit d'ailleurs (« à re-mesurer sur 7 j »). Comme filet unique,
  elle laisserait passer la situation actuelle ; comme complément, elle a du sens.
- E10 (équivalence `events_human` filtré = `cooked_events_window('human')`) : **tient**, c'est le test qui
  vérifie que (a) a bien été appliqué.

---

```
ID        d-06
Verdict   CONFIRMÉ (et l'effet, non quantifié par le constat, est ~10× plus grand qu'il ne le suppose)
```

**Ma preuve — corps prod.** `pg_get_functiondef('public.seo_to_contact_funnel(integer)')`, 02/09 15:31 Paris,
lignes filtrées :

```
RETURNS TABLE(… organic_entries bigint, contacts bigint, …, contact_rate_pct numeric)
    select distinct on (e.session_id)                              ← dénominateur : SESSION BRUTE
      and e.occurred_at > now() - make_interval(days => days_back)
    from public.conversion_journeys(days_back) j                   ← numérateur : via journeys
    where g.day > current_date - days_back                         ← GSC : date UTC
      where q.day > current_date - days_back
```

Les trois fenêtres et les deux notions d'identité sont confirmées dans le corps prod.

**Ma preuve — le numérateur est bien recousu.** Le corps de `conversion_journeys(integer)` contient **4**
références à `identity_stitch` / `visitor_key`. Le numérateur compte donc par visiteur recousu, le dénominateur
par `session_id` brut. **L'asymétrie d'identité est établie sur les corps, pas sur la doc.**

**Ma preuve — le TimeZone.** `current_setting('TimeZone')` = **UTC** (mesuré 15:14). Les CTE `gsc` et `topq`,
bornées sur `current_date`, sont donc bornées sur la date UTC. Violation de la règle CLAUDE.md confirmée.

**Ma preuve — quantification, que le constat n'a pas faite.** Le constat suppose l'effet « probablement petit
MAINTENANT » en s'appuyant sur un taux de sessions coupées de 0,04 %. J'ai mesuré directement le rapport entre
les deux populations, 02/09 15:32 Paris, fenêtre Paris 05/08→01/09, sessions avec pageview :

```
sessions brutes (DISTINCT session_id)                    = 11 067
visiteurs recousus (DISTINCT visitor_key via identity_stitch, kind='sid') = 10 006
ratio                                                    = 1,106
```

**Le dénominateur sur-compte la population du numérateur de 10,6 %**, pas de 0,04 %. `contact_rate_pct` est donc
sous-estimé d'environ **10 % en relatif** aujourd'hui, pas d'un epsilon.

**Réserve honnête sur ma propre mesure** : ce ratio de 1,106 agrège deux choses distinctes — la fragmentation
résiduelle d'identité **et** les visites répétées légitimes d'un même visiteur (qui produisent plusieurs
`session_id` sans aucun bug). Pour le ratio publié, les deux ont le même effet — le numérateur dédoublonne, le
dénominateur non — donc le biais de 10,6 % sur `contact_rate_pct` tient quelle que soit l'origine. Mais on ne
peut pas dire « 10,6 % de fragmentation ». **[non recoupé]** sur la ventilation entre les deux causes.

**Écart** — en défaveur du constat, dans le sens de l'aggravation :
- Le constat classe l'effet comme « probablement petit maintenant » (0,04 %). **Mesuré : 10,6 %.** Le 0,04 % de
  la baseline mesure un autre phénomène (sessions coupées par le bug de rotation) que le taux de sur-comptage
  du dénominateur face à un numérateur recousu. La sévérité P1 est donc justifiée sur le présent, pas seulement
  sur les fenêtres historiques.

**Invariant : (2) tient et est le bon ; (1) tient mais mal calibré.**
- (2) « numérateur et dénominateur sur la même fenêtre et la même clé d'identité, sinon exposer les deux comptes
  bruts » : **tient**, c'est exactement le défaut et c'est vérifiable à la revue. Le repli (exposer les comptes
  bruts) est meilleur que la règle : il rend le ratio reconstructible par l'appelant.
- (1) interdire `current_date`/`now()` nus : **tient sur le principe**, mais le décompte du constat (« 2
  fonctions avec `current_date` ») ne vaut que pour les fonctions lisant le GSC. Mon balayage confirme
  `cooked_page_index` et `seo_to_contact_funnel` comme les deux seules touchant les tables GSC avec
  `current_date` — sur ce périmètre le chiffre est bon. Interdire `now()` tout court serait en revanche
  ingérable : `now() - make_interval(...)` est le patron dominant côté Cooked et n'est pas fautif en soi (il
  est cohérent Paris/UTC pour un intervalle glissant). **Cibler `current_date` — qui, lui, est faux en UTC —
  et laisser `now() - interval` tranquille.**

---

```
ID        d-07
Verdict   CONFIRMÉ (y compris l'auto-atténuation en P2, que je valide)
```

**Ma preuve — corps prod.** `pg_get_functiondef('public.cooked_page_index(integer)')` (**lu, jamais exécuté**),
02/09 15:33 Paris. Les deux familles de bornes coexistent bien :

Côté GSC (`current_date`, donc UTC) :
```
FROM public.gsc_query_page_daily WHERE day > current_date - 90 AND NOT gsc_is_branded(query)     (fit)
… g.day > current_date - p_days AND NOT gsc_is_branded(g.query) GROUP BY g.path                  (capq)
WHERE day > current_date - p_days AND gsc_is_branded(query) GROUP BY path                        (capb)
capp AS (… FROM gsc_path_daily WHERE day > current_date - p_days GROUP BY path)                  (capp)
coalesce(sum(clicks) FILTER (WHERE day > current_date - p_days),0) c1,
coalesce(sum(clicks) FILTER (WHERE day BETWEEN current_date - 2*p_days AND current_date - p_days - 1),0) c0,
```
Côté Cooked (`now()`) :
```
FROM events_human eh WHERE name='pageview' AND occurred_at > now() - make_interval(days => p_days)  (firstpv)
spv AS (… WHERE name='pageview' AND occurred_at > now() - make_interval(days => p_days) …)          (spv)
WHERE e.name='page_exit' AND e.occurred_at > now() - make_interval(days => p_days)
… AND occurred_at > now() - make_interval(days => p_days) GROUP BY eh.path                          (lcp)
```

**Ma preuve — l'asymétrie du momentum, mesurée.** Je n'ai pas appelé la RPC ; j'ai rejoué **ses deux bornes**
sur `gsc_path_daily`, 02/09 15:34 Paris, `p_days = 28` :

| terme | borne | jours distincts | clics |
|---|---|---|---|
| c1 | `day > current_date - 28` | **25** | 4 689 |
| c0 | `day BETWEEN current_date - 56 AND current_date - 29` | **28** | 8 757 |

**Confirmé : les deux termes du rapport n'ont pas la même durée** — 25 jours contre 28. À volume journalier
égal, le rapport c1/c0 vaudrait mécaniquement 25/28 = 0,893 au lieu de 1. Le momentum brut est structurellement
tiré vers le bas.

**Ma preuve — l'atténuation avancée par le constat est correcte.** Le corps contient bien
`site AS (SELECT sum(c1) s1, sum(c0) s0 FROM mom)` : le momentum est normalisé par le site. Un biais de
troncature **uniforme** (toutes les pages perdent les mêmes 3 jours) se compense donc très largement au niveau
page. Et `capq`/`capp` partagent la borne `current_date - p_days`, donc le rapport observé/attendu de `zc` est
interne cohérent. **Le classement P2 plutôt que P1 est justifié** — je valide l'auto-atténuation du constat
plutôt que de la gonfler.

**Écart** — sur les chiffres, pas sur le défaut :
- « 24 jours / 4 548 clics » → je mesure **25 jours / 4 689 clics** (lag passé à J-3). Même remarque que d-03 :
  le déficit respire avec le lag Google.
- « ~14 % de sous-estimation de `clics_perdus` » → sur ma fenêtre, le déficit est de 12,5 %. Ordre de grandeur
  correct, chiffre daté.
- **Point que le constat manque** : `cooked_page_index` figure aussi dans mes 29 routines lisant `events_human`
  **sans filtre spam** (d-05). Ses termes `firstpv`, `spv` et `lcp` ingèrent donc les 1 899 sessions spam, dont
  les ~19 210 `engagement_tick`. L'atténuation « le momentum est normalisé par le site » ne couvre pas ce
  volet-là, car le spam n'est **pas** uniforme entre pages (98,7 % sur une page, 24 % sur une autre — d-05).
  **d-07 et d-05 interagissent sur le CPI, et cette interaction n'est pas uniforme, donc pas auto-compensée.**
  Cela ne change pas mon verdict P2 sur le défaut de fenêtre décrit, mais c'est une aggravation à porter au
  dossier CPI.

**Invariant : le second tient, le premier est le même que d-03 (donc même réserve).**
- Journaliser dans `cpi_daily` le nombre de jours GSC réellement couverts : **tient**, et c'est le meilleur des
  deux — il rend le défaut lisible sans rien recalculer, et il transforme un biais invisible en colonne.
  Refuser d'écrire le snapshot si jours ≠ `p_days` serait en revanche **contre-productif** : avec un lag J-3/J-4
  permanent, la condition serait fausse tous les jours et bloquerait le snapshot quotidien. **À poser en
  journalisation, jamais en garde bloquante.**
- Le test CI de d-03 : **tient sous la forme corrigée que j'ai donnée en d-03** (liste blanche), pas sous la
  forme « aucun littéral de date ».

---

```
ID        d-08
Verdict   CONFIRMÉ sur (a) (b) (c) (d) ; la sévérité de (d) est surestimée
```

**Ma preuve — le catalogue.** `pg_proc` + `pg_namespace`, 02/09 15:17 Paris. Les quatre paires existent bien :

```
macro_contacts_by_path(integer)                   secdef=true
macro_contacts_by_path(date,date)                 secdef=true
gsc_top_queries_for_path(text,integer,integer)    secdef=true
gsc_top_queries_for_path(text,text,integer)       secdef=true
page_reads(integer)                               secdef=false   ← SECURITY INVOKER
page_reads(timestamptz,timestamptz)               secdef=true    ← SECURITY DEFINER
```

**(a) — CONFIRMÉ.** Mesuré (cf. d-02) : `Σ macro_contacts_by_path(28)` = **188** = fenêtre `live` (jour en cours
inclus), contre **195** sur `live_j1`. Un `(28)` lu comme « 28 jours » est bien « 27 jours + le jour en cours ».

**(b) — CONFIRMÉ.** Corps prod des deux surcharges, lignes de bornes :
```
gtq(days_back)    : AND gqp.day >= (now() AT TIME ZONE 'Europe/Paris')::date - (days_back - 1)
gtq(period_kind)  : SELECT n_start, n_end FROM public.cooked_period_bounds(p_period_kind, 'cross') LIMIT 1
                    AND gqp.day >= b.n_start
```
Le second est aligné et borné haut, le premier ni l'un ni l'autre. **Un appel `('/x', 28, 20)` résout
silencieusement vers la surcharge non alignée** — le piège décrit est réel.

**(c) — CONFIRMÉ, et plus large que le constat.** `has_function_privilege('anon', …, 'EXECUTE')` :
```
page_reads(timestamptz,timestamptz) = true      ← SECURITY DEFINER + exécutable par anon
page_reads(integer)                 = true
```
Le constat ne mentionne que la surcharge `(ts,ts)`. **Les deux sont exécutables par `anon`.** La `(integer)`
étant SECURITY INVOKER, elle est probablement inoffensive en pratique (elle s'exécute avec les droits de
l'appelant sur les tables de base) — mais elle délègue à la `(ts,ts)`, qui est DEFINER : **la chaîne
`page_reads(integer)` → `page_reads(ts,ts)` DEFINER est appelable par `anon`.** Je m'arrête là : la
qualification du risque revient à la zone (h). Le point sémantique du constat (« non redondante, grain
session×path unique ») est correct et je ne le conteste pas.

**(d) — CONFIRMÉ sur le fond, sévérité à revoir.** Définition prod lue par `pg_get_viewdef` :
```sql
SELECT path, impressions_total, clicks_total, position_avg, ctr_pct
  FROM gsc_path_metrics(
    ((now() AT TIME ZONE 'Europe/Paris')::date - '28 days'::interval)::date,
    (now() AT TIME ZONE 'Europe/Paris')::date)
```
Bornes incluses ⇒ **29 jours nominaux** pour une vue nommée `_28d`, non alignée GSC. Mesurée à **4 896 clics**
(02/09 15:22), troisième valeur face à 4 689 et 5 358. Consommateurs : `grep -rn` hors `.git` → aucun dans le
code ; deux mentions documentaires (`docs/ROADMAP-sprint38-handoff.md:94` et `:234`, cette dernière disant déjà
« 0 dépendant en prod »). **Candidat DROP confirmé.**

**Écart** :
1. **La vue n'est PAS exposée.** `has_table_privilege('anon','public.gsc_path_metrics_28d','SELECT')` = **false**
   — et la migration d'origine `20260524220000_pulse_helpers.sql:151-152` fait explicitement
   `REVOKE … FROM public, anon, authenticated` puis `GRANT … TO service_role`. C'est de la surface morte, pas
   une surface exposée. Le constat ne prétend pas le contraire, mais l'impact « surface d'API » mérite d'être
   scindé : (c) est exposé à `anon`, (d) ne l'est pas.
2. (c) : les **deux** surcharges sont exécutables par `anon`, pas seulement celle citée.

**Invariant : la règle sur les overloads tient, la gate « ≥ 1 consommateur » est dangereuse en l'état.**
- Interdire deux surcharges dont les fenêtres ne dérivent pas de la même source, et privilégier
  `p_period_kind` / bornes explicites sur `days_back` : **tient**, c'est directement ce qui a produit d-02 et
  d-03. Supprimer `gsc_top_queries_for_path(days_back)` supprime le piège plutôt que de le documenter — c'est
  le bon geste.
- E12 (« toute routine publiée a ≥ 1 consommateur détecté », en gate CI) : **décoratif et risqué.** Le détecteur
  est un `grep` du repo — c'est le constat lui-même qui l'écrit en `[non recoupé]` (« un appel ad-hoc humain ou
  un script hors repo ne serait pas détecté »). Or l'ad-hoc **est** le mode d'usage principal de Cooked : une
  gate CI qui échoue sur les routines sans consommateur *dans le repo* condamnerait précisément les briques
  d'analyse ad-hoc que le système est fait pour offrir, et pousserait à les supprimer. **À garder comme rapport
  d'inventaire, jamais comme gate bloquante.**

---

```
ID        o-14
Verdict   PARTIEL — le trou de code est CONFIRMÉ ; l'impact annoncé (« classés direct/organique ») est RÉFUTÉ
```

**Ma preuve — le corps.** `pg_get_functiondef('public.classify_channel(text,text,text,text)')`, 02/09 15:35
Paris : **0** ligne contenant `gclid`, `gbraid` ou `wbraid` ; **0** ligne contenant `url`. La fonction ne reçoit
même pas l'URL en paramètre (signature : `referrer_hostname, utm_source, utm_medium, self_host`). **Le trou est
structurel, pas un oubli de branche** : l'information n'est pas disponible dans la fonction.

**Ma preuve — mesure.** 02/09/2026 15:36 Paris, `events_human`, 1re pageview de session, fenêtre Paris
05/08→01/09 :

```
sessions              = 11 067
paid                  =  1 472
paid avec gclid       =  1 219
non-paid avec gclid   =     19
```

`paid` = 1 472 : **identique au constat**. Le nombre d'entrées à `gclid` classées hors `paid` est **19** (contre
18) — soit **1,27 %** des 1 491 entrées porteuses d'un `gclid`. Le défaut est reproduit.

**Ma preuve — la décomposition, que le constat n'a pas faite** (règle « une maille en dessous ») :

| canal attribué aux 19 entrées à `gclid` hors `paid` | n |
|---|---|
| `gmb` | **16** |
| `direct` | 3 |
| `organic_*` | **0** |

**Le constat écrit « 1,2 % des clics Ads classés direct/organique ». C'est faux : aucune n'est classée
organique, et 16 sur 19 (84 %) sont classées `gmb`.** L'impact réel n'est pas une fuite vers l'organique — ce
qui aurait pollué le CPI, dont toutes les composantes filtrent `organic%` — mais un chevauchement entre `paid`
et `gmb`.

**Et cela retourne l'invariant proposé.** Ces 16 entrées portent à la fois `utm_source=gmb` et un `gclid` :
ce sont vraisemblablement des annonces servies sur la fiche / les résultats locaux, **légitimement les deux à
la fois**. Ajouter un test `gclid ⇒ paid` prioritaire les reclasserait en `paid` et **viderait d'autant le canal
`gmb`, que le restatement `classify_channel` v3 du 27/07/2026 a précisément créé** (CLAUDE.md : GMB convertit à
3,68 % contre 0,57 % pour le SEO réel — un canal à fort enjeu de décision). Le correctif naïf provoquerait donc
un nouveau restatement de canal, exactement la famille d'incident que o-14 dit vouloir prévenir.

**Écart** — sévérité P3 maintenue (1,27 %, effet nul sur le CPI), mais :
1. « classés direct/organique » : **réfuté**. 0 organique, 3 direct, 16 `gmb`.
2. Le cas majoritaire n'est pas une erreur de classement mais une **ambiguïté de définition** (paid ∩ gmb) que
   le modèle à canal unique ne peut pas représenter. Ce n'est pas le même problème.
3. `paid avec gclid` : 1 219 chez moi contre 1 185 — j'ai testé `(gclid|gbraid|wbraid)=` par regex, le constat
   probablement `gclid` seul. Sans effet.

**Invariant : décoratif tel qu'il est formulé, et il faut d'abord trancher une question de définition.**
Des vecteurs de test `(referrer, utm, url) → canal` rejoués en contract-test sont un bon mécanisme — mais un
vecteur ne peut être écrit qu'une fois décidé **ce que doit rendre une entrée `utm_source=gmb` + `gclid`**.
C'est une décision produit (Nicolas), pas une décision technique : elle déplace des contacts entre deux canaux
dont l'écart de conversion est de 6× et déclencherait un restatement. **Poser les vecteurs avant d'avoir tranché
figerait un arbitrage pris par défaut.** L'invariant utile en premier : que `classify_channel` **reçoive** l'URL
(elle ne l'a pas aujourd'hui) et qu'une entrée puisse porter un marqueur `paid` **en plus** de son canal, plutôt
qu'à sa place.

---

# Note transversale — ce que la passe fait apparaître au-delà des constats

Trois constats se croisent d'une manière qu'aucun ne décrit isolément :

1. **d-05 est en amont de d-04.** Le spam n'est pas seulement un sur-comptage de vues : ses ~10
   `engagement_tick` par session étirent la durée au-delà du seuil de 10 s, donc ces sessions entrent au
   dénominateur du rebond sans entrer au numérateur. Toute RPC lisant `events_human` en direct rend un taux de
   rebond **dilué**. C'est le candidat principal aux 11 points de d-04, que la fenêtre n'explique pas
   (0,76 pt mesuré).
2. **d-05 est aussi en amont de d-07.** `cooked_page_index` lit `events_human` sans filtre spam, et le spam
   n'est pas uniforme entre pages (98,7 % / 24 %). La normalisation par le site qui sauve le momentum de d-07
   ne protège pas de ce biais-là.
3. **Corollaire de méthode.** d-02, d-03 et d-07 produisent des chiffres qui **changent avec l'heure de
   lecture** — je l'ai vérifié malgré moi en re-mesurant 5 h après les constats (contacts `live` 183 → 188,
   fenêtre GSC 24 j → 25 j). Aucun de ces chiffres ne devrait être livré sans sa fenêtre et son horodatage. Le
   correctif de d-02 (1) — faire porter `n_start`/`n_end` par la sortie — est le seul invariant du lot qui
   traite la cause commune plutôt qu'un symptôme.
