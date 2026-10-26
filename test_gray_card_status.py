"""Gray-card status: a marked card that is rejected is reported clearly
(machine-readable status, human message, retake flag, baseline-ineligible)
instead of silently falling back to automatic white balance. The three
rejected readings below come from the user's Oct 25 scan CSV. Reporting
only: images and scores are unchanged."""
from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

import main

SIZE = 200
CARD = (slice(10, 50), slice(10, 50))
CARD_REGION = {"x": 10 / SIZE, "y": 10 / SIZE, "w": 40 / SIZE, "h": 40 / SIZE}
FACE_PHOTO = Path(__file__).resolve().parent / "test_fixtures" / "metric_regression" / "clear_face.jfif"


def _png(image: np.ndarray) -> bytes:
    ok, encoded = cv2.imencode(".png", image)
    assert ok
    return encoded.tobytes()


def _scene(scene_ab, card_lab) -> np.ndarray:
    """Gray scene with an a*/b* cast of scene_ab (signed from neutral) and a
    card patch of card_lab = (L 0-255, a signed, b signed), built in LAB."""
    rng = np.random.default_rng(11)
    lab = np.empty((SIZE, SIZE, 3), dtype=np.float64)
    lab[:, :, 0] = rng.normal(150, 4, (SIZE, SIZE))
    lab[:, :, 1] = 128 + scene_ab[0] + rng.normal(0, 0.6, (SIZE, SIZE))
    lab[:, :, 2] = 128 + scene_ab[1] + rng.normal(0, 0.6, (SIZE, SIZE))
    lab[CARD] = (card_lab[0], 128 + card_lab[1], 128 + card_lab[2])
    return cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)


def _run(image: np.ndarray, region=CARD_REGION) -> dict:
    return main._assess_and_normalize_image_with_pre_white_balance(_png(image), region)[1]


def _assert_rejected(profile, status, reason):
    assert profile["gray_card_marked"] is True
    assert profile["gray_card_correction_applied"] is False
    assert profile["gray_card_reason"] == reason
    assert profile["gray_card_status"] == status
    assert profile["gray_card_message"] == main.GRAY_CARD_STATUS_MESSAGES[status]
    assert profile["gray_card_retake_recommended"] is True
    assert profile["gray_card_baseline_eligible"] is False
    # The user sees the message among the preprocess warnings too.
    assert profile["gray_card_message"] in profile["preprocess_warnings"]


# ── The three real rejected readings ────────────────────────────────────


def test_reading_a_bright_bluish_card_is_rejected_as_scene_mismatch():
    # L=209, a=-2.9, b=-9.8: neutral enough (offset ~10.2) but ~21 from the
    # scene's own neutral estimate (a warm scene).
    profile = _run(_scene((8, 8), (209, -2.9, -9.8)))
    assert abs(profile["gray_card_mean_L"] - 209) < 1
    assert abs(profile["gray_card_mean_a"] - -2.9) < 1
    assert abs(profile["gray_card_mean_b"] - -9.8) < 1
    assert 10 < profile["gray_card_chroma_offset"] < 12
    assert profile["gray_card_scene_disagreement"] > main.GRAY_CARD_MAX_SCENE_DISAGREEMENT
    _assert_rejected(
        profile, main.GRAY_CARD_STATUS_REJECTED_SCENE_MISMATCH, "disagrees_with_scene"
    )


@pytest.mark.parametrize(
    "card_lab",
    [(131.0, 15.8, 7.8), (131.5, 16.1, 9.6)],
    ids=["reading_b", "reading_c"],
)
def test_readings_b_and_c_skin_or_shadow_are_rejected_as_wrong_area(card_lab):
    profile = _run(_scene((0, 0), card_lab))
    assert abs(profile["gray_card_mean_L"] - card_lab[0]) < 1
    # 8-bit LAB->BGR->LAB round trip moves a*/b* by up to ~1 unit.
    assert abs(profile["gray_card_mean_a"] - card_lab[1]) < 1.5
    assert abs(profile["gray_card_mean_b"] - card_lab[2]) < 1.5
    assert 16 < profile["gray_card_chroma_offset"] < 20
    _assert_rejected(
        profile, main.GRAY_CARD_STATUS_REJECTED_WRONG_AREA, "implausible_card_color"
    )


# ── Other rejections, accepted card, no card ────────────────────────────


def test_blown_out_card_is_rejected_for_exposure():
    profile = _run(_scene((0, 0), (250, 0, 0)))
    _assert_rejected(
        profile, main.GRAY_CARD_STATUS_REJECTED_BAD_EXPOSURE, "implausible_exposure"
    )


