#!/usr/bin/env python3
"""
Google Business Profile → Cooked — ÉTAPE 1 : reconnaissance (lecture seule).

Pourquoi ce script existe
-------------------------
Le tracker ne verra jamais un appel passé depuis la fiche Google : le
composeur s'ouvre sur le téléphone, pas sur le site. C'est l'angle mort
GMB (B3), assumé le 28/07/2026 après le refus du numéro traçable.
L'API Business Profile Performance donne `CALL_CLICKS` par jour SANS
toucher à la fiche et SANS numéro de tracking — elle ferme l'angle mort
par le seul côté qui restait ouvert.

Deux modes, tous deux en lecture seule et SANS écriture Supabase. La mise
en base viendra après validation (méthodo CLAUDE.md : itératif strict
avant scale) :

    python3 scripts/gbp_ingest.py discover
    python3 scripts/gbp_ingest.py probe --days 30

Auth
----
Les APIs Business Profile n'acceptent PAS les comptes de service —
contrairement à l'ingest GSC. Il faut un consentement OAuth utilisateur,
une fois, avec un compte qui gère la fiche. Deux voies, essayées dans
cet ordre :

  1. ADC gcloud (le plus simple, rien à télécharger) :
         gcloud auth application-default login \\
             --scopes=https://www.googleapis.com/auth/business.manage
     → credentials dans ~/.config/gcloud/application_default_credentials.json

  2. Client OAuth téléchargé depuis la console, si l'ADC est refusé :
         client OAuth  : ~/.claude/gbp-oauth-client.json  (JAMAIS committé)
         refresh token : ~/.claude/gbp-token.json         (JAMAIS committé)
     Surchargeables via GBP_CLIENT_SECRETS_PATH / GBP_TOKEN_PATH.

En CI (GitHub Actions), c'est la voie 2 qui sert : le refresh token est
posé en secret, l'ADC gcloud n'y existe pas.

Timezone
--------
L'API renvoie des jours calendaires dans le fuseau de l'établissement
(Europe/Paris ici) — donc déjà alignés sur la règle Paris du projet.
À confirmer au premier recoupement avec `WEBSITE_CLICKS` vs les entrées
`utm_source=gmb` de events_human.
"""
from __future__ import annotations

import argparse
import os
import sys
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

import google.auth
from google.auth.exceptions import DefaultCredentialsError
from google.auth.transport.requests import AuthorizedSession, Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = ["https://www.googleapis.com/auth/business.manage"]

DEFAULT_CLIENT_SECRETS = Path.home() / ".claude" / "gbp-oauth-client.json"
DEFAULT_TOKEN = Path.home() / ".claude" / "gbp-token.json"

ACCOUNTS_API = "https://mybusinessaccountmanagement.googleapis.com/v1"
INFO_API = "https://mybusinessbusinessinformation.googleapis.com/v1"
PERF_API = "https://businessprofileperformance.googleapis.com/v1"

LOCATION_READ_MASK = "name,title,storefrontAddress,websiteUri,phoneNumbers"

# Ordre d'affichage : le macro d'abord (c'est la raison d'être du chantier),
# la visibilité ensuite.
DAILY_METRICS = (
    "CALL_CLICKS",
    "WEBSITE_CLICKS",
    "BUSINESS_DIRECTION_REQUESTS",
    "BUSINESS_CONVERSATIONS",
    "BUSINESS_BOOKINGS",
    "BUSINESS_IMPRESSIONS_MOBILE_SEARCH",
    "BUSINESS_IMPRESSIONS_MOBILE_MAPS",
    "BUSINESS_IMPRESSIONS_DESKTOP_SEARCH",
    "BUSINESS_IMPRESSIONS_DESKTOP_MAPS",
)


def fr(d: date) -> str:
    """JJ/MM/AAAA — règle d'affichage du projet."""
    return d.strftime("%d/%m/%Y")


# --------------------------------------------------------------------------
# Auth
# --------------------------------------------------------------------------


def _path_from_env(var: str, default: Path) -> Path:
    return Path(os.environ.get(var, str(default))).expanduser()


def _creds_from_adc() -> Credentials | None:
    """Credentials posées par `gcloud auth application-default login`.

    Voie préférée : aucun fichier à télécharger depuis la console. On exige
    le scope business.manage — si gcloud a été lancé sans, on retombe sur la
    voie 2 plutôt que d'échouer en 403 plus loin.
    """
    try:
        creds, _ = google.auth.default(scopes=SCOPES)
    except DefaultCredentialsError:
        return None

    granted = set(getattr(creds, "scopes", None) or [])
    if granted and not set(SCOPES) <= granted:
        return None
    return creds


