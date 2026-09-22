"""Tests for tool/analyze_repeatability.py.

The tool has no import-time dependency on main.py's runtime pipeline (no
cv2/mediapipe/torch needed) -- it only parses text log lines -- so these
tests import it directly and exercise its functions on small, hand-built
log fixtures rather than requiring a real backend run.
"""
from __future__ import annotations

import sys
from datetime import datetime
from pathlib import Path

import pytest

TOOL_DIR = Path(__file__).resolve().parent / "tool"
sys.path.insert(0, str(TOOL_DIR))

import analyze_repeatability as ar  # noqa: E402


def _line(metric: str, value, ts: str | None = None) -> str:
    prefix = f"{ts} [INFO] " if ts else ""
    return (
        f"{prefix}CALIBRATION_LOG metric={metric} value={value} "
        "confidence=high path=cheek_primary capture_quality=normal roi_pixels=9000"
    )


class TestParsing:
    def test_extracts_all_fields_from_a_line_with_timestamp(self, tmp_path):
        log = tmp_path / "backend.log"
        log.write_text(
            _line("texture_smoothness", 39.4, ts="2026-09-22 10:05:03,001") + "\n"
        )

        readings = ar.parse_log([log])

        assert len(readings) == 1
        r = readings[0]
        assert r.metric == "texture_smoothness"
        assert r.value == 39.4
        assert r.confidence == "high"
        assert r.path == "cheek_primary"
        assert r.capture_quality == "normal"
        assert r.roi_pixels == 9000
        assert r.timestamp == datetime(2026, 9, 22, 10, 5, 3, 1000)

    def test_a_line_with_no_recognizable_timestamp_still_parses_with_none(
        self, tmp_path
    ):
        log = tmp_path / "backend.log"
        log.write_text(_line("texture_smoothness", 39.4) + "\n")

        readings = ar.parse_log([log])

        assert len(readings) == 1
        assert readings[0].timestamp is None

    def test_non_matching_lines_are_ignored(self, tmp_path):
        log = tmp_path / "backend.log"
        log.write_text(
            "2026-09-22 10:00:00,000 [INFO] ROI_PATH_SUMMARY cheek=100\n"
            + _line("localized_redness", 10.0)
            + "\n"
        )

        readings = ar.parse_log([log])

        assert len(readings) == 1
        assert readings[0].metric == "localized_redness"

    def test_multiple_files_are_concatenated_in_order(self, tmp_path):
        first = tmp_path / "backend.log.1"
        second = tmp_path / "backend.log"
        first.write_text(_line("localized_redness", 10.0) + "\n")
        second.write_text(_line("localized_redness", 20.0) + "\n")

        readings = ar.parse_log([first, second])

        assert [r.value for r in readings] == [10.0, 20.0]

    def test_a_nan_value_is_skipped_not_parsed_as_a_reading(self, tmp_path):
        log = tmp_path / "backend.log"
        log.write_text(_line("texture_smoothness", "nan") + "\n")

        readings = ar.parse_log([log])

        assert readings == []


class TestFrameGrouping:
    def test_a_metric_order_reset_starts_a_new_frame(self):
        # localized_redness (index 0) then texture_smoothness (index 6) is
        # increasing -- same frame. localized_redness again afterward has
        # index 0 <= 6 -- a new frame.
        readings = [
            ar.Reading(1, "localized_redness", 10.0, "high", "p", "normal", 100, None),
            ar.Reading(2, "texture_smoothness", 20.0, "high", "p", "normal", 100, None),
            ar.Reading(3, "localized_redness", 11.0, "high", "p", "normal", 100, None),
            ar.Reading(4, "texture_smoothness", 21.0, "high", "p", "normal", 100, None),
        ]

        frames = ar.group_into_frames(readings)

        assert len(frames) == 2
        assert [r.metric for r in frames[0]] == [
            "localized_redness",
            "texture_smoothness",
        ]
        assert [r.metric for r in frames[1]] == [
            "localized_redness",
            "texture_smoothness",
        ]

    def test_a_metric_missing_from_one_frame_does_not_break_boundary_detection(
        self,
    ):
        # Frame 1 has only localized_redness; frame 2 has both. The frame
        # boundary must still land between them, not merge everything into
        # one frame just because texture_smoothness was briefly absent.
        readings = [
            ar.Reading(1, "localized_redness", 10.0, "high", "p", "normal", 100, None),
            ar.Reading(2, "localized_redness", 11.0, "high", "p", "normal", 100, None),
            ar.Reading(3, "texture_smoothness", 21.0, "high", "p", "normal", 100, None),
        ]

        frames = ar.group_into_frames(readings)

        assert len(frames) == 2
        assert [r.metric for r in frames[0]] == ["localized_redness"]
        assert [r.metric for r in frames[1]] == [
            "localized_redness",
            "texture_smoothness",
        ]


