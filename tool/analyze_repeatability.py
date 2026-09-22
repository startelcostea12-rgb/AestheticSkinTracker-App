"""Repeatability analysis for main.py's CALIBRATION_LOG output.

Context: the trend honesty gate (main.py's _trend_delta_and_status) only
ever compares two point values and has no visibility into how much a
metric naturally wobbles frame-to-frame within one scan, let alone
scan-to-scan across repeated captures of the same face. A real session
showed texture_smoothness reading 19.4, 39.4, 33.9, and 48.7 across four
back-to-back scans -- variation far larger than the within-scan
frame-to-frame spread the gate implicitly assumes is the only noise
source. This tool measures both, from real backend logs, so a data-backed
noise floor can inform a future fix to the gate. It does not change the
gate itself.

Usage:
    # Save a uvicorn run's stdout/stderr to a file first, e.g.:
    #   uvicorn main:app > backend.log 2>&1
    # then, after running your repeated scans:
    python tool/analyze_repeatability.py backend.log

    # Multiple log files (e.g. rotated logs) are concatenated in the given
    # order:
    python tool/analyze_repeatability.py backend.log.1 backend.log

    # Group frames into scans by wall-clock gap instead of a fixed frame
    # count (falls back to --frames-per-scan if timestamps are missing):
    python tool/analyze_repeatability.py backend.log --group-by gap --gap-seconds 8

    # The app currently captures 3 frames per AI Skin Analysis scan; change
    # this if that ever changes, or if you captured a different count:
    python tool/analyze_repeatability.py backend.log --frames-per-scan 3

Output is one row per metric, a "CALIBRATION_LOG metric=... value=..."
producer, sorted by between-scan spread (worst first) so the metrics most
in need of a noise floor sort to the top.
"""

from __future__ import annotations

import argparse
import re
import statistics
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

# Mirrors main.py's `calibration_log_metrics` list order exactly. Within one
# analyze_skin_patch call, CALIBRATION_LOG lines are emitted for whichever of
# these metrics are present in metric_matrix, always in this relative order
# (a metric absent from one frame is simply skipped, never reordered). That
# makes "the next logged metric's index is <= the previous one's" a reliable
# frame-boundary signal, with no dependency on timestamps at all.
CANONICAL_METRIC_ORDER = [
    "localized_redness",
    "pigment_load",
    "rosacea_severity",
    "under_eye_dark_circle_density",
    "under_eye_texture_density",
    "glabellar_wrinkle_depth",
    "texture_smoothness",
    "wrinkle_load",
    "structural_firmness_elasticity",
    "skin_tone_radiance_evenness",
    "pore_visibility",
    "breakout_activity",
]

# main.py's own logger.info call always writes all six fields in this
# order -- there is only one CALIBRATION_LOG format in the source (see the
# comment directly above that logger.info call for the investigation this
# confirmed). Real captured logs have nonetheless been observed with only
# "metric=... value=..." present, everything after it missing. That is log
# capture/transport truncation (e.g. terminal line-wrapping or an
# ANSI-sequence interaction when output is captured via a transcript/session
# tool rather than a plain shell redirect), not a second emission site, so
# only metric= and value= are required here -- every field after value= is
# optional and, being a fixed trailing run in a single format string, can
# only ever be missing from the end, never reordered or missing from the
# middle.
CALIBRATION_LOG_RE = re.compile(
    r"CALIBRATION_LOG\s+metric=(?P<metric>\S+)\s+value=(?P<value>[-+0-9.eEnaif]+)"
    r"(?:\s+confidence=(?P<confidence>\S+))?"
    r"(?:\s+path=(?P<path>\S+))?"
    r"(?:\s+capture_quality=(?P<capture_quality>\S+))?"
    r"(?:\s+roi_pixels=(?P<roi_pixels>\d+))?"
)

