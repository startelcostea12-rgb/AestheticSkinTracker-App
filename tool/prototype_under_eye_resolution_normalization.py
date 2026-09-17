#!/usr/bin/env python3
"""STAGE 1 prototype: does normalizing input resolution BEFORE MediaPipe
face-landmark detection reduce under_eye_dark_circle_density's sensitivity
to input image resolution?

This is a standalone experiment, not a change to the production pipeline.
main.py's analyze_skin_patch() is NOT modified — landmark detection there
is a single call shared by every zone metric (localized_redness,
pigment_load, texture_smoothness, sebum_excess_oil_gloss, etc. all consume
the same aligned/normalized face patch and landmark points from one call
to _extract_primary_landmarks). There is no per-metric landmark stage to
scope a resize into, so "touch only under_eye_dark_circle_density's
pipeline stage" is not something that exists as a separate code path in
analyze_skin_patch today. This script instead re-runs the real,
unmodified pipeline HELPER functions (imported from main.py, not
reimplemented) in an isolated harness, with exactly one new step inserted
before landmark detection. Only under_eye_dark_circle_density's numbers
are reported; the other zone metrics get computed as an unavoidable
side effect of calling the real _compute_zone_based_metrics, but are not
touched, reported, or used to judge anything here.

Usage:
    python tool/prototype_under_eye_resolution_normalization.py <image_path>
"""

from __future__ import annotations

import contextlib
import sys
from pathlib import Path

import cv2
import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import main  # noqa: E402

NORMALIZE_TARGET_SIZE = 1024  # matches the largest size in the sweep


@contextlib.contextmanager
def _temporarily_widen_roi_expansion(extra_scale: float):
    """STAGE 5 experiment: monkeypatches main.py's ROI-expansion helpers for
    the duration of this context, composing `extra_scale` on top of
    whatever radial-expansion scale each call site already ships with
    (0.12 for cheeks via _expanded_polygon_points, 0.12 inlined in
    _under_eye_region_mask). Composed multiplicatively —
    (1+base)*(1+extra)-1 — so extra_scale=0.05 means "5% more expansion
    than what's already there," matching how the stage was framed
    ("beyond the landmark-defined boundary" the shipped code already
    produces), not "5% total."

    Patches main.py's module-level names directly rather than
    reimplementing _region_masks' cheek logic (asymmetric-cheek salvage,
    skin-mask-assist, adaptive re-dilation tiers — main.py ~1218-1370):
    that logic is intricate enough that a hand-copied version here risks
    silently diverging from the real behavior. Patching the shared
    low-level helper means the REAL _region_masks (with every real
    fallback tier intact) runs unchanged — it just starts from a wider
    polygon. Restores the originals on exit; nothing here touches main.py
    on disk, only this process's already-imported module object, only
    for the duration of one _run_under_eye_pipeline call.

    extra_scale=0.0 is a no-op (composed scale equals the shipped
    default), used as the "un-widened baseline" comparison point.
    """
    original_expand = main._expanded_polygon_points
    original_under_eye = main._under_eye_region_mask

    def patched_expand(polygon, shape, *, scale=0.12):
        composed = (1.0 + scale) * (1.0 + extra_scale) - 1.0
        return original_expand(polygon, shape, scale=composed)

    def patched_under_eye(shape, points, skin_mask, *, side):
        if side == "left":
            ids = [33, 133, 155, 154, 153, 145, 144, 163, 7]
        else:
            ids = [362, 263, 382, 381, 380, 374, 373, 390, 249]
        valid_ids = [idx for idx in ids if 0 <= idx < points.shape[0]]
        if len(valid_ids) < 3:
            return np.zeros(shape, dtype=np.uint8)
        eye_poly = points[valid_ids]
        composed = (1.0 + 0.12) * (1.0 + extra_scale) - 1.0
        expanded = original_expand(eye_poly, shape, scale=composed)
        expanded[:, 1] = expanded[:, 1] + (shape[0] * 0.028)
        mask = main._polygon_mask(shape, expanded)
        return cv2.bitwise_and(mask, skin_mask)

    main._expanded_polygon_points = patched_expand
    main._under_eye_region_mask = patched_under_eye
    try:
        yield
    finally:
        main._expanded_polygon_points = original_expand
        main._under_eye_region_mask = original_under_eye


