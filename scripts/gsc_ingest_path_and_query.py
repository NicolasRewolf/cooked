#!/usr/bin/env python3
"""
GSC backfill 16 mois → upsert direct dans gsc_path_daily + gsc_query_daily.
Lit SUPABASE_SECRET_KEY depuis env, ne la log JAMAIS.
"""
import os
import sys
from datetime import date, timedelta
from urllib.parse import urlparse, unquote
from collections import defaultdict
import unicodedata
import time

from google.oauth2 import service_account
from googleapiclient.discovery import build
from supabase import create_client

# ---- Config ----
SUPABASE_URL = 'https://mxycmjkeotrycyneacje.supabase.co'
SUPABASE_KEY = os.environ.get('SUPABASE_SECRET_KEY')
if not SUPABASE_KEY:
    sys.exit("ERROR: SUPABASE_SECRET_KEY env var manquante")

SCOPES = ['https://www.googleapis.com/auth/webmasters.readonly']
GSC_CREDS = '/Users/nicolas/.claude/gsc-credentials.json'
SITE = 'https://www.jplouton-avocat.fr/'
END_DATE = date(2026, 5, 19)   # dernière date finale stable
BATCH_SIZE = 1000              # rows par upsert
MONTHS_BACK = 16

# ---- Setup clients (clé en mémoire seulement) ----
sb = create_client(SUPABASE_URL, SUPABASE_KEY)
gsc_creds = service_account.Credentials.from_service_account_file(GSC_CREDS, scopes=SCOPES)
gsc = build('searchconsole', 'v1', credentials=gsc_creds)

# ---- Canonicalisation symétrique avec events.path de Cooked ----
def canonical_path(raw_url):
    p = urlparse(raw_url)
    path = unquote(p.path)
    path = unicodedata.normalize('NFC', path)
    if len(path) > 1 and path.endswith('/'):
        path = path[:-1]
    return path or '/'

# ---- Fetch GSC paginé ----
def fetch(dim, start_date, end_date):
    rows = []
    start_row = 0
    while True:
        resp = gsc.searchanalytics().query(siteUrl=SITE, body={
            'startDate': start_date, 'endDate': end_date,
            'dimensions': dim, 'dataState': 'final',
            'rowLimit': 25000, 'startRow': start_row,
        }).execute()
        batch = resp.get('rows', [])
        rows.extend(batch)
        if len(batch) < 25000:
            break
        start_row += 25000
        time.sleep(0.2)
    return rows

# ---- Agrégation après canonicalisation ----
def aggregate(rows, key_fn, key_col):
    agg = defaultdict(lambda: {'imp': 0, 'clk': 0, 'w_pos': 0.0})
    for r in rows:
        day = r['keys'][0]
        k = key_fn(r['keys'][1])
        b = agg[(day, k)]
        b['imp'] += r['impressions']
        b['clk'] += r['clicks']
        b['w_pos'] += r['position'] * r['impressions']
    out = []
    for (day, k), v in agg.items():
        if v['imp'] <= 0:
            continue
        out.append({
            'day': day,
            key_col: k,
            'impressions': int(v['imp']),
            'clicks': int(v['clk']),
            'position': round(v['w_pos'] / v['imp'], 2),
            'ctr': round(v['clk'] / v['imp'], 6),
        })
    return out

# ---- Upsert en batches ----
def upsert_batch(table, rows, key_col):
    """Upsert avec ON CONFLICT (day, key_col). supabase-py utilise PostgREST."""
    for i in range(0, len(rows), BATCH_SIZE):
        chunk = rows[i:i + BATCH_SIZE]
        sb.table(table).upsert(chunk, on_conflict=f'day,{key_col}').execute()

# ---- Liste des 16 mois chronologiques ----
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

# ---- Main loop ----
months = list_months(END_DATE, MONTHS_BACK)
total_p_upserted = 0
total_q_upserted = 0
t0 = time.time()

for i, (ms, me) in enumerate(months, 1):
    label = ms.strftime('%Y-%m')
    t_start = time.time()
    print(f"[{i:2}/16] {label}", flush=True)

    p_raw = fetch(['date', 'page'], ms.isoformat(), me.isoformat())
    p_rows = aggregate(p_raw, canonical_path, 'path')
    upsert_batch('gsc_path_daily', p_rows, 'path')
    total_p_upserted += len(p_rows)

    q_raw = fetch(['date', 'query'], ms.isoformat(), me.isoformat())
    q_rows = aggregate(q_raw, lambda x: x, 'query')
    upsert_batch('gsc_query_daily', q_rows, 'query')
    total_q_upserted += len(q_rows)

    elapsed = time.time() - t_start
    print(f"        path upsert={len(p_rows):>5}  |  query upsert={len(q_rows):>5}  |  {elapsed:.1f}s", flush=True)

total = time.time() - t0
print(f"\n=== DONE in {total:.1f}s ===")
print(f"  gsc_path_daily  : {total_p_upserted:,} rows upserted")
print(f"  gsc_query_daily : {total_q_upserted:,} rows upserted")
