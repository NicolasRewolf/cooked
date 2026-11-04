"""Les contrôles de dates refusent un diff Git impossible ou incomplet."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
VALID_RPCS = """-- ═══ public.paris_date(p_ts timestamp with time zone) ═══
CREATE OR REPLACE FUNCTION public.paris_date(p_ts timestamptz)
RETURNS date LANGUAGE sql AS $$ SELECT (p_ts AT TIME ZONE 'Europe/Paris')::date $$;
-- ═══ public.paris_today() ═══
CREATE OR REPLACE FUNCTION public.paris_today()
RETURNS date LANGUAGE sql AS $$ SELECT public.paris_date(now()) $$;
"""


def isolated_env() -> dict[str, str]:
    env = {
        key: value for key, value in os.environ.items()
        if not key.startswith(("GIT_", "GITHUB_"))
    }
    env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
    return env


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", *args],
        cwd=repo, env=isolated_env(), capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()


def commit(repo: Path, message: str) -> str:
    git(repo, "add", ".")
    git(repo, "commit", "-m", message)
    return git(repo, "rev-parse", "HEAD")


@pytest.fixture
def date_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    (repo / "scripts").mkdir(parents=True)
    (repo / "supabase/migrations").mkdir(parents=True)
    for name in ("check_migration_paris_date.py", "git_changes.py"):
        shutil.copyfile(ROOT / "scripts" / name, repo / "scripts" / name)
    (repo / "supabase/rpcs.sql").write_text(VALID_RPCS, encoding="utf-8")
    git(repo, "init", "-b", "main")
    git(repo, "config", "user.name", "Synthetic test")
    git(repo, "config", "user.email", "test@example.invalid")
    commit(repo, "baseline")
    git(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
    return repo


def run_guard(repo: Path, *args: str, **environment: str) -> subprocess.CompletedProcess[str]:
    env = isolated_env()
    env.update(GITHUB_ACTIONS="1", GITHUB_EVENT_NAME="pull_request", GITHUB_BASE_REF="main")
    env.update(environment)
    return subprocess.run(
        [sys.executable, str(repo / "scripts/check_migration_paris_date.py"), *args],
        cwd=repo, env=env, text=True, capture_output=True, check=False,
    )


def test_missing_base_is_failure_even_with_valid_inline_contract(date_repo: Path):
    result = run_guard(date_repo, GITHUB_BASE_REF="missing")
    assert result.returncode != 0
    assert "C6b OK" in result.stdout
    assert "impossible de vérifier les migrations" in result.stderr
    assert "origin/missing" in result.stderr
    assert "aucune migration modifiée" not in result.stdout


def test_no_changed_migration_passes(date_repo: Path):
    result = run_guard(date_repo)
    assert result.returncode == 0, result.stderr
    assert "C6b OK" in result.stdout
    assert "aucune migration modifiée" in result.stdout


@pytest.mark.parametrize("event", ["pull_request", "push"])
def test_invalid_changed_migration_fails(date_repo: Path, event: str):
    migration = date_repo / "supabase/migrations/20261102120000_bad.sql"
    migration.write_text("SELECT current_date;\n", encoding="utf-8")
    commit(date_repo, "invalid migration")
    result = run_guard(date_repo, GITHUB_EVENT_NAME=event)
    assert result.returncode != 0
    assert "C6c contract violation" in result.stdout
    assert migration.name in result.stdout


def test_push_checks_migration_before_last_commit(date_repo: Path):
    before = git(date_repo, "rev-parse", "HEAD")
    migration = date_repo / "supabase/migrations/20261102120000_bad.sql"
    migration.write_text("SELECT current_date;\n", encoding="utf-8")
    commit(date_repo, "invalid migration")
    (date_repo / "note.txt").write_text("later unrelated change\n", encoding="utf-8")
    after = commit(date_repo, "unrelated change")
    payload = date_repo.parent / "push.json"
    payload.write_text(json.dumps({"before": before, "after": after}), encoding="utf-8")
    result = run_guard(date_repo, GITHUB_EVENT_NAME="push", GITHUB_EVENT_PATH=str(payload))
    assert result.returncode != 0
    assert "C6c contract violation" in result.stdout
    assert migration.name in result.stdout


def test_inline_failure_reported_alongside_diff_failure(date_repo: Path):
    rpc = date_repo / "supabase/rpcs.sql"
    rpc.write_text(VALID_RPCS.replace("RETURNS date LANGUAGE", "STRICT\nRETURNS date LANGUAGE"))
    result = run_guard(date_repo, GITHUB_BASE_REF="missing")
    assert result.returncode != 0
    assert "C6b contract violation" in result.stdout
    assert "impossible de vérifier les migrations" in result.stderr


def test_inline_failure_still_fails_without_changed_migrations(date_repo: Path):
    rpc = date_repo / "supabase/rpcs.sql"
    rpc.write_text(VALID_RPCS.replace("RETURNS date LANGUAGE", "STRICT\nRETURNS date LANGUAGE"))
    result = run_guard(date_repo)
    assert result.returncode != 0
    assert "C6b contract violation" in result.stdout
    assert "aucune migration modifiée" in result.stdout


def test_explicit_file_scan_does_not_require_git_base(date_repo: Path):
    migration = date_repo / "supabase/migrations/20261102120000_manual.sql"
    migration.write_text("SELECT current_date;\n", encoding="utf-8")
    result = run_guard(date_repo, str(migration), GITHUB_BASE_REF="missing")
    assert result.returncode != 0
    assert "C6c contract violation" in result.stdout
    assert "impossible de vérifier" not in result.stderr


def test_local_full_scan_remains_available(date_repo: Path):
    migration = date_repo / "supabase/migrations/20261102120000_local.sql"
    migration.write_text("SELECT paris_today();\n", encoding="utf-8")
    result = run_guard(date_repo, GITHUB_ACTIONS="", GITHUB_BASE_REF="missing")
    assert result.returncode == 0, result.stderr
    assert "1 fichier(s) scanné(s)" in result.stdout


@pytest.mark.parametrize("state", ["staged", "unstaged", "untracked"])
def test_local_diff_scan_checks_uncommitted_migrations(date_repo: Path, state: str):
    migration = date_repo / "supabase/migrations/20261102120000_uncommitted.sql"
    if state == "unstaged":
        migration.write_text("SELECT paris_today();\n", encoding="utf-8")
        commit(date_repo, "tracked migration")
        git(date_repo, "update-ref", "refs/remotes/origin/main", "HEAD")
    migration.write_text("SELECT current_date;\n", encoding="utf-8")
    if state == "staged":
        git(date_repo, "add", str(migration))
    # make check enables diff mode without a GitHub push/PR payload.
    result = run_guard(date_repo, GITHUB_EVENT_NAME="")
    assert result.returncode == 1
    assert "C6c contract violation" in result.stdout
    assert migration.name in result.stdout
