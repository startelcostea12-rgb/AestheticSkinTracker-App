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

# A neutral card photographed under a warm cast (BGR): a* +7, b* +7,
# chroma offset ~9.9, inside the 12-unit acceptance limit.
WARM_CARD_BGR = (124, 132, 154)


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


def _linear_luminance(image: np.ndarray) -> np.ndarray:
    encoded = image.astype(np.float64) / 255.0
    linear = np.where(
        encoded <= 0.04045,
        encoded / 12.92,
        ((encoded + 0.055) / 1.055) ** 2.4,
    )
    return linear @ np.array([0.0722, 0.7152, 0.2126])


@pytest.mark.parametrize("gains", [(1.0, 1.0, 1.0), (0.7, 1.0, 1.4), (2.0, 0.5, 1.1)])
def test_linear_gains_preserve_luminance_even_at_gamut_limits(gains):
    image = np.random.default_rng(90).integers(0, 256, (100, 100, 3), dtype=np.uint8)
    image[0, :4] = [(0, 0, 0), (255, 255, 255), (0, 255, 0), (255, 0, 255)]
    original = image.copy()
    corrected = main._apply_linear_white_balance_gains(image, np.array(gains))
    before = _linear_luminance(image)
    after = _linear_luminance(corrected)
    assert abs(after.mean() - before.mean()) < 0.0001
    assert np.max(np.abs(after - before)) < 0.0045
    assert np.array_equal(image, original)
    assert corrected.dtype == np.uint8
    if gains == (1.0, 1.0, 1.0):
        assert np.array_equal(corrected, image)


def test_gains_are_applied_after_srgb_decode_not_to_encoded_values():
    image = np.array([[[40, 85, 125], [75, 105, 155]]], dtype=np.uint8)
    gains = np.array([1.2, 1.0, 0.8])
    encoded = image.astype(np.float64) / 255.0
    linear = ((encoded + 0.055) / 1.055) ** 2.4
    weighted = linear * gains
    weighted *= (_linear_luminance(image) / (weighted @ [0.0722, 0.7152, 0.2126]))[..., None]
    expected = np.rint((1.055 * weighted ** (1.0 / 2.4) - 0.055) * 255).astype(np.uint8)
    actual = main._apply_linear_white_balance_gains(image, gains)
    np.testing.assert_array_equal(actual, expected)
    gamma_scaled = image.astype(np.float64) * gains
    gamma_scaled *= (_linear_luminance(image) / _linear_luminance(np.rint(gamma_scaled).astype(np.uint8)))[..., None]
    assert not np.array_equal(actual, np.rint(gamma_scaled).astype(np.uint8))


@pytest.mark.parametrize("marked", [False, True])
def test_active_capture_wb_preserves_mean_linear_luminance(marked):
    image, region = _scene_with_card()
    sample = main._sample_gray_card(image, region) if marked else None
    corrected, profile = main._apply_capture_white_balance_correction(image, sample)
    assert profile["method"].startswith("linear_srgb_")
    before = _linear_luminance(image)
    encoded = corrected.astype(np.float64) / 255.0
    low = main._srgb_to_linear(np.maximum(encoded - 0.5 / 255.0, 0.0)) @ [0.0722, 0.7152, 0.2126]
    high = main._srgb_to_linear(np.minimum(encoded + 0.5 / 255.0, 1.0)) @ [0.0722, 0.7152, 0.2126]
    assert np.all(before >= low - 1e-12)
    assert np.all(before <= high + 1e-12)
    assert abs(_linear_luminance(corrected).mean() - before.mean()) <= (high - low).mean()


@pytest.mark.parametrize("metric,previous", [
    ("localized_redness", 3),
    ("pigment_load", 2),
    ("diffuse_flushing_erythema", 2),
    ("texture_smoothness", 4),
    ("pore_visibility", 3),
    ("chin_pore_visibility", 1),
    ("wrinkle_load", 4),
    ("sebum_excess_oil_gloss", 3),
    ("rosacea_severity", 3),
    ("pore_contraction_index", 3),
    ("glabellar_wrinkle_depth", 2),
    ("under_eye_texture_density", 5),
    ("under_eye_dark_circle_density", 5),
    ("breakout_activity", 2),
    ("skin_tone_radiance_evenness", 1),
    ("structural_firmness_elasticity", 1),
])
def test_linear_wb_refuses_each_previous_image_metric_version(metric, previous):
    expected_current = 4 if metric == "breakout_activity" else previous + 1
    assert main._metric_formula_version(metric) == expected_current
    assert main._trend_lock_reason(
        "primary_roi", "primary_roi", "normal", "normal",
        512, 512, 512, 512,
        current_formula_version=main._metric_formula_version(metric),
        baseline_formula_version=previous,
        current_pose_template="Front", baseline_pose_template="Front",
        current_guide_type="facial", baseline_guide_type="facial",
    ) == "formula_version_mismatch"


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
    assert profile["white_balance_profile"]["method"] == "linear_srgb_gray_card_reference"
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


