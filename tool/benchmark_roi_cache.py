import argparse
import json
import time
from pathlib import Path

import cv2

REPO_ROOT = Path(__file__).resolve().parents[1]
import sys
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import main


def _run_case(label: str, use_cache: bool):
    counts = {"pore": 0, "tzone": 0}
    orig_pore = main._build_pore_roi_masks
    orig_tzone = main._build_tzone_roi
    orig_cache_cls = main._RequestRoiCache

    def count_pore(shape, points, face_bgr, skin_mask):
        counts["pore"] += 1
        return orig_pore(shape, points, face_bgr, skin_mask)

    def count_tzone(shape, points, forehead_mask, skin_mask, face_skin_mask):
        counts["tzone"] += 1
        return orig_tzone(shape, points, forehead_mask, skin_mask, face_skin_mask)

    main._build_pore_roi_masks = count_pore
    main._build_tzone_roi = count_tzone

    if use_cache:
        main._RequestRoiCache = orig_cache_cls
    else:
        class NoCache:
            def get_pore_mask(self, shape, points, face_bgr, skin_mask):
                return count_pore(shape, points, face_bgr, skin_mask)

            def get_tzone_mask(self, shape, points, forehead_mask, skin_mask, face_skin_mask):
                return count_tzone(shape, points, forehead_mask, skin_mask, face_skin_mask)

        main._RequestRoiCache = NoCache

    start = time.perf_counter()
    result = main.analyze_skin_patch(img)
    elapsed = time.perf_counter() - start

    main._build_pore_roi_masks = orig_pore
    main._build_tzone_roi = orig_tzone
    main._RequestRoiCache = orig_cache_cls

    return {
        "label": label,
        "elapsed_s": round(elapsed, 4),
        "status": result.get("status", "ok"),
        "pore_calls": counts["pore"],
        "tzone_calls": counts["tzone"],
    }


def main_cli():
    parser = argparse.ArgumentParser(description="Benchmark ROI cache vs no-cache request path")
    parser.add_argument("--image", type=Path, default=Path("tmp_lena.jpg"))
    args = parser.parse_args()

    global img
    img = cv2.imread(str(args.image))
    if img is None:
        raise SystemExit(f"Image not found: {args.image}")

    before = _run_case("before_cache", use_cache=False)
    after = _run_case("after_cache", use_cache=True)
    print(json.dumps({"before": before, "after": after}, indent=2))


if __name__ == "__main__":
    main_cli()
