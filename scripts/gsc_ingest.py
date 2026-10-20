#!/usr/bin/env python3
"""
Ingestion GSC → Supabase Cooked.

  python3 scripts/gsc_ingest.py all
  python3 scripts/gsc_ingest.py all --daily   # fenêtre cron (2 mois)

Les modes path-query / query-page sont partiels : ils ferment le refresh
aval et ne publient pas de lot complet. Rejouer all pour le rétablir.

Env : SUPABASE_SECRET_KEY (requis), SUPABASE_URL, GSC_CREDENTIALS_PATH,
      GSC_SITE_URL, GSC_END_DATE. Voir cooked.gsc.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from cooked.gsc import main

if __name__ == "__main__":
    main()
