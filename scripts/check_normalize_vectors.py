#!/usr/bin/env python3
"""T-16 — les vecteurs de contracts/normalize_vectors.json passent en Python ET en SQL.

Python : cooked.secib (normalize_email / normalize_phone_fr) — toujours.
SQL    : cooked_normalize_email / cooked_normalize_phone_fr — si DATABASE_URL (prod-drift.yml,
         rôle cooked_ci_ro, EXECUTE accordé au T-16).
Un vecteur faux d'un seul côté = miroir cassé = clés de rapprochement fausses en silence.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
from cooked.secib import normalize_email, normalize_phone_fr

VECTORS = json.loads((ROOT / "contracts" / "normalize_vectors.json").read_text(encoding="utf-8"))
FUNCS = {"email": ("cooked_normalize_email", normalize_email), "phone_fr": ("cooked_normalize_phone_fr", normalize_phone_fr)}


def check_python() -> list[str]:
    fails = []
    for kind, (_, fn) in FUNCS.items():
        for v in VECTORS[kind]:
            got = fn(v["in"])
            if got != v["out"]:
                fails.append(f"python {kind} {v['in']!r} → {got!r} (attendu {v['out']!r})")
    return fails


def check_sql(url: str) -> list[str]:
    import psycopg2  # type: ignore

    fails = []
    with psycopg2.connect(url) as conn, conn.cursor() as cur:
        for kind, (sql_fn, _) in FUNCS.items():
            for v in VECTORS[kind]:
                cur.execute(f"SELECT public.{sql_fn}(%s)", (v["in"],))
                got = cur.fetchone()[0]
                if got != v["out"]:
                    fails.append(f"sql {sql_fn} {v['in']!r} → {got!r} (attendu {v['out']!r})")
    return fails


def main() -> int:
    fails = check_python()
    url = (os.environ.get("DATABASE_URL") or os.environ.get("DATABASE_URL_RO") or "").strip()
    sql_done = False
    if url:
        fails += check_sql(url)
        sql_done = True
    n = sum(len(v) for k, v in VECTORS.items() if isinstance(v, list))
    if fails:
        print("I12 normalize-vectors FAIL :\n" + "\n".join(f"  • {f}" for f in fails))
        return 1
    print(f"I12 OK — {n} vecteurs de normalisation : Python{' + SQL' if sql_done else ' (SQL non testé : DATABASE_URL absent)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
