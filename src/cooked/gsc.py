"""
Shared GSC → Supabase ingest (backfill + future cron).

Contract path (C3 — contrat partagé contracts/canonical_path_vectors.json) :
  decode → Unicode NFC → strip trailing slash (sauf /)
  Edge : supabase/functions/_shared/canonical_path.ts
  SQL  : public.canonical_path(text) (migration 20260709091028)
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Callable, Iterable, Sequence
from uuid import uuid4

from cooked.path import canonical_path
from cooked.store import CookedStore, SupabaseStore
from google.oauth2 import service_account
from googleapiclient.discovery import build

DEFAULT_GSC_CREDS = Path.home() / ".claude" / "gsc-credentials.json"
DEFAULT_SITE = "https://www.jplouton-avocat.fr/"
SCOPES = ["https://www.googleapis.com/auth/webmasters.readonly"]
BATCH_SIZE = 1000
MONTHS_BACK = 16
# Fenêtre cron quotidien (GitHub Actions) — 2 mois pour couvrir le mois précédent
# en entier (régression 01/07/2026 : n=1 sur fin de mois → trou gsc_gap).
GSC_DAILY_MONTHS_BACK = 2


def default_end_date() -> date:
    return date.today() - timedelta(days=1)


def parse_end_date(value: str | None) -> date:
    if value:
        return date.fromisoformat(value)
    env = os.environ.get("GSC_END_DATE")
    if env:
        return date.fromisoformat(env)
    return default_end_date()


def gsc_api_clients() -> tuple:
    creds_path = Path(
        os.environ.get("GSC_CREDENTIALS_PATH", str(DEFAULT_GSC_CREDS))
    ).expanduser()
    if not creds_path.is_file():
        sys.exit(f"ERROR: GSC credentials introuvables: {creds_path}")

    gsc_creds = service_account.Credentials.from_service_account_file(
        str(creds_path), scopes=SCOPES
    )
    gsc = build("searchconsole", "v1", credentials=gsc_creds)
    site = os.environ.get("GSC_SITE_URL", DEFAULT_SITE)
    return gsc, site


def clients() -> tuple:
    """Rétrocompat : (client Supabase brut, gsc, site). Préférer store + gsc_api_clients."""
    store = SupabaseStore.from_env()
    gsc, site = gsc_api_clients()
    return store.client, gsc, site


def fetch_gsc(
    gsc,
    site: str,
    dimensions: Sequence[str],
    start_date: date,
    end_date: date,
) -> list:
    rows: list = []
    start_row = 0
    while True:
        resp = (
            gsc.searchanalytics()
            .query(
                siteUrl=site,
                body={
                    "startDate": start_date.isoformat(),
                    "endDate": end_date.isoformat(),
                    "dimensions": list(dimensions),
                    "dataState": "final",
                    "rowLimit": 25000,
                    "startRow": start_row,
                },
            )
            .execute(num_retries=3)  # T-12 : backoff intégré googleapiclient
        )
        batch = resp.get("rows", [])
        rows.extend(batch)
        if len(batch) < 25000:
            break
        start_row += 25000
        time.sleep(0.2)
    return rows


def list_months(end: date, n: int) -> list[tuple[date, date]]:
    out: list[tuple[date, date]] = []
    cursor = end.replace(day=1)
    for _ in range(n):
        m_start = cursor
        if cursor.month == 12:
            m_end_max = date(cursor.year + 1, 1, 1) - timedelta(days=1)
        else:
            m_end_max = date(cursor.year, cursor.month + 1, 1) - timedelta(days=1)
        out.append((m_start, min(m_end_max, end)))
        if cursor.month == 1:
            cursor = date(cursor.year - 1, 12, 1)
        else:
            cursor = date(cursor.year, cursor.month - 1, 1)
    out.reverse()
    return out


def _metric_row(day: str, metrics: dict, extra: dict) -> dict:
    imp = metrics["imp"]
    clk = metrics["clk"]
    return {
        "day": day,
        **extra,
        "impressions": int(imp),
        "clicks": int(clk),
        "position": round(metrics["w_pos"] / imp, 2),
        "ctr": round(clk / imp, 6),
        "ingested_at": datetime.now(timezone.utc).isoformat(),
    }


def aggregate_daily(
    rows: Iterable,
    key_cols: Sequence[str],
    key_fns: Sequence[Callable[[str], str]],
) -> list[dict]:
    """Agrège lignes GSC par (day, *keys) avec position pondérée par impressions."""
    agg: dict = defaultdict(lambda: {"imp": 0, "clk": 0, "w_pos": 0.0})
    for r in rows:
        keys = r["keys"]
        day = keys[0]
        mapped = tuple(fn(keys[i + 1]) for i, fn in enumerate(key_fns))
        b = agg[(day, *mapped)]
        b["imp"] += r["impressions"]
        b["clk"] += r["clicks"]
        b["w_pos"] += r["position"] * r["impressions"]

    out: list[dict] = []
    col_names = list(key_cols)
    for key_tuple, v in agg.items():
        if v["imp"] <= 0:
            continue
        day = key_tuple[0]
        extra = dict(zip(col_names, key_tuple[1:]))
        out.append(_metric_row(day, v, extra))
    return out


def run_path_query(
    end_date: date,
    months_back: int = MONTHS_BACK,
    store: CookedStore | None = None,
) -> dict[str, int]:
    store = store or SupabaseStore.from_env()
    gsc, site = gsc_api_clients()
    months = list_months(end_date, months_back)
    total_p = total_q = 0
    t0 = time.time()

    for i, (ms, me) in enumerate(months, 1):
        label = ms.strftime("%Y-%m")
        t_start = time.time()
        print(f"[{i:2}/{months_back}] {label}", flush=True)

        p_raw = fetch_gsc(gsc, site, ["date", "page"], ms, me)
        p_rows = aggregate_daily(
            p_raw, ("path",), (canonical_path,)
        )
        store.upsert_batches("gsc_path_daily", p_rows, "day,path", BATCH_SIZE)
        total_p += len(p_rows)

        q_raw = fetch_gsc(gsc, site, ["date", "query"], ms, me)
        q_rows = aggregate_daily(q_raw, ("query",), (lambda x: x,))
        store.upsert_batches("gsc_query_daily", q_rows, "day,query", BATCH_SIZE)
        total_q += len(q_rows)

        elapsed = time.time() - t_start
        print(
            f"        path upsert={len(p_rows):>5}  |  query upsert={len(q_rows):>5}  |  {elapsed:.1f}s",
            flush=True,
        )

    print(f"\n=== path-query DONE in {time.time() - t0:.1f}s ===")
    print(f"  gsc_path_daily  : {total_p:,} rows upserted")
    print(f"  gsc_query_daily : {total_q:,} rows upserted")
    return {"gsc_path_daily": total_p, "gsc_query_daily": total_q}


def run_query_page(
    end_date: date,
    months_back: int = MONTHS_BACK,
    store: CookedStore | None = None,
) -> dict[str, int]:
    store = store or SupabaseStore.from_env()
    gsc, site = gsc_api_clients()
    months = list_months(end_date, months_back)
    total = 0
    t0 = time.time()

    for i, (ms, me) in enumerate(months, 1):
        label = ms.strftime("%Y-%m")
        t_start = time.time()

        raw = fetch_gsc(gsc, site, ["date", "page", "query"], ms, me)
        rows = aggregate_daily(
            raw, ("path", "query"), (canonical_path, lambda x: x)
        )
        store.upsert_batches("gsc_query_page_daily", rows, "day,path,query", BATCH_SIZE)
        total += len(rows)

        elapsed = time.time() - t_start
        print(
            f"[{i:2}/{months_back}] {label}  raw={len(raw):>6}  agg={len(rows):>6}  ({elapsed:.1f}s)",
            flush=True,
        )

    print(f"\n=== query-page DONE in {time.time() - t0:.1f}s ===")
    print(f"  gsc_query_page_daily : {total:,} rows upserted")
    return {"gsc_query_page_daily": total}


def run_ingestion(
    mode: str,
    end_date: date,
    months_back: int = MONTHS_BACK,
    store: CookedStore | None = None,
) -> None:
    """Publie uniquement un lot dont les trois sources ont été ingérées.

    Begin ferme le refresh aval AVANT la première écriture. Une interruption
    laisse ce verrou logique fermé ; le prochain lot complet reprend la
    fenêtre. Les anciens modes partiels restent utiles au diagnostic mais ne
    peuvent jamais annoncer une photographie complète.
    """
    if mode not in {"all", "path-query", "query-page"}:
        raise ValueError("Mode GSC inconnu")
    if months_back < 1:
        raise ValueError("months_back doit être positif")
    store = store or SupabaseStore.from_env()
    run_id = str(uuid4())
    start_date = list_months(end_date, months_back)[0][0]
    store.rpc("gsc_ingest_begin", {
        "p_run_id": run_id,
        "p_start": start_date.isoformat(),
        "p_end": end_date.isoformat(),
    })
    try:
        counts: dict[str, int] = {}
        if mode in {"all", "path-query"}:
            counts.update(run_path_query(end_date, months_back, store=store))
        if mode in {"all", "query-page"}:
            counts.update(run_query_page(end_date, months_back, store=store))
        if mode != "all":
            store.rpc("gsc_ingest_fail", {"p_run_id": run_id})
            print(
                "Lot GSC partiel : le rafraîchissement aval reste suspendu. "
                "Exécuter `gsc_ingest.py all` avec la même fenêtre pour publier.",
                flush=True,
            )
            return
        if not any(counts.values()):
            raise RuntimeError("Lot GSC entièrement vide : publication refusée")
        store.rpc("gsc_ingest_complete", {
            "p_run_id": run_id,
            "p_row_counts": counts,
        })
    except BaseException:
        # Un crash ne doit pas publier un lot partiel. Ne pas masquer l'erreur
        # initiale si la base est elle-même indisponible : running reste fermé.
        try:
            store.rpc("gsc_ingest_fail", {"p_run_id": run_id})
        except Exception:
            print("Échec du signal de fin GSC : reprise explicite requise.", file=sys.stderr)
        raise
    print("Lot GSC complet : les trois sources sont prêtes pour le refresh.", flush=True)


def _add_run_flags(p: argparse.ArgumentParser) -> None:
    p.add_argument(
        "--end-date",
        metavar="YYYY-MM-DD",
        help="Dernier jour inclus (défaut: hier, ou GSC_END_DATE)",
    )
    p.add_argument(
        "--daily",
        action="store_true",
        help=f"Fenêtre cron quotidien ({GSC_DAILY_MONTHS_BACK} mois — couvre le mois précédent en entier)",
    )
    p.add_argument(
        "--months",
        type=int,
        default=MONTHS_BACK,
        help=f"Mois d'historique (défaut: {MONTHS_BACK} ; ignoré si --daily)",
    )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Ingestion GSC → Cooked (all ; modes partiels de diagnostic)"
    )
    sub = parser.add_subparsers(dest="mode", required=True)

    _add_run_flags(sub.add_parser("all", help="Les trois sources, un seul lot publiable"))
    _add_run_flags(sub.add_parser("path-query", help="gsc_path_daily + gsc_query_daily"))
    _add_run_flags(sub.add_parser("query-page", help="gsc_query_page_daily"))

    args = parser.parse_args(argv)
    end = parse_end_date(args.end_date)
    months_back = GSC_DAILY_MONTHS_BACK if args.daily else args.months

    if months_back < 1:
        parser.error("--months doit être positif")
    run_ingestion(args.mode, end, months_back)
