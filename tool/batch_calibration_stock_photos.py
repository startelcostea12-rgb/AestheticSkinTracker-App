#!/usr/bin/env python3
"""Batch stock-photo calibration sweep for tone-stratified sanity checking.

This script is intentionally not a clinical validator or a same-person
longitudinal comparison tool. It exists only to gather volume for the existing
CALIBRATION_LOG pipeline and to give a human reviewer a side-by-side glimpse of
real-world score behavior across a rough Fitzpatrick-style tone spread.

The goal is to detect systematic bias patterns (especially skin-mask failures or
feature drift by tone), not to tune thresholds or claim clinical validity.
This is a data-collection and bias-detection pass, not a replacement for real
paired same-person studies or a medical-grade calibration pipeline.
"""

from __future__ import annotations

import argparse
import math
import statistics
import sys
from pathlib import Path
from typing import Any, Iterable
from urllib.request import urlretrieve

import cv2

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import main

DEFAULT_OUTPUT_DIR = REPO_ROOT / "calibration_stock_batch"

TONE_GROUPS = [
    "light",
    "light_medium",
    "medium_deep",
    "deep",
]

PHOTO_SOURCES = [
    ("portrait_01_woman_light.jpg", "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=1200&q=80", "light"),
    ("portrait_02_man_light.jpg", "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=1200&q=80", "light"),
    ("portrait_03_woman_peach.jpg", "https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=1200&q=80", "light_medium"),
    ("portrait_04_man_dark.jpg", "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=1200&q=80", "medium_deep"),
    ("portrait_05_woman_smile.jpg", "https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=1200&q=80", "light"),
    ("portrait_06_woman_portrait.jpg", "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=1200&q=80", "light_medium"),
    ("portrait_07_man_beard.jpg", "https://images.unsplash.com/photo-1504593811423-6dd665756598?auto=format&fit=crop&w=1200&q=80", "deep"),
    ("portrait_08_woman_hair.jpg", "https://images.unsplash.com/photo-1521119989659-a83eee488004?auto=format&fit=crop&w=1200&q=80", "light_medium"),
    ("portrait_09_woman_outdoor.jpg", "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=1200&q=80", "medium_deep"),
    ("portrait_10_woman_redness.jpg", "https://images.unsplash.com/photo-1546961329-78bef0414d7c?auto=format&fit=crop&w=1200&q=80", "medium_deep"),
    ("portrait_11_woman_olive.jpg", "https://images.unsplash.com/photo-1554151228-14d9def656e4?auto=format&fit=crop&w=1200&q=80", "light_medium"),
    ("portrait_12_woman_calm.jpg", "https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?auto=format&fit=crop&w=1200&q=80", "light"),
    ("portrait_13_man_outdoor.jpg", "https://images.unsplash.com/photo-1500917293891-ef795e70e1f6?auto=format&fit=crop&w=1200&q=80", "medium_deep"),
    ("portrait_14_woman_natural.jpg", "https://images.unsplash.com/photo-1521572267360-ee0c2909d518?auto=format&fit=crop&w=1200&q=80", "light"),
    ("portrait_15_woman_tone.jpg", "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?auto=format&fit=crop&w=1200&q=80", "light_medium"),
    ("portrait_16_man_older.jpg", "https://images.unsplash.com/photo-1504257432389-52343af06ae3?auto=format&fit=crop&w=1200&q=80", "medium_deep"),
    ("portrait_17_woman_older.jpg", "https://images.unsplash.com/photo-1524250502761-1ac6f2e30d43?auto=format&fit=crop&w=1200&q=80", "deep"),
    ("portrait_18_man_urban.jpg", "https://images.unsplash.com/photo-1504593811423-6dd665756598?auto=format&fit=crop&w=1200&q=80", "deep"),
    ("portrait_19_woman_deep.jpg", "https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?auto=format&fit=crop&w=1200&q=80", "deep"),
    ("portrait_20_man_deep.jpg", "https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?auto=format&fit=crop&w=1200&q=80", "deep"),
]

CORE_METRICS = [
    "localized_redness",
    "texture_smoothness",
    "pore_visibility",
    "breakout_activity",
    "pigment_load",
    "rosacea_severity",
    "skin_tone_radiance_evenness",
    "glabellar_wrinkle_depth",
    "under_eye_texture_density",
    "under_eye_dark_circle_density",
    "structural_firmness_elasticity",
]


