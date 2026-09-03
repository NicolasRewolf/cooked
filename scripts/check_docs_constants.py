#!/usr/bin/env python3
"""T-14 (mission 02/09/2026, #115) — les constantes des docs vivants suivent la prod. Invariant I13.

Source unique : contracts/doc_constants.json (mis à jour depuis la prod ; check_prod_drift.py
compare ses compteurs à la prod chaque matin et sur chaque PR SQL).

Contrôles, sur les « docs vivants » (racine + docs/, hors archives et dossier de mission) :
  1. nombres près d'un mot-clé (« N routines », « N corps de RPC », « N RPC dashboard »,
     « N règles d'alerte », « N jobs pg_cron ») = la valeur du JSON ;
  2. versions canoniques (tracker, Edge track, Edge form-webhook) : les motifs
     `sprint<NN>` / « Edge `track` : vNN » / « Edge `form-webhook` : vNN » d'AGENTS.md
     et CLAUDE.md sont ceux du JSON ;
  3. objets fantômes (fonctions/crons/alertes supprimés) absents des docs vivants ;
  4. chaque job pg_cron du JSON est cité dans docs/OPERATIONS.md ;
  5. orphelins : tout .md de la racine et de docs/ (hors annexes de mission) est référencé
     par docs/README.md, AGENTS.md ou CLAUDE.md.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONSTANTS = json.loads((ROOT / "contracts" / "doc_constants.json").read_text(encoding="utf-8"))
DOCS = CONSTANTS["docs"]

LIVING = [ROOT / p for p in DOCS["living_docs"]]
INDEXES = [ROOT / p for p in DOCS["index_docs"]]


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8") if p.exists() else ""


def check_numbers(failures: list[str]) -> None:
    rules = [
        (r"\b(\d{2,3}) routines\b", {"routines_pg_proc", "routines_cooked"}, "routines"),
        (r"\b(\d{2,3}) corps (?:de )?RPC\b", {"routines_pg_proc"}, "corps de RPC"),
        (r"\b(\d{1,2}) RPC `?dashboard", {"dashboard_rpcs"}, "RPC dashboard"),
        (r"\b(\d{1,2}) règles? d'alerte\b", {"alert_rules"}, "règles d'alerte"),
        (r"\b(\d{1,2}) jobs? pg_cron\b", {"cron_jobs_count"}, "jobs pg_cron"),
    ]
    for path in LIVING:
        text = read(path)
        for rx, keys, label in rules:
            allowed = {str(CONSTANTS[k]) for k in keys}
            for m in re.finditer(rx, text):
                if m.group(1) not in allowed:
                    line = text.count("\n", 0, m.start()) + 1
                    failures.append(
                        f"{path.relative_to(ROOT)}:{line}: « {m.group(0)} » ≠ {label} du JSON ({', '.join(sorted(allowed))})"
                    )


def check_versions(failures: list[str]) -> None:
    v = CONSTANTS["versions"]
    # Seules les lignes « canoniques » comptent (tableau « Versions canoniques » d'AGENTS.md,
    # bloc « Versions canoniques » de CLAUDE.md) — pas le récit des sprints.
    checks = [
        (r"^(?:- Tracker : \*\*`|\| Tracker \| `)(sprint\d+)`", v["tracker"]),
        (r"^(?:- Edge `track` : \*\*v|\| Edge `track` \| v)(\d+)", str(v["edge_track"])),
        (r"^(?:- Edge `form-webhook` : \*\*v|\| Edge `form-webhook` \| `v)(\d+)", str(v["edge_form_webhook"])),
    ]
    for path in [ROOT / "AGENTS.md", ROOT / "CLAUDE.md"]:
        text = read(path)
        for rx, expected in checks:
            hits = list(re.finditer(rx, text, re.M))
            for m in hits:
                if m.group(1) != expected:
                    line = text.count("\n", 0, m.start()) + 1
                    failures.append(f"{path.relative_to(ROOT)}:{line}: version « {m.group(0)} » ≠ {expected}")


def check_ghosts(failures: list[str]) -> None:
    for path in LIVING:
        text = read(path)
        for ghost in DOCS["forbidden_in_living_docs"]:
            for m in re.finditer(re.escape(ghost), text):
                line = text.count("\n", 0, m.start()) + 1
                ctx = text[max(0, m.start() - 40) : m.start()]
                if "supprim" in ctx.lower() or "ex-" in ctx.lower() or "fantôme" in ctx.lower() or "retir" in ctx.lower():
                    continue  # mention historique explicitement marquée
                failures.append(f"{path.relative_to(ROOT)}:{line}: objet supprimé cité comme vivant : `{ghost}`")


def check_crons(failures: list[str]) -> None:
    ops = read(ROOT / "docs" / "OPERATIONS.md")
    for job in CONSTANTS["cron_jobs"]:
        if f"`{job['jobname']}`" not in ops:
            failures.append(f"docs/OPERATIONS.md : job pg_cron `{job['jobname']}` absent du tableau des crons")


def check_orphans(failures: list[str]) -> None:
    index_text = "\n".join(read(p) for p in INDEXES)
    candidates = list(ROOT.glob("*.md")) + list((ROOT / "docs").rglob("*.md"))
    for md in sorted(candidates):
        rel = md.relative_to(ROOT).as_posix()
        if any(rel.startswith(x) for x in DOCS["orphan_check_exclude_prefixes"]):
            continue
        if md.name == "README.md" and md.parent == ROOT / "docs":
            continue
        if md.name not in index_text and rel not in index_text:
            failures.append(f"{rel} : n'est référencé par aucun index (docs/README.md, AGENTS.md, CLAUDE.md)")


def main() -> int:
    failures: list[str] = []
    check_numbers(failures)
    check_versions(failures)
    check_ghosts(failures)
    check_crons(failures)
    check_orphans(failures)
    if failures:
        print("I13 docs-constants FAIL :\n")
        print("\n".join(f"  • {f}" for f in failures))
        print(f"\nSource : contracts/doc_constants.json (mesuré le {CONSTANTS.get('measured_at')})")
        return 1
    print(f"I13 OK — {len(LIVING)} docs vivants cohérents avec contracts/doc_constants.json ({CONSTANTS.get('measured_at')})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
