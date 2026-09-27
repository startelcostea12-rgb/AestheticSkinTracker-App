"""Coverage for the logging-only color / redness-branch fields added to each
response's image_quality.

These fields exist so a scan's saved record shows the signed a*/b* the light
produced, what white balance subtracted, and which localized_redness branch
ran on which cheek. They must never change a score, so every test here also
checks the scored output is identical with and without them.
"""
from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
import pytest

import main

REPO_ROOT = Path(__file__).resolve().parent
CLEAR_FACE_PHOTO = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"

NEW_IMAGE_QUALITY_KEYS = {
    "color_lab_units",
    "whole_image_mean_a_before_wb",
    "whole_image_mean_b_before_wb",
    "whole_image_mean_a_after_wb",
    "whole_image_mean_b_after_wb",
    "wb_a_adjustment_post_clip",
    "wb_b_adjustment_post_clip",
    "redness_branch",
    "redness_cheek_side",
    "redness_cheek_roi_pixels",
    "redness_cheek_mean_a_after_wb",
    "redness_cheek_mean_b_after_wb",
    "redness_cheek_p10_a_after_wb",
    "redness_cheek_p95_a_after_wb",
    "redness_cheek_p10_a_before_wb",
    "redness_cheek_p95_a_before_wb",
    "redness_baseline_cheek_p95_a",
}


def _png_bytes(bgr: np.ndarray) -> bytes:
    ok, encoded = cv2.imencode(".png", bgr)
    assert ok
    return encoded.tobytes()


def _cast_image() -> np.ndarray:
    """A mostly-neutral grey card with a greenish tint plus a warm patch, so
    white balance has neutral candidates and a non-zero a* correction."""
    lab = np.full((200, 200, 3), 128, dtype=np.uint8)
    lab[:, :, 0] = 160
    lab[:, :, 1] = 122  # greenish neutral -> negative a* offset
    lab[:, :, 2] = 131
    lab[120:, 120:, 1] = 150
    lab[120:, 120:, 2] = 150
    return cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)


def test_signed_lab_value_centres_on_neutral():
    assert main._signed_lab_value(128.0) == 0.0
    assert main._signed_lab_value(140.25) == 12.25
    assert main._signed_lab_value(120.0) == -8.0
    assert main._signed_lab_value(None) is None
    assert main._signed_lab_value(float("nan")) is None


def test_assess_wrapper_is_unchanged_and_whole_image_color_is_signed():
    image_bytes = _png_bytes(_cast_image())
    normalized, profile = main.assess_and_normalize_image(image_bytes)
    normalized_2, profile_2, pre_wb = main._assess_and_normalize_image_with_pre_white_balance(
        image_bytes
    )
    assert np.array_equal(normalized, normalized_2)
    assert profile == profile_2
    assert pre_wb.shape == normalized.shape

    decoded = main._decode_image_bytes(image_bytes)
    pre_lab = cv2.cvtColor(decoded, cv2.COLOR_BGR2LAB)
    assert profile["whole_image_mean_a_before_wb"] == pytest.approx(
        float(np.mean(pre_lab[:, :, 1])) - 128.0, abs=1e-3
    )
    assert profile["whole_image_mean_b_before_wb"] == pytest.approx(
        float(np.mean(pre_lab[:, :, 2])) - 128.0, abs=1e-3
    )

    wb_bgr, wb_profile = main._apply_capture_white_balance_correction(decoded)
    wb_lab = cv2.cvtColor(wb_bgr, cv2.COLOR_BGR2LAB)
    assert profile["whole_image_mean_a_after_wb"] == pytest.approx(
        float(np.mean(wb_lab[:, :, 1])) - 128.0, abs=1e-3
    )
    assert profile["whole_image_mean_b_after_wb"] == pytest.approx(
        float(np.mean(wb_lab[:, :, 2])) - 128.0, abs=1e-3
    )
    # The post-clip adjustments are exactly what the correction subtracted.
    assert profile["wb_a_adjustment_post_clip"] == wb_profile["a_adjustment"]
    assert profile["wb_b_adjustment_post_clip"] == wb_profile["b_adjustment"]
    assert profile["wb_a_adjustment_post_clip"] < 0.0
    assert -8.0 <= profile["wb_a_adjustment_post_clip"] <= 8.0
    assert profile["color_lab_units"] == "signed_a_b_neutral_0"
    # chroma_cast keeps its existing (post-white-balance) definition.
    assert profile["chroma_cast"] == pytest.approx(
        float(
            np.hypot(
                profile["whole_image_mean_a_after_wb"],
                profile["whole_image_mean_b_after_wb"],
            )
        ),
        abs=0.02,
    )


