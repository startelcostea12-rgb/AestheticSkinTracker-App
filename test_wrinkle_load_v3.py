"""wrinkle_load v3: Canny runs on a Gaussian-smoothed patch, so a slight
focus/sharpening change no longer flips fine-texture edges on and off,
while real lines still register."""
from __future__ import annotations

import json
from pathlib import Path
from unittest import mock

import cv2
import numpy as np
import pytest

import main
import test_metric_regression_batch as regression

REPO_ROOT = Path(__file__).resolve().parent


def _v2_wrinkle_load(gray: np.ndarray, mask: np.ndarray) -> float:
    """The previous formula: raw-patch Canny (70, 140), edge share x 240."""
    edges = cv2.Canny(gray, 70, 140)
    share = np.count_nonzero((edges > 0) & (mask > 0)) / max(cv2.countNonZero(mask), 1)
    return share * 240.0


def _captured_wrinkle_inputs(normalized: np.ndarray, profile: dict):
    captured = {}
    real = main.compute_wrinkle_load

    def recording(gray, mask):
        captured["gray"], captured["mask"] = gray.copy(), mask.copy()
        return real(gray, mask)

    with mock.patch.object(main, "compute_wrinkle_load", recording):
        main.analyze_skin_patch(normalized, quality_profile=dict(profile))
    return captured["gray"], captured["mask"]


@pytest.fixture(scope="module")
def nikki3_inputs():
    manifest = json.loads(
        (REPO_ROOT / "test_fixtures/metric_regression/manifest.json").read_text()
    )
    case = next(c for c in manifest["cases"] if c["id"] == "nikki3")
    image_bytes = regression._prepare_image_bytes(
        REPO_ROOT / case["photo_path"], case["preprocess"]
    )
    normalized, profile = main.assess_and_normalize_image(image_bytes)
    blurred = cv2.GaussianBlur(normalized, (0, 0), 0.7)
    return (
        _captured_wrinkle_inputs(normalized, profile),
        _captured_wrinkle_inputs(blurred, profile),
    )


def test_version_and_constants():
    # v3 introduced the pre-smoothed Canny; v4 is the five-frame median.
    assert main._metric_formula_version("wrinkle_load") == 5
    assert main.WRINKLE_PRESMOOTH_SIGMA == 2.0
    assert (main.WRINKLE_CANNY_LOW, main.WRINKLE_CANNY_HIGH) == (20, 40)


def test_slight_blur_moves_v3_far_less_than_v2(nikki3_inputs):
    (gray, mask), (gray_blur, mask_blur) = nikki3_inputs
    v3_delta = abs(
        main.compute_wrinkle_load(gray_blur, mask_blur)
        - main.compute_wrinkle_load(gray, mask)
    )
    v2_delta = abs(_v2_wrinkle_load(gray_blur, mask_blur) - _v2_wrinkle_load(gray, mask))
    assert v2_delta > 10.0  # the instability v3 addresses
    assert v3_delta < 5.0
    assert v3_delta < v2_delta / 3.0


def test_real_lines_still_register():
    rng = np.random.default_rng(3)
    skin = np.clip(rng.normal(150, 4, (200, 200)), 0, 255).astype(np.uint8)
    lined = skin.copy()
    for y in range(30, 180, 30):
        cv2.line(lined, (20, y), (180, y + 4), 110, 2)
    mask = np.full((200, 200), 255, dtype=np.uint8)
    flat_score = main.compute_wrinkle_load(skin, mask)
    lined_score = main.compute_wrinkle_load(lined, mask)
    assert flat_score < 1.0
    assert lined_score > flat_score + 5.0