def _resize_to_square_forced(image_bgr: np.ndarray, size: int) -> np.ndarray:
    """STAGE 1's resize: non-uniformly stretches/squashes the image to force
    it square. Kept only for direct before/after comparison against the
    Stage 2 letterbox fix below — no longer used as the default normalize
    path. This is what broke face detection on
    portrait_17_woman_older.jpg (1798x1200 native) in Stage 1: its ~1.5:1
    aspect ratio got squashed into 1:1, distorting the face enough that
    MediaPipe couldn't detect it anymore.
    """
    h, w = image_bgr.shape[:2]
    interp = cv2.INTER_AREA if size < max(h, w) else cv2.INTER_CUBIC
    return cv2.resize(image_bgr, (size, size), interpolation=interp)


def _letterbox_transform_params(h: int, w: int, size: int) -> tuple[float, int, int, int, int]:
    """Returns (scale, left_pad, top_pad, new_w, new_h) for the letterbox
    transform _resize_to_letterbox applies to an h x w image targeting a
    size x size canvas. Factored out so both the forward resize and the
    Stage 4 inverse landmark-mapping use the exact same arithmetic instead
    of two copies that could drift out of sync.
    """
    scale = size / max(h, w)
    new_h, new_w = max(1, round(h * scale)), max(1, round(w * scale))
    pad_h, pad_w = size - new_h, size - new_w
    top, left = pad_h // 2, pad_w // 2
    return scale, left, top, new_w, new_h


def _resize_to_letterbox(
    image_bgr: np.ndarray, size: int, pad_mode: int = cv2.BORDER_CONSTANT
) -> np.ndarray:
    """STAGE 2 fix, STAGE 3 padding-mode correction: aspect-preserving
    resize. Scales the image so its LONGEST dimension reaches `size`, then
    symmetrically pads the shorter dimension to reach a size x size square
    canvas — no non-uniform stretching.

    Defaults to flat BLACK padding (BORDER_CONSTANT, value=0), not
    BORDER_REPLICATE as originally reasoned in Stage 2. That original
    reasoning ("a smooth edge-extension avoids a sharp artificial edge")
    turned out to be backwards in practice: BORDER_REPLICATE stretches a
    single edge COLUMN sideways, and when that column itself spans a
    bright-to-dark transition (e.g. background into hair), the result is a
    wide block of high-contrast horizontal stripes sitting directly next
    to the face — confirmed (Stage 2 investigation) to be exactly what
    broke face detection on portrait_08_woman_hair.jpg under replicate
    padding. Flat black has zero variance regardless of what the source
    edge column contains, so it can't manufacture that spurious structure.

    STAGE 3 also found that padding content still perturbs the *detected
    landmark coordinates* even for faces nowhere near the padding boundary
    (full-canvas inference isn't purely local) — which is why this
    function is now used for DETECTION ONLY (see "letterbox_crop_back"
    mode in _run_under_eye_pipeline below); metric computation runs on the
    original, unpadded image via _map_points_padded_to_original.
    """
    h, w = image_bgr.shape[:2]
    scale, left, top, new_w, new_h = _letterbox_transform_params(h, w, size)
    interp = cv2.INTER_AREA if scale < 1.0 else cv2.INTER_CUBIC
    resized = cv2.resize(image_bgr, (new_w, new_h), interpolation=interp)

    pad_h, pad_w = size - new_h, size - new_w
    bottom, right = pad_h - top, pad_w - left
    return cv2.copyMakeBorder(
        resized, top, bottom, left, right, pad_mode, value=(0, 0, 0)
    )


def _map_points_padded_to_original(
    padded_points: np.ndarray,
    scale: float,
    left: int,
    top: int,
    orig_w: int,
    orig_h: int,
) -> np.ndarray:
    """STAGE 4: inverts the letterbox transform on already-detected landmark
    points -- maps (x, y) pixel coordinates from the padded detection
    canvas back to the original, unpadded image's coordinate space. Pure
    arithmetic (undo the pad offset, then the scale); no image pixels are
    touched by this function at all, which is the whole point -- padding
    pixels only ever influence the detection step, never anything the
    metric math averages over.

    Clamped to the original image's bounds as a safety net for the edge
    case where MediaPipe places a landmark inside the padding region
    itself (a detection artifact, not something this transform should
    silently produce out-of-bounds coordinates for downstream code).
    """
    mapped = padded_points.astype(np.float64).copy()
    mapped[:, 0] = (mapped[:, 0] - left) / scale
    mapped[:, 1] = (mapped[:, 1] - top) / scale
    mapped[:, 0] = np.clip(mapped[:, 0], 0, max(orig_w - 1, 0))
    mapped[:, 1] = np.clip(mapped[:, 1], 0, max(orig_h - 1, 0))
    return mapped.astype(np.float32)


