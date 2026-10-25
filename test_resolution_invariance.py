"""Scores must be approximately invariant to the upload's pixel resolution.

The scoring pipeline runs on a fixed 512x512 face crop, but the crop used to be
cut from the source with bilinear sampling, so a high-resolution upload kept
aliased fine detail that the same face at lower resolution never had.
_align_and_crop_face now first area-averages large crops to a canonical analysis
resolution (_CANONICAL_ANALYSIS_CROP_SIZE).

Measured spread (max - min over long-side 512/768/1024/1536 px copies of the
same fixture, texture_smoothness, resolution fix only, texture formula as it was):
before 1.7 / 24.1 / 20.3 / 15.8 / 10.7 (clear_face / st1 / nikki2 / nikki3 /
portrait_09); after 0.3 / 4.0 / 2.1 / 2.4 / 0.9. Tolerances below sit just above
the post-fix numbers and well below the pre-fix ones; see
tool/measure_resolution_spread.py to re-measure every metric.
"""

from __future__ import annotations

import logging
import math
from pathlib import Path

import cv2
import numpy as np
import pytest

import main

REPO_ROOT = Path(__file__).resolve().parent
FIXTURES = {
    "clear_face": "test_fixtures/metric_regression/clear_face.jfif",
    "st1": "test_fixtures/metric_regression/st1.jpg",
    "nikki3": "test_fixtures/metric_regression/nikki3.jpg",
}
LONG_SIDES = (512, 768, 1024, 1536)
# metric -> max allowed (max - min) across LONG_SIDES, in score points.
TOLERANCE = {
    "texture_smoothness": 6.0,
    "wrinkle_load": 5.0,
}


def _score_at_long_side(image: np.ndarray, long_side: int) -> dict[str, float]:
    h, w = image.shape[:2]
    scale = long_side / max(h, w)
    interpolation = cv2.INTER_AREA if scale < 1.0 else cv2.INTER_CUBIC
    resized = cv2.resize(
        image, (round(w * scale), round(h * scale)), interpolation=interpolation
    )
    ok, buffer = cv2.imencode(".png", resized)
    assert ok
    normalized, quality = main.assess_and_normalize_image(buffer.tobytes())
    result = main.analyze_skin_patch(normalized, quality_profile=quality)
    return {
        key: float(value)
        for key, value in (result.get("metric_matrix") or {}).items()
        if isinstance(value, (int, float)) and math.isfinite(value)
    }


@pytest.fixture(scope="module")
def scores_by_resolution() -> dict[str, dict[int, dict[str, float]]]:
    logging.disable(logging.CRITICAL)
    try:
        out: dict[str, dict[int, dict[str, float]]] = {}
        for name, rel in FIXTURES.items():
            image = cv2.imread(str(REPO_ROOT / rel), cv2.IMREAD_COLOR)
            if image is None:
                pytest.fail(f"fixture cannot be decoded: {rel}")
            out[name] = {side: _score_at_long_side(image, side) for side in LONG_SIDES}
        return out
    finally:
        logging.disable(logging.NOTSET)


@pytest.mark.parametrize("fixture", sorted(FIXTURES))
@pytest.mark.parametrize("metric", sorted(TOLERANCE))
def test_metric_spread_across_resolutions_within_tolerance(
    scores_by_resolution, fixture, metric
) -> None:
    values = [scores_by_resolution[fixture][side].get(metric) for side in LONG_SIDES]
    assert all(v is not None for v in values), f"{metric} missing for {fixture}: {values}"
    spread = max(values) - min(values)
    assert spread <= TOLERANCE[metric], (
        f"{metric} on {fixture} varies by {spread:.1f} across long sides "
        f"{LONG_SIDES}: {values} (tolerance {TOLERANCE[metric]})"
    )


def _synthetic_face(size: int) -> tuple[np.ndarray, np.ndarray]:
    """Same smooth+textured scene rendered at `size` px, with level eyes and a
    fixed face box expressed in fractions of the image."""
    rng = np.random.default_rng(3)
    base = rng.normal(128.0, 40.0, (1024, 1024)).astype(np.float32)
    base = cv2.GaussianBlur(base, (0, 0), 3.0)
    base += cv2.GaussianBlur(rng.normal(0.0, 25.0, (1024, 1024)).astype(np.float32), (0, 0), 0.7)  # fine detail
    base += 30.0 * np.sin(np.linspace(0.0, 40.0, 1024, dtype=np.float32))[None, :]
    base = np.clip(base, 0, 255).astype(np.uint8)
    img = cv2.cvtColor(cv2.resize(base, (size, size), interpolation=cv2.INTER_AREA), cv2.COLOR_GRAY2BGR)
    pts = np.zeros((468, 2), dtype=np.float32)
    box = np.array([[0.25, 0.15], [0.75, 0.85]], dtype=np.float32) * size
    pts[:] = box[0]
    pts[0] = box[1]
    for idx, (fx, fy) in {33: (0.38, 0.40), 133: (0.44, 0.40), 362: (0.56, 0.40), 263: (0.62, 0.40)}.items():
        pts[idx] = (fx * size, fy * size)
    return img, pts


def test_face_crop_does_not_depend_on_source_resolution() -> None:
    """Crops of one scene rendered at 1024 px and at 512 px agree closely
    (fine-detail noise included); bilinear cropping left a ~3.2 grey-level gap."""
    hi_img, hi_pts = _synthetic_face(1024)
    lo_img, lo_pts = _synthetic_face(512)
    hi_crop, _ = main._align_and_crop_face(hi_img, hi_pts)
    lo_crop, _ = main._align_and_crop_face(lo_img, lo_pts)
    assert hi_crop.shape == lo_crop.shape == (512, 512, 3)
    diff = np.abs(hi_crop.astype(np.float32) - lo_crop.astype(np.float32)).mean()
    assert diff < 2.0, f"mean abs crop difference {diff:.2f} grey levels"
    # And fine detail energy matches (this is what texture/pore scores read).
    lap = lambda c: float(np.abs(cv2.Laplacian(cv2.cvtColor(c, cv2.COLOR_BGR2GRAY), cv2.CV_32F)).mean())
    assert lap(hi_crop) == pytest.approx(lap(lo_crop), rel=0.15)


def test_small_sources_are_not_blurred_further() -> None:
    """A crop already at or below the canonical analysis size is only resized
    to 512, never area-averaged first."""
    img, pts = _synthetic_face(200)
    crop, _ = main._align_and_crop_face(img, pts)
    assert crop.shape == (512, 512, 3)
