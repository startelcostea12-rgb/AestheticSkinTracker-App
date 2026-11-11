"""Shared crop-sharpness measure and floor used for image_blurry.

The Flutter app's imageSharpnessVarianceFromBytes (4-neighbour Laplacian
variance over every 2nd pixel, clamped 0-5000, floor 36) is the only
measure that decides whether a frame is too blurry to keep. The historical
cv2 ksize=3 blur_score / IQA_BLUR_THRESHOLD=80 scale is a different unit
and must not decide image_blurry.
"""

from __future__ import annotations

import math

import cv2
import numpy as np

import main


def _reference_variance(image_bgr: np.ndarray) -> float:
    """Pixel-loop copy of the Dart imageSharpnessVarianceFromBytes body."""
    if image_bgr is None or image_bgr.size == 0:
        return 0.0
    if image_bgr.ndim == 3:
        gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    else:
        gray = image_bgr
    height, width = gray.shape[:2]
    if width < 6 or height < 6:
        return 0.0
    step = 2
    count = 0
    total = 0.0
    sum_sq = 0.0
    for y in range(1, height - 1, step):
        for x in range(1, width - 1, step):
            center = float(gray[y, x])
            left = float(gray[y, x - 1])
            right = float(gray[y, x + 1])
            up = float(gray[y - 1, x])
            down = float(gray[y + 1, x])
            lap = (4.0 * center) - left - right - up - down
            total += lap
            sum_sq += lap * lap
            count += 1
    if count == 0:
        return 0.0
    mean = total / count
    variance = (sum_sq / count) - (mean * mean)
    if not math.isfinite(variance):
        return 0.0
    return float(min(max(variance, 0.0), 5000.0))


def _sharp_checkerboard(size: int = 96) -> np.ndarray:
    image = np.zeros((size, size, 3), dtype=np.uint8)
    for y in range(size):
        for x in range(size):
            value = 135 if ((x // 4) + (y // 4)) % 2 == 0 else 110
            image[y, x] = (value, value, value)
    return image


def _soft_noise(size: int = 96, seed: int = 7) -> np.ndarray:
    rng = np.random.default_rng(seed)
    base = np.full((size, size), 120, dtype=np.int16)
    noise = rng.integers(-1, 2, size=(size, size), dtype=np.int16)
    gray = np.clip(base + noise, 0, 255).astype(np.uint8)
    return cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)


def test_crop_sharpness_floor_is_the_agreed_36():
    assert main.CROP_SHARPNESS_FLOOR == 36.0


def test_vectorized_measure_matches_the_dart_pixel_loop():
    for image in (_sharp_checkerboard(), _soft_noise(), _sharp_checkerboard(97)):
        actual = main.image_sharpness_variance(image)
        expected = _reference_variance(image)
        assert actual == expected
        assert 0.0 <= actual <= 5000.0


def test_tiny_or_empty_images_score_zero():
    assert main.image_sharpness_variance(np.zeros((4, 4, 3), dtype=np.uint8)) == 0.0
    assert main.image_sharpness_variance(np.zeros((0, 0, 3), dtype=np.uint8)) == 0.0


def test_image_blurry_follows_crop_sharpness_not_the_old_threshold(monkeypatch):
    # Even if the historical env threshold is 80, a crop above 36 must
    # not be flagged blurry, and a crop below 36 must be flagged.
    monkeypatch.setenv("IQA_BLUR_THRESHOLD", "80.0")

    sharp = _sharp_checkerboard()
    soft = _soft_noise()
    _, sharp_quality = main.assess_and_normalize_image(_encode(sharp))
    _, soft_quality = main.assess_and_normalize_image(_encode(soft))

    assert sharp_quality["sharpness_floor"] == 36.0
    assert soft_quality["sharpness_floor"] == 36.0
    assert sharp_quality["crop_sharpness"] >= 36.0
    assert 0 < soft_quality["crop_sharpness"] < 36.0
    assert sharp_quality["image_blurry"] is False
    assert soft_quality["image_blurry"] is True
    # Historical score is still present for other gates, but it is not
    # what image_blurry used.
    assert "blur_score" in sharp_quality
    assert sharp_quality["blur_threshold"] == 80.0
    assert sharp_quality["image_blurry"] == (
        sharp_quality["crop_sharpness"] < main.CROP_SHARPNESS_FLOOR
    )
    assert soft_quality["image_blurry"] == (
        soft_quality["crop_sharpness"] < main.CROP_SHARPNESS_FLOOR
    )


def _encode(image_bgr: np.ndarray) -> bytes:
    ok, encoded = cv2.imencode(".png", image_bgr)
    assert ok
    return encoded.tobytes()