def test_wb_adjustment_is_zero_when_correction_skipped():
    # Fully saturated image: no low-chroma neutral candidates at all.
    lab = np.full((120, 120, 3), 128, dtype=np.uint8)
    lab[:, :, 0] = 150
    lab[:, :, 1] = 190
    lab[:, :, 2] = 190
    profile = main.assess_and_normalize_image(
        _png_bytes(cv2.cvtColor(lab, cv2.COLOR_LAB2BGR))
    )[1]
    assert profile["white_balance_profile"]["applied"] is False
    assert profile["white_balance_profile"]["reason"] == "insufficient_neutral_pixels"
    assert profile["wb_a_adjustment_post_clip"] == 0.0
    assert profile["wb_b_adjustment_post_clip"] == 0.0


def _zone_fixture():
    lab = np.full((120, 120, 3), 128, dtype=np.uint8)
    lab[:, :, 0] = 150
    lab[:, :, 1] = 140
    lab[:, :, 2] = 145
    # Right cheek carries a red hot-spot, so it has the larger p95-p10 spread.
    lab[60:80, 80:100, 1] = 170
    face = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)
    skin = np.full((120, 120), 255, dtype=np.uint8)
    left = np.zeros((120, 120), dtype=np.uint8)
    right = np.zeros((120, 120), dtype=np.uint8)
    left[50:100, 5:50] = 255
    right[50:100, 70:115] = 255
    regions = {"left_cheek": left, "right_cheek": right}
    return face, skin, regions


def test_within_cheek_spread_branch_reports_the_winning_cheek():
    face, skin, regions = _zone_fixture()
    points = np.zeros((0, 2), dtype=np.float32)
    plain = main._compute_zone_based_metrics(face, skin, regions, points)
    diagnostics: dict = {}
    logged = main._compute_zone_based_metrics(
        face, skin, regions, points, redness_diagnostics=diagnostics
    )
    assert logged == plain

    assert diagnostics["branch"] == "within_cheek_spread"
    assert diagnostics["cheek_side"] == "right"
    assert diagnostics["baseline_p95_a"] is None
    lab = cv2.cvtColor(face, cv2.COLOR_BGR2LAB)
    a_blur = cv2.GaussianBlur(lab[:, :, 1].astype(np.float32), (0, 0), sigmaX=2.0)
    right_mask = regions["right_cheek"] > 0
    assert np.array_equal(diagnostics["mask"], right_mask)
    assert diagnostics["p95_a_after_wb"] == pytest.approx(
        float(np.percentile(a_blur[right_mask], 95))
    )
    assert diagnostics["p10_a_after_wb"] == pytest.approx(
        float(np.percentile(a_blur[right_mask], 10))
    )
    assert diagnostics["cheek_roi_pixels"] == int(np.count_nonzero(right_mask))
    assert diagnostics["mean_a_after_wb"] == pytest.approx(
        float(np.mean(lab[:, :, 1][right_mask]))
    )
    assert diagnostics["mean_b_after_wb"] == pytest.approx(
        float(np.mean(lab[:, :, 2][right_mask]))
    )


