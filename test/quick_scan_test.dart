import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/screens/progress_report_screen.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScanHistoryEntry _scan(String id, int day, {String? mode}) => ScanHistoryEntry(
  id: id,
  timestamp: DateTime.utc(2026, 10, day, 9),
  scanType: ScanHistoryEntry.scanTypeAiAnalysis,
  estimatedSkinAge: 0,
  metrics: const <String, double>{},
  poseTemplate: 'Front',
  guideType: 'facial',
  focusArea: 'Full face',
  captureQuality: 'normal',
  rawPayload: <String, dynamic>{
    'metric_matrix': {'texture_smoothness': 59.0},
    'metric_extraction_paths': {'texture_smoothness': 'primary_roi'},
    'metric_formula_versions': {'texture_smoothness': 3},
    if (mode != null) aiScanModeKey: mode,
  },
);

Map<String, dynamic> _exposurePayload(List<({int? iso, double? bv})> frames) =>
    <String, dynamic>{
      aiScanPerFrameDiagnosticsKey: [
        for (final f in frames) {'iso': f.iso, 'brightness_value': f.bv},
      ],
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('labels', () {
    test('mode helpers', () {
      expect(isQuickAiScan(_scan('q', 1, mode: aiScanModeQuick)), isTrue);
      expect(isQuickAiScan(_scan('c', 1, mode: aiScanModeControlled)), isFalse);
      expect(
        aiScanModeLabel(_scan('q', 1, mode: aiScanModeQuick)),
        'Quick scan',
      );
      expect(
        aiScanModeLabel(_scan('c', 1, mode: aiScanModeControlled)),
        'Controlled scan',
      );
      expect(aiScanModeLabel(_scan('old', 1)), isNull);
    });

    test('export carries the scan mode', () {
      final rows = AiScanDataCsvExporter.format([
        _scan('q', 1, mode: aiScanModeQuick),
        _scan('c', 2, mode: aiScanModeControlled),
        _scan('old', 3),
      ], registryBaselineScanIds: const {}).split('\r\n');
      final header = rows.first.split(',');
      final column = header.indexOf('scan_mode');
      expect(column, isNonNegative);
      final byId = {
        for (final row in rows.skip(1))
          row.split(',')[header.indexOf('scan_id')]: row.split(',')[column],
      };
      expect(byId, {'q': 'quick', 'c': 'controlled', 'old': ''});
    });

    testWidgets('history detail is titled AI Quick Scan', (tester) async {
      // Wide surface: the detail screen has a separate, pre-existing
      // overflow at phone widths for every AI scan.
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ScanDetailScreen(scan: _scan('q', 1, mode: aiScanModeQuick)),
        ),
      );
      await tester.pump();
      expect(find.text('AI Quick Scan'), findsWidgets);
      expect(find.text('AI Deep Analysis'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: ScanDetailScreen(
            scan: _scan('c', 1, mode: aiScanModeControlled),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('AI Deep Analysis'), findsWidgets);
      expect(find.text('AI Quick Scan'), findsNothing);
      final source = File(
        'lib/screens/progress_report_screen.dart',
      ).readAsStringSync();
      expect(
        source,
        contains(
          "? (isQuickAiScan(scan) ? 'AI Quick Scan' : 'AI Deep Analysis')",
        ),
      );
    });
  });

  group('baseline', () {
    final quick = _scan('quick-first', 1, mode: aiScanModeQuick);
    final controlled = _scan('controlled-later', 2, mode: aiScanModeControlled);
    final key = controlled.aiBaselineKey;

    test('never chosen implicitly (legacy fallback or after a reset)', () {
      final legacy = resolveAiBaseline(
        key: key,
        keyMatches: [quick, controlled],
        allScans: [quick, controlled],
      );
      expect(legacy.baselineScan?.id, 'controlled-later');

      final reset = resolveAiBaseline(
        key: key,
        keyMatches: [quick, controlled],
        allScans: [quick, controlled],
        registryEntryExists: true,
        resetAt: DateTime.utc(2026, 9, 30),
      );
      expect(reset.baselineScan?.id, 'controlled-later');

      final onlyQuick = resolveAiBaseline(
        key: key,
        keyMatches: [quick],
        allScans: [quick],
      );
      expect(onlyQuick.baselineScan, isNull);
    });

    test('an explicitly set quick scan is the baseline', () {
      final pinned = resolveAiBaseline(
        key: key,
        keyMatches: [quick, controlled],
        allScans: [quick, controlled],
        pinnedScanId: 'quick-first',
        registryEntryExists: true,
      );
      expect(pinned.baselineScan?.id, 'quick-first');
    });

    test('a first quick scan is not auto-registered', () {
      final source = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      final start = source.indexOf('Future<void> _registerAiBaselineIfNeeded(');
      final body = source.substring(start, start + 1600);
      expect(body, contains('if (isQuickAiScan(savedEntry)) {'));
      expect(
        body.indexOf('if (isQuickAiScan(savedEntry))'),
        lessThan(body.indexOf('AppPrefs.setAiBaselineScanId')),
      );
    });
  });

  group('lighting lock on a single-frame quick scan (existing rule)', () {
    const status = {'texture_smoothness': 'improved'};
    const deltas = {'texture_smoothness': 12.0};
    final baseline = _exposurePayload([
      for (var i = 0; i < 5; i++) (iso: 64, bv: 3.5),
    ]);

    test('matching light compares', () {
      final result = lockTrendsForLightingMismatch(
        trendStatus: status,
        trendDeltas: deltas,
        trendLockReasons: const {},
        currentPayload: _exposurePayload([(iso: 64, bv: 3.3)]),
        baselinePayload: baseline,
      );
      expect(result.trendStatus, status);
      expect(result.trendLockReasons, isEmpty);
    });

    test('Bv beyond the existing limit locks', () {
      expect(provisionalBrightnessValueMismatchLimit, 1.0);
      final result = lockTrendsForLightingMismatch(
        trendStatus: status,
        trendDeltas: deltas,
        trendLockReasons: const {},
        currentPayload: _exposurePayload([(iso: 64, bv: 5.0)]),
        baselinePayload: baseline,
      );
      expect(
        result.trendLockReasons['texture_smoothness'],
        'lighting_mismatch',
      );
      expect(result.trendStatus, isEmpty);
    });

    test('missing exposure metadata locks', () {
      final result = lockTrendsForLightingMismatch(
        trendStatus: status,
        trendDeltas: deltas,
        trendLockReasons: const {},
        currentPayload: _exposurePayload([(iso: null, bv: null)]),
        baselinePayload: baseline,
      );
      expect(
        result.trendLockReasons['texture_smoothness'],
        'lighting_mismatch',
      );
    });
  });

  group('entry point', () {
    test('controlled scan stays the default; quick scan is one frame', () {
      expect(const CameraScreen().aiQuickScan, isFalse);
      final camera = File(
        'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
      ).readAsStringSync();
      expect(
        camera,
        contains(
          'final burstFrameCount = widget.aiQuickScan ? 1 : aiScanCaptureFrameCount;',
        ),
      );
      expect(camera, contains('quickScan: widget.aiQuickScan,'));
      final scan = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      expect(scan, contains('bool _quickScanMode = false;'));
      expect(scan, contains('aiQuickScan: _quickScanMode,'));
      expect(
        scan,
        contains('backendResponse[aiScanModeKey] = _capturedScanMode;'),
      );
    });

    testWidgets('the scan screen offers both, controlled selected', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'scan_lighting_tip_seen': 'true',
      });
      await tester.binding.setSurfaceSize(const Size(390, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: SkinAiAnalysisScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Controlled scan'), findsOneWidget);
      expect(find.text('Recommended for tracking'), findsOneWidget);
      expect(find.text('Quick scan'), findsOneWidget);
      expect(find.text('Single photo, faster'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
