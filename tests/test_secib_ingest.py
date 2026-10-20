"""T-16 — fonctions pures de cooked.secib : normalisation (vecteurs partagés) et dossier_row."""
import json
from datetime import date
from pathlib import Path

import pytest

from cooked import secib
from cooked.secib import dossier_row, normalize_email, normalize_phone_fr
from cooked.store import FakeStore, SupabaseStore

VECTORS = json.loads((Path(__file__).resolve().parents[1] / "contracts" / "normalize_vectors.json").read_text(encoding="utf-8"))


def test_email_vectors():
    for v in VECTORS["email"]:
        assert normalize_email(v["in"]) == v["out"], v


def test_phone_vectors():
    for v in VECTORS["phone_fr"]:
        assert normalize_phone_fr(v["in"]) == v["out"], v


def test_dossier_row_keeps_only_contact_identity_and_normalizes():
    d = {
        "DossierId": 42, "Code": "D-42", "DateCreation": "2026-08-10T10:57:00", "DateModification": None,
        "Matiere": {"MatiereId": 3, "Libelle": "Indemnisation"}, "EtatFacturable": "Facturable", "Type": "Contentieux",
        "IsArchive": False,
        "PremierClient": {"Personne": {"PersonneId": 7, "TypePersonne": "Physique", "Nom": "X", "Prenom": "Y",
                                        "Email": " X.Y@Example.com", "Telephone": "+33 (0)6 12 34 56 78", "Portable": None,
                                        "Adresse": "ne doit pas sortir"}},
    }
    row = dossier_row(d, "test")
    assert row["env"] == "test" and row["dossier_id"] == 42
    assert row["client_emails_norm"] == ["x.y@example.com"]
    assert row["client_tels_norm"] == ["+33612345678"]
    assert "Adresse" not in json.dumps(row)
    assert dossier_row({"Code": "sans id"}, "test") is None


@pytest.mark.parametrize("mode", ["probe", "ingest"])
def test_prod_is_blocked_before_credentials_or_network(monkeypatch, capsys, mode):
    def forbidden():
        raise AssertionError("aucun credential ne doit être lu")
    monkeypatch.setattr(secib, "load_credentials", forbidden)
    monkeypatch.setattr("sys.argv", ["secib_ingest.py", mode, "--secib-env", "prod"])
    with pytest.raises(SystemExit) as exc:
        secib.main()
    assert exc.value.code == 2
    assert "prod bloqué" in capsys.readouterr().err


@pytest.mark.parametrize("command", [secib.fetch_rows, secib.cmd_probe, secib.cmd_ingest])
def test_direct_commands_also_refuse_prod(command):
    # Le garde-fou ne dépend pas uniquement de l'analyse des arguments CLI.
    with pytest.raises(ValueError, match="prod bloqué"):
        command(None, 120, "prod")


def test_creation_window_is_inclusive_and_rejects_invalid_days():
    today = date(2026, 10, 20)
    assert secib.creation_window(1, today) == (today, today)
    assert secib.creation_window(28, today) == (date(2026, 9, 23), today)
    for days in [0, -1]:
        with pytest.raises(ValueError, match="strictement positif"):
            secib.creation_window(days, today)


class Response:
    def __init__(self, data):
        self.data = data

    def raise_for_status(self):
        pass

    def json(self):
        return self.data


class Session:
    def __init__(self, pages):
        self.pages = iter(pages)
        self.calls = []

    def post(self, url, **kwargs):
        self.calls.append((url, kwargs))
        return Response(next(self.pages))


def api_client(pages):
    # Jamais d'auth réelle : seule la pagination utilise une session factice.
    client = secib.SecibClient.__new__(secib.SecibClient)
    client.base = "https://secib.example.invalid"
    client.session = Session(pages)
    return client


def test_dossier_pagination_is_complete_with_verified_creation_filter():
    client = api_client([[{"DossierId": i} for i in range(50)], [{"DossierId": 50}]])
    rows = client.dossiers(date(2026, 9, 1), date(2026, 10, 20))
    assert len(rows) == 51
    assert [call[1]["params"]["range"] for call in client.session.calls] == ["0-49", "50-99"]
    assert client.session.calls[0][1]["json"] == {
        "DateCreationDateDebut": "2026-09-01",
        "DateCreationDateFin": "2026-10-20",
    }


