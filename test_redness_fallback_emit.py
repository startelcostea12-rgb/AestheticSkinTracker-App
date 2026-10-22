"""The redness availability fallback in analyze_skin_patch (used only when
the zone and canonical redness values are missing) must run without a
NameError. It used to log a name that only exists inside
_compute_canonical_patch_metrics."""

from __future__ import annotations

import math
from pathlib import Path
from unittest import mock

import cv2

import main

PHOTO = Path(__file__).resolve().parent / "test_fixtures" / "metric_regression" / "nikki2.jpg"


def _fixture_bytes() -> bytes:
    image = cv2.imread(str(PHOTO), cv2.IMREAD_COLOR)
    height, width = image.shape[:2]
    side = int(min(height, width) * 0.9)
    x0, y0 = width // 2 - side // 2, height // 2 - side // 2
    image = cv2.resize(image[y0 : y0 + side, x0 : x0 + side], (512, 512))
    ok, buffer = cv2.imencode(".jpg", image)
    assert ok
    return buffer.tobytes()


def test_redness_fallback_runs_when_zone_and_canonical_redness_are_missing():
    real_zone = main._compute_zone_based_metrics
    real_canonical = main._compute_canonical_patch_metrics

    def zone_without_redness(*args, **kwargs):
        metrics = dict(real_zone(*args, **kwargs))
        metrics.pop("localized_redness", None)
        return metrics

    def canonical_without_redness(*args, **kwargs):
        matrix, confidence, raw = real_canonical(*args, **kwargs)
        matrix = dict(matrix)
        matrix.pop("localized_redness", None)
        return matrix, confidence, raw

    normalized, quality = main.assess_and_normalize_image(_fixture_bytes())
    with mock.patch.object(
        main, "_compute_zone_based_metrics", zone_without_redness
    ), mock.patch.object(
        main, "_compute_canonical_patch_metrics", canonical_without_redness
    ):
        result = main.analyze_skin_patch(normalized, quality_profile=quality)

    redness = result["metric_matrix"].get("localized_redness")
    assert redness is not None and math.isfinite(float(redness))
