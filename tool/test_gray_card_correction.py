"""Standalone diagnostic for the gray-card LAB calibration correction.

Context: main.py's compute_gray_card_correction()/apply_gray_card_lab_correction()
are pure functions with only synthetic-array unit tests so far (see
test_gray_card_calibration.py). This tool runs them against a REAL decoded
photo, using manually specified pixel rectangles for the card and skin
regions (no card-detection or face-detection involved), so their behavior
can be sanity-checked before either is wired into any API endpoint.

CLI diagnostic only -- same category as tool/analyze_repeatability.py. Makes
no network calls, changes no API/UI code, and is not run automatically.

Usage:
    python tool/test_gray_card_correction.py PHOTO.jpg \
        --card 40,40,60,60 --skin 200,150,120,120

    # Rectangles are "x,y,w,h" in pixel coordinates against the DECODED
    # image (post assess_and_normalize_image, i.e. after white-balance/CLAHE
    # normalization but before any gray-card correction) -- open the photo
    # in an image viewer with pixel coordinates to find suitable boxes, e.g.
    # a visible gray/white card corner for --card, and a patch of cheek/
    # forehead skin for --skin.

Output:
    1. The card region's raw mean LAB values and whether
       compute_gray_card_correction() accepts or rejects it (with reason).
    2. If accepted: the skin region's mean LAB and a self-referencing
       redness signal (95th-minus-10th-percentile LAB a*, matching main.py's
       "self_cheek_p10" fallback -- see ROSACEA_CALIB in main.py) and the
       resulting localized_redness score, both before and after correction.
       localized_redness here uses diffuse_density=0.0 as a simplification:
       a plain rectangle has no face-zone mask to derive the real diffuse-
       flushing density from, so only the primary a*-spread term is
       exercised, not the full production diffuse-flushing pipeline.
    3. Confirmation that assess_and_normalize_image()'s quality_profile is
       identical whether or not apply_gray_card_lab_correction() was called
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


def _redness_signal_and_score(region_bgr: np.ndarray) -> tuple[float, float]:
    """Self-referencing p95-minus-p10 a* spread (mirrors main.py's
    "self_cheek_p10" fallback), plus the resulting localized_redness score
    with diffuse_density=0.0 (see module docstring for why).
    """
    lab = cv2.cvtColor(region_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    a_values = lab[:, :, 1]
    redness_signal = float(np.percentile(a_values, 95)) - float(np.percentile(a_values, 10))
    result = main.compute_localized_redness_and_rosacea(redness_signal, 0.0, 0.0)
    return redness_signal, float(result["localized_redness"])


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
    parser.add_argument(
        "--skin",
        type=_parse_rect,
        required=True,
        metavar="x,y,w,h",
        help="Pixel rectangle marking a skin region to compare before/after correction.",
    )
    args = parser.parse_args()

    if not args.photo.exists():
        raise SystemExit(f"Photo not found: {args.photo}")
    image_bytes = args.photo.read_bytes()

    img_before, quality_profile_before = main.assess_and_normalize_image(image_bytes)

    card_region_bgr = _crop(img_before, args.card, "card")
    skin_region_bgr = _crop(img_before, args.skin, "skin")

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

    print()
    print("=== Skin region (before correction) ===")
    skin_l, skin_a, skin_b = _mean_lab(skin_region_bgr)
    signal_before, redness_before = _redness_signal_and_score(skin_region_bgr)
    print(f"rect={args.skin} mean_lab=(L={skin_l:.2f}, a={skin_a:.2f}, b={skin_b:.2f})")
    print(f"redness_signal(p95-p10 a*)={signal_before:.2f} localized_redness={redness_before:.1f}")

    corrected_img, applied_correction = main.apply_gray_card_lab_correction(img_before, card_region_bgr)

    if correction.get("accepted"):
        print()
        print("=== Skin region (after correction) ===")
        corrected_skin_region_bgr = _crop(corrected_img, args.skin, "skin")
        skin_l_after, skin_a_after, skin_b_after = _mean_lab(corrected_skin_region_bgr)
        signal_after, redness_after = _redness_signal_and_score(corrected_skin_region_bgr)
        print(
            f"rect={args.skin} mean_lab=(L={skin_l_after:.2f}, a={skin_a_after:.2f}, "
            f"b={skin_b_after:.2f})"
        )
        print(f"redness_signal(p95-p10 a*)={signal_after:.2f} localized_redness={redness_after:.1f}")
        print()
        print(
            f"redness_signal delta: {signal_after - signal_before:+.2f} "
            f"localized_redness delta: {redness_after - redness_before:+.1f}"
        )
    else:
        print()
        print("Skipping before/after skin comparison: card region was rejected.")

    img_after, quality_profile_after = main.assess_and_normalize_image(image_bytes)
    identical = quality_profile_before == quality_profile_after
    print()
    print("=== quality_profile invariant ===")
    print(f"identical whether or not correction ran: {identical}")
    if not identical:
        print(f"BEFORE={quality_profile_before}")
        print(f"AFTER={quality_profile_after}")


if __name__ == "__main__":
    main_cli()
