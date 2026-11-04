#!/usr/bin/env python3
"""
Minify wix/tracker.html → wix/tracker.min.html for Wix Custom Code.

Wix Studio's Custom Code field has a **15 000 character limit**. The
source tracker (wix/tracker.html) keeps comments and formatting for
review. This script strips comments and
whitespace via jsmin (which preserves regex, string literals, and
automatic semicolon insertion).

Usage:
  python3 scripts/minify-tracker.py
  python3 scripts/minify-tracker.py --copy   # also copy to macOS clipboard

Requires:
  pip install jsmin

Outputs:
  wix/tracker.min.html   (gitignored — regenerate before each deploy)
"""
import json
import re
import subprocess
import sys
from pathlib import Path

try:
    from jsmin import jsmin
except ImportError:
    print("error: jsmin not installed. Run: pip install jsmin", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
SRC  = ROOT / "wix" / "tracker.html"
DST  = ROOT / "wix" / "tracker.min.html"
WIX_LIMIT = 15_000
CONSTANTS = ROOT / "contracts" / "doc_constants.json"

def main(copy_to_clipboard: bool):
    try:
        tracker = json.loads(CONSTANTS.read_text(encoding="utf-8"))["tracker"]
        soft = tracker["soft_limit_chars"]
        baseline = tracker["min_chars_baseline"]
        if any(type(value) is not int or not 0 < value <= WIX_LIMIT for value in (soft, baseline)):
            raise ValueError("bornes tracker invalides")
    except (OSError, ValueError, KeyError, TypeError):
        print("error: contrat tracker absent ou invalide dans contracts/doc_constants.json", file=sys.stderr)
        sys.exit(1)
    html = SRC.read_text(encoding="utf-8")

    # 1. Strip HTML comments (the big version-history banner).
    html_no_comments = re.sub(r"<!--.*?-->", "", html, flags=re.DOTALL)

    # 2. Extract <script>...</script>.
    m = re.search(r"<script>(.*?)</script>", html_no_comments, flags=re.DOTALL)
    if not m:
        print("error: no <script> block found in tracker.html", file=sys.stderr)
        sys.exit(1)
    js = m.group(1)

    # 3. Minify JS (jsmin is whitespace+comment only — safe for ES5).
    min_js = jsmin(js)
    min_js = re.sub(r"\n+", "\n", min_js).strip()

    # 4. Re-wrap.
    out = "<script>" + min_js + "</script>"
    DST.write_text(out, encoding="utf-8")

    size = len(out)
    pct  = 100 * size / WIX_LIMIT
    status = "✅ FITS" if size <= WIX_LIMIT else "❌ TOO BIG"
    print(f"Source   : {len(html):>7,} chars")
    print(f"Minified : {size:>7,} chars  ({pct:.1f}% of Wix's {WIX_LIMIT:,} limit)  {status}")
    print(f"Saved    : {DST.relative_to(ROOT)}")

    if size > WIX_LIMIT:
        print()
        print("The minified tracker exceeds Wix Custom Code's 15 000 char limit.", file=sys.stderr)
        print("Trim a comment or factor out a helper before redeploying.", file=sys.stderr)
        sys.exit(2)

    # Au-dessus de la cible, aucune augmentation par rapport à la taille de
    # référence déclarée dans le contrat. La limite Wix reste toujours stricte.
    if size > soft and size > baseline:
        print()
        print(f"T-17 : minifié {size:,} > baseline {baseline:,} au-dessus de la marge de sécurité ({soft:,}).", file=sys.stderr)
        print("Réduire le tracker, ou justifier une nouvelle taille de référence dans", file=sys.stderr)
        print("contracts/doc_constants.json → tracker.min_chars_baseline dans la même PR.", file=sys.stderr)
        sys.exit(3)
    if size > soft:
        print(f"⚠ {size:,} > cible {soft:,} : cliquet à {baseline:,} caractères.")

    if copy_to_clipboard:
        if sys.platform == "darwin":
            subprocess.run(["pbcopy"], input=out, text=True, check=True)
            print("Clipboard: copied (macOS pbcopy)")
        else:
            print(f"--copy is macOS-only. Copy manually from {DST}", file=sys.stderr)

if __name__ == "__main__":
    copy = "--copy" in sys.argv[1:]
    main(copy_to_clipboard=copy)
