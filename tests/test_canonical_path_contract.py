"""C3 — contrat canonical_path partagé (Python adapter = gsc_common)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from cooked_path import canonical_path  # noqa: E402

VECTORS = json.loads((ROOT / "contracts" / "canonical_path_vectors.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("row", VECTORS["path_cases"], ids=lambda r: r["id"])
def test_canonical_path_path_cases(row: dict) -> None:
    assert canonical_path(row["input"]) == row["expected"]


@pytest.mark.parametrize("row", VECTORS["python_url_cases"], ids=lambda r: r["id"])
def test_canonical_path_full_urls(row: dict) -> None:
    assert canonical_path(row["input"]) == row["expected"]
