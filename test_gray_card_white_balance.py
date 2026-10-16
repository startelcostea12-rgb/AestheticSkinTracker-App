"""Optional gray-card white balance: per-channel gains from a supplied card
region, applied before metric computation and logged in image_quality.
Off unless a region is supplied; an invalid region is skipped."""
from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

import main

REPO_ROOT = Path(__file__).resolve().parent
FACE_PHOTO = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"

# A neutral 18% card photographed under a warm cast (BGR).
WARM_CARD_BGR = (100, 125, 150)


def _image_with_card(card_bgr=WARM_CARD_BGR, size=200):
    rng = np.random.default_rng(7)
    image = np.clip(rng.normal(150, 6, (size, size, 3)), 0, 255).astype(np.uint8)
    card = np.zeros((40, 40, 3), dtype=np.float64) + np.array(card_bgr, dtype=np.float64)
    card += rng.normal(0, 1.5, card.shape)
    image[10:50, 10:50] = np.clip(card, 0, 255).astype(np.uint8)
    region = {"x": 10 / size, "y": 10 / size, "w": 40 / size, "h": 40 / size}
    return image, region


def _channel_spread(pixels_bgr: np.ndarray) -> float:
    means = pixels_bgr.reshape(-1, 3).astype(np.float64).mean(axis=0)
    return float(means.max() - means.min())


def test_known_gray_patch_moves_toward_neutral():
    image, region = _image_with_card()
    before = _channel_spread(image[10:50, 10:50])
    corrected, info = main.apply_gray_card_white_balance(image, region)
    after = _channel_spread(corrected[10:50, 10:50])

    assert before > 40.0
    assert after < 2.0
    assert info["gray_card_used"] is True
    # Warm cast: red is pulled down, blue pushed up.
    assert info["gray_card_gain_r"] < 1.0 < info["gray_card_gain_b"]
    assert info["gray_card_gain_g"] == pytest.approx(1.0, abs=0.02)
    assert info["gray_card_region_pixels"] == 1600
    r, g, b = info["gray_card_mean_rgb_after"]
    assert max(r, g, b) - min(r, g, b) < 2.0


def test_no_region_leaves_the_image_unchanged():
    image, _ = _image_with_card()
    corrected, info = main.apply_gray_card_white_balance(image, None)
    assert corrected is image
    assert info == {
        "gray_card_used": False,
        "gray_card_gain_r": None,
        "gray_card_gain_g": None,
        "gray_card_gain_b": None,
        "gray_card_reason": "no_card_region",
    }


@pytest.mark.parametrize(
    "region, reason",
    [
        ({"x": 0.9, "y": 0.9, "w": 0.2, "h": 0.2}, "region_out_of_bounds"),
        ({"x": 0.1, "y": 0.1, "w": 0.0, "h": 0.2}, "region_out_of_bounds"),
        ({"x": 0.05, "y": 0.05, "w": 0.03, "h": 0.03}, "insufficient_region_pixels"),
    ],
)
def test_invalid_region_is_skipped(region, reason):
    image, _ = _image_with_card()
    corrected, info = main.apply_gray_card_white_balance(image, region)
    assert corrected is image
    assert info["gray_card_used"] is False
    assert info["gray_card_reason"] == reason


def test_skin_colored_region_is_rejected_as_not_a_card():
    # Strongly colored patch: fails the existing chroma plausibility check.
    image, region = _image_with_card(card_bgr=(60, 90, 200))
    corrected, info = main.apply_gray_card_white_balance(image, region)
    assert corrected is image
    assert info["gray_card_reason"] == "implausible_card_color"


@pytest.mark.parametrize(
    "raw, expected",
    [
        (None, None),
        ("", None),
        ("not json", None),
        ('{"x": 0.1, "y": 0.2, "w": 0.3}', None),
        ('{"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.4}', {"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.4}),
        ("[0.1, 0.2, 0.3, 0.4]", {"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.4}),
        ({"x": "0.1", "y": 0, "w": 1, "h": 1}, {"x": 0.1, "y": 0.0, "w": 1.0, "h": 1.0}),
    ],
)
def test_parse_gray_card_region(raw, expected):
    assert main.parse_gray_card_region(raw) == expected


# ── Endpoint: off by default, logged when used ──────────────────────────


@pytest.fixture(scope="module")
def client():
    main.ensure_pipeline_ready()
    return TestClient(main.app)


def _face_jpeg_with_card() -> tuple[bytes, dict]:
    image = cv2.imread(str(FACE_PHOTO))
    assert image is not None
    image = cv2.resize(image, (512, 512))
    image[8:72, 8:72] = WARM_CARD_BGR
    ok, encoded = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 95])
    assert ok
    return encoded.tobytes(), {"x": 8 / 512, "y": 8 / 512, "w": 64 / 512, "h": 64 / 512}


def _post(client, jpeg: bytes, **fields):
    response = client.post(
        "/api/skin/analyze-single",
        files={"image": ("face.jpg", jpeg, "image/jpeg")},
        data=fields,
    )
    assert response.status_code == 200, response.text
    return response.json()


def _metrics(payload: dict) -> dict:
    return payload.get("metric_matrix") or payload["data"]["metric_matrix"]


def _image_quality(payload: dict) -> dict:
    return payload.get("image_quality") or payload["data"]["image_quality"]


def test_endpoint_without_card_keeps_metrics_and_logs_skip(client):
    jpeg, _ = _face_jpeg_with_card()
    plain = _post(client, jpeg)
    invalid = _post(client, jpeg, gray_card_region='{"x": 0.99, "y": 0.99, "w": 0.5, "h": 0.5}')

    # The direct pipeline with no gray-card step at all.
    normalized, profile, pre_wb = main._assess_and_normalize_image_with_pre_white_balance(jpeg)
    direct = main.analyze_skin_patch(
        normalized, quality_profile=profile, pre_white_balance_bgr=pre_wb
    )["metric_matrix"]

    assert _metrics(plain) == _metrics(invalid)
    for key, value in direct.items():
        assert _metrics(plain).get(key) == value, key
    assert _image_quality(plain)["gray_card_used"] is False
    assert _image_quality(plain)["gray_card_reason"] == "no_card_region"
    assert _image_quality(invalid)["gray_card_reason"] == "region_out_of_bounds"


def test_endpoint_with_card_applies_and_logs_gains(client):
    jpeg, region = _face_jpeg_with_card()
    payload = _post(client, jpeg, gray_card_region=json.dumps(region))
    quality = _image_quality(payload)
    assert quality["gray_card_used"] is True
    assert quality["gray_card_gain_r"] < 1.0 < quality["gray_card_gain_b"]
    r, g, b = quality["gray_card_mean_rgb_after"]
    assert max(r, g, b) - min(r, g, b) < 3.0
    # The lighting quality signals still describe the uncorrected capture.
    plain = _image_quality(_post(client, jpeg))
    for key in ("lighting_mean_l", "chroma_cast", "lighting_balance_score"):
        assert quality[key] == plain[key], key