def _ensure_downloaded(path: Path, url: str) -> None:
    if path.exists():
        return
    print(f"Downloading {path.name} from {url}")
    urlretrieve(url, str(path))


def _as_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(numeric):
        return None
    return numeric


def _safe_metric_value(result: dict[str, Any], metric: str) -> float | None:
    metric_matrix = result.get("metric_matrix") or {}
    value = metric_matrix.get(metric)
    numeric = _as_float(value)
    if numeric is None:
        return None
    return float(numeric)


def _safe_raw_pigment_signal(result: dict[str, Any]) -> float | None:
    raw_components = result.get("raw_components") or {}
    raw_signal = raw_components.get("pigment_signal")
    numeric = _as_float(raw_signal)
    if numeric is not None:
        return float(numeric)
    model_debug = result.get("model_debug") or {}
    model_signal = model_debug.get("pigment_signal")
    numeric = _as_float(model_signal)
    if numeric is not None:
        return float(numeric)
    return None


def _safe_metric_confidence(result: dict[str, Any], metric: str) -> str:
    metric_confidence = result.get("metric_confidence") or {}
    return str(metric_confidence.get(metric, "unknown"))


def _safe_metric_path(result: dict[str, Any], metric: str) -> str:
    extraction_paths = result.get("metric_extraction_paths") or {}
    return str(extraction_paths.get(metric, "unknown"))


def _calc_summary(values: Iterable[float]) -> dict[str, Any]:
    items = sorted(float(v) for v in values)
    if not items:
        return {"average": 0.0, "median": 0.0, "min": 0.0, "max": 0.0, "range": 0.0, "lower_bound": 0.0, "upper_bound": 0.0}
    avg = statistics.fmean(items)
    median = statistics.median(items)
    if len(items) < 2:
        return {
            "average": avg,
            "median": median,
            "min": items[0],
            "max": items[-1],
            "range": 0.0,
            "lower_bound": items[0],
            "upper_bound": items[-1],
        }
    lower_q = statistics.quantiles(items, n=4)[0]
    upper_q = statistics.quantiles(items, n=4)[2]
    iqr = upper_q - lower_q
    lower_bound = lower_q - 1.5 * iqr
    upper_bound = upper_q + 1.5 * iqr
    return {
        "average": avg,
        "median": median,
        "min": items[0],
        "max": items[-1],
        "range": items[-1] - items[0],
        "lower_bound": lower_bound,
        "upper_bound": upper_bound,
    }


def _safe_bool(result: dict[str, Any], key: str) -> bool:
    raw = (result.get("metric_matrix") or {}).get(key)
    if raw is None:
        return False
    value = _as_float(raw)
    return value is not None and value > 0.0


def _format_table_row(row: dict[str, Any]) -> str:
    cells = [row["photo"], row["tone"], row["confidence"], row["mask_failed"], row["cheek_no_skin"], *[row[m] for m in CORE_METRICS]]
    return " | ".join(str(v) for v in cells)


def _group_summary(rows: list[dict[str, Any]], tone: str) -> str:
    tone_rows = [r for r in rows if r["tone"] == tone]
    lines = [f"\nGroup: {tone} (n={len(tone_rows)})"]
    for metric in CORE_METRICS:
        values = [float(r[metric]) for r in tone_rows if r.get(metric) is not None]
        if not values:
            continue
        summary = _calc_summary(values)
        lines.append(
            f"  {metric}: avg={summary['average']:.2f}, median={summary['median']:.2f}, "
            f"min={summary['min']:.2f}, max={summary['max']:.2f}, range={summary['range']:.2f}"
        )
    conf_values = [float(r["confidence"]) for r in tone_rows]
    if conf_values:
        lines.append(
            f"  confidence_score avg={statistics.fmean(conf_values):.2f}, min={min(conf_values):.2f}, max={max(conf_values):.2f}"
        )
    mask_failed = sum(1 for r in tone_rows if r["mask_failed"])
    cheek_no_skin = sum(1 for r in tone_rows if r["cheek_no_skin"])
    lines.append(f"  skin_mask_failed rate={mask_failed / max(len(tone_rows), 1):.2%}")
    lines.append(f"  cheek_expand_no_skin_used rate={cheek_no_skin / max(len(tone_rows), 1):.2%}")
    return "\n".join(lines)


