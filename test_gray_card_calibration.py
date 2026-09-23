import unittest

import cv2
import numpy as np

import main
from main import (
    GRAY_CARD_MAX_CHROMA_OFFSET,
    GRAY_CARD_MIN_REGION_PIXELS,
    GRAY_CARD_NEUTRAL_TARGET,
    compute_gray_card_correction,
)


def _synthetic_lab_region(l_value: float, a_value: float, b_value: float, size: int = 24) -> np.ndarray:
    """Builds a small synthetic LAB array (OpenCV's 0-255 encoding) filled
    with a single color, standing in for a user-marked card region without
    needing a real decoded photo.
    """
    region = np.zeros((size, size, 3), dtype=np.float32)
    region[:, :, 0] = l_value
    region[:, :, 1] = a_value
    region[:, :, 2] = b_value
    return region


class ComputeGrayCardCorrectionTests(unittest.TestCase):
    def test_genuinely_neutral_card_applies_small_correction(self) -> None:
        # Slightly warm cast (a/b a few units above neutral, L a touch below
        # the ideal 128 target) -- exactly what a real 18% gray card under
        # ordinary indoor light would measure.
        region = _synthetic_lab_region(l_value=122.0, a_value=131.0, b_value=133.0)

        correction = compute_gray_card_correction(region)

        self.assertTrue(correction["accepted"])
        self.assertAlmostEqual(correction["delta_a"], GRAY_CARD_NEUTRAL_TARGET - 131.0, places=2)
        self.assertAlmostEqual(correction["delta_b"], GRAY_CARD_NEUTRAL_TARGET - 133.0, places=2)
        # Small measured offset -> small, gentle correction, not a wild swing.
        self.assertLess(abs(correction["delta_a"]), 10.0)
        self.assertLess(abs(correction["delta_b"]), 10.0)
        self.assertAlmostEqual(correction["l_gain"], GRAY_CARD_NEUTRAL_TARGET / 122.0, places=3)
        self.assertLess(abs(correction["l_gain"] - 1.0), 0.25)

    def test_implausible_card_region_is_rejected_and_falls_back_to_uncalibrated(self) -> None:
        # Strongly saturated, skin-tone-like color -- far enough from
        # neutral that this almost certainly isn't a photographed gray card.
        region = _synthetic_lab_region(l_value=150.0, a_value=170.0, b_value=178.0)

        correction = compute_gray_card_correction(region)

        self.assertFalse(correction["accepted"])
        self.assertEqual(correction["reason"], "implausible_card_color")
        self.assertGreater(correction["chroma_offset"], GRAY_CARD_MAX_CHROMA_OFFSET)

    def test_too_dark_region_is_rejected(self) -> None:
        region = _synthetic_lab_region(l_value=5.0, a_value=128.0, b_value=128.0)

        correction = compute_gray_card_correction(region)

        self.assertFalse(correction["accepted"])
        self.assertEqual(correction["reason"], "implausible_exposure")

    def test_too_small_region_is_rejected(self) -> None:
        region = _synthetic_lab_region(l_value=128.0, a_value=128.0, b_value=128.0, size=5)
        self.assertLess(region.shape[0] * region.shape[1], GRAY_CARD_MIN_REGION_PIXELS)

        correction = compute_gray_card_correction(region)

        self.assertFalse(correction["accepted"])
        self.assertEqual(correction["reason"], "insufficient_region_pixels")

    def test_l_gain_is_clamped_for_extreme_but_accepted_exposure(self) -> None:
        # Measured L is inside the plausible-exposure bounds but still far
        # enough from the neutral target that the raw ratio would exceed the
        # gain clamp -- the gain must be capped, not left unbounded.
        region = _synthetic_lab_region(l_value=30.0, a_value=128.0, b_value=128.0)

        correction = compute_gray_card_correction(region)

        self.assertTrue(correction["accepted"])
        self.assertGreater(correction["raw_l_gain"], correction["l_gain"])
        self.assertLessEqual(correction["l_gain"], 2.0)


class QualityProfileUnaffectedByCalibrationTests(unittest.TestCase):
    def test_quality_profile_is_identical_whether_or_not_calibration_ran(self) -> None:
        synthetic_image = np.full((64, 64, 3), (90, 95, 100), dtype=np.uint8)
        ok, encoded = cv2.imencode(".png", synthetic_image)
        self.assertTrue(ok)
        image_bytes = encoded.tobytes()

        img_before, profile_before = main.assess_and_normalize_image(image_bytes)
        snapshot_before = img_before.copy()

        card_region_bgr = np.full((24, 24, 3), (200, 128, 128), dtype=np.uint8)
        card_region_lab = cv2.cvtColor(card_region_bgr, cv2.COLOR_BGR2LAB)
        compute_gray_card_correction(card_region_lab)

        # Re-running the IQA step on the same raw bytes must produce a
        # bit-for-bit identical quality_profile regardless of whether
        # gray-card calibration was invoked in between.
        img_after, profile_after = main.assess_and_normalize_image(image_bytes)

        self.assertEqual(profile_before, profile_after)
        # The array assess_and_normalize_image handed back must not have
        # been mutated in place by the correction call.
        self.assertTrue(np.array_equal(img_before, snapshot_before))


if __name__ == "__main__":
    unittest.main()
