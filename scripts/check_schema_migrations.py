#!/usr/bin/env python3
"""Arch #10 — Vérifie que supabase/migrations/ est cohérent (versions uniques).

Avec DATABASE_URL : compare aussi schema_migrations prod vs fichiers locaux.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"

VERSION_RE = re.compile(r"^(\d{14})_")


def local_versions() -> list[str]:
    versions: list[str] = []
    for path in sorted(MIGRATIONS.glob("*.sql")):
        m = VERSION_RE.match(path.name)
        if not m:
            print(f"WARN: migration sans timestamp 14 chiffres: {path.name}")
            continue
        versions.append(m.group(1))
    return versions


def main() -> int:
    versions = local_versions()
    if not versions:
        print("Arch #10 WARN — aucune migration locale")
        return 0

    dupes = sorted({v for v in versions if versions.count(v) > 1})
    if dupes:
        print("Arch #10 migration duplicate versions:", ", ".join(dupes))
        return 1

    db_url = os.environ.get("DATABASE_URL", "").strip()
    if not db_url:
        print(f"Arch #10 OK — {len(versions)} migration(s) locales, versions uniques (pas de DATABASE_URL)")
        return 0

    try:
        import psycopg2  # type: ignore
    except ImportError:
        print("Arch #10 OK local — psycopg2 absent, skip prod diff")
        return 0

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT version FROM supabase_migrations.schema_migrations ORDER BY version"
            )
            prod = {row[0] for row in cur.fetchall()}

    local = set(versions)
    missing_local = sorted(prod - local)
    missing_prod = sorted(local - prod)

    failures: list[str] = []
    if missing_local:
        failures.append(
            f"{len(missing_local)} version(s) en prod sans fichier local (ex. {missing_local[:3]})"
        )
    if missing_prod:
        failures.append(
            f"{len(missing_prod)} fichier(s) local(aux) non appliqué(s) en prod (ex. {missing_prod[:3]})"
        )

    if failures:
        print("Arch #10 schema_migrations drift:\n")
        print("\n".join(f"  • {f}" for f in failures))
        return 1

    print(f"Arch #10 OK — {len(local)} migrations locales = prod")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
