#!/usr/bin/env python3
"""Gardes CI de la couture Paris-date.

C6 — interdit les casts Paris bruts dans les migrations SQL *nouvelles/modifiées*.
     Autorisé : paris_date(), paris_today(), cooked_paris_ts_*(), commentaires,
     définition de idx_events_paris_date, corps de paris_date() lui-même.

C6b — CONTRAT D'INLINING : vérifie dans le miroir supabase/rpcs.sql que
      paris_date() et paris_today() ne portent ni STRICT ni SET search_path.
      Postgres n'inline pas une fonction SQL avec proconfig non nul : la clause
      SET rend idx_events_paris_date inutilisable (cost 1,79 -> 495 118 mesuré
      en prod le 25/07/2026, index à 0 scan). La régression du 23/07/2026 est
      arrivée par une remédiation en masse de l'advisor Supabase appliquée hors
      repo ; elle a été enregistrée telle quelle dans rpcs.sql sans alerter.
      Voir 20260725045430_restore_paris_date_inlining_contract.sql.

C6c — BORNES D'HORLOGE : interdit `current_date` et `now() - make_interval(...)`
      dans les migrations à partir de T-09 (20260903093320). Ces deux formes ont
      produit les défauts d-02/d-06 de la mission du 02/09/2026 : une fenêtre
      « 28 j » qui change avec l'heure de la question et un `current_date` UTC
      qui décale la borne Paris. Fenêtres closes = cooked_period_bounds() /
      cooked_snapshot_window() / paris_today(). Les littéraux entre apostrophes
      (regex d'un contract-test) et les commentaires sont ignorés ; échappement
      explicite : `-- c6c:allow` sur la ligne.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
RPCS = ROOT / "supabase" / "rpcs.sql"

# Fonctions dont l'inlining est contractuel (cf. docstring C6b).
INLINE_CONTRACT_FUNCTIONS = ("paris_date", "paris_today")

MARKER = re.compile(r"^-- ═══ public\.(\w+)\(", re.MULTILINE)
INLINE_BREAKER = re.compile(r"^\s*(SET\s+search_path|STRICT\b)", re.IGNORECASE | re.MULTILINE)

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
    # T-12 : miroir exact d'une migration prod du 08/08 (casts Paris d'époque).
    # Ne pas « moderniser » le fichier — ça casserait la parité statements.
    "20260807224552_weekly_conversion_pages_routine.sql",
}


# C6c — règle instaurée par T-09 : s'applique à cette migration et aux suivantes.
CLOCK_BOUND_SINCE = "20260903093320"
CLOCK_BOUND = re.compile(r"\bcurrent_date\b|now\(\)\s*-\s*make_interval", re.IGNORECASE)
CLOCK_BOUND_ALLOW = re.compile(r"^\s*--|COMMENT ON|c6c:allow", re.IGNORECASE)
QUOTED_LITERAL = re.compile(r"'[^']*'")


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


def clock_bound_applies(path: Path) -> bool:
    version = path.name.split("_", 1)[0]
    return version.isdigit() and version >= CLOCK_BOUND_SINCE


def scan_clock_bounds(path: Path) -> list[tuple[int, str]]:
    """C6c — current_date / now() - make_interval interdits (fenêtres closes obligatoires)."""
    hits: list[tuple[int, str]] = []
    if not clock_bound_applies(path):
        return hits
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if CLOCK_BOUND_ALLOW.search(line):
            continue
        code = QUOTED_LITERAL.sub("''", line).split("--", 1)[0]
        if CLOCK_BOUND.search(code):
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


def rpcs_function_bodies() -> dict[str, str]:
    """Découpe supabase/rpcs.sql en blocs {nom_fonction: corps} via les marqueurs."""
    if not RPCS.exists():
        return {}
    text = RPCS.read_text(encoding="utf-8")
    blocks: dict[str, str] = {}
    matches = list(MARKER.finditer(text))
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        blocks.setdefault(m.group(1).lower(), "")
        blocks[m.group(1).lower()] += text[m.start():end]
    return blocks


def check_inlining_contract() -> list[str]:
    """C6b — paris_date()/paris_today() ne doivent porter ni SET search_path ni STRICT."""
    blocks = rpcs_function_bodies()
    if not blocks:
        return ["supabase/rpcs.sql introuvable ou sans marqueur — impossible de vérifier C6b"]
    failures: list[str] = []
    for name in INLINE_CONTRACT_FUNCTIONS:
        body = blocks.get(name)
        if body is None:
            failures.append(f"{name}() absente de supabase/rpcs.sql — miroir à régénérer")
            continue
        for m in INLINE_BREAKER.finditer(body):
            failures.append(
                f"supabase/rpcs.sql: public.{name}() porte « {m.group(1).strip()} » — "
                "Postgres ne peut plus l'inliner, idx_events_paris_date devient inutilisable"
            )
    return failures


def main() -> int:
    """Les deux contrats sont indépendants : on les évalue tous les deux, toujours.

    Un échec de l'un ne doit pas masquer l'état de l'autre — c'est précisément
    ainsi que la régression d'inlining du 23/07/2026 est passée inaperçue.
    """
    rc = 0

    # C6b d'abord : il ne dépend d'aucun diff, il lit le miroir rpcs.sql.
    inline_failures = check_inlining_contract()
    if inline_failures:
        print("C6b contract violation — CONTRAT D'INLINING paris_date/paris_today rompu:\n")
        print("\n".join(f"  • {f}" for f in inline_failures))
        print(
            "\nCorrectif : redéfinir la fonction SANS clause SET search_path ni STRICT "
            "(cf. supabase/migrations/20260725045430_restore_paris_date_inlining_contract.sql), "
            "puis régénérer supabase/rpcs.sql.\n"
        )
        rc = 1
    else:
        print(f"C6b OK — contrat d'inlining tenu ({', '.join(INLINE_CONTRACT_FUNCTIONS)})")

    targets = resolve_targets(sys.argv)
    if not targets:
        print("C6 OK — aucune migration modifiée à scanner")
        return rc

    failures: list[str] = []
    clock_failures: list[str] = []
    for path in targets:
        if not path.exists():
            continue
        for lineno, text in scan_file(path):
            failures.append(f"{path.name}:{lineno}: {text}")
        for lineno, text in scan_clock_bounds(path):
            clock_failures.append(f"{path.name}:{lineno}: {text}")
    if failures:
        print("C6 contract violation — use paris_date() / cooked_paris_ts_*() instead of raw casts:\n")
        print("\n".join(failures))
        rc = 1
    else:
        print(f"C6 OK — {len(targets)} fichier(s) scanné(s)")
    if clock_failures:
        print(
            "\nC6c contract violation — current_date / now() - make_interval interdits : "
            "fenêtre close via cooked_period_bounds() / paris_today() (ou `-- c6c:allow` justifié) :\n"
        )
        print("\n".join(clock_failures))
        rc = 1
    else:
        scanned = sum(1 for p in targets if p.exists() and clock_bound_applies(p))
        print(f"C6c OK — {scanned} migration(s) ≥ {CLOCK_BOUND_SINCE} sans borne d'horloge")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
