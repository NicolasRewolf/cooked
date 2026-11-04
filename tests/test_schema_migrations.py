"""A malformed or unavailable migration inventory cannot be reported as healthy."""
import importlib.util
from pathlib import Path
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "check_schema_migrations", ROOT / "scripts/check_schema_migrations.py",
)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


@pytest.fixture
def migrations(tmp_path, monkeypatch):
    monkeypatch.setattr(guard, "MIGRATIONS", tmp_path / "migrations")
    monkeypatch.delenv("DATABASE_URL", raising=False)
    return guard.MIGRATIONS


def write_migration(directory, name):
    directory.mkdir(exist_ok=True)
    (directory / name).write_text("SELECT 1;\n", encoding="utf-8")


@pytest.mark.parametrize("state", ["missing", "empty", "invalid", "duplicate"])
def test_invalid_local_inventory_fails(migrations, state, capsys):
    if state == "empty":
        migrations.mkdir()
    elif state == "invalid":
        write_migration(migrations, "20261104120000_valid.sql")
        write_migration(migrations, "bad_migration.sql")
    elif state == "duplicate":
        write_migration(migrations, "20261104120000_first.sql")
        write_migration(migrations, "20261104120000_second.sql")
    assert guard.main() == 1
    assert "OK" not in capsys.readouterr().out


def test_valid_local_inventory_passes(migrations):
    write_migration(migrations, "20261104120000_valid.sql")
    assert guard.main() == 0


def test_requested_database_check_requires_driver(migrations, monkeypatch, capsys):
    write_migration(migrations, "20261104120000_valid.sql")
    monkeypatch.setenv("DATABASE_URL", "synthetic-url-never-connected")
    monkeypatch.setitem(sys.modules, "psycopg2", None)
    assert guard.main() == 1
    assert "psycopg2" in capsys.readouterr().out