def _run_under_eye_pipeline(
    image_bgr: np.ndarray,
    *,
    white_balance: bool,
    normalize_mode: str | None = None,  # None | "square" | "letterbox" | "letterbox_crop_back"
    pad_mode: int = cv2.BORDER_CONSTANT,
    roi_extra_scale: float = 0.0,
) -> dict:
    """Re-runs the real analyze_skin_patch pipeline stages for one image,
    up through under_eye_dark_circle_density, using main.py's own
    unmodified helper functions. The only new logic here is the resize
    gated by normalize_mode, inserted immediately before the first
    landmark-detection call — mirrors exactly where the equivalent call
    sits in analyze_skin_patch (main.py line ~4452-4453).

    normalize_mode="letterbox_crop_back" is STAGE 4: landmark detection
    still runs on the padded canvas (necessary — MediaPipe needs a
    consistent input size, and letterbox is what fixed Stage 1's aspect
    distortion), but the detected points are mapped back to the original,
    unpadded image's coordinate space immediately afterward, and every
    metric-computation step from _align_and_crop_face onward runs on the
    ORIGINAL image. Padding pixels never enter any pixel average.
    "square" and "letterbox" (Stage 1-3) are unchanged: metrics still run
    on the resized/padded canvas, kept only for comparison.
    """
    main.ensure_pipeline_ready()

    if white_balance:
        calibrated_image, _ = main.apply_white_balance_calibration(image_bgr)
    else:
        calibrated_image = image_bgr

    # detection_image: what gets fed to the first landmark-detection call.
    # metrics_base_image: what _align_and_crop_face (and everything after
    # it) actually runs on. These are the same array for every mode except
    # letterbox_crop_back, which is the whole point of Stage 4.
    detection_image = calibrated_image
    metrics_base_image = calibrated_image

    if normalize_mode == "square":
        detection_image = _resize_to_square_forced(calibrated_image, NORMALIZE_TARGET_SIZE)
        metrics_base_image = detection_image
    elif normalize_mode == "letterbox":
        detection_image = _resize_to_letterbox(calibrated_image, NORMALIZE_TARGET_SIZE, pad_mode=pad_mode)
        metrics_base_image = detection_image
    elif normalize_mode == "letterbox_crop_back":
        detection_image = _resize_to_letterbox(calibrated_image, NORMALIZE_TARGET_SIZE, pad_mode=pad_mode)
        metrics_base_image = calibrated_image  # original, unpadded

    rgb = cv2.cvtColor(detection_image, cv2.COLOR_BGR2RGB)
    primary_landmarks, _, _ = main._extract_primary_landmarks(rgb)
    if primary_landmarks is None:
        return {"error": "no_face_detected_pass1"}

    if normalize_mode == "letterbox_crop_back":
        h0, w0 = calibrated_image.shape[:2]
        scale, left, top, _, _ = _letterbox_transform_params(h0, w0, NORMALIZE_TARGET_SIZE)
        padded_points = main._landmarks_to_points(
            primary_landmarks, NORMALIZE_TARGET_SIZE, NORMALIZE_TARGET_SIZE
        )
        points = _map_points_padded_to_original(padded_points, scale, left, top, w0, h0)
    else:
        points = main._landmarks_to_points(
            primary_landmarks, detection_image.shape[1], detection_image.shape[0]
        )

    aligned_face, aligned_points = main._align_and_crop_face(metrics_base_image, points)
    norm = main.normalize_lighting_and_shadows(aligned_face)
    mask = main._skin_mask(norm)

    norm_rgb = cv2.cvtColor(norm, cv2.COLOR_BGR2RGB)
    norm_landmarks, _, _ = main._extract_primary_landmarks(norm_rgb)
    if norm_landmarks is None:
        return {"error": "no_face_detected_pass2"}
    norm_points = main._landmarks_to_points(norm_landmarks, norm.shape[1], norm.shape[0])

    # STAGE 5: everything from here down (cheek + under-eye ROI masks, and
    # the metric math that averages over them) runs with the ROI-expansion
    # helpers widened by roi_extra_scale. roi_extra_scale=0.0 reproduces
    # exactly the shipped behavior (a no-op patch).
    with _temporarily_widen_roi_expansion(roi_extra_scale):
        regions = main._region_masks(norm.shape[:2], mask, norm_points)

        zone_metrics = main._compute_zone_based_metrics(
            norm, mask, regions, norm_points, roi_cache=main._RequestRoiCache()
        )

        # Recompute raw_delta/effective_delta directly (not returned by
        # _compute_zone_based_metrics) using the exact same real helpers, so
        # we can report the pre-rounding values the way the
        # UNDER_EYE_DARK_CIRCLE log line in main.py does.
        h, w = norm.shape[:2]
        left_under_eye = main._under_eye_region_mask((h, w), norm_points, mask, side="left")
        right_under_eye = main._under_eye_region_mask((h, w), norm_points, mask, side="right")
        peri_pixels = cv2.bitwise_or(left_under_eye, right_under_eye) > 0
        left_cheek = regions.get("left_cheek", np.zeros((h, w), dtype=np.uint8))
        right_cheek = regions.get("right_cheek", np.zeros((h, w), dtype=np.uint8))
        cheek_mask = cv2.bitwise_or(left_cheek, right_cheek) > 0
        lab = cv2.cvtColor(norm, cv2.COLOR_BGR2LAB)
        l_channel = lab[:, :, 0].astype(np.float32)
        cheek_l_mean = float(np.mean(l_channel[cheek_mask])) if np.any(cheek_mask) else 150.0
        peri_l_mean = float(np.mean(l_channel[peri_pixels])) if np.any(peri_pixels) else 150.0
        raw_delta = max(0.0, cheek_l_mean - peri_l_mean)

    return {
        "raw_delta": round(raw_delta, 2),
        "score": zone_metrics.get("under_eye_dark_circle_density"),
        "input_shape": tuple(image_bgr.shape),
        "detection_shape": tuple(detection_image.shape),
        "metrics_base_shape": tuple(metrics_base_image.shape),
    }


