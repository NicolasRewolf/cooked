"""T-16 — fonctions pures de cooked.gbp : queue rembourrée à zéro et lignes store."""
from datetime import date

from cooked.gbp import _to_store_rows, _trim_unconsolidated


def test_trim_unconsolidated_cuts_trailing_zero_days_only():
    rows = {
        date(2026, 8, 18): {"CALL_CLICKS": 5, "WEBSITE_CLICKS": 3},
        date(2026, 8, 19): {"CALL_CLICKS": 0, "WEBSITE_CLICKS": 0},  # vrai zéro au milieu : conservé
        date(2026, 8, 20): {"CALL_CLICKS": 4, "WEBSITE_CLICKS": 2},
        date(2026, 8, 21): {"CALL_CLICKS": 0, "WEBSITE_CLICKS": 0},  # queue non consolidée : coupée
        date(2026, 8, 22): {"CALL_CLICKS": 0, "WEBSITE_CLICKS": 0},
    }
    kept = _trim_unconsolidated(rows)
    assert sorted(kept) == [date(2026, 8, 18), date(2026, 8, 19), date(2026, 8, 20)]
    assert _trim_unconsolidated({date(2026, 8, 21): {"CALL_CLICKS": 0}}) == {}


def test_to_store_rows_is_long_format_sorted():
    out = _to_store_rows("locations/1", {date(2026, 8, 20): {"WEBSITE_CLICKS": 2, "CALL_CLICKS": 4}})
    assert [(r["day"], r["metric"], r["value"]) for r in out] == [
        ("2026-08-20", "CALL_CLICKS", 4), ("2026-08-20", "WEBSITE_CLICKS", 2)]
    assert all(r["location"] == "locations/1" and r["ingested_at"] for r in out)
