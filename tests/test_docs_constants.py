"""Le contrôle documentaire refuse guides absents, versions manquantes et liens cassés."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
VERSIONS = """| Tracker | `sprint44` | vérifié |
| Edge `track` | v32 | vérifié |
| Edge `form-webhook` | `v17` | vérifié |
"""


def git_environment() -> dict[str, str]:
    return {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}


@pytest.fixture
def docs_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    for directory in ("scripts", "contracts", "docs"):
        (repo / directory).mkdir(parents=True)
    shutil.copyfile(ROOT / "scripts/check_docs_constants.py", repo / "scripts/check_docs_constants.py")
    constants = json.loads((ROOT / "contracts/doc_constants.json").read_text())
    constants["versions"] = {"tracker": "sprint44", "edge_track": 32, "edge_form_webhook": 17}
    constants["docs"]["living_docs"] = ["README.md", "AGENTS.md", "docs/README.md", "docs/OPERATIONS.md"]
    constants["docs"]["index_docs"] = ["README.md", "AGENTS.md", "docs/README.md"]
    constants["cron_jobs"] = []
    (repo / "contracts/doc_constants.json").write_text(json.dumps(constants))
    (repo / "AGENTS.md").write_text(VERSIONS + "[Documentation](docs/README.md)\n")
    (repo / "README.md").write_text("[Agents](AGENTS.md)\n")
    (repo / "docs/README.md").write_text("[Accueil](../README.md)\n[Exploitation](OPERATIONS.md)\n")
    (repo / "docs/OPERATIONS.md").write_text("Guide courant.\n")
    subprocess.run(["git", "init", "-q", str(repo)], env=git_environment(), check=True)
    subprocess.run(["git", "add", "."], cwd=repo, env=git_environment(), check=True)
    return repo


def check(repo: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(repo / "scripts/check_docs_constants.py")], cwd=repo,
        env=git_environment(), text=True, capture_output=True, check=False,
    )


def test_current_index_and_versions_pass(docs_repo: Path):
    result = check(docs_repo)
    assert result.returncode == 0, result.stdout + result.stderr


def test_required_document_cannot_disappear(docs_repo: Path):
    (docs_repo / "docs/OPERATIONS.md").unlink()
    result = check(docs_repo)
    assert result.returncode == 1
    assert "docs/OPERATIONS.md : document déclaré absent" in result.stdout


@pytest.mark.parametrize("label,row", [("Tracker", 0), ("Edge track", 1), ("Edge form-webhook", 2)])
def test_each_canonical_version_is_required(docs_repo: Path, label: str, row: int):
    agents = docs_repo / "AGENTS.md"
    agents.write_text(agents.read_text().replace(VERSIONS.splitlines(keepends=True)[row], ""))
    result = check(docs_repo)
    assert result.returncode == 1
    assert f"version canonique {label} attendue une fois, trouvée 0 fois" in result.stdout


def test_duplicate_or_wrong_version_fails(docs_repo: Path):
    agents = docs_repo / "AGENTS.md"
    agents.write_text(agents.read_text() + "| Tracker | `sprint43` | ancien |\n")
    result = check(docs_repo)
    assert result.returncode == 1
    assert "trouvée 2 fois" in result.stdout
    assert "≠ sprint44" in result.stdout


@pytest.mark.parametrize("link", ["[Guide](absent.md)", "[Guide][source]\n[source]: absent.md"])
def test_broken_links_in_non_living_document_fail(docs_repo: Path, link: str):
    github = docs_repo / ".github"
    github.mkdir()
    (github / "guide.md").write_text(link)
    result = check(docs_repo)
    assert result.returncode == 1
    assert ".github/guide.md" in result.stdout
    assert "lien local absent : .github/absent.md" in result.stdout


def test_links_resolve_paths_without_scanning_code_examples(docs_repo: Path):
    (docs_repo / "docs/notes utiles.txt").write_text("Texte.\n")
    guide = docs_repo / "docs/OPERATIONS.md"
    guide.write_text('''[Notes](notes%20utiles.txt#section)
[Notes avec espaces](<notes utiles.txt>)
[Dossier](../scripts/)
[Chemin racine](/README.md)
[Ancre](#section)
[Externe](https://example.invalid/inconnu)
[Courriel](mailto:example@example.invalid)
`[Exemple](absent.md)`
```md
[Exemple](absent.md)
```
''')
    result = check(docs_repo)
    assert result.returncode == 0, result.stdout + result.stderr


def test_same_basename_does_not_index_another_document(docs_repo: Path):
    for directory in ("a", "b"):
        (docs_repo / "docs" / directory).mkdir()
        (docs_repo / "docs" / directory / "topic.md").write_text("Guide.\n")
    index = docs_repo / "docs/README.md"
    index.write_text(index.read_text() + "[Sujet](a/topic.md)\n")
    result = check(docs_repo)
    assert result.returncode == 1
    assert "docs/b/topic.md : n'est lié par aucun index" in result.stdout
    assert "docs/a/topic.md : n'est lié" not in result.stdout


def test_deleted_tracked_and_ignored_documents_are_not_orphans(docs_repo: Path):
    retired = docs_repo / "docs/retired.md"
    retired.write_text("Retiré.\n")
    subprocess.run(["git", "add", "docs/retired.md"], cwd=docs_repo, env=git_environment(), check=True)
    retired.unlink()
    (docs_repo / ".gitignore").write_text("private.md\n")
    (docs_repo / "private.md").write_text("[Privé](absent.md)\n")
    result = check(docs_repo)
    assert result.returncode == 0, result.stdout + result.stderr


def test_link_cannot_depend_on_file_outside_repository(docs_repo: Path):
    (docs_repo.parent / "outside.md").write_text("Hors dépôt.\n")
    (docs_repo / "README.md").write_text("[Agents](AGENTS.md)\n[Externe](../outside.md)\n")
    result = check(docs_repo)
    assert result.returncode == 1
    assert "README.md:2: lien local hors du dépôt" in result.stdout
