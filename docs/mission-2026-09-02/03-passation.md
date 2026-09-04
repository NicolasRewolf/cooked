# 03 — Passation finale — mission Cooked 02/09/2026

> Écrite le **04/09/2026 à 09:50 Paris**, à la fin de la Phase 4 ; **mise à jour 04/09 12:15**
> (collages Wix, secret, ntfy, annotations, dédup CRM, CNIL 13 mois). Registre : celui du §2 de
> `ROADMAP-sprint38-handoff.md` — sans langue de bois. La passation intermédiaire de l'ARRÊT 1
> (02/09 20:20) est conservée en fin de fichier pour l'historique.

## État exact

**Les 20 tickets `ready-for-agent` sont livrés** (T-01, T-03 → T-20 ; T-21/T-22 absorbés par T-19),
chacun au sens strict de la mission : PR mergée CI verte, migration appliquée **et** mirrorée au timestamp
prod, `rpcs.sql` régénéré depuis la prod, effet vérifié en prod, docs à jour, ligne de journal. PRs #124 → #146.
Deux jours (02/09 01:12 → 04/09 09:50), 49 migrations prod (`20260902182316` → `20260904073502`), 4 versions
Edge (`track` v28 → v30, `form-webhook` v14 → v15), tracker `sprint42` sur `main`.

Ce que la re‑mesure (`02-apres.md`) établit, en trois chiffres qui comptent :

- **Contacts macro 28 j = un seul chiffre partout** : 193 (07/08 → 03/09, clos J‑1) dans les cinq RPC de
  contacts — avant : 182 / 183 / 189 / 195 selon la fonction appelée.
- **`events_human` sans le bot Baidu** : −11 % d'events, `browser` inconnu sur les pageviews 16 % → 2,2 %,
  `page_exit` apparié desktop 60 % → 95 %. Quatre mois de chiffres « humains » contenaient un robot.
- **Surface d'attaque** : 0 fonction ni vue exposée à `anon`/`authenticated`, 0 GRANT relation, default
  privileges révoqués (tables, séquences, fonctions), advisors 0 ERROR ; 48 alertes muettes → 2 alertes
  vraies et attendues.

Les invariants (14, `02-apres.md` §4) sont tous sous gate : CI (prod‑drift, docs‑constants, sql‑contracts,
tracker, Edge, dashboard, python), contract‑tests nocturnes (51), règles d'alerte (19), registre de fraîcheur (15).

