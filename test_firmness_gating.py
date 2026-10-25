"""structural_firmness_elasticity is a landmark-ratio score, so it must be
omitted (never 0.0) when landmarks are missing or the head is not frontal, and
downstream trend code must treat the omission as 'no reading', not as 0."""

from __future__ import annotations

import logging
from pathlib import Path

import cv2
import numpy as np
import pytest

import main

KEY = "structural_firmness_elasticity"


def _frontal_points(*, yaw_offset: float = 0.0, nose_drop: float = 36.0) -> np.ndarray:
    """468 landmarks with a level, symmetric face: pose proxy ~ (0 pitch, 0 yaw)
    when the offsets are 0. Eyes 100 apart, forehead->chin 200 tall."""
    pts = np.full((468, 2), 250.0, dtype=np.float32)
    pts[33] = (200.0, 200.0)
    pts[263] = (300.0, 200.0)
    pts[1] = (250.0 + yaw_offset, 200.0 + nose_drop)
    pts[10] = (250.0, 100.0)
    pts[152] = (250.0, 300.0)
    for idx in (6, 168, 197):
        pts[idx] = (250.0, 215.0)
    for idx in (149, 176, 377, 400):
        pts[idx] = (250.0, 285.0)
    for idx in (61, 291):
        pts[idx] = (250.0, 262.0)
    return pts


def _expected_firmness(pts: np.ndarray) -> float:
    upper = np.mean(pts[[6, 168, 197], 1])
    jaw = np.mean(pts[[152, 149, 176, 377, 400], 1])
    naso = np.mean(pts[[61, 291], 1])
    height = float(pts[:, 1].max() - pts[:, 1].min())
    drift = ((jaw - upper) * 0.65 + (naso - upper) * 0.35) / height
    return float(np.clip((0.72 - drift) / 0.34 * 100.0, 0.0, 100.0))


def _structural(points: np.ndarray) -> dict:
    image = np.full((400, 500, 3), 128, dtype=np.uint8)
    empty = np.zeros((400, 500), dtype=np.uint8)
    return main._compute_structural_opencv_metrics(
        image, empty, {"left_cheek": empty, "right_cheek": empty}, points
    )


def test_frontal_complete_landmarks_are_scored_with_the_original_formula():
    pts = _frontal_points()
    assert main._firmness_gate_reason(pts) is None
    result = _structural(pts)
    assert result[KEY] == pytest.approx(_expected_firmness(pts), abs=0.1)


@pytest.mark.parametrize(
    "points",
    [
        None,
        np.zeros((0, 2), dtype=np.float32),
        np.zeros((100, 2), dtype=np.float32),  # too few landmarks
        np.zeros((468, 2), dtype=np.float32),  # degenerate: all at one point
    ],
)
def test_missing_landmarks_omit_firmness_instead_of_zero(points):
    assert main._firmness_gate_reason(points) == "landmarks_missing"
    if points is not None and points.shape[0] > 0:
        result = _structural(points)
        assert KEY not in result  # not 0.0, not present at all


def test_nan_landmark_counts_as_missing():
    pts = _frontal_points()
    pts[152] = (np.nan, np.nan)
    assert main._firmness_gate_reason(pts) == "landmarks_missing"
    assert KEY not in _structural(pts)


def test_early_return_for_empty_image_does_not_emit_firmness_zero():
    empty_img = np.zeros((0, 0, 3), dtype=np.uint8)
    result = main._compute_structural_opencv_metrics(
        empty_img, np.zeros((0, 0), dtype=np.uint8), {}, _frontal_points()
    )
    assert KEY not in result


@pytest.mark.parametrize(
    ("kwargs", "label"),
    [
        ({"yaw_offset": 30.0}, "yaw ~27 deg"),
        ({"yaw_offset": -30.0}, "yaw ~-27 deg"),
        ({"nose_drop": 80.0}, "pitch down"),
        ({"nose_drop": -10.0}, "pitch up"),
    ],
)
def test_non_frontal_pose_omits_firmness(kwargs, label):
    pts = _frontal_points(**kwargs)
    pitch, yaw = main._compute_pose_pitch_yaw_from_landmarks(pts)
    assert not main._pose_is_frontal(pitch, yaw), label
    assert main._firmness_gate_reason(pts) == "pose_not_frontal"
    assert KEY not in _structural(pts)


def test_pose_limits_match_the_pore_gate_thresholds():
    assert main.FRONTAL_POSE_MAX_ABS_PITCH == 20.0
    assert main.FRONTAL_POSE_MAX_ABS_YAW == 18.0
    assert main._pose_is_frontal(20.0, 18.0)
    assert not main._pose_is_frontal(20.1, 0.0)
    assert not main._pose_is_frontal(0.0, -18.1)


# ── downstream handling of an omitted firmness ──────────────────────────


def _trend_kwargs(keys):
    return dict(
        current_paths={k: "primary_roi" for k in keys},
        baseline_paths={k: "primary_roi" for k in keys},
        current_formula_versions={k: main._metric_formula_version(k) for k in keys},
        baseline_formula_versions={k: main._metric_formula_version(k) for k in keys},
        current_pose_template="Front",
        baseline_pose_template="Front",
        current_guide_type="facial",
        baseline_guide_type="facial",
    )


@pytest.mark.parametrize("current", [{"texture_smoothness": 60.0}, {"texture_smoothness": 60.0, KEY: None}])
def test_trend_deltas_skip_a_missing_current_firmness(current):
    baseline = {"texture_smoothness": 50.0, KEY: 55.0}
    keys = list(baseline)
    deltas = main._compute_trend_deltas(current, baseline, **_trend_kwargs(keys))
    assert KEY not in deltas  # no fabricated "firmness fell 100%" delta
    assert "texture_smoothness" in deltas
    statuses = main._compute_trend_statuses(current, baseline, **_trend_kwargs(keys))
    assert KEY not in statuses


def test_trend_deltas_skip_a_missing_baseline_firmness():
    current = {KEY: 55.0}
    deltas = main._compute_trend_deltas(current, {}, **_trend_kwargs([KEY]))
    assert deltas == {}


# ── end to end through analyze_skin_patch ───────────────────────────────

ST1 = Path(__file__).resolve().parent / "test_fixtures" / "metric_regression" / "st1.jpg"


def _analyze_st1() -> dict:
    logging.disable(logging.CRITICAL)
    try:
        data = cv2.imencode(".png", cv2.imread(str(ST1)))[1].tobytes()
        normalized, quality = main.assess_and_normalize_image(data)
        return main.analyze_skin_patch(normalized, quality_profile=quality)
    finally:
        logging.disable(logging.NOTSET)


def test_pipeline_omits_firmness_and_reports_reason_when_pose_is_not_frontal(monkeypatch):
    monkeypatch.setattr(main, "_compute_pose_pitch_yaw_from_landmarks", lambda pts: (0.0, 40.0))
    result = _analyze_st1()
    assert KEY not in (result.get("metric_matrix") or {})
    assert result.get(KEY) is None
    assert result["omitted_metric_reasons"][KEY] == "pose_not_frontal"


def test_pipeline_emits_firmness_when_pose_is_frontal(monkeypatch):
    monkeypatch.setattr(main, "_compute_pose_pitch_yaw_from_landmarks", lambda pts: (0.0, 0.0))
    result = _analyze_st1()
    value = (result.get("metric_matrix") or {}).get(KEY)
    assert value is not None and 0.0 <= value <= 100.0
    assert KEY not in result["omitted_metric_reasons"]
