## Résumé

<!-- Quoi et pourquoi (1-3 phrases) -->

## Changements

-

## Checklist

- [ ] CI verte (`gh pr checks`)
- [ ] Migration prod appliquée = fichier dans `supabase/migrations/` (même PR)
- [ ] `latest_rpc_health()` + advisors vérifiés après migration
- [ ] Si RPC modifiée : `supabase/rpcs.sql` + `contracts/rpc_snapshot_meta.json` régénérés
- [ ] Si tracker : `python3 scripts/minify-tracker.py` OK (< 15 000 car.)
- [ ] [CHANGELOG.md](CHANGELOG.md) mis à jour si changement notable
- [ ] Pas de secret / credential dans le diff

## Test plan

-
