@AGENTS.md
@README.md

## Règles dures

1. Les RPC `dashboard_*` sont un **contrat** : leurs corps vivent dans
   `../supabase/rpcs.sql` (miroir lecture). Tout changement passe par une
   migration `../supabase/migrations/` + régénération du miroir
   (`../scripts/generate_rpcs_sql.py` — gate CI).
2. `SUPABASE_SECRET_KEY` est **server-only** : jamais importée ni exposée côté
   client (`src/lib/supabase-admin.ts` est marqué `import "server-only"`).
3. Les données affichées sont des **snapshots quotidiens** en fenêtre close à
   J-1 Paris (lens `live_j1`) — pas de temps réel. Ne pas promettre ni déboguer
   du « live » : la fraîcheur normale, c'est hier soir.
4. « Contacts assistés » = sémantique **visite recousue** (`identity_stitch`)
   depuis le 12/07/2026 — distincte des « contacts » du tableau, comptés au
   path de l'event (voir README, section « Contacts assistés »).
5. **Aucune couleur en dur dans un composant.** Tous les tokens vivent dans
   `src/app/globals.css` (`@theme inline`) ; les SVG les lisent par
   `stroke="var(--color-…)"`. Une teinte qui manque se déclare là-bas, jamais
   dans le JSX. Identité non négociable : angles vifs, orange rewolf `#FF4F04`,
   IBM Plex, thème clair. Voir README, section « Système visuel ».
6. Un **total de pied de tableau** ne s'ajoute que si l'agrégat est juste : pas
   de position moyenne inter-pages (piège n°2 du playbook), pas de médiane de
   médianes. Le CTR s'agrège en Σ clics / Σ impressions (`aggregateCtrPct`).