def test_baseline_p95_anchor_branch_reports_both_cheeks_and_baseline():
    face, skin, regions = _zone_fixture()
    points = np.zeros((0, 2), dtype=np.float32)
    baseline = {"localized_redness": 20.0, "a_p95": 150.0}
    plain = main._compute_zone_based_metrics(
        face, skin, regions, points, baseline_matrix=baseline
    )
    diagnostics: dict = {}
    logged = main._compute_zone_based_metrics(
        face,
        skin,
        regions,
        points,
        baseline_matrix=baseline,
        redness_diagnostics=diagnostics,
    )
    assert logged == plain

    assert diagnostics["branch"] == "baseline_p95_anchor"
    assert diagnostics["cheek_side"] == "both"
    assert diagnostics["baseline_p95_a"] == 150.0
    union = (regions["left_cheek"] > 0) | (regions["right_cheek"] > 0)
    assert np.array_equal(diagnostics["mask"], union)
    lab = cv2.cvtColor(face, cv2.COLOR_BGR2LAB)
    a_blur = cv2.GaussianBlur(lab[:, :, 1].astype(np.float32), (0, 0), sigmaX=2.0)
    assert diagnostics["p95_a_after_wb"] == pytest.approx(
        float(np.percentile(a_blur[union], 95))
    )
    assert diagnostics["p10_a_after_wb"] == pytest.approx(
        float(np.percentile(a_blur[union], 10))
    )

    fields = main._redness_color_diagnostics(
        diagnostics,
        branch="baseline_p95_anchor",
        p10_a_before_wb=None,
        p95_a_before_wb=None,
    )
    assert fields["redness_baseline_cheek_p95_a"] == 22.0
    assert fields["redness_cheek_side"] == "both"


def test_non_zone_branch_reports_its_name_and_null_cheek_fields():
    fields = main._redness_color_diagnostics(
        {"branch": "within_cheek_spread", "cheek_side": "left", "p95_a_after_wb": 150.0},
        branch="redness_fallback_emit",
        p10_a_before_wb=140.0,
        p95_a_before_wb=151.0,
    )
    assert fields["redness_branch"] == "redness_fallback_emit"
    for key, value in fields.items():
        if key != "redness_branch":
            assert value is None, key


def test_full_pipeline_emits_fields_without_changing_any_score():
    image_bytes = CLEAR_FACE_PHOTO.read_bytes()
    normalized, profile, pre_wb = main._assess_and_normalize_image_with_pre_white_balance(
        image_bytes
    )
    without = main.analyze_skin_patch(normalized, quality_profile=dict(profile))
    with_pre = main.analyze_skin_patch(
        normalized, quality_profile=dict(profile), pre_white_balance_bgr=pre_wb
    )

    iq_without = without.pop("image_quality")
    iq_with = with_pre.pop("image_quality")
    assert without == with_pre
    assert NEW_IMAGE_QUALITY_KEYS <= set(iq_with)
    for key, value in profile.items():
        assert iq_with[key] == value

    assert iq_with["redness_branch"] in {"within_cheek_spread", "baseline_p95_anchor"}
    assert iq_with["redness_cheek_side"] in {"left", "right"}
    assert iq_with["redness_cheek_p95_a_after_wb"] is not None
    assert iq_with["redness_cheek_p10_a_after_wb"] is not None
    assert iq_with["redness_cheek_p95_a_before_wb"] is not None
    assert iq_with["redness_cheek_p10_a_before_wb"] is not None
    # Without the pre-white-balance image only the "before" percentiles are unknown.
    assert iq_without["redness_cheek_p10_a_before_wb"] is None
    assert iq_without["redness_cheek_p95_a_before_wb"] is None
    assert iq_without["redness_cheek_p10_a_after_wb"] == iq_with["redness_cheek_p10_a_after_wb"]
    assert iq_without["redness_cheek_p95_a_after_wb"] == iq_with["redness_cheek_p95_a_after_wb"]
