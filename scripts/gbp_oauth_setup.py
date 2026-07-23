#!/usr/bin/env python3
"""
Setup one-shot OAuth pour Google Business Profile → Cooked.

Prérequis (Google Cloud Console, projet plouton-472207 ou dédié) :
  1. Activer les APIs :
       - My Business Account Management API
       - My Business Business Information API
       - Business Profile Performance API
  2. Demander l'accès GBP si le quota est à 0
     (formulaire Google « Business Profile APIs » — délai jours/semaines).
  3. OAuth consent screen (External ou Internal) + scope
     https://www.googleapis.com/auth/business.manage
  4. Créer des credentials OAuth « Application de bureau » → télécharger
     le JSON client (client_id + client_secret).

Usage :
  python3 scripts/gbp_oauth_setup.py --client-secrets ~/Downloads/client_secret_….json

Le navigateur s'ouvre ; se connecter avec le Google Account qui GÈRE la
fiche du cabinet. Un fichier ~/.claude/gbp-token.json est écrit (hors repo).

Ensuite :
  python3 scripts/gbp_ingest.py --list-locations
  python3 scripts/gbp_ingest.py --days 365
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = ["https://www.googleapis.com/auth/business.manage"]
DEFAULT_OUT = Path.home() / ".claude" / "gbp-token.json"


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Autorisation OAuth one-shot pour GBP → Cooked"
    )
    parser.add_argument(
        "--client-secrets",
        required=True,
        type=Path,
        help="JSON OAuth Desktop téléchargé depuis Google Cloud Console",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help=f"Fichier token de sortie (défaut: {DEFAULT_OUT})",
    )
    args = parser.parse_args(argv)

    secrets = args.client_secrets.expanduser()
    if not secrets.is_file():
        sys.exit(f"ERROR: fichier introuvable: {secrets}")

    flow = InstalledAppFlow.from_client_secrets_file(str(secrets), SCOPES)
    creds = flow.run_local_server(port=0, prompt="consent")

    if not creds.refresh_token:
        sys.exit(
            "ERROR: pas de refresh_token reçu. Révoquer l'accès de l'appli "
            "sur https://myaccount.google.com/permissions puis relancer "
            "avec prompt=consent."
        )

    # Extraire client_id/secret depuis le fichier secrets (formats web/installed).
    raw = json.loads(secrets.read_text(encoding="utf-8"))
    block = raw.get("installed") or raw.get("web") or {}
    out = {
        "client_id": block.get("client_id") or creds.client_id,
        "client_secret": block.get("client_secret") or creds.client_secret,
        "refresh_token": creds.refresh_token,
        "token_uri": creds.token_uri or "https://oauth2.googleapis.com/token",
        "scopes": list(SCOPES),
    }

    dest = args.out.expanduser()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    dest.chmod(0o600)

    print(f"OK — token écrit dans {dest}")
    print("Prochaine étape : python3 scripts/gbp_ingest.py --list-locations")
    print()
    print("Pour GitHub Actions, poser ces secrets (valeurs du JSON) :")
    print("  GBP_OAUTH_CLIENT_ID")
    print("  GBP_OAUTH_CLIENT_SECRET")
    print("  GBP_OAUTH_REFRESH_TOKEN")


if __name__ == "__main__":
    main()
