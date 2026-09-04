"""C7 — tests unitaires des pures de cooked.gsc."""
from __future__ import annotations

from datetime import date

import pytest

from cooked.gsc import (
    GSC_DAILY_MONTHS_BACK,
    aggregate_daily,
    list_months,
    parse_end_date,
)
from cooked.path import canonical_path


def test_gsc_daily_months_back_is_two() -> None:
    assert GSC_DAILY_MONTHS_BACK == 2


def test_list_months_daily_window_covers_june_30_on_july_first() -> None:
    """Régression 01/07/2026 : fenêtre cron (2 mois) doit inclure tout juin."""
    end = date(2026, 7, 1)
    months = list_months(end, GSC_DAILY_MONTHS_BACK)
    assert (date(2026, 6, 1), date(2026, 6, 30)) in months
    assert (date(2026, 7, 1), date(2026, 7, 1)) in months


def test_list_months_single_month_misses_previous_month_end() -> None:
    """Documente le piège qui a causé gsc_gap avant --months 2."""
    end = date(2026, 7, 1)
    months = list_months(end, 1)
    assert months == [(date(2026, 7, 1), date(2026, 7, 1))]


def test_list_months_end_mid_month_clips_current_month() -> None:
    end = date(2026, 6, 15)
    months = list_months(end, 1)
    assert months == [(date(2026, 6, 1), date(2026, 6, 15))]


def test_list_months_spans_year_boundary() -> None:
    end = date(2026, 1, 10)
    months = list_months(end, 2)
    assert (date(2025, 12, 1), date(2025, 12, 31)) in months
    assert (date(2026, 1, 1), date(2026, 1, 10)) in months


def test_aggregate_daily_weighted_position() -> None:
    rows = [
        {
            "keys": ["2026-06-01", "https://www.jplouton-avocat.fr/post/a"],
            "impressions": 100,
            "clicks": 10,
            "position": 5.0,
        },
        {
            "keys": ["2026-06-01", "https://www.jplouton-avocat.fr/post/a"],
            "impressions": 50,
            "clicks": 5,
            "position": 8.0,
        },
    ]
    out = aggregate_daily(rows, ("path",), (canonical_path,))
    assert len(out) == 1
    row = out[0]
    assert row["day"] == "2026-06-01"
    assert row["path"] == "/post/a"
    assert row["impressions"] == 150
    assert row["clicks"] == 15
    assert row["position"] == pytest.approx(6.0)
    assert row["ctr"] == pytest.approx(0.1)


def test_aggregate_daily_skips_zero_impressions() -> None:
    rows = [
        {
            "keys": ["2026-06-01", "/x"],
            "impressions": 0,
            "clicks": 0,
            "position": 1.0,
        },
    ]
    assert aggregate_daily(rows, ("path",), (canonical_path,)) == []


def test_parse_end_date_explicit_and_env(monkeypatch: pytest.MonkeyPatch) -> None:
    assert parse_end_date("2026-06-30") == date(2026, 6, 30)
    monkeypatch.setenv("GSC_END_DATE", "2026-05-31")
    assert parse_end_date(None) == date(2026, 5, 31)
