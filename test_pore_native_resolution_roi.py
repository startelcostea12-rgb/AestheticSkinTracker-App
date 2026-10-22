"""Regression test for the pore_visibility native-resolution ROI fix.

Historical bug: _extract_normalized_pore_roi (now
_extract_native_resolution_pore_roi) upsampled a small (~80-120px) native
face crop to a fixed 512x512 canvas *before* running the DoG frequency
analysis used to compute pore_visibility. This destroyed real pore-scale
detail (crushing pore_spread into a narrow low band across real photos)
and made the pore_roi_pixels size gate measure the resized canvas instead
of real available detail, so it could never meaningfully reject anything.

This test locks in that the DoG analysis crop:
  1. is never upsampled to a fixed normalization canvas, and
  2. reports a pixel count proportional to the real crop, not ~262144.
"""

from __future__ import annotations

from pathlib import Path
from unittest import mock

import cv2
import numpy as np

import main

REPO_ROOT = Path(__file__).resolve().parent
CLEAR_FACE_PHOTO = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"


def _native_pore_roi_for(photo_path: Path):
    main.ensure_pipeline_ready()
    image_bytes = photo_path.read_bytes()
    normalized_bgr, _quality_profile = main.assess_and_normalize_image(image_bytes)
    rgb = cv2.cvtColor(normalized_bgr, cv2.COLOR_BGR2RGB)
    landmarks, _count, _source = main._extract_primary_landmarks(rgb)
    assert landmarks is not None, "Fixture must produce landmarks for this test to be meaningful."

    points = main._landmarks_to_points(landmarks, normalized_bgr.shape[1], normalized_bgr.shape[0])
    aligned_face, _aligned_points = main._align_and_crop_face(normalized_bgr, points)
    norm = main.normalize_lighting_and_shadows(aligned_face)
    mask = main._skin_mask(norm)

    norm_rgb = cv2.cvtColor(norm, cv2.COLOR_BGR2RGB)
    norm_landmarks, _norm_count, _norm_source = main._extract_primary_landmarks(norm_rgb)
    assert norm_landmarks is not None
    norm_points = main._landmarks_to_points(norm_landmarks, norm.shape[1], norm.shape[0])

    _, face_skin_mask = main._build_face_skin_mask(
        norm.shape[:2], norm_points, mask
    )
    return main._extract_native_resolution_pore_roi(
        norm, norm_points, face_skin_mask
    )


def _face_and_pore_masks_for(photo_path: Path):
    main.ensure_pipeline_ready()
    normalized_bgr, _ = main.assess_and_normalize_image(photo_path.read_bytes())
    landmarks, _, _ = main._extract_primary_landmarks(
        cv2.cvtColor(normalized_bgr, cv2.COLOR_BGR2RGB)
    )
    assert landmarks is not None
    points = main._landmarks_to_points(
        landmarks, normalized_bgr.shape[1], normalized_bgr.shape[0]
    )
    aligned_face, _ = main._align_and_crop_face(normalized_bgr, points)
    norm = main.normalize_lighting_and_shadows(aligned_face)
    skin_mask = main._skin_mask(norm)
    norm_landmarks, _, _ = main._extract_primary_landmarks(
        cv2.cvtColor(norm, cv2.COLOR_BGR2RGB)
    )
    assert norm_landmarks is not None
    norm_points = main._landmarks_to_points(
        norm_landmarks, norm.shape[1], norm.shape[0]
    )
    _, face_skin_mask = main._build_face_skin_mask(
        norm.shape[:2], norm_points, skin_mask
    )
    _, pore_roi_mask = main._build_pore_roi_masks(
        norm.shape[:2], norm_points, face_skin_mask
    )
    regions = main._region_masks(norm.shape[:2], skin_mask, norm_points)
    forehead_skin_mask = cv2.bitwise_and(
        regions["forehead"], face_skin_mask
    )
    return face_skin_mask, pore_roi_mask, forehead_skin_mask


def test_face_skin_mask_is_not_limited_to_pore_tzone_window():
    face_skin_mask, pore_roi_mask, _ = _face_and_pore_masks_for(CLEAR_FACE_PHOTO)

    face_pixels = cv2.countNonZero(face_skin_mask)
    pore_pixels = cv2.countNonZero(pore_roi_mask)
    assert face_pixels > pore_pixels > 0

    ys, xs = (pore_roi_mask > 0).nonzero()
    assert int(xs.max() - xs.min() + 1) <= 120
    assert int(ys.max() - ys.min() + 1) <= 100


def test_forehead_face_skin_intersection_is_nontrivial_on_normal_face():
    _, _, forehead_skin_mask = _face_and_pore_masks_for(CLEAR_FACE_PHOTO)
    assert cv2.countNonZero(forehead_skin_mask) >= main.MIN_USABLE_TEXTURE_ROI_PIXELS


