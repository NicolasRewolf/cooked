"""
Shared DataForSEO → Supabase ingest (keyword volume + CPC).

Aligné sur le pattern scripts/gsc_common.py : env vars, client singleton,
upsert batch. Source de keywords à syncer = RPC dfs_keywords_to_sync(N)
qui lit les top par clics GSC 90j.

API DataForSEO : Google Ads search_volume live (Keywords Data endpoint).
Retourne : search_volume (moy 12 mois), cpc, competition, competition_level,
monthly_searches (12 mois historique).
Tarification : ~$0.075 par 1000 keywords (donc ~$0.04 par run de 500).
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from datetime import datetime, timezone
from typing import Sequence

import requests
from supabase import create_client


DEFAULT_SUPABASE_URL = "https://mxycmjkeotrycyneacje.supabase.co"
DFS_API_BASE         = "https://api.dataforseo.com/v3"
DFS_ENDPOINT         = "/keywords_data/google_ads/search_volume/live"
LOCATION_CODE_FR     = 2250  # France entière
LANGUAGE_CODE_FR     = "fr"
BATCH_SIZE_DFS       = 200    # API limite à 1000 keywords par tâche, mais 200 = sweet spot pour la latence
BATCH_SIZE_UPSERT    = 500


def clients() -> tuple:
    supabase_url = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE_URL)
    supabase_key = os.environ.get("SUPABASE_SECRET_KEY")
    if not supabase_key:
        sys.exit("ERROR: SUPABASE_SECRET_KEY env var manquante")

    dfs_username = os.environ.get("DFS_USERNAME")
    dfs_password = os.environ.get("DFS_PASSWORD")
    if not dfs_username or not dfs_password:
        sys.exit("ERROR: DFS_USERNAME et DFS_PASSWORD env vars manquantes")

    sb = create_client(supabase_url, supabase_key)
    dfs_auth = base64.b64encode(f"{dfs_username}:{dfs_password}".encode()).decode()
    return sb, dfs_auth


def fetch_keywords_to_sync(sb, limit_n: int) -> list[str]:
    """Lit les top N keywords par clics GSC 90j via RPC publiée."""
    resp = sb.rpc("dfs_keywords_to_sync", {"limit_n": limit_n}).execute()
    rows = resp.data or []
    return [r["keyword"] for r in rows]


def fetch_dfs_search_volume(dfs_auth: str, keywords: Sequence[str]) -> list[dict]:
    """Appel DataForSEO Google Ads search_volume pour 1 batch de keywords."""
    url = DFS_API_BASE + DFS_ENDPOINT
    headers = {
        "Authorization": f"Basic {dfs_auth}",
        "Content-Type": "application/json",
    }
    body = [{
        "keywords": list(keywords),
        "location_code": LOCATION_CODE_FR,
        "language_code": LANGUAGE_CODE_FR,
        "search_partners": False,  # uniquement Google.fr, pas les partners
    }]
    r = requests.post(url, headers=headers, json=body, timeout=60)
    r.raise_for_status()
    data = r.json()
    if data.get("status_code") != 20000:
        sys.exit(f"ERROR DFS API: {data.get('status_message')} (code {data.get('status_code')})")
    tasks = data.get("tasks") or []
    if not tasks or tasks[0].get("status_code") != 20000:
        msg = tasks[0].get("status_message") if tasks else "no tasks"
        sys.exit(f"ERROR DFS task: {msg}")
    return tasks[0].get("result") or []


def transform_dfs_result(items: list[dict]) -> list[dict]:
    """Transforme les rows DFS en rows pour upsert dans dfs_keyword_volume.

    Mapping DFS → table (attention au piège du naming croisé) :
      DFS `competition`        = label "LOW" / "MEDIUM" / "HIGH"   → col `competition_level` (text)
      DFS `competition_index`  = score 0–100                         → col `competition` (numeric 0.000–1.000)
    """
    now_iso = datetime.now(timezone.utc).isoformat()
    rows = []
    for item in items:
        keyword = item.get("keyword")
        if not keyword:
            continue
        comp_index = item.get("competition_index")
        comp_numeric = round(comp_index / 100.0, 3) if comp_index is not None else None
        rows.append({
            "keyword": keyword,
            "location_code": LOCATION_CODE_FR,
            "language_code": LANGUAGE_CODE_FR,
            "search_volume": item.get("search_volume"),
            "cpc": item.get("cpc"),
            "competition": comp_numeric,
            "competition_level": item.get("competition"),
            "monthly_searches": item.get("monthly_searches"),
            "last_synced_at": now_iso,
        })
    return rows


def upsert_batch(sb, rows: list[dict]) -> None:
    """Upsert en batch dans dfs_keyword_volume. last_synced_at est inclus
    en ISO timestamp côté Python → le ON CONFLICT UPDATE le rafraîchit."""
    if not rows:
        return
    for i in range(0, len(rows), BATCH_SIZE_UPSERT):
        chunk = rows[i:i + BATCH_SIZE_UPSERT]
        sb.table("dfs_keyword_volume") \
          .upsert(chunk, on_conflict="keyword,location_code") \
          .execute()


def run_sync(limit_n: int) -> None:
    sb, dfs_auth = clients()
    t0 = time.time()

    print(f"=== DFS sync — top {limit_n} keywords GSC 90j → France ===", flush=True)

    keywords = fetch_keywords_to_sync(sb, limit_n)
    if not keywords:
        sys.exit("Aucun keyword à syncer (gsc_query_daily vide sur 90j ?)")

    print(f"  {len(keywords)} keywords à syncer", flush=True)

    total_upserted = 0
    total_with_volume = 0
    for i in range(0, len(keywords), BATCH_SIZE_DFS):
        batch = keywords[i:i + BATCH_SIZE_DFS]
        t_start = time.time()
        items = fetch_dfs_search_volume(dfs_auth, batch)
        rows = transform_dfs_result(items)
        upsert_batch(sb, rows)

        elapsed = time.time() - t_start
        with_vol = sum(1 for r in rows if r.get("search_volume") is not None)
        total_upserted += len(rows)
        total_with_volume += with_vol
        print(
            f"  batch {i // BATCH_SIZE_DFS + 1}: "
            f"{len(batch):>4} requested → {len(rows):>4} returned "
            f"({with_vol:>4} with volume), {elapsed:.1f}s",
            flush=True,
        )

    print(f"\n=== DONE en {time.time() - t0:.1f}s ===")
    print(f"  upserts : {total_upserted:,}")
    print(f"  avec volume non-null : {total_with_volume:,} ({100 * total_with_volume / total_upserted:.1f}%)")
    print(f"  long-tail null : {total_upserted - total_with_volume:,}")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Sync DataForSEO Google Ads search_volume → Supabase dfs_keyword_volume"
    )
    parser.add_argument(
        "--limit", type=int, default=500,
        help="Top N keywords par clics GSC 90j (défaut: 500)"
    )
    args = parser.parse_args(argv)
    run_sync(args.limit)


if __name__ == "__main__":
    main()
