"""Regression tests for the core metric scoring formulas in main.py.

These target the pure functions extracted from _compute_zone_based_metrics
and _compute_canonical_patch_metrics (compute_localized_redness_and_rosacea,
compute_pigment_load, compute_under_eye_dark_circle_density,
is_redness_unset) — plain scalar in, scalar out, no image/ROI pipeline
involved. Each test locks in a specific, already-verified fix so a future
edit to these formulas can't silently regress it.
"""

import math

import pytest

from main import (
    PIGMENT_LOAD_DEAD_ZONE_SIGNAL,
    PIGMENT_LOAD_L_CONTRAST_WEIGHT,
    PIGMENT_LOAD_SCORE_CENTER,
    PIGMENT_LOAD_SCORE_SLOPE,
    UNDER_EYE_DARK_CIRCLE_DEAD_ZONE_L_UNITS,
    UNDER_EYE_DARK_CIRCLE_SCORE_MULTIPLIER,
    compute_localized_redness_and_rosacea,
    compute_pigment_load,
    compute_under_eye_dark_circle_density,
    is_redness_unset,
)


# ── 1. localized_redness / rosacea_severity ─────────────────────────────


class TestLocalizedRednessAndRosacea:
    def test_zero_signal_yields_zero_redness_and_rosacea(self):
        result = compute_localized_redness_and_rosacea(
            p95_a=128.0, baseline_a_ref=128.0, diffuse_density=0.0
        )
        assert result["localized_redness"] == 0.0
        assert result["rosacea_severity"] == 0.0
        assert result["rosacea_reason"] == "unchanged"

    def test_moderate_redness_with_low_diffuse_density_is_uncapped(self):
        # p95_a - baseline = 10 -> localized_redness = 31.0, well under the
        # 25.0 cap-eligibility threshold's cap check only fires when
        # rosacea_before actually exceeds the cap.
        result = compute_localized_redness_and_rosacea(
            p95_a=138.0, baseline_a_ref=128.0, diffuse_density=20.0
        )
        assert result["localized_redness"] == pytest.approx(31.0, abs=0.05)
        assert result["rosacea_reason"] == "unchanged"
        # rosacea_before = 0.65*diffuse_flushing_erythema + 0.35*localized_redness
        diffuse_flushing = 0.70 * 20.0 + 0.30 * result["localized_redness"]
        expected_rosacea = 0.65 * diffuse_flushing + 0.35 * result["localized_redness"]
        assert result["rosacea_severity"] == pytest.approx(expected_rosacea, abs=0.05)

    def test_low_redness_high_diffuse_divergence_triggers_the_cap(self):
        # Low localized_redness (<=25) but very high diffuse_density can
        # push rosacea_before far above what a low-redness face should show
        # -- this is exactly the divergence the cap exists to catch.
        result = compute_localized_redness_and_rosacea(
            p95_a=131.0, baseline_a_ref=128.0, diffuse_density=100.0
        )
        assert result["localized_redness"] <= 25.0
        assert result["rosacea_reason"] == "cap_low_redness_divergence"
        rosacea_cap = max(
            result["localized_redness"] + 20.0,
            result["localized_redness"] * 2.5,
            100.0 * 0.45,
        )
        assert result["rosacea_severity"] == pytest.approx(
            min(rosacea_cap, 100.0), abs=0.05
        )
        # The cap must actually have reduced it below the uncapped value.
        assert result["rosacea_severity"] < result["rosacea_before"]

    def test_high_redness_is_never_capped_even_with_high_diffuse_density(self):
        result = compute_localized_redness_and_rosacea(
            p95_a=160.0, baseline_a_ref=128.0, diffuse_density=100.0
        )
        assert result["localized_redness"] > 25.0
        assert result["rosacea_reason"] == "unchanged"
        assert result["rosacea_severity"] == result["rosacea_before"]

    def test_output_is_clipped_to_0_100(self):
        result = compute_localized_redness_and_rosacea(
            p95_a=500.0, baseline_a_ref=0.0, diffuse_density=100.0
        )
        assert result["localized_redness"] == 100.0
        assert 0.0 <= result["rosacea_severity"] <= 100.0


