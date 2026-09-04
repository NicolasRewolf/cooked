#!/usr/bin/env python3
"""
SECIB → Cooked — ingestion des dossiers pour le pont prospects ↔ dossiers.

Pourquoi ce script existe
-------------------------
Décision produit du 10/08/2026 : Cooked rapproche EN CLAIR les prospects web
(nom/prénom/email/téléphone capturés par form-webhook v13 → crm_prospects)
des dossiers réellement ouverts / facturés dans SECIB. Ce script alimente le
côté SECIB du pont : la table `secib_dossiers` (RLS deny-all, service_role
uniquement). La vue `pont_prospects_dossiers` fait ensuite le matching en SQL
(email normalisé prioritaire, sinon téléphone E.164).

Discipline PII : on ne lit du DTO SECIB QUE l'identité de contact du premier
client (nom, prénom, email, téléphones) + les métadonnées dossier (dates,
matière, état facturable, facturation agrégée). Tout le reste — n° de
sécurité sociale, adresses, contenu du dossier — n'est JAMAIS lu ni stocké.

Deux modes :

    python3 scripts/secib_ingest.py probe  --days 120        # lecture seule, résumé masqué
    python3 scripts/secib_ingest.py ingest --days 120        # → secib_dossiers

`ingest` demande SUPABASE_SECRET_KEY (absente en local, posée en CI).

Auth SECIB
----------
Token OAuth client_credentials sur la passerelle api.secib.fr :
    POST https://api.secib.fr/forward/{GUID}/ApiToken
    (client_id, client_secret, grant_type=client_credentials) → bearer ~8 h.

Credentials résolus dans cet ordre :
  1. env : SECIB_CLIENT_ID / SECIB_CLIENT_SECRET / SECIB_CABINET_GUID (CI)
  2. fichier local ~/.claude/secib-credentials.json (JAMAIS committé)

`--secib-env` marque la colonne env de secib_dossiers : `test` = cabinet bac
à sable Septeo (défaut tant que le devis SECIB+ n'est pas signé), `prod` =
cabinet Plouton réel (changer aussi les credentials).

Pièges connus
-------------
* Dossier/Get : le POST avec body FiltreDossierApiDto fonctionne ; le GET
  avec query params filtreDate.* renvoie 400. Toujours le POST.
* Pagination par query param range=a-b, 50 max par page.
* Les dates SECIB sont naïves en heure locale cabinet (Europe/Paris).
* Le lien facture → dossier n'existe QUE dans ExportComptable/ExportFinancier
  (FactureExportApiDto.DossierCode + DossierMatiereId) — pas dans les DTOs
  Facture simples.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import requests

PARIS = ZoneInfo("Europe/Paris")
DEFAULT_CREDENTIALS = Path.home() / ".claude" / "secib-credentials.json"
API_BASE = "https://api.secib.fr/forward"
PAGE_SIZE = 50  # maximum accepté par l'API

# ---------------------------------------------------------------------------
# Normalisation — MIROIR STRICT des fonctions SQL cooked_normalize_email /
# cooked_normalize_phone_fr (migration 20260810082433_secib_pont_fondations ; v2 T-16 20260903).
# Toute évolution doit se faire des deux côtés — vecteurs partagés : contracts/normalize_vectors.json.
# ---------------------------------------------------------------------------


def normalize_email(raw: str | None) -> str | None:
    if not raw:
        return None
    out = re.sub(r"\s", "", raw).lower()
    return out or None


def normalize_phone_fr(raw: str | None) -> str | None:
    if not raw:
        return None
    d = re.sub(r"[^0-9]", "", raw)
    if not d:
        return None
    # T-16 (e-05) : « +33 (0)6 … » / « 00 33 (0)6 … » — le (0) après l'indicatif
    if d.startswith("00330") and len(d) == 14:
        return "+33" + d[5:]
    if d.startswith("330") and len(d) == 12:
        return "+33" + d[3:]
    if d.startswith("0033") and len(d) == 13:
        return "+33" + d[4:]
    if d.startswith("33") and len(d) == 11:
        return "+" + d
    if d.startswith("0") and len(d) == 10:
        return "+33" + d[1:]
    if 8 <= len(d) <= 15:
        return "+" + d
    return None


# ---------------------------------------------------------------------------
# Client API SECIB
# ---------------------------------------------------------------------------


def load_credentials() -> dict:
    cid = os.environ.get("SECIB_CLIENT_ID")
    secret = os.environ.get("SECIB_CLIENT_SECRET")
    guid = os.environ.get("SECIB_CABINET_GUID")
    if cid and secret and guid:
        return {"client_id": cid, "client_secret": secret, "cabinet_guid": guid}
    if DEFAULT_CREDENTIALS.exists():
        data = json.loads(DEFAULT_CREDENTIALS.read_text())
        if data.get("client_id") and data.get("client_secret") and data.get("cabinet_guid"):
            return data
    sys.exit(
        "ERROR: credentials SECIB introuvables — env SECIB_CLIENT_ID/"
        "SECIB_CLIENT_SECRET/SECIB_CABINET_GUID ou ~/.claude/secib-credentials.json"
    )


class SecibClient:
    def __init__(self, creds: dict) -> None:
        self.guid = creds["cabinet_guid"]
        self.base = f"{API_BASE}/{self.guid}/api/v1"
        resp = requests.post(
            f"{API_BASE}/{self.guid}/ApiToken",
            data={
                "client_id": creds["client_id"],
                "client_secret": creds["client_secret"],
                "grant_type": "client_credentials",
            },
            timeout=30,
        )
        resp.raise_for_status()
        self.session = requests.Session()
        self.session.headers["Authorization"] = "Bearer " + resp.json()["access_token"]

    def dossiers(self, date_from: date, date_to: date) -> list[dict]:
        """Tous les dossiers créés dans [date_from, date_to] (POST paginé)."""
        out: list[dict] = []
        start = 0
        while True:
            resp = self.session.post(
                f"{self.base}/Dossier/Get",
                params={"range": f"{start}-{start + PAGE_SIZE - 1}"},
                json={
                    "DateCreationDateDebut": date_from.isoformat(),
                    "DateCreationDateFin": date_to.isoformat(),
                },
                timeout=60,
            )
            resp.raise_for_status()
            page = resp.json()
            out.extend(page)
            if len(page) < PAGE_SIZE:
                return out
            start += PAGE_SIZE

    def export_financier(self, date_from: date, date_to: date) -> dict:
        resp = self.session.post(
            f"{self.base}/ExportComptable/ExportFinancier",
            json={
                "DateDebut": date_from.isoformat(),
                "DateFin": date_to.isoformat(),
                "Facture": True,
                "Reglement": False,
                "FraisFournisseur": False,
            },
            timeout=120,
        )
        resp.raise_for_status()
        return resp.json()


# ---------------------------------------------------------------------------
# Transformation DTO → row secib_dossiers
# ---------------------------------------------------------------------------


def paris_iso(naive: str | None) -> str | None:
    """Timestamp SECIB naïf (heure cabinet) → ISO tz-aware Europe/Paris."""
    if not naive:
        return None
    try:
        dt = datetime.fromisoformat(naive)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=PARIS)
    return dt.isoformat()


def dossier_row(d: dict, secib_env: str) -> dict | None:
    dossier_id = d.get("DossierId")
    if dossier_id is None:
        return None
    matiere = d.get("Matiere") or {}
    personne = (d.get("PremierClient") or {}).get("Personne") or {}

    # Discipline PII : UNIQUEMENT identité de contact — rien d'autre du DTO.
    emails = [e for e in [personne.get("Email")] if e]
    telephones = [t for t in [personne.get("Telephone"), personne.get("Portable")] if t]

    return {
        "env": secib_env,
        "dossier_id": dossier_id,
        "code": d.get("Code"),
        "date_creation": paris_iso(d.get("DateCreation")),
        "date_modification": paris_iso(d.get("DateModification")),
        "matiere_id": matiere.get("MatiereId"),
        "matiere_libelle": matiere.get("Libelle"),
        "etat_facturable": d.get("EtatFacturable"),
        "type_dossier": d.get("Type"),
        "is_archive": d.get("IsArchive"),
        "client_personne_id": personne.get("PersonneId"),
        "client_type": personne.get("TypePersonne"),
        "client_nom": personne.get("Nom"),
        "client_prenom": personne.get("Prenom"),
        "client_emails": emails,
        "client_telephones": telephones,
        "client_emails_norm": sorted({n for n in map(normalize_email, emails) if n}),
        "client_tels_norm": sorted({n for n in map(normalize_phone_fr, telephones) if n}),
        "synced_at": datetime.now(tz=PARIS).isoformat(),
    }


def billing_by_code(export: dict) -> dict[str, dict]:
    """Agrège l'export financier par DossierCode : total HT + bornes de dates."""
    agg: dict[str, dict] = defaultdict(lambda: {"total_ht": 0.0, "dates": []})
    for f in export.get("ListFactureExport") or []:
        code = f.get("DossierCode")
        if not code:
            continue
        ht = f.get("MontantHt") or 0.0
        agg[code]["total_ht"] += -ht if f.get("IsAvoir") else ht
        day = (f.get("Date") or "")[:10]
        if day:
            agg[code]["dates"].append(day)
    return dict(agg)


