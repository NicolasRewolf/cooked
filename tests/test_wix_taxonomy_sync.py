"""Inventaire publié complet Wix : sources, pagination et livraison atomique."""
import json
from types import SimpleNamespace

import pytest

from cooked.wix import taxonomy
from cooked.wix.taxonomy import RESSOURCE_CATEGORY_ID


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


def test_pagination_includes_articles_beyond_the_first_hundred():
    posts = [{'id': str(i)} for i in range(205)]
    offsets = []
    def get_page(url, **kwargs):
        offset, limit = kwargs['params']['paging.offset'], kwargs['params']['paging.limit']
        offsets.append(offset)
        page = posts[offset:offset + limit]
        return Response({'posts': page, 'metaData': {'count': len(page), 'offset': offset, 'total': len(posts)}})
    assert taxonomy.collection(SimpleNamespace(get=get_page), taxonomy.WIX_POSTS_URL, 'ephemeral', 'posts') == posts
    assert offsets == [0, 100, 200]


def test_sitemap_reads_every_child_and_rejects_an_incomplete_child():
    base = taxonomy.SITE_URL
    documents = {
        base + '/sitemap.xml': f'<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
        f'<sitemap><loc>{base}/pages-sitemap.xml</loc></sitemap>'
        f'<sitemap><loc>{base}/blog-posts-sitemap.xml</loc></sitemap></sitemapindex>',
        base + '/pages-sitemap.xml': f'<urlset><url><loc>{base}/</loc></url></urlset>',
        base + '/blog-posts-sitemap.xml': f'<urlset><url><loc>{base}/post/nouvel-article</loc></url></urlset>',
    }
    class SitemapResponse(Response):
        def __init__(self, url):
            self.content = documents[url].encode()
    session = SimpleNamespace(get=lambda url, **kwargs: SitemapResponse(url))
    assert taxonomy.published_sitemap(session) == {'/', '/post/nouvel-article'}
    documents[base + '/blog-posts-sitemap.xml'] = '<urlset/>'
    with pytest.raises(ValueError):
        taxonomy.published_sitemap(session)


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
                           'url': {'base': taxonomy.SITE_URL, 'path': '/post/nouvel-article'}},
                          {'slug': 'article-hors-sitemap',
                           'url': {'base': taxonomy.SITE_URL, 'path': '/post/article-hors-sitemap'}}],
                'categories': [{'url': {'base': taxonomy.SITE_URL, 'path': '/blog/categories/penal'}}]}
    monkeypatch.setattr(taxonomy, 'collection', lambda session, url, token, name: entities[name])
    sitemap = {'/', '/post/nouvel-article', '/blog/categories/penal'}
    monkeypatch.setattr(taxonomy, 'published_sitemap', lambda session: sitemap)
    verified = []
    monkeypatch.setattr(taxonomy, 'verify_unlisted', verified.append)
    result = taxonomy.fetch_inventory()
    assert result['counts'] == {'posts': 2, 'categories': 1, 'static': 2}
    assert len(result['pages']) == 5
    assert sorted(verified) == ['/post/article-hors-sitemap', '/suivi-de-dossier']
    assert {row['path']: row['category'] for row in result['pages'] if row['path'].startswith('/post/')} == {
        '/post/nouvel-article': 'ressource', '/post/article-hors-sitemap': 'classique',
    }
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


def test_from_file_accepts_only_a_complete_inventory_object(tmp_path, monkeypatch):
    inventory = {
        'observed_at': '2026-11-04T06:00:00Z',
        'counts': {'posts': 1, 'categories': 1, 'static': 1},
        'pages': [{'path': '/', 'category': None},
                  {'path': '/blog/categories/penal', 'category': None},
                  {'path': '/post/nouvel-article', 'category': 'classique'}],
    }
    source = tmp_path / 'inventory.json'
    source.write_text(json.dumps(inventory), encoding='utf-8')
    calls = []
    def rpc(payload, dry):
        calls.append((payload, dry))
        return {'inserted': 0, 'updated': 0, 'unpublished': 0}
    monkeypatch.setattr(taxonomy, 'call_sync_rpc', rpc)
    assert taxonomy.main(['--from-file', str(source), '--dry-run']) == 0
    assert calls == [(inventory, True)]
    for legacy in [json.dumps([{'slug': 'article', 'category': 'classique'}]), 'article|r|2026-11-04', 'null']:
        source.write_text(legacy, encoding='utf-8')
        assert taxonomy.main(['--from-file', str(source)]) == 1
    assert calls == [(inventory, True)], 'legacy input is rejected before any RPC'


@pytest.mark.parametrize('url,source,status,rpc_failure', [
    (taxonomy.WIX_POSTS_URL + '?token=private-token', 'api-blog-wix', 403, False),
    (taxonomy.SITE_URL + '/_api/v1/access-tokens?token=private-token', 'site-public-wix', 429, False),
    ('https://mxycmjkeotrycyneacje.supabase.co/rest/v1/rpc/page_taxonomy_sync_wix?token=private-token',
     'rpc-supabase', 401, True),
    ('https://private-token.invalid/path', 'source-inconnue', 500, False),
])
def test_http_failure_identifies_source_without_exposing_credentials(
        monkeypatch, capsys, url, source, status, rpc_failure):
    response = taxonomy.requests.Response()
    response.status_code = status
    response.url = url
    response._content = b'private response body with private-token'
    error = taxonomy.requests.HTTPError('private exception with private-token', response=response)
    def fail(*args):
        raise error
    calls = []
    monkeypatch.delenv('SUPABASE_URL', raising=False)
    monkeypatch.setattr(taxonomy, 'fetch_inventory', lambda: {} if rpc_failure else fail())
    monkeypatch.setattr(taxonomy, 'call_sync_rpc', fail if rpc_failure else lambda *args: calls.append(args))
    assert taxonomy.main([]) == 1
    assert calls == []
    output = capsys.readouterr()
    phase = 'synchronisation-supabase' if rpc_failure else 'lecture-inventaire'
    assert output.out == ''
    assert output.err == (f'Inventaire Wix non appliqué (HTTPError; phase={phase}; '
                          f'source={source}; HTTP={status}).\n')
