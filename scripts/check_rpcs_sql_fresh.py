#!/usr/bin/env python3
"""Arch #5 — Toute création, modification ou suppression de RPC régénère le miroir.

Règle :
  • CREATE [OR REPLACE], ALTER ou DROP (FUNCTION|PROCEDURE) public.<name>
    → supabase/rpcs.sql et ses métadonnées figurent dans le même diff PR/push
    → les fonctions créées et non supprimées ont un marqueur dans rpcs.sql
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from git_changes import changed_paths

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
RPCS = ROOT / "supabase" / "rpcs.sql"

RPC_CHANGE = re.compile(
    r"(?P<operation>CREATE|ALTER|DROP)\s+(?:OR\s+REPLACE\s+)?"
    r"(?:FUNCTION|PROCEDURE)\s+(?:IF\s+EXISTS\s+)?public\.(?P<name>\w+)",
    re.IGNORECASE,
)
MARKER = re.compile(r"^-- ═══ public\.(\w+)\(", re.MULTILINE)


def rpc_markers_in_rpcs_sql() -> set[str]:
    if not RPCS.exists():
        return set()
    return {m.group(1).lower() for m in MARKER.finditer(RPCS.read_text(encoding="utf-8"))}


def main() -> int:
    try:
        paths = changed_paths(ROOT)
    except RuntimeError as exc:
        print(f"Arch #5 — contrôle impossible : {exc}", file=sys.stderr)
        return 1

    migrations = sorted(p for p in paths if p.parent == MIGRATIONS)
    if not migrations:
        print("Arch #5 OK — aucune migration modifiée")
        return 0

    touched: set[str] = set()
    defined: set[str] = set()
    for path in migrations:
        if path.exists():
            text = path.read_text(encoding="utf-8")
            for match in RPC_CHANGE.finditer(text):
                name, operation = match["name"].lower(), match["operation"].upper()
                touched.add(name)
                if operation == "CREATE":
                    defined.add(name)
                elif operation == "DROP":
                    defined.discard(name)

    if not touched:
        print(f"Arch #5 OK — {len(migrations)} migration(s), aucune RPC modifiée")
        return 0

    pr_files = {p.relative_to(ROOT).as_posix() for p in paths}
    rpcs_changed = "supabase/rpcs.sql" in pr_files
    meta_changed = "contracts/rpc_snapshot_meta.json" in pr_files

    failures: list[str] = []
    if not rpcs_changed:
        failures.append(
            "supabase/rpcs.sql doit être régénéré (python3 scripts/generate_rpcs_sql.py) "
            f"car ces RPC sont modifiées : {', '.join(sorted(touched))}"
        )
    if not meta_changed:
        failures.append("contracts/rpc_snapshot_meta.json doit être mis à jour avec rpcs.sql")

    markers = rpc_markers_in_rpcs_sql()
    missing = sorted(defined - markers)
    if missing and rpcs_changed:
        failures.append(
            f"Marqueurs absents dans rpcs.sql : {', '.join(missing)} "
            "(régénérer depuis la prod après merge migration)"
        )

    if failures:
        print("Arch #5 rpcs.sql contract violation:\n")
        print("\n".join(f"  • {f}" for f in failures))
        return 1

    print(
        f"Arch #5 OK — {len(touched)} RPC(s) modifiée(s), rpcs.sql à jour "
        f"({', '.join(sorted(touched))})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
