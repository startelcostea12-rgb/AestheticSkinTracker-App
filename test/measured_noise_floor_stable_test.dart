import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, String> trendLockReasons,
})
_apply(
  String key,
  double baseline,
  double current, {
  String status = 'improved',
  double delta = 9.0,
  String? lockReason,
}) => forceStableWithinMeasuredNoiseFloors(
  trendStatus: {key: status},
  trendDeltas: {key: delta},
  trendLockReasons: {if (lockReason != null) key: lockReason},
  averagedMetricMatrix: {key: current},
  baselineMetricMatrix: {key: baseline},
);

void main() {
  test('the four floors are as specified', () {
    expect(measuredStableNoiseFloors, {
      'texture_smoothness': 2.0,
      'pigment_load': 1.5,
      'pore_visibility': 1.5,
      'structural_firmness_elasticity': 2.0,
    });
  });

  test('a 1.0-point texture move is stable with no percentage', () {
    final result = _apply('texture_smoothness', 57.0, 58.0);
    expect(result.trendStatus['texture_smoothness'], 'stable');
    expect(result.trendDeltas['texture_smoothness'], 0.0);
  });

  test('a 2.5-point texture move keeps its improved or worsened status', () {
    final up = _apply('texture_smoothness', 57.0, 59.5);
    expect(up.trendStatus['texture_smoothness'], 'improved');
    expect(up.trendDeltas['texture_smoothness'], 9.0);
    final down = _apply(
      'texture_smoothness',
      57.0,
      54.5,
      status: 'worsened',
      delta: -4.4,
    );
    expect(down.trendStatus['texture_smoothness'], 'worsened');
  });

  test('a move exactly at the floor is not forced to stable', () {
    expect(
      _apply(
        'texture_smoothness',
        57.0,
        59.0,
      ).trendStatus['texture_smoothness'],
      'improved',
    );
  });

  test('pigment, pores, and firmness follow the same rule', () {
    for (final (key, below, above) in const [
      ('pigment_load', 1.0, 2.0),
      ('pore_visibility', 1.2, 1.6),
      ('structural_firmness_elasticity', 1.5, 2.5),
    ]) {
      final under = _apply(key, 20.0, 20.0 + below, status: 'worsened');
      expect(under.trendStatus[key], 'stable', reason: key);
      expect(under.trendDeltas[key], 0.0, reason: key);
      final over = _apply(key, 20.0, 20.0 + above, status: 'worsened');
      expect(over.trendStatus[key], 'worsened', reason: key);
    }
  });

  test('locks and insufficient_signal take priority', () {
    for (final lock in const [
      'lighting_mismatch',
      'formula_version_mismatch',
      'frame_range_overlap',
    ]) {
      final locked = _apply(
        'texture_smoothness',
        57.0,
        58.0,
        status: 'stable',
        delta: 0.0,
        lockReason: lock,
      );
      expect(locked.trendLockReasons['texture_smoothness'], lock);
    }
    final weak = _apply(
      'pigment_load',
      10.0,
      10.5,
      status: 'insufficient_signal',
      delta: 0.0,
    );
    expect(weak.trendStatus['pigment_load'], 'insufficient_signal');
  });

  test('other metrics are unchanged', () {
    final redness = _apply('localized_redness', 10.0, 10.5);
    expect(redness.trendStatus['localized_redness'], 'improved');
    final radiance = _apply('skin_tone_radiance_evenness', 30.0, 30.5);
    expect(radiance.trendStatus['skin_tone_radiance_evenness'], 'improved');
  });

  test('chained before the backend-floor gate and the lighting lock', () {
    Map<String, dynamic> exposure(double bv) => {
      aiScanPerFrameDiagnosticsKey: [
        for (var i = 0; i < 3; i++) {'iso': 400, 'brightness_value': bv},
      ],
    };
    ({
      Map<String, String> trendStatus,
      Map<String, double> trendDeltas,
      Map<String, String> trendLockReasons,
    })
    chain(double current, {double currentBv = 1.4}) {
      final measured = _apply('texture_smoothness', 57.0, current);
      final backendFloor = downgradeTrendBelowMeasuredNoiseFloor(
        trendStatus: measured.trendStatus,
        trendDeltas: measured.trendDeltas,
        trendLockReasons: measured.trendLockReasons,
        averagedMetricMatrix: {'texture_smoothness': current},
        baselineMetricMatrix: {'texture_smoothness': 57.0},
        metricNoiseFloor2sd: {'texture_smoothness': 5.4},
        trendNoiseFloorExceedsUsefulRange: const {},
        trendNoiseFloorExcludedMultiplier: 3.0,
      );
      return lockTrendsForLightingMismatch(
        trendStatus: backendFloor.trendStatus,
        trendDeltas: backendFloor.trendDeltas,
        trendLockReasons: backendFloor.trendLockReasons,
        currentPayload: exposure(currentBv),
        baselinePayload: exposure(1.4),
      );
    }

    // Below 2.0: stable, not the backend-floor lock.
    final small = chain(58.0);
    expect(small.trendStatus['texture_smoothness'], 'stable');
    expect(small.trendLockReasons.containsKey('texture_smoothness'), isFalse);

    // Between 2.0 and the backend's 5.4: the existing lock still applies.
    final medium = chain(60.0);
    expect(medium.trendLockReasons['texture_smoothness'], 'below_noise_floor');

    // A lighting mismatch still locks a move the floor made stable.
    final dim = chain(58.0, currentBv: 3.0);
    expect(dim.trendLockReasons['texture_smoothness'], 'lighting_mismatch');
    expect(dim.trendStatus.containsKey('texture_smoothness'), isFalse);
  });

  group('on the card', () {
    Map<String, dynamic> payload({
      required String status,
      String? lockReason,
    }) => <String, dynamic>{
      'is_follow_up': true,
      'local_history_count': 2,
      'metric_matrix': {'texture_smoothness': 58.0},
      'baseline_metric_matrix': {'texture_smoothness': 57.0},
      'metric_extraction_paths': {'texture_smoothness': 'laplacian_fallback'},
      'baseline_metric_extraction_paths': {
        'texture_smoothness': 'laplacian_fallback',
      },
      'trend_status': {'texture_smoothness': status},
      'trend_deltas': {'texture_smoothness': 0.0},
      if (lockReason != null)
        'trend_lock_reasons': {'texture_smoothness': lockReason},
    };

    Finder inCard(Finder matching) => find.descendant(
      of: find.byKey(const ValueKey('result_metric_texture_smoothness')),
      matching: matching,
    );

    testWidgets('a forced stable shows Stable with no percentage', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LuxeReportLayout(
                rawPayload: payload(status: 'stable'),
                requireBackendVerdict: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        inCard(find.text('Stable - change within tracking noise')),
        findsWidgets,
      );
      expect(inCard(find.textContaining('%')), findsNothing);
    });

    testWidgets('a locked metric still shows the lock, not Stable', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LuxeReportLayout(
                rawPayload: payload(
                  status: 'stable',
                  lockReason: 'lighting_mismatch',
                ),
                requireBackendVerdict: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(inCard(find.textContaining('Not comparable:')), findsOneWidget);
      expect(
        inCard(find.text('Stable - change within tracking noise')),
        findsNothing,
      );
    });
  });

  test('the live flow applies the measured floors before the backend gate', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    final run = source.indexOf('Future<void> _runAnalysis() async {');
    final measured = source.indexOf(
      '= forceStableWithinMeasuredNoiseFloors(',
      run,
    );
    final backendGate = source.indexOf(
      '= downgradeTrendBelowMeasuredNoiseFloor(',
      run,
    );
    final lighting = source.indexOf('= lockTrendsForLightingMismatch(', run);
    expect(measured, greaterThan(run));
    expect(backendGate, greaterThan(measured));
    expect(lighting, greaterThan(backendGate));
  });

  group('live card matches the saved status', () {
    Map<String, dynamic> savedPayload(
      String key,
      double baseline,
      double current, {
      String status = 'improved',
      String? lockReason,
    }) {
      final trend = forceStableWithinMeasuredNoiseFloors(
        trendStatus: {key: status},
        trendDeltas: {key: 4.0},
        trendLockReasons: {if (lockReason != null) key: lockReason},
        averagedMetricMatrix: {key: current},
        baselineMetricMatrix: {key: baseline},
      );
      final cleared = clearLockedTrendVerdicts(
        trendStatus: trend.trendStatus,
        trendDeltas: trend.trendDeltas,
        trendLockReasons: trend.trendLockReasons,
      );
      return <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': {key: current},
        'baseline_metric_matrix': {key: baseline},
        'metric_extraction_paths': {key: 'primary_roi'},
        'baseline_metric_extraction_paths': {key: 'primary_roi'},
        'trend_status': cleared.trendStatus,
        'trend_deltas': cleared.trendDeltas,
        'trend_lock_reasons': cleared.trendLockReasons,
      };
    }

    Widget liveCard(Map<String, dynamic> payload) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LuxeReportLayout(
            rawPayload: payload,
            requireBackendVerdict: true,
            applyDisplayNoiseFloors: true,
          ),
        ),
      ),
    );

    Finder inCard(String key, Finder matching) => find.descendant(
      of: find.byKey(ValueKey('result_metric_$key')),
      matching: matching,
    );

    String exportedStatus(Map<String, dynamic> payload, String key) {
      final rows = AiScanDataCsvExporter.format([
        ScanHistoryEntry(
          id: 'floor-$key',
          timestamp: DateTime.utc(2026, 10, 13),
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          estimatedSkinAge: 0,
          metrics: const <String, double>{},
          rawPayload: payload,
        ),
      ], registryBaselineScanIds: const {}).split('\r\n');
      final header = rows.first.split(',');
      return rows[1].split(',')[header.indexOf('${key}_trend_status')];
    }

    testWidgets('a 1.0-point texture move is Stable on the card and export', (
      tester,
    ) async {
      final payload = savedPayload('texture_smoothness', 57.0, 58.0);
      expect(exportedStatus(payload, 'texture_smoothness'), 'stable');

      await tester.pumpWidget(liveCard(payload));
      await tester.pumpAndSettle();
      expect(
        inCard(
          'texture_smoothness',
          find.text('Stable - change within tracking noise'),
        ),
        findsWidgets,
      );
      expect(
        inCard('texture_smoothness', find.textContaining('%')),
        findsNothing,
      );
      expect(find.text('Texture Smoothness: Stable.'), findsOneWidget);
    });

    testWidgets('pigment, pores, firmness below their floors read Stable', (
      tester,
    ) async {
      for (final (key, move) in const [
        ('pigment_load', 1.0),
        ('pore_visibility', 1.2),
        ('structural_firmness_elasticity', 1.5),
      ]) {
        final payload = savedPayload(
          key,
          20.0,
          20.0 + move,
          status: 'worsened',
        );
        expect(exportedStatus(payload, key), 'stable', reason: key);
        await tester.pumpWidget(liveCard(payload));
        await tester.pumpAndSettle();
        expect(
          inCard(key, find.text('Stable - change within tracking noise')),
          findsWidgets,
          reason: key,
        );
      }
    });

    testWidgets('a locked metric inside the floor still shows the lock', (
      tester,
    ) async {
      final payload = savedPayload(
        'texture_smoothness',
        57.0,
        58.0,
        status: 'stable',
        lockReason: 'lighting_mismatch',
      );
      expect(exportedStatus(payload, 'texture_smoothness'), isEmpty);
      await tester.pumpWidget(liveCard(payload));
      await tester.pumpAndSettle();
      expect(
        inCard('texture_smoothness', find.textContaining('Not comparable:')),
        findsOneWidget,
      );
      expect(
        inCard(
          'texture_smoothness',
          find.text('Stable - change within tracking noise'),
        ),
        findsNothing,
      );
    });
  });
}
