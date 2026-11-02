"""Shared Git comparison for CI guards; an unreadable diff is never an empty diff."""
from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path


def comparison_revisions() -> tuple[str, ...]:
    if os.environ.get("GITHUB_EVENT_NAME") != "push":
        base = os.environ.get("GITHUB_BASE_REF", "main")
        return (f"origin/{base}...HEAD",)

    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        # Local invocation without a GitHub event: compare the last commit.
        return ("HEAD~1", "HEAD")

    try:
        event = json.loads(Path(event_path).read_text(encoding="utf-8"))
        revisions = (event["before"], event["after"])
        if any(
            not isinstance(sha, str)
            or re.fullmatch(r"[0-9a-fA-F]{40}", sha) is None
            or sha == "0" * 40
            for sha in revisions
        ):
            raise ValueError("before/after doivent désigner deux commits existants")
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise RuntimeError(f"Bornes du push GitHub indisponibles : {exc}") from exc
    return revisions


def changed_paths(root: Path) -> list[Path]:
    revisions = comparison_revisions()
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "-z", *revisions, "--"],
            capture_output=True,
            text=True,
            cwd=root,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or f"code de sortie {exc.returncode}"
        raise RuntimeError(
            f"Diff Git impossible ({' '.join(revisions)}) : {detail}. "
            "Vérifier les références et récupérer l’historique nécessaire (fetch-depth: 0 en CI)."
        ) from exc
    except OSError as exc:
        raise RuntimeError(f"Impossible d’exécuter Git : {exc}") from exc
    return [root / path for path in result.stdout.split("\0") if path]
