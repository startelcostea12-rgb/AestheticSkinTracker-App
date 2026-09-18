from __future__ import annotations

import cv2
import numpy as np
import pytest

import main


@pytest.mark.parametrize(
    ("photo", "expected"),
    [
        ("candidate_body_4.jpg", "reasonable"),
        ("candidate_body_5.jpg", "reasonable"),
        ("candidate_body_6.jpg", "reasonable"),
        ("stock_body_photo_b.jpg", "partial"),
        ("candidate_body_3.jpg", "partial"),
        ("candidate_body_7.jpg", None),
        ("stock_body_photo_a.jpg", None),
    ],
)
def test_yunet_fallback_tiers_match_real_evidence_photos(photo: str, expected: str | None) -> None:
    image = cv2.imread(photo, cv2.IMREAD_COLOR)
    assert image is not None, f"missing fixture photo: {photo}"
    assert main._detect_yunet_face_outline(image) == expected


def test_yunet_reasonable_outline_changes_only_failure_message(monkeypatch: pytest.MonkeyPatch) -> None:
    image = np.zeros((120, 120, 3), dtype=np.uint8)
    monkeypatch.setattr(main, "ensure_pipeline_ready", lambda: {"status": "ready"})
    monkeypatch.setattr(main, "_extract_primary_landmarks", lambda rgb: (None, 0, "mesh"))
    monkeypatch.setattr(main, "_detect_yunet_face_outline", lambda bgr: "reasonable")

    def fail_if_metrics_run(*args, **kwargs):
        raise AssertionError("YuNet fallback must not feed metric extraction")

    monkeypatch.setattr(main, "_align_and_crop_face", fail_if_metrics_run)

    with pytest.raises(RuntimeError, match="detected a face outline") as exc:
        main.analyze_skin_patch(image)

    assert str(exc.value) == main.YUNET_PRECISE_LANDMARKS_MESSAGE


def test_yunet_partial_outline_changes_only_failure_message(monkeypatch: pytest.MonkeyPatch) -> None:
    image = np.zeros((120, 120, 3), dtype=np.uint8)
    monkeypatch.setattr(main, "ensure_pipeline_ready", lambda: {"status": "ready"})
    monkeypatch.setattr(main, "_extract_primary_landmarks", lambda rgb: (None, 0, "mesh"))
    monkeypatch.setattr(main, "_detect_yunet_face_outline", lambda bgr: "partial")

    with pytest.raises(RuntimeError) as exc:
        main.analyze_skin_patch(image)

    assert str(exc.value) == main.YUNET_PARTIAL_FACE_MESSAGE


def test_yunet_no_detection_keeps_original_no_face_failure(monkeypatch: pytest.MonkeyPatch) -> None:
    image = np.zeros((120, 120, 3), dtype=np.uint8)
    monkeypatch.setattr(main, "ensure_pipeline_ready", lambda: {"status": "ready"})
    monkeypatch.setattr(main, "_extract_primary_landmarks", lambda rgb: (None, 0, "mesh"))
    monkeypatch.setattr(main, "_detect_yunet_face_outline", lambda bgr: None)

    with pytest.raises(RuntimeError) as exc:
        main.analyze_skin_patch(image)

    assert str(exc.value) == (
        "No face detected by MediaPipe Face Mesh. "
        "Please avoid camera monitor reflection or glare noise."
    )