def authorized_session() -> AuthorizedSession:
    creds = _creds_from_adc()
    if creds:
        return AuthorizedSession(creds)

    token_path = _path_from_env("GBP_TOKEN_PATH", DEFAULT_TOKEN)
    file_creds: Credentials | None = None

    if token_path.is_file():
        file_creds = Credentials.from_authorized_user_file(str(token_path), SCOPES)
        if file_creds and file_creds.expired and file_creds.refresh_token:
            file_creds.refresh(Request())

    if not file_creds or not file_creds.valid:
        client_path = _path_from_env("GBP_CLIENT_SECRETS_PATH", DEFAULT_CLIENT_SECRETS)
        if not client_path.is_file():
            sys.exit(
                "ERROR: aucune credential utilisable.\n\n"
                "  Voie 1 (la plus simple) :\n"
                "    gcloud auth application-default login \\\n"
                "        --scopes=https://www.googleapis.com/auth/business.manage\n\n"
                f"  Voie 2 : client OAuth téléchargé, attendu ici : {client_path}\n"
                "    (Ne jamais le committer : il vit hors du repo, dans ~/.claude/.)"
            )
        flow = InstalledAppFlow.from_client_secrets_file(str(client_path), SCOPES)
        # prompt=consent : force la délivrance d'un refresh_token même si un
        # consentement existe déjà pour ce client.
        file_creds = flow.run_local_server(port=0, prompt="consent")
        token_path.parent.mkdir(parents=True, exist_ok=True)
        token_path.write_text(file_creds.to_json())
        token_path.chmod(0o600)
        print(f"→ refresh token enregistré : {token_path}\n")

    return AuthorizedSession(file_creds)


def _get(session: AuthorizedSession, url: str, params=None) -> dict:
    resp = session.get(url, params=params, timeout=60)
    if resp.status_code >= 400:
        sys.exit(f"ERROR {resp.status_code} sur {url}\n{resp.text[:1000]}")
    return resp.json()


def _paged(session: AuthorizedSession, url: str, params: dict, key: str) -> list[dict]:
    out: list[dict] = []
    page_token = None
    while True:
        p = dict(params)
        if page_token:
            p["pageToken"] = page_token
        data = _get(session, url, p)
        out.extend(data.get(key, []))
        page_token = data.get("nextPageToken")
        if not page_token:
            return out


# --------------------------------------------------------------------------
# Découverte comptes / fiches
# --------------------------------------------------------------------------


def list_accounts(session: AuthorizedSession) -> list[dict]:
    return _paged(session, f"{ACCOUNTS_API}/accounts", {"pageSize": 20}, "accounts")


def list_locations(session: AuthorizedSession, account: str) -> list[dict]:
    return _paged(
        session,
        f"{INFO_API}/{account}/locations",
        {"readMask": LOCATION_READ_MASK, "pageSize": 100},
        "locations",
    )


def resolve_locations(session: AuthorizedSession) -> list[tuple[str, dict]]:
    """[(account, location), …] sur tous les comptes accessibles."""
    found: list[tuple[str, dict]] = []
    for account in list_accounts(session):
        name = account.get("name", "")
        for loc in list_locations(session, name):
            found.append((name, loc))
    return found


# --------------------------------------------------------------------------
# Performance
# --------------------------------------------------------------------------


def fetch_daily(
    session: AuthorizedSession,
    location: str,
    start: date,
    end: date,
    metrics: tuple[str, ...] = DAILY_METRICS,
) -> dict[date, dict[str, int]]:
    params: list[tuple[str, object]] = [("dailyMetrics", m) for m in metrics]
    params += [
        ("dailyRange.start_date.year", start.year),
        ("dailyRange.start_date.month", start.month),
        ("dailyRange.start_date.day", start.day),
        ("dailyRange.end_date.year", end.year),
        ("dailyRange.end_date.month", end.month),
        ("dailyRange.end_date.day", end.day),
    ]
    data = _get(
        session, f"{PERF_API}/{location}:fetchMultiDailyMetricsTimeSeries", params
    )

    rows: dict[date, dict[str, int]] = defaultdict(dict)
    for multi in data.get("multiDailyMetricTimeSeries", []):
        for series in multi.get("dailyMetricTimeSeries", []):
            metric = series.get("dailyMetric", "?")
            for dv in series.get("timeSeries", {}).get("datedValues", []):
                d = dv.get("date", {})
                if not d.get("year"):
                    continue
                day = date(d["year"], d.get("month", 1), d.get("day", 1))
                # `value` est absent quand la valeur vaut 0 (int64 sérialisé
                # en string quand il est présent).
                rows[day][metric] = int(dv.get("value", 0))
    return rows


# --------------------------------------------------------------------------
# Commandes
# --------------------------------------------------------------------------


