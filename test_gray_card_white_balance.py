"""Optional gray-card white balance: a marked card is sampled before any
white balance and used as the neutral reference for the existing LAB a*/b*
shift, before metrics are computed. No mark: the automatic path unchanged."""
from __future__ import annotations

import json
from pathlib import Path
from unittest import mock

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

import main

REPO_ROOT = Path(__file__).resolve().parent
FACE_PHOTO = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"

# A neutral card photographed under a warm cast (BGR).
WARM_CARD_BGR = (100, 125, 150)


def _png(image: np.ndarray) -> bytes:
    ok, encoded = cv2.imencode(".png", image)
    assert ok
    return encoded.tobytes()


def _scene_with_card(card_bgr=WARM_CARD_BGR, size=200):
    rng = np.random.default_rng(7)
    image = np.clip(rng.normal(150, 6, (size, size, 3)), 0, 255).astype(np.uint8)
    image[10:50, 10:50] = card_bgr
    region = {"x": 10 / size, "y": 10 / size, "w": 40 / size, "h": 40 / size}
    return image, region


def _card_lab_mean(image_bgr: np.ndarray) -> np.ndarray:
    lab = cv2.cvtColor(image_bgr[10:50, 10:50], cv2.COLOR_BGR2LAB)
    return lab.reshape(-1, 3).astype(np.float64).mean(axis=0)


def test_marked_card_shifts_white_balance_toward_neutral():
    image, region = _scene_with_card()
    raw = _card_lab_mean(image)
    normalized, profile, pre_wb = main._assess_and_normalize_image_with_pre_white_balance(
        _png(image), region
    )
    after = _card_lab_mean(normalized)

    assert abs(raw[1] - 128) > 4 and abs(raw[2] - 128) > 4
    assert abs(after[1] - 128) < 1.5
    assert abs(after[2] - 128) < 1.5
    assert profile["white_balance_profile"]["method"] == "gray_card_reference"
    assert profile["gray_card_marked"] is True
    assert profile["gray_card_correction_applied"] is True
    assert profile["gray_card_reason"] is None
    # The raw pre-white-balance sample: L* 8-bit, a*/b* signed.
    assert profile["gray_card_mean_L"] == pytest.approx(raw[0], abs=0.01)
    assert profile["gray_card_mean_a"] == pytest.approx(raw[1] - 128, abs=0.01)
    assert profile["gray_card_mean_b"] == pytest.approx(raw[2] - 128, abs=0.01)
    # The shift is the card's own offset; the pre-WB diagnostic is untouched.
    assert profile["wb_a_adjustment_post_clip"] == pytest.approx(raw[1] - 128, abs=0.01)
    assert abs(_card_lab_mean(pre_wb)[1] - raw[1]) < 1.0
    # Before/after stays visible.
    assert "chroma_cast" in profile
    assert "whole_image_mean_a_before_wb" in profile


def test_only_a_and_b_are_shifted():
    image, region = _scene_with_card()
    marked, _, _ = main._assess_and_normalize_image_with_pre_white_balance(
        _png(image), region
    )
    # Undo nothing: L* of the marked result matches the automatic path's L*
    # within LAB round-trip rounding (no exposure change from the card).
    plain, _, _ = main._assess_and_normalize_image_with_pre_white_balance(_png(image))
    l_marked = cv2.cvtColor(marked, cv2.COLOR_BGR2LAB)[:, :, 0].astype(int)
    l_plain = cv2.cvtColor(plain, cv2.COLOR_BGR2LAB)[:, :, 0].astype(int)
    assert np.abs(l_marked - l_plain).mean() < 1.5


def test_no_mark_is_exactly_the_automatic_path():
    image, _ = _scene_with_card()
    data = _png(image)
    expected_image, expected_profile, _ = main._assess_and_normalize_image_with_pre_white_balance(data)
    normalized, profile, _ = main._assess_and_normalize_image_with_pre_white_balance(data, None)
    assert np.array_equal(normalized, expected_image)
    assert profile["white_balance_profile"] == expected_profile["white_balance_profile"]
    assert profile["gray_card_marked"] is False
    assert profile["gray_card_correction_applied"] is False
    assert profile["gray_card_mean_a"] is None


