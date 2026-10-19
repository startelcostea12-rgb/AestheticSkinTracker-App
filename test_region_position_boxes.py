"""Region-position logging for region_position_mismatch: every scan logs the
wrinkle region, pore-contraction ROI and both under-eye bands as boxes in
face-width units. Logging only -- metric values are unchanged."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

import main
import test_metric_regression_batch as regression

REPO_ROOT = Path(__file__).resolve().parent


@pytest.fixture(scope="module")
def nikki3_quality():
    main.ensure_pipeline_ready()
    manifest = json.loads(
        (REPO_ROOT / "test_fixtures/metric_regression/manifest.json").read_text()
    )
    case = next(c for c in manifest["cases"] if c["id"] == "nikki3")
    data = regression._prepare_image_bytes(REPO_ROOT / case["photo_path"], case["preprocess"])
    normalized, profile = main.assess_and_normalize_image(data)
    return main.analyze_skin_patch(normalized, quality_profile=profile)["image_quality"]


def test_every_region_box_is_logged(nikki3_quality):
    for prefix in main.REGION_POSITION_BOX_PREFIXES:
        for field in ("cx", "cy", "w", "h"):
            value = nikki3_quality.get(f"{prefix}_box_{field}")
            assert isinstance(value, float), f"{prefix}_box_{field}"
            assert 0.0 <= value <= 2.0, f"{prefix}_box_{field}={value}"


def test_boxes_sit_where_the_regions_are(nikki3_quality):
    q = nikki3_quality
    # Under-eye bands: left of centre / right of centre, below the forehead.
    assert q["under_eye_left_box_cx"] < 0.5 < q["under_eye_right_box_cx"]
    assert q["wrinkle_region_box_cy"] < q["under_eye_left_box_cy"]


def test_box_helper_units():
    points = np.array([[100.0, 50.0], [300.0, 50.0], [100.0, 350.0], [300.0, 350.0]])
    mask = np.zeros((400, 400), dtype=np.uint8)
    mask[100:150, 150:250] = 255  # 100 wide, 50 tall
    box = main._mask_box_in_face_units(mask, points)
    # Face width 200 px; box centre (200, 125) -> (0.5, 0.375) face widths.
    assert box == {"cx": 0.5, "cy": 0.375, "w": 0.5, "h": 0.25}
    assert main._mask_box_in_face_units(np.zeros((10, 10), np.uint8), points) is None
