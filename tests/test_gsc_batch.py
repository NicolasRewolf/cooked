"""Le refresh ne voit jamais une ingestion GSC partielle comme complète."""
from datetime import date

import pytest

from cooked import gsc
from cooked.store import FakeStore


def prepare(monkeypatch, *, fail_at=None, empty=False):
    calls = []

    class Store(FakeStore):
        def rpc(self, name, params):
            calls.append((name, params))
            return super().rpc(name, params)

    store = Store()

    def path_query(end_date, months_back, *, store):
        calls.append(("path_query", None))
        if fail_at == "path_query":
            raise RuntimeError("synthetic path failure")
        return {"gsc_path_daily": 0 if empty else 10, "gsc_query_daily": 0 if empty else 20}

    def query_page(end_date, months_back, *, store):
        calls.append(("query_page", None))
        if fail_at == "query_page":
            raise RuntimeError("synthetic query-page failure")
        return {"gsc_query_page_daily": 0 if empty else 30}

    monkeypatch.setattr(gsc, "run_path_query", path_query)
    monkeypatch.setattr(gsc, "run_query_page", query_page)
    return store, calls


def test_publish_happens_only_after_all_sources(monkeypatch):
    store, calls = prepare(monkeypatch)
    gsc.run_ingestion("all", date(2026, 7, 1), 2, store)
    assert [name for name, _ in calls] == [
        "gsc_ingest_begin", "path_query", "query_page", "gsc_ingest_complete"
    ]
    begin, complete = calls[0][1], calls[-1][1]
    assert begin["p_start"] == "2026-06-01"
    assert begin["p_end"] == "2026-07-01"
    assert begin["p_run_id"] == complete["p_run_id"]
    assert complete["p_row_counts"] == {
        "gsc_path_daily": 10, "gsc_query_daily": 20, "gsc_query_page_daily": 30,
    }


@pytest.mark.parametrize("fail_at", ["path_query", "query_page"])
def test_interrupted_batch_is_never_published(monkeypatch, fail_at):
    store, calls = prepare(monkeypatch, fail_at=fail_at)
    with pytest.raises(RuntimeError):
        gsc.run_ingestion("all", date(2026, 7, 1), 2, store)
    assert calls[0][0] == "gsc_ingest_begin"
    assert all(name != "gsc_ingest_complete" for name, _ in calls)
    assert calls[-1][0] == "gsc_ingest_fail"


@pytest.mark.parametrize("mode", ["path-query", "query-page"])
def test_partial_commands_cannot_publish(monkeypatch, mode, capsys):
    store, calls = prepare(monkeypatch)
    gsc.run_ingestion(mode, date(2026, 7, 1), 2, store)
    assert calls[0][0] == "gsc_ingest_begin"
    assert all(name != "gsc_ingest_complete" for name, _ in calls)
    assert calls[-1][0] == "gsc_ingest_fail"
    assert "rafraîchissement aval reste suspendu" in capsys.readouterr().out


def test_empty_batch_is_not_a_success(monkeypatch):
    store, calls = prepare(monkeypatch, empty=True)
    with pytest.raises(RuntimeError, match="vide"):
        gsc.run_ingestion("all", date(2026, 7, 1), 2, store)
    assert all(name != "gsc_ingest_complete" for name, _ in calls)


def test_begin_failure_prevents_source_writes(monkeypatch):
    store, calls = prepare(monkeypatch)

    def unavailable(_):
        raise RuntimeError("refresh already holds lock")

    store.rpc_handlers["gsc_ingest_begin"] = unavailable
    with pytest.raises(RuntimeError):
        gsc.run_ingestion("all", date(2026, 7, 1), 2, store)
    assert [name for name, _ in calls] == ["gsc_ingest_begin"]


def test_failure_notification_does_not_mask_source_error(monkeypatch):
    store, calls = prepare(monkeypatch, fail_at="query_page")

    def unavailable(_):
        raise ValueError("database also unavailable")

    store.rpc_handlers["gsc_ingest_fail"] = unavailable
    with pytest.raises(RuntimeError, match="synthetic query-page failure"):
        gsc.run_ingestion("all", date(2026, 7, 1), 2, store)
    assert calls[-1][0] == "gsc_ingest_fail"


@pytest.mark.parametrize("mode,months", [("unknown", 2), ("all", 0)])
def test_invalid_run_does_not_touch_database(monkeypatch, mode, months):
    store, calls = prepare(monkeypatch)
    with pytest.raises(ValueError):
        gsc.run_ingestion(mode, date(2026, 7, 1), months, store)
    assert calls == []
