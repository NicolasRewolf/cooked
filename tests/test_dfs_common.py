"""Tests unitaires pour scripts/dfs_common.py (sanitize DFS, collisions)."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from dfs_common import prepare_keywords_for_dfs, sanitize_for_dfs  # noqa: E402


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("garde à vue", "garde à vue"),
        ("durée—garde", "durée-garde"),
        ("foo(bar)", "foo bar"),
        ("test  foo", "test foo"),
        ("", None),
        ("   ", None),
    ],
)
def test_sanitize_for_dfs_ok(raw: str, expected: str | None) -> None:
    assert sanitize_for_dfs(raw) == expected


def test_sanitize_em_dash() -> None:
    assert sanitize_for_dfs("ITT — définition") == "ITT - définition"


def test_sanitize_nbsp() -> None:
    # non-breaking space U+00A0 → espace normal
    assert sanitize_for_dfs("garde\u00a0à\u00a0vue") == "garde à vue"


def test_sanitize_too_many_words() -> None:
    eleven = " ".join(f"mot{i}" for i in range(11))
    assert sanitize_for_dfs(eleven) is None
    assert sanitize_for_dfs(" ".join(f"mot{i}" for i in range(10))) == " ".join(
        f"mot{i}" for i in range(10)
    )


def test_sanitize_too_long() -> None:
    long_kw = "a" * 81
    assert sanitize_for_dfs(long_kw) is None
    assert sanitize_for_dfs("a" * 80) == "a" * 80


def test_sanitize_unsafe_char_after_strip() -> None:
    # Caractère hors charset même après nettoyage
    assert sanitize_for_dfs("requête € prix") is None


def test_prepare_collision() -> None:
    clean, mapping, skipped, collisions = prepare_keywords_for_dfs(
        ["test&foo", "test foo"]
    )
    assert skipped == []
    assert len(collisions) == 1
    assert collisions[0] == ("test foo", "test&foo")
    assert clean == ["test foo"]
    assert mapping["test foo"] == "test&foo"


def test_prepare_no_collision_different_sanitized() -> None:
    clean, _, skipped, collisions = prepare_keywords_for_dfs(
        ["garde à vue", "durée garde à vue"]
    )
    assert skipped == []
    assert collisions == []
    assert len(clean) == 2
