#!/usr/bin/env python3
"""Batch check, part 2 of the resolution-normalization prototype: run the
20-photo calibration batch through the under_eye_dark_circle_density
pipeline with a given pre-landmark resize mode enabled, checking
specifically for NaN/crash/omitted-key issues. Does not touch main.py;
reuses the same harness as prototype_under_eye_resolution_normalization.py.

Usage:
    python tool/prototype_under_eye_batch_check.py [square|letterbox|letterbox_crop_back]
    (defaults to letterbox_crop_back — Stage 4: same letterbox+black
    detection canvas as Stage 3, but metrics run on the original,
    unpadded image via back-transformed landmark coordinates)
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import cv2

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

sys.path.insert(0, str(REPO_ROOT / "tool"))
from prototype_under_eye_resolution_normalization import _run_under_eye_pipeline  # noqa: E402

BATCH_DIR = REPO_ROOT / "calibration_stock_batch"


def main() -> None:
    normalize_mode = sys.argv[1] if len(sys.argv) > 1 else "letterbox_crop_back"
    if normalize_mode not in ("square", "letterbox", "letterbox_crop_back"):
        print("normalize_mode must be 'square', 'letterbox', or 'letterbox_crop_back'")
        sys.exit(1)

    photos = sorted(BATCH_DIR.glob("*.jpg"))
    if not photos:
        print(f"No photos found in {BATCH_DIR}")
        sys.exit(1)

    print(
        f"Running {len(photos)} calibration photos through the "
        f"{normalize_mode}-normalized pipeline...\n"
    )
    issues = []
    ok_count = 0
    for photo_path in photos:
        img = cv2.imread(str(photo_path))
        if img is None:
            issues.append((photo_path.name, "unreadable_file"))
            print(f"  {photo_path.name:35s} -> UNREADABLE FILE")
            continue
        try:
            result = _run_under_eye_pipeline(
                img, white_balance=False, normalize_mode=normalize_mode
            )
        except Exception as exc:  # noqa: BLE001
            issues.append((photo_path.name, f"crash: {exc}"))
            print(f"  {photo_path.name:35s} -> CRASH: {exc}")
            continue

        if "error" in result:
            issues.append((photo_path.name, result["error"]))
            print(f"  {photo_path.name:35s} -> ERROR: {result['error']}")
            continue

        score = result.get("score")
        raw_delta = result.get("raw_delta")
        if score is None or "under_eye_dark_circle_density" not in [
            "under_eye_dark_circle_density"
        ]:
            issues.append((photo_path.name, "missing_key"))
            print(f"  {photo_path.name:35s} -> MISSING KEY")
            continue
        if not math.isfinite(score) or not math.isfinite(raw_delta):
            issues.append((photo_path.name, f"non_finite score={score} raw_delta={raw_delta}"))
            print(f"  {photo_path.name:35s} -> NON-FINITE: score={score} raw_delta={raw_delta}")
            continue

        ok_count += 1
        print(f"  {photo_path.name:35s} -> OK  raw_delta={raw_delta:6.2f}  score={score:5.1f}")

    print(f"\n{ok_count}/{len(photos)} photos processed cleanly.")
    if issues:
        print(f"{len(issues)} issue(s) found:")
        for name, issue in issues:
            print(f"  - {name}: {issue}")
    else:
        print("No NaN/crash/omitted-key issues.")


if __name__ == "__main__":
    main()
