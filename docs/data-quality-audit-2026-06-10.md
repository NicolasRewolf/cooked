# Audit qualité des données — 10/06/2026 (Sprint 37, post-déploiement)

Audit complet de Cooked comme « source de vérité » : events, GSC, pipeline.
Réalisé en prod (lecture seule) dans la nuit du 09 au 10/06, juste après la
mise en ligne du tracker sprint37. Verdict global : **sain**. Chaque bruit
résiduel est qualifié ci-dessous avec son ampleur exacte.

## 1. Events (fenêtre 90 jours)

| Contrôle | Résultat |
|---|---|
| Paths NULL (hors form server) | **0** |
| Hostnames étrangers | **0** |
| scroll > 100 % | **0** |
| Durées négatives | **0** |
| Noms d'events hors taxonomie | **0** |
| Doublons même-seconde post-dédup S37 | **0** |
| Events « futurs » (occurred > received +5 min) | 1 127 (**0,28 %**) |
| — dont décalés > 24 h (mauvais jour Paris possible) | **15 / 90 j** |
| Durées > 4 h | 2 |
| engagement_tick avec active_ms > 60 s | 9 |
| Events sans `props._v` postérieurs au Sprint 26 | ~49 / 2 semaines |

Qualification des trois bruits :
- **Horloge client** : `occurred_at` vient du navigateur ; 0,28 % des
  visiteurs ont une horloge déréglée. Seuls les 15 events à > 24 h peuvent
  atterrir sur le mauvais jour dans les agrégats Paris. Fix spécifié (P2,
  cf. roadmap) : clamp à l'ingestion dans l'Edge `track`.
- **Ticks aberrants** (9) : probable suspension/reprise d'onglet mobile.
  Négligeable ; cap possible à l'ingestion (P2).
- **Sans version récents** : visiteurs servant des pages en cache
  pré-Sprint 26 (profil dominant : iPhone iOS 18.7). Vrais humains, vieux
  tracker — longue traîne de cache, à NE PAS exclure.

## 2. GSC

- **Authentification : Service Account** (PAS d'OAuth utilisateur), scope
  `webmasters.readonly`, credentials en GitHub Secrets (base64), écrits en
  `$RUNNER_TEMP` chmod 600, jamais loggés, cleanup `if: always()`.
  Révocable d'un clic dans GCP. Architecture saine.
- **Auto-cicatrisation** : le daily (`gsc-daily-ingest.yml`, 06:00 UTC)
  re-fetch `--months 1` et upserte → toute ingestion ratée se répare seule
  sous 24 h.
- **Intégrité interne (90 j)** : 0 doublon de clé `(path, day)` et
  `(query, path, day)` ; 0 jour où `sum(query_page.clicks) >
  path_daily.clicks`.
- **Jour manquant : 31/05/2026.** Redemandé à Google ~10 fois par le daily
  glissant → le trou est côté API Google, pas côté pipeline. Aucune action.
- Fraîcheur au moment de l'audit : dernier jour 07/06 (normal — lag GSC J-2
  + run de 06:00 UTC pas encore passé).

## 3. Pipeline & stockage

- `refresh_pipeline_health()` : **healthy, issues: []** (snapshot, cron,
  events temps réel, GSC, DFS tous verts).
- `events` : 406 MB / 403 544 rows, **49 dead tuples** → ce n'est pas du
  bloat, c'est le poids légitime des `props` jsonb + index. La purge de
  `payload_meta` > 90 j reste un P2 d'optimisation, pas de fiabilité.
- Alertes actives : 2, les deux attendues (`double_embed_suspect` — devenue
  inoffensive grâce au garde sprint37, extinction < 24 h ;
  `form_attribution_degraded` — extinction dès les premières soumissions
  avec champs cachés).

## 4. Conclusion

Aucune « hallucination » : la seule falsification systémique de l'historique
était le double-embed (+13,6 % de faux `cta_phone_click`), corrigée
rétroactivement au Sprint 37 et surveillée par alerte. Chaque chiffre produit
par les RPCs est traçable jusqu'à l'event brut.

**Restatement à communiquer à Me Plouton** : contacts téléphone 28 j
110 → 95. C'est une correction de mesure, pas une baisse d'activité.
