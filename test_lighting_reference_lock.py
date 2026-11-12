import unittest

from main import (
    LIGHTING_REF_COLOR_AFTER_WB_LIMIT,
    LIGHTING_REF_MEAN_L_LIMIT,
    _apply_lighting_reference_trend_lock,
    _evaluate_lighting_reference_check,
    _parse_image_quality_map,
)


def _quality(*, L=122.92, a=5.689, b=9.788):
    return {
        "lighting_mean_l": L,
        "whole_image_mean_a_after_wb": a,
        "whole_image_mean_b_after_wb": b,
    }


# Nov 7 23:51:49 baseline references from the 60-scan export.
BASELINE = _quality()

# Nov 7 23:55 same-session follow-up: color distance 0.90, dL 0.09.
MATCHING = _quality(L=122.83, a=6.55, b=9.529)

# Nov 9 21:41:00: color distance 8.33, dL 1.06.
MISMATCH = _quality(L=123.98, a=12.03, b=4.38)


class LightingReferenceEvaluationTests(unittest.TestCase):
    def test_matching_same_session_is_within_threshold(self) -> None:
        check = _evaluate_lighting_reference_check(MATCHING, BASELINE)
        self.assertEqual(check["status"], "match")
        self.assertIsNone(check["lock_reason"])
        self.assertLess(check["color_delta_after_wb"], LIGHTING_REF_COLOR_AFTER_WB_LIMIT)
        self.assertLess(check["lighting_mean_l_delta"], LIGHTING_REF_MEAN_L_LIMIT)
        self.assertEqual(check["failed_signals"], [])

    def test_nov9_color_shift_is_a_mismatch(self) -> None:
        check = _evaluate_lighting_reference_check(MISMATCH, BASELINE)
        self.assertEqual(check["status"], "mismatch")
        self.assertEqual(check["lock_reason"], "lighting_mismatch")
        self.assertGreater(check["color_delta_after_wb"], LIGHTING_REF_COLOR_AFTER_WB_LIMIT)
        self.assertIn("color_after_wb", check["failed_signals"])

    def test_brightness_only_shift_locks(self) -> None:
        # Color matches; L moves past the 8.0 same-night ceiling.
        current = _quality(L=122.92 + 8.1, a=5.689, b=9.788)
        check = _evaluate_lighting_reference_check(current, BASELINE)
        self.assertEqual(check["status"], "mismatch")
        self.assertEqual(check["failed_signals"], ["lighting_mean_l"])

    def test_missing_baseline_quality_fails_open(self) -> None:
        check = _evaluate_lighting_reference_check(MATCHING, None)
        self.assertEqual(check["status"], "no_baseline")
        self.assertIsNone(check["lock_reason"])

        check = _evaluate_lighting_reference_check(MATCHING, {})
        self.assertEqual(check["status"], "no_baseline")
        self.assertIsNone(check["lock_reason"])

    def test_missing_reference_fields_fail_open(self) -> None:
        check = _evaluate_lighting_reference_check({"blur_score": 1.0}, {"blur_score": 1.0})
        self.assertEqual(check["status"], "lighting_reference_unavailable")
        self.assertEqual(check["unavailable_reason"], "missing_lighting_or_color_reference")
        self.assertIsNone(check["lock_reason"])

    def test_invalid_baseline_json_fails_open(self) -> None:
        parsed = _parse_image_quality_map("not-json")
        self.assertEqual(parsed, {})
        check = _evaluate_lighting_reference_check(MATCHING, parsed)
        self.assertEqual(check["status"], "no_baseline")


class LightingReferenceTrendLockTests(unittest.TestCase):
    def _maps(self):
        return (
            {
                "texture_smoothness": "stable",
                "pigment_load": "worsened",
                "localized_redness": "improved",
                "under_eye_dark_circle_density": "worsened",
            },
            {
                "texture_smoothness": 0.0,
                "pigment_load": -75.3,
                "localized_redness": 10.0,
                "under_eye_dark_circle_density": -12.6,
            },
            {"under_eye_dark_circle_density": None},
        )

    def test_mismatch_clears_verdicts_keeps_raw_claim_and_under_eye(self) -> None:
        status, deltas, reasons = self._maps()
        check = _evaluate_lighting_reference_check(MISMATCH, BASELINE)
        metric_values = {"pigment_load": 15.5, "under_eye_dark_circle_density": 25.2}
        _apply_lighting_reference_trend_lock(status, deltas, reasons, check)

        self.assertNotIn("texture_smoothness", status)
        self.assertNotIn("pigment_load", status)
        self.assertNotIn("localized_redness", status)
        self.assertNotIn("pigment_load", deltas)
        self.assertEqual(
            reasons,
            {
                "texture_smoothness": "lighting_mismatch",
                "pigment_load": "lighting_mismatch",
                "localized_redness": "lighting_mismatch",
                "under_eye_dark_circle_density": None,
            },
        )
        # Claim-free under-eye is unchanged, including any pre-existing status.
        self.assertEqual(status["under_eye_dark_circle_density"], "worsened")
        self.assertEqual(deltas["under_eye_dark_circle_density"], -12.6)
        # Raw metric numbers are not part of this lock and stay as they were.
        self.assertEqual(metric_values["pigment_load"], 15.5)
        self.assertEqual(metric_values["under_eye_dark_circle_density"], 25.2)

    def test_matching_lighting_leaves_verdicts_unchanged(self) -> None:
        status, deltas, reasons = self._maps()
        original_status = dict(status)
        original_deltas = dict(deltas)
        original_reasons = dict(reasons)
        check = _evaluate_lighting_reference_check(MATCHING, BASELINE)
        _apply_lighting_reference_trend_lock(status, deltas, reasons, check)
        self.assertEqual(status, original_status)
        self.assertEqual(deltas, original_deltas)
        self.assertEqual(reasons, original_reasons)

    def test_unavailable_reference_leaves_verdicts_unchanged(self) -> None:
        status, deltas, reasons = self._maps()
        original_status = dict(status)
        check = _evaluate_lighting_reference_check({"blur_score": 1.0}, {"blur_score": 1.0})
        _apply_lighting_reference_trend_lock(status, deltas, reasons, check)
        self.assertEqual(status, original_status)
        self.assertEqual(check["status"], "lighting_reference_unavailable")


if __name__ == "__main__":
    unittest.main()
