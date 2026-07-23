#!/usr/bin/env python3
"""
Ingestion Google Business Profile → Supabase Cooked.

  python3 scripts/gbp_ingest.py --list-locations   # sanity OAuth
  python3 scripts/gbp_ingest.py                    # backfill 365 j
  python3 scripts/gbp_ingest.py --daily            # fenêtre cron (90 j)

Env : SUPABASE_SECRET_KEY (requis), SUPABASE_URL,
      GBP_OAUTH_CLIENT_ID, GBP_OAUTH_CLIENT_SECRET, GBP_OAUTH_REFRESH_TOKEN
      (ou GBP_TOKEN_PATH → ~/.claude/gbp-token.json),
      GBP_LOCATION_ID (optionnel), GBP_END_DATE.
Voir scripts/gbp_common.py + docs/OPERATIONS.md.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gbp_common import main

if __name__ == "__main__":
    main()