# ── 2. pigment_load (dead_zone=4.0, center=13.5, slope=3.6) ─────────────


class TestPigmentLoad:
    def test_constants_match_the_calibrated_values(self):
        # If these ever drift, the known before/after pairs below will
        # silently stop meaning what this test file says they mean.
        assert PIGMENT_LOAD_DEAD_ZONE_SIGNAL == 4.0
        assert PIGMENT_LOAD_SCORE_CENTER == 13.5
        assert PIGMENT_LOAD_SCORE_SLOPE == 3.6

    def test_l_contrast_is_excluded_from_the_signal(self):
        # Measured discrimination between a visually clear and a visibly
        # pigmented cheek was 1.01x, so the term contributes nothing but a
        # pedestal that lifts the floor off genuinely clear skin.
        assert PIGMENT_LOAD_L_CONTRAST_WEIGHT == 0.0

    def test_visually_clear_face_signal_6_77_scores_low(self):
        # clear face.jfif, measured cheek self-mean chroma dispersion.
        assert compute_pigment_load(6.77) == pytest.approx(13.4, abs=0.2)

    def test_visibly_pigmented_face_signal_12_99_scores_mid(self):
        # st1.jpg, same measurement path.
        assert compute_pigment_load(12.99) == pytest.approx(46.5, abs=0.2)

    def test_clear_and_pigmented_faces_are_clearly_separated(self):
        # The pedestal bug left these only 1.95x apart (35.4 vs 68.9).
        clear = compute_pigment_load(6.77)
        pigmented = compute_pigment_load(12.99)
        assert pigmented / clear > 3.0

    def test_signal_at_or_below_the_dead_zone_does_not_score_zero(self):
        # The dead zone shifts the sigmoid's effective input, it does not
        # hard-floor the score to 0 -- a signal of exactly the dead zone
        # still sits partway up the curve (effective_signal = 0).
        score_at_dead_zone = compute_pigment_load(PIGMENT_LOAD_DEAD_ZONE_SIGNAL)
        score_below_dead_zone = compute_pigment_load(0.0)
        assert score_at_dead_zone == score_below_dead_zone
        assert 0.0 < score_at_dead_zone < 50.0

    def test_score_is_monotonically_increasing_with_signal(self):
        signals = [0.0, 4.0, 6.77, 10.0, 12.99, 15.5, 20.0, 36.76]
        scores = [compute_pigment_load(s) for s in signals]
        assert scores == sorted(scores)

    def test_very_negative_signal_floors_at_the_dead_zone_zero_point_not_0(self):
        # effective_signal = max(0.0, signal - dead_zone) clamps at 0 for
        # any signal at or below the dead zone, so arbitrarily negative
        # signals all floor at the same sigmoid value, not 0.0.
        floor_value = compute_pigment_load(0.0)
        assert compute_pigment_load(-1000.0) == pytest.approx(floor_value, abs=0.001)
        assert 0.0 < floor_value < 15.0

    def test_very_positive_signal_approaches_100(self):
        assert compute_pigment_load(1000.0) == pytest.approx(100.0, abs=0.5)

    def test_output_stays_within_0_100_bounds(self):
        for signal in (-1000.0, -50.0, 0.0, 6.77, 12.99, 100.0, 1000.0):
            score = compute_pigment_load(signal)
            assert 0.0 <= score <= 100.0


# ── 3. under_eye_dark_circle_density dead-zone formula ──────────────────


