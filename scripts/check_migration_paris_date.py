#!/usr/bin/env python3
"""C6 — Garde CI : interdit les casts Paris bruts dans les migrations SQL.

Autorisé : paris_date(), paris_today(), cooked_paris_ts_*(), commentaires,
définition de idx_events_paris_date, corps de paris_date() lui-même.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"

# Cast brut « occurred_at AT TIME ZONE 'Europe/Paris' » (variantes espaces)
RAW_PARIS_CAST = re.compile(
    r"(?:occurred_at|received_at|now\(\))\s+AT\s+TIME\s+ZONE\s+'Europe/Paris'",
    re.IGNORECASE,
)

ALLOW_LINE = re.compile(
    r"paris_date|paris_today|cooked_paris_ts|idx_events_paris_date|"
    r"COMMENT ON|--|paris_date_seam|CREATE OR REPLACE FUNCTION public\.paris_date",
    re.IGNORECASE,
)

# Fichiers historiques : ne pas bloquer le passé (on ne convertit que le diff CI)
HISTORICAL_ALLOWLIST = {
    "20260604150000_paris_date_seam.sql",
    "20260525170000_events_paris_date_index.sql",
}


def scan_file(path: Path) -> list[tuple[int, str]]:
    hits: list[tuple[int, str]] = []
    if path.name in HISTORICAL_ALLOWLIST:
        return hits
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if ALLOW_LINE.search(line):
            continue
        if RAW_PARIS_CAST.search(line):
            hits.append((i, line.strip()))
    return hits


def main() -> int:
    only_files = [Path(p) for p in sys.argv[1:]] if len(sys.argv) > 1 else sorted(MIGRATIONS.glob("*.sql"))
    failures: list[str] = []
    for path in only_files:
        if not path.exists():
            continue
        for lineno, text in scan_file(path):
            failures.append(f"{path.name}:{lineno}: {text}")
    if failures:
        print("C6 contract violation — use paris_date() / cooked_paris_ts_*() instead of raw casts:\n")
        print("\n".join(failures))
        return 1
    print(f"C6 OK — {len(only_files)} fichier(s) scanné(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
