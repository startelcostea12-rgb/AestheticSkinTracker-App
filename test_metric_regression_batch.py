"""Full-pipeline regression gate for real skin-metric reference photos.

This suite exists because main.py's scoring formulas have been fixed
multiple times after real bugs (redness suppression, pigment
ceiling-clustering, pigment pedestal contamination). This is the permanent
safeguard against those exact regressions recurring silently.

The suite intentionally bypasses camera-framing QA because several references
are clinical crops, but it still runs the real normalization, landmarks, ROIs,
YOLO, zone formulas, and canonical metric assembly in analyze_skin_patch.
"""

from __future__ import annotations

import json
import math
import warnings
from pathlib import Path
from typing import Any

import cv2
import pytest

import main


REPO_ROOT = Path(__file__).resolve().parent
MANIFEST_PATH = REPO_ROOT / "test_fixtures" / "metric_regression" / "manifest.json"


def _load_manifest() -> dict[str, Any]:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def _prepare_image_bytes(photo_path: Path, preprocess: dict[str, Any]) -> bytes:
    if not photo_path.is_file():
        pytest.fail(f"Metric regression fixture is missing: {photo_path}")

    mode = preprocess.get("mode", "raw")
    if mode == "raw":
        return photo_path.read_bytes()

    image = cv2.imread(str(photo_path), cv2.IMREAD_COLOR)
    if image is None:
        pytest.fail(f"Metric regression fixture cannot be decoded: {photo_path}")

    if mode == "center_crop_resize_jpeg":
        crop_fraction = float(preprocess["crop_fraction"])
        height, width = image.shape[:2]
        side = int(min(height, width) * crop_fraction)
        center_x, center_y = width // 2, height // 2
        x0 = max(0, center_x - side // 2)
        y0 = max(0, center_y - side // 2)
        image = image[y0 : y0 + side, x0 : x0 + side]
    elif mode != "resize_jpeg":
        pytest.fail(f"Unsupported regression preprocessing mode: {mode}")

    size = int(preprocess["size"])
    image = cv2.resize(image, (size, size), interpolation=cv2.INTER_CUBIC)
    encoded, buffer = cv2.imencode(".jpg", image)
    if not encoded:
        pytest.fail(f"Could not JPEG-encode metric regression fixture: {photo_path}")
    return buffer.tobytes()


def _analyze_case(case: dict[str, Any]) -> dict[str, float]:
    photo_path = REPO_ROOT / case["photo_path"]
    image_bytes = _prepare_image_bytes(photo_path, case["preprocess"])
    normalized_image, quality_profile = main.assess_and_normalize_image(image_bytes)
    result = main.analyze_skin_patch(
        normalized_image,
        quality_profile=quality_profile,
    )
    metric_matrix = result.get("metric_matrix") or {}
    return {
        key: float(value)
        for key, value in metric_matrix.items()
        if value is not None and isinstance(value, (int, float)) and math.isfinite(value)
    }


@pytest.fixture(scope="module")
def regression_results() -> tuple[
    dict[str, Any], dict[str, dict[str, float]], dict[str, str]
]:
    manifest = _load_manifest()
    results: dict[str, dict[str, float]] = {}
    setup_errors: dict[str, str] = {}
    for case in manifest["cases"]:
        try:
            results[case["id"]] = _analyze_case(case)
        except Exception as exc:
            setup_errors[case["id"]] = (
                f"{case['photo_path']}: {type(exc).__name__}: {exc}"
            )
    return manifest, results, setup_errors


def test_fixture_setup_errors_are_reported(
    regression_results: tuple[
        dict[str, Any], dict[str, dict[str, float]], dict[str, str]
    ],
) -> None:
    _manifest, _results, setup_errors = regression_results
    assert not setup_errors, "Fixture setup error(s):\n" + "\n".join(
        f"{case_id}: {error}" for case_id, error in setup_errors.items()
    )


def test_full_pipeline_metric_regressions(
    regression_results: tuple[
        dict[str, Any], dict[str, dict[str, float]], dict[str, str]
    ],
) -> None:
    manifest, results, setup_errors = regression_results
    failures: list[str] = []

    for case in manifest["cases"]:
        if not case["strict"]:
            continue
        if case["id"] in setup_errors:
            continue
        photo_metrics = results[case["id"]]
        for metric, expected in case["metrics"].items():
            actual = photo_metrics.get(metric)
            if actual is None:
                failures.append(
                    f"{case['photo_path']} :: {metric} :: missing; "
                    f"expected [{expected['min']:.1f}, {expected['max']:.1f}]"
                )
                continue
            if not expected["min"] <= actual <= expected["max"]:
                failures.append(
                    f"{case['photo_path']} :: {metric} :: actual={actual:.1f}; "
                    f"expected [{expected['min']:.1f}, {expected['max']:.1f}] "
                    f"around confirmed={expected['confirmed']:.1f}"
                )

    assert not failures, "Skin metric regression(s) detected:\n" + "\n".join(failures)


def test_tracked_outliers_are_reported_without_gating(
    regression_results: tuple[
        dict[str, Any], dict[str, dict[str, float]], dict[str, str]
    ],
) -> None:
    manifest, results, setup_errors = regression_results
    tracked_lines: list[str] = []

    for case in manifest["cases"]:
        if case["strict"]:
            continue
        if case["id"] in setup_errors:
            continue
        photo_metrics = results[case["id"]]
        for metric, expected in case["metrics"].items():
            actual = photo_metrics.get(metric)
            rendered = "missing" if actual is None else f"{actual:.1f}"
            tracked_lines.append(
                f"{case['photo_path']} :: {metric}={rendered} "
                f"(historical={expected['confirmed']:.1f}; non-gating known outlier)"
            )

    assert tracked_lines, "Manifest must contain at least one tracked non-gating case."
    warnings.warn("TRACKED SKIN METRIC OUTLIER: " + " | ".join(tracked_lines), stacklevel=1)


def test_glabellar_wrinkle_depth_no_longer_zeroes_out_on_nikki3(
    regression_results: tuple[
        dict[str, Any], dict[str, dict[str, float]], dict[str, str]
    ],
) -> None:
    """Regression guard for the specific bug fixed in formula v2: nikki3 used
    to have glabellar_wrinkle_depth entirely omitted (the 82nd-percentile
    threshold + (3,5) opening kernel erased its real-but-thin furrow response
    completely). This asserts the value is present and non-zero directly,
    independent of the manifest's numeric band, so a future retune can't
    silently reintroduce the omission while still passing a loosened band.
    """
    _manifest, results, _setup_errors = regression_results
    value = results.get("nikki3", {}).get("glabellar_wrinkle_depth")
    assert value is not None, "glabellar_wrinkle_depth is missing again on nikki3"
    assert value > 0.0, f"glabellar_wrinkle_depth zeroed out again on nikki3: {value}"
