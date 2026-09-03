#!/usr/bin/env python3
"""T-15 (mission 02/09/2026, #116) — synchro page_taxonomy ← liste PUBLIÉE du blog Wix.

La catégorie Wix Blog (« ressource » / « classique ») n'existait dans page_taxonomy que si
quelqu'un rejouait la synchro à la main via le MCP Wix ; les mécanismes automatiques ne
regardaient que les paths déjà vus dans events_human. Un article publié mais pas encore visité
n'avait aucune ligne (5 ressources invisibles deux mois durant, migration 20260831090540 ; rechute
dès le 31/08). Ici la source de vérité est la liste publiée de l'API Wix, pas le trafic.

Le script ne calcule rien : il lit l'API et passe la liste à la RPC SQL
`page_taxonomy_sync_wix(jsonb)` (SECURITY DEFINER, service_role), qui insère les paths manquants
avec la catégorie et le thème (même heuristique de slug que refresh_page_taxonomy_heuristic —
une seule implémentation, en SQL), met à jour `category` seule sur les lignes existantes et
compte les paths de la table absents de la liste (dépubliés / re-sluggés : jamais supprimés).

Env : WIX_API_KEY (clé API compte Wix, permission Blog lecture), WIX_SITE_ID
      (défaut : site Cabinet Plouton), SUPABASE_SECRET_KEY, SUPABASE_URL (défaut prod).
Usage :
  python3 scripts/wix_taxonomy_sync.py                       # API Wix → RPC
  python3 scripts/wix_taxonomy_sync.py --dry-run             # API Wix → affiche le diff (RPC en mode dry)
  python3 scripts/wix_taxonomy_sync.py --from-file tests/fixtures/wix_blog_posts_2026-09-03.txt --dry-run
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

WIX_SITE_ID_DEFAULT = "0870235c-b92d-4a69-a2f4-25a976ae5f0c"
RESSOURCE_CATEGORY_ID = "9477320f-5902-40e9-ace3-b0e3b6b8b51f"
WIX_POSTS_URL = "https://www.wixapis.com/blog/v3/posts"
PAGE = 100


def post_to_row(post: dict) -> dict | None:
    """Un post publié de l'API → {slug, category, published}. None si pas de slug."""
    slug = (post.get("slug") or "").strip()
    if not slug:
        return None
    cats = post.get("categoryIds") or []
    return {
        "slug": slug,
        "category": "ressource" if RESSOURCE_CATEGORY_ID in cats else "classique",
        "published": (post.get("firstPublishedDate") or "")[:10] or None,
    }


def parse_fixture(text: str) -> list[dict]:
    """Format `slug|r|YYYY-MM-DD` (r = ressource, c = classique), lignes `#` ignorées."""
    rows: list[dict] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        slug, flag, *rest = line.split("|")
        rows.append({
            "slug": slug,
            "category": "ressource" if flag == "r" else "classique",
            "published": rest[0] if rest and rest[0] else None,
        })
    return rows


def fetch_published_posts(api_key: str, site_id: str) -> list[dict]:
    import requests  # type: ignore

    headers = {"Authorization": api_key, "wix-site-id": site_id}
    rows: list[dict] = []
    offset = 0
    while True:
        r = requests.get(
            WIX_POSTS_URL,
            headers=headers,
            params={"paging.limit": PAGE, "paging.offset": offset},
            timeout=60,
        )
        r.raise_for_status()
        posts = r.json().get("posts") or []
        rows.extend(row for row in (post_to_row(p) for p in posts) if row)
        if len(posts) < PAGE:
            break
        offset += PAGE
    return rows


def call_sync_rpc(rows: list[dict], dry_run: bool) -> dict:
    import requests  # type: ignore

    url = os.environ.get("SUPABASE_URL", "https://mxycmjkeotrycyneacje.supabase.co").rstrip("/")
    key = os.environ["SUPABASE_SECRET_KEY"]
    r = requests.post(
        f"{url}/rest/v1/rpc/page_taxonomy_sync_wix",
        headers={"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        data=json.dumps({"p_posts": rows, "p_dry_run": dry_run}, ensure_ascii=False).encode("utf-8"),
        timeout=120,
    )
    r.raise_for_status()
    data = r.json()
    return data[0] if isinstance(data, list) else data


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from-file", help="fixture slug|r|date au lieu de l'API Wix")
    ap.add_argument("--dry-run", action="store_true", help="n'écrit rien, affiche le diff")
    args = ap.parse_args(argv)

    if args.from_file:
        rows = parse_fixture(Path(args.from_file).read_text(encoding="utf-8"))
        source = args.from_file
    else:
        api_key = os.environ.get("WIX_API_KEY", "").strip()
        if not api_key:
            print("WIX_API_KEY absent — rien à faire (le registre freshness_contract.page_taxonomy sonne "
                  "après 21 j sans synchro).", file=sys.stderr)
            return 2
        rows = fetch_published_posts(api_key, os.environ.get("WIX_SITE_ID", WIX_SITE_ID_DEFAULT))
        source = "API Wix"
    if len(rows) < 300:
        print(f"liste suspecte : {len(rows)} posts (< 300) — abandon, rien n'est écrit", file=sys.stderr)
        return 1

    res = call_sync_rpc(rows, args.dry_run)
    mode = "DRY-RUN" if args.dry_run else "SYNC"
    print(f"[{mode}] source={source} posts={len(rows)} ressources={sum(r['category']=='ressource' for r in rows)}")
    print(f"  insérés   : {res.get('inserted')}  {res.get('inserted_paths') or ''}")
    print(f"  catégorie corrigée : {res.get('updated')}  {res.get('updated_paths') or ''}")
    print(f"  en base mais dépubliés (conservés) : {res.get('unpublished')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