# Strips ANSI/VT100 escape sequences (SGR color codes, cursor movement,
# line-clear codes, etc.) that can end up embedded in a captured log line --
# e.g. from a colorized console session recorded through a transcript tool
# rather than a plain shell redirect -- and would otherwise break a field
# match that happens to land right where a sequence was inserted.
ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*[a-zA-Z]")

# Optional leading timestamp produced by main.py's own logging.basicConfig
# format ("%(asctime)s [%(levelname)s] %(message)s"), e.g.
# "2026-09-22 10:15:32,123 [INFO] CALIBRATION_LOG ...". Best-effort: a line
# without a recognizable timestamp (a different logging setup, or the
# CALIBRATION_LOG text pasted without its prefix) just gets timestamp=None,
# and --group-by gap falls back to frame-count grouping if any are missing.
TIMESTAMP_RE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?)"
)


@dataclass(frozen=True)
class Reading:
    line_no: int
    metric: str
    value: float
    confidence: str | None
    path: str | None
    capture_quality: str | None
    roi_pixels: int | None
    timestamp: datetime | None


def _parse_timestamp(text: str) -> datetime | None:
    match = TIMESTAMP_RE.match(text)
    if not match:
        return None
    raw = match.group("ts").replace(",", ".").replace("T", " ")
    for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(raw, fmt)
        except ValueError:
            continue
    return None


def parse_log(paths: list[Path]) -> list[Reading]:
    """Reads CALIBRATION_LOG lines from one or more log files, in order.

    Non-matching lines (everything else uvicorn/main.py logs) are silently
    skipped. Multiple files are concatenated in the given order, which lets
    a rotated log be passed as two files without manually stitching them.
    """
    readings: list[Reading] = []
    line_no = 0
    for path in paths:
        text = path.read_text(encoding="utf-8", errors="replace")
        for raw_line in text.splitlines():
            line_no += 1
            line = ANSI_ESCAPE_RE.sub("", raw_line)
            match = CALIBRATION_LOG_RE.search(line)
            if not match:
                continue
            try:
                value = float(match.group("value"))
            except ValueError:
                continue
            if value != value:  # NaN never represents a usable measurement.
                continue
            roi_pixels_text = match.group("roi_pixels")
            readings.append(
                Reading(
                    line_no=line_no,
                    metric=match.group("metric"),
                    value=value,
                    confidence=match.group("confidence"),
                    path=match.group("path"),
                    capture_quality=match.group("capture_quality"),
                    roi_pixels=int(roi_pixels_text) if roi_pixels_text else None,
                    timestamp=_parse_timestamp(line),
                )
            )
    return readings


def group_into_frames(readings: list[Reading]) -> list[list[Reading]]:
    """Splits a flat reading stream into one group per backend call.

    See CANONICAL_METRIC_ORDER's comment for the wrap-around heuristic this
    relies on. A metric not in CANONICAL_METRIC_ORDER (e.g. a future
    addition to main.py's calibration_log_metrics list this tool hasn't been
    updated for) is treated as always starting a new frame, which is the
    conservative choice -- it can over-split, never silently merge two real
    frames together.
    """
    frames: list[list[Reading]] = []
    current: list[Reading] = []
    last_index = -1
    for reading in readings:
        try:
            index = CANONICAL_METRIC_ORDER.index(reading.metric)
        except ValueError:
            index = -1
        if current and index <= last_index:
            frames.append(current)
            current = []
        current.append(reading)
        last_index = index
    if current:
        frames.append(current)
    return frames


# A Scan keeps its frame boundaries (list of frames, each a list of
# Reading) rather than flattening immediately, so the report can show real
# per-scan frame counts and so within-scan spread can be computed per
# metric without re-deriving frame membership.
Scan = list[list[Reading]]


