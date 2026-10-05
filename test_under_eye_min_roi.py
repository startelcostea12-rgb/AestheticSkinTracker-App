"""under_eye_texture_density and under_eye_dark_circle_density share one
under-eye mask. Below MIN_USABLE_TZONE_PIXELS that mask is a shadow pocket,
not a measurement, so both metrics are omitted. At or above it they are
emitted exactly as the (unchanged) zone formulas produce them.
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


def test_minimum_is_the_existing_tzone_floor():
    assert main.MIN_USABLE_TZONE_PIXELS == 1500


def test_under_eye_omitted_below_existing_minimum(clear_face_input, caplog):
    caplog.set_level(logging.INFO, logger=main.logger.name)
    result, zone = _analyze(clear_face_input)
    assert _logged_under_eye_pixels(caplog) < main.MIN_USABLE_TZONE_PIXELS

    # The zone formulas still produced values; the mask is just too small.
    for key in UNDER_EYE_KEYS:
        assert zone[key] is not None
        assert key not in result["metric_matrix"]
        assert result["metric_status"][key] == "unavailable"
        assert result["omitted_metric_reasons"][key] == "under_eye_roi_too_small"


def test_under_eye_emitted_above_existing_minimum(clear_face_input, caplog):
    real_mask = main._under_eye_region_mask

    def widened_mask(shape, points, skin_mask, *, side):
        # Same landmarks, but with the skin mask treated as full so the
        # union clears the floor; scores still come from the real formulas.
        mask = real_mask(shape, points, np.full(shape, 255, dtype=np.uint8), side=side)
        return cv2.dilate(mask, np.ones((9, 9), dtype=np.uint8))

    caplog.set_level(logging.INFO, logger=main.logger.name)
    result, zone = _analyze(clear_face_input, widened_mask)
    assert _logged_under_eye_pixels(caplog) >= main.MIN_USABLE_TZONE_PIXELS

    for key in UNDER_EYE_KEYS:
        assert result["omitted_metric_reasons"].get(key) != "under_eye_roi_too_small"
        assert result["metric_matrix"][key] == zone[key]


def test_under_eye_formula_versions_bumped():
    for key in UNDER_EYE_KEYS:
        assert main._metric_formula_version(key) == 2
