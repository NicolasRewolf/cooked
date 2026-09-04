"""T-16 — fonctions pures de cooked.secib : normalisation (vecteurs partagés) et dossier_row."""
import json
from pathlib import Path

from cooked.secib import dossier_row, normalize_email, normalize_phone_fr

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