def group_frames_fixed(frames: list[list[Reading]], frames_per_scan: int) -> list[Scan]:
    """Chunks frames into scans of a fixed frame count.

    The last, possibly-partial chunk is still reported as a scan -- a
    session that doesn't divide evenly is more useful partially analyzed
    than silently dropped.
    """
    return [
        frames[start : start + frames_per_scan]
        for start in range(0, len(frames), frames_per_scan)
    ]


def _frame_timestamp(frame: list[Reading]) -> datetime | None:
    timestamps = [r.timestamp for r in frame if r.timestamp is not None]
    return min(timestamps) if timestamps else None


def group_frames_by_gap(
    frames: list[list[Reading]], gap_seconds: float
) -> list[Scan] | None:
    """Starts a new scan whenever the gap since the previous frame exceeds
    gap_seconds. Returns None (rather than a best-effort guess) if any
    frame has no usable timestamp, so the caller can fall back to
    group_frames_fixed instead of silently misgrouping.
    """
    frame_times = [_frame_timestamp(frame) for frame in frames]
    if any(ts is None for ts in frame_times):
        return None

    scans: list[Scan] = []
    current: Scan = []
    previous_ts: datetime | None = None
    for frame, ts in zip(frames, frame_times):
        if previous_ts is not None and (ts - previous_ts).total_seconds() > gap_seconds:
            scans.append(current)
            current = []
        current.append(frame)
        previous_ts = ts
    if current:
        scans.append(current)
    return scans


@dataclass
class MetricStats:
    metric: str
    n: int
    minimum: float
    maximum: float
    mean: float
    stdev: float | None
    spread_pct: float
    n_scans: int
    within_scan_mean_pct: float | None
    within_scan_max_pct: float | None
    between_scan_pct: float | None
    noise_floor_2sd: float | None


def build_metric_reports(scans: list[Scan]) -> dict[str, MetricStats]:
    all_metrics = sorted(
        {r.metric for scan in scans for frame in scan for r in frame}
    )
    reports: dict[str, MetricStats] = {}

    for metric in all_metrics:
        per_scan_values: list[list[float]] = []
        for scan in scans:
            values = [
                r.value for frame in scan for r in frame if r.metric == metric
            ]
            if values:
                per_scan_values.append(values)

        all_values = [v for values in per_scan_values for v in values]
        if not all_values:
            continue

        n = len(all_values)
        vmin = min(all_values)
        vmax = max(all_values)
        vmean = statistics.fmean(all_values)
        vstdev = statistics.stdev(all_values) if n >= 2 else None
        spread_pct = ((vmax - vmin) / vmean * 100.0) if vmean else float("nan")

        within_ranges = [
            max(values) - min(values) for values in per_scan_values if len(values) >= 2
        ]
        if within_ranges and vmean:
            within_scan_mean_pct = statistics.fmean(within_ranges) / vmean * 100.0
            within_scan_max_pct = max(within_ranges) / vmean * 100.0
        else:
            within_scan_mean_pct = None
            within_scan_max_pct = None

        scan_means = [statistics.fmean(values) for values in per_scan_values]
        if len(scan_means) >= 2 and vmean:
            between_scan_pct = (max(scan_means) - min(scan_means)) / vmean * 100.0
            noise_floor_2sd = 2.0 * statistics.stdev(scan_means)
        else:
            between_scan_pct = None
            noise_floor_2sd = None

        reports[metric] = MetricStats(
            metric=metric,
            n=n,
            minimum=vmin,
            maximum=vmax,
            mean=vmean,
            stdev=vstdev,
            spread_pct=spread_pct,
            n_scans=len(per_scan_values),
            within_scan_mean_pct=within_scan_mean_pct,
            within_scan_max_pct=within_scan_max_pct,
            between_scan_pct=between_scan_pct,
            noise_floor_2sd=noise_floor_2sd,
        )

    return reports


