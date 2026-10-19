import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

const _policy = <String, dynamic>{
  'honesty_band_percent': 8.0,
  'metric_noise_floor_2sd': {
    'wrinkle_load': 3.7,
    'pore_contraction_index': 2.0,
  },
  'trend_noise_floor_exceeds_useful_range': ['localized_redness'],
  'trend_noise_floor_excluded_multiplier': 3.0,
  'metric_higher_is_worse': {
    'wrinkle_load': true,
    'pore_contraction_index': true,
    'under_eye_dark_circle_density': true,
    'under_eye_texture_density': true,
  },
};

RollingTrendScan _scan(
  String id,
  int minute, {
  double wrinkle = 30.0,
  double bv = 3.4,
  String path = 'primary_roi',
  int version = 4,
  String quality = 'normal',
  String pose = 'Front',
  bool policy = false,
}) => (
  id: id,
  timestamp: DateTime(2026, 10, 19, 9, minute),
  poseTemplate: pose,
  guideType: 'facial',
  captureQuality: quality,
  payload: <String, dynamic>{
    'metric_matrix': {'wrinkle_load': wrinkle},
    'metric_extraction_paths': {'wrinkle_load': path},
    'metric_formula_versions': {'wrinkle_load': version},
    aiScanPerFrameDiagnosticsKey: [
      for (var i = 0; i < 5; i++) {'iso': 64, 'brightness_value': bv},
    ],
    if (policy) ..._policy,
  },
);

