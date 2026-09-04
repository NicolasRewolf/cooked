#!/usr/bin/env python3
"""Synchro page_taxonomy ← liste publiée du blog Wix.

  python3 scripts/wix_taxonomy_sync.py
  python3 scripts/wix_taxonomy_sync.py --dry-run
  python3 scripts/wix_taxonomy_sync.py --from-file tests/fixtures/wix_blog_posts_2026-09-03.txt --dry-run
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from cooked.wix.taxonomy import main

if __name__ == "__main__":
    raise SystemExit(main())
