#!/usr/bin/env python3
"""
convert_skin_model_to_tflite.py
================================

Convert a trained Keras skin-analysis model (`.h5`) into a quantized,
metadata-rich `skin_analysis_model.tflite` that drops straight into this
app's `assets/models/` folder and is consumed by
`lib/services/skin_analysis_service_io.dart`.

App contract (must match the Dart loader):
  • Input  : float32 tensor [1, 224, 224, 3], RGB, normalised to [0, 1]
  • Output : float32 tensor [1, N] where N is 4 or 6
               4 metrics -> pigment, redness, texture, wrinkle
               6 metrics -> + acne_severity, rosacea_intensity
  • Values : 0..1 (the app multiplies by 10 for its 0–10 clinical scale)

What this script does:
  1. Loads the `.h5` model.
  2. Converts to TFLite with dynamic-range + float16 quantization.
  3. Writes TFLite metadata (input image normalisation + output metric
     names) using tflite-support (gracefully skipped if unavailable).
  4. Saves to `assets/models/skin_analysis_model.tflite`.
  5. Provides `run_inference(image_path)` that returns JSON metrics.

Ready to run in Google Colab — see the "COLAB QUICK START" block at the
bottom, or just run `python convert_skin_model_to_tflite.py`.
"""

from __future__ import annotations

import json
import os
from typing import List

import numpy as np

# TensorFlow is heavy; import lazily-friendly but at module top for Colab.
import tensorflow as tf

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

# Input .h5 model. Falls back through a few common names so you can just
# upload whichever file you have.
H5_CANDIDATES = [
    "acne_rosacea_clinical_model.h5",
    "skin_analysis_model.h5",
    "best_model.h5",
    "model.h5",
]

# Where the app expects the converted model. In Colab this folder is
# created automatically; locally it matches the Flutter assets path.
ASSETS_DIR = os.environ.get("ASSETS_DIR", "assets/models")
OUTPUT_TFLITE = os.path.join(ASSETS_DIR, "skin_analysis_model.tflite")

INPUT_SIZE = 224  # 224 x 224

# Canonical metric order. The first 4 are the "general skin quality"
# head; the last 2 are the "inflammatory" head used when the model emits
# 6 outputs. Order MUST match the model's output layer.
METRIC_NAMES_4 = ["pigment", "redness", "texture", "wrinkle"]
METRIC_NAMES_6 = METRIC_NAMES_4 + ["acne_severity", "rosacea_intensity"]


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------


def _resolve_h5_path() -> str:
    """Return the first existing candidate .h5, or raise a helpful error."""
    explicit = os.environ.get("H5_MODEL_PATH")
    candidates = ([explicit] if explicit else []) + H5_CANDIDATES
    for path in candidates:
        if path and os.path.isfile(path):
            print(f"[convert] Using Keras model: {path}")
            return path
    raise FileNotFoundError(
        "No .h5 model found. Set H5_MODEL_PATH or place one of "
        f"{H5_CANDIDATES} in the working directory."
    )


def _metric_names_for(num_outputs: int) -> List[str]:
    """Pick the metric name list that matches the model's output width."""
    if num_outputs == 4:
        return METRIC_NAMES_4
    if num_outputs == 6:
        return METRIC_NAMES_6
    # Unknown width: still produce stable, indexed names so the file is
    # usable and self-describing.
    names = list(METRIC_NAMES_6[:num_outputs])
    while len(names) < num_outputs:
        names.append(f"metric_{len(names)}")
    print(
        f"[convert] WARNING: model has {num_outputs} outputs (expected 4 or 6). "
        f"Using names: {names}"
    )
    return names


# ----------------------------------------------------------------------------
# 1–2. Load + convert (dynamic range + float16 quantization)
# ----------------------------------------------------------------------------


def convert(h5_path: str) -> tuple[bytes, List[str]]:
    """Load the .h5 model and return (tflite_bytes, metric_names)."""
    model = tf.keras.models.load_model(h5_path, compile=False)

    # Determine output width (last dimension of the final output tensor).
    out_shape = model.outputs[0].shape
    num_outputs = int(out_shape[-1])
    metric_names = _metric_names_for(num_outputs)
    print(f"[convert] Detected {num_outputs} output metrics: {metric_names}")

    converter = tf.lite.TFLiteConverter.from_keras_model(model)

    # Dynamic-range quantization: weights -> int8, activations computed in
    # float at runtime. Enabled via the default optimization set.
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    # Float16: keep a float16 copy of the weights too. Combined with the
    # default optimizations this yields a compact model that runs in plain
    # float on CPU and can accelerate on float16-capable GPU delegates,
    # exactly matching the app's `Interpreter.run` (no integer I/O).
    converter.target_spec.supported_types = [tf.float16]

    # Keep float32 I/O so the Dart side feeds/reads plain floats.
    converter.inference_input_type = tf.float32
    converter.inference_output_type = tf.float32

    tflite_bytes = converter.convert()
    print(f"[convert] TFLite size: {len(tflite_bytes) / 1024:.1f} KiB")
    return tflite_bytes, metric_names


# ----------------------------------------------------------------------------
# 3. Metadata (input image norm + output metric names)
# ----------------------------------------------------------------------------


