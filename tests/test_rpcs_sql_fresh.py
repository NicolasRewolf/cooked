"""The RPC guard must inspect the real Git diff and fail if it cannot do so."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "scripts/check_rpcs_sql_fresh.py"
MIGRATION = "supabase/migrations/20261102000000_example.sql"


def clean_env():
    env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "GITHUB_"))}
    env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
    return env


def git(repo, *args):
    return subprocess.run(
        ["git", *args], cwd=repo, env=clean_env(),
        check=True, capture_output=True, text=True,
    ).stdout.strip()


def write(repo, path, content):
    target = repo / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def commit(repo):
    git(repo, "add", ".")
    git(repo, "commit", "-m", "synthetic change")
    return git(repo, "rev-parse", "HEAD")


@pytest.fixture
def repo(tmp_path):
    git(tmp_path, "init", "--initial-branch=main")
    git(tmp_path, "config", "user.name", "Synthetic Test")
    git(tmp_path, "config", "user.email", "test@example.invalid")
    for path in (SCRIPT, "scripts/git_changes.py"):
        (tmp_path / path).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / path, tmp_path / path)
    write(tmp_path, "supabase/rpcs.sql", "-- empty snapshot\n")
    write(tmp_path, "contracts/rpc_snapshot_meta.json", "{}\n")
    commit(tmp_path)
    git(tmp_path, "update-ref", "refs/remotes/origin/main", "HEAD")
    return tmp_path


def add_rpc(repo, *, snapshot=False, metadata=False, marker=True):
    write(repo, MIGRATION, "CREATE OR REPLACE FUNCTION public.example() RETURNS int "
          "LANGUAGE sql AS $$ SELECT 1 $$;\n")
    if snapshot:
        write(repo, "supabase/rpcs.sql", "-- ═══ public.example() ═══\n" if marker else "-- changed\n")
    if metadata:
        write(repo, "contracts/rpc_snapshot_meta.json", '{"sha256":"synthetic"}\n')
    commit(repo)


def run_guard(repo, event, **extra_env):
    env = clean_env()
    env.update(GITHUB_EVENT_NAME=event, **extra_env)
    return subprocess.run(
        [sys.executable, SCRIPT], cwd=repo, env=env,
        capture_output=True, text=True, check=False,
    )


@pytest.mark.parametrize("event", ["push", "pull_request"])
def test_rpc_change_without_snapshot_fails(repo, event):
    add_rpc(repo)
    result = run_guard(repo, event)
    assert result.returncode == 1
    assert "supabase/rpcs.sql doit être régénéré" in result.stdout
    assert "contracts/rpc_snapshot_meta.json" in result.stdout
    assert "example" in result.stdout


@pytest.mark.parametrize("event", ["push", "pull_request"])
def test_rpc_change_with_snapshot_and_metadata_passes(repo, event):
    add_rpc(repo, snapshot=True, metadata=True)
    result = run_guard(repo, event)
    assert result.returncode == 0
    assert "1 RPC(s) modifiée(s)" in result.stdout


@pytest.mark.parametrize("event", ["push", "pull_request"])
def test_change_without_rpc_is_a_real_success(repo, event):
    write(repo, "README.md", "Documentation only.\n")
    commit(repo)
    result = run_guard(repo, event)
    assert result.returncode == 0
    assert "aucune migration modifiée" in result.stdout


@pytest.mark.parametrize("event", ["push", "pull_request"])
def test_missing_comparison_base_fails(repo, event):
    # This repository has no HEAD~1; for PRs, deliberately select an absent remote ref.
    result = run_guard(repo, event, GITHUB_BASE_REF="absent")
    assert result.returncode == 1
    assert "Diff Git impossible" in result.stderr
    assert "fetch-depth: 0" in result.stderr
    assert "Arch #5 OK" not in result.stdout


@pytest.mark.parametrize("metadata,marker,expected", [
    (False, True, "contracts/rpc_snapshot_meta.json doit être mis à jour"),
    (True, False, "Marqueurs absents dans rpcs.sql : example"),
])
def test_incomplete_snapshot_fails(repo, metadata, marker, expected):
    add_rpc(repo, snapshot=True, metadata=metadata, marker=marker)
    result = run_guard(repo, "pull_request")
    assert result.returncode == 1
    assert expected in result.stdout


@pytest.mark.parametrize("statement", [
    "CREATE FUNCTION public.example() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$;",
    "CREATE PROCEDURE public.example() LANGUAGE sql AS $$ SELECT 1 $$;",
    "DROP FUNCTION IF EXISTS public.example();",
    "DROP PROCEDURE public.example();",
    "ALTER FUNCTION public.example() SET search_path = public;",
])
def test_routine_changes_require_updated_snapshot(repo, statement):
    write(repo, MIGRATION, statement + "\n")
    commit(repo)
    result = run_guard(repo, "pull_request")
    assert result.returncode == 1
    assert "supabase/rpcs.sql doit être régénéré" in result.stdout
    assert "contracts/rpc_snapshot_meta.json doit être mis à jour" in result.stdout


def test_dropped_routine_does_not_require_a_marker_for_removed_function(repo):
    write(repo, MIGRATION, "DROP FUNCTION public.example();\n")
    write(repo, "supabase/rpcs.sql", "-- updated snapshot after removal\n")
    write(repo, "contracts/rpc_snapshot_meta.json", '{"sha256":"updated"}\n')
    commit(repo)
    result = run_guard(repo, "pull_request")
    assert result.returncode == 0, result.stdout


@pytest.mark.parametrize("recreated", [False, True])
def test_marker_requirement_follows_final_create_or_drop(repo, recreated):
    create = "CREATE FUNCTION public.example() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$;"
    drop = "DROP FUNCTION public.example();"
    statements = [drop, create] if recreated else [create, drop]
    write(repo, MIGRATION, "\n".join(statements) + "\n")
    write(repo, "supabase/rpcs.sql", "-- snapshot without example\n")
    write(repo, "contracts/rpc_snapshot_meta.json", '{"sha256":"updated"}\n')
    commit(repo)
    result = run_guard(repo, "pull_request")
    assert result.returncode == int(recreated), result.stdout
    assert ("Marqueurs absents dans rpcs.sql : example" in result.stdout) == recreated


def test_push_checks_all_commits_in_event(repo, tmp_path):
    before = git(repo, "rev-parse", "HEAD")
    add_rpc(repo)
    write(repo, "README.md", "Later documentation commit.\n")
    after = commit(repo)
    event_file = tmp_path / "push-event.json"
    event_file.write_text(json.dumps({"before": before, "after": after}), encoding="utf-8")

    result = run_guard(repo, "push", GITHUB_EVENT_PATH=str(event_file))
    assert result.returncode == 1
    assert "supabase/rpcs.sql doit être régénéré" in result.stdout


@pytest.mark.parametrize("payload", [
    "{invalid json",
    json.dumps({"before": "0" * 40, "after": "1" * 40}),
])
def test_unusable_push_event_does_not_fall_back_to_incomplete_diff(repo, tmp_path, payload):
    write(repo, "README.md", "No migration in last commit.\n")
    commit(repo)
    event_file = tmp_path / "push-event.json"
    event_file.write_text(payload, encoding="utf-8")
    result = run_guard(repo, "push", GITHUB_EVENT_PATH=str(event_file))
    assert result.returncode == 1
    assert "Bornes du push GitHub indisponibles" in result.stderr
    assert "Arch #5 OK" not in result.stdout


@pytest.mark.parametrize("state", ["staged", "unstaged", "untracked"])
@pytest.mark.parametrize("snapshot", [False, True])
def test_local_guard_includes_uncommitted_changes(repo, state, snapshot):
    if state == "unstaged":
        write(repo, MIGRATION, "SELECT 1;\n")
        commit(repo)
        git(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
    write(repo, MIGRATION, "CREATE FUNCTION public.example() RETURNS int "
          "LANGUAGE sql AS $$ SELECT 1 $$;\n")
    if snapshot:
        write(repo, "supabase/rpcs.sql", "-- ═══ public.example() ═══\n")
        write(repo, "contracts/rpc_snapshot_meta.json", '{"sha256":"working-copy"}\n')
    if state == "staged":
        git(repo, "add", ".")
    result = run_guard(repo, "")
    assert result.returncode == (0 if snapshot else 1), result.stdout
    assert "example" in result.stdout
    assert "aucune migration modifiée" not in result.stdout


@pytest.mark.parametrize("event", ["pull_request", "push"])
def test_ci_payload_keeps_its_committed_scope(repo, tmp_path, event):
    before = git(repo, "rev-parse", "HEAD")
    write(repo, "README.md", "Only this committed file belongs to the event.\n")
    after = commit(repo)
    write(repo, MIGRATION, "CREATE FUNCTION public.example() RETURNS int "
          "LANGUAGE sql AS $$ SELECT 1 $$;\n")
    git(repo, "add", MIGRATION)
    event_file = tmp_path / "event.json"
    event_file.write_text(json.dumps({"before": before, "after": after}), encoding="utf-8")
    result = run_guard(repo, event, GITHUB_EVENT_PATH=str(event_file))
    assert result.returncode == 0, result.stderr
    assert "aucune migration modifiée" in result.stdout


def test_local_guard_excludes_ignored_untracked_files(repo):
    write(repo, ".gitignore", MIGRATION + "\n")
    write(repo, MIGRATION, "CREATE FUNCTION public.ignored() RETURNS int "
          "LANGUAGE sql AS $$ SELECT 1 $$;\n")
    result = run_guard(repo, "")
    assert result.returncode == 0, result.stderr
    assert "aucune migration modifiée" in result.stdout
