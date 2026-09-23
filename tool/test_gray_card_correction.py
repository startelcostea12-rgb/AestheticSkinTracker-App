"""Standalone diagnostic for the gray-card LAB calibration measurement.

Context: main.py's compute_gray_card_correction() is a pure measurement
function with only synthetic-array unit tests so far (see
test_gray_card_calibration.py). This tool runs it against a REAL decoded
photo, using a manually specified pixel rectangle for the card region (no
card-detection or face-detection involved), so its behavior can be
sanity-checked before it's wired into any API endpoint. There is currently
no "apply this correction to an image" function in main.py (the earlier
apply_gray_card_lab_correction was removed as unused/premature -- see git
history) -- this tool only exercises the measurement step.

CLI diagnostic only -- same category as tool/analyze_repeatability.py. Makes
no network calls, changes no API/UI code, and is not run automatically.

Usage:
    python tool/test_gray_card_correction.py PHOTO.jpg --card 40,40,60,60

    # Rectangle is "x,y,w,h" in pixel coordinates against the DECODED
    # image (post assess_and_normalize_image, i.e. after white-balance/CLAHE
    # normalization) -- open the photo in an image viewer with pixel
    # coordinates to find a suitable box over a visible gray/white card.

Output:
    1. The card region's raw mean LAB values and whether
       compute_gray_card_correction() accepts or rejects it (with reason).
    2. Confirmation that assess_and_normalize_image()'s quality_profile is
       identical whether or not compute_gray_card_correction() was called
       in between, run against this real photo rather than a synthetic array.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import main  # noqa: E402


def _parse_rect(value: str) -> tuple[int, int, int, int]:
    parts = value.split(",")
    if len(parts) != 4:
        raise argparse.ArgumentTypeError(
            f"Expected 'x,y,w,h' (4 comma-separated integers), got: {value!r}"
        )
    try:
        x, y, w, h = (int(p.strip()) for p in parts)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"Rectangle values must be integers: {value!r}") from exc
    if w <= 0 or h <= 0:
        raise argparse.ArgumentTypeError(f"Rectangle width/height must be positive: {value!r}")
    return x, y, w, h


def _crop(img_bgr: np.ndarray, rect: tuple[int, int, int, int], label: str) -> np.ndarray:
    x, y, w, h = rect
    height, width = img_bgr.shape[:2]
    if x < 0 or y < 0 or x + w > width or y + h > height:
        raise SystemExit(
            f"--{label} rectangle {rect} falls outside the decoded image "
            f"bounds ({width}x{height})."
        )
    return img_bgr[y : y + h, x : x + w]


def _mean_lab(region_bgr: np.ndarray) -> tuple[float, float, float]:
    lab = cv2.cvtColor(region_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    return (
        float(np.mean(lab[:, :, 0])),
        float(np.mean(lab[:, :, 1])),
        float(np.mean(lab[:, :, 2])),
    )


def main_cli() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("photo", type=Path, help="Path to a real photo to decode.")
    parser.add_argument(
        "--card",
        type=_parse_rect,
        required=True,
        metavar="x,y,w,h",
        help="Pixel rectangle marking the gray-card region.",
    )
    args = parser.parse_args()

    if not args.photo.exists():
        raise SystemExit(f"Photo not found: {args.photo}")
    image_bytes = args.photo.read_bytes()

    img_before, quality_profile_before = main.assess_and_normalize_image(image_bytes)

    card_region_bgr = _crop(img_before, args.card, "card")

    card_l, card_a, card_b = _mean_lab(card_region_bgr)
    print("=== Card region ===")
    print(f"rect={args.card} mean_lab=(L={card_l:.2f}, a={card_a:.2f}, b={card_b:.2f})")

    card_region_lab = cv2.cvtColor(card_region_bgr, cv2.COLOR_BGR2LAB)
    correction = main.compute_gray_card_correction(card_region_lab)
    if correction.get("accepted"):
        print(
            "ACCEPTED: "
            f"delta_a={correction['delta_a']:.3f} delta_b={correction['delta_b']:.3f} "
            f"l_gain={correction['l_gain']:.4f} (raw_l_gain={correction['raw_l_gain']:.4f})"
        )
    else:
        print(f"REJECTED: reason={correction['reason']} details={correction}")

    _img_after, quality_profile_after = main.assess_and_normalize_image(image_bytes)
    identical = quality_profile_before == quality_profile_after
    print()
    print("=== quality_profile invariant ===")
    print(f"identical whether or not correction ran: {identical}")
    if not identical:
        print(f"BEFORE={quality_profile_before}")
        print(f"AFTER={quality_profile_after}")


if __name__ == "__main__":
    main_cli()

