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

Prototype de test uniquement — deux modes :

    python3 scripts/secib_ingest.py probe  --days 120        # lecture seule, résumé borné
    python3 scripts/secib_ingest.py ingest --days 120        # métadonnées test uniquement

`ingest` demande SUPABASE_SECRET_KEY (absente en local, posée en CI).

Auth SECIB
----------
Token OAuth client_credentials sur la passerelle api.secib.fr :
    POST https://api.secib.fr/forward/{GUID}/ApiToken
    (client_id, client_secret, grant_type=client_credentials) → bearer ~8 h.

Credentials résolus dans cet ordre :
  1. env : SECIB_CLIENT_ID / SECIB_CLIENT_SECRET / SECIB_CABINET_GUID (CI)
  2. fichier local ~/.claude/secib-credentials.json (JAMAIS committé)

`--secib-env prod` est refusé AVANT chargement des credentials/appels réseau.
L'API vérifiée filtre les créations, pas les dernières modifications. Un
export financier borné ne constitue pas le cumul d'un dossier. Les champs
facture_total_ht / premiere_facture / derniere_facture sont donc écrits NULL
sur les lignes test relues ; le résumé financier reste réservé à `probe`.
Les dossiers plus anciens hors fenêtre ne sont pas synchronisés. Avant toute
activation prod, il faut valider une reprise complète des dossiers modifiés
et de la facturation, avec périmètre et complétude contrôlables.

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
MAX_DOSSIER_PAGES = 1000  # garde-fou : un dépassement échoue, jamais un succès partiel


class SecibResponseError(ValueError):
    """Réponse incompatible avec le contrat vérifié ; ne jamais inclure le DTO/PII."""


def require_test_environment(secib_env: str) -> None:
    if secib_env != "test":
        raise ValueError(
            "SECIB prod bloqué : synchronisation des modifications et cumul de "
            "facturation non validés. Ce prototype accepte uniquement env=test."
        )


def creation_window(days: int, today: date | None = None) -> tuple[date, date]:
    if days < 1:
        raise ValueError("--days doit être strictement positif")
    date_to = today or datetime.now(tz=PARIS).date()
    # `days` jours calendaires inclusifs ; aujourd'hui peut être incomplet.
    return date_to - timedelta(days=days - 1), date_to

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
        """Créations dans [date_from, date_to] ; pas une synchronisation des modifications."""
        out: list[dict] = []
        seen_ids: set[int | str] = set()
        for page_number in range(MAX_DOSSIER_PAGES):
            start = page_number * PAGE_SIZE
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
            if not isinstance(page, list) or len(page) > PAGE_SIZE:
                raise SecibResponseError("Dossier/Get : forme ou taille de page inattendue")
            for item in page:
                dossier_id = item.get("DossierId") if isinstance(item, dict) else None
                if isinstance(dossier_id, bool) or not isinstance(dossier_id, (int, str)) or dossier_id == "":
                    raise SecibResponseError("Dossier/Get : identifiant absent ou invalide")
                if dossier_id in seen_ids:
                    raise SecibResponseError("Dossier/Get : pagination répétée ou incohérente")
                seen_ids.add(dossier_id)
            out.extend(page)
            if len(page) < PAGE_SIZE:
                return out
        raise SecibResponseError("Dossier/Get : plafond de pagination atteint, résultat incomplet")

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
        # Une fenêtre de factures n'est ni un cumul ni la première/dernière
        # facture d'un dossier. NULL évite aussi de conserver un ancien extrait
        # trompeur lors de la relecture d'une ligne du bac à sable.
        "facture_total_ht": None,
        "premiere_facture": None,
        "derniere_facture": None,
        "synced_at": datetime.now(tz=PARIS).isoformat(),
    }


def billing_codes(export: dict) -> set[str]:
    """Codes renseignés de l'EXTRAIT, pour probe uniquement ; aucun montant cumulé."""
    if not isinstance(export, dict) or not isinstance(export.get("ListFactureExport"), list):
        raise SecibResponseError("ExportFinancier : liste des factures absente ou invalide")
    codes: set[str] = set()
    for f in export["ListFactureExport"]:
        if not isinstance(f, dict):
            raise SecibResponseError("ExportFinancier : facture invalide")
        code = f.get("DossierCode")
        if not code:
            continue
        if not isinstance(code, str):
            raise SecibResponseError("ExportFinancier : code dossier invalide")
        codes.add(code)
    return codes


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------