class TestScanGrouping:
    def _frames(self, n: int) -> list[list[ar.Reading]]:
        return [
            [ar.Reading(i, "texture_smoothness", float(i), "high", "p", "normal", 100, None)]
            for i in range(n)
        ]

    def test_fixed_grouping_chunks_by_frame_count(self):
        frames = self._frames(7)

        scans = ar.group_frames_fixed(frames, frames_per_scan=3)

        assert [len(scan) for scan in scans] == [3, 3, 1]

    def test_gap_grouping_starts_a_new_scan_after_the_threshold(self):
        base = datetime(2026, 9, 22, 10, 0, 0)
        frames = [
            [ar.Reading(1, "m", 1.0, "high", "p", "normal", 100, base)],
            [ar.Reading(2, "m", 2.0, "high", "p", "normal", 100, base.replace(second=2))],
            [ar.Reading(3, "m", 3.0, "high", "p", "normal", 100, base.replace(minute=5))],
        ]

        scans = ar.group_frames_by_gap(frames, gap_seconds=5.0)

        assert scans is not None
        assert len(scans) == 2
        assert len(scans[0]) == 2
        assert len(scans[1]) == 1

    def test_gap_grouping_returns_none_when_a_frame_has_no_timestamp(self):
        frames = [
            [ar.Reading(1, "m", 1.0, "high", "p", "normal", 100, datetime(2026, 1, 1))],
            [ar.Reading(2, "m", 2.0, "high", "p", "normal", 100, None)],
        ]

        assert ar.group_frames_by_gap(frames, gap_seconds=5.0) is None


class TestMetricReports:
    def _scan(self, values: list[float]) -> ar.Scan:
        return [
            [ar.Reading(i, "texture_smoothness", v, "high", "p", "normal", 100, None)]
            for i, v in enumerate(values)
        ]

    def test_basic_stats_over_all_readings(self):
        scans = [self._scan([10.0, 20.0, 30.0])]

        reports = ar.build_metric_reports(scans)

        stats = reports["texture_smoothness"]
        assert stats.n == 3
        assert stats.minimum == 10.0
        assert stats.maximum == 30.0
        assert stats.mean == 20.0
        assert stats.spread_pct == 100.0  # (30-10)/20 * 100

    def test_within_scan_and_between_scan_spread_are_reported_separately(self):
        # Directly models the reported problem: the trend gate treats
        # within-scan frame spread as the noise floor, but scan-to-scan
        # variation can dwarf it. Each scan here is tightly clustered
        # (small within-scan spread) while the two scans' means are far
        # apart (large between-scan spread) -- exactly the shape a fixed
        # single-scan honesty band can't see.
        scans = [
            self._scan([19.0, 19.4, 19.8]),  # baseline scan, mean 19.4
            self._scan([39.0, 39.4, 39.8]),  # current scan, mean 39.4
        ]

        reports = ar.build_metric_reports(scans)
        stats = reports["texture_smoothness"]

        assert stats.n_scans == 2
        assert stats.within_scan_mean_pct is not None
        assert stats.between_scan_pct is not None
        assert stats.between_scan_pct > stats.within_scan_mean_pct
        assert stats.within_scan_mean_pct == pytest.approx(0.8 / 29.4 * 100, rel=1e-6)
        assert stats.between_scan_pct == pytest.approx(20.0 / 29.4 * 100, rel=1e-6)

    def test_noise_floor_is_two_standard_deviations_of_scan_means(self):
        scans = [self._scan([10.0]), self._scan([20.0]), self._scan([30.0])]

        reports = ar.build_metric_reports(scans)
        stats = reports["texture_smoothness"]

        import statistics

        expected = 2.0 * statistics.stdev([10.0, 20.0, 30.0])
        assert stats.noise_floor_2sd == expected

    def test_fewer_than_two_scans_reports_between_scan_as_unavailable(self):
        scans = [self._scan([10.0, 20.0])]

        reports = ar.build_metric_reports(scans)
        stats = reports["texture_smoothness"]

        assert stats.n_scans == 1
        assert stats.between_scan_pct is None
        assert stats.noise_floor_2sd is None
        # Within-scan spread is still computable from the one scan's frames.
        assert stats.within_scan_mean_pct is not None

    def test_a_single_frame_scan_reports_within_scan_as_unavailable(self):
        scans = [self._scan([10.0]), self._scan([20.0])]

        reports = ar.build_metric_reports(scans)
        stats = reports["texture_smoothness"]

        assert stats.within_scan_mean_pct is None
        assert stats.between_scan_pct is not None


