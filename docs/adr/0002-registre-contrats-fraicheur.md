# ADR-0002 — Le contrat de fraîcheur des sources est un registre déclaratif

- **Statut** : accepté
- **Date** : 23/08/2026
- **Concerne** : `freshness_contract` (table), `alert_rule_freshness()`,
  `alert_rule_warn_escalation()`, `raise_cooked_alert()`,
  `cooked_alerts_refresh()` — migration `freshness_contract_registre_alertes`.

## Contexte

Deux pannes d'ingestion silencieuses découvertes le 22/08/2026 : l'automation
Wix → `form-webhook` supprimée le 11/08 (11 jours, 22 soumissions perdues,
zéro alerte) et le cron GBP mort le 08/08 (poussé sur ntfy à J+14 seulement).
La revue d'architecture a montré que « cette source est-elle en retard ? »
était réécrit à la main dans 5 fonctions plpgsql (+ `dashboard_check_stale`
+ 5 axes de `refresh_pipeline_health`) avec trois horloges, quatre grandeurs
et des sévérités contradictoires — et qu'**aucune requête ne pouvait dire
quelles sources n'étaient PAS surveillées**. `form_submit`, `crm_prospects`,
`cta_phone_click`, `seo_url_snapshot`, `gsc_query_daily` et les snapshots
dashboard étaient hors radar ; la seule règle qui touchait les formulaires
(`form_attribution_degraded`) se désarme sous 5 soumissions — muette
exactement quand l'ingestion meurt.

## Décision

1. **Un registre, une règle.** Le contrat de fraîcheur de chaque source est
   **une ligne de données** dans `public.freshness_contract` (source, dernier
   point de donnée en SQL, lag normal, seuils warn/critical, fenêtre de trous,
   geste de réparation), évaluée par une unique `alert_rule_freshness()` avec
   une seule horloge (`paris_today()`). Kinds émis : `<source>_stale`,
   `<source>_gap`, `<source>_contract_failed`. Ajouter une source = un INSERT.
2. **Le Silence est un contrat.** Les sources événementielles (`form_submit`,
   `cta_phone_click`, `crm_prospects`) portent des seuils sur l'âge de leur
   dernier événement — forms : warn > 2 j, critical > 4 j (décision Nicolas,
   22/08/2026, baseline ~45 soumissions/mois).
3. **Escalade générique.** Un warn ininterrompu depuis ≥ 5 jours, quel que
   soit son kind, devient critical (donc pousse sur ntfy). **Acker la
   dernière alerte du kind suspend l'escalade et le re-push** — `acked`
   redevient porteur de sens (« vu, je gère »).
4. **Le driver découvre les règles par catalogue** (`pg_proc`, préfixe
   `alert_rule_`, zéro argument) avec isolation par règle : une règle qui
   plante devient une alerte `<règle>_crashed` au lieu d'annuler le tick.
5. **Dédup par (kind, severity)** dans `raise_cooked_alert` : le passage
   warn→critical n'attend plus l'expiration de la fenêtre 24 h du warn.

## Justification

- Les 5 règles supprimées différaient exactement par 4 valeurs et un gabarit
  de message : c'était de la configuration déguisée en code (shallow).
- La panne A aurait sonné à ~72 h (au lieu de jamais), la panne B idem
  (détection par le symptôme ; le chantier « battement d'exécution » ramènera
  la détection de la cause à J+0).
- Le contrat de couverture devient exprimable : `scripts/c2_alerts_contract.sql`
  v2 échoue si une source attendue n'a pas de ligne active — et n'énumère
  plus les règles (découverte par catalogue, il ne peut plus décrocher).

## Conséquences

- Les kinds historiques changent : `gbp_gap` → `gbp_daily_stale`,
  `gsc_gap` → `gsc_path_daily_gap`, `dfs_stale` → `dfs_keyword_volume_stale`,
  `cpi_stale`/`cpi_gap` → `cpi_daily_stale`/`cpi_daily_gap`,
  `dashboard_stale` → `dashboard_resources_snapshot_stale`. L'historique de
  la table `alerts` garde les anciens kinds.
- Un critical persistant non acké **re-pousse chaque jour** (rappel) ; un
  critical acké n'insère plus que la trace, sans notification.
- `identity_stitch` n'a pas de colonne temporelle : couverte par le chantier
  « battement d'exécution » (registre des jobs), pas par ce registre.
- **Différé au chantier 2** : `refresh_pipeline_health()` doit devenir une
  projection de lecture du registre + des épisodes (ses seuils GSC/DFS/events
  contredisent encore le registre, et l'invariant « un critical ouvert ⇒
  status ≠ healthy » n'est pas encore garanti).
- La table est service_role only (RLS deny-all + REVOKE) : ses fragments SQL
  sont exécutés par une fonction SECURITY DEFINER, y écrire équivaut à écrire
  une migration.

## Alternatives écartées

- **Réparer règle par règle** (ajouter `form_gap`, durcir `gbp_gap`…) :
  reproduit le mode d'échec — l'oubli reste le défaut, la 8e copie arrive
  avec SECIB (ROADMAP #9).
- **Un cadre d'ingestion Python générique** : les divergences (auth, fenêtres,
  pagination) sont du domaine ; un pipeline générique serait shallow. Ce qui
  doit être partagé est le contrat, pas le pipeline.
- **Escalade codée dans chaque règle** (le `elsif` artisanal de feu
  `alert_rule_gbp_gap`) : la politique doit vivre à un endroit.
