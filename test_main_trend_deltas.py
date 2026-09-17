import unittest

import numpy as np

import main
from main import (
    _body_consistent_scan_count,
    _body_trend_delta_and_status,
    _body_trend_lock_reason,
    _compute_body_silhouette_trend,
    _coalesce_personal_lab_baseline,
    _compute_redness_from_personal_baseline,
    _compute_trend_deltas,
    _compute_trend_lock_reasons,
    _compute_trend_statuses,
    _normalize_capture_quality,
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
        delta, status = _trend_delta_and_status(
            "localized_redness",
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
        )
        reasons = _compute_trend_lock_reasons(
            current,
            baseline,
            current_paths=paths,
            baseline_paths={"localized_redness": "fallback", "texture_smoothness": "primary_roi"},
            current_capture_quality="normal",
            baseline_capture_quality="normal",
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

    def test_texture_smoothness_increase_is_positive_improvement(self) -> None:
        current = {"texture_smoothness": 72.0}
        baseline = {"texture_smoothness": 60.0}

        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths=self._paths("texture_smoothness"),
            baseline_paths=self._paths("texture_smoothness"),
        )

        self.assertEqual(deltas["texture_smoothness"], 20.0)

    def test_defect_metric_decrease_stays_positive_improvement(self) -> None:
        current = {
            "localized_redness": 18.0,
            "breakout_activity": 12.0,
            "diffuse_flushing_erythema": 11.0,
            "sebum_excess_oil_gloss": 9.0,
            "glabellar_wrinkle_depth": 14.0,
            "pore_contraction_index": 10.0,
        }
        baseline = {
            "localized_redness": 24.0,
            "breakout_activity": 15.0,
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
        )

        self.assertEqual(deltas["localized_redness"], 25.0)
        self.assertEqual(deltas["breakout_activity"], 20.0)
        self.assertEqual(deltas["diffuse_flushing_erythema"], 50.0)
        self.assertEqual(deltas["sebum_excess_oil_gloss"], 25.0)
        self.assertEqual(deltas["glabellar_wrinkle_depth"], 30.0)
        self.assertEqual(deltas["pore_contraction_index"], 20.0)

    def test_defect_metric_increase_is_negative_regression(self) -> None:
        current = {"diffuse_flushing_erythema": 30.0}
        baseline = {"diffuse_flushing_erythema": 20.0}

        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths=self._paths("diffuse_flushing_erythema"),
            baseline_paths=self._paths("diffuse_flushing_erythema"),
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

        deltas = _compute_trend_deltas(current, baseline)

        self.assertEqual(deltas["localized_redness"], 0.0)

    def test_path_mismatch_forces_stable_zero(self) -> None:
        current = {"localized_redness": 12.0}
        baseline = {"localized_redness": 24.0}

        deltas = _compute_trend_deltas(
            current,
            baseline,
            current_paths={"localized_redness": "primary_roi"},
            baseline_paths={"localized_redness": "fallback"},
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
        self.assertGreater(redness, 0.0)
        self.assertEqual(_compute_redness_from_personal_baseline({"a_p95": 126.0}, {}), 0.0)

    def test_request_roi_cache_reuses_masks_within_single_analysis(self) -> None:
        cache = main._RequestRoiCache()
        image = np.zeros((120, 120, 3), dtype=np.uint8)
        points = np.zeros((468, 2), dtype=np.float32)
        skin_mask = np.ones((120, 120), dtype=np.uint8) * 255

        first = cache.get_pore_mask((120, 120), points, image, skin_mask)
        second = cache.get_pore_mask((120, 120), points, image, skin_mask)
        self.assertIs(first, second)

        forehead_mask = np.zeros((120, 120), dtype=np.uint8)
        face_skin_mask = np.ones((120, 120), dtype=np.uint8) * 255
        first_tzone = cache.get_tzone_mask((120, 120), points, forehead_mask, skin_mask, face_skin_mask)
        second_tzone = cache.get_tzone_mask((120, 120), points, forehead_mask, skin_mask, face_skin_mask)
        self.assertIs(first_tzone, second_tzone)


if __name__ == "__main__":
    unittest.main()
