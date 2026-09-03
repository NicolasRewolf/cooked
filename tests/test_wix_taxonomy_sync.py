"""T-15 — parse de la liste publiée Wix (fixture du 03/09/2026) → lignes pour page_taxonomy_sync_wix."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from wix_taxonomy_sync import RESSOURCE_CATEGORY_ID, parse_fixture, post_to_row  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "wix_blog_posts_2026-09-03.txt"


def test_fixture_is_the_published_list_of_2026_09_03():
    rows = parse_fixture(FIXTURE.read_text(encoding="utf-8"))
    assert len(rows) == 434
    assert sum(r["category"] == "ressource" for r in rows) == 62
    assert rows[0]["slug"] == "pression-assureurs-gironde-analyse-juridique-cabinet-plouton"
    assert rows[0]["published"] == "2026-08-26"
    assert len({r["slug"] for r in rows}) == 434  # pas de doublon


def test_post_to_row_reads_category_and_date():
    row = post_to_row({"slug": "abandon-de-poste-quels-risques", "categoryIds": ["x", RESSOURCE_CATEGORY_ID],
                       "firstPublishedDate": "2025-01-13T08:00:00.000Z"})
    assert row == {"slug": "abandon-de-poste-quels-risques", "category": "ressource", "published": "2025-01-13"}
    assert post_to_row({"slug": "", "categoryIds": []}) is None
    assert post_to_row({"slug": "x"})["category"] == "classique"


def test_article_published_after_last_manual_sync_is_in_the_list():
    # e-06 : histoire-artan (publié 18/08) manquait de page_taxonomy le 02/09 — la liste publiée le porte.
    slugs = {r["slug"] for r in parse_fixture(FIXTURE.read_text(encoding="utf-8"))}
    assert "histoire-artan-engagement-grands-traumatises" in slugs
