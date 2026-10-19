"""under_eye_texture_density and under_eye_dark_circle_density share one
under-eye mask. There is no pixel-count omit gate on that mask: a phone-sized
mask (~1200 px) emits both metrics at the zone formulas' own values. The
mask's pixel count and any omit reason are exported on every scan.
"""
from __future__ import annotations

import contextlib
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
def clear_face_input():
    normalized, profile, _ = main._assess_and_normalize_image_with_pre_white_balance(
        CLEAR_FACE_PHOTO.read_bytes()
    )
    return normalized, profile


def _logged_under_eye_pixels(caplog) -> int:
    for record in reversed(caplog.records):
        match = re.search(r"SMALL_ROI_PIXELS glabella=\d+ under_eye=(\d+)", record.getMessage())
        if match:
            return int(match.group(1))
    raise AssertionError("SMALL_ROI_PIXELS log line not found")


def _analyze(clear_face_input, under_eye_mask_factory=None):
    normalized, profile = clear_face_input
    real_zone = main._compute_zone_based_metrics
    zone_outputs = []

    def recording_zone(*args, **kwargs):
        zone = real_zone(*args, **kwargs)
        zone_outputs.append(dict(zone))
        return zone

    with contextlib.ExitStack() as stack:
        stack.enter_context(
            mock.patch.object(main, "_compute_zone_based_metrics", recording_zone)
        )
        if under_eye_mask_factory is not None:
            stack.enter_context(
                mock.patch.object(main, "_under_eye_region_mask", under_eye_mask_factory)
            )
        result = main.analyze_skin_patch(normalized, quality_profile=dict(profile))
    return result, zone_outputs[-1]


def _phone_sized_mask(shape, points, skin_mask, *, side):
    # One eye's real lash-free band only: ~1,100-1,300 px on the clear-face
    # fixture, under the old 1500 px gate (the phone scans measured 1194,
    # 1254, 1282 on the old geometry).
    if side != "left":
        return np.zeros(shape, dtype=np.uint8)
    return _REAL_UNDER_EYE_MASK(shape, points, skin_mask, side=side)


def _empty_mask(shape, points, skin_mask, *, side):
    return np.zeros(shape, dtype=np.uint8)


_REAL_UNDER_EYE_MASK = main._under_eye_region_mask


def test_phone_sized_mask_emits_both_metrics_at_their_own_values(clear_face_input, caplog):
    caplog.set_level(logging.INFO, logger=main.logger.name)
    result, zone = _analyze(clear_face_input, _phone_sized_mask)
    pixels = _logged_under_eye_pixels(caplog)

    assert 0 < pixels < 1500
    for key in UNDER_EYE_KEYS:
        assert result["metric_matrix"][key] == zone[key]
        assert key not in result["omitted_metric_reasons"]
        assert result["image_quality"][f"{key}_mask_kind"] == main.UNDER_EYE_MASK_KIND
        assert result["image_quality"][f"{key}_mask_pixels"] == pixels
        assert result["image_quality"][f"{key}_omit_reason"] is None


def test_real_clear_face_mask_emits_both_metrics(clear_face_input, caplog):
    caplog.set_level(logging.INFO, logger=main.logger.name)
    result, zone = _analyze(clear_face_input)
    pixels = _logged_under_eye_pixels(caplog)

    for key in UNDER_EYE_KEYS:
        assert result["metric_matrix"][key] == zone[key]
        assert result["image_quality"][f"{key}_mask_pixels"] == pixels


def test_empty_mask_still_omits_and_exports_count_and_reason(clear_face_input):
    result, _ = _analyze(clear_face_input, _empty_mask)

    for key in UNDER_EYE_KEYS:
        assert key not in result["metric_matrix"]
        reason = result["omitted_metric_reasons"][key]
        assert reason
        assert result["image_quality"][f"{key}_mask_pixels"] == 0
        assert result["image_quality"][f"{key}_omit_reason"] == reason


def test_under_eye_roi_too_small_gate_is_gone():
    assert "under_eye_roi_too_small" not in Path(main.__file__).read_text()


def test_under_eye_formula_versions_bumped():
    for key in UNDER_EYE_KEYS:
        assert main._metric_formula_version(key) == 5
