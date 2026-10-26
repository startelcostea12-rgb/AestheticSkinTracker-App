"""Gray-card guard: a sampled card is used only when it reads within 12
a*/b* units of neutral AND within 12 units of the scene's own automatic
neutral estimate. Otherwise the card is ignored and the automatic white
balance runs exactly as it does without a card. Skin caught by the fixed
under-chin box (a* ~ +16-17) must never drive the correction."""
from __future__ import annotations

import logging

import cv2
import numpy as np
import pytest

import main

SIZE = 200
CARD = (slice(10, 50), slice(10, 50))
CARD_REGION = {"x": 10 / SIZE, "y": 10 / SIZE, "w": 40 / SIZE, "h": 40 / SIZE}


def _png(image: np.ndarray) -> bytes:
    ok, encoded = cv2.imencode(".png", image)
    assert ok
    return encoded.tobytes()


def _scene(scene_ab, card_ab) -> np.ndarray:
    """A gray scene with an a*/b* cast of scene_ab (signed, from 128) and a
    card patch reading card_ab, built in LAB so the offsets are exact."""
    rng = np.random.default_rng(11)
    lab = np.empty((SIZE, SIZE, 3), dtype=np.float64)
    lab[:, :, 0] = rng.normal(150, 4, (SIZE, SIZE))
    lab[:, :, 1] = 128 + scene_ab[0] + rng.normal(0, 0.6, (SIZE, SIZE))
    lab[:, :, 2] = 128 + scene_ab[1] + rng.normal(0, 0.6, (SIZE, SIZE))
    lab[CARD] = (145, 128 + card_ab[0], 128 + card_ab[1])
    return cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)


def _run(image: np.ndarray, region=CARD_REGION):
    return main._assess_and_normalize_image_with_pre_white_balance(_png(image), region)


def test_limits_are_12():
    assert main.GRAY_CARD_MAX_CHROMA_OFFSET == 12.0
    assert main.GRAY_CARD_MAX_SCENE_DISAGREEMENT == 12.0


def test_skin_in_the_box_is_rejected_by_the_offset_limit(caplog):
    # The measured under-chin samples: a* ~ +16.5, b* ~ +10 (offset ~19).
    caplog.set_level(logging.INFO, logger=main.logger.name)
    image = _scene((0, 0), (16.5, 10))
    plain, _, _ = main._assess_and_normalize_image_with_pre_white_balance(_png(image))
    normalized, profile, _ = _run(image)

    assert np.array_equal(normalized, plain)
    assert profile["white_balance_profile"]["method"] == "linear_srgb_low_chroma_reference"
    assert profile["gray_card_marked"] is True
    assert profile["gray_card_correction_applied"] is False
    assert profile["gray_card_reason"] == "implausible_card_color"
    assert profile["gray_card_chroma_offset"] > 12
    assert any(
        "GRAY_CARD sample accepted=False reason=implausible_card_color" in r.getMessage()
        for r in caplog.records
    )


def test_offset_just_inside_the_old_45_limit_is_now_rejected():
    lab = np.full((40, 40, 3), (145, 128 + 20, 128 + 20), dtype=np.uint8)
    check = main.compute_gray_card_correction(lab)
    assert check["accepted"] is False
    assert check["reason"] == "implausible_card_color"


def test_card_disagreeing_with_the_scene_falls_back_to_automatic(caplog):
    # Card offset ~8.5 passes the 12 limit, but the scene reads cool
    # (b* -6), so card and scene are ~14 apart: not the same light.
    caplog.set_level(logging.INFO, logger=main.logger.name)
    image = _scene((0, -6), (3, 8))
    plain, plain_profile, _ = main._assess_and_normalize_image_with_pre_white_balance(
        _png(image)
    )
    normalized, profile, _ = _run(image)

    assert np.array_equal(normalized, plain)
    wb = profile["white_balance_profile"]
    assert wb["method"] == "linear_srgb_low_chroma_reference"
    assert wb["a_adjustment"] == plain_profile["white_balance_profile"]["a_adjustment"]
    assert wb["b_adjustment"] == plain_profile["white_balance_profile"]["b_adjustment"]
    assert profile["gray_card_marked"] is True
    assert profile["gray_card_correction_applied"] is False
    assert profile["gray_card_reason"] == "disagrees_with_scene"
    assert profile["gray_card_chroma_offset"] < 12
    assert profile["gray_card_scene_disagreement"] > 12
    messages = [r.getMessage() for r in caplog.records]
    assert any("GRAY_CARD rejected reason=disagrees_with_scene" in m for m in messages)
    assert not any("GRAY_CARD accepted" in m for m in messages)


def test_card_agreeing_with_the_scene_is_applied(caplog):
    # Warm scene and a card under the same warm light.
    caplog.set_level(logging.INFO, logger=main.logger.name)
    image = _scene((4, 7), (5, 8))
    normalized, profile, _ = _run(image)

    card = cv2.cvtColor(normalized[CARD], cv2.COLOR_BGR2LAB).reshape(-1, 3).mean(axis=0)
    assert abs(card[1] - 128) < 1.5 and abs(card[2] - 128) < 1.5
    assert profile["white_balance_profile"]["method"] == "linear_srgb_gray_card_reference"
    assert profile["gray_card_correction_applied"] is True
    assert profile["gray_card_reason"] is None
    assert profile["gray_card_scene_disagreement"] < 12
    messages = [r.getMessage() for r in caplog.records]
    assert any("GRAY_CARD sample accepted=True" in m and "chroma_offset=" in m for m in messages)
    assert any("GRAY_CARD accepted" in m for m in messages)


def test_no_card_reports_no_card_fields():
    image = _scene((0, 0), (0, 0))
    _, profile, _ = main._assess_and_normalize_image_with_pre_white_balance(_png(image))
    assert profile["gray_card_marked"] is False
    assert profile["gray_card_chroma_offset"] is None
    assert profile["gray_card_scene_disagreement"] is None
    assert "gray_card_rejected_reason" not in profile["white_balance_profile"]


@pytest.mark.parametrize("scene_ab", [(0, 0), (3, 6), (-4, -5)])
def test_automatic_path_is_unchanged_without_a_card(scene_ab):
    image = _scene(scene_ab, scene_ab)
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    neutral = main._automatic_neutral_estimate(lab)
    _, wb = main._apply_capture_white_balance_correction(image)
    assert neutral["available"] is True
    assert wb["a_adjustment"] == round(float(np.clip(neutral["a_offset"] * 0.70, -8, 8)), 3)
    assert wb["b_adjustment"] == round(float(np.clip(neutral["b_offset"] * 0.70, -8, 8)), 3)
