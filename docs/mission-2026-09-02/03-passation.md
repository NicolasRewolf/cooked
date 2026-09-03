# 03 — Passation (intermédiaire, ARRÊT 1) — mission Cooked 02/09/2026

> Écrit à la fin de la Phase 2 (02/09/2026 20:20 Paris). La version finale viendra après les Phases 3‑4.
> Registre : celui du §2 de `ROADMAP-sprint38-handoff.md` — sans langue de bois.

## État exact (mis à jour 03/09/2026 07:20)

- **T‑01 exécuté et vérifié** (02/09 20:23 → 03/09 07:04) ; **T‑12 exécuté par une session Cursor parallèle** (PR #124,
  02/09 23:00→00:08) : gate `prod-drift` verte, `rpcs.sql` régénéré (124 fonctions), `doc_constants.json`, 7 migrations
  re‑datées, miroirs T‑01/weekly. Ma migration `20260903050701` (rôle CI) est redondante et mirrorée.
- **T‑02** (rotation de la clé publishable, relecture des logs) : action Nicolas, non faite à ma connaissance.
- **Vague 1 validée** (T‑03, T‑04 sans purge, T‑05+T‑06 fusionnés option b, T‑08 [objectif à fournir], T‑09) : à
  exécuter en sessions fraîches, une par ticket, en commençant par relire ce dossier.


- **Fait** : `00-baseline.md` (photo « avant », 35 requêtes), `01-audit.md` (86 constats, 81 réfutés fail‑closed :
  70 confirmés / 11 partiels / 0 réfuté ; 19 contre‑vérifiés à la main ; 7 causes racines ; 13 invariants),
  `02-plan.md` (22 tickets en 4 vagues, 8 décisions), 22 issues GitHub (#102‑#123). Livrables bruts des 18 agents
  dans `annexes/`.
- **Pas fait, volontairement** : aucune écriture prod (pas même l'acquittement des 51 alertes) ; aucun push ; pas
  de recoupement Google Ads (MCP sans `GOOGLE_ADS_DEVELOPER_TOKEN`) ; pas d'appel de `rpc_contract_check` ni de
  `cooked_page_index(28)` ; pas de lecture de PII au‑delà des comptes.
- **En attente de Nicolas** : validation des tickets (bloc ou un par un, citée mot pour mot) ; les 8 décisions du §7
  de `02-plan.md` ; secret CI lecture seule (T‑12) ; collages Wix (T‑17, T‑18) ; valeur de l'objectif trimestre (T‑08).

## Ce qui reste ouvert et qui n'est pas dans un ticket

- La cause des 11 points d'écart résiduel de `cooked_bounce_rate` (d‑04) — à instruire dans T‑03.
- La cause de la troncature à 105 caractères d'un path de `page_taxonomy` (e‑06).
- La réception réelle des pushs ntfy (à confirmer par Nicolas sur son téléphone).
- L'exploitation éventuelle de l'exposition h‑01 au‑delà des 24 h de logs (T‑02).

## Ce que je referais autrement

- **Lancer 9 agents Opus en parallèle a consommé la limite de session deux fois** (≈10:10 et ≈15:50 ; 4 h 30 de
  réinitialisation cumulées). La prochaine fois : 3 à 4 agents à la fois, réfuteurs en Sonnet pour les zones sans
  P0/P1 de chiffre, et un fichier de livrable écrit **au fil de l'eau** par les agents (les deux coupures ont
  frappé pendant l'écriture finale).
- **Mesurer la baseline hors spam** : trois lignes de `00-baseline.md` ont été contaminées par un bot que la zone (a)
  n'a trouvé qu'en Phase 1. Le réflexe « décomposer une maille en dessous » aurait dû s'appliquer à `user_agent`
  dès la Phase 0.
- **Lire les corps de fonction en prod, jamais dans `rpcs.sql`** : le fichier était faux sur 12 fonctions, dont les
  deux du cœur des alertes.
- Les briefs de réfutation contenaient parfois des chiffres du jour (fenêtres glissantes) : plusieurs « écarts »
  ne sont que des effets d'heure. Figer une date de mesure commune (`paris_today()-1`) dans les briefs.
