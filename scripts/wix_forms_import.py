#!/usr/bin/env python3
"""
Import de l'export CSV Wix Forms → crm_prospects (pont SECIB).

Usage :
    python3 scripts/wix_forms_import.py --csv "/chemin/vers/export.csv" [--dry-run]

Charge l'historique des soumissions de formulaires (export manuel Wix :
Formulaires → Soumissions → Exporter) dans `crm_prospects`, pour que le
rapprochement SECIB couvre tout l'historique et pas seulement les captures
du webhook v13 (actives depuis le 10/08/2026).

Règles — MIROIR des garde-fous de form-webhook v13 (_shared/form_row.ts) :
  * identité uniquement : nom, prénom, email, téléphone, objet, page, UTM.
    Le Message (texte libre) n'est JAMAIS lu au-delà du parsing CSV.
  * email doit contenir @ ; téléphone 8-15 chiffres ; nom/prénom jamais un
    email recopié ; caps de longueur identiques.
  * cooked_aid/sid validés par la même regex que le tracker.

Idempotence : wix_submission_id = 'wiximport-' + sha1(date|email|tel|nom|prenom).
Les empreintes déjà en base sont sautées → rejouable sur un export plus frais
sans doublon ni écrasement (INSERT only, jamais d'UPDATE).

Clé Supabase : env SUPABASE_SECRET_KEY, sinon dashboard/.env.local.
Le CSV reste hors repo (chemin local) et n'est jamais committé.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from secib_ingest import normalize_email, normalize_phone_fr  # noqa: E402  (miroir SQL, réutilisé)

ISO_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")
ID_RE = re.compile(r"^[a-zA-Z0-9_-]{8,128}$")
FORM_ID = "Prise de contact site-web"
BATCH = 200


def cap(v: str | None, n: int) -> str | None:
    v = (v or "").strip()
    return v[:n] if v else None


def clean_email(v: str | None) -> str | None:
    v = cap(v, 200)
    return v if v and "@" in v else None


def clean_phone(v: str | None) -> str | None:
    v = cap(v, 50)
    if not v:
        return None
    digits = re.sub(r"\D", "", v)
    return v if 8 <= len(digits) <= 15 else None


def clean_name(v: str | None) -> str | None:
    v = cap(v, 150)
    return None if (v and "@" in v) else v


def clean_id(v: str | None) -> str | None:
    v = (v or "").strip()
    return v if ID_RE.match(v) else None


def clean_path(v: str | None) -> str | None:
    v = (v or "").strip()
    if not v:
        return None
    v = re.sub(r"^https?://[^/]+", "", v)
    v = v.split("?")[0]
    if not v.startswith("/"):
        v = "/" + v
    return cap(v, 500)


def load_secret_key() -> tuple[str, str]:
    url = os.environ.get("SUPABASE_URL", "https://mxycmjkeotrycyneacje.supabase.co")
    key = os.environ.get("SUPABASE_SECRET_KEY")
    if not key:
        env_local = ROOT / "dashboard" / ".env.local"
        if env_local.exists():
            for line in env_local.read_text().splitlines():
                if line.startswith("SUPABASE_SECRET_KEY="):
                    key = line.split("=", 1)[1].strip()
    if not key:
        sys.exit("ERROR: SUPABASE_SECRET_KEY introuvable (env ou dashboard/.env.local)")
    return url, key


def already_captured(row: dict, webhook_rows: list[tuple[str | None, str]], tolerance_s: int = 120) -> bool:
    """T-16 (e-04) : vrai si le webhook a déjà capturé ce prospect (même email normalisé, à ± tolerance_s).

    L'import CSV ne connaissait que ses propres lignes (`wiximport-…`) : rejouer un export qui
    chevauche la période où le webhook tournait dupliquait les prospects (2 doublons email/minute
    en base le 03/09/2026). `webhook_rows` = [(email_norm, occurred_at ISO)] des lignes non importées.
    """
    email_norm = normalize_email(row.get("email"))
    if not email_norm:
        return False

    def _ts(value: str):
        # Les dates naïves (export CSV) sont stockées telles quelles en timestamptz → UTC.
        d = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return d if d.tzinfo else d.replace(tzinfo=timezone.utc)

    try:
        t = _ts(row["occurred_at"])
    except ValueError:
        return False
    for e, ts in webhook_rows:
        if e != email_norm:
            continue
        try:
            u = _ts(ts)
        except ValueError:
            continue
        if abs((u - t).total_seconds()) <= tolerance_s:
            return True
    return False


def build_row(r: dict) -> dict | None:
    date = (r.get("Date d'envoi") or "").strip()
    if not ISO_RE.match(date):
        return None
    nom = clean_name(r.get("Nom"))
    prenom = clean_name(r.get("Prénom"))
    email = clean_email(r.get("Email"))
    telephone = clean_phone(r.get("Téléphone"))
    if not (nom or prenom or email or telephone):
        return None
    fingerprint = hashlib.sha1(
        "|".join([
            date,
            (email or "").lower(),
            telephone or "",
            nom or "",
            prenom or "",
        ]).encode()
    ).hexdigest()[:20]
    return {
        "occurred_at": date,
        "source": "form",
        "form_id": FORM_ID,
        "wix_submission_id": "wiximport-" + fingerprint,
        "objet": cap(r.get("Objet de ma demande"), 200),
        "page_source_path": clean_path(r.get("page_source")),
        "cooked_aid": clean_id(r.get("cooked_aid")),
        "cooked_sid": clean_id(r.get("cooked_sid")),
        "nom": nom,
        "prenom": prenom,
        "email": email,
        "telephone": telephone,
        "utm_source": cap(r.get("utm_source"), 100),
        "utm_medium": cap(r.get("utm_medium"), 100),
        "utm_term": cap(r.get("utm_term"), 100),
        "fields_keys": [],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Export Wix Forms → crm_prospects")
    parser.add_argument("--csv", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    with open(args.csv, newline="", encoding="utf-8-sig") as f:
        raw = list(csv.DictReader(f))

    rows = [row for row in (build_row(r) for r in raw) if row]
    skipped = len(raw) - len(rows)
    tel_norm_ok = sum(1 for row in rows if normalize_phone_fr(row["telephone"]))
    years = Counter(row["occurred_at"][:4] for row in rows)
    print(f"CSV : {len(raw)} lignes → {len(rows)} rows importables ({skipped} sans date/identité)")
    print(f"  emails : {sum(1 for r in rows if r['email'])} | téléphones : "
          f"{sum(1 for r in rows if r['telephone'])} (normalisables E.164 : {tel_norm_ok})")
    print(f"  cooked_aid : {sum(1 for r in rows if r['cooked_aid'])} | utm_source : "
          f"{sum(1 for r in rows if r['utm_source'])}")
    print(f"  par année : {dict(sorted(years.items()))}")

    if args.dry_run:
        print("\n(dry-run — aucune écriture)")
        return

    from supabase import create_client

    url, key = load_secret_key()
    client = create_client(url, key)

    existing = set()
    start = 0
    while True:
        page = (
            client.table("crm_prospects")
            .select("wix_submission_id")
            .like("wix_submission_id", "wiximport-%")
            .range(start, start + 999)
            .execute()
            .data
        )
        existing.update(p["wix_submission_id"] for p in page)
        if len(page) < 1000:
            break
        start += 1000

    # T-16 (e-04) : les lignes capturées par le webhook (pas d'id wiximport-) comptent aussi.
    webhook_rows: list[tuple[str | None, str]] = []
    start = 0
    while True:
        page = (
            client.table("crm_prospects")
            .select("email_norm,occurred_at")
            .not_.like("wix_submission_id", "wiximport-%")
            .range(start, start + 999)
            .execute()
            .data
        )
        webhook_rows.extend((p["email_norm"], p["occurred_at"]) for p in page)
        if len(page) < 1000:
            break
        start += 1000

    todo = [r for r in rows if r["wix_submission_id"] not in existing and not already_captured(r, webhook_rows)]
    print(f"\nDéjà en base : {len(existing)} imports + {len(webhook_rows)} webhook — à insérer : {len(todo)}")
    for i in range(0, len(todo), BATCH):
        chunk = todo[i : i + BATCH]
        client.table("crm_prospects").insert(chunk).execute()
        print(f"  batch {i // BATCH + 1} : {len(chunk)} rows OK")
    print(f"\nImport terminé : {len(todo)} prospects historiques dans crm_prospects.")


if __name__ == "__main__":
    main()