void main() {
  final baseline = _scan('baseline', 0, wrinkle: 40.0);
  final current = _scan('current', 30, wrinkle: 30.0, policy: true);

  test('uses the median of three scans when two qualify', () {
    final result = applyRollingTrend(
      trendStatus: const {},
      trendDeltas: const {},
      trendLockReasons: const {},
      current: current,
      baseline: baseline,
      history: [
        baseline,
        _scan('p1', 10, wrinkle: 50.0),
        _scan('p2', 20, wrinkle: 32.0),
      ],
    );
    // median(30, 50, 32) = 32 vs baseline 40: (40-32)/40 = 20% better.
    final note = result.rollingTrend['wrinkle_load']!;
    expect(note['method'], 'rolling_median_3');
    expect(note['current_value'], 32.0);
    expect(note['baseline_value'], 40.0);
    expect(note['baseline_method'], 'single_scan');
    expect(note['scan_ids'], ['current', 'p2', 'p1']);
    expect(result.trendStatus['wrinkle_load'], 'improved');
    expect(result.trendDeltas['wrinkle_load'], 20.0);
  });

  test("uses the baseline's own last three when they exist", () {
    final result = applyRollingTrend(
      trendStatus: const {},
      trendDeltas: const {},
      trendLockReasons: const {},
      current: current,
      baseline: baseline,
      history: [
        _scan('b2', -20, wrinkle: 34.0),
        _scan('b1', -10, wrinkle: 36.0),
        baseline,
        _scan('p1', 10, wrinkle: 31.0),
        _scan('p2', 20, wrinkle: 29.0),
      ],
    );
    final note = result.rollingTrend['wrinkle_load']!;
    expect(note['baseline_method'], 'rolling_median_3');
    expect(note['baseline_value'], 36.0); // median(40, 36, 34)
    expect(note['current_value'], 30.0); // median(30, 31, 29)
    expect(note['baseline_scan_ids'], ['baseline', 'b1', 'b2']);
    // |30 - 36| = 6 clears the 3.7 floor; 16.7% clears the 8% band.
    expect(result.trendStatus['wrinkle_load'], 'improved');
    expect(result.trendDeltas['wrinkle_load'], 16.7);
  });

  test('falls back to the single-scan comparison with fewer than three', () {
    final result = applyRollingTrend(
      trendStatus: const {},
      trendDeltas: const {},
      trendLockReasons: const {},
      current: current,
      baseline: baseline,
      history: [
        baseline,
        _scan('ok', 25, wrinkle: 31.0),
        _scan('bright', 21, bv: 4.6), // |dBv| > 1.0
        _scan('path', 22, path: 'fallback'),
        _scan('version', 23, version: 3),
        _scan('blurry', 24, quality: 'blurry'),
        _scan('angle', 26, pose: 'Left 45°'),
        _scan('before_baseline', -5),
      ],
    );
    final note = result.rollingTrend['wrinkle_load']!;
    expect(note['method'], 'single_scan_fallback');
    expect(note['reason'], 'fewer_than_three_scans');
    expect(note['qualifying_scans'], 2);
    expect(result.trendStatus.containsKey('wrinkle_load'), isFalse);
  });

  test('a locked metric keeps its lock and gets no rolling verdict', () {
    final result = applyRollingTrend(
      trendStatus: const {},
      trendDeltas: const {},
      trendLockReasons: const {'wrinkle_load': 'formula_version_mismatch'},
      current: current,
      baseline: baseline,
      history: [baseline, _scan('p1', 10), _scan('p2', 20)],
    );
    expect(result.rollingTrend['wrinkle_load'], {
      'method': 'locked',
      'lock_reason': 'formula_version_mismatch',
    });
    expect(result.trendStatus, isEmpty);
  });

  test('rolling status uses the echoed policy (floor and band)', () {
    expect(
      rollingTrendStatus(
        key: 'wrinkle_load',
        current: 37.0,
        baseline: 40.0,
        policy: _policy,
      ),
      (delta: 0.0, status: 'stable'), // 3.0 < 3.7 floor
    );
    expect(
      rollingTrendStatus(
        key: 'wrinkle_load',
        current: 46.0,
        baseline: 40.0,
        policy: _policy,
      ),
      (delta: -15.0, status: 'worsened'),
    );
    expect(
      rollingTrendStatus(
        key: 'wrinkle_load',
        current: 46.0,
        baseline: 40.0,
        policy: const {},
      ),
      isNull,
    );
  });

  test('without the echoed policy it falls back', () {
    final result = applyRollingTrend(
      trendStatus: const {},
      trendDeltas: const {},
      trendLockReasons: const {},
      current: _scan('current', 30),
      baseline: baseline,
      history: [baseline, _scan('p1', 10), _scan('p2', 20)],
    );
    expect(
      result.rollingTrend['wrinkle_load']!['reason'],
      'policy_unavailable',
    );
  });

  test('runs before the lock steps and is saved with the scan', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    final rolling = source.indexOf(
      'final rollingAdjustedTrend = applyRollingTrend(',
    );
    final redness = source.indexOf(
      'final rednessAdjustedTrend = downgradeRednessTrendForCaptureMismatch(',
    );
    final lighting = source.indexOf(
      'final lightingAdjustedTrend = lockTrendsForLightingMismatch(',
    );
    final region = source.indexOf(
      'final regionAdjustedTrend = lockTrendsForRegionPositionMismatch(',
    );
    expect(rolling, isNonNegative);
    expect(redness, greaterThan(rolling));
    expect(lighting, greaterThan(rolling));
    expect(region, greaterThan(rolling));
    expect(
      source,
      contains(
        "backendResponse['rolling_trend'] = rollingAdjustedTrend.rollingTrend;",
      ),
    );
  });

  test('the export carries the rolling note', () {
    final rows = AiScanDataCsvExporter.format([
      ScanHistoryEntry(
        id: 'rolling',
        timestamp: DateTime.parse('2026-10-19T09:30:00'),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: const {
          'metric_matrix': {'wrinkle_load': 30.0},
          'rolling_trend': {
            'wrinkle_load': {
              'method': 'rolling_median_3',
              'current_value': 32.0,
              'baseline_value': 40.0,
              'baseline_method': 'single_scan',
            },
            'under_eye_texture_density': {
              'method': 'single_scan_fallback',
              'reason': 'fewer_than_three_scans',
            },
          },
        },
      ),
    ], registryBaselineScanIds: const {}).split('\r\n');
    final header = rows.first.split(',');
    final values = rows[1].split(',');
    String cell(String c) => values[header.indexOf(c)];
    expect(cell('wrinkle_load_rolling_method'), 'rolling_median_3');
    expect(cell('wrinkle_load_rolling_current_value'), '32.0');
    expect(cell('wrinkle_load_rolling_baseline_method'), 'single_scan');
    expect(
      cell('under_eye_texture_density_rolling_method'),
      'single_scan_fallback',
    );
    expect(cell('pore_contraction_index_rolling_method'), isEmpty);
  });
}
