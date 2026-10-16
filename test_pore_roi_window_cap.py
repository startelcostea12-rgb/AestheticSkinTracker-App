"""The pore ROI is bounded by _build_pore_roi_masks' T-zone window (at most
120 x 100 = 12 000 px), so the former 25 000 px "final cap" in
_extract_native_resolution_pore_roi could never fire and was removed. These
tests pin that the returned pore mask is unchanged."""
from __future__ import annotations

import inspect
from pathlib import Path

import cv2
import numpy as np
import pytest

import main
import test_metric_regression_batch as regression

REPO_ROOT = Path(__file__).resolve().parent
CLEAR_FACE = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"


def _pore_inputs(photo: Path):
    main.ensure_pipeline_ready()
    # Same preprocessing as the metric regression manifest's clear_face case.
    image_bytes = regression._prepare_image_bytes(
        photo, {"mode": "resize_jpeg", "size": 512}
    )
    normalized, _ = main.assess_and_normalize_image(image_bytes)
    landmarks, _, _ = main._extract_primary_landmarks(
        cv2.cvtColor(normalized, cv2.COLOR_BGR2RGB)
    )
    assert landmarks is not None
    points = main._landmarks_to_points(landmarks, normalized.shape[1], normalized.shape[0])
    face, _ = main._align_and_crop_face(normalized, points)
    norm = main.normalize_lighting_and_shadows(face)
    norm_landmarks, _, _ = main._extract_primary_landmarks(
        cv2.cvtColor(norm, cv2.COLOR_BGR2RGB)
    )
    assert norm_landmarks is not None
    norm_points = main._landmarks_to_points(norm_landmarks, norm.shape[1], norm.shape[0])
    _, face_skin_mask = main._build_face_skin_mask(
        norm.shape[:2], norm_points, main._skin_mask(norm)
    )
    return norm, norm_points, face_skin_mask


def test_pore_mask_unchanged_on_a_normal_face():
    norm, points, face_skin_mask = _pore_inputs(CLEAR_FACE)
    _, window_mask = main._build_pore_roi_masks(norm.shape[:2], points, face_skin_mask)
    l_crop, mask_crop, pixels = main._extract_native_resolution_pore_roi(
        norm, points, face_skin_mask
    )
    # Same count as before the dead branch was removed (verified old vs new
    # on every regression fixture: clear_face 7954, nikki2 9200, nikki3
    # 9180, st1 6665, portrait_09 3956).
    assert pixels == 7954
    assert pixels == int(cv2.countNonZero(window_mask))
    assert l_crop is not None and mask_crop is not None
    assert l_crop.shape == mask_crop.shape


@pytest.mark.parametrize("size", [(200, 200), (600, 400), (1600, 1200), (4000, 3000)])
def test_window_never_exceeds_12000_pixels(size):
    # Even a whole-image skin mask on a very large face crop is bounded by
    # the 120 x 100 T-zone window, far under the removed 25 000 check.
    w, h = size
    rng = np.random.default_rng(1)
    points = np.column_stack(
        [rng.uniform(0.2 * w, 0.8 * w, 478), rng.uniform(0.2 * h, 0.8 * h, 478)]
    ).astype(np.float32)
    full_skin = np.full((h, w), 255, dtype=np.uint8)
    _, window_mask = main._build_pore_roi_masks((h, w), points, full_skin)
    assert cv2.countNonZero(window_mask) <= 120 * 100


def test_dead_25000_branch_is_gone():
    source = inspect.getsource(main._extract_native_resolution_pore_roi)
    assert "25000" not in source
    assert "tight_mask" not in source
