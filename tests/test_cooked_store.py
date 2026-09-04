"""C7 — adaptateur store partagé GSC/DFS."""
from __future__ import annotations

from cooked.store import FakeStore


def test_fake_store_batches_upserts() -> None:
    store = FakeStore()
    rows = [{"day": "2026-06-01", "path": "/a", "clicks": 1}]
    store.upsert_batches("gsc_path_daily", rows, "day,path", batch_size=1)
    store.upsert_batches("gsc_path_daily", rows * 2, "day,path", batch_size=2)
    assert len(store.upserts) == 2
    assert store.upserts[0].table == "gsc_path_daily"
    assert store.upserts[0].on_conflict == "day,path"
    assert len(store.upserts[0].rows) == 1
    assert len(store.upserts[1].rows) == 2


def test_fake_store_rpc() -> None:
    store = FakeStore(
        rpc_handlers={
            "dfs_keywords_to_sync": lambda p: [{"keyword": "garde à vue"}],
        }
    )
    resp = store.rpc("dfs_keywords_to_sync", {"limit_n": 3})
    assert resp.data == [{"keyword": "garde à vue"}]
