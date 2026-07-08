#!/usr/bin/env python3
"""C6 — Garde CI : interdit les casts Paris bruts dans les migrations SQL *nouvelles/modifiées*.

Autorisé : paris_date(), paris_today(), cooked_paris_ts_*(), commentaires,
définition de idx_events_paris_date, corps de paris_date() lui-même.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"

RAW_PARIS_CAST = re.compile(
    r"(?:occurred_at|received_at|now\(\))\s+AT\s+TIME\s+ZONE\s+'Europe/Paris'",
    re.IGNORECASE,
)

ALLOW_LINE = re.compile(
    r"paris_date|paris_today|cooked_paris_ts|idx_events_paris_date|"
    r"COMMENT ON|--|paris_date_seam|CREATE OR REPLACE FUNCTION public\.paris_date",
    re.IGNORECASE,
)

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


def git_diff_migration_paths() -> list[Path]:
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    if event == "push":
        cmd = ["git", "diff", "--name-only", "HEAD~1", "HEAD", "--", "supabase/migrations"]
    else:
        base = os.environ.get("GITHUB_BASE_REF", "main")
        cmd = ["git", "diff", "--name-only", f"origin/{base}...HEAD", "--", "supabase/migrations"]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, check=False)
    if result.returncode != 0:
        return []
    paths: list[Path] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.endswith(".sql"):
            paths.append(ROOT / line)
    return paths


def resolve_targets(argv: list[str]) -> list[Path]:
    if len(argv) > 1:
        return [Path(p) for p in argv[1:]]
    if os.environ.get("GITHUB_ACTIONS"):
        return git_diff_migration_paths()
    return sorted(MIGRATIONS.glob("*.sql"))


def main() -> int:
    targets = resolve_targets(sys.argv)
    if not targets:
        print("C6 OK — aucune migration modifiée à scanner")
        return 0
    failures: list[str] = []
    for path in targets:
        if not path.exists():
            continue
        for lineno, text in scan_file(path):
            failures.append(f"{path.name}:{lineno}: {text}")
    if failures:
        print("C6 contract violation — use paris_date() / cooked_paris_ts_*() instead of raw casts:\n")
        print("\n".join(failures))
        return 1
    print(f"C6 OK — {len(targets)} fichier(s) scanné(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