def test_repeated_page_fails_instead_of_looping_or_claiming_complete():
    page = [{"DossierId": i} for i in range(50)]
    client = api_client([page, page])
    with pytest.raises(secib.SecibResponseError, match="pagination répétée"):
        client.dossiers(date(2026, 9, 1), date(2026, 10, 20))
    assert len(client.session.calls) == 2


@pytest.mark.parametrize("page", [
    {"error": "sensitive detail"},
    [{"DossierId": i} for i in range(51)],
    [{"DossierId": 1}, {"DossierId": 1}],
    [{"Code": "missing-id"}],
])
def test_invalid_pages_fail_without_exposing_the_response(page):
    client = api_client([page])
    with pytest.raises(secib.SecibResponseError) as exc:
        client.dossiers(date(2026, 9, 1), date(2026, 10, 20))
    assert "sensitive detail" not in str(exc.value)
    assert "missing-id" not in str(exc.value)


def test_page_limit_fails_before_partial_result_is_returned(monkeypatch):
    monkeypatch.setattr(secib, "MAX_DOSSIER_PAGES", 1)
    client = api_client([[{"DossierId": i} for i in range(50)]])
    with pytest.raises(secib.SecibResponseError, match="résultat incomplet"):
        client.dossiers(date(2026, 9, 1), date(2026, 10, 20))


class PrototypeClient:
    def dossiers(self, _date_from, _date_to):
        return [{
            "DossierId": 1, "Code": "RECENT-TEST",
            "DateCreation": "2026-10-10T12:00:00",
            "PremierClient": {"Personne": {"Email": "synthetic@example.invalid"}},
        }]

    def export_financier(self, _date_from, _date_to):
        return {"ListFactureExport": [
            {"DossierCode": "RECENT-TEST", "MontantHt": 100},
            # Facture récente d'un dossier créé avant la fenêtre : explicitement
            # hors des métadonnées relues, jamais considérée comme synchronisée.
            {"DossierCode": "ANCIEN-TEST", "MontantHt": 900},
        ]}


def test_ingest_never_overwrites_a_lifetime_total_with_a_window_export(monkeypatch, capsys):
    store = FakeStore()
    monkeypatch.setattr(SupabaseStore, "from_env", classmethod(lambda cls: store))
    client = PrototypeClient()
    def forbidden_export(*_args):
        raise AssertionError("l'ingestion ne doit pas lire d'extrait financier")
    monkeypatch.setattr(client, "export_financier", forbidden_export)
    secib.cmd_ingest(client, 120, "test")
    assert len(store.upserts) == 1
    call = store.upserts[0]
    assert call.table == "secib_dossiers" and call.on_conflict == "env,dossier_id"
    row = call.rows[0]
    assert row["env"] == "test"
    assert row["facture_total_ht"] is None
    assert row["premiere_facture"] is None
    assert row["derniere_facture"] is None
    # L'upsert invalide un ancien montant test non démontré au lieu de le
    # conserver comme cumul ; aucune écriture n'est faite pendant ce test.
    previously_imported = {"facture_total_ht": 9000, "premiere_facture": "2025-01-01"}
    previously_imported.update(row)
    assert previously_imported["facture_total_ht"] is None
    assert "anciens dossiers" in capsys.readouterr().out


def test_probe_reports_old_dossier_gap_without_pii_or_cumulative_claim(monkeypatch, capsys):
    monkeypatch.setattr(secib, "creation_window", lambda *_args: (date(2026, 9, 1), date(2026, 10, 20)))
    secib.cmd_probe(PrototypeClient(), 50, "test")
    output = capsys.readouterr().out
    assert "1 dans les créations relues ; 1 hors de ces créations" in output
    assert "Aucun cumul" in output
    assert "complétude de l'export non certifiée" in output
    assert "2026-09-01 → 2026-10-20" in output
    assert "synthetic@example.invalid" not in output
    assert "ANCIEN-TEST" not in output
    assert "RECENT-TEST" not in output


def test_financial_preview_does_not_turn_an_unknown_response_into_zero():
    for data in [{}, {"ListFactureExport": None}, {"ListFactureExport": [42]}]:
        with pytest.raises(secib.SecibResponseError):
            secib.billing_codes(data)
    assert secib.billing_codes({"ListFactureExport": []}) == set()
    assert secib.billing_codes({"ListFactureExport": [{"DossierCode": "X"}, {"DossierCode": "X"}]}) == {"X"}
