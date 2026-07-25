#!/usr/bin/env python3
"""Arch #6 — Gate CI : colonnes RPC dashboard alignées sur rpc-schemas.ts (Zod).

Compare contracts/dashboard_rpc_columns.json (source canonique des colonnes
SQL attendues) aux clés des schémas Zod dans dashboard/src/data/rpc-schemas.ts.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "contracts" / "dashboard_rpc_columns.json"
SCHEMAS = ROOT / "dashboard" / "src" / "data" / "rpc-schemas.ts"

# rpc_name -> export Zod object name in rpc-schemas.ts
RPC_TO_SCHEMA: dict[str, str] = {
    "dashboard_seo_by_query": "seoQueryRowSchema",
    "dashboard_honoraires_funnel": "honorairesFunnelSchema",
}


def zod_object_keys(ts: str, schema_name: str) -> set[str]:
    m = re.search(
        rf"export const {re.escape(schema_name)}\s*=\s*z\s*\.object\(\{{(.*?)\}}\)",
        ts,
        re.S,
    )
    if not m:
        # honorairesFunnelSchema wraps array — inner object
        m = re.search(
            rf"export const {re.escape(schema_name)}\s*=\s*z\s*\.array\(\s*z\s*\.object\(\{{(.*?)\}}\)",
            ts,
            re.S,
        )
    if not m:
        raise KeyError(f"schema {schema_name} not found in rpc-schemas.ts")
    body = m.group(1)
    return set(re.findall(r"^\s*(\w+)\s*:", body, re.M))


def main() -> int:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    ts = SCHEMAS.read_text(encoding="utf-8")
    failures: list[str] = []

    for rpc, expected_cols in contract.items():
        schema = RPC_TO_SCHEMA.get(rpc)
        if not schema:
            failures.append(f"{rpc}: no RPC_TO_SCHEMA mapping")
            continue
        zod_keys = zod_object_keys(ts, schema)
        expected = set(expected_cols)
        missing_in_zod = sorted(expected - zod_keys)
        extra_in_zod = sorted(zod_keys - expected)
        if missing_in_zod:
            failures.append(f"{rpc}: colonnes contrat absentes du Zod: {missing_in_zod}")
        if extra_in_zod:
            failures.append(f"{rpc}: colonnes Zod absentes du contrat: {extra_in_zod}")

    if failures:
        print("Dashboard RPC column contract violation:\n")
        print("\n".join(f"  • {f}" for f in failures))
        return 1

    print(f"Arch #6 OK — {len(contract)} RPC(s) dashboard alignées Zod ↔ contrat")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
