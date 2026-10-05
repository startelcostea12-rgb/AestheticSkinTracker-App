import unittest

import numpy as np

import main
from main import (
    METRIC_FORMULA_VERSION,
    METRIC_NOISE_FLOOR_2SD,
    TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE,
    TREND_NOISE_FLOOR_EXCLUDED_MULTIPLIER,
    _body_consistent_scan_count,
    _body_trend_delta_and_status,
    _body_trend_lock_reason,
    _baseline_formula_versions_for_redness_reference,
    _compute_body_silhouette_trend,
    _coalesce_personal_lab_baseline,
    _compute_redness_from_personal_baseline,
    _compute_trend_deltas,
    _compute_trend_lock_reasons,
    _compute_trend_statuses,
    _metric_formula_version,
    _normalize_baseline_metric_formula_versions,
    _normalize_capture_quality,
    _normalize_metric_formula_versions,
    _trend_delta_and_status,
    _trend_lock_reason,
)


class BodyConsistentScanCountTests(unittest.TestCase):
    @staticmethod
    def _result(scale: float = 200.0) -> dict[str, float]:
        return {
            "normalized_area_index": 120.0,
            "scale_reference_pixels": scale,
            "confidence": 0.85,
        }

    def test_sequence_increments_only_for_consistent_pairs_and_gates_trends(self) -> None:
        baseline = self._result()
        second = self._result(210.0)
        third = self._result(205.0)
        inconsistent = self._result(270.0)

        first_count = _body_consistent_scan_count(
            baseline,
            None,
            candidate_count=1,
            current_capture_quality="normal",
            baseline_capture_quality=None,
            current_capture_mode="mirror",
            baseline_capture_mode=None,
        )
        second_count = _body_consistent_scan_count(
            second,
            baseline,
            candidate_count=first_count + 1,
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_capture_mode="mirror",
            baseline_capture_mode="mirror",
        )
        third_count = _body_consistent_scan_count(
            third,
            second,
            candidate_count=second_count + 1,
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_capture_mode="mirror",
            baseline_capture_mode="mirror",
        )
        reset_count = _body_consistent_scan_count(
            inconsistent,
            third,
            candidate_count=third_count + 1,
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_capture_mode="mirror",
            baseline_capture_mode="mirror",
        )

        self.assertEqual(first_count, 1)
        self.assertEqual(second_count, 2)
        self.assertEqual(third_count, 3)
        self.assertEqual(reset_count, 1)

        _, insufficient_status, _, required, _ = _compute_body_silhouette_trend(
            second,
            baseline,
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_consistent_scan_count=1,
            baseline_consistent_scan_count=1,
            current_capture_mode="mirror",
            baseline_capture_mode="mirror",
        )
        _, eligible_status, _, _, _ = _compute_body_silhouette_trend(
            second,
            baseline,
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_consistent_scan_count=second_count,
            baseline_consistent_scan_count=first_count,
            current_capture_mode="mirror",
            baseline_capture_mode="mirror",
        )

        self.assertEqual(required, 2)
        self.assertEqual(insufficient_status["normalized_area_index"], "insufficient_signal")
        self.assertEqual(eligible_status["normalized_area_index"], "stable")


