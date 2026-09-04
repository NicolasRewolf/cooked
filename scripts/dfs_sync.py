#!/usr/bin/env python3
"""
CLI DataForSEO → Supabase.

    python3 scripts/dfs_sync.py           # défaut : top 500
    python3 scripts/dfs_sync.py --limit 200
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from cooked.dfs import main

if __name__ == "__main__":
    main()
