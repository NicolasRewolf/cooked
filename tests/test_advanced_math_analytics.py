"""The real cache CLI keeps missing contacts distinct from an observed zero."""
import json
import importlib.util
import os
from datetime import date
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/advanced_math_analytics.py"
METADATA = {
    "window_days": 28,
    "window_start": "2026-10-01",
    "window_end": "2026-10-28",
    "computed_at": "2026-10-29T06:00:00+00:00",
    "calculation_version": "paris_j1_v1",
}


@pytest.fixture
def cache(tmp_path):
    rows = [
        {"journey": ["/post/bridge", "/honoraires-rendez-vous"],
         "converted": True, "entry_channel": "organic_google", "n": 8},
        {"journey": ["/post/bridge"], "converted": False,
         "entry_channel": "organic_google", "n": 12},
    ]
    edges = [{"src": "/post/bridge", "dst": "/honoraires-rendez-vous",
              "kind": "flow", "placement": None, "weight": 8, "dst_resolved": False}]
    for name, data in (
        ("visit_sequences_28", [row | METADATA for row in rows]),
        ("internal_edges_28", [row | METADATA for row in edges]),
        ("gsc_daily", []), ("annotations", []),
    ):
        (tmp_path / f"{name}.json").write_text(json.dumps(data))
    return tmp_path


def run_cli(cache, *args):
    output = cache / "report.json"
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("SUPABASE_", "DATABASE_"))}
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--source", "cache", "--cache-dir", str(cache),
         "--bootstrap", "0", "--permutations", "20", "--json-out", str(output), *args],
        cwd=ROOT, env=env, text=True, capture_output=True, check=False,
    )
    return result, json.loads(output.read_text()) if output.exists() else None


def test_missing_contacts_keep_independent_analyses_but_no_invented_assists(cache):
    result, report = run_cli(cache)

    assert result.returncode == 2, result.stderr
    assert report["markov"]["n_conversions"] == 8
    assert report["graph"]["n_edges"] == 1
    assert report["shapley"]["shapley"]
    assert report["comparison"]["status"] == "unavailable"
    assert report["invisible_bridges"] is None
    assert report["bridges"]
    assert all(row["direct_contacts"] is None and row["assist_ratio"] is None
               for row in report["bridges"])
    assert "contacts directs indisponibles" in result.stdout.lower()


def test_snapshots_from_different_periods_are_not_combined(cache):
    path = cache / "internal_edges_28.json"
    rows = json.loads(path.read_text())
    for row in rows:
        row.update(window_start="2026-10-02", window_end="2026-10-29")
    path.write_text(json.dumps(rows))

    result, report = run_cli(cache)

    assert result.returncode == 2, result.stderr
    assert report["comparison"]["status"] == "incompatible"
    assert report["bridges"] is None
    assert report["invisible_bridges"] is None
    assert report["markov"]["n_conversions"] == 8
    assert report["graph"]["n_edges"] == 1
    assert report["sources"]["visit_sequences"]["window_end"] == "2026-10-28"
    assert "périodes ou versions différentes" in result.stdout.lower()


def test_confirmed_empty_contacts_are_an_observed_zero(cache):
    (cache / "macro_contacts_28.json").write_text(json.dumps({
        "metadata": {"window_start": "2026-10-01", "window_end": "2026-10-28"},
        "rows": [],
    }))
    result, report = run_cli(cache)

    assert result.returncode == 0, result.stderr
    assert report["status"] == "complete"
    assert report["comparison"]["status"] == "available"
    assert report["invisible_bridges"]
    assert all(row["direct_contacts"] == 0 and row["assist_ratio"] == 1
               for row in report["bridges"])
    assert "01/10/2026" in result.stdout
    assert "28/10/2026" in result.stdout


@pytest.mark.parametrize("change", ["legacy", "different_generation", "different_version"])
def test_unverified_snapshot_is_not_silently_combined(cache, change):
    path = cache / "internal_edges_28.json"
    rows = json.loads(path.read_text())
    if change == "legacy":
        rows = [{key: value for key, value in row.items() if key not in METADATA} for row in rows]
    elif change == "different_generation":
        rows[0]["computed_at"] = "2026-10-29T07:00:00+00:00"
    else:
        rows[0]["calculation_version"] = "legacy_rolling"
    path.write_text(json.dumps(rows))

    result, report = run_cli(cache)

    assert result.returncode == 2, result.stderr
    assert report["comparison"]["status"] == "incompatible"
    assert report["bridges"] is None
    assert report["invisible_bridges"] is None
    assert report["markov"]["n_conversions"] == 8


@pytest.mark.parametrize("contacts", [
    [],
    {"metadata": {"window_start": "2026-10-02", "window_end": "2026-10-29"},
     "rows": [{"path": "/post/bridge", "contacts": 8}]},
])
def test_unverified_or_different_contact_dates_do_not_become_zero(cache, contacts):
    (cache / "macro_contacts_28.json").write_text(json.dumps(contacts))
    result, report = run_cli(cache)

    assert result.returncode == 2, result.stderr
    assert report["comparison"]["status"] == "unavailable"
    assert all(row["direct_contacts"] is None for row in report["bridges"])
    assert report["invisible_bridges"] is None


