#!/usr/bin/env python3
"""
probe_skin_model_index_mapping.py
==================================

Verifies (or refutes) the assumed output-index -> label mapping for
`assets/models/skin_analysis_model.tflite` (the 6-output MobileNetV2-based
regressor converted by `convert_skin_model_to_tflite.py`), and separately
checks whether the [0, 1] normalization the Dart loader used to use, or
the [-1, 1] MobileNetV2 normalization it uses now, produces more sensible
output.

WHY THIS EXISTS: a Dense(6, sigmoid) output layer carries no label
metadata for its 6 units. The label order
["pigment", "redness", "texture", "wrinkle", "acne_severity",
"rosacea_intensity"] is only a training-script comment
(METRIC_NAMES_6 in convert_skin_model_to_tflite.py) -- it has never been
verified against the model's actual behavior. This script runs the model
against reference photos with known, unambiguous visible severity and
reports whether any output index tracks that severity sensibly.

RESULT AS OF THE LAST RUN (see the doc comment on `_allMetrics` in
lib/services/skin_analysis_service_io.dart for the full analysis): NO
output index, under either normalization, ranks the 5 reference photos
by visible redness/rosacea severity in a sensible order. The severe
clinical rosacea photo (`red.jpg`) scored LOWEST of all 5 on output[1]
("redness") under the corrected [-1, 1] normalization, and tied with the
clearest-skin reference on output[5] ("rosacea_intensity"). Conclusion:
the assumed index mapping is not just unconfirmed, current evidence
argues against trusting it. Do not wire this model's acne_severity /
rosacea_intensity output into any user-facing display until this
verification passes on a real, labeled dataset.

Usage:
    python tool/probe_skin_model_index_mapping.py [--tflite PATH] [photo=path ...]

With no arguments, uses the 5 reference photos this investigation used
(paths relative to the repo root; some live outside the repo -- see
PHOTOS below and adjust to your machine if they've moved).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Dict, List

import numpy as np

try:
    import tensorflow as tf
except ImportError:  # pragma: no cover - environment-dependent
    print("tensorflow is required: pip install tensorflow", file=sys.stderr)
    raise

from PIL import Image

INPUT_SIZE = 224
LABELS = ["pigment", "redness", "texture", "wrinkle", "acne_severity", "rosacea_intensity"]

DEFAULT_TFLITE_PATH = os.path.join("assets", "models", "skin_analysis_model.tflite")

# Reference photos used for the initial verification. Each was chosen for
# having an unambiguous, known visible severity so a working model's
# output could be sanity-checked against it -- NOT a labeled training/
# validation set. Replace/extend with real labeled photos before treating
# any future "pass" here as more than a smoke test.
DEFAULT_PHOTOS = {
    "clear_face (near-zero redness/acne reference)": os.path.expanduser(
        r"C:\Users\Admin\Pictures\clear face.jfif"
    ),
    "nikki2.jpg (neutral stock photo, no skin condition)": "nikki2.jpg",
    "portrait_10_woman_redness.jpg (mild cheek/nose flush)": os.path.join(
        "calibration_stock_batch", "portrait_10_woman_redness.jpg"
    ),
    "red.jpg (severe clinical rosacea/papulopustular reference)": "red.jpg",
    "portrait_05_woman_smile.jpg (clear skin, unrelated blue color-cast)": os.path.join(
        "calibration_stock_batch", "portrait_05_woman_smile.jpg"
    ),
}


def load_rgb_224(path: str) -> np.ndarray:
    img = Image.open(path).convert("RGB").resize((INPUT_SIZE, INPUT_SIZE), Image.BILINEAR)
    return np.asarray(img, dtype=np.float32)


def preprocess_wrong_0_1(pixels: np.ndarray) -> np.ndarray:
    """The normalization skin_analysis_service_io.dart used before the fix."""
    return pixels / 255.0


def preprocess_correct_neg1_1(pixels: np.ndarray) -> np.ndarray:
    """Correct MobileNetV2 preprocessing: (pixel - 127.5) / 127.5 -> [-1, 1]."""
    return (pixels - 127.5) / 127.5


def run_inference(interpreter, input_details, output_details, tensor: np.ndarray) -> np.ndarray:
    x = np.expand_dims(tensor, axis=0).astype(input_details["dtype"])
    interpreter.set_tensor(input_details["index"], x)
    interpreter.invoke()
    return interpreter.get_tensor(output_details["index"])[0].astype(float)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tflite", default=DEFAULT_TFLITE_PATH, help="Path to skin_analysis_model.tflite")
    parser.add_argument("--json-out", default="probe_results.json", help="Where to write the raw JSON results")
    args = parser.parse_args()

    if not os.path.isfile(args.tflite):
        raise SystemExit(
            f"TFLite model not found at {args.tflite!r}. Run "
            "convert_skin_model_to_tflite.py first."
        )

    photos = {label: path for label, path in DEFAULT_PHOTOS.items() if os.path.isfile(path)}
    missing = [f"{label} -> {path}" for label, path in DEFAULT_PHOTOS.items() if not os.path.isfile(path)]
    if missing:
        print("Skipping photos that could not be found:", file=sys.stderr)
        for m in missing:
            print(f"  {m}", file=sys.stderr)
    if not photos:
        raise SystemExit("None of the reference photos were found; nothing to probe.")

    interpreter = tf.lite.Interpreter(model_path=args.tflite)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]
    print(f"Input:  {input_details['shape']} {input_details['dtype']}")
    print(f"Output: {output_details['shape']} {output_details['dtype']}")
    print()

    results: Dict[str, Dict[str, List[float]]] = {}
    for label, path in photos.items():
        pixels = load_rgb_224(path)
        wrong = run_inference(interpreter, input_details, output_details, preprocess_wrong_0_1(pixels))
        correct = run_inference(interpreter, input_details, output_details, preprocess_correct_neg1_1(pixels))
        results[label] = {"wrong_0_1": wrong.tolist(), "correct_neg1_1": correct.tolist()}

        print(f"=== {label} ===")
        print("  WRONG   [0,1]  : " + ", ".join(f"{n}={v:.4f}" for n, v in zip(LABELS, wrong)))
        print("  CORRECT [-1,1] : " + ", ".join(f"{n}={v:.4f}" for n, v in zip(LABELS, correct)))
        print()

    with open(args.json_out, "w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    print(f"Wrote {args.json_out}")
    print()
    print(
        "Manually inspect whether any single index ranks the photos by "
        "visible severity in the order you'd expect (e.g. the severe "
        "clinical photo highest on redness/rosacea). If not, do not trust "
        "the assumed label order -- see this file's module docstring for "
        "the last documented finding."
    )


if __name__ == "__main__":
    main()
