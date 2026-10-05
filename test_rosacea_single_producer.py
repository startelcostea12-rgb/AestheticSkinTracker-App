"""rosacea_severity has exactly one producer: the U-zone formula in
_compute_zone_based_metrics. When that formula does not emit, the metric is
omitted -- never rebuilt afterwards from emitted localized_redness and
diffuse_flushing_erythema, and never substituted with 0.
"""
from __future__ import annotations

from pathlib import Path
from unittest import mock

import numpy as np
import pytest

import main

REPO_ROOT = Path(__file__).resolve().parent
CLEAR_FACE_PHOTO = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"


@pytest.fixture(scope="module")
def clear_face_input():
    normalized, profile, _ = main._assess_and_normalize_image_with_pre_white_balance(
        CLEAR_FACE_PHOTO.read_bytes()
    )
    return normalized, profile


def _analyze_with_zone_rosacea(clear_face_input, rosacea_value):
    normalized, profile = clear_face_input
    real_zone = main._compute_zone_based_metrics
    zone_outputs = []

    def patched_zone(*args, **kwargs):
        zone = real_zone(*args, **kwargs)
        if rosacea_value is not _UNCHANGED:
            zone["rosacea_severity"] = rosacea_value
        zone_outputs.append(dict(zone))
        return zone

    with mock.patch.object(main, "_compute_zone_based_metrics", patched_zone):
        result = main.analyze_skin_patch(normalized, quality_profile=dict(profile))
    return result, zone_outputs[-1]


_UNCHANGED = object()


def test_rosacea_is_omitted_when_zone_formula_does_not_emit(clear_face_input):
    result, _ = _analyze_with_zone_rosacea(clear_face_input, None)
    matrix = result["metric_matrix"]

    # The removed recomputation fired exactly under these conditions:
    # emitted redness > 0 and a missing rosacea. Both hold here, so it
    # would have filled rosacea; it must not.
    assert matrix["localized_redness"] > 0.0
    assert "rosacea_severity" not in matrix
    assert result["metric_status"]["rosacea_severity"] == "unavailable"
    assert result["omitted_metric_reasons"]["rosacea_severity"] == "non_usable_value"


def test_zone_zero_is_not_rebuilt_from_redness(clear_face_input):
    # A measured zone 0.0 is a real reading. The old branch treated a
    # nonpositive rosacea as missing and overwrote it from redness.
    result, _ = _analyze_with_zone_rosacea(clear_face_input, 0.0)
    matrix = result["metric_matrix"]

    assert matrix["localized_redness"] > 0.0
    assert matrix["rosacea_severity"] == 0.0


def test_real_zone_result_is_emitted_unchanged(clear_face_input):
    result, zone = _analyze_with_zone_rosacea(clear_face_input, _UNCHANGED)

    assert zone["rosacea_severity"] > 0.0
    assert result["metric_matrix"]["rosacea_severity"] == zone["rosacea_severity"]
    assert result["metric_extraction_paths"]["rosacea_severity"] == "primary_roi"


def test_post_emission_recomputation_is_gone():
    source = Path(main.__file__).read_text()
    assert "ROSACEA_CALIB_POST_FORCE" not in source
    assert "post_force_calibration" not in source


def test_rosacea_formula_version_bumped():
    assert main._metric_formula_version("rosacea_severity") == 3


def test_empty_crop_returns_no_rosacea():
    empty = np.zeros((0, 0, 3), dtype=np.uint8)
    zone = main._compute_zone_based_metrics(
        empty, np.zeros((0, 0), dtype=np.uint8), {}, np.zeros((0, 2), dtype=np.float32)
    )
    assert zone["rosacea_severity"] is None


def test_empty_crop_omits_rosacea_from_pipeline(clear_face_input):
    normalized, profile = clear_face_input
    real_zone = main._compute_zone_based_metrics

    def empty_crop_zone(face_bgr, skin_mask, regions, points, **kwargs):
        return real_zone(face_bgr[:0, :0], skin_mask[:0, :0], regions, points, **kwargs)

    with mock.patch.object(main, "_compute_zone_based_metrics", empty_crop_zone):
        result = main.analyze_skin_patch(normalized, quality_profile=dict(profile))

    assert result["metric_matrix"]["localized_redness"] > 0.0
    assert "rosacea_severity" not in result["metric_matrix"]
    assert result["omitted_metric_reasons"]["rosacea_severity"] == "non_usable_value"
