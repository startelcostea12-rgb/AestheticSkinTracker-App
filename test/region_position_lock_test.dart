import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:aesthetic_skin_tracker/utils/trend_lock_reason.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _boxes({
  double wrinkleCx = 0.48,
  double wrinkleW = 0.9,
  double underEyeLeftCx = 0.24,
  double underEyeLeftH = 0.11,
}) => <String, dynamic>{
  'wrinkle_region_box_cx': wrinkleCx,
  'wrinkle_region_box_cy': 0.22,
  'wrinkle_region_box_w': wrinkleW,
  'wrinkle_region_box_h': 0.30,
  'pore_contraction_roi_box_cx': 0.5,
  'pore_contraction_roi_box_cy': 0.72,
  'pore_contraction_roi_box_w': 0.97,
  'pore_contraction_roi_box_h': 0.74,
  'under_eye_left_box_cx': underEyeLeftCx,
  'under_eye_left_box_cy': 0.49,
  'under_eye_left_box_w': 0.21,
  'under_eye_left_box_h': underEyeLeftH,
  'under_eye_right_box_cx': 0.72,
  'under_eye_right_box_cy': 0.50,
  'under_eye_right_box_w': 0.22,
  'under_eye_right_box_h': 0.11,
};

Map<String, dynamic> _payload(Map<String, dynamic> boxes) => <String, dynamic>{
  'metric_matrix': <String, dynamic>{
    'wrinkle_load': 28.0,
    'pore_contraction_index': 68.0,
    'under_eye_dark_circle_density': 30.0,
    'under_eye_texture_density': 55.0,
    'texture_smoothness': 59.0,
  },
  'image_quality': boxes,
};

const _status = <String, String>{
  'wrinkle_load': 'improved',
  'under_eye_dark_circle_density': 'worsened',
  'texture_smoothness': 'stable',
};
const _deltas = <String, double>{
  'wrinkle_load': 12.0,
  'under_eye_dark_circle_density': -9.0,
  'texture_smoothness': 0.0,
};

void main() {
  test('limits are 4% of face width and 8% area', () {
    expect(regionPositionCenterShiftLimit, 0.04);
    expect(regionPositionAreaChangeLimit, 0.08);
    expect(knownTrendLockReasons, contains('region_position_mismatch'));
    expect(trendLockReasonShortLabel('region_position_mismatch'), isNotNull);
  });

  test('a box centre shift > 4% locks and clears status and delta', () {
    final result = lockTrendsForRegionPositionMismatch(
      trendStatus: _status,
      trendDeltas: _deltas,
      trendLockReasons: const {},
      currentPayload: _payload(_boxes(wrinkleCx: 0.48 + 0.05)),
      baselinePayload: _payload(_boxes()),
    );
    expect(result.trendLockReasons['wrinkle_load'], 'region_position_mismatch');
    expect(result.trendStatus.containsKey('wrinkle_load'), isFalse);
    expect(result.trendDeltas.containsKey('wrinkle_load'), isFalse);
    // Other metrics untouched.
    expect(result.trendStatus['under_eye_dark_circle_density'], 'worsened');
    expect(result.trendStatus['texture_smoothness'], 'stable');
    expect(result.trendLockReasons.containsKey('texture_smoothness'), isFalse);
  });

  test('an area change > 8% locks; each under-eye band counts', () {
    final result = lockTrendsForRegionPositionMismatch(
      trendStatus: _status,
      trendDeltas: _deltas,
      trendLockReasons: const {},
      currentPayload: _payload(_boxes(underEyeLeftH: 0.11 * 1.10)),
      baselinePayload: _payload(_boxes()),
    );
    for (final key in const [
      'under_eye_dark_circle_density',
      'under_eye_texture_density',
    ]) {
      expect(result.trendLockReasons[key], 'region_position_mismatch');
    }
    expect(
      result.trendStatus.containsKey('under_eye_dark_circle_density'),
      isFalse,
    );
    expect(result.trendLockReasons.containsKey('wrinkle_load'), isFalse);
  });

  test('small shifts within the limits do not lock', () {
    final result = lockTrendsForRegionPositionMismatch(
      trendStatus: _status,
      trendDeltas: _deltas,
      trendLockReasons: const {},
      currentPayload: _payload(
        _boxes(wrinkleCx: 0.48 + 0.03, underEyeLeftH: 0.11 * 1.05),
      ),
      baselinePayload: _payload(_boxes()),
    );
    expect(result.trendLockReasons, isEmpty);
    expect(result.trendStatus, _status);
  });

  test('a baseline without logged boxes, or no baseline, does not lock', () {
    for (final baseline in [
      _payload(const <String, dynamic>{}),
      const <String, dynamic>{},
    ]) {
      final result = lockTrendsForRegionPositionMismatch(
        trendStatus: _status,
        trendDeltas: _deltas,
        trendLockReasons: const {},
        currentPayload: _payload(_boxes(wrinkleCx: 0.9)),
        baselinePayload: baseline,
      );
      expect(result.trendLockReasons, isEmpty);
    }
  });

  test('an existing lock reason is kept', () {
    final result = lockTrendsForRegionPositionMismatch(
      trendStatus: const {},
      trendDeltas: const {},
      trendLockReasons: const {'wrinkle_load': 'formula_version_mismatch'},
      currentPayload: _payload(_boxes(wrinkleCx: 0.9)),
      baselinePayload: _payload(_boxes()),
    );
    expect(result.trendLockReasons['wrinkle_load'], 'formula_version_mismatch');
  });

  test('runs in the live trend chain before locked verdicts are cleared', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    final lighting = source.indexOf(
      'final lightingAdjustedTrend = lockTrendsForLightingMismatch(',
    );
    final region = source.indexOf(
      'final regionAdjustedTrend = lockTrendsForRegionPositionMismatch(',
    );
    final clear = source.indexOf(
      'final unlockedVerdictsOnly = clearLockedTrendVerdicts(',
    );
    expect(lighting, isNonNegative);
    expect(region, greaterThan(lighting));
    expect(clear, greaterThan(region));
  });

  test('the export carries the region boxes', () {
    final row = AiScanDataCsvExporter.format([
      ScanHistoryEntry(
        id: 'boxes',
        timestamp: DateTime.parse('2026-10-19T08:00:00'),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: _payload(_boxes()),
      ),
    ], registryBaselineScanIds: const {}).split('\r\n');
    final header = row.first.split(',');
    final values = row[1].split(',');
    String cell(String c) => values[header.indexOf(c)];
    expect(cell('image_quality.wrinkle_region_box_cx'), '0.48');
    expect(cell('image_quality.under_eye_left_box_h'), '0.11');
    expect(cell('image_quality.pore_contraction_roi_box_w'), '0.97');
    expect(
      header.where((c) => c == 'image_quality.under_eye_right_box_cy'),
      hasLength(1),
    );
  });
}
