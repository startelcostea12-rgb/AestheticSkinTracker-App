import cv2
import numpy as np

from main import _compute_zone_analysis


def test_zone_analysis_emits_only_supported_valid_roi_combinations() -> None:
    image = np.zeros((120, 120, 3), dtype=np.uint8)
    image[:, :, 0] = 120
    image[:, :, 1] = 135
    image[:, :, 2] = 150
    skin = np.full((120, 120), 255, dtype=np.uint8)
    regions = {
        "forehead": np.pad(
            np.ones((45, 80), dtype=np.uint8) * 255,
            ((5, 70), (20, 20)),
        ),
        "left_cheek": np.pad(
            np.ones((50, 45), dtype=np.uint8) * 255,
            ((50, 20), (5, 70)),
        ),
        "right_cheek": np.pad(
            np.ones((50, 45), dtype=np.uint8) * 255,
            ((50, 20), (70, 5)),
        ),
        "nose": np.pad(
            np.ones((30, 20), dtype=np.uint8) * 255,
            ((45, 45), (50, 50)),
        ),
    }

    result = _compute_zone_analysis(image, skin, regions, min_pixels=100)

    assert set(result) == {"forehead", "left_cheek", "right_cheek", "nose"}
    assert "localized_redness" in result["nose"]["metrics"]
    assert "texture_smoothness" in result["forehead"]["metrics"]
    assert "pigment_load" in result["left_cheek"]["metrics"]
    assert result["left_cheek"]["crop"]["coordinate_space"] == "normalized_face"


def test_zone_analysis_omits_insufficient_fallback_roi() -> None:
    image = np.zeros((120, 120, 3), dtype=np.uint8)
    skin = np.full((120, 120), 255, dtype=np.uint8)
    tiny = np.zeros((120, 120), dtype=np.uint8)
    tiny[10:15, 10:15] = 255

    result = _compute_zone_analysis(
        image,
        skin,
        {"forehead": tiny, "left_cheek": tiny},
        min_pixels=100,
    )

    assert result == {}
