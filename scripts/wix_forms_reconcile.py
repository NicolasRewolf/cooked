#!/usr/bin/env python3
"""Entrée CLI du rapprochement agrégé Wix/Cooked."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from cooked.wix.reconcile import main

if __name__ == "__main__":
    raise SystemExit(main())
