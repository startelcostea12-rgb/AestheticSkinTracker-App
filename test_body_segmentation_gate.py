import numpy as np

from main import _body_segmentation_quality_gate


def _inputs(*, coverage: float, center_x: float, uncertainty: float):
    mask = np.zeros((100, 100), dtype=np.uint8)
    width = int(round(coverage * 100))
    left = int(round(center_x * 100 - width / 2))
    left = max(0, min(100 - width, left))
    mask[:, left : left + width] = 1
    confidence = np.full((100, 100), 0.9, dtype=np.float32)
    uncertain_count = int(round(uncertainty * confidence.size))
    confidence.reshape(-1)[:uncertain_count] = 0.5
    return mask, confidence


def test_plausible_centered_body_mask_passes():
    mask, confidence = _inputs(coverage=0.60, center_x=0.50, uncertainty=0.01)

    passed, reason, stats = _body_segmentation_quality_gate(
        mask,
        confidence,
        (0, 0, 100, 100),
    )

    assert passed is True
    assert reason == ""
    assert stats["roi_coverage"] == 0.60


def test_high_uncertainty_rejects_before_score_emission():
    mask, confidence = _inputs(coverage=0.60, center_x=0.50, uncertainty=0.11)

    passed, reason, _ = _body_segmentation_quality_gate(
        mask,
        confidence,
        (0, 0, 100, 100),
    )

    assert passed is False
    assert "confidence was ambiguous" in reason


def test_sparse_off_center_mask_rejects_hard_negative_shape():
    mask, confidence = _inputs(coverage=0.38, center_x=0.70, uncertainty=0.01)

    passed, reason, stats = _body_segmentation_quality_gate(
        mask,
        confidence,
        (0, 0, 100, 100),
    )

    assert passed is False
    assert "plausible body region" in reason
    assert "not centered" in reason
    assert stats["foreground_center_x"] > 0.65