class SourceResolutionTrendHonestyTests(unittest.TestCase):
    def test_matching_capture_quality_does_not_force_capture_quality_lock(self) -> None:
        statuses = _compute_trend_statuses(
            {"localized_redness": 20.0},
            {"localized_redness": 50.0},
            current_paths={"localized_redness": "primary_roi"},
            baseline_paths={"localized_redness": "primary_roi"},
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_source_width=1000,
            current_source_height=750,
            baseline_source_width=1000,
            baseline_source_height=750,
            current_formula_versions={"localized_redness": 2},
            baseline_formula_versions={"localized_redness": 2},
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        reasons = _compute_trend_lock_reasons(
            {"localized_redness": 20.0},
            {"localized_redness": 50.0},
            current_paths={"localized_redness": "primary_roi"},
            baseline_paths={"localized_redness": "primary_roi"},
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_source_width=1000,
            current_source_height=750,
            baseline_source_width=1000,
            baseline_source_height=750,
            current_formula_versions={"localized_redness": 2},
            baseline_formula_versions={"localized_redness": 2},
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(statuses["localized_redness"], "improved")
        self.assertIsNone(reasons["localized_redness"])

    def test_face_resolution_mismatch_forces_stable(self) -> None:
        delta, status = _trend_delta_and_status(
            "localized_redness",
            20.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1600,
            1200,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(delta, 0.0)
        self.assertEqual(status, "stable")

    def test_similar_face_resolutions_remain_comparable(self) -> None:
        delta, status = _trend_delta_and_status(
            "localized_redness",
            20.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1100,
            820,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertGreater(delta, 0.0)
        self.assertEqual(status, "improved")

    def test_body_resolution_mismatch_forces_stable(self) -> None:
        delta, status = _body_trend_delta_and_status(
            "normalized_area_index",
            140.0,
            100.0,
            205.0,
            200.0,
            0.9,
            0.9,
            "normal",
            "normal",
            honesty_band_pct=10.0,
            minimum_consistent_scans=1,
            current_capture_mode="mirror",
            baseline_capture_mode="mirror",
            current_source_width=1600,
            current_source_height=1200,
            baseline_source_width=1000,
            baseline_source_height=750,
        )
        self.assertEqual(delta, 0.0)
        self.assertEqual(status, "stable")


class TrendLockReasonTests(unittest.TestCase):
    """Covers the purely-additive trend_lock_reason companion functions.

    These explain WHY a "stable" trend_status was reached (a genuine small
    delta vs. a forced honesty-gate override) without changing any gating
    logic/thresholds themselves — _trend_delta_and_status /
    _body_trend_delta_and_status are untouched and still decide trend_status
    on their own; _trend_lock_reason / _body_trend_lock_reason just mirror
    the same checks to report *why*.
    """

    def test_genuine_small_delta_stable_has_no_lock_reason(self) -> None:
        # A real small delta that legitimately falls inside the honesty band
        # (comparable paths, matching normal capture quality, comparable
        # resolutions) is genuine stability, not a mismatch lock.
        # pore_contraction_index has no measured noise floor, so this
        # exercises the honesty-band gate alone, not the noise-floor gate --
        # see MeasuredNoiseFloorGateTests for that.
        delta, status = _trend_delta_and_status(
            "pore_contraction_index",
            51.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "stable")
        reason = _trend_lock_reason(
            "primary_roi",
            "primary_roi",
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertIsNone(reason)
        self.assertEqual(delta, 0.0)

    def test_capture_quality_mismatch_reason(self) -> None:
        delta, status = _trend_delta_and_status(
            "localized_redness",
            80.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "blurry",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "stable")
        self.assertEqual(delta, 0.0)
        reason = _trend_lock_reason(
            "primary_roi",
            "primary_roi",
            "blurry",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(reason, "capture_quality_mismatch")

    def test_path_mismatch_reason(self) -> None:
        reason = _trend_lock_reason(
            "primary_roi",
            "fallback",
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(reason, "path_mismatch")

    def test_missing_path_reason(self) -> None:
        reason = _trend_lock_reason(
            "unknown",
            "cheek_primary",
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(reason, "path_mismatch")

    def test_resolution_mismatch_reason(self) -> None:
        delta, status = _trend_delta_and_status(
            "localized_redness",
            80.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1600,
            1200,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "stable")
        self.assertEqual(delta, 0.0)
        reason = _trend_lock_reason(
            "primary_roi",
            "primary_roi",
            "normal",
            "normal",
            1600,
            1200,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(reason, "resolution_mismatch")

    def test_real_improved_delta_has_no_lock_reason(self) -> None:
        delta, status = _trend_delta_and_status(
            "texture_smoothness",
            80.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "improved")
        reason = _trend_lock_reason(
            "primary_roi",
            "primary_roi",
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertIsNone(reason)

    def test_compute_trend_lock_reasons_matches_per_metric_gates(self) -> None:
        current = {"localized_redness": 51.0, "texture_smoothness": 60.5}
        baseline = {"localized_redness": 50.0, "texture_smoothness": 60.0}
        paths = {"localized_redness": "primary_roi", "texture_smoothness": "primary_roi"}

        statuses = _compute_trend_statuses(
            current,
            baseline,
            current_paths=paths,
            baseline_paths={"localized_redness": "fallback", "texture_smoothness": "primary_roi"},
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_formula_versions={
                "localized_redness": 2,
                "texture_smoothness": 2,
            },
            baseline_formula_versions={
                "localized_redness": 2,
                "texture_smoothness": 2,
            },
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        reasons = _compute_trend_lock_reasons(
            current,
            baseline,
            current_paths=paths,
            baseline_paths={"localized_redness": "fallback", "texture_smoothness": "primary_roi"},
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_formula_versions={
                "localized_redness": 2,
                "texture_smoothness": 2,
            },
            baseline_formula_versions={
                "localized_redness": 2,
                "texture_smoothness": 2,
            },
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        # localized_redness is forced stable by a path mismatch.
        self.assertEqual(statuses["localized_redness"], "stable")
        self.assertEqual(reasons["localized_redness"], "path_mismatch")
        # texture_smoothness is genuinely stable (small delta, matching paths).
        self.assertEqual(statuses["texture_smoothness"], "stable")
        self.assertIsNone(reasons["texture_smoothness"])

    def test_body_genuine_stable_has_no_lock_reason(self) -> None:
        reason = _body_trend_lock_reason(
            100.0,
            200.0,
            200.0,
            0.9,
            0.9,
            "normal",
            "normal",
            current_capture_mode="mirror",
            baseline_capture_mode="mirror",
            current_source_width=1000,
            current_source_height=750,
            baseline_source_width=1000,
            baseline_source_height=750,
        )
        self.assertIsNone(reason)

    def test_body_capture_quality_mismatch_reason(self) -> None:
        _, status = _body_trend_delta_and_status(
            "normalized_area_index",
            140.0,
            100.0,
            200.0,
            200.0,
            0.9,
            0.9,
            "blurry",
            "normal",
            honesty_band_pct=10.0,
            minimum_consistent_scans=1,
        )
        self.assertEqual(status, "stable")
        reason = _body_trend_lock_reason(
            100.0,
            200.0,
            200.0,
            0.9,
            0.9,
            "blurry",
            "normal",
        )
        self.assertEqual(reason, "capture_quality_mismatch")

    def test_body_resolution_mismatch_reason(self) -> None:
        reason = _body_trend_lock_reason(
            100.0,
            200.0,
            200.0,
            0.9,
            0.9,
            "normal",
            "normal",
            current_source_width=1600,
            current_source_height=1200,
            baseline_source_width=1000,
            baseline_source_height=750,
        )
        self.assertEqual(reason, "resolution_mismatch")

    def test_body_scale_mismatch_reason(self) -> None:
        _, status = _body_trend_delta_and_status(
            "normalized_area_index",
            140.0,
            100.0,
            260.0,
            200.0,
            0.9,
            0.9,
            "normal",
            "normal",
            honesty_band_pct=10.0,
            minimum_consistent_scans=1,
        )
        self.assertEqual(status, "stable")
        reason = _body_trend_lock_reason(
            100.0,
            260.0,
            200.0,
            0.9,
            0.9,
            "normal",
            "normal",
        )
        self.assertEqual(reason, "scale_mismatch")

    def test_body_capture_mode_mismatch_reason(self) -> None:
        _, status = _body_trend_delta_and_status(
            "normalized_area_index",
            140.0,
            100.0,
            205.0,
            200.0,
            0.9,
            0.9,
            "normal",
            "normal",
            honesty_band_pct=10.0,
            minimum_consistent_scans=1,
            current_capture_mode="mirror",
            baseline_capture_mode="assisted",
        )
        self.assertEqual(status, "stable")
        reason = _body_trend_lock_reason(
            100.0,
            205.0,
            200.0,
            0.9,
            0.9,
            "normal",
            "normal",
            current_capture_mode="mirror",
            baseline_capture_mode="assisted",
        )
        self.assertEqual(reason, "capture_mode_mismatch")

    def test_compute_body_silhouette_trend_returns_lock_reasons(self) -> None:
        baseline_result = {
            "normalized_area_index": 100.0,
            "scale_reference_pixels": 200.0,
            "confidence": 0.9,
        }
        current_result = {
            "normalized_area_index": 140.0,
            "scale_reference_pixels": 200.0,
            "confidence": 0.9,
        }
        _, statuses, _, _, reasons = _compute_body_silhouette_trend(
            current_result,
            baseline_result,
            current_capture_quality="blurry",
            baseline_capture_quality="normal",
            current_consistent_scan_count=2,
            baseline_consistent_scan_count=2,
        )
        self.assertEqual(statuses["normalized_area_index"], "stable")
        self.assertEqual(
            reasons["normalized_area_index"], "capture_quality_mismatch"
        )


class ComputeTrendDeltasTests(unittest.TestCase):
    @staticmethod
    def _paths(*keys: str) -> dict[str, str]:
        return {key: "primary_roi" for key in keys}

    @staticmethod
    def _versions(*keys: str) -> dict[str, int]:
        return {key: _metric_formula_version(key) for key in keys}

    def test_texture_smoothness_increase_is_positive_improvement(self) -> None:
        current = {"texture_smoothness": 72.0}
        baseline = {"texture_smoothness": 60.0}

        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths=self._paths("texture_smoothness"),
            baseline_paths=self._paths("texture_smoothness"),
            current_formula_versions=self._versions("texture_smoothness"),
            baseline_formula_versions=self._versions("texture_smoothness"),
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(deltas["texture_smoothness"], 20.0)

    def test_defect_metric_decrease_stays_positive_improvement(self) -> None:
        # localized_redness and glabellar_wrinkle_depth deltas are sized to
        # clear their measured noise floors (see METRIC_NOISE_FLOOR_2SD /
        # TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE) so this test still
        # exercises pure sign-handling for "higher is worse" metrics, not
        # the noise-floor gate -- that gate has its own dedicated tests.
        # breakout_activity is deliberately excluded from this set: it is
        # now a measured, TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE metric (see
        # MeasuredNoiseFloorGateTests), so a plain sign-handling example
        # would need values sized around its 3x-floor threshold rather than
        # this test's small illustrative deltas.
        current = {
            "localized_redness": 5.0,
            "diffuse_flushing_erythema": 11.0,
            "sebum_excess_oil_gloss": 9.0,
            "glabellar_wrinkle_depth": 10.0,
            "pore_contraction_index": 10.0,
        }
        baseline = {
            "localized_redness": 30.0,
            "diffuse_flushing_erythema": 22.0,
            "sebum_excess_oil_gloss": 12.0,
            "glabellar_wrinkle_depth": 20.0,
            "pore_contraction_index": 12.5,
        }

        keys = tuple(current.keys())
        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths=self._paths(*keys),
            baseline_paths=self._paths(*keys),
            current_formula_versions=self._versions(*keys),
            baseline_formula_versions=self._versions(*keys),
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(deltas["localized_redness"], 83.3)
        self.assertEqual(deltas["diffuse_flushing_erythema"], 50.0)
        self.assertEqual(deltas["sebum_excess_oil_gloss"], 25.0)
        self.assertEqual(deltas["glabellar_wrinkle_depth"], 50.0)
        self.assertEqual(deltas["pore_contraction_index"], 20.0)

    def test_defect_metric_increase_is_negative_regression(self) -> None:
        current = {"diffuse_flushing_erythema": 30.0}
        baseline = {"diffuse_flushing_erythema": 20.0}

        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths=self._paths("diffuse_flushing_erythema"),
            baseline_paths=self._paths("diffuse_flushing_erythema"),
            current_formula_versions=self._versions("diffuse_flushing_erythema"),
            baseline_formula_versions=self._versions("diffuse_flushing_erythema"),
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(deltas["diffuse_flushing_erythema"], -50.0)

    def test_radiance_evenness_increase_is_positive_improvement(self) -> None:
        current = {"skin_tone_radiance_evenness": 84.0}
        baseline = {"skin_tone_radiance_evenness": 70.0}

        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths=self._paths("skin_tone_radiance_evenness"),
            baseline_paths=self._paths("skin_tone_radiance_evenness"),
            current_formula_versions=self._versions("skin_tone_radiance_evenness"),
            baseline_formula_versions=self._versions("skin_tone_radiance_evenness"),
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(deltas["skin_tone_radiance_evenness"], 20.0)

    def test_structural_firmness_increase_is_positive_improvement(self) -> None:
        current = {"structural_firmness_elasticity": 79.2}
        baseline = {"structural_firmness_elasticity": 72.0}

        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths=self._paths("structural_firmness_elasticity"),
            baseline_paths=self._paths("structural_firmness_elasticity"),
            current_formula_versions=self._versions("structural_firmness_elasticity"),
            baseline_formula_versions=self._versions("structural_firmness_elasticity"),
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(deltas["structural_firmness_elasticity"], 10.0)

    def test_zero_baseline_returns_zero_delta(self) -> None:
        current = {
            "texture_smoothness": 75.0,
            "localized_redness": 10.0,
            "sebum_excess_oil_gloss": 7.0,
            "diffuse_flushing_erythema": 13.0,
            "skin_tone_radiance_evenness": 82.0,
            "glabellar_wrinkle_depth": 19.0,
            "pore_contraction_index": 9.5,
            "structural_firmness_elasticity": 77.0,
        }
        baseline = {
            "texture_smoothness": 0.0,
            "localized_redness": 0.0,
            "sebum_excess_oil_gloss": 0.0,
            "diffuse_flushing_erythema": 0.0,
            "skin_tone_radiance_evenness": 0.0,
            "glabellar_wrinkle_depth": 0.0,
            "pore_contraction_index": 0.0,
            "structural_firmness_elasticity": 0.0,
        }

        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths=self._paths(*tuple(current.keys())),
            baseline_paths=self._paths(*tuple(current.keys())),
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(deltas["texture_smoothness"], 0.0)
        self.assertEqual(deltas["localized_redness"], 0.0)
        self.assertEqual(deltas["sebum_excess_oil_gloss"], 0.0)
        self.assertEqual(deltas["diffuse_flushing_erythema"], 0.0)
        self.assertEqual(deltas["skin_tone_radiance_evenness"], 0.0)
        self.assertEqual(deltas["glabellar_wrinkle_depth"], 0.0)
        self.assertEqual(deltas["pore_contraction_index"], 0.0)
        self.assertEqual(deltas["structural_firmness_elasticity"], 0.0)

    def test_normalize_capture_quality_accepts_blurry_and_guidance_tags(self) -> None:
        self.assertEqual(_normalize_capture_quality("blurry"), "blurry")
        self.assertEqual(_normalize_capture_quality("poor_angle"), "poor_angle")
        self.assertEqual(_normalize_capture_quality("uneven_lighting"), "uneven_lighting")
        self.assertEqual(_normalize_capture_quality("normal"), "normal")

    def test_unknown_paths_force_stable_zero(self) -> None:
        current = {"localized_redness": 12.0}
        baseline = {"localized_redness": 24.0}

        deltas = _compute_trend_deltas(current, baseline,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(deltas["localized_redness"], 0.0)

    def test_path_mismatch_forces_stable_zero(self) -> None:
        current = {"localized_redness": 12.0}
        baseline = {"localized_redness": 24.0}

        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths={"localized_redness": "primary_roi"},
            baseline_paths={"localized_redness": "fallback"},
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(deltas["localized_redness"], 0.0)

    def test_honesty_band_under_8_percent_forces_stable(self) -> None:
        current = {"skin_tone_radiance_evenness": 75.0}
        baseline = {"skin_tone_radiance_evenness": 70.0}

        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths=self._paths("skin_tone_radiance_evenness"),
            baseline_paths=self._paths("skin_tone_radiance_evenness"),
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(deltas["skin_tone_radiance_evenness"], 0.0)

    def test_personal_lab_baseline_is_used_instead_of_neutral_128(self) -> None:
        baseline = _coalesce_personal_lab_baseline({
            "a_mean": 110.0,
            "b_mean": 118.0,
            "a_p95": 126.0,
            "b_p95": 124.0,
        })
        current = {
            "a_mean": 128.0,
            "b_mean": 121.0,
            "a_p95": 138.0,
            "b_p95": 126.0,
        }

        redness = _compute_redness_from_personal_baseline(current, baseline)
        self.assertAlmostEqual(redness, 28.05, places=2)
        self.assertEqual(_compute_redness_from_personal_baseline({"a_p95": 126.0}, {}), 0.0)

    def test_request_roi_cache_reuses_masks_within_single_analysis(self) -> None:
        cache = main._RequestRoiCache()
        points = np.zeros((468, 2), dtype=np.float32)
        skin_mask = np.ones((120, 120), dtype=np.uint8) * 255

        first = cache.get_face_skin_mask((120, 120), points, skin_mask)
        second = cache.get_face_skin_mask((120, 120), points, skin_mask)
        self.assertIs(first, second)

        forehead_mask = np.zeros((120, 120), dtype=np.uint8)
        face_skin_mask = np.ones((120, 120), dtype=np.uint8) * 255
        first_tzone = cache.get_tzone_mask((120, 120), points, forehead_mask, skin_mask, face_skin_mask)
        second_tzone = cache.get_tzone_mask((120, 120), points, forehead_mask, skin_mask, face_skin_mask)
        self.assertIs(first_tzone, second_tzone)


class MeasuredNoiseFloorGateTests(unittest.TestCase):
    """Covers METRIC_NOISE_FLOOR_2SD / TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE
    / TREND_NOISE_FLOOR_EXCLUDED_MULTIPLIER, the per-metric absolute-change
    gate that replaces guessing a single uniform percentage band with each
    metric's own measured scan-to-scan noise. Provenance gates (capture
    quality/path/resolution) are covered elsewhere and are untouched by this
    feature -- these tests all use matching, "normal" provenance so the
    noise-floor logic is what's actually being exercised.
    """

    def test_setup_constants_match_the_measured_repeatability_session(self) -> None:
        # Pins the actual measured values (max of two sessions) so a future
        # edit to the table can't silently drift without a test noticing.
        self.assertEqual(
            METRIC_NOISE_FLOOR_2SD,
            {
                "localized_redness": 6.8,
                "rosacea_severity": 3.9,
                "glabellar_wrinkle_depth": 6.4,
                "texture_smoothness": 5.4,
                "wrinkle_load": 3.7,
                "under_eye_dark_circle_density": 14.1,
                "under_eye_texture_density": 6.0,
                "structural_firmness_elasticity": 3.0,
                "pigment_load": 2.0,
                "skin_tone_radiance_evenness": 1.1,
                "pore_visibility": 1.0,
                "breakout_activity": 13.1,
            },
        )
        self.assertEqual(
            TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE,
            {"localized_redness", "rosacea_severity", "breakout_activity"},
        )
        self.assertEqual(TREND_NOISE_FLOOR_EXCLUDED_MULTIPLIER, 3.0)

    def test_below_floor_delta_forces_stable_for_a_non_excluded_metric(self) -> None:
        # texture_smoothness's floor is 5.4. A 4-point move clears the 8%
        # relative honesty band easily (40%) but must still be held to
        # stable by the absolute floor -- this is exactly the reported
        # texture_smoothness "Improved by 100%" bug's shape: a small
        # absolute move that reads huge in percentage terms on a small
        # baseline.
        delta, status = _trend_delta_and_status(
            "texture_smoothness", 14.0, 10.0, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "stable")
        self.assertEqual(delta, 0.0)

    def test_at_or_above_floor_delta_still_requires_the_honesty_band(self) -> None:
        # pigment_load's floor is 2.0. A 3-point move clears the floor but
        # is only a 3.3% relative move on a baseline of 90 -- the existing
        # 8% relative band must still be able to hold this to stable. The
        # noise floor is an additional requirement, not a replacement.
        delta, status = _trend_delta_and_status(
            "pigment_load", 93.0, 90.0, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "stable")
        self.assertEqual(delta, 0.0)

    def test_a_real_change_clearing_both_gates_is_reported_normally(self) -> None:
        # wrinkle_load's floor is 3.7. A move of 10 clears both the floor
        # and the relative band, so this must still report a direction.
        delta, status = _trend_delta_and_status(
            "wrinkle_load", 10.0, 20.0, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "improved")
        self.assertEqual(delta, 50.0)

    def test_a_metric_with_no_measured_floor_is_unaffected(self) -> None:
        # diffuse_flushing_erythema has never been part of a repeatability
        # session (unlike pore_visibility and breakout_activity, which now
        # have measured floors from the second session -- see
        # METRIC_NOISE_FLOOR_2SD), so a tiny absolute move (0.5) that
        # nonetheless clears the relative band must still report a
        # direction exactly as before this feature existed.
        self.assertNotIn("diffuse_flushing_erythema", METRIC_NOISE_FLOOR_2SD)
        delta, status = _trend_delta_and_status(
            "diffuse_flushing_erythema", 1.5, 1.0, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "worsened")
        self.assertEqual(delta, -50.0)

    def test_excluded_metric_below_3x_floor_is_insufficient_signal_not_stable(
        self,
    ) -> None:
        # localized_redness's floor is 6.8; 3x is 20.4. A 5-point move is
        # comfortably below that -- for this metric, that must report
        # insufficient_signal, never "stable": "stable" is itself an
        # overconfident claim once the floor swallows most of the range
        # real users show.
        delta, status = _trend_delta_and_status(
            "localized_redness", 15.0, 10.0, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "insufficient_signal")
        self.assertEqual(delta, 0.0)

    def test_excluded_metric_at_or_above_3x_floor_reports_a_real_direction(
        self,
    ) -> None:
        # A 25-point move (10 -> 35) clears 3x localized_redness's floor
        # (20.4) by a wide margin -- a real, obvious change must still be
        # reported. The exclusion only withholds the ambiguous "we can't
        # tell" claim, never suppresses an unambiguous one.
        delta, status = _trend_delta_and_status(
            "localized_redness", 35.0, 10.0, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "worsened")
        self.assertEqual(delta, -250.0)

    def test_second_excluded_metric_rosacea_severity_below_threshold(self) -> None:
        # rosacea_severity's floor is 3.9; 3x is 11.7. A 4-point move stays
        # below that.
        delta, status = _trend_delta_and_status(
            "rosacea_severity", 14.0, 10.0, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "insufficient_signal")
        self.assertEqual(delta, 0.0)

    def test_excluded_metric_exactly_at_the_3x_threshold_is_not_excluded(
        self,
    ) -> None:
        # Boundary check: the gate is "< required", so a delta exactly
        # equal to 3x the floor must NOT be treated as insufficient signal.
        required = METRIC_NOISE_FLOOR_2SD["rosacea_severity"] * (
            TREND_NOISE_FLOOR_EXCLUDED_MULTIPLIER
        )
        baseline = 10.0
        current = baseline + required
        delta, status = _trend_delta_and_status(
            "rosacea_severity", current, baseline, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "worsened")
        self.assertNotEqual(delta, 0.0)

    def test_provenance_gates_still_run_before_the_noise_floor_gate(self) -> None:
        # A capture-quality mismatch must still force stable even for a
        # huge localized_redness delta that would otherwise clear 3x its
        # floor -- provenance validity is checked first, unconditionally.
        delta, status = _trend_delta_and_status(
            "localized_redness", 90.0, 10.0, "primary_roi", "primary_roi", 8.0,
            "blurry", "normal", 1000, 750, 1000, 750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "stable")
        self.assertEqual(delta, 0.0)


class NormalizeMetricFormulaVersionsTests(unittest.TestCase):
    def test_none_input_defaults_every_metric_to_1(self) -> None:
        result = _normalize_metric_formula_versions(None, ["texture_smoothness", "wrinkle_load"])
        self.assertEqual(result, {"texture_smoothness": 1, "wrinkle_load": 1})

    def test_empty_string_defaults_every_metric_to_1(self) -> None:
        result = _normalize_metric_formula_versions("", ["texture_smoothness"])
        self.assertEqual(result, {"texture_smoothness": 1})

    def test_a_provided_version_overrides_the_default(self) -> None:
        result = _normalize_metric_formula_versions(
            {"texture_smoothness": 2},
            ["texture_smoothness", "wrinkle_load"],
        )
        self.assertEqual(result, {"texture_smoothness": 2, "wrinkle_load": 1})

    def test_json_string_payload_is_parsed(self) -> None:
        result = _normalize_metric_formula_versions(
            '{"texture_smoothness": 2}',
            ["texture_smoothness"],
        )
        self.assertEqual(result, {"texture_smoothness": 2})

    def test_malformed_json_string_falls_back_to_defaults(self) -> None:
        result = _normalize_metric_formula_versions(
            "{not valid json",
            ["texture_smoothness"],
        )
        self.assertEqual(result, {"texture_smoothness": 1})

    def test_a_non_numeric_value_falls_back_to_the_default_for_that_key(self) -> None:
        result = _normalize_metric_formula_versions(
            {"texture_smoothness": "not-a-number"},
            ["texture_smoothness"],
        )
        self.assertEqual(result, {"texture_smoothness": 1})

    def test_a_key_outside_the_known_metric_list_is_ignored(self) -> None:
        result = _normalize_metric_formula_versions(
            {"not_a_real_metric": 5},
            ["texture_smoothness"],
        )
        self.assertEqual(result, {"texture_smoothness": 1})

    def test_a_canonical_key_is_applied_directly(self) -> None:
        result = _normalize_metric_formula_versions(
            {"glabellar_wrinkle_depth": 4},
            ["texture_smoothness", "glabellar_wrinkle_depth"],
        )
        self.assertEqual(
            result,
            {"texture_smoothness": 1, "glabellar_wrinkle_depth": 4},
        )

    def test_baseline_normalizer_keeps_missing_versions_missing(self) -> None:
        self.assertEqual(
            _normalize_baseline_metric_formula_versions(
                {"glabellar_wrinkle_depth": 2},
                ["texture_smoothness", "glabellar_wrinkle_depth"],
            ),
            {"glabellar_wrinkle_depth": 2},
        )


class BaselineFormulaVersionComparisonTests(unittest.TestCase):
    @staticmethod
    def _reason(baseline_versions: dict[str, int] | None) -> str | None:
        return _compute_trend_lock_reasons(
            {"glabellar_wrinkle_depth": 10.0},
            {"glabellar_wrinkle_depth": 20.0},
            current_paths={"glabellar_wrinkle_depth": "primary_roi"},
            baseline_paths={"glabellar_wrinkle_depth": "primary_roi"},
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_formula_versions={"glabellar_wrinkle_depth": 2},
            baseline_formula_versions=baseline_versions,
            current_pose_template="Front",
            baseline_pose_template="Front",
            current_guide_type="facial",
            baseline_guide_type="facial",
        )["glabellar_wrinkle_depth"]

    def test_baseline_v2_current_v2_has_no_formula_lock(self) -> None:
        self.assertIsNone(self._reason({"glabellar_wrinkle_depth": 2}))

    def test_baseline_v1_current_v2_has_formula_lock(self) -> None:
        self.assertEqual(
            self._reason({"glabellar_wrinkle_depth": 1}),
            "formula_version_mismatch",
        )

    def test_missing_baseline_version_has_formula_lock(self) -> None:
        self.assertEqual(self._reason(None), "formula_version_mismatch")

    def test_stored_glabellar_v2_compares_with_current_v2(self) -> None:
        stored_baseline_versions = {"glabellar_wrinkle_depth": 2}
        self.assertIsNone(self._reason(stored_baseline_versions))

    def test_legacy_redness_v2_baseline_locks_against_current_v3(self) -> None:
        baseline_versions = _baseline_formula_versions_for_redness_reference(
            {"localized_redness": 3},
            {"localized_redness": 20.0},
        )
        self.assertEqual(baseline_versions["localized_redness"], 2)
        reason = _compute_trend_lock_reasons(
            {"localized_redness": 30.0},
            {"localized_redness": 20.0},
            current_paths={"localized_redness": "cheek_primary"},
            baseline_paths={"localized_redness": "cheek_primary"},
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_formula_versions={"localized_redness": 3},
            baseline_formula_versions=baseline_versions,
            current_pose_template="Front",
            baseline_pose_template="Front",
            current_guide_type="facial",
            baseline_guide_type="facial",
        )["localized_redness"]

        self.assertEqual(reason, "formula_version_mismatch")

    def test_redness_baseline_with_p95_keeps_v3(self) -> None:
        baseline_versions = _baseline_formula_versions_for_redness_reference(
            {"localized_redness": 3},
            {"localized_redness": 20.0, "a_p95": 128.0},
        )

        self.assertEqual(baseline_versions["localized_redness"], 3)


class MetricFormulaVersionRegistryTests(unittest.TestCase):
    def test_registry_only_contains_deliberately_bumped_metrics(self) -> None:
        # localized_redness now anchors follow-ups to a stored U-zone p95;
        # old v2 self-spread baselines are intentionally incomparable.
        # chin_pore_visibility remains independently at its initial version.
        self.assertEqual(
            METRIC_FORMULA_VERSION,
            {
                "localized_redness": 3,
                "texture_smoothness": 2,
                "pigment_load": 2,
                "wrinkle_load": 2,
                "sebum_excess_oil_gloss": 2,
                "diffuse_flushing_erythema": 2,
                "rosacea_severity": 2,
                "pore_visibility": 3,
                "chin_pore_visibility": 1,
                "pore_contraction_index": 2,
                "glabellar_wrinkle_depth": 2,
            },
        )

    def test_every_metric_defaults_to_version_1(self) -> None:
        self.assertEqual(_metric_formula_version("texture_smoothness"), 2)
        self.assertEqual(_metric_formula_version("wrinkle_load"), 2)
        self.assertEqual(_metric_formula_version("anything_unknown"), 1)

    def test_glabellar_wrinkle_depth_is_pinned_to_version_2(self) -> None:
        self.assertEqual(_metric_formula_version("glabellar_wrinkle_depth"), 2)

    def test_face_skin_mask_changes_refuse_version_one_baselines(self) -> None:
        for metric_key in {
            "localized_redness",
            "texture_smoothness",
            "pigment_load",
            "wrinkle_load",
            "sebum_excess_oil_gloss",
            "diffuse_flushing_erythema",
            "rosacea_severity",
            "pore_visibility",
        }:
            with self.subTest(metric_key=metric_key):
                self.assertEqual(
                    _trend_lock_reason(
                        "primary_roi",
                        "primary_roi",
                        "normal",
                        "normal",
                        1000,
                        750,
                        1000,
                        750,
                        current_formula_version=_metric_formula_version(metric_key),
                        baseline_formula_version=1,
                        current_pose_template="Front",
                        baseline_pose_template="Front",
                        current_guide_type="facial",
                        baseline_guide_type="facial",
                    ),
                    "formula_version_mismatch",
                )

    def test_pore_fallback_removal_refuses_version_two_baseline(self) -> None:
        self.assertEqual(_metric_formula_version("pore_visibility"), 3)
        self.assertEqual(
            _trend_lock_reason(
                "primary_roi",
                "primary_roi",
                "normal",
                "normal",
                1000,
                750,
                1000,
                750,
                current_formula_version=3,
                baseline_formula_version=2,
                current_pose_template="Front",
                baseline_pose_template="Front",
                current_guide_type="facial",
                baseline_guide_type="facial",
            ),
            "formula_version_mismatch",
        )

    def test_pore_contraction_omission_refuses_version_one_baseline(self) -> None:
        self.assertEqual(_metric_formula_version("pore_contraction_index"), 2)
        self.assertEqual(
            _trend_lock_reason(
                "primary_roi",
                "primary_roi",
                "normal",
                "normal",
                1000,
                750,
                1000,
                750,
                current_formula_version=2,
                baseline_formula_version=1,
                current_pose_template="Front",
                baseline_pose_template="Front",
                current_guide_type="facial",
                baseline_guide_type="facial",
            ),
            "formula_version_mismatch",
        )


class FormulaVersionMismatchGateTests(unittest.TestCase):
    """Covers the formula_version_mismatch provenance gate: a scoring-
    formula change for a metric makes its baseline and current values
    incomparable, the same way a capture-quality/path/resolution mismatch
    already does -- so it belongs in the SAME provenance chain, checked the
    same way, not as a separate mechanism.
    """

    def test_matching_versions_do_not_affect_a_real_delta(self) -> None:
        delta, status = _trend_delta_and_status(
            "wrinkle_load", 10.0, 20.0, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_formula_version=1,
            baseline_formula_version=1,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "improved")
        self.assertEqual(delta, 50.0)

    def test_mismatched_versions_force_stable_even_for_a_large_real_delta(
        self,
    ) -> None:
        delta, status = _trend_delta_and_status(
            "wrinkle_load", 10.0, 20.0, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_formula_version=2,
            baseline_formula_version=1,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "stable")
        self.assertEqual(delta, 0.0)

    def test_missing_versions_default_to_1_and_are_therefore_comparable(
        self,
    ) -> None:
        # Neither side specifies a version (an older scan, or a metric with
        # no registry entry) -- both default to 1 and compare normally.
        delta, status = _trend_delta_and_status(
            "wrinkle_load", 10.0, 20.0, "primary_roi", "primary_roi", 8.0,
            "normal", "normal", 1000, 750, 1000, 750,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(status, "improved")
        self.assertEqual(delta, 50.0)

    def test_lock_reason_reports_formula_version_mismatch(self) -> None:
        reason = _trend_lock_reason(
            "primary_roi", "primary_roi", "normal", "normal",
            1000, 750, 1000, 750,
            current_formula_version=2,
            baseline_formula_version=1,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(reason, "formula_version_mismatch")

    def test_lock_reason_is_none_when_versions_match(self) -> None:
        reason = _trend_lock_reason(
            "primary_roi", "primary_roi", "normal", "normal",
            1000, 750, 1000, 750,
            current_formula_version=1,
            baseline_formula_version=1,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertIsNone(reason)

    def test_capture_quality_mismatch_is_reported_before_formula_version_mismatch(
        self,
    ) -> None:
        # Provenance checks run in a fixed order; an earlier, more
        # fundamental mismatch (capture quality) must still win over a
        # later one (formula version) when both are present.
        reason = _trend_lock_reason(
            "primary_roi", "primary_roi", "blurry", "normal",
            1000, 750, 1000, 750,
            current_formula_version=2,
            baseline_formula_version=1,
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        self.assertEqual(reason, "capture_quality_mismatch")

    def test_compute_trend_wrappers_thread_formula_versions_through(self) -> None:
        current = {"wrinkle_load": 10.0}
        baseline = {"wrinkle_load": 20.0}
        paths = {"wrinkle_load": "primary_roi"}

        matched = _compute_trend_statuses(
            current, baseline,
            current_paths=paths, baseline_paths=paths,
            current_capture_quality="normal", baseline_capture_quality="normal",
            current_formula_versions={"wrinkle_load": 1},
            baseline_formula_versions={"wrinkle_load": 1},
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        mismatched = _compute_trend_statuses(
            current, baseline,
            current_paths=paths, baseline_paths=paths,
            current_capture_quality="normal", baseline_capture_quality="normal",
            current_formula_versions={"wrinkle_load": 2},
            baseline_formula_versions={"wrinkle_load": 1},
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        mismatched_deltas = _compute_trend_deltas(
            current, baseline,
            current_paths=paths, baseline_paths=paths,
            current_capture_quality="normal", baseline_capture_quality="normal",
            current_formula_versions={"wrinkle_load": 2},
            baseline_formula_versions={"wrinkle_load": 1},
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )
        mismatched_reasons = _compute_trend_lock_reasons(
            current, baseline,
            current_paths=paths, baseline_paths=paths,
            current_capture_quality="normal", baseline_capture_quality="normal",
            current_formula_versions={"wrinkle_load": 2},
            baseline_formula_versions={"wrinkle_load": 1},
            current_pose_template='Front',
            baseline_pose_template='Front',
            current_guide_type='facial',
            baseline_guide_type='facial',
        )

        self.assertEqual(matched["wrinkle_load"], "improved")
        self.assertEqual(mismatched["wrinkle_load"], "stable")
        self.assertEqual(mismatched_deltas["wrinkle_load"], 0.0)
        self.assertEqual(mismatched_reasons["wrinkle_load"], "formula_version_mismatch")


class AngleAndGuideTypeTrendHonestyTests(unittest.TestCase):
    """Only compare scans with the same recorded pose template (view angle)
    AND the same camera guide type -- "Left 45°" is never treated as "Left
    Profile", and a missing value on either side is never treated as a
    match. Same honesty-gate style as the existing capture-quality/path/
    resolution/formula-version gates in _trend_delta_and_status.
    """

    def test_same_pose_template_and_guide_type_reports_a_real_delta(self) -> None:
        delta, status = _trend_delta_and_status(
            "localized_redness",
            20.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template="Front",
            baseline_pose_template="Front",
            current_guide_type="facial",
            baseline_guide_type="facial",
        )
        self.assertEqual(status, "improved")
        self.assertEqual(delta, 60.0)

    def test_different_pose_template_forces_stable(self) -> None:
        # "Left 45°" is a different angle than "Left Profile" -- never
        # treated as the same view even though both are non-null.
        delta, status = _trend_delta_and_status(
            "localized_redness",
            20.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template="Left 45°",
            baseline_pose_template="Left Profile",
            current_guide_type="facial",
            baseline_guide_type="facial",
        )
        self.assertEqual(status, "stable")
        self.assertEqual(delta, 0.0)

    def test_different_guide_type_forces_stable(self) -> None:
        delta, status = _trend_delta_and_status(
            "localized_redness",
            20.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template="Front",
            baseline_pose_template="Front",
            current_guide_type="facial",
            baseline_guide_type="body",
        )
        self.assertEqual(status, "stable")
        self.assertEqual(delta, 0.0)

    def test_missing_pose_template_on_either_side_forces_stable(self) -> None:
        missing_current = _trend_delta_and_status(
            "localized_redness",
            20.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template=None,
            baseline_pose_template="Front",
            current_guide_type="facial",
            baseline_guide_type="facial",
        )
        self.assertEqual(missing_current, (0.0, "stable"))

        missing_both = _trend_delta_and_status(
            "localized_redness",
            20.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template=None,
            baseline_pose_template=None,
            current_guide_type=None,
            baseline_guide_type=None,
        )
        self.assertEqual(
            missing_both,
            (0.0, "stable"),
            "both sides missing is still not a match -- unknown never matches unknown",
        )

    def test_missing_guide_type_on_either_side_forces_stable(self) -> None:
        delta, status = _trend_delta_and_status(
            "localized_redness",
            20.0,
            50.0,
            "primary_roi",
            "primary_roi",
            8.0,
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template="Front",
            baseline_pose_template="Front",
            current_guide_type="facial",
            baseline_guide_type=None,
        )
        self.assertEqual(status, "stable")
        self.assertEqual(delta, 0.0)

    def test_lock_reason_reports_angle_or_guide_mismatch(self) -> None:
        reason = _trend_lock_reason(
            "primary_roi",
            "primary_roi",
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template="Left 45°",
            baseline_pose_template="Left Profile",
            current_guide_type="facial",
            baseline_guide_type="facial",
        )
        self.assertEqual(reason, "angle_or_guide_mismatch")

    def test_lock_reason_is_none_when_angle_and_guide_match(self) -> None:
        reason = _trend_lock_reason(
            "primary_roi",
            "primary_roi",
            "normal",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template="Front",
            baseline_pose_template="Front",
            current_guide_type="facial",
            baseline_guide_type="facial",
        )
        self.assertIsNone(reason)

    def test_capture_quality_mismatch_is_reported_before_angle_mismatch(self) -> None:
        # Provenance checks run in a fixed order; capture quality is checked
        # before the angle/guide gate, so it still wins when both are wrong.
        reason = _trend_lock_reason(
            "primary_roi",
            "primary_roi",
            "blurry",
            "normal",
            1000,
            750,
            1000,
            750,
            current_pose_template="Left 45°",
            baseline_pose_template="Left Profile",
            current_guide_type="facial",
            baseline_guide_type="facial",
        )
        self.assertEqual(reason, "capture_quality_mismatch")

    def test_compute_trend_wrappers_gate_on_angle_and_guide_type(self) -> None:
        current = {"wrinkle_load": 10.0}
        baseline = {"wrinkle_load": 20.0}
        paths = {"wrinkle_load": "primary_roi"}
        common_kwargs = dict(
            current_paths=paths,
            baseline_paths=paths,
            current_capture_quality="normal",
            baseline_capture_quality="normal",
            current_formula_versions={"wrinkle_load": 2},
            baseline_formula_versions={"wrinkle_load": 2},
        )

        matched_status = _compute_trend_statuses(
            current,
            baseline,
            current_pose_template="Front",
            baseline_pose_template="Front",
            current_guide_type="facial",
            baseline_guide_type="facial",
            **common_kwargs,
        )
        mismatched_status = _compute_trend_statuses(
            current,
            baseline,
            current_pose_template="Front",
            baseline_pose_template="Left 45°",
            current_guide_type="facial",
            baseline_guide_type="facial",
            **common_kwargs,
        )
        mismatched_deltas = _compute_trend_deltas(
            current,
            baseline,
            current_pose_template="Front",
            baseline_pose_template="Left 45°",
            current_guide_type="facial",
            baseline_guide_type="facial",
            **common_kwargs,
        )
        mismatched_reasons = _compute_trend_lock_reasons(
            current,
            baseline,
            current_pose_template="Front",
            baseline_pose_template="Left 45°",
            current_guide_type="facial",
            baseline_guide_type="facial",
            **common_kwargs,
        )

        self.assertEqual(matched_status["wrinkle_load"], "improved")
        self.assertEqual(mismatched_status["wrinkle_load"], "stable")
        self.assertEqual(mismatched_deltas["wrinkle_load"], 0.0)
        self.assertEqual(mismatched_reasons["wrinkle_load"], "angle_or_guide_mismatch")


if __name__ == "__main__":
    unittest.main()
