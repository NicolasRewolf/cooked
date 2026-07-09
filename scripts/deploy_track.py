#!/usr/bin/env python3
"""
Déploie la Edge Function `track` sur le projet Cooked Supabase.

Prérequis :
  export SUPABASE_ACCESS_TOKEN='sbp_...'   # https://supabase.com/dashboard/account/tokens

Usage :
  python3 scripts/deploy_track.py
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

PROJECT_REF = "mxycmjkeotrycyneacje"
FUNCTION_SLUG = "track"
ROOT = Path(__file__).resolve().parent.parent
FUNCTION_DIR = ROOT / "supabase" / "functions" / "track"
INDEX = FUNCTION_DIR / "index.ts"
SHARED_CANONICAL = ROOT / "supabase" / "functions" / "_shared" / "canonical_path.ts"


def main() -> None:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        sys.exit(
            "ERROR: SUPABASE_ACCESS_TOKEN manquant.\n"
            "Crée un token sur https://supabase.com/dashboard/account/tokens\n"
            "puis : export SUPABASE_ACCESS_TOKEN='sbp_...'"
        )

    content = INDEX.read_text(encoding="utf-8")
    shared = SHARED_CANONICAL.read_text(encoding="utf-8")
    if "canonicalPath" not in content:
        sys.exit("ERROR: index.ts ne contient pas canonicalPath — mauvais fichier ?")
    if "PLACEHOLDER" in content or "FROM_FILE" in content:
        sys.exit("ERROR: index.ts contient un placeholder — abort.")

    body = json.dumps(
        {
            "slug": FUNCTION_SLUG,
            "name": FUNCTION_SLUG,
            "verify_jwt": False,
            "entrypoint_path": "index.ts",
            "import_map_path": None,
            "files": [
                {"name": "index.ts", "content": content},
                {"name": "../_shared/canonical_path.ts", "content": shared},
            ],
        }
    ).encode("utf-8")

    url = f"https://api.supabase.com/v1/projects/{PROJECT_REF}/functions/deploy"
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        sys.exit(f"Deploy failed HTTP {e.code}: {err}")

    version = result.get("version") or result.get("id") or "?"
    print(f"OK — track déployé (version/id: {version})")
    print("Vérifie : canonicalPath présent dans le code déployé.")


if __name__ == "__main__":
    main()
