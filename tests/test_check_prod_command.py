"""Run the real check-prod recipe with a recorder instead of database scripts."""

import os
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
CHECKS = [
    ("scripts/check_prod_drift.py", ""),
    ("scripts/check_normalize_vectors.py", ""),
    ("scripts/generate_dashboard_contracts.py", "--check"),
]


@pytest.fixture
def run_check_prod(tmp_path):
    recorder = tmp_path / "fake-python"
    log = tmp_path / "checks.log"
    recorder.write_text(
        "#!/bin/sh\n"
        "printf '%s\\t%s\\t%s\\n' \"$1\" \"${2-}\" \"$DATABASE_URL\" "
        ">> \"$COOKED_CHECK_TEST_LOG\"\n"
        "if [ \"$1\" = \"$COOKED_CHECK_FAIL_SCRIPT\" ]; then exit 7; fi\n"
    )
    recorder.chmod(0o755)

    def run(database_env, *, fail_script=""):
        # Deliberately do not inherit database credentials, MAKEFLAGS or .env files.
        env = {
            "PATH": os.defpath,
            "COOKED_CHECK_TEST_LOG": str(log),
            "COOKED_CHECK_FAIL_SCRIPT": fail_script,
            **database_env,
        }
        result = subprocess.run(
            ["make", "-f", str(ROOT / "Makefile"), "check-prod", f"PYTHON={recorder}"],
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        calls = [line.split("\t") for line in log.read_text().splitlines()] if log.exists() else []
        return result, calls

    return run


@pytest.mark.parametrize("failed_index", range(len(CHECKS)))
def test_check_prod_stops_at_first_failed_check(run_check_prod, failed_index):
    result, calls = run_check_prod(
        {"DATABASE_URL_RO": "fake-read-only-url"},
        fail_script=CHECKS[failed_index][0],
    )

    assert result.returncode != 0
    assert calls == [
        [script, argument, "fake-read-only-url"]
        for script, argument in CHECKS[: failed_index + 1]
    ]


@pytest.mark.parametrize(
    ("database_env", "expected_url"),
    [
        ({"DATABASE_URL_RO": "fake-read-only-url"}, "fake-read-only-url"),
        (
            {"DATABASE_URL_RO": "fake-read-only-url", "DATABASE_URL": "fake-primary-url"},
            "fake-read-only-url",
        ),
        ({"DATABASE_URL": "fake-primary-url"}, "fake-primary-url"),
        ({"DATABASE_URL_RO": "", "DATABASE_URL": "fake-primary-url"}, "fake-primary-url"),
    ],
)
def test_check_prod_runs_all_checks_with_selected_url(run_check_prod, database_env, expected_url):
    result, calls = run_check_prod(database_env)

    assert result.returncode == 0, result.stderr
    assert calls == [[script, argument, expected_url] for script, argument in CHECKS]


def test_check_prod_requires_database_url_before_running_any_check(run_check_prod):
    result, calls = run_check_prod({})

    assert result.returncode != 0
    assert "DATABASE_URL_RO (ou DATABASE_URL) requis" in result.stdout
    assert calls == []
