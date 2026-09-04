#!/usr/bin/env python3
"""
Google Business Profile → Cooked.

    python3 scripts/gbp_ingest.py discover
    python3 scripts/gbp_ingest.py probe --days 30
    python3 scripts/gbp_ingest.py ingest --days 540
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from cooked.gbp import main

if __name__ == "__main__":
    main()
