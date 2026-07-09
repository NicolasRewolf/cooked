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
import unicodedata
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Callable, Iterable, Sequence
from urllib.parse import unquote, urlparse

from google.oauth2 import service_account
from googleapiclient.discovery import build
from supabase import create_client

DEFAULT_SUPABASE_URL = "https://mxycmjkeotrycyneacje.supabase.co"
DEFAULT_GSC_CREDS = Path.home() / ".claude" / "gsc-credentials.json"
DEFAULT_SITE = "https://www.jplouton-avocat.fr/"
SCOPES = ["https://www.googleapis.com/auth/webmasters.readonly"]
BATCH_SIZE = 1000
MONTHS_BACK = 16


def canonical_path(raw: str) -> str:
    """Path canonique partagé Cooked × GSC (pathname ou URL GSC complète)."""
    if raw.startswith("http://") or raw.startswith("https://"):
        path = urlparse(raw).path
    else:
        path = raw
    path = unquote(path)
    path = unicodedata.normalize("NFC", path)
    if len(path) > 1 and path.endswith("/"):
        path = path[:-1]
    return path or "/"


def default_end_date() -> date:
    return date.today() - timedelta(days=1)


def parse_end_date(value: str | None) -> date:
    if value:
        return date.fromisoformat(value)
    env = os.environ.get("GSC_END_DATE")
    if env:
        return date.fromisoformat(env)
    return default_end_date()


def clients() -> tuple:
    supabase_url = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE_URL)
    supabase_key = os.environ.get("SUPABASE_SECRET_KEY")
    if not supabase_key:
        sys.exit("ERROR: SUPABASE_SECRET_KEY env var manquante")

    creds_path = Path(
        os.environ.get("GSC_CREDENTIALS_PATH", str(DEFAULT_GSC_CREDS))
    ).expanduser()
    if not creds_path.is_file():
        sys.exit(f"ERROR: GSC credentials introuvables: {creds_path}")

    sb = create_client(supabase_url, supabase_key)
    gsc_creds = service_account.Credentials.from_service_account_file(
        str(creds_path), scopes=SCOPES
    )
    gsc = build("searchconsole", "v1", credentials=gsc_creds)
    site = os.environ.get("GSC_SITE_URL", DEFAULT_SITE)
    return sb, gsc, site


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


def upsert_batches(sb, table: str, rows: list[dict], on_conflict: str) -> None:
    for i in range(0, len(rows), BATCH_SIZE):
        sb.table(table).upsert(rows[i : i + BATCH_SIZE], on_conflict=on_conflict).execute()


def run_path_query(end_date: date, months_back: int = MONTHS_BACK) -> None:
    sb, gsc, site = clients()
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
        upsert_batches(sb, "gsc_path_daily", p_rows, "day,path")
        total_p += len(p_rows)

        q_raw = fetch_gsc(gsc, site, ["date", "query"], ms, me)
        q_rows = aggregate_daily(q_raw, ("query",), (lambda x: x,))
        upsert_batches(sb, "gsc_query_daily", q_rows, "day,query")
        total_q += len(q_rows)

        elapsed = time.time() - t_start
        print(
            f"        path upsert={len(p_rows):>5}  |  query upsert={len(q_rows):>5}  |  {elapsed:.1f}s",
            flush=True,
        )

    print(f"\n=== path-query DONE in {time.time() - t0:.1f}s ===")
    print(f"  gsc_path_daily  : {total_p:,} rows upserted")
    print(f"  gsc_query_daily : {total_q:,} rows upserted")


def run_query_page(end_date: date, months_back: int = MONTHS_BACK) -> None:
    sb, gsc, site = clients()
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
        upsert_batches(sb, "gsc_query_page_daily", rows, "day,path,query")
        total += len(rows)

        elapsed = time.time() - t_start
        print(
            f"[{i:2}/{months_back}] {label}  raw={len(raw):>6}  agg={len(rows):>6}  ({elapsed:.1f}s)",
            flush=True,
        )

    print(f"\n=== query-page DONE in {time.time() - t0:.1f}s ===")
    print(f"  gsc_query_page_daily : {total:,} rows upserted")


def _add_run_flags(p: argparse.ArgumentParser) -> None:
    p.add_argument(
        "--end-date",
        metavar="YYYY-MM-DD",
        help="Dernier jour inclus (défaut: hier, ou GSC_END_DATE)",
    )
    p.add_argument(
        "--months",
        type=int,
        default=MONTHS_BACK,
        help=f"Mois d'historique (défaut: {MONTHS_BACK})",
    )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Ingestion GSC → Cooked (path-query | query-page)"
    )
    sub = parser.add_subparsers(dest="mode", required=True)

    _add_run_flags(sub.add_parser("path-query", help="gsc_path_daily + gsc_query_daily"))
    _add_run_flags(sub.add_parser("query-page", help="gsc_query_page_daily"))

    args = parser.parse_args(argv)
    end = parse_end_date(args.end_date)

    if args.mode == "path-query":
        run_path_query(end, args.months)
    else:
        run_query_page(end, args.months)
