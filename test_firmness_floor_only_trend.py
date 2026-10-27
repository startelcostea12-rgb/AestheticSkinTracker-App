"""structural_firmness_elasticity: a move at or past its own measured noise
floor is never labeled "stable" by the shared 8% honesty band. Every other
metric still applies the band after its floor, and the band constant is
unchanged.
"""
from __future__ import annotations

import pytest

import main


def _status(metric_key: str, current: float, baseline: float) -> tuple[float, str]:
    return main._trend_delta_and_status(
        metric_key,
        current,
        baseline,
        "primary_roi",
        "primary_roi",
        main.HONESTY_STABLE_BAND_PCT,
        "normal",
        "normal",
        current_formula_version=main._metric_formula_version(metric_key),
        baseline_formula_version=main._metric_formula_version(metric_key),
        current_pose_template="front",
        baseline_pose_template="front",
        current_guide_type="facial",
        baseline_guide_type="facial",
    )


def test_band_constant_and_floor_only_set_are_as_expected():
    assert main.HONESTY_STABLE_BAND_PCT == 8.0
    assert main.TREND_FLOOR_ONLY_METRICS == {"structural_firmness_elasticity"}
    assert main.METRIC_NOISE_FLOOR_2SD["structural_firmness_elasticity"] == 5.0


@pytest.mark.parametrize(
    ("current", "expected"),
    [
        (75.0, "worsened"),
        (74.9, "worsened"),
        (85.0, "improved"),
    ],
)
def test_firmness_move_at_or_past_its_floor_is_not_stable(current, expected):
    delta, status = _status("structural_firmness_elasticity", current, 80.0)
    assert status == expected
    assert delta != 0.0


@pytest.mark.parametrize("current", [53.8, 54.3, 57.7, 58.7, 52.2, 51.9, 58.8, 51.8, 59.8])
def test_firmness_move_inside_its_floor_stays_stable(current):
    assert _status("structural_firmness_elasticity", current, 55.8) == (0.0, "stable")


def test_pigment_still_uses_the_band_after_its_floor():
    # +2.1 points clears pigment's 2.0 floor but is only +7% of 30.0.
    assert _status("pigment_load", 32.1, 30.0) == (0.0, "stable")
    # Past the floor and past the band still gets a direction.
    assert _status("pigment_load", 9.9, 7.67)[1] == "worsened"


def test_pore_visibility_still_uses_the_band_after_its_floor():
    # +1.0 reaches pore's 1.0 floor but is only +7.3% of 13.7.
    assert _status("pore_visibility", 14.7, 13.7) == (0.0, "stable")


def test_texture_and_radiance_unchanged():
    # Radiance: +-1.2 clears its 1.1 floor but is only 3.7% of 32.1.
    assert _status("skin_tone_radiance_evenness", 30.9, 32.1) == (0.0, "stable")
    # Texture: inside its 5.4 floor.
    assert _status("texture_smoothness", 59.0, 57.5) == (0.0, "stable")
