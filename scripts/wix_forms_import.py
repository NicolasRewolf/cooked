#!/usr/bin/env python3
"""Import CSV Wix Forms → crm_prospects.

    python3 scripts/wix_forms_import.py --csv "/chemin/vers/export.csv" [--dry-run]
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from cooked.wix.forms import main

if __name__ == "__main__":
    main()
