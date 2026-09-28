"""Regression test for the "zero-means-missing" bug in main.py's metric
emission gate.

Background: logs showed frames with ROSACEA_CALIB redness=0.0 having
localized_redness omitted from metric_matrix with reason "non_usable_value"
and redness_path=skipped, while a frame with redness=6.1 was emitted
normally. Root cause: analyze_skin_patch's shared metric-emission loop
disqualified a candidate value as unusable whenever it was `<= 0.0`,
conflating a genuinely measured zero ("no visible redness") with a value
that was never computed at all (None/NaN/Infinite). The exact same
`<= 0.0` disqualifier was duplicated three times (the forced-value gate,
the candidate-value gate, and a redundant post-rounding "rounded_to_floor"
gate), and the same `> 0.0` pattern gated whether pigment_load,
rosacea_severity, skin_tone_radiance_evenness, and structural_firmness_elasticity
were even attempted as forced fallback writes -- so a real zero for any of
those metrics silently never got a chance either.

A second, related bug: the exception handlers around
_compute_zone_based_metrics, _compute_additional_opencv_metrics, and
_compute_structural_opencv_metrics used 0.0 as a "computation failed"
placeholder for their output metrics. Once the zero-disqualifier above is
removed, that placeholder would start being emitted as if it were a real
measurement -- exactly the regression the fix must not introduce. Those
placeholders must be None (missing), not 0.0.

The fix introduces `_is_missing_metric_value`, a pure helper used at every
one of these gates, that only ever treats None/NaN/Infinite as missing. A
finite value of exactly 0.0 (or a negative raw value that clips to 0.0) is
a genuine reading and must be emitted.

This suite does not re-run the full image pipeline (see
test_metric_regression_batch.py for that). It pins the helper's semantics
directly, and statically inspects main.py so the emission-loop gates and
the exception-handler placeholders can't silently regress back to treating
zero as missing.
"""
from __future__ import annotations

import math
import re
from pathlib import Path

import numpy as np

import main

MAIN_PY = Path(__file__).resolve().parent / "main.py"


def _read_main_source() -> str:
    return MAIN_PY.read_text(encoding="utf-8")


class TestIsMissingMetricValue:
    def test_none_is_missing(self):
        assert main._is_missing_metric_value(None) is True

    def test_nan_is_missing(self):
        assert main._is_missing_metric_value(float("nan")) is True

    def test_infinity_is_missing(self):
        assert main._is_missing_metric_value(float("inf")) is True
        assert main._is_missing_metric_value(float("-inf")) is True

    def test_a_genuine_zero_reading_is_not_missing(self):
        # This is the exact scenario from the reported bug: a measured
        # localized_redness of 0.0 ("no visible redness above baseline")
        # must never be treated the same as "never computed".
        assert main._is_missing_metric_value(0.0) is False

    def test_a_negative_raw_value_is_not_missing(self):
        # Represents a raw signal below the zero-reference floor; it still
        # came from a real measurement and clips to 0.0 downstream, it did
        # not fail to measure.
        assert main._is_missing_metric_value(-3.5) is False

    def test_a_positive_value_is_not_missing(self):
        assert main._is_missing_metric_value(6.1) is False


class TestEmissionGatesUseTheSharedMissingCheck:
    """Static guards ensuring the three known gate sites (and the four
    upstream forced-write attempts) route through _is_missing_metric_value
    instead of a reintroduced literal `<= 0.0` / `> 0.0` comparison, and
    that the redundant rounded_to_floor gate stays removed.
    """

    def test_non_usable_value_gate_uses_the_shared_helper(self):
        source = _read_main_source()
        # The candidate-value emission gate: whatever precedes the
        # "non_usable_value" omission reason must be a call to
        # _is_missing_metric_value, not a raw comparison.
        match = re.search(
            r"if (?P<cond>.+?):\s*\n"
            r"\s*metric_status\.setdefault\(metric_key, \"unavailable\"\)\s*\n"
            r"\s*omitted_metric_reasons\[metric_key\] = \"non_usable_value\"",
            source,
        )
        assert match is not None, "non_usable_value gate not found in main.py"
        assert "_is_missing_metric_value" in match.group("cond")
        assert "<= 0.0" not in match.group("cond")

    def test_non_usable_forced_value_gate_uses_the_shared_helper(self):
        source = _read_main_source()
        match = re.search(
            r"if (?P<cond>.+?):\s*\n"
            r"\s*metric_status\.setdefault\(metric_key, \"unavailable\"\)\s*\n"
            r"\s*omitted_metric_reasons\[metric_key\] = \"non_usable_forced_value\"",
            source,
        )
        assert match is not None, "non_usable_forced_value gate not found in main.py"
        assert "_is_missing_metric_value" in match.group("cond")
        assert "<= 0.0" not in match.group("cond")

    def test_rounded_to_floor_gate_was_removed_not_just_relaxed(self):
        # This was a second, redundant zero-disqualifier applied after
        # clipping/rounding. A measured value that rounds to 0.0 is still a
        # genuine reading, so this gate must be gone entirely rather than
        # merely loosened.
        source = _read_main_source()
        assert "rounded_to_floor" not in source

    def test_upstream_forced_write_attempts_no_longer_require_strictly_positive(self):
        # pigment_load, rosacea_severity, skin_tone_radiance_evenness, and
        # structural_firmness_elasticity each decide whether to attempt a
        # forced fallback write by checking their raw numeric candidate.
        # None of those checks may require `> 0.0` any more -- a real zero
        # must still be attempted (and then correctly emitted as 0).
        source = _read_main_source()
        for numeric_name in (
            "pigment_numeric",
            "rosacea_numeric",
            "radiance_numeric",
            "firmness_numeric",
        ):
            assert f"{numeric_name} > 0.0" not in source, (
                f"{numeric_name} still gates its forced-write attempt on "
                "being strictly positive, so a genuine zero reading for "
                "that metric would never be attempted."
            )


