"""Formula v7 for under_eye_dark_circle_density and under_eye_texture_density:
a lash-free lower-lid band and its cheek reference strip, clipped to wide face skin.
"""
from __future__ import annotations

import logging
import re
from pathlib import Path
from unittest import mock

import cv2
import numpy as np
import pytest

import main

REPO_ROOT = Path(__file__).resolve().parent
CLEAR_FACE_PHOTO = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"
UNDER_EYE_KEYS = ("under_eye_texture_density", "under_eye_dark_circle_density")


@pytest.fixture(scope="module")
def zone_inputs():
    """The exact face patch, skin mask, and landmarks analyze_skin_patch
    hands to _compute_zone_based_metrics for the clear-face fixture."""
    normalized, profile, _ = main._assess_and_normalize_image_with_pre_white_balance(
        CLEAR_FACE_PHOTO.read_bytes()
    )
    captured = {}
    real_zone = main._compute_zone_based_metrics

    def recording_zone(face_bgr, skin_mask, regions, points, **kwargs):
        _, face_skin_mask = main._build_face_skin_mask(
            face_bgr.shape[:2], points, skin_mask
        )
        captured.update(
            face_bgr=face_bgr,
            skin_mask=skin_mask,
            face_skin_mask=face_skin_mask,
            regions=regions,
            points=points,
        )
        return real_zone(face_bgr, skin_mask, regions, points, **kwargs)

    with mock.patch.object(main, "_compute_zone_based_metrics", recording_zone):
        result = main.analyze_skin_patch(normalized, quality_profile=dict(profile))
    return captured, result


def test_band_geometry_constants():
    assert main.UNDER_EYE_BAND_START_EYE_WIDTHS == 0.15
    assert main.UNDER_EYE_BAND_HEIGHT_EYE_WIDTHS == 0.30
    assert main.UNDER_EYE_MASK_KIND == "under_eye_lash_free_band"


@pytest.mark.parametrize("side", ["left", "right"])
def test_band_excludes_the_lower_lid_landmark_row(zone_inputs, side):
    captured, _ = zone_inputs
    face = captured["face_bgr"]
    face_skin = captured["face_skin_mask"]
    points = captured["points"]
    shape = face.shape[:2]
    band = main._under_eye_region_mask(shape, points, face_skin, side=side)
    assert cv2.countNonZero(band) > 0

    lid_ids = main._UNDER_EYE_LOWER_LID_IDS[side]
    lid = points[lid_ids]
    eye_width = float(np.linalg.norm(lid[0] - lid[-1]))
    for x, y in np.round(lid).astype(int):
        if 0 <= y < shape[0] and 0 <= x < shape[1]:
            assert band[y, x] == 0, (side, x, y)

    # No band pixel sits above the lid row plus the lash-free offset (with
    # one pixel of polygon rasterization tolerance).
    ys, xs = np.nonzero(band)
    lid_x = lid[:, 0]
    order = np.argsort(lid_x)
    lid_y_at = np.interp(xs, lid_x[order], lid[order, 1])
    offset = main.UNDER_EYE_BAND_START_EYE_WIDTHS * eye_width
    assert np.all(ys >= lid_y_at + offset - 1.0)


def test_band_is_smaller_than_cheeks_and_clipped_to_face_skin(zone_inputs, monkeypatch):
    captured, _ = zone_inputs
    face = captured["face_bgr"]
    face_skin = captured["face_skin_mask"]
    regions = captured["regions"]
    points = captured["points"]
    shape = face.shape[:2]
    received_masks = []
    real_region_mask = main._under_eye_region_mask

    def recording_region_mask(shape, points, mask, *, side):
        received_masks.append(mask.copy())
        return real_region_mask(shape, points, mask, side=side)

    with mock.patch.object(main, "_under_eye_region_mask", recording_region_mask):
        main._compute_zone_based_metrics(
            face, captured["skin_mask"], regions, points
        )

    assert received_masks
    assert all(np.array_equal(mask, face_skin) for mask in received_masks)
    band = cv2.bitwise_or(
        real_region_mask(shape, points, face_skin, side="left"),
        real_region_mask(shape, points, face_skin, side="right"),
    )
    cheeks = cv2.bitwise_or(regions["left_cheek"], regions["right_cheek"])
    assert cv2.countNonZero(cv2.bitwise_and(band, cv2.bitwise_not(face_skin))) == 0
    assert 0 < cv2.countNonZero(band) < cv2.countNonZero(cheeks)


def test_reference_strip_sits_directly_below_the_band(zone_inputs):
    captured, _ = zone_inputs
    face = captured["face_bgr"]
    face_skin = captured["face_skin_mask"]
    points = captured["points"]
    shape = face.shape[:2]
    for side in ("left", "right"):
        band = main._under_eye_region_mask(shape, points, face_skin, side=side)
        reference = main._under_eye_reference_mask(shape, points, face_skin, side=side)
        assert cv2.countNonZero(reference) > 0
        assert cv2.countNonZero(cv2.bitwise_and(band, reference)) == 0
        assert np.mean(np.nonzero(reference)[0]) > np.mean(np.nonzero(band)[0])


