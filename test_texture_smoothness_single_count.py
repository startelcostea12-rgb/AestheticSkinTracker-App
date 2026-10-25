"""texture_smoothness: var_p80 and lap_p80 must each contribute once.

The roughness blend used to add var_p80 / lap_p80 directly (n_var, n_lap) and
again through texture_energy (n_energy). These tests pin the single-count
structure and that the score keeps its 0-100 range and direction.
"""

import math

import numpy as np
import pytest

from main import _texture_roughness_index, _texture_smoothness_from_roughness


def _old_roughness(var_p80: float, lap_p80: float, spread: float) -> float:
    """The pre-fix (double-counting) formula, kept only as a reference."""
    sv = math.sqrt(max(var_p80, 0.0))
    energy = 0.65 * sv + 0.35 * lap_p80
    n_energy = float(np.clip((energy - 8.0) / 22.0, 0.0, 1.0))
    n_var = float(np.clip((sv - 6.0) / 14.0, 0.0, 1.0))
    n_lap = float(np.clip((lap_p80 - 14.0) / 32.0, 0.0, 1.0))
    n_spread = float(np.clip((spread - 18.0) / 32.0, 0.0, 1.0))
    return float(np.clip(0.45 * n_energy + 0.20 * n_var + 0.20 * n_lap + 0.15 * n_spread, 0.0, 1.0))


def _smooth(var_p80, lap_p80, spread):
    return _texture_smoothness_from_roughness(_texture_roughness_index(var_p80, lap_p80, spread))


def test_each_signal_enters_only_through_energy_in_the_unclipped_range():
    # sqrt(var)=12, lap=20, spread=24 sits inside every old clip window.
    base = _texture_roughness_index(144.0, 20.0, 24.0)
    d = 0.5
    # Moving sqrt(var) by d moves roughness by exactly 0.85 * 0.65 * d / 22.
    up_var = _texture_roughness_index((12.0 + d) ** 2, 20.0, 24.0)
    assert up_var - base == pytest.approx(0.85 * 0.65 * d / 22.0, rel=1e-6)
    # Same for lap_p80 with weight 0.35.
    up_lap = _texture_roughness_index(144.0, 20.0 + d, 24.0)
    assert up_lap - base == pytest.approx(0.85 * 0.35 * d / 22.0, rel=1e-6)
    # And spread keeps its 0.15 weight over its own 32-unit window.
    up_spread = _texture_roughness_index(144.0, 20.0, 24.0 + d)
    assert up_spread - base == pytest.approx(0.15 * d / 32.0, rel=1e-6)


def test_slope_stays_close_to_the_old_formula():
    """Removing the double count must not silently re-scale the score: the
    per-signal slope matches the old formula to within 15%."""
    d = 0.5
    old_base = _old_roughness(144.0, 20.0, 24.0)
    new_base = _texture_roughness_index(144.0, 20.0, 24.0)
    for args in (((12.0 + d) ** 2, 20.0, 24.0), (144.0, 20.0 + d, 24.0)):
        old_slope = _old_roughness(*args) - old_base
        new_slope = _texture_roughness_index(*args) - new_base
        assert new_slope == pytest.approx(old_slope, rel=0.15)


def test_range_and_direction_are_unchanged():
    assert _smooth(0.0, 0.0, 0.0) == pytest.approx(100.0)
    assert _smooth(10_000.0, 500.0, 200.0) == pytest.approx(0.0)
    rng = np.random.default_rng(7)
    for _ in range(200):
        v, l, s = rng.uniform(0, 900), rng.uniform(0, 80), rng.uniform(0, 60)
        score = _smooth(v, l, s)
        assert 0.0 <= score <= 100.0
        # rougher inputs never score smoother
        assert _smooth(v + 25.0, l + 2.0, s + 2.0) <= score + 1e-9


def test_saturated_energy_cannot_stack_with_extra_terms():
    """Old: past the clip points all three var/lap-derived terms saturate at
    once. New: a single saturated energy term caps their share at 0.85."""
    assert _texture_roughness_index(900.0, 80.0, 0.0) == pytest.approx(0.85)