def sorted_by_between_scan_spread(
    reports: dict[str, MetricStats],
) -> list[MetricStats]:
    """Worst (largest) between-scan spread first. A metric with no
    between-scan figure (fewer than 2 scans contributed a value) sorts
    last, since "unknown" is not the same claim as "small"."""

    def key(stats: MetricStats) -> float:
        return stats.between_scan_pct if stats.between_scan_pct is not None else -1.0

    return sorted(reports.values(), key=key, reverse=True)


def _fmt(value: float | None, digits: int = 1) -> str:
    return "n/a" if value is None else f"{value:.{digits}f}"


def print_report(scans: list[Scan], reports: dict[str, MetricStats]) -> None:
    print(f"Scans detected: {len(scans)}")
    for i, scan in enumerate(scans, start=1):
        readings = [r for frame in scan for r in frame]
        metrics_present = sorted({r.metric for r in readings})
        print(
            f"  scan {i}: {len(scan)} frames, {len(readings)} readings "
            f"across {len(metrics_present)} metrics"
        )
    print()

    ordered = sorted_by_between_scan_spread(reports)

    header = (
        f"{'metric':<32} {'n':>3} {'min':>7} {'max':>7} {'mean':>7} {'stdev':>7} "
        f"{'spread%':>8} {'within%':>8} {'between%':>9} {'noise_floor_2sd':>16}"
    )
    print(header)
    print("-" * len(header))
    for stats in ordered:
        print(
            f"{stats.metric:<32} {stats.n:>3} "
            f"{stats.minimum:>7.1f} {stats.maximum:>7.1f} {stats.mean:>7.1f} "
            f"{_fmt(stats.stdev):>7} {_fmt(stats.spread_pct):>8} "
            f"{_fmt(stats.within_scan_mean_pct):>8} {_fmt(stats.between_scan_pct):>9} "
            f"{_fmt(stats.noise_floor_2sd):>16}"
        )
    print()
    print(
        "spread% = (max-min)/mean over all readings; within% = average "
        "per-scan (max-min)/overall-mean; between% = (max(scan means) - "
        "min(scan means))/overall-mean. noise_floor_2sd = 2 * stdev(scan "
        "means), in the metric's own 0-100 units -- a candidate minimum "
        "change threshold for the trend gate, sized to this metric's "
        "actual scan-to-scan variability rather than a single fixed "
        "percentage applied to every metric alike."
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "log_files",
        nargs="+",
        type=Path,
        help="One or more uvicorn log files containing CALIBRATION_LOG lines.",
    )
    parser.add_argument(
        "--frames-per-scan",
        type=int,
        default=3,
        help="Frames per scan for --group-by frames (default: 3, matching "
        "the app's current AI Skin Analysis capture count).",
    )
    parser.add_argument(
        "--group-by",
        choices=("frames", "gap"),
        default="frames",
        help="How to group frames into scans (default: frames).",
    )
    parser.add_argument(
        "--gap-seconds",
        type=float,
        default=5.0,
        help="Minimum wall-clock gap (seconds) between frames that starts "
        "a new scan, for --group-by gap (default: 5.0).",
    )
    args = parser.parse_args(argv)

    for path in args.log_files:
        if not path.is_file():
            parser.error(f"Log file not found: {path}")

    readings = parse_log(args.log_files)
    if not readings:
        print(
            "No CALIBRATION_LOG lines found in the given log file(s).",
            file=sys.stderr,
        )
        return 1

    frames = group_into_frames(readings)

    scans: list[Scan] | None = None
    if args.group_by == "gap":
        scans = group_frames_by_gap(frames, args.gap_seconds)
        if scans is None:
            print(
                "Warning: one or more frames have no usable timestamp; "
                f"falling back to --frames-per-scan {args.frames_per_scan} "
                "grouping.",
                file=sys.stderr,
            )
    if scans is None:
        scans = group_frames_fixed(frames, args.frames_per_scan)

    print(f"Parsed {len(readings)} CALIBRATION_LOG readings, {len(frames)} frames.")
    reports = build_metric_reports(scans)
    print_report(scans, reports)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