def fetch_rows(client: SecibClient, days: int, secib_env: str, *, today: date | None = None) -> list[dict]:
    require_test_environment(secib_env)
    date_from, date_to = creation_window(days, today)
    print(f"Fenêtre de CRÉATION : {date_from.isoformat()} → {date_to.isoformat()} inclus (env=test)")
    print("Métadonnées partielles : anciens dossiers modifiés hors fenêtre non relus.")
    dossiers = client.dossiers(date_from, date_to)
    rows = [r for r in (dossier_row(d, secib_env) for d in dossiers) if r]
    print(f"Dossiers reçus : {len(dossiers)} — rows construites : {len(rows)}")

    return rows


def cmd_probe(client: SecibClient, days: int, secib_env: str) -> None:
    require_test_environment(secib_env)
    date_from, date_to = creation_window(days)
    rows = fetch_rows(client, days, secib_env, today=date_to)
    billing = billing_codes(client.export_financier(date_from, date_to))
    current_codes = {r["code"] for r in rows if r["code"]}
    in_window = len(current_codes.intersection(billing))
    outside_window = len(set(billing).difference(current_codes))
    with_email = sum(1 for r in rows if r["client_emails_norm"])
    with_tel = sum(1 for r in rows if r["client_tels_norm"])
    with_any = sum(1 for r in rows if r["client_emails_norm"] or r["client_tels_norm"])
    matieres = defaultdict(int)
    for r in rows:
        matieres[r["matiere_libelle"] or "(sans matière)"] += 1
    print()
    print(f"Clés de matching : email {with_email}/{len(rows)}, téléphone {with_tel}/{len(rows)}, "
          f"au moins une {with_any}/{len(rows)}")
    print(f"Extrait financier : {date_from.isoformat()} → {date_to.isoformat()} inclus "
          "(journée courante potentiellement partielle ; complétude de l'export non certifiée)")
    print(f"Codes renseignés facturés dans cet extrait : {len(billing)} ; "
          f"{in_window} dans les créations relues ; {outside_window} hors de ces créations.")
    print("Aucun cumul ni première/dernière facture d'un dossier déduit de cet extrait.")
    print("Par matière :", dict(sorted(matieres.items(), key=lambda kv: -kv[1])))
    print()
    print("(probe = lecture seule, aucune écriture Supabase)")


def cmd_ingest(client: SecibClient, days: int, secib_env: str) -> None:
    require_test_environment(secib_env)
    from cooked.store import SupabaseStore  # import tardif : exige supabase-py

    rows = fetch_rows(client, days, secib_env)
    if not rows:
        print("Aucune row à écrire.")
        return
    store = SupabaseStore.from_env()
    store.upsert_batches("secib_dossiers", rows, on_conflict="env,dossier_id")
    print(f"Upsert métadonnées test : {len(rows)} rows → secib_dossiers (env=test). "
          "Facturation cumulée inconnue (NULL) ; aucune synchronisation des anciens dossiers.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Prototype SECIB test : créations récentes, facturation cumulée inconnue")
    parser.add_argument("mode", choices=["probe", "ingest"])
    parser.add_argument("--days", type=int, default=120,
                        help="jours calendaires de création, aujourd'hui inclus (défaut 120)")
    parser.add_argument("--secib-env", choices=["test", "prod"], default="test",
                        help="test uniquement ; prod refusé tant que la synchronisation complète n'est pas validée")
    args = parser.parse_args()

    try:
        require_test_environment(args.secib_env)
        creation_window(args.days)
    except ValueError as exc:
        parser.error(str(exc))
    client = SecibClient(load_credentials())
    if args.mode == "probe":
        cmd_probe(client, args.days, args.secib_env)
    else:
        cmd_ingest(client, args.days, args.secib_env)


if __name__ == "__main__":
    main()
