"""
Shared DataForSEO → Supabase ingest (keyword volume + CPC).

Aligné sur le pattern cooked.gsc : env vars, client singleton,
upsert batch. Source de keywords à syncer = RPC dfs_keywords_to_sync(N)
(union top clics GSC 28j ∪ 90j).

API DataForSEO : Google Ads search_volume live (Keywords Data endpoint).
Retourne : search_volume (moy 12 mois), cpc, competition, competition_level,
monthly_searches (12 mois historique).
Tarification : ~$0.075 par 1000 keywords (donc ~$0.04 par run de 500).
"""
from __future__ import annotations

import argparse
import base64
import os
import re
import sys
import time
import unicodedata
from datetime import datetime, timezone
from typing import Sequence

import requests
from cooked.store import CookedStore, SupabaseStore


DFS_API_BASE         = "https://api.dataforseo.com/v3"
DFS_ENDPOINT         = "/keywords_data/google_ads/search_volume/live"
LOCATION_CODE_FR     = 2250  # France entière
LANGUAGE_CODE_FR     = "fr"
BATCH_SIZE_DFS       = 200    # API limite à 1000 keywords par tâche, mais 200 = sweet spot pour la latence
BATCH_SIZE_UPSERT    = 500


# DataForSEO rejette les caractères "smart" Unicode (em dash, smart quotes…).
# Sortie typique en cas d'envoi d'un keyword problématique :
#   "Invalid Field: 'keywords'. Keyword text has invalid characters or symbols: '…'"
# Et le batch ENTIER est rejeté → on assainit avant envoi.
_DFS_TRANSLATIONS = str.maketrans({
    "—": "-",  # — em dash
    "–": "-",  # – en dash
    "−": "-",  # − minus sign
    "‒": "-",  # ‒ figure dash
    "‐": "-",  # ‐ hyphen
    "‘": "'",  # ' left single quote
    "’": "'",  # ' right single quote
    "“": '"',  # " left double quote
    "”": '"',  # " right double quote
    "…": "...",  # …
    " ": " ",  # non-breaking space
    "​": "",   # zero-width space
    "﻿": "",   # BOM
})

# Ponctuation que DFS rejette : on remplace par espace pour préserver la
# séparation des tokens (ex: "abc(def)" → "abc def", pas "abcdef").
# Observé sur le run 24/05/2026 : parens, brackets, &, %, +, :, ?, ! etc.
_DFS_STRIP = str.maketrans({c: " " for c in '()[]{}&%+:?!@#"*=<>|^~`;\\'})

# Charset jugé sûr APRES sanitization : lettres Unicode, chiffres, espace,
# apostrophe, hyphen, point, virgule. Liste minimale acceptée par Google Ads.
_DFS_SAFE_RE = re.compile(r"^[\w\s'.,\-]+$", re.UNICODE)


class DfsApiError(Exception):
    """Erreur API DataForSEO (batch rejeté, mauvais creds, etc.)."""


def sanitize_for_dfs(kw: str) -> str | None:
    """Renvoie une variante DFS-safe de `kw`, ou None si non nettoyable.

    On garde l'idée de préserver la sémantique du keyword utilisateur tout en
    purgeant les caractères que DFS rejette. Si le keyword reste hors charset
    après normalisation, on le drop (perte du volume pour cette requête, mais
    le reste du batch passe).
    """
    if not kw:
        return None
    kw = unicodedata.normalize("NFC", kw)
    kw = kw.translate(_DFS_TRANSLATIONS)  # smart Unicode → ASCII équivalent
    kw = kw.translate(_DFS_STRIP)          # ponctuation rejetée → espace
    kw = " ".join(kw.split()).strip()
    if not kw:
        return None
    if not _DFS_SAFE_RE.match(kw):
        return None
    # DFS limite ~80 chars par keyword (au-delà → souvent rejet ou volume null)
    if len(kw) > 80:
        return None
    # DFS limite à ~10 mots par keyword. Observé sur run 24/05/2026 :
    #   "une garde a vue est elle inscrit dans le casier judiciaire" (11 mots) → rejet
    if len(kw.split()) > 10:
        return None
    return kw


