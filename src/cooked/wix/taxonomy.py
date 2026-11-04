#!/usr/bin/env python3
"""Synchronise l'inventaire publié Wix dans page_taxonomy, indépendamment du trafic.

Une lecture complète réunit routes publiées, articles et catégories, puis confronte
ces URLs au sitemap. Les pages hors sitemap sont vérifiées sur le site publié.
Une seule RPC applique l'inventaire complet. Aucun état de publication ne change
si une lecture ou sa validation échoue. Le même inventaire JSON complet peut
être fourni avec --from-file.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

import requests

from cooked.path import canonical_path

WIX_SITE_ID_DEFAULT = "0870235c-b92d-4a69-a2f4-25a976ae5f0c"
RESSOURCE_CATEGORY_ID = "9477320f-5902-40e9-ace3-b0e3b6b8b51f"
WIX_BLOG_APP = "14bca956-e09f-f4d6-14d7-466cb3f09103"
SITE_URL = "https://www.jplouton-avocat.fr"
WIX_POSTS_URL = "https://www.wixapis.com/blog/v3/posts"
WIX_CATEGORIES_URL = "https://www.wixapis.com/blog/v3/categories"
PAGE = 100


class PublishedPage(HTMLParser):
    """Read only the published routing metadata and canonical URL."""

    def __init__(self, html: str):
        super().__init__()
        self.model_text: list[str] = []
        self.in_model = False
        self.canonical = None
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "script" and attributes.get("id") == "wix-viewer-model":
            self.in_model = True
        if tag == "link" and attributes.get("rel") == "canonical":
            self.canonical = attributes.get("href")

    def handle_data(self, data):
        if self.in_model:
            self.model_text.append(data)

    def handle_endtag(self, tag):
        if tag == "script":
            self.in_model = False

    def model(self) -> dict:
        return json.loads("".join(self.model_text))


def page_path(url: str) -> str:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.netloc != urlsplit(SITE_URL).netloc:
        raise ValueError("URL d'inventaire hors du site")
    if parsed.query or parsed.fragment:
        raise ValueError("URL d'inventaire avec paramètres")
    return canonical_path(parsed.path)


def get(session, url, **kwargs):
    response = session.get(url, timeout=45, **kwargs)
    response.raise_for_status()
    return response


def collection(session, url: str, token: str, name: str) -> list[dict]:
    """Reject missing pages, changed totals and repeated identities before any RPC."""
    rows: list[dict] = []
    seen = set()
    total = None
    for _ in range(100):
        data = get(session, url, headers={"Authorization": token}, params={
            "paging.limit": PAGE, "paging.offset": len(rows), "fieldsets": "URL",
        }).json()
        items, meta = data[name], data["metaData"]
        if not isinstance(items, list) or type(meta["total"]) is not int:
            raise ValueError("Réponse Wix invalide")
        if total is None:
            total = meta["total"]
        if meta["total"] != total or meta["offset"] != len(rows) or meta["count"] != len(items):
            raise ValueError("Pagination Wix incohérente")
        for item in items:
            identity = item["id"]
            if not identity or identity in seen:
                raise ValueError("Identité Wix absente ou répétée")
            seen.add(identity)
        rows.extend(items)
        if len(rows) == total:
            return rows
        if not items or len(rows) > total:
            raise ValueError("Pagination Wix interrompue")
    raise ValueError("Pagination Wix trop longue")


def published_sitemap(session) -> set[str]:
    index = ET.fromstring(get(session, SITE_URL + "/sitemap.xml").content)
    children = index.findall("{*}sitemap/{*}loc")
    if not children:
        raise ValueError("Index sitemap absent")
    paths = set()
    for child in children:
        url = child.text or ""
        page_path(url)  # same origin before the server fetches a URL from XML
        document = ET.fromstring(get(session, url).content)
        entries = document.findall("{*}url/{*}loc")
        if not entries:
            raise ValueError("Sitemap vide ou invalide")
        paths.update(page_path(entry.text or "") for entry in entries)
    return paths


def static_paths(model: dict) -> set[str]:
    router = model["siteFeaturesConfigs"]["router"]
    pages, routes = router["pagesMap"], router["routes"]
    result = set()
    for route, target in routes.items():
        if target["type"] != "Static" or not route.startswith("./"):
            raise ValueError("Famille de routes Wix inconnue")
        page_id = target["pageId"]
        page = pages[page_id]
        if page_id == router["customNotFoundPage"]["pageId"]:
            continue
        # Wix exposes lightboxes and the empty Blog post template as routes.
        # Both were verified on the published site; they are not content pages.
        if page["pageUriSEO"].startswith("popup-") or page["pageUriSEO"] == "post":
            continue
        path = page_path(SITE_URL + route[1:])
        if page_id == router["mainPageId"]:
            path = "/"
        result.add(path)
    if "/" not in result:
        raise ValueError("Accueil absent des routes publiées")
    return result


def verify_unlisted(path: str) -> None:
    response = get(requests, SITE_URL + path)
    page = PublishedPage(response.text)
    model = page.model()
    features = model["siteFeaturesConfigs"]
    if features["pagesService"]["currentPageId"] == features["router"]["customNotFoundPage"]["pageId"]:
        raise ValueError("Route hors sitemap rendue en erreur")
    if not page.canonical or page_path(page.canonical) != path:
        raise ValueError("Route hors sitemap sans URL canonique correspondante")


def fetch_inventory() -> dict:
    # This is when observation begins. An overlapping older run cannot overwrite
    # a newer completed observation in the RPC.
    observed_at = datetime.now(timezone.utc).isoformat()
    with requests.Session() as session:
        model = PublishedPage(get(session, SITE_URL).text).model()
        token_url = model["accessTokensUrl"]
        if token_url != SITE_URL + "/_api/v1/access-tokens":
            raise ValueError("Source de session publique Wix inconnue")
        credentials = get(session, token_url).json()
        if credentials["metaSiteId"] != WIX_SITE_ID_DEFAULT:
            raise ValueError("Site Wix inattendu")
        token = credentials["apps"][WIX_BLOG_APP]["accessToken"]
        posts = collection(session, WIX_POSTS_URL, token, "posts")
        categories = collection(session, WIX_CATEGORIES_URL, token, "categories")
        static = static_paths(model)
        sitemap = published_sitemap(session)

    rows = [{"path": path, "category": None} for path in static]
    for post in posts:
        if not (post.get("slug") or "").strip():
            raise ValueError("Article publié sans slug")
        path = page_path(post["url"]["base"] + post["url"]["path"])
        if path != canonical_path("/post/" + post["slug"]):
            raise ValueError("URL Wix Blog inattendue")
        rows.append({"path": path, "category":
                     "ressource" if RESSOURCE_CATEGORY_ID in (post.get("categoryIds") or []) else "classique"})
    for category in categories:
        path = page_path(category["url"]["base"] + category["url"]["path"])
        if not path.startswith("/blog/categories/"):
            raise ValueError("URL de catégorie Wix inattendue")
        rows.append({"path": path, "category": None})
    paths = {row["path"] for row in rows}
    if len(paths) != len(rows) or not posts or not categories or not sitemap.issubset(paths):
        raise ValueError("Inventaire incomplet ou chemins répétés")
    # noindex pages are published too. Validate them independently instead of
    # treating absence from a sitemap as evidence of unpublication.
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(verify_unlisted, sorted(paths - sitemap)))
    return {"pages": sorted(rows, key=lambda row: row["path"]), "observed_at": observed_at,
            "counts": {"posts": len(posts), "categories": len(categories), "static": len(static)}}


def call_sync_rpc(inventory: dict, dry_run: bool) -> dict:
    url = os.environ.get("SUPABASE_URL", "https://mxycmjkeotrycyneacje.supabase.co").rstrip("/")
    key = os.environ["SUPABASE_SECRET_KEY"]
    response = requests.post(
        f"{url}/rest/v1/rpc/page_taxonomy_sync_wix",
        headers={"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        json={"p_posts": inventory, "p_dry_run": dry_run}, timeout=120,
    )
    response.raise_for_status()
    data = response.json()
    return data[0] if isinstance(data, list) else data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--from-file", help="inventaire JSON complet (pages, observed_at, counts)")
    parser.add_argument("--dry-run", action="store_true", help="valide et compare sans écriture")
    args = parser.parse_args(argv)
    phase = "lecture-inventaire"
    try:
        if args.from_file:
            inventory = json.loads(Path(args.from_file).read_text(encoding="utf-8"))
            if not isinstance(inventory, dict):
                raise ValueError("Un inventaire JSON complet est requis")
        else:
            inventory = fetch_inventory()
        phase = "synchronisation-supabase"
        result = call_sync_rpc(inventory, args.dry_run)
        print(json.dumps({"dry_run": args.dry_run, "complete_inventory": True,
                          "inserted": result["inserted"], "categories_updated": result["updated"],
                          "absent": result["unpublished"]}, ensure_ascii=False))
        return 0
    except requests.HTTPError as error:
        response = error.response
        host = urlsplit(response.url or "").hostname if response is not None else None
        source = {
            urlsplit(SITE_URL).hostname: "site-public-wix",
            urlsplit(WIX_POSTS_URL).hostname: "api-blog-wix",
            urlsplit(os.environ.get("SUPABASE_URL", "https://mxycmjkeotrycyneacje.supabase.co")).hostname: "rpc-supabase",
        }.get(host, "source-inconnue")
        status = response.status_code if response is not None else "inconnu"
        # Fixed source labels and numeric HTTP status only: never emit the
        # exception, response body, request URL, credentials or headers.
        print(f"Inventaire Wix non appliqué (HTTPError; phase={phase}; source={source}; HTTP={status}).",
              file=sys.stderr)
        return 1
    except Exception as error:
        # HTTP exception bodies can contain tokens or user data. Emit only type.
        print(f"Inventaire Wix non appliqué ({type(error).__name__}).", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
