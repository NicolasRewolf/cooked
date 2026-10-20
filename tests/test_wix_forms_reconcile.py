from datetime import date

import pytest

from cooked.wix.reconcile import compare_counts, utc_bounds, wix_daily_counts


class Response:
    def __init__(self, data):
        self.data = data

    def raise_for_status(self):
        pass

    def json(self):
        return self.data


def submission(ident, when="2026-10-20T22:30:00Z"):
    return {
        "id": ident, "createdDate": when, "status": "CONFIRMED",
        "submissions": {"ignored_private_field": "must never leave the reader"},
    }


def test_paris_bounds_follow_daylight_saving():
    assert utc_bounds(date(2026, 10, 25), date(2026, 10, 25)) == (
        "2026-10-24T22:00:00+00:00", "2026-10-25T23:00:00+00:00",
    )


def test_all_cursor_pages_count_paris_day_without_exporting_payload():
    calls = []
    pages = [
        {"submissions": [submission("one")], "metadata": {"hasNext": True, "cursors": {"next": "page2"}}},
        {"submissions": [submission("two")], "metadata": {"hasNext": False}},
    ]

    def post(url, **kwargs):
        calls.append(kwargs["json"])
        return Response(pages.pop(0))

    counts = wix_daily_counts("synthetic", "synthetic", date(2026, 10, 21), date(2026, 10, 21), post=post)
    assert counts == {"2026-10-21": 2}
    assert calls[0]["onlyYourOwn"] is False
    assert calls[1]["query"] == {"cursorPaging": {"limit": 100, "cursor": "page2"}}


@pytest.mark.parametrize("metadata", [
    {}, {"hasNext": True}, {"hasNext": True, "cursors": {"next": ""}},
])
def test_incomplete_pagination_is_not_silently_accepted(metadata):
    with pytest.raises(ValueError):
        wix_daily_counts("x", "x", date(2026, 10, 21), date(2026, 10, 21),
                         post=lambda *a, **k: Response({"submissions": [], "metadata": metadata}))


@pytest.mark.parametrize("rows", [
    [submission("same"), submission("same")],
    [submission("outside", "2026-10-19T12:00:00Z")],
    [{**submission("bad"), "status": "PENDING"}],
    [{**submission("bad"), "createdDate": "2026-10-21T12:00:00"}],
])
def test_invalid_results_do_not_produce_a_comparison(rows):
    with pytest.raises(ValueError):
        wix_daily_counts("x", "x", date(2026, 10, 21), date(2026, 10, 21),
                         post=lambda *a, **k: Response({"submissions": rows, "metadata": {"hasNext": False}}))


def test_equal_totals_do_not_hide_daily_mismatches():
    result = compare_counts({"2026-10-20": 1, "2026-10-21": 2}, [
        {"day": "2026-10-20", "submissions": 2},
        {"day": "2026-10-21", "submissions": 1},
    ])
    assert result["wix_forms"] == result["cooked_forms"] == 3
    assert result["mismatched_days"] == 2


def test_missing_cooked_day_is_not_assumed_to_be_zero():
    with pytest.raises(ValueError, match="incomplète"):
        compare_counts({"2026-10-20": 0}, [])
