# Scripts SQL manuels (Supabase SQL Editor)

**Source de vérité :** `supabase/migrations/*.sql` (versionné, rejouable via Supabase CLI ou le dashboard).

**Usage normal (prod)** : laisser les migrations s’appliquer automatiquement. Ne pas copier-coller les `APPLIQUER_*.sql` sauf urgence ou rattrapage d’une env qui n’a pas le CLI.

## Ordre des migrations récentes (référence)

| Migration | Rôle |
|-----------|------|
| `20260529120000` + `20260529120100` | 3 zones données : `gsc_last_data_day`, `cooked_period_bounds(live/gsc/cross)`, RPCs par lens |
| `20260528120000` | DRY macro contacts + `gsc_top_queries` par `period_kind` |
| `20260527120000` | Exclusion candidatures dans `form_submit` |
| `20260526100000` | `cooked_period_bounds` + KPIs par période |
| `20260525160000` | Index GSC/DFS : composites `(path, day)` puis drop redondants |
| `20260525170000` | Index fonctionnel Paris-date sur `events` |
| `20260530120000` | Drop index `query` inutilisés, `canonical_path` search_path, `ANALYZE` GSC |

Liste complète : `supabase/migrations/`.

## Fichiers `APPLIQUER_*.sql` (rattrapage manuel uniquement)

Doublons historiques du SQL Editor — **dépréciés** dès qu’une migration équivalente existe :

| Script | Remplacé par |
|--------|----------------|
| `APPLIQUER_periodes_dashboard.sql` | `20260526100000_cooked_period_bounds.sql` |
| `APPLIQUER_exclure_candidatures.sql` | `20260527120000_form_submit_exclude_recruitment.sql` |
| `APPLIQUER_20260528_macro_dry.sql` | `20260528120000_macro_dry_and_gsc_period.sql` |
| `APPLIQUER_20260528_perf_dashboard.sql` | `20260528140000` + `20260528141000` |
| `APPLIQUER_20260529_data_lens.sql` | `20260529120000` + `20260529120100` |

En cas de doute, **toujours** préférer `migrations/`.

## Validation après migration périodes

`validate_period_bounds.sql` — contrôles visuels sur `cooked_period_bounds('rolling_28', 'live'|'gsc'|'cross')`.

## Post-deploy index (si migration 301200 déjà passée sans ANALYZE)

```sql
ANALYZE public.gsc_path_daily;
ANALYZE public.gsc_query_daily;
ANALYZE public.gsc_query_page_daily;
```
