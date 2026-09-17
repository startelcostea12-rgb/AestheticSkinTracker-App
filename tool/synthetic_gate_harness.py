#!/usr/bin/env python3
"""Synthetic gate robustness harness for /api/skin/analyze-single.

This harness intentionally stresses only the honesty gates (blur, darkness, and
capture_quality labeling) while keeping the face framed in a valid camera QA
range. It is not meant to calibrate redness or pigment severity scores.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any, Iterable

import cv2
import numpy as np
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import main

BASE_CANDIDATES = [
    Path("tmp_lena.jpg"),
    Path("tmp_obama.jpg"),
    Path("tmp_biden.jpg"),
]


def _load_image(path: Path) -> np.ndarray:
    image = cv2.imread(str(path))
    if image is None:
        raise RuntimeError(f"Failed to read image: {path}")
    return image


def _encode_jpeg(image: np.ndarray) -> bytes:
    ok, encoded = cv2.imencode(".jpg", image)
    if not ok:
        raise RuntimeError("OpenCV JPG encoding failed")
    return encoded.tobytes()


def _fake_face_landmarks(width: int, height: int, *, face_w: float = 560.0, face_h: float = 700.0) -> Any:
    cx = width * 0.5
    cy = height * 0.5
    a = face_w / 2.0
    b = face_h / 2.0
    points = []
    for i in range(468):
        theta = (2.0 * 3.141592653589793 * i) / 468.0
        x = cx + a * __import__("math").cos(theta)
        y = cy + b * __import__("math").sin(theta) * 0.92
        points.append(type("LM", (), {"x": float(x / max(width, 1)), "y": float(y / max(height, 1))})())
    return type("FaceLandmarks", (), {"landmark": points})()


def _as_valid_face_frame(base: np.ndarray, *, target_size: tuple[int, int] = (1400, 1200)) -> np.ndarray:
    target_w, target_h = target_size
    canvas = np.full((target_h, target_w, 3), 200, dtype=np.uint8)
    center = (target_w // 2, target_h // 2)
    face = np.zeros((target_h, target_w, 3), dtype=np.uint8)
    cv2.ellipse(face, center, (290, 340), 0, 0, 360, (135, 130, 125), -1)
    cv2.ellipse(face, (center[0], center[1] - 20), (150, 120), 0, 0, 360, (190, 175, 165), -1)
    cv2.circle(face, (center[0] - 75, center[1] - 35), 18, (70, 60, 55), -1)
    cv2.circle(face, (center[0] + 75, center[1] - 35), 18, (70, 60, 55), -1)
    cv2.rectangle(face, (center[0] - 110, center[1] + 80), (center[0] + 110, center[1] + 230), (80, 70, 60), -1)
    canvas = cv2.addWeighted(canvas, 1.0, face, 1.0, 0.0)
    return canvas


def _apply_gaussian_blur(image: np.ndarray, sigma: float) -> np.ndarray:
    k = max(3, int(round(sigma * 6)))
    if k % 2 == 0:
        k += 1
    return cv2.GaussianBlur(image, (k, k), sigmaX=sigma, sigmaY=sigma)


def _apply_tint(image: np.ndarray, *, warm: bool, strength: float) -> np.ndarray:
    out = image.astype(np.float32).copy()
    amount = float(strength)
    if warm:
        out[:, :, 2] = np.clip(out[:, :, 2] + (60.0 * amount), 0, 255)
        out[:, :, 1] = np.clip(out[:, :, 1] + (18.0 * amount), 0, 255)
        out[:, :, 0] = np.clip(out[:, :, 0] - (10.0 * amount), 0, 255)
    else:
        out[:, :, 0] = np.clip(out[:, :, 0] + (60.0 * amount), 0, 255)
        out[:, :, 1] = np.clip(out[:, :, 1] + (12.0 * amount), 0, 255)
        out[:, :, 2] = np.clip(out[:, :, 2] - (18.0 * amount), 0, 255)
    return np.clip(out, 0, 255).astype(np.uint8)


def _apply_low_light(image: np.ndarray, brightness_scale: float, contrast_scale: float) -> np.ndarray:
    img = image.astype(np.float32)
    img = img * brightness_scale
    img = (img - 128.0) * contrast_scale + 128.0
    return np.clip(img, 0, 255).astype(np.uint8)


def _variation_set_for(base: np.ndarray) -> list[dict[str, Any]]:
    variations: list[dict[str, Any]] = []

    variations.append({
        "name": "baseline_normal",
        "image": base.copy(),
        "expected_tag": "normal",
        "expected_blur": False,
        "expected_dark": False,
        "expected_cast": False,
    })

    for sigma, label in [(4.0, "mild"), (9.0, "moderate"), (16.0, "severe")]:
        variations.append({
            "name": f"blur_{label}",
            "image": _apply_gaussian_blur(base.copy(), sigma),
            "expected_tag": "blurry",
            "expected_blur": True,
            "expected_dark": False,
            "expected_cast": False,
        })

    for amount, label in [(0.35, "mild"), (0.70, "moderate"), (1.10, "strong")]:
        variations.append({
            "name": f"warm_tint_{label}",
            "image": _apply_tint(base.copy(), warm=True, strength=amount),
            "expected_tag": "normal",
            "expected_blur": False,
            "expected_dark": False,
            "expected_cast": True,
        })
        variations.append({
            "name": f"cool_tint_{label}",
            "image": _apply_tint(base.copy(), warm=False, strength=amount),
            "expected_tag": "normal",
            "expected_blur": False,
            "expected_dark": False,
            "expected_cast": True,
        })

    for scale, label in [(0.60, "mild"), (0.48, "moderate"), (0.32, "severe")]:
        variations.append({
            "name": f"low_light_{label}",
            "image": _apply_low_light(base.copy(), scale, 0.95),
            "expected_tag": "low_light",
            "expected_blur": False,
            "expected_dark": True,
            "expected_cast": False,
        })
        variations.append({
            "name": f"low_light_contrast_{label}",
            "image": _apply_low_light(base.copy(), 0.90, 0.55 + (0.75 - scale) * 0.40),
            "expected_tag": "low_light",
            "expected_blur": False,
            "expected_dark": True,
            "expected_cast": False,
        })

    variations.append({
        "name": "blur_plus_low_light",
        "image": _apply_low_light(_apply_gaussian_blur(base.copy(), 9.0), 0.52, 0.80),
        "expected_tag": "blurry",
        "expected_blur": True,
        "expected_dark": True,
        "expected_cast": False,
    })
    variations.append({
        "name": "blur_plus_warm_tint",
        "image": _apply_tint(_apply_gaussian_blur(base.copy(), 9.0), warm=True, strength=0.85),
        "expected_tag": "blurry",
        "expected_blur": True,
        "expected_dark": False,
        "expected_cast": True,
    })
    variations.append({
        "name": "low_light_plus_cool_tint",
        "image": _apply_tint(_apply_low_light(base.copy(), 0.42, 0.78), warm=False, strength=0.7),
        "expected_tag": "low_light",
        "expected_blur": False,
        "expected_dark": True,
        "expected_cast": True,
    })
    return variations


def _evaluate_response(payload: dict[str, Any], expected_tag: str, expected_blur: bool, expected_dark: bool, expected_cast: bool) -> dict[str, Any]:
    image_quality = payload.get("image_quality") or {}
    capture_quality = str(payload.get("capture_quality") or "unknown").strip().lower()
    actual_blur = bool(image_quality.get("image_blurry", False))
    actual_dark = float(image_quality.get("lighting_mean_l", 255.0)) < 80.0 or float(image_quality.get("lighting_balance_score", 1.0)) < 0.45
    actual_cast = float(image_quality.get("chroma_cast", 0.0)) > 20.0
    warnings = image_quality.get("preprocess_warnings", []) or []
    tag_ok = capture_quality == expected_tag or (expected_tag == "normal" and capture_quality in {"normal", "unknown"})
    blur_ok = actual_blur == expected_blur
    dark_ok = actual_dark == expected_dark
    cast_ok = actual_cast == expected_cast
    overall_ok = tag_ok and blur_ok and dark_ok and cast_ok

    return {
        "capture_quality": capture_quality,
        "expected_capture_quality": expected_tag,
        "actual_blur": actual_blur,
        "expected_blur": expected_blur,
        "actual_dark": actual_dark,
        "expected_dark": expected_dark,
        "actual_cast": actual_cast,
        "expected_cast": expected_cast,
        "blur_match": blur_ok,
        "dark_match": dark_ok,
        "cast_match": cast_ok,
        "capture_match": tag_ok,
        "overall_pass": overall_ok,
        "mean_l": image_quality.get("lighting_mean_l"),
        "lighting_balance_score": image_quality.get("lighting_balance_score"),
        "blur_score": image_quality.get("blur_score"),
        "chroma_cast": image_quality.get("chroma_cast"),
        "warnings": warnings,
    }


def _run_case(base_path: Path, variation: dict[str, Any]) -> dict[str, Any]:
    client = TestClient(main.app)
    image_bytes = _encode_jpeg(variation["image"])
    response = client.post(
        "/api/skin/analyze-single",
        files={"image": (base_path.name, image_bytes, "image/jpeg")},
        data={"capture_quality": variation["expected_tag"]},
    )
    payload = response.json()
    result = {
        "base_path": str(base_path),
        "variation": variation["name"],
        "status_code": response.status_code,
        "expected_tag": variation["expected_tag"],
        "expected_blur": variation["expected_blur"],
        "expected_dark": variation["expected_dark"],
        "expected_cast": variation["expected_cast"],
    }
    if response.status_code != 200:
        result["failure_detail"] = payload.get("detail") or payload
        result["overall_pass"] = False
        return result

    result.update(_evaluate_response(payload, variation["expected_tag"], variation["expected_blur"], variation["expected_dark"], variation["expected_cast"]))
    return result


def _summarize_results(rows: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for row in rows:
        if row.get("status_code") != 200:
            out.append({
                "variation": row["variation"],
                "expected": f"tag={row.get('expected_tag')}; blur={row.get('expected_blur')}; dark={row.get('expected_dark')}; cast={row.get('expected_cast')}",
                "actual": row.get("failure_detail") or "request_failed",
                "pass": False,
            })
            continue
        out.append({
            "variation": row["variation"],
            "expected": f"tag={row['expected_tag']}; blur={row['expected_blur']}; dark={row['expected_dark']}; cast={row['expected_cast']}",
            "actual": (
                f"tag={row['capture_quality']}; blur={row['actual_blur']}; dark={row['actual_dark']}; cast={row['actual_cast']}"
                f"; mean_l={row.get('mean_l')}"
            ),
            "pass": bool(row.get("overall_pass")),
        })
    return out


def main_cli() -> int:
    print("Synthetic gate harness: blur, lighting, and capture_quality checks")
    print("Note: this validates gate robustness only, not metric severity accuracy.")
    print()

    original_landmarks_fn = main._extract_primary_landmarks
    def _stubbed_landmarks(rgb_image: np.ndarray):
        return _fake_face_landmarks(rgb_image.shape[1], rgb_image.shape[0]), 468, "synthetic"
    main._extract_primary_landmarks = _stubbed_landmarks
    try:
        rows: list[dict[str, Any]] = []
        for baseline_path in BASE_CANDIDATES:
            if not baseline_path.exists():
                print(f"Skipping missing baseline: {baseline_path}")
                continue
            base_image = _load_image(baseline_path)
            framed = _as_valid_face_frame(base_image)
            for variation in _variation_set_for(framed):
                rows.append(_run_case(baseline_path, variation))

        summary = _summarize_results(rows)
        print("VARIATION | EXPECTED | ACTUAL | PASS")
        for item in summary:
            print(f"{item['variation']} | {item['expected']} | {item['actual']} | {'PASS' if item['pass'] else 'FAIL'}")
        print()
        pass_count = sum(1 for item in summary if item["pass"])
        print(f"TOTAL_CASES={len(summary)} PASS_COUNT={pass_count} FAIL_COUNT={len(summary)-pass_count}")
        if pass_count != len(summary):
            failed = [item for item in summary if not item["pass"]]
            print("FAILED_CASES=")
            for row in failed:
                print(f"  - {row['variation']} :: {row['expected']} :: {row['actual']}")
            return 1
        return 0
    finally:
        main._extract_primary_landmarks = original_landmarks_fn

    summary = _summarize_results(rows)
    print("VARIATION | EXPECTED | ACTUAL | PASS")
    for item in summary:
        print(f"{item['variation']} | {item['expected']} | {item['actual']} | {'PASS' if item['pass'] else 'FAIL'}")
    print()
    pass_count = sum(1 for item in summary if item["pass"])
    print(f"TOTAL_CASES={len(summary)} PASS_COUNT={pass_count} FAIL_COUNT={len(summary)-pass_count}")
    if pass_count != len(summary):
        failed = [item for item in summary if not item["pass"]]
        print("FAILED_CASES=")
        for row in failed:
            print(f"  - {row['variation']} :: {row['expected']} :: {row['actual']}")
        return 1
    return 0


if __name__ == "__main__":
    os.environ.setdefault("IQA_BLUR_THRESHOLD", "80.0")
    raise SystemExit(main_cli())