def apply_billing(rows: list[dict], billing: dict[str, dict]) -> int:
    hits = 0
    for row in rows:
        b = billing.get(row.get("code") or "")
        if not b:
            continue
        hits += 1
        row["facture_total_ht"] = round(b["total_ht"], 2)
        if b["dates"]:
            row["premiere_facture"] = min(b["dates"])
            row["derniere_facture"] = max(b["dates"])
    return hits


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------


def fetch_rows(client: SecibClient, days: int, secib_env: str) -> list[dict]:
    date_to = datetime.now(tz=PARIS).date()
    date_from = date_to - timedelta(days=days)
    print(f"Fenêtre dossiers : {date_from.isoformat()} → {date_to.isoformat()} (env={secib_env})")
    dossiers = client.dossiers(date_from, date_to)
    rows = [r for r in (dossier_row(d, secib_env) for d in dossiers) if r]
    print(f"Dossiers reçus : {len(dossiers)} — rows construites : {len(rows)}")

    export = client.export_financier(date_from, date_to)
    billing = billing_by_code(export)
    hits = apply_billing(rows, billing)
    print(f"Facturation : {len(billing)} codes facturés dans la fenêtre, {hits} dossiers enrichis")
    return rows


def cmd_probe(client: SecibClient, days: int, secib_env: str) -> None:
    rows = fetch_rows(client, days, secib_env)
    with_email = sum(1 for r in rows if r["client_emails_norm"])
    with_tel = sum(1 for r in rows if r["client_tels_norm"])
    with_any = sum(1 for r in rows if r["client_emails_norm"] or r["client_tels_norm"])
    facture = sum(1 for r in rows if r.get("facture_total_ht"))
    matieres = defaultdict(int)
    for r in rows:
        matieres[r["matiere_libelle"] or "(sans matière)"] += 1
    print()
    print(f"Clés de matching : email {with_email}/{len(rows)}, téléphone {with_tel}/{len(rows)}, "
          f"au moins une {with_any}/{len(rows)}")
    print(f"Dossiers avec facturation dans la fenêtre : {facture}")
    print("Par matière :", dict(sorted(matieres.items(), key=lambda kv: -kv[1])))
    print()
    print("(probe = lecture seule, aucune écriture Supabase)")


def cmd_ingest(client: SecibClient, days: int, secib_env: str) -> None:
    from cooked.store import SupabaseStore  # import tardif : exige supabase-py

    rows = fetch_rows(client, days, secib_env)
    if not rows:
        print("Aucune row à écrire.")
        return
    store = SupabaseStore.from_env()
    store.upsert_batches("secib_dossiers", rows, on_conflict="env,dossier_id")
    print(f"Upsert OK : {len(rows)} rows → secib_dossiers (env={secib_env})")


def main() -> None:
    parser = argparse.ArgumentParser(description="SECIB → secib_dossiers (pont prospects)")
    parser.add_argument("mode", choices=["probe", "ingest"])
    parser.add_argument("--days", type=int, default=120,
                        help="fenêtre de création des dossiers (défaut 120)")
    parser.add_argument("--secib-env", choices=["test", "prod"], default="test",
                        help="valeur de la colonne env (test = bac à sable Septeo)")
    args = parser.parse_args()

    client = SecibClient(load_credentials())
    if args.mode == "probe":
        cmd_probe(client, args.days, args.secib_env)
    else:
        cmd_ingest(client, args.days, args.secib_env)


if __name__ == "__main__":
    main()
