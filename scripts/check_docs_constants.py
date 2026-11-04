#!/usr/bin/env python3
"""Les guides maintenus suivent le catalogue et leurs liens locaux existent.

Source unique : contracts/doc_constants.json (mis à jour depuis la prod ; check_prod_drift.py
compare ses compteurs à la prod chaque matin et sur chaque PR SQL).

Contrôles sur les guides maintenus :
  1. nombres près d'un mot-clé (« N routines », « N corps de RPC », « N RPC dashboard »,
     « N règles d'alerte », « N jobs pg_cron ») = la valeur du JSON ;
  2. versions canoniques (tracker, Edge track, Edge form-webhook) : les motifs
     `sprint<NN>` / « Edge `track` : vNN » / « Edge `form-webhook` : vNN » d'AGENTS.md
     sont présents exactement une fois et correspondent au JSON ;
  3. objets fantômes (fonctions/crons/alertes supprimés) absents des docs vivants ;
  4. chaque job pg_cron du JSON est cité dans docs/OPERATIONS.md ;
  5. chaque document déclaré existe ; les liens locaux des Markdown publiés aboutissent ;
  6. tout .md de la racine et de docs/ est lié par un index déclaré.
"""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
CONSTANTS = json.loads((ROOT / "contracts" / "doc_constants.json").read_text(encoding="utf-8"))
DOCS = CONSTANTS["docs"]

LIVING = [ROOT / p for p in DOCS["living_docs"]]
INDEXES = [ROOT / p for p in DOCS["index_docs"]]


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def check_required_files(failures: list[str]) -> None:
    for path in sorted(set(LIVING + INDEXES)):
        if not path.is_file():
            failures.append(f"{path.relative_to(ROOT)} : document déclaré absent")


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
    # AGENTS.md est l'unique tableau canonique ; les récits de livraison sont datés.
    checks = [
        ("Tracker", r"^\| Tracker \| `(sprint\d+)` \|", v["tracker"]),
        ("Edge track", r"^\| Edge `track` \| v(\d+) \|", str(v["edge_track"])),
        ("Edge form-webhook", r"^\| Edge `form-webhook` \| `v(\d+)` \|", str(v["edge_form_webhook"])),
    ]
    text = read(ROOT / "AGENTS.md")
    for label, rx, expected in checks:
        hits = list(re.finditer(rx, text, re.M))
        if len(hits) != 1:
            failures.append(f"AGENTS.md : version canonique {label} attendue une fois, trouvée {len(hits)} fois")
        for m in hits:
            if m.group(1) != expected:
                line = text.count("\n", 0, m.start()) + 1
                failures.append(f"AGENTS.md:{line}: version « {m.group(0)} » ≠ {expected}")


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


def published_markdown() -> list[Path]:
    # Les rapports privés et autres artefacts ignorés ne font pas partie de la
    # documentation publiée. Inclure les nouveaux fichiers non ignorés aussi.
    published = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.md"],
        cwd=ROOT,
    ).decode().split("\0")
    return sorted({ROOT / rel for rel in published if rel and (ROOT / rel).is_file()})


def local_links(path: Path) -> list[tuple[int, Path]]:
    """Liens et images inline, définitions de liens ; exemples de code exclus."""
    links = []
    fence = None
    for line_no, line in enumerate(read(path).splitlines(), 1):
        marker = re.match(r"^\s{0,3}(`{3,}|~{3,})", line)
        if fence:
            if re.match(rf"^\s{{0,3}}{re.escape(fence[0])}{{{len(fence)},}}\s*$", line):
                fence = None
            continue
        if marker:
            fence = marker.group(1)
            continue
        line = re.sub(r"(`+).*?\1", "", line)
        destinations = re.findall(r"\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|([^\s)]+))", line)
        destinations += re.findall(r"^\s{0,3}\[[^\]\n]+\]:\s*(?:<([^>\n]+)>|(\S+))", line)
        for angled, plain in destinations:
            target = urlsplit(angled or plain)
            if target.scheme or target.netloc or not target.path:
                continue
            target_path = unquote(target.path)
            base = ROOT if target_path.startswith("/") else path.parent
            links.append((line_no, (base / target_path.lstrip("/")).resolve()))
    return links


def check_links(published: list[Path], failures: list[str]) -> None:
    for path in published:
        for line, target in local_links(path):
            if not target.is_relative_to(ROOT):
                failures.append(f"{path.relative_to(ROOT)}:{line}: lien local hors du dépôt")
            elif not target.exists():
                failures.append(f"{path.relative_to(ROOT)}:{line}: lien local absent : {target.relative_to(ROOT)}")


def check_orphans(published: list[Path], failures: list[str]) -> None:
    indexed = {target for path in INDEXES for _, target in local_links(path)}
    for md in published:
        rel = md.relative_to(ROOT).as_posix()
        if "/" in rel and not rel.startswith("docs/"):
            continue
        if md not in indexed:
            failures.append(f"{rel} : n'est lié par aucun index déclaré")


def main() -> int:
    failures: list[str] = []
    check_required_files(failures)
    if failures:
        print("\n".join(failures))
        return 1
    check_numbers(failures)
    check_versions(failures)
    check_ghosts(failures)
    check_crons(failures)
    published = published_markdown()
    check_links(published, failures)
    check_orphans(published, failures)
    if failures:
        print("I13 docs-constants FAIL :\n")
        print("\n".join(f"  • {f}" for f in failures))
        print(f"\nSource : contracts/doc_constants.json (mesuré le {CONSTANTS.get('measured_at')})")
        return 1
    print(f"I13 OK — {len(LIVING)} docs vivants cohérents avec contracts/doc_constants.json ({CONSTANTS.get('measured_at')})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
