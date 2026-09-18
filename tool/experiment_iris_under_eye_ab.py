"""Contained Iris-vs-contour under-eye ROI experiment.

This file intentionally does not modify main.py. It reuses the production
normalization, alignment, skin mask, cheek reference, and under-eye score
formula, while comparing the current contour ROI with an iris-anchored ROI.
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

import main

ROOT = Path(__file__).resolve().parents[1]
TARGET_SIZE = 1024
FACE = mp.solutions.face_mesh.FaceMesh


def _resize_variants(image: np.ndarray) -> list[tuple[str, np.ndarray]]:
    variants = [("native", image)]
    for size in (512, 1024):
        h, w = image.shape[:2]
        interpolation = cv2.INTER_AREA if size < max(h, w) else cv2.INTER_CUBIC
        variants.append((f"{size}x{size}", cv2.resize(image, (size, size), interpolation=interpolation)))
    return variants


def _points_from_landmarks(face_landmarks, shape: tuple[int, int]) -> np.ndarray:
    h, w = shape
    return np.array([[p.x * w, p.y * h] for p in face_landmarks.landmark], dtype=np.float32)


def _detect_points(detector: object, image: np.ndarray) -> np.ndarray | None:
    rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    result = detector.process(rgb)
    if not result.multi_face_landmarks:
        return None
    return _points_from_landmarks(result.multi_face_landmarks[0], image.shape[:2])


def _contour_under_eye(shape, points: np.ndarray, skin_mask: np.ndarray, side: str) -> np.ndarray:
    if side == "left":
        ids = [33, 133, 155, 154, 153, 145, 144, 163, 7]
    else:
        ids = [362, 263, 382, 381, 380, 374, 373, 390, 249]
    eye_poly = points[ids]
    center = np.mean(eye_poly, axis=0)
    expanded = eye_poly + ((eye_poly - center) * 0.12)
    expanded[:, 1] += shape[0] * 0.028
    mask = main._polygon_mask(shape, expanded)
    return cv2.bitwise_and(mask, skin_mask)


def _iris_under_eye(shape, points: np.ndarray, skin_mask: np.ndarray, side: str) -> np.ndarray:
    # MediaPipe refined FaceMesh iris topology: 468..472 and 473..477.
    ids = range(468, 473) if side == "left" else range(473, 478)
    iris = points[list(ids)]
    center = iris.mean(axis=0)
    radius = max(float(np.mean(np.linalg.norm(iris - center, axis=1))), 1.0)
    # Anchor below the observed iris, with axes scaled by the iris radius.
    # The scale is deliberately fixed for this experiment so only landmark
    # source/geometry changes between the two paths.
    ellipse_center = (int(round(center[0])), int(round(center[1] + 2.2 * radius)))
    axes = (max(2, int(round(2.8 * radius))), max(2, int(round(1.6 * radius))))
    mask = np.zeros(shape, dtype=np.uint8)
    cv2.ellipse(mask, ellipse_center, axes, 0.0, 0.0, 360.0, 255, -1)
    return cv2.bitwise_and(mask, skin_mask)


def _score_under_eye(norm: np.ndarray, skin_mask: np.ndarray, points: np.ndarray, geometry: str) -> dict[str, float | int]:
    shape = norm.shape[:2]
    left = (
        _contour_under_eye(shape, points, skin_mask, "left")
        if geometry == "contour"
        else _iris_under_eye(shape, points, skin_mask, "left")
    )
    right = (
        _contour_under_eye(shape, points, skin_mask, "right")
        if geometry == "contour"
        else _iris_under_eye(shape, points, skin_mask, "right")
    )
    peri = cv2.bitwise_or(left, right) > 0
    lab = cv2.cvtColor(norm, cv2.COLOR_BGR2LAB)
    l_channel = lab[:, :, 0].astype(np.float32)
    cheek_regions = main._region_masks(shape, skin_mask, points)
    cheeks = cv2.bitwise_or(
        cheek_regions.get("left_cheek", np.zeros(shape, dtype=np.uint8)),
        cheek_regions.get("right_cheek", np.zeros(shape, dtype=np.uint8)),
    ) > 0
    cheek_l = float(np.mean(l_channel[cheeks])) if np.any(cheeks) else 150.0
    peri_l = float(np.mean(l_channel[peri])) if np.any(peri) else 150.0
    raw_delta = max(0.0, cheek_l - peri_l)
    return {
        "raw_delta": round(raw_delta, 4),
        "score": round(float(main.compute_under_eye_dark_circle_density(raw_delta)), 4),
        "roi_pixels": int(peri.sum()),
    }


def _run(image: np.ndarray, geometry: str, refine: bool) -> dict[str, object]:
    calibrated, _ = main.apply_white_balance_calibration(image)
    detector = FACE(static_image_mode=True, max_num_faces=1, refine_landmarks=refine, min_detection_confidence=0.5)
    try:
        points = _detect_points(detector, calibrated)
        if points is None:
            return {"error": "pass1_no_face"}
        aligned, _ = main._align_and_crop_face(calibrated, points)
        norm = main.normalize_lighting_and_shadows(aligned)
        skin = main._skin_mask(norm)
        norm_points = _detect_points(detector, norm)
        if norm_points is None:
            return {"error": "pass2_no_face"}
        if refine and len(norm_points) < 478:
            return {"error": f"expected_478_landmarks_got_{len(norm_points)}"}
        return _score_under_eye(norm, skin, norm_points, geometry)
    finally:
        detector.close()


def main_cli() -> None:
    paths = [
        ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif",
        ROOT / "test_fixtures" / "metric_regression" / "nikki2.jpg",
        ROOT / "test_fixtures" / "metric_regression" / "nikki3.jpg",
        ROOT / "test_fixtures" / "metric_regression" / "st1.jpg",
    ]
    report: dict[str, object] = {}
    for path in paths:
        image = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if image is None:
            report[path.name] = {"error": "unreadable"}
            continue
        rows = []
        for resolution, variant in _resize_variants(image):
            contour = _run(variant, "contour", refine=False)
            iris_contour = _run(variant, "contour", refine=True)
            iris = _run(variant, "iris", refine=True)
            rows.append({
                "resolution": resolution,
                "production_contour_468": contour,
                "refined_contour_478": iris_contour,
                "iris_anchored_478": iris,
            })
        report[path.name] = rows
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main_cli()