def test_pore_roi_crop_is_not_upsampled_to_fixed_canvas():
    l_crop, mask_crop, pixel_count = _native_pore_roi_for(CLEAR_FACE_PHOTO)

    assert l_crop is not None
    assert mask_crop is not None
    # The old bug always returned a (512, 512) canvas regardless of the
    # real crop size; the fix must return the native crop dimensions.
    assert l_crop.shape != (512, 512)
    assert mask_crop.shape != (512, 512)
    assert l_crop.shape == mask_crop.shape

    # A real T-zone/cheek crop box is capped at 120x100 px in native
    # resolution, so its pixel count must be far below a 512x512 canvas
    # (262144 px), which is what the old bug always reported.
    assert 0 < pixel_count < 15000


def test_pore_visibility_reaches_high_confidence_on_real_clear_face_photo():
    # Historically, no real photo ever reached "high" confidence
    # (pore_spread >= 2.5) because upsampling crushed the DoG spread signal.
    # After the fix, a real clear-face reference should reach it.
    image_bytes = CLEAR_FACE_PHOTO.read_bytes()
    normalized_bgr, quality_profile = main.assess_and_normalize_image(image_bytes)
    result = main.analyze_skin_patch(normalized_bgr, quality_profile=quality_profile)

    metric_confidence = result.get("metric_confidence") or {}
    metric_matrix = result.get("metric_matrix") or {}

    assert metric_confidence.get("pore_visibility") == "high"
    assert metric_matrix.get("pore_visibility") is not None
    assert result["metric_extraction_paths"]["pore_visibility"] == "primary_roi"


def test_pore_visibility_omission_path_reports_pose_crop_and_dog_spread():
    valid_components = {
        "pore_visibility_face_detected": 1.0,
        "pore_visibility_pose_ok": 1.0,
        "pore_visibility_crop_available": 1.0,
        "primary_pore_roi_pixels": 9100.0,
        "pore_visibility_dog_spread_failed": 0.0,
    }

    assert main._pore_visibility_omission_path(
        {**valid_components, "pore_visibility_pose_ok": 0.0}
    ) == "pose"
    assert main._pore_visibility_omission_path(
        {**valid_components, "pore_visibility_dog_spread_failed": 1.0}
    ) == "dog_spread"
    assert main._pore_visibility_omission_path(
        {**valid_components, "pore_visibility_crop_available": 0.0}
    ) == "crop"
    assert main._pore_visibility_omission_path(valid_components) == "skipped"


def test_pore_visibility_is_omitted_below_5000_pixels_without_fallback():
    image = np.full((120, 120, 3), 128, dtype=np.uint8)
    skin = np.full((120, 120), 255, dtype=np.uint8)
    points = np.zeros((468, 2), dtype=np.float32)
    regions = {
        "forehead": skin.copy(),
        "left_cheek": skin.copy(),
        "right_cheek": skin.copy(),
    }
    pore_crop = np.full((71, 71), 128, dtype=np.float32)
    pore_mask = np.full((71, 71), 255, dtype=np.uint8)

    with mock.patch.object(
        main,
        "_extract_native_resolution_pore_roi",
        return_value=(pore_crop, pore_mask, 4999),
    ):
        matrix, _confidence, raw = main._compute_canonical_patch_metrics(
            image,
            skin,
            regions,
            points,
            yolo_kept=0,
            yolo_max_conf=0.0,
        )

    assert "pore_visibility" not in matrix
    assert raw["primary_pore_roi_pixels"] == 4999
    # There is no pore fallback ROI: nothing else is emitted for it.
    assert "fallback_pore_roi_pixels" not in raw
    assert "pore_fallback_used" not in raw


def test_chin_pore_visibility_is_separate_from_tzone_and_omitted_under_5000_pixels():
    image = np.full((200, 200, 3), 128, dtype=np.uint8)
    skin = np.full((200, 200), 255, dtype=np.uint8)
    points = np.zeros((468, 2), dtype=np.float32)
    regions = {
        "forehead": skin.copy(),
        "left_cheek": skin.copy(),
        "right_cheek": skin.copy(),
    }

    chin_crop = np.full((71, 71), 128, dtype=np.float32)
    chin_mask = np.full((71, 71), 255, dtype=np.uint8)
    tzone_crop = np.linspace(100.0, 200.0, num=71 * 71, dtype=np.float32).reshape(71, 71)
    tzone_mask = np.full((71, 71), 255, dtype=np.uint8)

    with mock.patch.object(
        main,
        "_extract_native_resolution_chin_pore_roi",
        return_value=(chin_crop, chin_mask, 4999),
    ), mock.patch.object(
        main,
        "_extract_native_resolution_pore_roi",
        return_value=(tzone_crop, tzone_mask, 15000),
    ):
        matrix, _confidence, raw = main._compute_canonical_patch_metrics(
            image,
            skin,
            regions,
            points,
            yolo_kept=0,
            yolo_max_conf=0.0,
        )

    assert "chin_pore_visibility" not in matrix
    assert raw["chin_pore_visibility_mask_pixels"] == 4999
    assert raw["chin_pore_visibility_mask_pixels"] < raw["primary_pore_roi_pixels"]
    assert raw["primary_pore_roi_pixels"] == 15000
    assert raw["chin_pore_visibility_mask_kind"] == "chin_pore"
