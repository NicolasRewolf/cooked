"""Rapprochement quotidien Wix/Cooked : compteurs uniquement, jamais de PII.

API vérifiée le 20/10/2026 :
https://dev.wix.com/docs/api-reference/crm/forms/form-submissions/query-submissions-by-namespace
La réponse Wix contient les formulaires ; seuls id/date/statut sont examinés
en mémoire. Aucun contenu de formulaire, identifiant ou corps HTTP n'est loggé.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

import requests

from cooked.store import SupabaseStore
from cooked.wix.taxonomy import WIX_SITE_ID_DEFAULT

PARIS = ZoneInfo("Europe/Paris")
SUBMISSIONS_URL = "https://www.wixapis.com/forms/v4/submissions/namespace/query"


def window_days(start: date, end: date) -> list[str]:
    length = (end - start).days + 1
    if not 1 <= length <= 93:
        raise ValueError("Période de rapprochement attendue : 1 à 93 jours")
    return [(start + timedelta(days=i)).isoformat() for i in range(length)]


def utc_bounds(start: date, end: date) -> tuple[str, str]:
    window_days(start, end)
    bounds = [
        datetime.combine(start, time(), PARIS),
        datetime.combine(end + timedelta(days=1), time(), PARIS),
    ]
    return tuple(d.astimezone(timezone.utc).isoformat() for d in bounds)


def wix_daily_counts(api_key: str, site_id: str, start: date, end: date, *, post=None) -> dict[str, int]:
    """Pagination complète, bornes vérifiées à nouveau côté client."""
    post = post or requests.post
    counts = dict.fromkeys(window_days(start, end), 0)
    lower, upper = utc_bounds(start, end)
    query = {
        "filter": {
            "$and": [
                {"namespace": {"$eq": "wix.form_app.form"}},
                {"status": {"$eq": "CONFIRMED"}},
                {"createdDate": {"$gte": lower}},
                {"createdDate": {"$lt": upper}},
            ],
        },
        "sort": [{"fieldName": "createdDate", "order": "ASC"}],
        "cursorPaging": {"limit": 100},
    }
    seen_ids: set[str] = set()
    seen_cursors: set[str] = set()
    for _ in range(1000):
        response = post(
            SUBMISSIONS_URL,
            headers={"Authorization": api_key, "wix-site-id": site_id},
            json={"query": query, "onlyYourOwn": False},
            timeout=60,
        )
        response.raise_for_status()
        data = response.json()
        if not isinstance(data, dict) or not isinstance(data.get("submissions"), list):
            raise ValueError("Réponse Wix invalide : submissions absentes")
        for row in data["submissions"]:
            if not isinstance(row, dict) or row.get("status") != "CONFIRMED":
                raise ValueError("Réponse Wix non conforme au statut demandé")
            ident = row.get("id")
            if not isinstance(ident, str) or not ident or ident in seen_ids:
                raise ValueError("Identifiant Wix absent ou doublon de pagination")
            stamp = datetime.fromisoformat(row["createdDate"].replace("Z", "+00:00"))
            if stamp.tzinfo is None:
                raise ValueError("Date Wix sans fuseau")
            day = stamp.astimezone(PARIS).date().isoformat()
            if day not in counts:
                raise ValueError("Soumission Wix hors période")
            seen_ids.add(ident)
            counts[day] += 1
        metadata = data.get("metadata", {})
        if metadata.get("hasNext") is False:
            return counts
        if metadata.get("hasNext") is not True:
            raise ValueError("Pagination Wix indéterminée")
        cursor = (metadata.get("cursors") or {}).get("next")
        if not isinstance(cursor, str) or not cursor or cursor in seen_cursors:
            raise ValueError("Pagination Wix interrompue ou cyclique")
        seen_cursors.add(cursor)
        # Contrat Wix : les pages suivantes utilisent le curseur sans
        # répéter filter/sort, qui sont déjà attachés au curseur.
        query = {"cursorPaging": {"limit": 100, "cursor": cursor}}
    raise ValueError("Pagination Wix dépasse la borne de sécurité")


def compare_counts(wix: dict[str, int], rows: list[dict]) -> dict:
    if not isinstance(rows, list):
        raise ValueError("Réponse Cooked invalide")
    cooked = {}
    for row in rows:
        day, count = row["day"], int(row["submissions"])
        if day not in wix or day in cooked or count < 0:
            raise ValueError("Réponse Cooked hors période ou dupliquée")
        cooked[day] = count
    if cooked.keys() != wix.keys():
        raise ValueError("Réponse Cooked incomplète")
    differences = [
        {"day": day, "wix": count, "cooked": cooked[day]}
        for day, count in wix.items() if count != cooked[day]
    ]
    return {
        "wix_forms": sum(wix.values()),
        "cooked_forms": sum(cooked.values()),
        "days": len(wix),
        "mismatched_days": len(differences),
        "differences": differences,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Rapprochement Wix/Cooked sans données personnelles")
    parser.add_argument("--days", type=int, default=28)
    parser.add_argument("--end-date", type=date.fromisoformat)
    args = parser.parse_args(argv)
    if not 1 <= args.days <= 93:
        parser.error("--days doit être compris entre 1 et 93")
    end = args.end_date or (datetime.now(PARIS).date() - timedelta(days=1))
    start = end - timedelta(days=args.days - 1)
    try:
        counts = wix_daily_counts(
            os.environ["WIX_API_KEY"],
            os.environ.get("WIX_SITE_ID", WIX_SITE_ID_DEFAULT),
            start, end,
        )
        store = SupabaseStore.from_env()
        rows = store.rpc("form_submission_counts_for_period", {
            "p_start": start.isoformat(), "p_end": end.isoformat(),
        }).data
        result = compare_counts(counts, rows)
        result.update({"start": start.isoformat(), "end": end.isoformat()})
        # Les logs GitHub Actions du dépôt sont publics : aucun volume de
        # prospects ni détail quotidien. Le diagnostic reste dans Supabase.
        print(json.dumps({
            "start": start.isoformat(),
            "end": end.isoformat(),
            "checked_days": result["days"],
            "matched": result["mismatched_days"] == 0,
        }, ensure_ascii=False))
        if result["mismatched_days"]:
            store.rpc("raise_cooked_alert", {
                "p_kind": "form_reconciliation_mismatch",
                "p_sev": "critical",
                "p_detail": (
                    f"Rapprochement formulaires {start:%d/%m/%Y}–{end:%d/%m/%Y} : "
                    f"Wix={result['wix_forms']}, Cooked={result['cooked_forms']}, "
                    f"{result['mismatched_days']} jour(s) discordant(s). "
                    "Vérifier Wix avant tout rattrapage ; aucun contenu personnel exporté."
                ),
            })
            return 1
        return 0
    except Exception as error:
        # Les erreurs des SDK peuvent inclure des corps HTTP sensibles.
        print(f"Rapprochement impossible ({type(error).__name__}) ; aucun résultat validé.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