def main_cli() -> int:
    parser = argparse.ArgumentParser(description="Tone-stratified stock face calibration sweep for bias detection.")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR, help="Folder for downloaded stock photos")
    parser.add_argument("--download-if-missing", action="store_true", help="Download the stock reference set if missing")
    parser.add_argument("--limit", type=int, default=20, help="Number of photos to include in the batch")
    args = parser.parse_args()

    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    selected_sources = PHOTO_SOURCES[: max(1, min(args.limit, len(PHOTO_SOURCES)))]
    if not args.download_if_missing:
        selected_sources = [(name, url, tone) for name, url, tone in selected_sources if (output_dir / name).exists()]
        if not selected_sources:
            raise SystemExit("No stock photos were found. Re-run with --download-if-missing.")

    for name, url, _tone in selected_sources:
        _ensure_downloaded(output_dir / name, url)

    main.ensure_pipeline_ready()

    rows: list[dict[str, Any]] = []
    for name, _url, tone in selected_sources:
        image_path = output_dir / name
        if not image_path.exists():
            print(f"Skipping missing file: {image_path}", file=sys.stderr)
            continue
        image_bytes = image_path.read_bytes()
        try:
            normalized_image, quality_profile = main.assess_and_normalize_image(image_bytes)
            analysis = main.analyze_skin_patch(normalized_image, capture_quality="stock_photo_batch")
        except Exception as exc:
            print(f"ERROR analyzing {image_path.name}: {exc}", file=sys.stderr)
            continue

        raw_components = analysis.get("raw_components") or {}
        model_debug = analysis.get("model_debug") or {}
        metric_matrix = analysis.get("metric_matrix") or {}
        row: dict[str, Any] = {
            "photo": image_path.name,
            "tone": tone,
            "confidence": float(analysis.get("confidence_score", 0.0)),
            "mask_failed": bool((metric_matrix).get("skin_mask_failed", 0.0) > 0.0),
            "cheek_no_skin": bool((metric_matrix).get("cheek_expand_no_skin_used", 0.0) > 0.0),
            "raw_pigment_signal": _safe_raw_pigment_signal(analysis),
        }
        for metric in CORE_METRICS:
            row[metric] = _safe_metric_value(analysis, metric)
        rows.append(row)

    if not rows:
        raise SystemExit("No images were analyzed successfully.")

    print(f"TOTAL_IMAGES {len(selected_sources)}")
    print(f"VALID_IMAGES {len(rows)}")

    pigment_values = [float(r["pigment_load"]) for r in rows if r.get("pigment_load") is not None]
    if pigment_values:
        pigment_summary = _calc_summary(pigment_values)
        print("\n=== PIGMENT_LOAD AGGREGATE ===")
        print(
            "avg={:.2f}, median={:.2f}, min={:.2f}, max={:.2f}, range={:.2f}".format(
                pigment_summary["average"],
                pigment_summary["median"],
                pigment_summary["min"],
                pigment_summary["max"],
                pigment_summary["range"],
            )
        )

    print("\n=== STRATIFIED TABLE ===")
    print("photo | tone | confidence | skin_mask_failed | cheek_expand_no_skin_used | localized_redness | texture_smoothness | pore_visibility | breakout_activity | pigment_load | rosacea_severity | skin_tone_radiance_evenness | glabellar_wrinkle_depth | under_eye_texture_density | under_eye_dark_circle_density | structural_firmness_elasticity")
    for r in rows:
        print(
            f"{r['photo']} | {r['tone']} | {r['confidence']:.2f} | {str(r['mask_failed'])} | {str(r['cheek_no_skin'])} | "
            f"{r['localized_redness'] if r['localized_redness'] is not None else 'n/a'} | "
            f"{r['texture_smoothness'] if r['texture_smoothness'] is not None else 'n/a'} | "
            f"{r['pore_visibility'] if r['pore_visibility'] is not None else 'n/a'} | "
            f"{r['breakout_activity'] if r['breakout_activity'] is not None else 'n/a'} | "
            f"{r['pigment_load'] if r['pigment_load'] is not None else 'n/a'} | "
            f"{r['rosacea_severity'] if r['rosacea_severity'] is not None else 'n/a'} | "
            f"{r['skin_tone_radiance_evenness'] if r['skin_tone_radiance_evenness'] is not None else 'n/a'} | "
            f"{r['glabellar_wrinkle_depth'] if r['glabellar_wrinkle_depth'] is not None else 'n/a'} | "
            f"{r['under_eye_texture_density'] if r['under_eye_texture_density'] is not None else 'n/a'} | "
            f"{r['under_eye_dark_circle_density'] if r['under_eye_dark_circle_density'] is not None else 'n/a'} | "
            f"{r['structural_firmness_elasticity'] if r['structural_firmness_elasticity'] is not None else 'n/a'}"
        )

    print("\n=== STRATIFIED SUMMARY ===")
    for tone in TONE_GROUPS:
        print(_group_summary(rows, tone))

    print("\n=== PIGMENT LOAD OUTLIER FLAGS ===")
    pigment_rows = [r for r in rows if r.get("pigment_load") is not None]
    if pigment_rows:
        pigment_scores = [float(r["pigment_load"]) for r in pigment_rows]
        q1, q3 = statistics.quantiles(pigment_scores, n=4)[:2]
        iqr = q3 - q1
        lower_bound = q1 - 1.5 * iqr
        upper_bound = q3 + 1.5 * iqr
        raw_values = [float(r["raw_pigment_signal"]) for r in pigment_rows if r.get("raw_pigment_signal") is not None]
        raw_lower = raw_upper = None
        if raw_values:
            q1_raw, q3_raw = statistics.quantiles(raw_values, n=4)[:2]
            raw_iqr = q3_raw - q1_raw
            raw_lower = q1_raw - 1.5 * raw_iqr
            raw_upper = q3_raw + 1.5 * raw_iqr
        flagged = []
        for row in pigment_rows:
            score = float(row["pigment_load"])
            raw_signal = row.get("raw_pigment_signal")
            reason = []
            if score < lower_bound or score > upper_bound:
                reason.append("score_outlier")
            if raw_signal is not None and raw_lower is not None and raw_upper is not None:
                if raw_signal < raw_lower or raw_signal > raw_upper:
                    reason.append("raw_signal_outlier")
            if reason:
                flagged.append((row["photo"], score, raw_signal, reason))
        if flagged:
            for photo, score, raw_signal, reason in flagged:
                print(
                    f"{photo}: pigment_load={score:.2f}, raw_pigment_signal={raw_signal if raw_signal is not None else 'n/a'}, flags={', '.join(reason)}"
                )
        else:
            print("No pigment-load or raw-signal outliers detected by 1.5xIQR criteria.")
    else:
        print("No pigment_load values were available for outlier detection.")

    print("\n=== TONE-BIAS CHECKS ===")
    by_tone: dict[str, list[dict[str, Any]]] = {tone: [] for tone in TONE_GROUPS}
    for row in rows:
        by_tone.setdefault(row["tone"], []).append(row)

    for tone in TONE_GROUPS:
        group = by_tone[tone]
        if not group:
            continue
        avg_conf = statistics.fmean([r["confidence"] for r in group])
        mask_fail_rate = sum(1 for r in group if r["mask_failed"]) / len(group)
        cheek_fallback_rate = sum(1 for r in group if r["cheek_no_skin"]) / len(group)
        print(
            f"{tone}: confidence_avg={avg_conf:.2f}, "
            f"mask_failed_rate={mask_fail_rate:.2%}, cheek_expand_no_skin_used_rate={cheek_fallback_rate:.2%}"
        )

    print("\nPotential bias interpretation:")
    print("- This checks for systematic trend differences across tone buckets; it does not prove a model defect by itself.")
    print("- If one tone group shows a materially higher mask failure/fallback rate, that points toward an input-threshold bias in YCrCb skin segmentation.")
    print("- If one tone group shows persistently high or low values without matching visible condition, flag it for manual review before any threshold change.")
    print("- Null result is still useful: no clear tone-based drift across this sample set is itself evidence that the problem is not globally tone-biased in the tested photos.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main_cli())
