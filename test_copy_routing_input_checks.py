"""Copy / routing / input checks on the backend (no metric changes):

* /api/skin/analyze-single rejects a non-finite rosacea_score or
  sensitivity_score with HTTP 400; finite values behave exactly as before.
* A normal analyze-single response is unchanged versus a baseline captured on
  commit e1941f9 (before these edits) from the same input. The only field
  excluded from the comparison is `smart_narrative`, whose hardcoded sentence
  was intentionally replaced with honest wording.
* A note containing "rosacea" no longer triggers the Rosaliac AR /
  "Vascular Calm" recommendation.
* /api/ai-coach uses only the server's GEMINI_API_KEY and ignores any key
  supplied in the request body.

The baseline JSON was captured by posting the same fixed inputs (the
metric-regression clear_face photo resized to 512x512 PNG) to the untouched
branch; it is environment-sensitive in the same way as the other metric
fixtures (same OpenCV / MediaPipe versions required).
"""
from __future__ import annotations

import json
from pathlib import Path
from unittest import mock

import cv2
import pytest
from fastapi.testclient import TestClient

import main

REPO_ROOT = Path(__file__).resolve().parent
FACE_PHOTO = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"
BASELINE = REPO_ROOT / "test_fixtures" / "analyze_single_baseline_e1941f9.json"

# Intentionally changed copy; every other response field must be identical.
INTENTIONALLY_CHANGED_FIELDS = ("smart_narrative",)

BASELINE_CASES = {
    "plain": {},
    "finite_scores": {"rosacea_score": "3.5", "sensitivity_score": "5.0"},
    "finite_extremes": {"rosacea_score": "12.5", "sensitivity_score": "-2"},
    "barrier_flag": {
        "compromised_barrier": "true",
        "procedure_type": "halo",
        "days_post_op": "3",
    },
}


@pytest.fixture(scope="module")
def client():
    main.ensure_pipeline_ready()
    return TestClient(main.app)


@pytest.fixture(scope="module")
def face_png() -> bytes:
    image = cv2.imread(str(FACE_PHOTO))
    assert image is not None
    ok, encoded = cv2.imencode(".png", cv2.resize(image, (512, 512)))
    assert ok
    return encoded.tobytes()


def _post(client, face_png, data):
    files = {"image": ("face.png", face_png, "image/png")}
    return client.post("/api/skin/analyze-single", files=files, data=data)


# ── Non-finite safety scores -> 400 ─────────────────────────────────────


@pytest.mark.parametrize("bad", ["nan", "NaN", "inf", "-inf", "Infinity", "1e999"])
def test_non_finite_rosacea_score_returns_400(client, face_png, bad):
    response = _post(client, face_png, {"rosacea_score": bad})
    assert response.status_code == 400, response.text
    detail = response.json()["detail"]
    assert "rosacea_score" in detail
    assert "finite" in detail


@pytest.mark.parametrize("bad", ["nan", "inf", "-inf"])
def test_non_finite_sensitivity_score_returns_400(client, face_png, bad):
    response = _post(client, face_png, {"sensitivity_score": bad})
    assert response.status_code == 400, response.text
    detail = response.json()["detail"]
    assert "sensitivity_score" in detail
    assert "finite" in detail


def test_non_finite_rejected_even_when_other_score_is_finite(client, face_png):
    response = _post(
        client, face_png, {"rosacea_score": "3.5", "sensitivity_score": "nan"}
    )
    assert response.status_code == 400, response.text


def test_unparseable_score_still_falls_back_as_before(client, face_png):
    # Non-numeric text is not "non-finite": existing handling (ignored,
    # inferred from the scan) is unchanged and must not become a 400.
    response = _post(client, face_png, {"rosacea_score": "abc"})
    assert response.status_code == 200, response.text
    assert "safety_profile" in response.json()


# ── Finite values / normal scan unchanged vs pre-edit baseline ──────────