def cmd_discover(_args) -> None:
    session = authorized_session()
    accounts = list_accounts(session)
    if not accounts:
        sys.exit(
            "Aucun compte Business Profile accessible avec ce compte Google.\n"
            "  → la fiche du cabinet est gérée par un autre compte : refaire le\n"
            "    consentement avec celui-là (supprimer ~/.claude/gbp-token.json),\n"
            "    ou s'y faire ajouter comme gestionnaire."
        )

    print(f"{len(accounts)} compte(s) accessible(s) :\n")
    total_loc = 0
    for account in accounts:
        print(f"  {account.get('name')}  —  {account.get('accountName', '?')}"
              f"  [{account.get('type', '?')}]")
        locations = list_locations(session, account.get("name", ""))
        total_loc += len(locations)
        for loc in locations:
            addr = loc.get("storefrontAddress", {})
            city = " ".join(addr.get("addressLines", []) or []) or "?"
            print(f"      └─ {loc.get('name')}  «{loc.get('title', '?')}»")
            print(f"         {city}, {addr.get('locality', '?')}"
                  f"  |  {loc.get('websiteUri', 'pas de site')}")
        if not locations:
            print("      └─ (aucune fiche)")
        print()

    print(f"→ {total_loc} fiche(s) au total.")
    if total_loc:
        first = resolve_locations(session)[0][1].get("name")
        print(f"→ Étape suivante : python3 scripts/gbp_ingest.py probe --location {first}")


def cmd_probe(args) -> None:
    session = authorized_session()

    location = args.location
    if not location:
        found = resolve_locations(session)
        if len(found) != 1:
            sys.exit(
                f"{len(found)} fiche(s) trouvée(s) — préciser --location locations/XXXX "
                "(voir `discover`)."
            )
        location = found[0][1]["name"]

    end = date.today()
    start = end - timedelta(days=args.days)
    print(f"Fiche  : {location}")
    print(f"Fenêtre demandée : {fr(start)} → {fr(end)}  ({args.days} jours)\n")

    rows = fetch_daily(session, location, start, end)
    if not rows:
        sys.exit("Aucune donnée renvoyée sur cette fenêtre.")

    days = sorted(rows)
    # Ce que la fenêtre demandée a réellement rendu : borne l'historique
    # disponible ET le lag de fraîcheur — deux inconnues non documentées.
    print(f"Données rendues  : {fr(days[0])} → {fr(days[-1])}  ({len(days)} jours)")

    # L'API rembourre la fin de fenêtre avec des jours à zéro tant que Google
    # n'a pas consolidé. Le dernier jour EXPLOITABLE est le dernier jour non
    # nul — s'aligner sur days[-1] ferait entrer des zéros factices dans les
    # moyennes et daterait le cron trop tôt.
    filled = [d for d in days if sum(rows[d].values()) > 0]
    if not filled:
        sys.exit("Aucun jour non nul : fenêtre entièrement en attente de consolidation.")
    last_real = filled[-1]
    lag = (end - last_real).days
    print(f"Dernier jour consolidé : {fr(last_real)}  →  lag J-{lag}")
    print(f"(les {(end - last_real).days} derniers jours sont rembourrés à zéro)\n")

    width = max(len(m) for m in DAILY_METRICS)

    def _cumuls(label: str, subset: list[date]) -> None:
        print(f"{label} ({len(subset)} jours, {fr(subset[0])} → {fr(subset[-1])}) :")
        for metric in DAILY_METRICS:
            total = sum(rows[d].get(metric, 0) for d in subset)
            print(f"  {metric:<{width}}  {total:>8,}".replace(",", " "))
        print()

    _cumuls("Cumuls sur toute la période", days)
    window28 = [d for d in days if last_real - timedelta(days=27) <= d <= last_real]
    if len(window28) >= 28:
        _cumuls("Cumuls sur 28 jours consolidés", window28)

    tail = days[-args.tail:]
    print(f"\nDétail des {len(tail)} derniers jours :")
    print(f"  {'jour':<12} {'appels':>7} {'site':>7} {'itin.':>7} {'impr.':>8}")
    for day in tail:
        r = rows[day]
        impressions = sum(
            r.get(m, 0) for m in DAILY_METRICS if m.startswith("BUSINESS_IMPRESSIONS")
        )
        print(
            f"  {fr(day):<12} {r.get('CALL_CLICKS', 0):>7}"
            f" {r.get('WEBSITE_CLICKS', 0):>7}"
            f" {r.get('BUSINESS_DIRECTION_REQUESTS', 0):>7}"
            f" {impressions:>8}"
        )

    print(
        "\n⚠️  Chiffres NON recoupés à ce stade. Le contrôle viendra du croisement\n"
        "    WEBSITE_CLICKS (Google) vs entrées utm_source=gmb (Cooked) sur fenêtre\n"
        "    alignée — l'écart mesurera ce que Cooked rate du canal."
    )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Google Business Profile → Cooked (reconnaissance, lecture seule)"
    )
    sub = parser.add_subparsers(dest="mode", required=True)

    sub.add_parser("discover", help="comptes + fiches accessibles").set_defaults(
        func=cmd_discover
    )

    p_probe = sub.add_parser("probe", help="séries quotidiennes affichées à l'écran")
    p_probe.add_argument("--location", help="locations/XXXX (défaut: l'unique fiche)")
    p_probe.add_argument(
        "--days", type=int, default=30, help="profondeur en jours (défaut: 30)"
    )
    p_probe.add_argument(
        "--tail", type=int, default=14, help="jours détaillés en fin de tableau"
    )
    p_probe.set_defaults(func=cmd_probe)

    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