def test_metadata_envelopes_replay_a_known_contact_count(cache):
    for name in ("visit_sequences_28", "internal_edges_28"):
        path = cache / f"{name}.json"
        rows = [{key: value for key, value in row.items() if key not in METADATA}
                for row in json.loads(path.read_text())]
        path.write_text(json.dumps({"metadata": METADATA, "rows": rows}))
    (cache / "macro_contacts_28.json").write_text(json.dumps({
        "metadata": {"window_start": "2026-10-01", "window_end": "2026-10-28"},
        "rows": [{"path": "/post/bridge", "contacts": 8}],
    }))
    result, report = run_cli(cache)

    assert result.returncode == 0, result.stderr
    bridge = next(row for row in report["bridges"] if row["path"] == "/post/bridge")
    assert bridge["direct_contacts"] == 8
    assert bridge["assist_ratio"] == 0
    assert all(row["path"] != "/post/bridge" for row in report["invisible_bridges"])


@pytest.mark.parametrize("computed_at,expected_status", [
    ("2026-10-28T20:00:00+00:00", "unverified"),
    ("2026-10-28T23:30:00+00:00", "verified"),
])
def test_snapshot_j1_metadata_uses_the_paris_generation_day(cache, computed_at, expected_status):
    path = cache / "visit_sequences_28.json"
    rows = json.loads(path.read_text())
    for row in rows:
        row["computed_at"] = computed_at
    path.write_text(json.dumps(rows))

    result, report = run_cli(cache, "--module", "markov")

    assert report["sources"]["visit_sequences"]["status"] == expected_status
    assert result.returncode == (0 if expected_status == "verified" else 2)


@pytest.fixture
def analytics():
    spec = importlib.util.spec_from_file_location("cooked_math_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize(("data", "total", "expected"), [
    (None, 0, None),
    ([], None, None),
    ([{"path": "/a", "contacts": 2}], 2, None),
    ([], 0, {}),
    ([{"path": "/a", "contacts": 2}], 1, {"/a": 2}),
])
def test_supabase_contacts_require_a_complete_result_for_the_requested_dates(
    analytics, monkeypatch, data, total, expected,
):
    calls = []

    class Postgrest:
        def rpc(self, name, params, *, count=None):
            calls.append((name, params, count))
            return SimpleNamespace(execute=lambda: SimpleNamespace(data=data, count=total))

    monkeypatch.setattr("supabase.create_client", lambda _url, _key: Postgrest())
    source = analytics.SupabaseSource("https://example.invalid", "synthetic")
    if expected is None:
        with pytest.raises(analytics.DataUnavailable):
            source.macro_contacts(date(2026, 10, 1), date(2026, 10, 28))
    else:
        assert source.macro_contacts(date(2026, 10, 1), date(2026, 10, 28)) == expected
    assert calls == [("macro_contacts_by_path", {
        "start_date": "2026-10-01", "end_date": "2026-10-28",
    }, "exact")]


def test_supabase_report_reads_snapshot_metadata_and_exact_contact_period(
    analytics, cache, monkeypatch,
):
    tables = {
        "math_visit_sequences_snapshot": json.loads((cache / "visit_sequences_28.json").read_text()),
        "math_internal_edges_snapshot": json.loads((cache / "internal_edges_28.json").read_text()),
        "gsc_path_daily": [], "annotations": [],
    }
    calls = []

    class TableQuery:
        def __init__(self, rows):
            self.rows = rows

        def select(self, columns):
            self.rows = [{key: row[key] for key in columns.split(",") if key in row}
                         for row in self.rows]
            return self

        def eq(self, key, value):
            self.rows = [row for row in self.rows if row.get(key) == value]
            return self

        def range(self, start, end):
            self.rows = self.rows[start:end + 1]
            return self

        def execute(self):
            return SimpleNamespace(data=self.rows)

    class Postgrest:
        def table(self, name):
            return TableQuery(tables[name])

        def rpc(self, name, params, *, count):
            calls.append((name, params))
            return SimpleNamespace(execute=lambda: SimpleNamespace(data=[], count=0))

    monkeypatch.setenv("SUPABASE_SECRET_KEY", "synthetic-test-key")
    monkeypatch.setenv("SUPABASE_URL", "https://example.invalid")
    monkeypatch.setattr("supabase.create_client", lambda _url, _key: Postgrest())
    output = cache / "supabase-report.json"
    code = analytics.main(["--bootstrap", "0", "--permutations", "20",
                           "--json-out", str(output)])
    report = json.loads(output.read_text())

    assert code == 0
    assert report["sources"]["visit_sequences"]["computed_at"] == METADATA["computed_at"]
    assert report["sources"]["internal_edges"]["calculation_version"] == "paris_j1_v1"
    assert report["comparison"]["status"] == "available"
    assert calls == [("macro_contacts_by_path", {
        "start_date": "2026-10-01", "end_date": "2026-10-28",
    })]
