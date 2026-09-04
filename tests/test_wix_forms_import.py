"""T-16 — fonctions pures de cooked.wix.forms : nettoyage, build_row, dédup contre le webhook (e-04)."""
from cooked.wix.forms import already_captured, build_row, clean_email, clean_path, clean_phone


def test_clean_helpers():
    assert clean_email(" a@b.fr ") == "a@b.fr" and clean_email("pas un email") is None
    assert clean_phone("06 12 34 56 78") == "06 12 34 56 78" and clean_phone("123") is None
    assert clean_path("https://www.jplouton-avocat.fr/post/x?utm=1") == "/post/x"
    assert clean_path("") is None


def test_build_row_is_idempotent_and_needs_identity():
    r = {"Date d'envoi": "2026-08-15T10:00:00", "Nom": "N", "Prénom": "P", "Email": "n.p@ex.fr",
         "Téléphone": "0612345678", "Objet de ma demande": "Divorce", "page_source": "/x"}
    a, b = build_row(r), build_row(dict(r))
    assert a["wix_submission_id"] == b["wix_submission_id"] and a["wix_submission_id"].startswith("wiximport-")
    assert build_row({"Date d'envoi": "2026-08-15T10:00:00"}) is None  # sans identité
    assert build_row({"Date d'envoi": "15/08/2026", "Nom": "N"}) is None  # date non ISO


def test_already_captured_matches_webhook_row_within_two_minutes():
    row = build_row({"Date d'envoi": "2026-08-15T10:00:30", "Nom": "N", "Email": "N.P@ex.fr"})
    webhook = [("n.p@ex.fr", "2026-08-15T10:01:10+00:00"), ("autre@ex.fr", "2026-08-15T10:00:30+00:00")]
    assert already_captured(row, webhook) is True
    assert already_captured(row, [("n.p@ex.fr", "2026-08-15T12:00:00+00:00")]) is False
    assert already_captured(row, []) is False