def prepare_keywords_for_dfs(
    keywords: Sequence[str],
) -> tuple[list[str], dict[str, str], list[str], list[tuple[str, str]]]:
    """Assainit une liste GSC pour l'API DFS.

    Returns:
        clean_keywords: clés uniques envoyables à DFS
        original_by_sanitized: sanitized → keyword GSC d'origine (PK upsert)
        skipped_keywords: requêtes GSC droppées (sanitize impossible)
        collisions: paires (nouveau, existant) si 2 requêtes GSC → même sanitized
    """
    original_by_sanitized: dict[str, str] = {}
    collisions: list[tuple[str, str]] = []
    skipped_keywords: list[str] = []
    for kw in keywords:
        s = sanitize_for_dfs(kw)
        if s is None:
            skipped_keywords.append(kw)
            continue
        prev = original_by_sanitized.get(s)
        if prev is not None and prev != kw:
            collisions.append((kw, prev))
            continue
        original_by_sanitized.setdefault(s, kw)
    return list(original_by_sanitized.keys()), original_by_sanitized, skipped_keywords, collisions


def dfs_auth_from_env() -> str:
    dfs_username = os.environ.get("DFS_USERNAME")
    dfs_password = os.environ.get("DFS_PASSWORD")
    if not dfs_username or not dfs_password:
        sys.exit("ERROR: DFS_USERNAME et DFS_PASSWORD env vars manquantes")
    return base64.b64encode(f"{dfs_username}:{dfs_password}".encode()).decode()


def clients() -> tuple[CookedStore, str]:
    return SupabaseStore.from_env(), dfs_auth_from_env()


def fetch_keywords_to_sync(store: CookedStore, limit_n: int) -> list[str]:
    """Lit les top N keywords (union GSC 28j ∪ 90j) via RPC dfs_keywords_to_sync."""
    resp = store.rpc("dfs_keywords_to_sync", {"limit_n": limit_n})
    rows = resp.data or []
    return [r["keyword"] for r in rows]


def fetch_dfs_search_volume(dfs_auth: str, keywords: Sequence[str]) -> list[dict]:
    """Appel DataForSEO Google Ads search_volume pour 1 batch de keywords.

    Lève DfsApiError au lieu de sys.exit pour permettre au caller de skip
    le batch en cas d'erreur (résilience cron).
    """
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
        raise DfsApiError(
            f"DFS API status {data.get('status_code')}: {data.get('status_message')}"
        )
    tasks = data.get("tasks") or []
    if not tasks or tasks[0].get("status_code") != 20000:
        msg = tasks[0].get("status_message") if tasks else "no tasks"
        raise DfsApiError(f"DFS task: {msg}")
    return tasks[0].get("result") or []


def transform_dfs_result(
    items: list[dict],
    original_by_sanitized: dict[str, str] | None = None,
) -> list[dict]:
    """Transforme les rows DFS en rows pour upsert dans dfs_keyword_volume.

    `original_by_sanitized` permet de stocker le keyword ORIGINAL en PK même
    si on a envoyé une version sanitizée à DFS (préserve le JOIN avec
    gsc_query_daily où le texte est intact).

    Mapping DFS → table (attention au piège du naming croisé) :
      DFS `competition`        = label "LOW" / "MEDIUM" / "HIGH"   → col `competition_level` (text)
      DFS `competition_index`  = score 0–100                         → col `competition` (numeric 0.000–1.000)
    """
    now_iso = datetime.now(timezone.utc).isoformat()
    rows = []
    for item in items:
        sanitized = item.get("keyword")
        if not sanitized:
            continue
        # Recover original keyword (so PK matches GSC query text)
        keyword = (
            original_by_sanitized.get(sanitized, sanitized)
            if original_by_sanitized
            else sanitized
        )
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


def upsert_batch(store: CookedStore, rows: list[dict]) -> None:
    """Upsert en batch dans dfs_keyword_volume. last_synced_at est inclus
    en ISO timestamp côté Python → le ON CONFLICT UPDATE le rafraîchit."""
    store.upsert_batches(
        "dfs_keyword_volume",
        rows,
        "keyword,location_code",
        BATCH_SIZE_UPSERT,
    )