**Le dernier snapshot CPI est celui du 03/09** (version de définition 2.2.5). Celui du 04/09 s'écrira après
l'ingestion GSC du jour (~12:30 Paris) : **la vérification J+1 du restatement T-05/T-06/T-09 se lit après**,
et elle conditionne le DROP de `cpi_pre_restatement_20260903` (condition posée par Nicolas sur #120).

## Ce qui reste ouvert — actions Nicolas (aucune n'est bloquante pour la mesure)

| # | Action | Ticket / doc | Effet attendu |
|---|---|---|---|
| 1 | ~~**Coller `wix/tracker.min.html`** (sprint42)~~ **FAIT 04/09 10:12** — dans le Custom Code Wix, puis `UPDATE cooked_config SET value='sprint42' WHERE key='expected_tracker_version'` (migration) | T-17 (#118) | CLS = 0 explicite ; sans le collage `tracker_drift` reste muet et la prod tourne en sprint41 (fonctionnellement équivalent) |
| 2 | ~~Coller `masterpage-cooked.js` + `http-functions.js` + champs cachés~~ **FAIT 04/09 matin** — publiés ; Divorce et Demande dossier ont `page_source` + objet. Alerte `form_fields_missing` **reste** jusqu'au prochain vrai envoi (les 28 j d'avant n'ont pas le champ) | T-18 (#119) | le prochain Divorce / dossier porte `page_source` |
| 3 | ~~Poser le secret GitHub `WIX_API_KEY`~~ **FAIT 04/09** — dry-run `wix-taxonomy-sync` n° 33854781065 : 434 posts, 0 à insérer | T-15 (#116) | synchro hebdo lundi 05:00 UTC |
| 4 | **T-02** : **ne pas** désactiver les clés JWT (`Disable JWT-based API keys`) — Vercel et Wix sont déjà en `sb_publishable` / `sb_secret` ; le bouton tuerait aussi `service_role` JWT encore utilisé ailleurs | #103 **reste ouverte** | h‑01 fermé côté exposition ; rotation JWT = plus tard, quand tous les secrets sont `sb_secret_` |
| 5 | Lire la vérif J+1 du 04/09 (`cpi_movers`, 0 mover fiable inexpliqué attendu), puis `DROP TABLE cpi_pre_restatement_20260903` (migration) | #120, `docs/cpi-cooked-page-index.md` | **en attente** : GSC du 04/09 pas encore arrivée (dernière ingest 03/09 12:35 Paris) |
| 6 | Après le 01/10/2026 : DROP des overloads dépréciés `gsc_top_queries_for_path(text, integer, integer)` et `macro_contacts_by_path(integer)` (COMMENT « déprécié »), 4 appelants RPC à basculer | #120 | — |
| 7 | ~~**CNIL 13 mois**~~ **FAIT 04/09 11:19** — `purge_old_events` passe de 400 j à `interval '13 months'` (`20260904091903`) ; 0 ligne à supprimer aujourd'hui ; 1er run utile ≈ 06/2027 | #120 | politique posée |
| 8 | ~~2 doublons `crm_prospects`~~ **FAIT 04/09** — 2e envoi retiré (17/04 import + 25/08 webhook) ; 0 doublon email×minute ; `crm_prospects` = 856 | T-16 (#117) | comptes du pont exacts à l'unité |
| 9 | ~~Relire les 3 libellés d'annotation T-20~~ **FAIT 04/09** — Nicolas les a validés tels quels | T-20 (#121) | — |
| 10 | ~~Confirmer ntfy~~ **FAIT 04/09** — Nicolas a reçu les push | `cooked_config.ntfy_topic` | chaîne d'alerte vérifiée de bout en bout |
| 11 | Verdict Google Business Profile (~10-15/09) puis réactivation du cron GBP | ROADMAP #5 | `gbp_daily_stale` critical s'éteint |

Reste vraiment ouvert pour Nicolas : **T-02 (#103, ne pas cliquer)**, **vérif CPI J+1 puis DROP de la photo 03/09**, **overloads après le 01/10**, **GBP ~10-15/09**. Cookiebot (`_ckd` / `_ckd_aid` à classer Nécessaire) : Nicolas gère hors mission.

## Ce qui reste ouvert — hors tickets (à mettre au ROADMAP, fait)

- **Parité sémantique `views.sql` ↔ prod** : 11/11 noms mais le fichier est reformaté à la main ; aucune gate ne
  le compare (zone i). Petit : faire générer `views.sql` par le même workflow que `rpcs.sql`.
- **3 copies littérales `m.baidu.com`** dans des corps RPC (`rpcs.sql:2426`, `:4640`, `:4846`) au lieu de
  `cooked_is_spam_referrer()` — même chaîne, aucun chiffre faux, mais une divergence future n'aurait pas de
  test.
- **`CLAUDE.md` = 1 252 lignes** (+140 pendant la mission : 3 règles absolues et des notes T‑xx). T-14 a retiré
  du récit, la mission en a remis. Le fichier reste lisible mais gagnerait un déplacement des blocs « Sprint
  37/38/39 » vers `HISTORY-sprints.md`.
- **Chute de ~40 % des clics GSC depuis le 27/07** : non instruite (ROADMAP #12) ; le momentum du CPI est relatif
  au site, donc il ne la voit pas — c'est voulu, mais il faut le savoir en lisant les « ↗ ».
- **18 fonctions SECURITY INVOKER exécutables par `anon`** (helpers purs + `cooked_page_index`,
  `cooked_cpi_snapshot`) : inertes sans grant sur les tables, mais une révocation de cohérence coûterait dix
  lignes ; laissé tel quel pour ne pas toucher `paris_date`/`paris_today` (contrat d'inlining) sans besoin.

## Ce que je referais autrement (Phases 3-4)

- **Le faux positif `gsc_ingest_missed` est à moi** (T-11, 03/09) : une garde en heure UTC et une comparaison en
  jour Paris dans la même fonction. Il a sonné dès la première nuit. La règle que j'aurais dû m'appliquer :
  *une règle d'alerte se teste sur les 24 heures d'une journée simulée avant d'être mise en prod* — les
  contract‑tests savent le faire (`rpc_contract_check` avec un `now()` figé n'existe pas encore ; c'est le
  petit outil qui manque).
- **La re‑mesure a trouvé trois défauts de plus** (default privileges tables/séquences, vue sans
  `security_invoker`, fonction T-15 sans `search_path`). Deux sont antérieurs à la mission, un est une
  régression de la mission. Le prod‑drift ne les voyait pas parce qu'il compare des listes, pas des ACL de
  tables : une gate `has_table_privilege('anon', t, 'TRUNCATE') = false` sur toutes les tables serait la
  suite logique de `alert_rule_exposure()`.
- **Journal d'heures** : mes horodatages ont dérivé de +1 h en fin de nuit (recalibrés sur les versions de
  migration, en UTC). Écrire l'heure depuis `now()` de la base, pas de tête.
- **Un lot de requêtes MCP trop gros** (Q‑13 → Q‑18 en un appel) a dépassé le budget de la fonction
  `execute_sql` : trois appels séparés suffisent et n'ont aucune incidence prod. Découper d'abord.
- **Ce qui a bien marché et que je garderais** : une PR par ticket, régénération de `rpcs.sql` par le workflow
  puis commit vide de relance, journal écrit avant de pousser, et la lecture des corps de fonction **en prod**
  avant toute modification.

---

## Annexe — passation intermédiaire (ARRÊT 1, 02/09/2026 20:20, mise à jour 03/09 07:20)

- **T‑01 exécuté et vérifié** (02/09 20:23 → 03/09 07:04) ; **T‑12 exécuté par une session Cursor parallèle** (PR #124,
  02/09 23:00→00:08) : gate `prod-drift` verte, `rpcs.sql` régénéré (124 fonctions), `doc_constants.json`, 7 migrations
  re‑datées, miroirs T‑01/weekly. Ma migration `20260903050701` (rôle CI) est redondante et mirrorée.
- **Fait** : `00-baseline.md` (photo « avant », 35 requêtes), `01-audit.md` (86 constats, 81 réfutés fail‑closed :
  70 confirmés / 11 partiels / 0 réfuté ; 19 contre‑vérifiés à la main ; 7 causes racines ; 13 invariants),
  `02-plan.md` (22 tickets en 4 vagues, 8 décisions), 22 issues GitHub (#102‑#123). Livrables bruts des 18 agents
  dans `annexes/`.
- **Pas fait, volontairement** : aucune écriture prod ; aucun push ; pas de recoupement Google Ads (MCP sans
  `GOOGLE_ADS_DEVELOPER_TOKEN`) ; pas de lecture de PII au‑delà des comptes.
- **Ce que je referais autrement (Phases 0-2)** : 9 agents Opus en parallèle ont consommé la limite de session deux
  fois → 3 à 4 agents à la fois, réfuteurs en Sonnet, livrable écrit au fil de l'eau ; mesurer la baseline hors
  spam (trois lignes contaminées par le bot trouvé en Phase 1) ; lire les corps de fonction en prod, jamais dans
  `rpcs.sql` ; figer une date de mesure commune dans les briefs.