def test_dark_circle_score_uses_side_cheek_skin_and_averages_eyes(zone_inputs):
    captured, _ = zone_inputs
    face = captured["face_bgr"]
    skin = captured["skin_mask"]
    face_skin = captured["face_skin_mask"]
    points = captured["points"]
    regions = captured["regions"]
    zone = main._compute_zone_based_metrics(face, skin, regions, points)
    diagnostics = main._under_eye_darkness_diagnostics(face, points, face_skin, regions)
    l_channel = cv2.cvtColor(face.astype(np.float32) / 255.0, cv2.COLOR_BGR2LAB)[:, :, 0]
    scores = []
    for side in ("left", "right"):
        cheek_pixels = cv2.bitwise_and(regions[f"{side}_cheek"], face_skin) > 0
        prefix = f"under_eye_{side}_darkness"
        assert diagnostics[f"{prefix}_reference_median_L"] == pytest.approx(
            np.median(l_channel[cheek_pixels])
        )
        scores.append(diagnostics[f"{prefix}_score"])
    assert zone["under_eye_dark_circle_density"] == round(float(np.mean(scores)), 1)


def test_darkness_keeps_fractional_l_and_equal_eye_weights(zone_inputs):
    captured, _ = zone_inputs
    lab = np.zeros_like(captured["face_bgr"], dtype=np.float32)
    lab[:, :, 0] = 80.25
    bands = {}
    for side, value in (("left", 70.25), ("right", 76.25)):
        band = main._under_eye_region_mask(
            lab.shape[:2], captured["points"], captured["face_skin_mask"], side=side
        ) > 0
        bands[side] = band
        lab[band, 0] = value
    with mock.patch.object(main.cv2, "cvtColor", return_value=lab):
        diagnostics = main._under_eye_darkness_diagnostics(
            captured["face_bgr"], captured["points"],
            captured["face_skin_mask"], captured["regions"],
        )
        for side in ("left", "right"):
            assert diagnostics[f"under_eye_{side}_darkness_band_median_L"] % 1 != 0
        old_score = diagnostics["under_eye_left_darkness_score"]
        lab[bands["left"], 0] += 0.1
        changed = main._under_eye_darkness_diagnostics(
            captured["face_bgr"], captured["points"],
            captured["face_skin_mask"], captured["regions"],
        )
    change = abs(changed["under_eye_left_darkness_score"] - old_score)
    assert 0 < change < 1.0
    with mock.patch.object(main, "_under_eye_darkness_diagnostics", return_value={
        "under_eye_left_darkness_score": 10.25,
        "under_eye_right_darkness_score": 30.75,
    }):
        zone = main._compute_zone_based_metrics(
            captured["face_bgr"], captured["skin_mask"],
            captured["regions"], captured["points"],
        )
    assert zone["under_eye_dark_circle_density"] == 20.5


def test_texture_is_the_band_over_reference_dog_ratio(zone_inputs, caplog):
    captured, _ = zone_inputs
    face, skin, points = captured["face_bgr"], captured["skin_mask"], captured["points"]
    caplog.set_level(logging.INFO, logger=main.logger.name)
    zone = main._compute_zone_based_metrics(face, skin, {}, points)
    line = next(
        r.getMessage() for r in caplog.records if "UNDER_EYE_TEXTURE" in r.getMessage()
    )
    ratio = float(re.search(r"ratio=([\d.]+)", line).group(1))
    assert zone["under_eye_texture_density"] == pytest.approx(
        min(100.0, main.UNDER_EYE_TEXTURE_RATIO_SCALE * ratio), abs=0.06
    )


def test_logging_diagnostics_include_each_eye_measurement(zone_inputs):
    captured, _ = zone_inputs
    diagnostics = main._under_eye_logging_diagnostics(
        captured["face_bgr"],
        captured["points"],
        captured["face_skin_mask"],
    )
    for side in ("left", "right"):
        prefix = f"under_eye_{side}_"
        for field in (
            "offset_eye_widths",
            "band_median_L",
            "reference_median_L",
            "raw_L_delta",
            "dark_circle_density",
            "texture_density",
        ):
            assert prefix + field in diagnostics
        assert diagnostics[f"{prefix}dark_circle_density"] == pytest.approx(
            main.compute_under_eye_dark_circle_density(
                max(0.0, diagnostics[f"{prefix}raw_L_delta"])
            )
        )


def test_formula_versions_bumped_and_old_baselines_refused():
    for key in UNDER_EYE_KEYS:
        current_version = main._metric_formula_version(key)
        assert current_version == (8 if key == "under_eye_dark_circle_density" else 7)
        for old in range(1, current_version):
            assert (
                main._trend_lock_reason(
                    "primary_roi",
                    "primary_roi",
                    "normal",
                    "normal",
                    current_formula_version=current_version,
                    baseline_formula_version=old,
                    current_pose_template="front",
                    baseline_pose_template="front",
                    current_guide_type="facial",
                    baseline_guide_type="facial",
                )
                == "formula_version_mismatch"
            )


def test_export_contains_new_mask_kind_and_pixel_counts(zone_inputs):
    _, result = zone_inputs
    image_quality = result["image_quality"]
    for key in UNDER_EYE_KEYS:
        assert image_quality[f"{key}_mask_kind"] == "under_eye_lash_free_band"
        # Larger than the old lid polygon's ~1,000-1,500 px on this face.
        assert image_quality[f"{key}_mask_pixels"] > 1500
    assert image_quality["under_eye_reference_mask_pixels"] > 1500
