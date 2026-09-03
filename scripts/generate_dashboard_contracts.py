#!/usr/bin/env python3
"""T-13 (mission 02/09/2026, #114) — contrat des RPC dashboard DEPUIS LA PROD.

Écrit contracts/dashboard_rpc_columns.json à partir du catalogue Postgres :
  • RPC `RETURNS TABLE(...)`      → noms de colonnes (pg_get_function_result)
  • RPC `RETURNS SETOF <table>`   → colonnes de la table (pg_attribute) + colonnes NOT NULL
  • RPC `RETURNS jsonb`           → clés de premier niveau d'un appel réel (échantillon)

Le fichier commité est ensuite confronté aux schémas Zod par
dashboard/src/data/rpc-contract.test.ts (vitest, sans base) ; ce script tourne en CI
(prod-drift.yml, rôle lecture seule cooked_ci_ro) en mode --check : si la prod a
bougé, le JSON régénéré diffère du JSON commité → CI rouge. Avec --samples <fichier>,
il écrit aussi un appel réel par RPC, que le même test vitest parse avec les schémas
Zod (DASHBOARD_RPC_SAMPLES=<fichier>) — le seul test qui aurait attrapé l'incident
/seo du 25/07/2026 (16 colonnes en prod, 20 exigées côté Zod).

Usage :
  DATABASE_URL=postgresql://… python3 scripts/generate_dashboard_contracts.py            # écrit le JSON
  DATABASE_URL=… python3 scripts/generate_dashboard_contracts.py --check                 # compare, exit 1 si drift
  DATABASE_URL=… python3 scripts/generate_dashboard_contracts.py --samples /tmp/s.json   # + échantillons
"""
from __future__ import annotations

import json
import os
import sys
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "contracts" / "dashboard_rpc_columns.json"

# Un appel réel par RPC — mêmes arguments que run_rpc_contract_tests (03/09/2026).
# Les jeux de résultats sont bornés (max_rows) : l'échantillon sert au contrat, pas à l'analyse.
SAMPLE_CALLS: dict[str, str] = {
    "dashboard_annotations": "select * from public.dashboard_annotations('rolling_28') limit 3",
    "dashboard_article_detail": "select public.dashboard_article_detail('/post/abandon-de-poste-quels-risques', 'rolling_28')",
    "dashboard_assisted_quarter": "select public.dashboard_assisted_quarter()",
    "dashboard_expertises_kpis": "select * from public.dashboard_expertises_kpis('rolling_28')",
    "dashboard_expertises_overview": "select * from public.dashboard_expertises_overview('rolling_28', 3)",
    "dashboard_expertises_trend": "select * from public.dashboard_expertises_trend('rolling_28')",
    "dashboard_honoraires_funnel": "select * from public.dashboard_honoraires_funnel('rolling_28')",
    "dashboard_intervention_effect": "select public.dashboard_intervention_effect('/', date '2026-09-01')",
    "dashboard_lab_gsc_weekly": "select public.dashboard_lab_gsc_weekly(3)",
    "dashboard_resources_assisted": "select * from public.dashboard_resources_assisted('rolling_28') limit 3",
    "dashboard_resources_cohorts": "select public.dashboard_resources_cohorts()",
    "dashboard_resources_kpis": "select * from public.dashboard_resources_kpis('rolling_28')",
    "dashboard_resources_overview": "select * from public.dashboard_resources_overview('rolling_28', 3)",
    "dashboard_resources_trend": "select * from public.dashboard_resources_trend('rolling_28')",
    "dashboard_seo_by_query": "select * from public.dashboard_seo_by_query('rolling_28', 'ressource', 0, 3)",
    "dashboard_seo_kpis": "select * from public.dashboard_seo_kpis('rolling_28', 'ressource')",
}

CATALOG_SQL = """
SELECT p.proname,
       pg_get_function_result(p.oid) AS res,
       t.typrelid::regclass::text     AS relation,
       (SELECT json_agg(a.attname ORDER BY a.attnum)
          FROM pg_attribute a
         WHERE a.attrelid = t.typrelid AND a.attnum > 0 AND NOT a.attisdropped) AS rel_cols,
       (SELECT json_agg(a.attname ORDER BY a.attnum)
          FROM pg_attribute a
         WHERE a.attrelid = t.typrelid AND a.attnum > 0 AND NOT a.attisdropped AND a.attnotnull) AS rel_not_null
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_type t ON t.oid = p.prorettype
WHERE n.nspname = 'public' AND p.proname LIKE 'dashboard\\_%'
ORDER BY p.proname
""".strip()


