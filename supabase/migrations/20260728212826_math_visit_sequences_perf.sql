-- Miroir exact de la migration appliquee en prod (MCP) le 28/07/2026.
-- Perf 1/3 — le join lateral du canal d'entree s'executait une fois par visite
-- (~16 000 scans d'une CTE materialisee de 20 000 lignes) -> timeout.
-- Remplace par DISTINCT ON + classify_channel evalue une fois par
-- combinaison (referrer, utm) au lieu d'une fois par visite.
-- Corps remplace par 20260728215013 (etat final).

-- (CREATE OR REPLACE FUNCTION public.math_visit_sequences — voir etat final)
