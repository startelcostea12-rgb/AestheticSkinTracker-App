"""sebum_excess_oil_gloss v3: a T-zone pixel counts as an oil highlight
only when it is bright, low-saturation, AND locally peaked, so a flat
clipped (overexposed) region no longer counts as oil."""
from __future__ import annotations

import cv2
import numpy as np

import main


def _v2_sebum(val, sat, t_zone):
    """The previous formula: V >= max(220, T-zone p95 V), S <= 70 -- the
    same bright-pixel mask radiance still excludes."""
    mask = main._radiance_specular_exclusion_mask(val, sat, t_zone)
    return cv2.countNonZero(mask) / max(cv2.countNonZero(t_zone), 1) * 100.0


def _skin(size=200, seed=5):
    rng = np.random.default_rng(seed)
    val = np.clip(rng.normal(170, 6, (size, size)), 0, 255).astype(np.uint8)
    sat = np.full((size, size), 50, dtype=np.uint8)
    t_zone = np.full((size, size), 255, dtype=np.uint8)
    return val, sat, t_zone


def _add_specular_points(val, count=40, seed=7):
    rng = np.random.default_rng(seed)
    out = val.copy()
    for _ in range(count):
        y, x = rng.integers(10, val.shape[0] - 10, size=2)
        cv2.circle(out, (int(x), int(y)), 2, 250, -1)
    return out


def test_version_and_constants():
    assert main._metric_formula_version("sebum_excess_oil_gloss") == 3
    assert main.SEBUM_HIGHLIGHT_MIN_V == 220.0
    assert main.SEBUM_HIGHLIGHT_MAX_SATURATION == 70
    assert main.SEBUM_HIGHLIGHT_LOCAL_SIGMA == 5.0
    assert main.SEBUM_HIGHLIGHT_MIN_LOCAL_CONTRAST == 15.0


def test_small_specular_points_count_as_oil():
    val, sat, t_zone = _skin()
    assert main.compute_sebum_gloss(val, sat, t_zone) == 0.0
    oily = _add_specular_points(val)
    assert main.compute_sebum_gloss(oily, sat, t_zone) > 0.5


def test_a_flat_clipped_region_does_not_count_as_oil():
    val, sat, t_zone = _skin()
    oily = _add_specular_points(val)
    clipped = oily.copy()
    clipped[40:120, 40:120] = 255  # a large overexposed, flat plateau

    v3_before = main.compute_sebum_gloss(oily, sat, t_zone)
    v3_after = main.compute_sebum_gloss(clipped, sat, t_zone)
    v2_before = _v2_sebum(oily, sat, t_zone)
    v2_after = _v2_sebum(clipped, sat, t_zone)

    plateau_share = 80 * 80 / (200 * 200) * 100.0  # 16% of the T-zone
    assert v2_after - v2_before > plateau_share * 0.8  # v2 counts the plateau
    assert v3_after - v3_before < plateau_share * 0.25  # v3 counts its rim only


def test_radiance_exclusion_mask_is_unchanged():
    # Radiance still excludes v2-style bright pixels; the sebum change must
    # not alter radiance's refined-skin exclusions.
    val, sat, t_zone = _skin()
    clipped = val.copy()
    clipped[40:120, 40:120] = 255
    mask = main._radiance_specular_exclusion_mask(clipped, sat, t_zone)
    assert cv2.countNonZero(mask) >= 80 * 80 * 0.9
