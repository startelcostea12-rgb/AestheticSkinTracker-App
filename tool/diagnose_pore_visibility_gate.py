"""Read-only diagnostic: reproduces the REAL pore_visibility pipeline
(the same code path analyze_skin_patch uses) against real reference
photos, and reports the exact gate values instead of guessing.

This does not modify any production formula; it only calls main.py's
existing helper functions in the same order analyze_skin_patch does.
"""
from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np

import main

ROOT = Path(__file__).resolve().parents[1]

PHOTOS = [
    ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif",
    ROOT / "test_fixtures" / "metric_regression" / "nikki2.jpg",
    ROOT / "test_fixtures" / "metric_regression" / "nikki3.jpg",
    ROOT / "test_fixtures" / "metric_regression" / "st1.jpg",
    *sorted((ROOT / "calibration_stock_batch").glob("*.jpg")),
]


def run_one(path: Path) -> dict:
    image_bytes = path.read_bytes()
    try:
        normalized_bgr, quality_profile = main.assess_and_normalize_image(image_bytes)
    except Exception as exc:  # noqa: BLE001
        return {"photo": path.name, "error": f"normalize_failed: {exc}"}

    rgb = cv2.cvtColor(normalized_bgr, cv2.COLOR_BGR2RGB)
    primary_landmarks, primary_count, primary_source = main._extract_primary_landmarks(rgb)
    if primary_landmarks is None:
        return {"photo": path.name, "error": "no_face_pass1"}

    points = main._landmarks_to_points(primary_landmarks, normalized_bgr.shape[1], normalized_bgr.shape[0])
    aligned_face, _ = main._align_and_crop_face(normalized_bgr, points)
    norm = main.normalize_lighting_and_shadows(aligned_face)
    mask = main._skin_mask(norm)

    norm_rgb = cv2.cvtColor(norm, cv2.COLOR_BGR2RGB)
    norm_landmarks, norm_count, norm_source = main._extract_primary_landmarks(norm_rgb)
    if norm_landmarks is None:
        return {"photo": path.name, "error": "no_face_pass2"}

    norm_points = main._landmarks_to_points(norm_landmarks, norm.shape[1], norm.shape[0])
    regions = main._region_masks(norm.shape[:2], mask, norm_points)

    matrix, confidence, raw_components = main._compute_canonical_patch_metrics(
        norm,
        mask,
        regions,
        norm_points,
        yolo_kept=0,
        yolo_max_conf=0.0,
    )

    return {
        "photo": path.name,
        "norm_shape": list(norm.shape[:2]),
        "pose_pitch": raw_components.get("pore_pose_pitch"),
        "pose_yaw": raw_components.get("pore_pose_yaw"),
        "pose_ok": abs(raw_components.get("pore_pose_pitch", 999.0)) <= 20.0
        and abs(raw_components.get("pore_pose_yaw", 999.0)) <= 18.0,
        "pore_roi_pixels": raw_components.get("pores_roi_pixels"),
        "primary_pore_roi_pixels": raw_components.get("primary_pore_roi_pixels"),
        "fallback_pore_roi_pixels": raw_components.get("fallback_pore_roi_pixels"),
        "pore_fallback_used": bool(raw_components.get("pore_fallback_used", 0.0) > 0.5),
        "pore_hf_energy": raw_components.get("pore_hf_energy"),
        "pore_spread": raw_components.get("pore_spread"),
        "pore_confidence": confidence.get("pore_visibility"),
        "pore_visibility_value": matrix.get("pore_visibility"),
    }


def main_cli() -> None:
    main.ensure_pipeline_ready()
    results = [run_one(p) for p in PHOTOS if p.is_file()]
    print(json.dumps(results, indent=2, sort_keys=True))


if __name__ == "__main__":
    main_cli()