def test_region_out_of_bounds_is_rejected_as_unreadable():
    image = _scene((0, 0), (145, 0, 0))
    profile = _run(image, {"x": 0.9, "y": 0.9, "w": 0.3, "h": 0.3})
    _assert_rejected(
        profile, main.GRAY_CARD_STATUS_REJECTED_UNREADABLE, "region_out_of_bounds"
    )


def test_plausible_neutral_card_is_applied():
    profile = _run(_scene((4, 7), (145, 5, 8)))
    assert profile["gray_card_correction_applied"] is True
    assert profile["gray_card_status"] == "applied"
    assert profile["gray_card_message"] is None
    assert profile["gray_card_retake_recommended"] is False
    assert profile["gray_card_baseline_eligible"] is True
    assert not any("gray card" in w.lower() for w in profile["preprocess_warnings"])


def test_no_card_marked_is_unchanged():
    image = _scene((0, 0), (145, 0, 0))
    profile = main._assess_and_normalize_image_with_pre_white_balance(_png(image))[1]
    assert profile["gray_card_marked"] is False
    assert profile["gray_card_status"] == "not_marked"
    assert profile["gray_card_message"] is None
    assert profile["gray_card_retake_recommended"] is False
    assert profile["gray_card_baseline_eligible"] is True
    assert not any("gray card" in w.lower() for w in profile["preprocess_warnings"])


def test_rejected_card_does_not_change_the_image_or_warnings_otherwise():
    # Same pixels as the automatic path: only the reporting differs.
    image = _scene((0, 0), (131.0, 15.8, 7.8))
    plain, plain_profile, _ = main._assess_and_normalize_image_with_pre_white_balance(
        _png(image)
    )
    marked, marked_profile, _ = main._assess_and_normalize_image_with_pre_white_balance(
        _png(image), CARD_REGION
    )
    assert np.array_equal(plain, marked)
    assert marked_profile["preprocess_warnings"][:-1] == plain_profile["preprocess_warnings"]
    assert marked_profile["lighting_balance_score"] == plain_profile["lighting_balance_score"]


def test_plausibility_constants_are_documented_values():
    assert main.GRAY_CARD_MAX_CHROMA_OFFSET == 12.0
    assert main.GRAY_CARD_MIN_MEASURED_L == 20.0
    assert main.GRAY_CARD_MAX_MEASURED_L == 240.0
    assert main.GRAY_CARD_MAX_SCENE_DISAGREEMENT == 12.0


# ── Endpoint ────────────────────────────────────────────────────────────


@pytest.fixture(scope="module")
def client():
    main.ensure_pipeline_ready()
    return TestClient(main.app)


def _face_png() -> bytes:
    image = cv2.imread(str(FACE_PHOTO))
    assert image is not None
    return _png(cv2.resize(image, (512, 512)))


def _post(client, patch: bytes | None):
    files = {"image": ("face.png", _face_png(), "image/png")}
    data = {}
    if patch is not None:
        files["gray_card_image"] = ("gray_card.png", patch, "image/png")
        data["gray_card_still_region"] = json.dumps({"x": 0.3, "y": 0.82, "w": 0.4, "h": 0.12})
    response = client.post("/api/skin/analyze-single", files=files, data=data)
    assert response.status_code == 200, response.text
    return response.json()


def test_endpoint_reports_rejected_card_at_top_level_and_in_image_quality(client):
    skin_patch = _png(np.full((60, 90, 3), (60, 90, 200), dtype=np.uint8))
    payload = _post(client, skin_patch)
    for source in (payload, payload["image_quality"], payload["metrics"]):
        assert source["gray_card_status"] == "rejected_wrong_area"
        assert source["gray_card_retake_recommended"] is True
        assert source["gray_card_baseline_eligible"] is False
    assert "skin or shadow" in payload["gray_card_message"]


def test_endpoint_applied_and_not_marked(client):
    applied = _post(client, _png(np.full((60, 90, 3), (124, 132, 154), dtype=np.uint8)))
    assert applied["gray_card_status"] == "applied"
    assert applied["gray_card_retake_recommended"] is False
    assert applied["gray_card_baseline_eligible"] is True
    plain = _post(client, None)
    assert plain["gray_card_status"] == "not_marked"
    assert plain["gray_card_retake_recommended"] is False
    assert plain["gray_card_baseline_eligible"] is True
