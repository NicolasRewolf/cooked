"""C3 — contrat canonical_path partagé (Python adapter = cooked.path)."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from cooked.path import canonical_path

ROOT = Path(__file__).resolve().parents[1]
VECTORS = json.loads((ROOT / "contracts" / "canonical_path_vectors.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("row", VECTORS["path_cases"], ids=lambda r: r["id"])
def test_canonical_path_path_cases(row: dict) -> None:
    assert canonical_path(row["input"]) == row["expected"]


@pytest.mark.parametrize("row", VECTORS["python_url_cases"], ids=lambda r: r["id"])
def test_canonical_path_full_urls(row: dict) -> None:
    assert canonical_path(row["input"]) == row["expected"]
