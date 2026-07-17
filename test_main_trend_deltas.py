import unittest

from main import _compute_trend_deltas


class ComputeTrendDeltasTests(unittest.TestCase):
    def test_texture_smoothness_increase_is_positive_improvement(self) -> None:
        current = {"texture_smoothness": 72.0}
        baseline = {"texture_smoothness": 60.0}

        deltas = _compute_trend_deltas(current, baseline)

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

        deltas = _compute_trend_deltas(current, baseline)

        self.assertEqual(deltas["localized_redness"], 25.0)
        self.assertEqual(deltas["breakout_activity"], 20.0)
        self.assertEqual(deltas["diffuse_flushing_erythema"], 50.0)
        self.assertEqual(deltas["sebum_excess_oil_gloss"], 25.0)
        self.assertEqual(deltas["glabellar_wrinkle_depth"], 30.0)
        self.assertEqual(deltas["pore_contraction_index"], 20.0)

    def test_defect_metric_increase_is_negative_regression(self) -> None:
        current = {"diffuse_flushing_erythema": 30.0}
        baseline = {"diffuse_flushing_erythema": 20.0}

        deltas = _compute_trend_deltas(current, baseline)

        self.assertEqual(deltas["diffuse_flushing_erythema"], -50.0)

    def test_radiance_evenness_increase_is_positive_improvement(self) -> None:
        current = {"skin_tone_radiance_evenness": 84.0}
        baseline = {"skin_tone_radiance_evenness": 70.0}

        deltas = _compute_trend_deltas(current, baseline)

        self.assertEqual(deltas["skin_tone_radiance_evenness"], 20.0)

    def test_structural_firmness_increase_is_positive_improvement(self) -> None:
        current = {"structural_firmness_elasticity": 79.2}
        baseline = {"structural_firmness_elasticity": 72.0}

        deltas = _compute_trend_deltas(current, baseline)

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

        deltas = _compute_trend_deltas(current, baseline)

        self.assertEqual(deltas["texture_smoothness"], 0.0)
        self.assertEqual(deltas["localized_redness"], 0.0)
        self.assertEqual(deltas["sebum_excess_oil_gloss"], 0.0)
        self.assertEqual(deltas["diffuse_flushing_erythema"], 0.0)
        self.assertEqual(deltas["skin_tone_radiance_evenness"], 0.0)
        self.assertEqual(deltas["glabellar_wrinkle_depth"], 0.0)
        self.assertEqual(deltas["pore_contraction_index"], 0.0)
        self.assertEqual(deltas["structural_firmness_elasticity"], 0.0)


if __name__ == "__main__":
    unittest.main()
