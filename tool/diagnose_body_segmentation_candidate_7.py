from __future__ import annotations

import json
import os
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import vision as mp_vision
from mediapipe.tasks import python as mp_python

import main

ROOT = Path(__file__).resolve().parents[1]
PHOTO = ROOT / "candidate_body_7.jpg"
OUT = ROOT / "diagnostics" / "candidate_body_7_segmentation"
OUT.mkdir(parents=True, exist_ok=True)


def save_model_outputs() -> dict[str, object]:
    bgr = cv2.imread(str(PHOTO), cv2.IMREAD_COLOR)
    if bgr is None:
        raise RuntimeError(f"Could not decode {PHOTO}")
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)

    legacy = mp.solutions.selfie_segmentation.SelfieSegmentation(model_selection=1)
    legacy_result = legacy.process(rgb)
    legacy_conf = legacy_result.segmentation_mask.astype(np.float32)
    legacy.close()

    custom_options = mp_vision.ImageSegmenterOptions(
        base_options=mp_python.BaseOptions(
            model_asset_buffer=(ROOT / "backend" / "models" / "selfie_segmenter.tflite").read_bytes(),
        ),
        running_mode=mp_vision.RunningMode.IMAGE,
        output_confidence_masks=True,
        output_category_mask=False,
    )
    custom = mp_vision.ImageSegmenter.create_from_options(custom_options)
    custom_result = custom.segment(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
    if not custom_result.confidence_masks:
        raise RuntimeError("Custom segmenter returned no confidence mask")
    custom_conf = custom_result.confidence_masks[0].numpy_view().astype(np.float32)
    custom.close()

    if legacy_conf.shape != custom_conf.shape:
        custom_conf = cv2.resize(custom_conf, (legacy_conf.shape[1], legacy_conf.shape[0]), interpolation=cv2.INTER_LINEAR)

    legacy_mask = legacy_conf > 0.5
    custom_mask = custom_conf > 0.5
    disagreement = legacy_mask != custom_mask

    def stats(conf: np.ndarray, mask: np.ndarray) -> dict[str, object]:
        values = conf.reshape(-1)
        return {
            "shape": list(conf.shape),
            "min": float(values.min()),
            "max": float(values.max()),
            "mean": float(values.mean()),
            "p01": float(np.percentile(values, 1)),
            "p05": float(np.percentile(values, 5)),
            "p25": float(np.percentile(values, 25)),
            "p50": float(np.percentile(values, 50)),
            "p75": float(np.percentile(values, 75)),
            "p95": float(np.percentile(values, 95)),
            "p99": float(np.percentile(values, 99)),
            "positive_pixels_at_0_5": int(mask.sum()),
            "positive_fraction_at_0_5": float(mask.mean()),
            "near_threshold_0_4_0_6_fraction": float(((conf >= 0.4) & (conf <= 0.6)).mean()),
        }

    def overlay(conf: np.ndarray, mask: np.ndarray, color: tuple[int, int, int], name: str) -> None:
        normalized = np.clip(conf * 255.0, 0, 255).astype(np.uint8)
        cv2.imwrite(str(OUT / f"{name}_confidence_grayscale.png"), normalized)
        result = bgr.copy()
        tint = np.zeros_like(result)
        tint[mask] = color
        result = cv2.addWeighted(result, 0.62, tint, 0.38, 0)
        contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cv2.drawContours(result, contours, -1, color, 2)
        cv2.imwrite(str(OUT / f"{name}_overlay.png"), result)

    overlay(legacy_conf, legacy_mask, (0, 0, 255), "legacy_model_selection_1")
    overlay(custom_conf, custom_mask, (0, 255, 0), "custom_bundled")
    difference = np.zeros_like(bgr)
    difference[legacy_mask & ~custom_mask] = (0, 0, 255)
    difference[custom_mask & ~legacy_mask] = (0, 255, 0)
    difference[legacy_mask & custom_mask] = (255, 255, 255)
    cv2.imwrite(str(OUT / "mask_difference_red_legacy_green_custom.png"), difference)
    cv2.imwrite(str(OUT / "original.png"), bgr)

    report = {
        "photo": str(PHOTO),
        "output_dir": str(OUT),
        "legacy_model_selection_1": stats(legacy_conf, legacy_mask),
        "custom_bundled_model": stats(custom_conf, custom_mask),
        "pixel_disagreement": {
            "count": int(disagreement.sum()),
            "fraction": float(disagreement.mean()),
            "legacy_only_count": int((legacy_mask & ~custom_mask).sum()),
            "custom_only_count": int((custom_mask & ~legacy_mask).sum()),
            "both_positive_count": int((legacy_mask & custom_mask).sum()),
            "both_negative_count": int((~legacy_mask & ~custom_mask).sum()),
            "mean_absolute_confidence_difference": float(np.abs(legacy_conf - custom_conf).mean()),
            "p95_absolute_confidence_difference": float(np.percentile(np.abs(legacy_conf - custom_conf), 95)),
        },
    }
    (OUT / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    return report


if __name__ == "__main__":
    save_model_outputs()
