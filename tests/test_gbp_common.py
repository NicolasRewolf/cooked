"""Tests unitaires des pures de scripts/gbp_common.py (sans credentials)."""
from __future__ import annotations

import sys
from datetime import date
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from gbp_common import (  # noqa: E402
    GBP_DAILY_DAYS_BACK,
    fill_missing_days,
    location_id_of,
    parse_end_date,
    rows_for_location,
)


def test_gbp_daily_days_back_is_90() -> None:
    assert GBP_DAILY_DAYS_BACK == 90


def test_location_id_of_strips_prefix() -> None:
    assert location_id_of("locations/12345") == "12345"
    assert location_id_of("12345") == "12345"


def test_parse_end_date_explicit() -> None:
    assert parse_end_date("2026-07-20") == date(2026, 7, 20)


def test_fill_missing_days_pads_zeros_range() -> None:
    start = date(2026, 7, 1)
    end = date(2026, 7, 3)
    by_day = {"2026-07-02": {"call_clicks": 5}}
    filled = fill_missing_days(by_day, start, end)
    assert set(filled) == {"2026-07-01", "2026-07-02", "2026-07-03"}
    assert filled["2026-07-02"]["call_clicks"] == 5
    assert filled["2026-07-01"] == {}


def test_rows_for_location_defaults_metrics_to_zero() -> None:
    loc = {"location_id": "999", "title": "Cabinet Test", "name": "locations/999"}
    by_day = {
        "2026-07-01": {"call_clicks": 3},
        "2026-07-02": {},
    }
    rows = rows_for_location(loc, by_day)
    assert len(rows) == 2
    r0 = rows[0]
    assert r0["day"] == "2026-07-01"
    assert r0["location_id"] == "999"
    assert r0["location_title"] == "Cabinet Test"
    assert r0["call_clicks"] == 3
    assert r0["website_clicks"] == 0
    assert r0["impressions_mobile_search"] == 0
    r1 = rows[1]
    assert r1["call_clicks"] == 0
    assert "ingested_at" in r1


def test_rows_preserve_all_impression_columns() -> None:
    loc = {"location_id": "1", "title": "X", "name": "locations/1"}
    by_day = {
        "2026-07-01": {
            "call_clicks": 1,
            "website_clicks": 2,
            "direction_requests": 3,
            "conversations": 4,
            "impressions_desktop_maps": 10,
            "impressions_desktop_search": 20,
            "impressions_mobile_maps": 30,
            "impressions_mobile_search": 40,
        }
    }
    row = rows_for_location(loc, by_day)[0]
    assert row["impressions_desktop_maps"] == 10
    assert row["impressions_desktop_search"] == 20
    assert row["impressions_mobile_maps"] == 30
    assert row["impressions_mobile_search"] == 40