@pytest.mark.parametrize(
    "region, card, reason",
    [
        ({"x": 0.9, "y": 0.9, "w": 0.2, "h": 0.2}, WARM_CARD_BGR, "region_out_of_bounds"),
        ({"x": 0.05, "y": 0.05, "w": 0.03, "h": 0.03}, WARM_CARD_BGR, "insufficient_region_pixels"),
        (None, (60, 90, 200), "implausible_card_color"),
    ],
)
def test_rejected_card_keeps_the_automatic_path(region, card, reason):
    image, card_region = _scene_with_card(card_bgr=card)
    data = _png(image)
    plain, _, _ = main._assess_and_normalize_image_with_pre_white_balance(data)
    normalized, profile, _ = main._assess_and_normalize_image_with_pre_white_balance(
        data, region or card_region
    )
    assert np.array_equal(normalized, plain)
    assert profile["gray_card_marked"] is True
    assert profile["gray_card_correction_applied"] is False
    assert profile["gray_card_reason"] == reason


@pytest.mark.parametrize(
    "raw, expected",
    [
        (None, None),
        ("", None),
        ("not json", None),
        ('{"x": 0.1, "y": 0.2, "w": 0.3}', None),
        ('{"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.4}', {"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.4}),
        ("[0.1, 0.2, 0.3, 0.4]", {"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.4}),
    ],
)
def test_parse_gray_card_region(raw, expected):
    assert main.parse_gray_card_region(raw) == expected


def test_no_rgb_gain_step_remains():
    assert not hasattr(main, "apply_gray_card_white_balance")


# ── Endpoint ─────────────────────────────────────────────────────────────


@pytest.fixture(scope="module")
def client():
    main.ensure_pipeline_ready()
    return TestClient(main.app)


def _face_with_card() -> tuple[bytes, dict, tuple[slice, slice]]:
    image = cv2.imread(str(FACE_PHOTO))
    assert image is not None
    image = cv2.resize(image, (512, 512))
    image[8:72, 8:72] = WARM_CARD_BGR
    region = {"x": 8 / 512, "y": 8 / 512, "w": 64 / 512, "h": 64 / 512}
    return _png(image), region, (slice(8, 72), slice(8, 72))


def _post(client, data: bytes, **fields):
    response = client.post(
        "/api/skin/analyze-single",
        files={"image": ("face.png", data, "image/png")},
        data=fields,
    )
    assert response.status_code == 200, response.text
    return response.json()


def _image_quality(payload: dict) -> dict:
    return payload.get("image_quality") or payload["data"]["image_quality"]


def _metrics(payload: dict) -> dict:
    return payload.get("metric_matrix") or payload["data"]["metric_matrix"]


def test_correction_happens_before_metric_computation(client):
    data, region, (ys, xs) = _face_with_card()
    seen = []
    real = main.analyze_skin_patch

    def recording(image, *args, **kwargs):
        seen.append(image.copy())
        return real(image, *args, **kwargs)

    with mock.patch.object(main, "analyze_skin_patch", recording):
        marked = _post(client, data, gray_card_region=json.dumps(region))
        plain = _post(client, data)

    card_marked = cv2.cvtColor(seen[0][ys, xs], cv2.COLOR_BGR2LAB).reshape(-1, 3).mean(axis=0)
    card_plain = cv2.cvtColor(seen[1][ys, xs], cv2.COLOR_BGR2LAB).reshape(-1, 3).mean(axis=0)
    # The image the metrics are computed on already has the card neutral.
    assert abs(card_marked[1] - 128) < 1.5 and abs(card_marked[2] - 128) < 1.5
    assert abs(card_plain[1] - 128) > abs(card_marked[1] - 128)

    quality = _image_quality(marked)
    assert quality["gray_card_marked"] is True
    assert quality["gray_card_correction_applied"] is True
    for key in ("gray_card_mean_L", "gray_card_mean_a", "gray_card_mean_b"):
        assert isinstance(quality[key], (int, float)), key
    assert "chroma_cast" in quality and "whole_image_mean_a_before_wb" in quality
    assert _image_quality(plain)["gray_card_marked"] is False


def test_no_mark_endpoint_matches_the_pipeline_without_a_card(client):
    data, _, _ = _face_with_card()
    plain = _post(client, data)
    normalized, profile, pre_wb = main._assess_and_normalize_image_with_pre_white_balance(data)
    direct = main.analyze_skin_patch(
        normalized, quality_profile=profile, pre_white_balance_bgr=pre_wb
    )["metric_matrix"]
    for key, value in direct.items():
        assert _metrics(plain).get(key) == value, key
