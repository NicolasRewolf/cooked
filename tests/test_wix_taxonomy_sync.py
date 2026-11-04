"""T-15 — parse de la liste publiée Wix → lignes pour page_taxonomy_sync_wix."""
from pathlib import Path

from cooked.wix.taxonomy import RESSOURCE_CATEGORY_ID, parse_fixture, post_to_row

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


# Completeness is the publication contract: a missing supplier page must never
# become evidence of unpublication. These fixtures exercise the normal CLI path.
import json
from types import SimpleNamespace

import pytest

from cooked.wix import taxonomy


class Response:
    def __init__(self, value):
        self.value = value

    def raise_for_status(self):
        pass

    def json(self):
        return self.value


def test_pagination_requires_a_stable_total_and_distinct_ids():
    def run(pages):
        iterator = iter(pages)
        return taxonomy.collection(SimpleNamespace(get=lambda *a, **kw: Response(next(iterator))),
                                   taxonomy.WIX_POSTS_URL, 'ephemeral-token', 'posts')

    first = {'posts': [{'id': 'a'}], 'metaData': {'count': 1, 'offset': 0, 'total': 2}}
    assert len(run([first, {'posts': [{'id': 'b'}], 'metaData': {'count': 1, 'offset': 1, 'total': 2}}])) == 2
    for second in [
        {'posts': [], 'metaData': {'count': 0, 'offset': 1, 'total': 2}},
        {'posts': [{'id': 'a'}], 'metaData': {'count': 1, 'offset': 1, 'total': 2}},
        {'posts': [{'id': 'b'}], 'metaData': {'count': 1, 'offset': 1, 'total': 3}},
        {'posts': [{'id': 'b'}], 'metaData': {'count': 1, 'offset': 0, 'total': 2}},
    ]:
        with pytest.raises(ValueError):
            run([first, second])
    with pytest.raises(KeyError):
        run([{'posts': []}])


def test_inventory_checks_hidden_pages_and_preserves_zero_traffic(monkeypatch):
    router = {
        'mainPageId': 'home', 'customNotFoundPage': {'pageId': '404'},
        'pagesMap': {p: {'pageUriSEO': slug} for p, slug in
                     [('home', 'home'), ('404', 'error404'), ('popup', 'popup-x'), ('post', 'post'), ('hidden', 'suivi-de-dossier')]},
        'routes': {route: {'type': 'Static', 'pageId': page} for route, page in
                   [('./', 'home'), ('./home', 'home'), ('./error404', '404'), ('./popup-x', 'popup'), ('./post', 'post'), ('./suivi-de-dossier', 'hidden')]},
    }
    model = {'accessTokensUrl': taxonomy.SITE_URL + '/_api/v1/access-tokens',
             'siteFeaturesConfigs': {'router': router}}
    assert taxonomy.static_paths(model) == {'/', '/suivi-de-dossier'}
    text = '<script id="wix-viewer-model" type="application/json">' + json.dumps(model) + '</script>'
    credentials = {'metaSiteId': taxonomy.WIX_SITE_ID_DEFAULT,
                   'apps': {taxonomy.WIX_BLOG_APP: {'accessToken': 'ephemeral'}}}
    monkeypatch.setattr(taxonomy, 'get', lambda session, url, **kw:
                        SimpleNamespace(text=text) if url == taxonomy.SITE_URL else Response(credentials))
    entities = {'posts': [{'slug': 'nouvel-article', 'categoryIds': [RESSOURCE_CATEGORY_ID],
                           'url': {'base': taxonomy.SITE_URL, 'path': '/post/nouvel-article'}}],
                'categories': [{'url': {'base': taxonomy.SITE_URL, 'path': '/blog/categories/penal'}}]}
    monkeypatch.setattr(taxonomy, 'collection', lambda session, url, token, name: entities[name])
    sitemap = {'/', '/post/nouvel-article', '/blog/categories/penal'}
    monkeypatch.setattr(taxonomy, 'published_sitemap', lambda session: sitemap)
    verified = []
    monkeypatch.setattr(taxonomy, 'verify_unlisted', verified.append)
    result = taxonomy.fetch_inventory()
    assert result['counts'] == {'posts': 1, 'categories': 1, 'static': 2}
    assert len(result['pages']) == 4
    assert verified == ['/suivi-de-dossier']
    assert result['pages'][-1] == {'path': '/suivi-de-dossier', 'category': None}

    called = []
    monkeypatch.setattr(taxonomy, 'call_sync_rpc', lambda *args: called.append(args))
    sitemap.add('/a-new-unsupported-page-family')
    assert taxonomy.main([]) == 1
    assert called == []
    sitemap.remove('/a-new-unsupported-page-family')
    monkeypatch.setattr(taxonomy, 'verify_unlisted', lambda path: (_ for _ in ()).throw(ValueError('404')))
    assert taxonomy.main([]) == 1
    assert called == []


def test_public_routes_and_urls_fail_closed():
    for value in ['https://elsewhere.fr/page', 'https://www.jplouton-avocat.fr/x?q=1',
                  'https://www.jplouton-avocat.fr/x#y', '//www.jplouton-avocat.fr/']:
        with pytest.raises(ValueError):
            taxonomy.page_path(value)
    assert taxonomy.page_path(taxonomy.SITE_URL + '/post/caf%C3%A9/') == '/post/café'


def test_cli_dry_run_passes_full_inventory_without_hiding_failure(monkeypatch):
    inventory = {'pages': [], 'observed_at': '2026-11-04T06:00:00Z', 'counts': {}}
    calls = []
    monkeypatch.setattr(taxonomy, 'fetch_inventory', lambda: inventory)
    def rpc(payload, dry):
        calls.append((payload, dry))
        return {'inserted': 0, 'updated': 0, 'unpublished': 0}
    monkeypatch.setattr(taxonomy, 'call_sync_rpc', rpc)
    assert taxonomy.main(['--dry-run']) == 0
    assert calls == [(inventory, True)]
    monkeypatch.setattr(taxonomy, 'fetch_inventory', lambda: (_ for _ in ()).throw(TimeoutError()))
    assert taxonomy.main([]) == 1
    assert len(calls) == 1