def parse_table_columns(res: str) -> list[str]:
    inner = res[len("TABLE(") : -1]
    return [part.strip().split(" ")[0] for part in inner.split(",")]


def rows_to_sample(cur, sql: str):
    cur.execute(sql)
    cols = [d[0] for d in cur.description]
    rows = cur.fetchall()
    if len(cols) == 1 and cols[0].startswith("dashboard_"):
        # RPC jsonb appelée en scalaire : select public.f(...) → une cellule
        return rows[0][0] if rows else None
    return [dict(zip(cols, r)) for r in rows]


def build(conn, want_samples: bool):
    contract: dict[str, dict] = {}
    samples: dict[str, object] = {}
    with conn.cursor() as cur:
        cur.execute(CATALOG_SQL)
        catalog = cur.fetchall()
        for proname, res, relation, rel_cols, rel_not_null in catalog:
            entry: dict = {}
            if res.startswith("TABLE("):
                entry = {"kind": "table", "columns": parse_table_columns(res)}
            elif res.startswith("SETOF "):
                entry = {
                    "kind": "setof",
                    "columns": list(rel_cols or []),
                    "not_null": list(rel_not_null or []),
                    "relation": relation,
                }
            else:
                entry = {"kind": "jsonb"}
            call = SAMPLE_CALLS.get(proname)
            if call is None:
                entry["sample_call"] = None
            else:
                entry["sample_call"] = call
                if entry["kind"] == "jsonb" or want_samples:
                    data = rows_to_sample(cur, call)
                    if entry["kind"] == "jsonb":
                        entry["columns"] = sorted((data or {}).keys()) if isinstance(data, dict) else []
                    if want_samples:
                        samples[proname] = data
            contract[proname] = entry
    return contract, samples


KEY_ORDER = ("kind", "columns", "not_null", "relation", "sample_call")


def canonical(contract: dict[str, dict]) -> dict[str, dict]:
    """Ordre de clés stable (RPC triées, champs dans KEY_ORDER) → diff textuel lisible."""
    return {
        rpc: {k: entry[k] for k in KEY_ORDER if k in entry}
        for rpc, entry in sorted(contract.items())
    }


def _json_default(o):
    # psycopg2 rend numeric en Decimal et date/timestamptz en objets ; PostgREST (ce que le
    # dashboard reçoit) rend des nombres JSON et des chaînes ISO — on reproduit cette forme.
    if isinstance(o, Decimal):
        return float(o)
    if isinstance(o, (date, datetime)):
        return o.isoformat()
    return str(o)


def dumps(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, indent=2, default=_json_default) + "\n"


def main() -> int:
    args = sys.argv[1:]
    check = "--check" in args
    samples_path = None
    if "--samples" in args:
        samples_path = Path(args[args.index("--samples") + 1])

    url = (os.environ.get("DATABASE_URL") or os.environ.get("DATABASE_URL_RO") or "").strip()
    if not url:
        print("DATABASE_URL absent — ce script lit la prod (rôle cooked_ci_ro en CI).")
        print("Sans base : dashboard/src/data/rpc-contract.test.ts compare le JSON commité aux schémas Zod.")
        return 1
    try:
        import psycopg2  # type: ignore
    except ImportError:
        print("psycopg2 requis (pip install psycopg2-binary)")
        return 1

    with psycopg2.connect(url) as conn:
        conn.set_session(readonly=True)
        contract, samples = build(conn, want_samples=samples_path is not None)

    contract = canonical(contract)
    text = dumps(contract)
    if samples_path is not None:
        samples_path.write_text(dumps(samples), encoding="utf-8")
        print(f"échantillons écrits : {samples_path} ({len(samples)} RPC)")

    if check:
        committed = CONTRACT.read_text(encoding="utf-8") if CONTRACT.exists() else ""
        old = json.loads(committed) if committed else {}
        if old != contract:
            print("T-13 dashboard contract FAIL — contracts/dashboard_rpc_columns.json dérive de la prod :")
            for rpc in sorted(set(old) | set(contract)):
                if old.get(rpc) != contract.get(rpc):
                    print(f"  • {rpc}: repo={old.get(rpc)}\n            prod={contract.get(rpc)}")
            print("Régénérer : DATABASE_URL=… python3 scripts/generate_dashboard_contracts.py")
            return 1
        if committed != text:
            print("T-13 : contenu identique à la prod, formatage différent — régénérer pour aligner le texte")
        print(f"T-13 OK — {len(contract)} RPC dashboard : contrat commité = prod")
        return 0

    CONTRACT.write_text(text, encoding="utf-8")
    print(f"écrit {CONTRACT} ({len(contract)} RPC)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