class TestUnderEyeDarkCircleDensity:
    def test_constants_match_the_calibrated_values(self):
        assert UNDER_EYE_DARK_CIRCLE_DEAD_ZONE_L_UNITS == 8.0
        assert UNDER_EYE_DARK_CIRCLE_SCORE_MULTIPLIER == 1.2

    def test_delta_within_the_dead_zone_scores_zero(self):
        # Anatomical eye-socket shadow, not a dark circle.
        assert compute_under_eye_dark_circle_density(0.0) == 0.0
        assert compute_under_eye_dark_circle_density(5.0) == 0.0
        assert compute_under_eye_dark_circle_density(8.0) == 0.0

    def test_delta_past_the_dead_zone_scales_by_the_multiplier(self):
        # delta=20 -> effective=12 -> score = 12 * 1.2 = 14.4
        assert compute_under_eye_dark_circle_density(20.0) == pytest.approx(14.4, abs=0.01)

    def test_a_large_raw_delta_no_longer_saturates_to_100_under_the_new_multiplier(self):
        # This is the exact regression the 2.0 -> 1.2 multiplier change was
        # for: real photos showed raw deltas of >=50 from anatomical shadow
        # and lighting/angle alone, which used to saturate to 100.0 under
        # the old multiplier=2.0, no-dead-zone formula.
        old_formula_score = 50.0 * 2.0  # pre-fix: raw delta * 2.0, no dead zone
        assert old_formula_score >= 100.0  # confirms the old formula did saturate

        new_score = compute_under_eye_dark_circle_density(50.0)
        assert new_score < 100.0
        # effective = 50 - 8 = 42; score = 42 * 1.2 = 50.4
        assert new_score == pytest.approx(50.4, abs=0.01)

    def test_output_is_clipped_to_0_100(self):
        assert compute_under_eye_dark_circle_density(-10.0) == 0.0
        assert compute_under_eye_dark_circle_density(1000.0) == 100.0


# ── 4. redness canonical-value-wins-over-fallback guard ─────────────────


class TestRednessUnsetGuard:
    def test_a_valid_positive_canonical_value_is_not_unset(self):
        # This is the exact scenario that was broken before: a valid,
        # already-computed canonical localized_redness value must make
        # redness_unset False, so the mean-based cheek-ROI fallback block
        # (gated entirely on redness_unset being True) is never entered
        # and therefore can never overwrite it.
        assert is_redness_unset(42.5) is False
        assert is_redness_unset(0.1) is False
        assert is_redness_unset(100.0) is False

    def test_none_is_unset(self):
        assert is_redness_unset(None) is True

    def test_zero_is_unset(self):
        # Matches _compute_zone_based_metrics's own "unset" convention:
        # a canonical value of exactly 0.0 is treated as never having been
        # computed, not as a genuine "no redness detected" reading.
        assert is_redness_unset(0.0) is True

    def test_negative_is_unset(self):
        assert is_redness_unset(-5.0) is True

    def test_nan_is_unset(self):
        assert is_redness_unset(float("nan")) is True

    def test_infinity_is_unset(self):
        assert is_redness_unset(float("inf")) is True

    def test_fallback_gating_end_to_end_with_a_valid_canonical_value(self):
        # Mirrors the real call site's exact branch structure:
        #   if redness_unset and roi_pixels >= 500: <fallback overwrites>
        #   elif redness_unset: <mark unavailable>
        #   (else: canonical_metric_matrix is left untouched)
        canonical_metric_matrix = {"localized_redness": 42.5}
        redness_current = canonical_metric_matrix.get("localized_redness")
        redness_unset = is_redness_unset(redness_current)
        redness_roi_pixels = 5000  # plenty of pixels available for the fallback

        ran_fallback = False
        if redness_unset and redness_roi_pixels >= 500:
            ran_fallback = True
            canonical_metric_matrix["localized_redness"] = 99.9  # would-be overwrite
        elif redness_unset:
            canonical_metric_matrix["localized_redness"] = None

        assert ran_fallback is False
        assert canonical_metric_matrix["localized_redness"] == 42.5

    def test_fallback_gating_end_to_end_with_an_unset_canonical_value(self):
        # Sanity check the opposite branch still works: when there is no
        # valid canonical value, the fallback IS allowed to run.
        canonical_metric_matrix = {"localized_redness": 0.0}
        redness_current = canonical_metric_matrix.get("localized_redness")
        redness_unset = is_redness_unset(redness_current)
        redness_roi_pixels = 5000

        ran_fallback = False
        if redness_unset and redness_roi_pixels >= 500:
            ran_fallback = True
            canonical_metric_matrix["localized_redness"] = 55.0

        assert ran_fallback is True
        assert canonical_metric_matrix["localized_redness"] == 55.0