def main_cli() -> None:
    if len(sys.argv) < 2:
        print("Usage: python tool/prototype_under_eye_resolution_normalization.py <image_path>")
        sys.exit(1)

    image_path = sys.argv[1]
    original = cv2.imread(image_path)
    if original is None:
        print(f"Could not read image: {image_path}")
        sys.exit(1)

    print(f"Source image: {image_path}  native_shape={original.shape}")

    sizes: list[tuple[str, np.ndarray]] = [("native", original)]
    for s in (512, 1024):
        h, w = original.shape[:2]
        interp = cv2.INTER_AREA if s < max(h, w) else cv2.INTER_CUBIC
        sizes.append((f"{s}x{s}", cv2.resize(original, (s, s), interpolation=interp)))

    for normalize_label, normalize_mode in [
        ("BEFORE (no normalization)", None),
        ("STAGE 1 (forced-square resize pre-landmark)", "square"),
        ("STAGE 3 (letterbox + black padding, metrics on padded canvas)", "letterbox"),
        ("STAGE 4 (letterbox + black padding, metrics on ORIGINAL image)", "letterbox_crop_back"),
    ]:
        print(f"\n=== {normalize_label} ===")
        results = []
        for size_label, img in sizes:
            for wb_label, wb_flag in [("wb_off", False), ("wb_on", True)]:
                result = _run_under_eye_pipeline(
                    img, white_balance=wb_flag, normalize_mode=normalize_mode
                )
                results.append((size_label, wb_label, result))
                if "error" in result:
                    print(f"  input={size_label:9s} {wb_label:6s} -> ERROR: {result['error']}")
                else:
                    print(
                        f"  input={size_label:9s} {wb_label:6s} -> "
                        f"raw_delta={result['raw_delta']:.2f}  score={result['score']:.1f}"
                    )
        scores = [r["score"] for _, _, r in results if "score" in r]
        if scores:
            print(
                f"  spread across {len(scores)} combos: "
                f"min={min(scores):.1f} max={max(scores):.1f} range={max(scores) - min(scores):.1f}"
            )
        else:
            print("  no successful combos (all errored)")


if __name__ == "__main__":
    main_cli()
