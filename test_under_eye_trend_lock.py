"""Under-eye trend locks once the app sends the baseline scan's stored
under-eye extraction path (see aiBaselineExtractionPathsForRequest in
skin_ai_analysis_screen.dart). Same path and same formula version must not
lock on path_mismatch; a missing baseline path still does; an older-version
baseline still locks on formula_version_mismatch.
"""
from __future__ import annotations

from pathlib import Path
from unittest import mock

import numpy as np
import pytest

import main

REPO_ROOT = Path(__file__).resolve().parent
CLEAR_FACE_PHOTO = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"
UNDER_EYE_KEYS = ("under_eye_texture_density", "under_eye_dark_circle_density")
CURRENT_VERSION = 3


@pytest.fixture(scope="module")
def scan():
    normalized, profile, _ = main._assess_and_normalize_image_with_pre_white_balance(
        CLEAR_FACE_PHOTO.read_bytes()
    )
    common = {
        "quality_profile": dict(profile),
        "capture_quality": "normal",
        "baseline_capture_quality": "normal",
        "pose_template": "front",
        "baseline_pose_template": "front",
        "guide_type": "ai_skin_scan",
        "baseline_guide_type": "ai_skin_scan",
    }
    first = main.analyze_skin_patch(normalized, **common)
    baseline = {key: first["metric_matrix"][key] * 1.3 for key in UNDER_EYE_KEYS}
    return normalized, common, baseline


def _compare(scan, baseline_paths, baseline_version, *, baseline_matrix=None, empty_mask=False):
    normalized, common, baseline = scan
    kwargs = dict(common)
    kwargs["quality_profile"] = dict(common["quality_profile"])
    patches = []
    if empty_mask:
        patches.append(
            mock.patch.object(
                main,
                "_under_eye_region_mask",
                lambda shape, points, skin_mask, *, side: np.zeros(shape, dtype=np.uint8),
            )
        )
    for patch in patches:
        patch.start()
    try:
        return main.analyze_skin_patch(
            normalized,
            baseline_matrix=dict(baseline if baseline_matrix is None else baseline_matrix),
            baseline_extraction_paths=baseline_paths,
            baseline_formula_versions={key: baseline_version for key in UNDER_EYE_KEYS},
            **kwargs,
        )
    finally:
        for patch in patches:
            patch.stop()


def test_current_under_eye_version_is_three():
    for key in UNDER_EYE_KEYS:
        assert main._metric_formula_version(key) == CURRENT_VERSION


def test_same_path_same_version_does_not_lock_on_path(scan):
    result = _compare(scan, {key: "primary_roi" for key in UNDER_EYE_KEYS}, CURRENT_VERSION)
    for key in UNDER_EYE_KEYS:
        assert result["metric_extraction_paths"][key] == "primary_roi"
        assert key in result["trend_status"]
        assert result["trend_lock_reasons"].get(key) != "path_mismatch"
        assert result["trend_lock_reasons"].get(key) is None


def test_missing_baseline_path_still_locks_on_path(scan):
    result = _compare(scan, {}, CURRENT_VERSION)
    for key in UNDER_EYE_KEYS:
        assert result["trend_lock_reasons"][key] == "path_mismatch"


@pytest.mark.parametrize("baseline_version", [1, 2])
def test_older_baseline_version_locks_on_formula_version(scan, baseline_version):
    result = _compare(scan, {key: "primary_roi" for key in UNDER_EYE_KEYS}, baseline_version)
    for key in UNDER_EYE_KEYS:
        assert result["trend_lock_reasons"][key] == "formula_version_mismatch"


def test_omitted_vs_omitted_makes_no_comparison(scan):
    result = _compare(
        scan,
        {key: "skipped" for key in UNDER_EYE_KEYS},
        CURRENT_VERSION,
        baseline_matrix={},
        empty_mask=True,
    )
    for key in UNDER_EYE_KEYS:
        assert key not in result["metric_matrix"]
        assert result["metric_extraction_paths"][key] == "skipped"
        assert key not in result["trend_status"]
        assert key not in result["trend_lock_reasons"]
