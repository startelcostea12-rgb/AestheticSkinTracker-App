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

import cv2

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

    return main._extract_native_resolution_pore_roi(norm, norm_points, mask)


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
