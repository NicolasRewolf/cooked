#!/usr/bin/env python3
"""
SECIB → Cooked (pont prospects ↔ dossiers).

    python3 scripts/secib_ingest.py probe  --days 120
    python3 scripts/secib_ingest.py ingest --days 120
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from cooked.secib import main

if __name__ == "__main__":
    main()
