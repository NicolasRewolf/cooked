#!/usr/bin/env python3
"""
Backfill gsc_query_page_daily — 16 mois × dimensions ['date','page','query'].
Lit SUPABASE_SECRET_KEY depuis env, jamais loggée.
"""
import os
import sys
import time
import unicodedata
from datetime import date, timedelta
from urllib.parse import urlparse, unquote
from collections import defaultdict

from google.oauth2 import service_account
from googleapiclient.discovery import build
from supabase import create_client

# Config
SUPABASE_URL = 'https://mxycmjkeotrycyneacje.supabase.co'
SUPABASE_KEY = os.environ.get('SUPABASE_SECRET_KEY')
if not SUPABASE_KEY:
    sys.exit("ERROR: SUPABASE_SECRET_KEY env var manquante")

SCOPES = ['https://www.googleapis.com/auth/webmasters.readonly']
GSC_CREDS = '/Users/nicolas/.claude/gsc-credentials.json'
SITE = 'https://www.jplouton-avocat.fr/'
END_DATE = date(2026, 5, 19)
BATCH_SIZE = 1000
MONTHS_BACK = 16

# Clients
sb = create_client(SUPABASE_URL, SUPABASE_KEY)
gsc_creds = service_account.Credentials.from_service_account_file(GSC_CREDS, scopes=SCOPES)
gsc = build('searchconsole', 'v1', credentials=gsc_creds)

def canonical_path(raw_url):
    """Symétrique avec events.path Cooked et gsc_path_daily."""
    p = urlparse(raw_url)
    path = unquote(p.path)
    path = unicodedata.normalize('NFC', path)
    if len(path) > 1 and path.endswith('/'):
        path = path[:-1]
    return path or '/'

def fetch(start_date, end_date):
    """Fetch GSC paginé sur dimensions [date, page, query]."""
    rows = []
    start_row = 0
    while True:
        resp = gsc.searchanalytics().query(siteUrl=SITE, body={
            'startDate': start_date, 'endDate': end_date,
            'dimensions': ['date', 'page', 'query'],
            'dataState': 'final',
            'rowLimit': 25000,
            'startRow': start_row,
        }).execute()
        batch = resp.get('rows', [])
        rows.extend(batch)
        if len(batch) < 25000:
            break
        start_row += 25000
        time.sleep(0.2)
    return rows

def aggregate(rows):
    """Agrège par (day, canonical_path, query). 1 row par triplet."""
    agg = defaultdict(lambda: {'imp': 0, 'clk': 0, 'w_pos': 0.0})
    for r in rows:
        day = r['keys'][0]
        path = canonical_path(r['keys'][1])
        query = r['keys'][2]
        b = agg[(day, path, query)]
        b['imp'] += r['impressions']
        b['clk'] += r['clicks']
        b['w_pos'] += r['position'] * r['impressions']
    out = []
    for (day, path, query), v in agg.items():
        if v['imp'] <= 0:
            continue
        out.append({
            'day': day,
            'path': path,
            'query': query,
            'impressions': int(v['imp']),
            'clicks': int(v['clk']),
            'position': round(v['w_pos'] / v['imp'], 2),
            'ctr': round(v['clk'] / v['imp'], 6),
        })
    return out

def upsert_batch(rows):
    for i in range(0, len(rows), BATCH_SIZE):
        chunk = rows[i:i + BATCH_SIZE]
        sb.table('gsc_query_page_daily').upsert(
            chunk, on_conflict='day,path,query'
        ).execute()

def list_months(end, n):
    out = []
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

# Main
months = list_months(END_DATE, MONTHS_BACK)
total_upserted = 0
t0 = time.time()

for i, (ms, me) in enumerate(months, 1):
    label = ms.strftime('%Y-%m')
    t_start = time.time()

    raw = fetch(ms.isoformat(), me.isoformat())
    agg = aggregate(raw)
    upsert_batch(agg)
    total_upserted += len(agg)

    elapsed = time.time() - t_start
    print(f"[{i:2}/16] {label}  raw={len(raw):>6}  agg={len(agg):>6}  ({elapsed:.1f}s)", flush=True)

total = time.time() - t0
print(f"\n=== DONE in {total:.1f}s ===")
print(f"  gsc_query_page_daily : {total_upserted:,} rows upserted")
