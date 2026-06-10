# CPI — Cooked Page Index (v2.1, Sprint 38)

Score de santé 0-100 par page, calculé sur 28 jours glissants. Croise GSC
(capture) et Cooked (rétention, lecture, conversion), avec momentum relatif
au site et gate technique LCP.

## Usage

```sql
-- Classement complet
SELECT * FROM cooked_page_index(28) ORDER BY cpi ASC;

-- Les malades certifiés (à traiter en priorité)
SELECT path, cpi, zc, zr, zl, zv, momentum_badge, clics_perdus
FROM cooked_page_index(28)
WHERE grade IN ('A','B') AND cpi < 35 ORDER BY n_org DESC;

-- Trajectoire d'une page (snapshot quotidien, cron 07:30 UTC)
SELECT day, cpi, zc, zv, momentum FROM cpi_daily
WHERE path = '/post/...' ORDER BY day;
```

## Grille de lecture

| CPI | État |
|---|---|
| > 75 | champion |
| 50-75 | sain |
| 35-50 | à surveiller |
| < 35 | malade |

**Grades de confiance** : A = verdict (n_org≥100, E≥20) · B = solide · C = hypothèse.
Règle d'or : **le CPI trie, les quatre z diagnostiquent** — ne jamais lire le
nombre sans ses composantes.

## Les quatre z (vs pairs du même type de page, robustes médiane/MAD)

- **zc capture** : clics réels vs attendus à ces positions (courbe CTR propre
  au site, loi de puissance R²=0,917, branded exclu). zc<0 = snippet malade.
- **zr rétention** : survie des 15 premières secondes (organique).
- **zl lecture** : profondeur qualifiée *parmi les retenus* (seuils = médianes
  du type). Orthogonal à zr par construction.
- **zv conversion** : contacts directs + assists dilués (1/longueur du
  parcours) + 0,25×bookings, par entrée organique, lissage empirical Bayes.

`momentum` ∈ [0,71-1,40] : tendance clics **relative au site** (une marée qui
baisse partout ne punit personne). `couv_gsc_pct` : part des impressions dont
Google révèle la requête (peut descendre à 6 % — d'où le scaling v2.1).

## Archétypes détectés (run de validation 10/06/2026)

- zc−− zl−− zv−− : **dictionnaire** (mis-en-cause, période-de-sûreté)
- zc−− zr++ zl++ zv−− : **mauvaise cible** — lus à fond, jamais clients (bail-commercial)
- zv−− M↘ : **hors-périmètre qui décline** (loi Badinter, exclue de la CIVI)
- zc−− M↘ : **prochain malade** (casier-judiciaire)
- zv++ M↗ : **étoile montante** (délai-déraisonnable, CTR ×6 l'attendu)

Premier snapshot : 10/06/2026 — 192 pages, CPI pondéré trafic = 32,
446 clics perdus/28j.

## Validation à J+28 (P1)

Spearman(CPI_t, Δcontacts_{t→t+28}) > 0,3 ; calibration courbe CTR ;
ablation par composante ; stabilité des poids ±0,05 (Kendall τ > 0,9).