# ── Card patch from outside the face crop ────────────────────────────────


def _face_png() -> bytes:
    image = cv2.imread(str(FACE_PHOTO))
    assert image is not None
    return _png(cv2.resize(image, (512, 512)))


def _patch(card_bgr) -> bytes:
    return _png(np.full((60, 90, 3), card_bgr, dtype=np.uint8))


STILL_REGION = {"x": 0.30, "y": 0.82, "w": 0.40, "h": 0.12}  # under the chin


def _post_with_patch(client, patch: bytes, **fields):
    response = client.post(
        "/api/skin/analyze-single",
        files={
            "image": ("face.png", _face_png(), "image/png"),
            "gray_card_image": ("gray_card.png", patch, "image/png"),
        },
        data={"gray_card_still_region": json.dumps(STILL_REGION), **fields},
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_patch_from_below_the_face_drives_the_white_balance(client):
    seen = []
    real = main.analyze_skin_patch

    def recording(image, *args, **kwargs):
        seen.append(image.copy())
        return real(image, *args, **kwargs)

    with mock.patch.object(main, "analyze_skin_patch", recording):
        payload = _post_with_patch(client, _patch(WARM_CARD_BGR))
        plain = _post(client, _face_png())

    quality = _image_quality(payload)
    assert quality["gray_card_marked"] is True
    assert quality["gray_card_correction_applied"] is True
    assert quality["gray_card_region_space"] == "full_still"
    assert (
        quality["gray_card_region_x"],
        quality["gray_card_region_y"],
        quality["gray_card_region_w"],
        quality["gray_card_region_h"],
    ) == (0.30, 0.82, 0.40, 0.12)
    card_lab = cv2.cvtColor(
        np.full((1, 1, 3), WARM_CARD_BGR, dtype=np.uint8), cv2.COLOR_BGR2LAB
    )[0, 0].astype(float)
    assert quality["gray_card_mean_a"] == pytest.approx(card_lab[1] - 128, abs=0.01)
    # The face image the metrics saw was shifted by the card's offset.
    shift = cv2.cvtColor(seen[1], cv2.COLOR_BGR2LAB)[:, :, 1].astype(float).mean() - cv2.cvtColor(
        seen[0], cv2.COLOR_BGR2LAB
    )[:, :, 1].astype(float).mean()
    assert shift > 1.0
    assert _image_quality(plain)["gray_card_marked"] is False


@pytest.mark.parametrize(
    "patch, reason",
    [
        (_patch((60, 90, 200)), "implausible_card_color"),
        (b"not an image", "card_image_unreadable"),
    ],
)
def test_rejected_patch_still_completes_the_scan(client, patch, reason):
    payload = _post_with_patch(client, patch)
    quality = _image_quality(payload)
    assert quality["gray_card_marked"] is True
    assert quality["gray_card_correction_applied"] is False
    assert quality["gray_card_reason"] == reason
    assert quality["gray_card_region_y"] == 0.82
    plain = _post(client, _face_png())
    assert _metrics(payload) == _metrics(plain)


def test_region_without_patch_is_recorded_not_dropped(client):
    response = client.post(
        "/api/skin/analyze-single",
        files={"image": ("face.png", _face_png(), "image/png")},
        data={"gray_card_still_region": json.dumps(STILL_REGION)},
    )
    assert response.status_code == 200, response.text
    quality = _image_quality(response.json())
    assert quality["gray_card_marked"] is True
    assert quality["gray_card_correction_applied"] is False
    assert quality["gray_card_reason"] == "card_image_missing"
    assert quality["gray_card_region_space"] == "full_still"
    assert quality["gray_card_region_x"] == 0.30
