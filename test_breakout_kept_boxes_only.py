"""breakout_activity counts only boxes kept at YOLO_CONF_THRESHOLD.

Formula v1 also added 22 x the strongest RAW box, including boxes the keep
threshold rejected, so a photo with zero kept boxes still scored 0.7-3.6 on
the regression fixtures. v2 adds confidence only from kept boxes; zero kept
boxes emit no positive score.
"""
from __future__ import annotations

from pathlib import Path
from unittest import mock

import numpy as np
import pytest

import main

REPO_ROOT = Path(__file__).resolve().parent
CLEAR_FACE_PHOTO = REPO_ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif"


def _canonical(yolo_kept: int, yolo_max_conf: float):
    image = np.full((200, 200, 3), 128, dtype=np.uint8)
    skin = np.full((200, 200), 255, dtype=np.uint8)
    points = np.zeros((468, 2), dtype=np.float32)
    regions = {
        "forehead": skin.copy(),
        "left_cheek": skin.copy(),
        "right_cheek": skin.copy(),
    }
    matrix, confidence, raw = main._compute_canonical_patch_metrics(
        image,
        skin,
        regions,
        points,
        yolo_kept=yolo_kept,
        yolo_max_conf=yolo_max_conf,
    )
    return matrix, confidence, raw


@pytest.mark.parametrize("sub_threshold_conf", [0.0326, 0.1616, 0.17])
def test_zero_kept_boxes_with_sub_threshold_confidence_emit_nothing(sub_threshold_conf):
    matrix, _confidence, raw = _canonical(0, sub_threshold_conf)
    assert "breakout_activity" not in matrix
    # The raw diagnostic still records what the detector saw.
    assert raw["yolo_kept"] == 0
    assert raw["yolo_max_conf"] == pytest.approx(sub_threshold_conf, abs=1e-4)


def test_one_kept_box_scores_from_kept_count_and_confidence():
    matrix, confidence, _raw = _canonical(1, 0.40)
    assert matrix["breakout_activity"] == pytest.approx(14.0 + 0.40 * 22.0)
    assert confidence["breakout_activity"] == "high"


def test_kept_boxes_below_high_confidence_are_medium():
    matrix, confidence, _raw = _canonical(2, 0.20)
    assert matrix["breakout_activity"] == pytest.approx(28.0 + 0.20 * 22.0)
    assert confidence["breakout_activity"] == "medium"


def test_breakout_formula_version_is_three():
    assert main._metric_formula_version("breakout_activity") == 3


@pytest.mark.parametrize("baseline_version", [None, 1])
def test_old_breakout_baseline_is_refused_by_formula_version_gate(baseline_version):
    assert (
        main._trend_lock_reason(
            "full_face_yolo",
            "full_face_yolo",
            "normal",
            "normal",
            current_formula_version=2,
            baseline_formula_version=baseline_version,
            current_pose_template="front",
            baseline_pose_template="front",
            current_guide_type="ai_skin_scan",
            baseline_guide_type="ai_skin_scan",
        )
        == "formula_version_mismatch"
    )


@pytest.fixture(scope="module")
def clear_face():
    normalized, profile, _ = main._assess_and_normalize_image_with_pre_white_balance(
        CLEAR_FACE_PHOTO.read_bytes()
    )
    return normalized, profile


def test_real_photo_with_zero_kept_boxes_omits_breakout(clear_face):
    normalized, profile = clear_face
    result = main.analyze_skin_patch(normalized, quality_profile=dict(profile))

    assert result["model_debug"]["yolo_boxes"] == 0
    assert "breakout_activity" not in result["metric_matrix"]
    # Legacy top-level fields stay, unchanged, and are not the card score.
    assert result["acne_activity_score"] == 100.0
    assert result["raw_pore_density"] == 0.0


def test_pipeline_locks_a_v1_breakout_baseline_against_v2(clear_face):
    normalized, profile = clear_face
    common = {
        "quality_profile": dict(profile),
        "capture_quality": "normal",
        "baseline_capture_quality": "normal",
        "pose_template": "front",
        "baseline_pose_template": "front",
        "guide_type": "ai_skin_scan",
        "baseline_guide_type": "ai_skin_scan",
    }
    with mock.patch.object(main, "_run_yolo_detection_stats", return_value=(1, 0.40)):
        result = main.analyze_skin_patch(
            normalized,
            baseline_matrix={"breakout_activity": 3.6},
            baseline_extraction_paths={"breakout_activity": "full_face_yolo"},
            baseline_formula_versions={"breakout_activity": 1},
            **common,
        )

    assert result["metric_matrix"]["breakout_activity"] == pytest.approx(22.8)
    assert result["metric_formula_versions"]["breakout_activity"] == 3
    assert result["trend_lock_reasons"]["breakout_activity"] == "formula_version_mismatch"
