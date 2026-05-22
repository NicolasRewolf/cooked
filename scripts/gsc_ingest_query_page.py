#!/usr/bin/env python3
"""Wrapper rétro-compat — préférer: python3 scripts/gsc_ingest.py query-page"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gsc_common import main

if __name__ == "__main__":
    main(["query-page"] + sys.argv[1:])
