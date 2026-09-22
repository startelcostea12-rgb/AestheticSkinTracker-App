"""Regression coverage for A2's threshold-publishing contract.

Context: _trend_delta_and_status's measured-noise-floor gate runs once per
backend call, against a single frame's raw value -- but the app averages
several frames' values client-side into the number it actually displays.
Re-applying the SAME noise-floor policy client-side (against the averaged
value) requires the client to have the actual threshold numbers, without
hardcoding a second, driftable copy of main.py's calibration table in Dart.
The fix: analyze_skin_patch echoes METRIC_NOISE_FLOOR_2SD /
TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE / TREND_NOISE_FLOOR_EXCLUDED_MULTIPLIER
in its response payload, and
lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart's
downgradeTrendBelowMeasuredNoiseFloor reads them from there.

This suite locks in that the response payload actually carries those three
fields, with values matching the constants exactly -- the contract the
Dart-side gate depends on -- using a real photo through the real pipeline
rather than a source-text check, so a refactor that silently drops the
fields from the response dict (while leaving the constants themselves
intact) is caught.
"""
from __future__ import annotations

import re
from pathlib import Path

import main

REPO_ROOT = Path(__file__).resolve().parent
CLEAR_FACE_PHOTO = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"
MAIN_PY = REPO_ROOT / "main.py"


def test_response_payload_echoes_the_noise_floor_thresholds_exactly():
    image_bytes = CLEAR_FACE_PHOTO.read_bytes()
    normalized_bgr, quality_profile = main.assess_and_normalize_image(image_bytes)
    result = main.analyze_skin_patch(normalized_bgr, quality_profile=quality_profile)

    assert result.get("metric_noise_floor_2sd") == main.METRIC_NOISE_FLOOR_2SD
    assert result.get("trend_noise_floor_exceeds_useful_range") == sorted(
        main.TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE
    )
    assert (
        result.get("trend_noise_floor_excluded_multiplier")
        == main.TREND_NOISE_FLOOR_EXCLUDED_MULTIPLIER
    )


def test_trend_noise_floor_exceeds_useful_range_is_json_serializable_as_a_list():
    # A bare Python set is not valid JSON; the response payload must carry
    # a list, not the set object itself, or the client never receives it.
    image_bytes = CLEAR_FACE_PHOTO.read_bytes()
    normalized_bgr, quality_profile = main.assess_and_normalize_image(image_bytes)
    result = main.analyze_skin_patch(normalized_bgr, quality_profile=quality_profile)

    assert isinstance(result.get("trend_noise_floor_exceeds_useful_range"), list)


def test_calibration_log_metrics_includes_pore_visibility_and_breakout_activity():
    # pore_visibility and breakout_activity previously had no CALIBRATION_LOG
    # history at all, so tool/analyze_repeatability.py had no data to
    # measure a noise floor from -- confirmed by pore_visibility reporting a
    # 17% "improvement" on an unchanged face while fully ungated. Adding
    # them here lets a future repeatability session measure real floors.
    source = MAIN_PY.read_text(encoding="utf-8")
    match = re.search(
        r"calibration_log_metrics = \[(?P<body>.*?)\]",
        source,
        re.DOTALL,
    )
    assert match is not None, "calibration_log_metrics list not found in main.py"
    body = match.group("body")
    assert '"pore_visibility"' in body
    assert '"breakout_activity"' in body


def test_calibration_roi_pixels_has_entries_for_the_two_new_metrics():
    source = MAIN_PY.read_text(encoding="utf-8")
    match = re.search(
        r"calibration_roi_pixels = \{(?P<body>.*?)\}",
        source,
        re.DOTALL,
    )
    assert match is not None, "calibration_roi_pixels dict not found in main.py"
    body = match.group("body")
    assert '"pore_visibility":' in body
    assert '"breakout_activity":' in body
