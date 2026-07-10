#!/usr/bin/env python3
"""Arch #5 — Génère supabase/rpcs.sql (corps complets) depuis Postgres.

Usage :
  DATABASE_URL='postgresql://...' python3 scripts/generate_rpcs_sql.py

Sans DATABASE_URL : affiche la requête SQL à lancer via MCP Supabase / psql.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "supabase" / "rpcs.sql"
META = ROOT / "contracts" / "rpc_snapshot_meta.json"

HEADER_TEMPLATE = """-- ============================================================================
-- supabase/rpcs.sql — CORPS COMPLETS DES RPC (généré, LECTURE SEULE)
--
-- ⚠️  NE PAS REJOUER COMME SOURCE D'UN DÉPLOIEMENT. NE PAS ÉDITER À LA MAIN.
--
-- Source de vérité DDL = supabase/migrations/*.sql (+ état prod).
-- Ce fichier = instantané lisible pour humains et agents (Arch #5, 10/07/2026).
--
-- Régénérer : python3 scripts/generate_rpcs_sql.py  (DATABASE_URL requis)
-- Généré le {generated_fr} — projet mxycmjkeotrycyneacje.
-- ============================================================================

"""

DUMP_SQL = """
SELECT coalesce(string_agg(
  format(E'-- ═══ public.%s(%s) ═══\\n%s',
    p.proname,
    pg_get_function_identity_arguments(p.oid),
    pg_get_functiondef(p.oid)),
  E'\\n\\n' ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)), '')
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind IN ('f', 'p');
""".strip()


def dump_via_psycopg2(url: str) -> str:
    try:
        import psycopg2
    except ImportError as exc:
        raise SystemExit(
            "psycopg2 requis : pip install psycopg2-binary (ou utilisez psql — voir --print-sql)"
        ) from exc

    with psycopg2.connect(url) as conn:
        with conn.cursor() as cur:
            cur.execute(DUMP_SQL)
            row = cur.fetchone()
            return row[0] or ""


def write_outputs(body: str) -> None:
    generated_fr = date.today().strftime("%d/%m/%Y")
    header = HEADER_TEMPLATE.format(generated_fr=generated_fr)
    content = header + body + "\n"
    OUT.write_text(content, encoding="utf-8")

    function_count = body.count("-- ═══ public.")
    META.parent.mkdir(parents=True, exist_ok=True)
    META.write_text(
        json.dumps(
            {
                "generated_at": date.today().isoformat(),
                "project_id": "mxycmjkeotrycyneacje",
                "function_count": function_count,
                "content_sha256": hashlib.sha256(body.encode()).hexdigest(),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {OUT.relative_to(ROOT)} ({len(content)} bytes, {function_count} functions)")
    print(f"Wrote {META.relative_to(ROOT)}")


def main() -> int:
    if "--print-sql" in sys.argv:
        print(DUMP_SQL)
        return 0

    url = os.environ.get("DATABASE_URL") or os.environ.get("SUPABASE_DB_URL")
    if not url:
        print("DATABASE_URL non défini — requête à lancer sur la prod :\n")
        print(DUMP_SQL)
        print("\nPuis coller le résultat dans supabase/rpcs.sql (voir header du fichier).")
        return 1

    body = dump_via_psycopg2(url)
    if not body.strip():
        print("Aucune fonction retournée — vérifier la connexion.")
        return 1
    write_outputs(body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
