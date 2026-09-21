#!/usr/bin/env python3
"""Run one real photo through the complete backend analysis pipeline.

Examples:
    python tool/test_photo_full_pipeline.py path/to/photo.jpg
    python tool/test_photo_full_pipeline.py after.jpg --compare before.jpg

The command calls the same assess_and_normalize_image() and analyze_skin_patch()
functions used by the backend endpoint and regression tests. It does not mock,
recompute, or reinterpret canonical metric values or honesty-gate statuses.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Any

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import main  # noqa: E402

CANONICAL_METRICS = tuple(main.CANONICAL_METRIC_ORDER)
EXPERIMENTAL_FIELDS = (
    "texture_ml_rough_flaky_experimental",
    "dermatitis_pattern_ml_experimental",
)


def _read_and_analyze(path: Path, baseline: dict[str, Any] | None = None) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(path)
    image_bytes = path.read_bytes()
    decoded = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
    if decoded is None:
        raise ValueError(f"Could not decode image: {path}")

    normalized, quality_profile = main.assess_and_normalize_image(image_bytes)
    kwargs: dict[str, Any] = {
        "quality_profile": quality_profile,
        "source_image_width": int(decoded.shape[1]),
        "source_image_height": int(decoded.shape[0]),
    }
    if baseline is not None:
        kwargs.update(
            baseline_matrix=baseline["result"].get("metric_matrix") or {},
            baseline_extraction_paths=baseline["result"].get("metric_extraction_paths") or {},
            baseline_capture_quality=baseline["result"].get("capture_quality"),
            baseline_image_bgr=baseline["decoded"],
            baseline_source_image_width=int(baseline["decoded"].shape[1]),
            baseline_source_image_height=int(baseline["decoded"].shape[0]),
        )

    result = main.analyze_skin_patch(normalized, **kwargs)
    return {"path": path, "decoded": decoded, "quality": quality_profile, "result": result}


def _format_number(value: Any) -> str:
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return f"{float(value):.1f}"
    return "-"


def _print_capture(report: dict[str, Any]) -> None:
    result = report["result"]
    quality = report["quality"]
    print("CAPTURE / CONFIDENCE")
    print(f"  image:              {report['path']}")
    print(f"  dimensions:         {report['decoded'].shape[1]} x {report['decoded'].shape[0]}")
    print(f"  capture_quality:    {result.get('capture_quality', 'unknown')}")
    print(f"  confidence_score:   {_format_number(result.get('confidence_score'))}")
    print(f"  sharpness_score:    {_format_number(quality.get('sharpness_score'))}")
    print(f"  lighting_balance:   {_format_number(quality.get('lighting_balance_score'))}")
    print(f"  confidence_hints:   {result.get('confidence_hints') or 'none'}")


def _print_metrics(result: dict[str, Any]) -> None:
    matrix = result.get("metric_matrix") or {}
    confidence = result.get("metric_confidence") or {}
    status = result.get("metric_status") or {}
    print("CANONICAL METRICS")
    print("  metric                              value   confidence  status")
    for key in CANONICAL_METRICS:
        value = matrix.get(key)
        if value is None:
            print(f"  {key:<34} {'omitted':>7}   {confidence.get(key, '-'):>10}  {status.get(key, 'unavailable')}")
        else:
            print(f"  {key:<34} {_format_number(value):>7}   {confidence.get(key, '-'):>10}  {status.get(key, 'computed')}")
    print("  severity bands:     not emitted by the backend metric contract; confidence/status shown above")


def _print_omissions(result: dict[str, Any]) -> None:
    omissions = result.get("omitted_metric_reasons") or {}
    print("OMITTED METRICS")
    if not omissions:
        print("  none")
        return
    for key, reason in omissions.items():
        print(f"  {key}: {reason}")


def _print_experimental(result: dict[str, Any]) -> None:
    values = result.get("experimental_metrics") or {}
    metadata = result.get("experimental_model_metadata") or {}
    print("EXPERIMENTAL ML METRICS (non-canonical)")
    print(f"  model_status:       {metadata.get('status', 'unknown')}")
    for key in EXPERIMENTAL_FIELDS:
        value = values.get(key)
        rendered = "unavailable" if value is None else f"{float(value) * 100:.1f}% probability"
        print(f"  {key}: {rendered}")
    print("  note:               these fields never feed canonical scoring, trends, or recommendations")


def _print_trends(result: dict[str, Any]) -> None:
    statuses = result.get("trend_status") or {}
    reasons = result.get("trend_lock_reasons") or {}
    deltas = result.get("trend_deltas") or {}
    print("HONESTY-GATED TRENDS")
    if not statuses:
        print("  no baseline verdicts available")
        return
    print("  metric                              status       lock_reason                 delta")
    for key, value in statuses.items():
        print(f"  {key:<34} {str(value):<12} {str(reasons.get(key) or '-'): <27} {_format_number(deltas.get(key))}")


def run() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("image", type=Path, help="current/after photo path")
    parser.add_argument("--compare", type=Path, help="baseline/before photo path")
    args = parser.parse_args()

    try:
        main.ensure_pipeline_ready()
        baseline = _read_and_analyze(args.compare) if args.compare else None
        report = _read_and_analyze(args.image, baseline=baseline)
    except Exception as exc:
        print(f"ERROR: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    print("=" * 78)
    print("FULL BACKEND PHOTO PIPELINE REPORT")
    print("=" * 78)
    if args.compare:
        print(f"comparison: after={args.image}  before={args.compare}")
    print()
    _print_capture(report)
    print()
    _print_metrics(report["result"])
    print()
    _print_omissions(report["result"])
    print()
    _print_experimental(report["result"])
    print()
    _print_trends(report["result"])
    print("=" * 78)
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