@pytest.mark.parametrize("case", sorted(BASELINE_CASES))
def test_response_matches_pre_edit_baseline(client, face_png, case):
    baseline = json.loads(BASELINE.read_text())[case]
    response = _post(client, face_png, BASELINE_CASES[case])
    assert response.status_code == baseline["status"] == 200
    body = response.json()
    expected = baseline["body"]

    assert set(body) == set(expected), "top-level response keys changed"
    for key in expected:
        if key in INTENTIONALLY_CHANGED_FIELDS:
            continue
        assert body[key] == expected[key], f"field changed: {key}"


def test_only_smart_narrative_copy_differs_and_is_honest(client, face_png):
    baseline = json.loads(BASELINE.read_text())["plain"]["body"]
    body = _post(client, face_png, {}).json()
    assert body["smart_narrative"] != baseline["smart_narrative"]
    assert "cellular maturation" not in body["smart_narrative"]
    assert "analyzed on our server" in body["smart_narrative"]
    assert "not a diagnosis" in body["smart_narrative"]


def test_finite_safety_scores_echo_unclamped_as_before(client, face_png):
    body = _post(
        client, face_png, {"rosacea_score": "12.5", "sensitivity_score": "-2"}
    ).json()
    assert body["safety_profile"]["rosacea_score"] == 12.5
    assert body["safety_profile"]["sensitivity_score"] == -2.0


# ── Rosacea note no longer triggers Rosaliac AR ─────────────────────────


def test_rosacea_note_does_not_recommend_vascular_calm(client, face_png):
    response = _post(client, face_png, {"skin_profile_note": "I have rosacea"})
    assert response.status_code == 200, response.text
    body = response.json()
    redness = float(body["metrics"]["calibrated_redness_score"])
    # Keep the test meaningful: the unchanged redness-band trigger must not
    # be what is in play for this photo.
    assert not (75.0 <= redness <= 85.0)
    tags = [p["reason_tag"] for p in body["recommended_products"]]
    names = [p["name"] for p in body["recommended_products"]]
    assert "Vascular Calm" not in tags
    assert not any("Rosaliac" in n for n in names)


# ── /api/ai-coach ignores a client-supplied Gemini key ──────────────────


class _FakeModels:
    def generate_content(self, model, contents):
        return mock.Mock(text="coach reply")


class _FakeGenaiClient:
    created_with: list = []

    def __init__(self, api_key=None, **kwargs):
        type(self).created_with.append(api_key)
        self.models = _FakeModels()


CLIENT_KEY_BODIES = [
    {"systemPrompt": "s", "userPrompt": "u", "geminiApiKey": "CLIENT-KEY"},
    {"systemPrompt": "s", "userPrompt": "u", "gemini_api_key": "CLIENT-KEY"},
    {"systemPrompt": "s", "userPrompt": "u", "apiKey": "CLIENT-KEY"},
    {"systemPrompt": "s", "userPrompt": "u", "api_key": "CLIENT-KEY"},
    {"payload": {"systemPrompt": "s", "userPrompt": "u", "geminiApiKey": "CLIENT-KEY"}},
]


@pytest.mark.parametrize("body", CLIENT_KEY_BODIES)
def test_ai_coach_uses_server_key_not_client_key(client, monkeypatch, body):
    monkeypatch.setenv("GEMINI_API_KEY", "SERVER-KEY")
    _FakeGenaiClient.created_with = []
    with mock.patch.object(main.genai, "Client", _FakeGenaiClient):
        response = client.post("/api/ai-coach", json=body)
    assert response.status_code == 200, response.text
    assert response.json()["text"] == "coach reply"
    assert _FakeGenaiClient.created_with == ["SERVER-KEY"]
    assert "CLIENT-KEY" not in response.text


@pytest.mark.parametrize("body", CLIENT_KEY_BODIES)
def test_ai_coach_without_server_key_never_uses_client_key(client, monkeypatch, body):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    _FakeGenaiClient.created_with = []
    with mock.patch.object(main.genai, "Client", _FakeGenaiClient):
        response = client.post("/api/ai-coach", json=body)
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "fallback"
    assert _FakeGenaiClient.created_with == [], "client-supplied key was used"
    assert "CLIENT-KEY" not in response.text