def dfs_run_failed(total_failed: int, total_requested: int) -> bool:
    """True si le run doit être considéré en échec : > 50 % des keywords
    demandés en erreur DFS. Extrait pour être testable unitairement
    (T-12, audit 02/07/2026)."""
    return bool(total_requested) and total_failed >= total_requested * 0.5


def run_sync(limit_n: int, store: CookedStore | None = None) -> None:
    store = store or SupabaseStore.from_env()
    dfs_auth = dfs_auth_from_env()
    t0 = time.time()

    print(f"=== DFS sync — top {limit_n} keywords GSC (28j∪90j) → France ===", flush=True)

    keywords = fetch_keywords_to_sync(store, limit_n)
    if not keywords:
        sys.exit("Aucun keyword à syncer (gsc_query_daily vide ?)")

    total_requested = len(keywords)
    print(f"  {total_requested} keywords à syncer", flush=True)

    total_upserted = 0
    total_with_volume = 0
    total_skipped = 0
    total_collisions = 0
    total_failed = 0

    for i in range(0, len(keywords), BATCH_SIZE_DFS):
        batch = keywords[i:i + BATCH_SIZE_DFS]
        batch_num = i // BATCH_SIZE_DFS + 1
        t_start = time.time()

        clean_batch, original_by_sanitized, skipped, collisions = (
            prepare_keywords_for_dfs(batch)
        )
        total_skipped += len(skipped)
        total_collisions += len(collisions)
        for kw in skipped:
            print(f"    SKIP (chars non DFS-safe): {kw!r}", flush=True)
        for new_kw, kept_kw in collisions:
            print(
                f"    COLLISION sanitize: {new_kw!r} → même clé que {kept_kw!r} (1er gardé)",
                flush=True,
            )
        if not clean_batch:
            continue

        # 2. Appel DFS. Si erreur API → on log et on continue au batch suivant
        #    (mieux vaut 80 % de volumes que rien du tout).
        try:
            items = fetch_dfs_search_volume(dfs_auth, clean_batch)
        except (DfsApiError, requests.RequestException) as e:
            total_failed += len(batch)
            print(
                f"  batch {batch_num}: FAIL ({e}) — skip {len(batch)} keywords demandés",
                flush=True,
            )
            continue

        rows = transform_dfs_result(items, original_by_sanitized)
        upsert_batch(store, rows)

        elapsed = time.time() - t_start
        with_vol = sum(1 for r in rows if r.get("search_volume") is not None)
        total_upserted += len(rows)
        total_with_volume += with_vol
        print(
            f"  batch {batch_num}: "
            f"{len(batch):>4} requested → {len(clean_batch):>4} sent → {len(rows):>4} returned "
            f"({with_vol:>4} with volume), {elapsed:.1f}s",
            flush=True,
        )

    elapsed_total = time.time() - t0
    print(f"\n=== DONE en {elapsed_total:.1f}s ===")
    print(f"  demandés (RPC)      : {total_requested:,}")
    print(f"  upserts             : {total_upserted:,}")
    if total_upserted:
        print(
            f"  avec volume non-null: {total_with_volume:,} "
            f"({100 * total_with_volume / total_upserted:.1f}%)"
        )
        print(f"  long-tail null      : {total_upserted - total_with_volume:,}")
    if total_skipped:
        print(f"  skipped (sanitize)  : {total_skipped:,}")
    if total_collisions:
        print(f"  collisions sanitize : {total_collisions:,}")
    if total_failed:
        print(f"  failed (DFS error)  : {total_failed:,}")

    # T-12 (audit 02/07/2026) : échec dur si > 50 % des keywords demandés ont
    # échoué → le workflow passe rouge (sinon une panne DFS totale laisse le
    # cron vert et trompeur). Complète l'alerte dfs_stale de cooked_alerts_refresh().
    if dfs_run_failed(total_failed, total_requested):
        sys.exit(
            f"ÉCHEC DFS : {total_failed}/{total_requested} keywords en erreur "
            f"(> 50 %) — voir logs ci-dessus"
        )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Sync DataForSEO Google Ads search_volume → Supabase dfs_keyword_volume"
    )
    parser.add_argument(
        "--limit", type=int, default=500,
        help="Top N keywords GSC 28j∪90j (défaut: 500)"
    )
    args = parser.parse_args(argv)
    run_sync(args.limit)


if __name__ == "__main__":
    main()