def add_metadata(tflite_bytes: bytes, metric_names: List[str]) -> bytes:
    """
    Attach TFLite metadata describing the image input ([0,1] normalised)
    and the named metric outputs. Uses tflite-support; if it isn't
    installed the original bytes are returned unchanged (metadata is
    optional for this app's runtime).
    """
    try:
        from tflite_support.metadata_writers import image_classifier
        from tflite_support.metadata_writers import writer_utils
    except Exception as exc:  # pragma: no cover - optional dependency
        print(
            "[metadata] tflite-support not available "
            f"({exc}); skipping metadata. Install with "
            "`pip install tflite-support` to embed it."
        )
        return tflite_bytes

    # Input is RGB normalised to [0, 1] -> mean=0, std=255 maps 0..255 px
    # to 0..1. The ImageClassifier writer conveniently models a single
    # image input + a single score vector output, which fits our metric
    # head (each "label" is a metric name).
    ImageClassifierWriter = image_classifier.MetadataWriter
    INPUT_NORM_MEAN = [0.0]
    INPUT_NORM_STD = [255.0]

    # The writer expects a label file; write metric names one-per-line.
    labels_path = os.path.join(ASSETS_DIR, "skin_analysis_labels.txt")
    with open(labels_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(metric_names) + "\n")

    try:
        writer = ImageClassifierWriter.create_for_inference(
            tflite_bytes,
            INPUT_NORM_MEAN,
            INPUT_NORM_STD,
            [labels_path],
        )
        with_metadata = writer.populate()
        print("[metadata] Embedded input normalisation + output metric names.")
        return with_metadata
    except Exception as exc:  # pragma: no cover - best effort
        print(f"[metadata] Failed to embed metadata ({exc}); saving raw model.")
        return tflite_bytes


# ----------------------------------------------------------------------------
# 4. Save
# ----------------------------------------------------------------------------


def save(tflite_bytes: bytes, out_path: str = OUTPUT_TFLITE) -> str:
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as fh:
        fh.write(tflite_bytes)
    print(f"[save] Wrote {out_path} ({len(tflite_bytes) / 1024:.1f} KiB)")
    return out_path


# ----------------------------------------------------------------------------
# 5. Test inference
# ----------------------------------------------------------------------------


def _preprocess(image_path: str) -> np.ndarray:
    """Decode + resize to 224x224x3 and normalise to [0, 1] float32."""
    from PIL import Image  # local import keeps top-level deps light

    img = Image.open(image_path).convert("RGB").resize((INPUT_SIZE, INPUT_SIZE))
    arr = np.asarray(img, dtype=np.float32) / 255.0
    return np.expand_dims(arr, axis=0)  # [1, 224, 224, 3]


def run_inference(
    image_path: str,
    tflite_path: str = OUTPUT_TFLITE,
    as_clinical_scale: bool = False,
) -> str:
    """
    Run the converted TFLite model on a single image and return a JSON
    string of {metric_name: value}.

    Values are the model's raw 0..1 outputs by default. Set
    `as_clinical_scale=True` to multiply by 10 (the 0–10 scale the
    Flutter app surfaces in its UI).
    """
    interpreter = tf.lite.Interpreter(model_path=tflite_path)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]

    x = _preprocess(image_path).astype(input_details["dtype"])
    interpreter.set_tensor(input_details["index"], x)
    interpreter.invoke()

    raw = interpreter.get_tensor(output_details["index"])[0].astype(float)
    names = _metric_names_for(len(raw))

    scale = 10.0 if as_clinical_scale else 1.0
    metrics = {
        name: round(float(np.clip(value, 0.0, 1.0)) * scale, 4)
        for name, value in zip(names, raw)
    }
    return json.dumps(metrics, indent=2)


# ----------------------------------------------------------------------------
# Orchestration
# ----------------------------------------------------------------------------


def main() -> None:
    h5_path = _resolve_h5_path()
    tflite_bytes, metric_names = convert(h5_path)
    tflite_bytes = add_metadata(tflite_bytes, metric_names)
    out_path = save(tflite_bytes)

    # Optional smoke test: set TEST_IMAGE_PATH to a face photo to verify.
    test_image = os.environ.get("TEST_IMAGE_PATH")
    if test_image and os.path.isfile(test_image):
        print("[test] Running inference on:", test_image)
        print(run_inference(test_image, out_path, as_clinical_scale=True))
    else:
        print(
            "[test] Set TEST_IMAGE_PATH=/path/to/face.jpg to run a quick "
            "inference check."
        )


if __name__ == "__main__":
    main()


# ============================================================================
# COLAB QUICK START
# ----------------------------------------------------------------------------
# Paste these into Colab cells (or run this file after uploading a model):
#
#   # 1) Install deps
#   !pip install -q "tensorflow==2.15.*" tflite-support pillow numpy
#
#   # 2) Upload your trained model (.h5) and an optional test image
#   from google.colab import files
#   files.upload()   # choose acne_rosacea_clinical_model.h5 (+ a face.jpg)
#
#   # 3) Run the converter
#   !python convert_skin_model_to_tflite.py
#
#   # 4) (Optional) test inference and print JSON metrics
#   from convert_skin_model_to_tflite import run_inference
#   print(run_inference("face.jpg", as_clinical_scale=True))
#
#   # 5) Download the result for your app's assets/models/ folder
#   from google.colab import files
#   files.download("assets/models/skin_analysis_model.tflite")
# ============================================================================
