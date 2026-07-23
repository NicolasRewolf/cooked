"""
Shared GBP (Google Business Profile) → Supabase ingest.

Auth : OAuth 2.0 refresh token (scope business.manage). Les service
accounts Google ne passent pas bien sur GBP — un compte humain manager
de la fiche doit autoriser une fois (scripts/gbp_oauth_setup.py).

APIs :
  - mybusinessaccountmanagement v1  → list accounts
  - mybusinessbusinessinformation v1 → list locations
  - businessprofileperformance v1   → métriques quotidiennes
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from cooked_store import CookedStore, SupabaseStore
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

DEFAULT_TOKEN_PATH = Path.home() / ".claude" / "gbp-token.json"
SCOPES = ["https://www.googleapis.com/auth/business.manage"]
BATCH_SIZE = 500
# Fenêtre cron quotidien — 90 j (volume faible : 1 row/jour/fiche).
GBP_DAILY_DAYS_BACK = 90
# Backfill initial conseillé
GBP_DEFAULT_DAYS_BACK = 365

DAILY_METRICS = (
    "CALL_CLICKS",
    "WEBSITE_CLICKS",
    "BUSINESS_DIRECTION_REQUESTS",
    "BUSINESS_CONVERSATIONS",
    "BUSINESS_IMPRESSIONS_DESKTOP_MAPS",
    "BUSINESS_IMPRESSIONS_DESKTOP_SEARCH",
    "BUSINESS_IMPRESSIONS_MOBILE_MAPS",
    "BUSINESS_IMPRESSIONS_MOBILE_SEARCH",
)

METRIC_TO_COLUMN = {
    "CALL_CLICKS": "call_clicks",
    "WEBSITE_CLICKS": "website_clicks",
    "BUSINESS_DIRECTION_REQUESTS": "direction_requests",
    "BUSINESS_CONVERSATIONS": "conversations",
    "BUSINESS_IMPRESSIONS_DESKTOP_MAPS": "impressions_desktop_maps",
    "BUSINESS_IMPRESSIONS_DESKTOP_SEARCH": "impressions_desktop_search",
    "BUSINESS_IMPRESSIONS_MOBILE_MAPS": "impressions_mobile_maps",
    "BUSINESS_IMPRESSIONS_MOBILE_SEARCH": "impressions_mobile_search",
}


def default_end_date() -> date:
    return date.today() - timedelta(days=1)


def parse_end_date(value: str | None) -> date:
    if value:
        return date.fromisoformat(value)
    env = os.environ.get("GBP_END_DATE")
    if env:
        return date.fromisoformat(env)
    return default_end_date()


def _token_dict_from_env_or_file() -> dict[str, str]:
    """Lit client_id / client_secret / refresh_token depuis env ou JSON local."""
    path = Path(
        os.environ.get("GBP_TOKEN_PATH", str(DEFAULT_TOKEN_PATH))
    ).expanduser()

    data: dict[str, Any] = {}
    if path.is_file():
        data = json.loads(path.read_text(encoding="utf-8"))

    client_id = os.environ.get("GBP_OAUTH_CLIENT_ID") or data.get("client_id")
    client_secret = os.environ.get("GBP_OAUTH_CLIENT_SECRET") or data.get(
        "client_secret"
    )
    refresh_token = os.environ.get("GBP_OAUTH_REFRESH_TOKEN") or data.get(
        "refresh_token"
    )

    missing = [
        name
        for name, val in (
            ("client_id", client_id),
            ("client_secret", client_secret),
            ("refresh_token", refresh_token),
        )
        if not val
    ]
    if missing:
        sys.exit(
            "ERROR: credentials GBP incomplets ("
            + ", ".join(missing)
            + "). "
            "Lancer scripts/gbp_oauth_setup.py une fois, ou poser "
            "GBP_OAUTH_CLIENT_ID / GBP_OAUTH_CLIENT_SECRET / "
            "GBP_OAUTH_REFRESH_TOKEN (ou GBP_TOKEN_PATH)."
        )

    return {
        "client_id": str(client_id),
        "client_secret": str(client_secret),
        "refresh_token": str(refresh_token),
        "token_uri": data.get("token_uri", "https://oauth2.googleapis.com/token"),
    }


def gbp_credentials() -> Credentials:
    tok = _token_dict_from_env_or_file()
    creds = Credentials(
        token=None,
        refresh_token=tok["refresh_token"],
        token_uri=tok["token_uri"],
        client_id=tok["client_id"],
        client_secret=tok["client_secret"],
        scopes=SCOPES,
    )
    creds.refresh(Request())
    return creds


def gbp_api_clients() -> tuple[Credentials, Any, Any]:
    """Retourne (creds, account_management, business_information)."""
    creds = gbp_credentials()
    accounts = build(
        "mybusinessaccountmanagement", "v1", credentials=creds, cache_discovery=False
    )
    info = build(
        "mybusinessbusinessinformation", "v1", credentials=creds, cache_discovery=False
    )
    return creds, accounts, info


def location_id_of(name: str) -> str:
    """`locations/123` → `123` ; déjà bare → inchangé."""
    if name.startswith("locations/"):
        return name.split("/", 1)[1]
    return name


def list_locations(
    accounts_svc: Any,
    info_svc: Any,
    forced_location_id: str | None = None,
) -> list[dict[str, str]]:
    """Retourne [{location_id, title, name}, ...]."""
    forced = forced_location_id or os.environ.get("GBP_LOCATION_ID")
    if forced:
        lid = location_id_of(forced)
        title = os.environ.get("GBP_LOCATION_TITLE", "")
        return [
            {
                "location_id": lid,
                "title": title,
                "name": f"locations/{lid}",
            }
        ]

    out: list[dict[str, str]] = []
    page_token = None
    while True:
        req = accounts_svc.accounts().list(pageSize=20, pageToken=page_token)
        resp = req.execute(num_retries=3)
        for acc in resp.get("accounts", []):
            acc_name = acc["name"]  # accounts/{id}
            loc_token = None
            while True:
                loc_resp = (
                    info_svc.accounts()
                    .locations()
                    .list(
                        parent=acc_name,
                        pageSize=100,
                        pageToken=loc_token,
                        readMask="name,title",
                    )
                    .execute(num_retries=3)
                )
                for loc in loc_resp.get("locations", []):
                    name = loc.get("name", "")
                    out.append(
                        {
                            "location_id": location_id_of(name),
                            "title": loc.get("title") or "",
                            "name": name if name.startswith("locations/") else f"locations/{location_id_of(name)}",
                        }
                    )
                loc_token = loc_resp.get("nextPageToken")
                if not loc_token:
                    break
        page_token = resp.get("nextPageToken")
        if not page_token:
            break

    if not out:
        sys.exit(
            "ERROR: aucune fiche GBP visible pour ce compte OAuth. "
            "Vérifier que le Google Account manager de la fiche a bien "
            "autorisé l'appli (gbp_oauth_setup.py)."
        )
    return out


def fetch_daily_metrics(
    creds: Credentials,
    location_name: str,
    start: date,
    end: date,
) -> dict[str, dict[str, int]]:
    """
    Retourne { 'YYYY-MM-DD': { column: value, ... }, ... }.
    Les jours absents de la réponse API ne sont pas créés (Google omet
    parfois les jours à 0 — on les remplit ensuite pour éviter gbp_gap).

    Appel REST direct (query params nested) : plus fiable que le mapping
    discovery du client pour dailyRange.start_date.*.
    """
    from urllib.parse import urlencode

    from google.auth.transport.requests import AuthorizedSession

    by_day: dict[str, dict[str, int]] = {}
    authed = AuthorizedSession(creds)
    base = "https://businessprofileperformance.googleapis.com/v1"
    url = f"{base}/{location_name}:fetchMultiDailyMetricsTimeSeries"

    params: list[tuple[str, str]] = [
        ("dailyRange.start_date.year", str(start.year)),
        ("dailyRange.start_date.month", str(start.month)),
        ("dailyRange.start_date.day", str(start.day)),
        ("dailyRange.end_date.year", str(end.year)),
        ("dailyRange.end_date.month", str(end.month)),
        ("dailyRange.end_date.day", str(end.day)),
    ]
    for metric in DAILY_METRICS:
        params.append(("dailyMetrics", metric))

    full_url = f"{url}?{urlencode(params)}"
    http_resp = authed.get(full_url, timeout=60)
    if http_resp.status_code >= 400:
        raise RuntimeError(
            f"GBP Performance API HTTP {http_resp.status_code}: {http_resp.text[:500]}"
        )
    resp = http_resp.json()
    if "error" in resp:
        raise RuntimeError(f"GBP Performance API error: {resp['error']}")

    for multi in resp.get("multiDailyMetricTimeSeries", []):
        for series in multi.get("dailyMetricTimeSeries", []):
            metric = series.get("dailyMetric")
            col = METRIC_TO_COLUMN.get(metric or "")
            if not col:
                continue
            for point in series.get("timeSeries", {}).get("datedValues", []):
                d = point.get("date") or {}
                if not d.get("year"):
                    continue
                day_key = date(d["year"], d["month"], d["day"]).isoformat()
                bucket = by_day.setdefault(day_key, {})
                # datedValues.value est string ; absent = 0
                raw = point.get("value")
                bucket[col] = int(raw) if raw is not None else 0

    return by_day


def fill_missing_days(
    by_day: dict[str, dict[str, int]],
    start: date,
    end: date,
) -> dict[str, dict[str, int]]:
    """Assure une ligne par jour calendaire (zéros) pour éviter gbp_gap."""
    out = dict(by_day)
    cursor = start
    while cursor <= end:
        key = cursor.isoformat()
        out.setdefault(key, {})
        cursor += timedelta(days=1)
    return out


def rows_for_location(
    location: dict[str, str],
    by_day: dict[str, dict[str, int]],
) -> list[dict]:
    now = datetime.now(timezone.utc).isoformat()
    rows: list[dict] = []
    zero_cols = {col: 0 for col in METRIC_TO_COLUMN.values()}
    for day_key, metrics in sorted(by_day.items()):
        row = {
            "day": day_key,
            "location_id": location["location_id"],
            "location_title": location.get("title") or None,
            "ingested_at": now,
            **zero_cols,
            **metrics,
        }
        rows.append(row)
    return rows


def run_ingest(
    end_date: date,
    days_back: int = GBP_DEFAULT_DAYS_BACK,
    store: CookedStore | None = None,
) -> None:
    store = store or SupabaseStore.from_env()
    creds, accounts_svc, info_svc = gbp_api_clients()
    locations = list_locations(accounts_svc, info_svc)

    start = end_date - timedelta(days=days_back - 1)
    print(
        f"GBP ingest {start.isoformat()} → {end_date.isoformat()} "
        f"({len(locations)} fiche(s))",
        flush=True,
    )

    total = 0
    t0 = time.time()
    for loc in locations:
        label = loc.get("title") or loc["location_id"]
        t_start = time.time()
        by_day = fetch_daily_metrics(creds, loc["name"], start, end_date)
        by_day = fill_missing_days(by_day, start, end_date)
        rows = rows_for_location(loc, by_day)
        store.upsert_batches(
            "gbp_location_daily", rows, "day,location_id", BATCH_SIZE
        )
        total += len(rows)
        print(
            f"  {label}: {len(rows)} jours "
            f"({time.time() - t_start:.1f}s)",
            flush=True,
        )

    print(f"\n=== GBP DONE in {time.time() - t0:.1f}s ===")
    print(f"  gbp_location_daily : {total:,} rows upserted")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Ingestion Google Business Profile → Cooked"
    )
    parser.add_argument(
        "--end-date",
        metavar="YYYY-MM-DD",
        help="Dernier jour inclus (défaut: hier, ou GBP_END_DATE)",
    )
    parser.add_argument(
        "--daily",
        action="store_true",
        help=f"Fenêtre cron quotidien ({GBP_DAILY_DAYS_BACK} jours)",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=GBP_DEFAULT_DAYS_BACK,
        help=f"Jours d'historique (défaut: {GBP_DEFAULT_DAYS_BACK} ; ignoré si --daily)",
    )
    parser.add_argument(
        "--list-locations",
        action="store_true",
        help="Liste les fiches visibles et quitte (sanity check OAuth)",
    )
    args = parser.parse_args(argv)

    if args.list_locations:
        _, accounts_svc, info_svc = gbp_api_clients()
        for loc in list_locations(accounts_svc, info_svc):
            print(f"{loc['location_id']}\t{loc.get('title') or '(sans titre)'}")
        return

    end = parse_end_date(args.end_date)
    days_back = GBP_DAILY_DAYS_BACK if args.daily else args.days
    run_ingest(end, days_back)