class TestSortingWorstFirst:
    def test_sorted_by_between_scan_spread_descending(self):
        reports = {
            "low_spread": ar.MetricStats(
                metric="low_spread",
                n=6,
                minimum=10.0,
                maximum=12.0,
                mean=11.0,
                stdev=1.0,
                spread_pct=18.0,
                n_scans=2,
                within_scan_mean_pct=5.0,
                within_scan_max_pct=6.0,
                between_scan_pct=10.0,
                noise_floor_2sd=0.5,
            ),
            "high_spread": ar.MetricStats(
                metric="high_spread",
                n=6,
                minimum=10.0,
                maximum=50.0,
                mean=30.0,
                stdev=15.0,
                spread_pct=133.0,
                n_scans=2,
                within_scan_mean_pct=20.0,
                within_scan_max_pct=25.0,
                between_scan_pct=68.6,
                noise_floor_2sd=28.5,
            ),
            "unknown_spread": ar.MetricStats(
                metric="unknown_spread",
                n=3,
                minimum=10.0,
                maximum=15.0,
                mean=12.0,
                stdev=None,
                spread_pct=41.7,
                n_scans=1,
                within_scan_mean_pct=41.7,
                within_scan_max_pct=41.7,
                between_scan_pct=None,
                noise_floor_2sd=None,
            ),
        }

        ordered = ar.sorted_by_between_scan_spread(reports)

        assert [stats.metric for stats in ordered] == [
            "high_spread",
            "low_spread",
            "unknown_spread",
        ]


class TestEndToEnd:
    def test_main_runs_on_a_realistic_log_and_exits_zero(self, tmp_path, capsys):
        lines = []
        base_minute = 0
        # Two scans, three frames each, texture_smoothness spanning the
        # exact reported values (28.7-50.2 current vs 11.2-30.3 baseline).
        for scan_index, values in enumerate([[11.2, 19.4, 30.3], [28.7, 39.4, 50.2]]):
            for frame_index, value in enumerate(values):
                ts = f"2026-09-22 10:{base_minute + scan_index * 5:02d}:{frame_index * 2:02d},000"
                lines.append(_line("localized_redness", 10.0 + value / 10, ts=ts))
                lines.append(_line("texture_smoothness", value, ts=ts))
        log = tmp_path / "backend.log"
        log.write_text("\n".join(lines) + "\n")

        exit_code = ar.main([str(log)])

        assert exit_code == 0
        out = capsys.readouterr().out
        assert "texture_smoothness" in out
        assert "Scans detected: 2" in out
        # texture_smoothness must sort above localized_redness: its
        # between-scan spread is far larger.
        texture_pos = out.index("texture_smoothness")
        redness_pos = out.index("localized_redness")
        assert texture_pos < redness_pos

    def test_main_returns_1_and_prints_a_message_when_no_lines_match(
        self, tmp_path, capsys
    ):
        log = tmp_path / "backend.log"
        log.write_text("nothing to see here\n")

        exit_code = ar.main([str(log)])

        assert exit_code == 1
        assert "No CALIBRATION_LOG lines found" in capsys.readouterr().err

    def test_main_errors_on_a_missing_log_file(self, tmp_path, capsys):
        missing = tmp_path / "does_not_exist.log"

        try:
            ar.main([str(missing)])
        except SystemExit as exc:
            assert exc.code == 2
        else:
            raise AssertionError("expected argparse to reject a missing file")
