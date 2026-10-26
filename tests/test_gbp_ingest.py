"""T-16 — fonctions pures de cooked.gbp : queue rembourrée à zéro et lignes store."""
from datetime import date
from unittest.mock import Mock

import pytest
from google.auth.exceptions import RefreshError

from cooked.gbp import (
    _get,
    _http_failure_message,
    _to_store_rows,
    _trim_unconsolidated,
)


def test_trim_unconsolidated_cuts_trailing_zero_days_only():
    rows = {
        date(2026, 8, 18): {"CALL_CLICKS": 5, "WEBSITE_CLICKS": 3},
        date(2026, 8, 19): {"CALL_CLICKS": 0, "WEBSITE_CLICKS": 0},  # vrai zéro au milieu : conservé
        date(2026, 8, 20): {"CALL_CLICKS": 4, "WEBSITE_CLICKS": 2},
        date(2026, 8, 21): {"CALL_CLICKS": 0, "WEBSITE_CLICKS": 0},  # queue non consolidée : coupée
        date(2026, 8, 22): {"CALL_CLICKS": 0, "WEBSITE_CLICKS": 0},
    }
    kept = _trim_unconsolidated(rows)
    assert sorted(kept) == [date(2026, 8, 18), date(2026, 8, 19), date(2026, 8, 20)]
    assert _trim_unconsolidated({date(2026, 8, 21): {"CALL_CLICKS": 0}}) == {}


def test_to_store_rows_is_long_format_sorted():
    out = _to_store_rows("locations/1", {date(2026, 8, 20): {"WEBSITE_CLICKS": 2, "CALL_CLICKS": 4}})
    assert [(r["day"], r["metric"], r["value"]) for r in out] == [
        ("2026-08-20", "CALL_CLICKS", 4), ("2026-08-20", "WEBSITE_CLICKS", 2)]
    assert all(r["location"] == "locations/1" and r["ingested_at"] for r in out)


def quota_error(limit, consumer="projects/123456"):
    return {
        "error": {
            "code": 429,
            "status": "RESOURCE_EXHAUSTED",
            "message": "raw diagnostic must not leak secret-sentinel",
            "details": [{
                "@type": "type.googleapis.com/google.rpc.ErrorInfo",
                "reason": "RATE_LIMIT_EXCEEDED",
                "metadata": {
                    "service": "businessprofileperformance.googleapis.com",
                    "quota_limit_value": limit,
                    "consumer": consumer,
                },
            }],
        }
    }


@pytest.mark.parametrize("limit", ["0", 0])
def test_zero_quota_prioritizes_existing_approval_not_oauth_retry(limit):
    session = Mock()
    session.get.return_value.status_code = 429
    session.get.return_value.json.return_value = quota_error(limit)
    with pytest.raises(SystemExit, match="GBP_QUOTA_ZERO") as error:
        _get(session, "https://businessprofileperformance.googleapis.com/v1/test")
    diagnostic = str(error.value)
    assert "projects/123456" in diagnostic
    assert "un projet déjà approuvé et le dossier d'accès existant" in diagnostic
    assert "réutiliser ce projet si les droits le permettent" in diagnostic
    assert "inaccessible ou supprimé" in diagnostic
    assert "General API Question" in diagnostic
    assert "rétablir ou transférer l'accès" in diagnostic
    assert "https://support.google.com/business/contact/api_default" in diagnostic
    assert "gcloud auth" not in diagnostic
    assert "secret-sentinel" not in diagnostic
    assert session.get.call_count == 1


def test_zero_quota_only_suggests_first_application_without_known_approval():
    diagnostic = _http_failure_message(429, quota_error("0"))
    previous_approval, application = diagnostic.split(
        "Seulement si aucune approbation antérieure n'est connue, demander ", 1
    )
    assert "General API Question" in previous_approval
    assert "Application for Basic API Access" not in previous_approval
    assert "Application for Basic API Access" in application
    assert "https://developers.google.com/my-business/content/prereqs" in application


def test_nonzero_quota_is_not_reported_as_missing_approval():
    diagnostic = _http_failure_message(429, quota_error("300"))
    assert "GBP_RATE_LIMIT" in diagnostic
    assert "GBP_QUOTA_ZERO" not in diagnostic
    assert "Basic API Access" not in diagnostic


def test_error_metadata_never_leaks_arbitrary_consumer_text():
    diagnostic = _http_failure_message(429, quota_error("0", "secret-sentinel"))
    assert "GBP_QUOTA_ZERO" in diagnostic
    assert "secret-sentinel" not in diagnostic
    assert "projet appelant" in diagnostic


@pytest.mark.parametrize("payload", [None, [], {"error": None}, {"error": {"details": None}}])
def test_unstructured_quota_error_remains_unclassified(payload):
    assert "GBP_RATE_LIMIT" in _http_failure_message(429, payload)


def test_refresh_error_guides_dedicated_oauth_reauthorization_without_gcloud():
    session = Mock()
    session.get.side_effect = RefreshError("secret-sentinel")
    with pytest.raises(SystemExit, match="GBP_AUTH") as error:
        _get(session, "https://businessprofileperformance.googleapis.com/v1/test")
    diagnostic = str(error.value)
    assert "Réautoriser le client OAuth dédié existant" in diagnostic
    assert "https://www.googleapis.com/auth/business.manage" in diagnostic
    assert "auth/cloud-platform" not in diagnostic
    assert "gcloud auth" not in diagnostic
    assert "GBP_CREDENTIALS_B64" in diagnostic
    assert "appel API réussi et le rattrapage des jours manquants" in diagnostic
    assert "secret-sentinel" not in diagnostic


def test_http_auth_and_permission_failures_are_distinct():
    assert "GBP_AUTH" in _http_failure_message(401, None)
    assert "GBP_ACCESS_DENIED" in _http_failure_message(403, None)
    assert "gcloud auth" not in _http_failure_message(403, None)


def test_non_json_http_error_does_not_dump_response_body():
    session = Mock()
    session.get.return_value.status_code = 502
    session.get.return_value.json.side_effect = ValueError("secret-sentinel")
    session.get.return_value.text = "secret-sentinel"
    with pytest.raises(SystemExit, match="GBP_HTTP_502") as error:
        _get(session, "https://businessprofileperformance.googleapis.com/v1/test")
    assert "secret-sentinel" not in str(error.value)


def test_successful_get_keeps_payload_contract():
    payload = {"multiDailyMetricTimeSeries": []}
    session = Mock()
    session.get.return_value.status_code = 200
    session.get.return_value.json.return_value = payload
    assert _get(session, "https://businessprofileperformance.googleapis.com/v1/test") == payload