class TestFailurePlaceholdersAreMissingNotZero:
    """The exception handlers for zone/additional/structural metric
    extraction must represent a total computation failure as None, never
    as a fabricated 0.0 -- otherwise, once the zero-disqualifier above is
    removed, a real extraction failure would be emitted as if it were a
    genuine "no signal" measurement.
    """

    def test_zone_metrics_exception_fallback_uses_none(self):
        source = _read_main_source()
        match = re.search(
            r"except Exception as exc:\s*\n"
            r"\s*logger\.warning\(\s*\n"
            r'\s*"Zone-based feature extraction failed[^"]*",',
            source,
        )
        assert match is not None
        fallback_block = source[match.end() : match.end() + 400]
        assert '"localized_redness": None' in fallback_block
        assert '"rosacea_severity": None' in fallback_block
        assert '"localized_redness": 0.0' not in fallback_block
        assert '"rosacea_severity": 0.0' not in fallback_block

    def test_additional_metrics_exception_fallback_uses_none(self):
        source = _read_main_source()
        match = re.search(
            r"except Exception as exc:\s*\n"
            r"\s*logger\.warning\(\s*\n"
            r'\s*"Additional feature extraction failed[^"]*",',
            source,
        )
        assert match is not None
        fallback_block = source[match.end() : match.end() + 400]
        assert '"sebum_excess_oil_gloss": None' in fallback_block
        assert '"sebum_excess_oil_gloss": 0.0' not in fallback_block

    def test_structural_metrics_exception_fallback_uses_none(self):
        source = _read_main_source()
        match = re.search(
            r"except Exception as exc:\s*\n"
            r"\s*logger\.warning\(\s*\n"
            r'\s*"Structural feature extraction failed[^"]*",',
            source,
        )
        assert match is not None
        fallback_block = source[match.end() : match.end() + 400]
        assert '"glabellar_wrinkle_depth": None' in fallback_block
        assert '"glabellar_wrinkle_depth": 0.0' not in fallback_block


def test_empty_pore_roi_omits_pore_contraction_index():
    image = np.full((120, 120, 3), 128, dtype=np.uint8)
    empty = np.zeros((120, 120), dtype=np.uint8)
    points = np.zeros((468, 2), dtype=np.float32)

    result = main._compute_structural_opencv_metrics(
        image,
        empty,
        {"left_cheek": empty, "right_cheek": empty},
        points,
    )

    assert "pore_contraction_index" not in result


class TestConfidenceHelperDoesNotDowngradeGenuineZero:
    def test_conf_from_pixels_and_value_gate_uses_the_shared_helper(self):
        # _conf_from_pixels_and_value used to force "low" confidence for any
        # value <= 0.0, which would have kept a genuine zero measurement
        # excluded via the confidence gate even after the value-omission
        # gates above were fixed.
        source = _read_main_source()
        match = re.search(
            r"numeric = safe_float\(value\)\s*\n\s*if (?P<cond>.+?):\s*\n\s*return \"low\"",
            source,
        )
        assert match is not None
        assert "_is_missing_metric_value" in match.group("cond")
        assert "<= 0.0" not in match.group("cond")


class TestSmallRoiZeroFloorMetricsUnaffected:
    """glabellar_wrinkle_depth and the under_eye_* metrics deliberately keep
    treating an adequate-ROI zero as ambiguous ("insufficient_signal") --
    a documented, intentional design distinct from the redness bug, because
    a small ROI genuinely can't distinguish flawless skin from a detector
    floor. This fix must not have touched that mechanism.
    """

    def test_small_roi_zero_floor_mechanism_still_present(self):
        source = _read_main_source()
        assert "small_roi_zero_floor_metrics" in source
        assert "insufficient_signal" in source
