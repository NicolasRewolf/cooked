# Scripts SQL manuels (Supabase SQL Editor)

**Source de vérité :** `supabase/migrations/*.sql` (versionné, rejouable).

## Ordre d’application prod (si pas encore fait)

1. `20260526100000_cooked_period_bounds.sql` — sélecteur de périodes
2. `20260527120000_form_submit_exclude_recruitment.sql` — exclusion candidatures
3. `20260528120000_macro_dry_and_gsc_period.sql` — DRY macro + `gsc_top_queries` par période
4. `20260528140000_pages_overview_perf.sql` + `20260528141000_top_contact_pages.sql` — fix timeout dashboard

## Script du jour (perf dashboard — timeout)

Copier-coller : `supabase/scripts/APPLIQUER_20260528_perf_dashboard.sql`

(ou les deux migrations `20260528140000` + `20260528141000`).

## Scripts précédents

`APPLIQUER_20260528_macro_dry.sql` — DRY macro (si pas encore fait).

## Fichiers historiques (dépréciés)

- `APPLIQUER_periodes_dashboard.sql` — doublon de la migration `20260526100000` ; ne plus maintenir.
- `APPLIQUER_exclure_candidatures.sql` — doublon de `20260527120000`.

En cas de doute, toujours préférer le fichier dans `migrations/`.
