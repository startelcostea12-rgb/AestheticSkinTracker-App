import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reset removes the old comparison id but preserves historical rows', () {
    final historical = <String, dynamic>{
      aiComparisonBaselineScanIdKey: 'oct27-id',
      aiComparisonBaselineSourceKey: 'registry',
      'metric_matrix': {'localized_redness': 8.0},
      'imagePath': 'saved-photo.jpg',
      'baseline_metric_matrix': {'localized_redness': 4.0},
      'trend_status': {'localized_redness': 'worsened'},
      'metrics': {
        aiComparisonBaselineScanIdKey: 'oct27-id',
        'metric_matrix': {'localized_redness': 8.0},
      },
    };
    final cleared = clearAiComparisonBaselineForReset(historical);
    expect(cleared[aiComparisonBaselineScanIdKey], isNull);
    expect(cleared[aiComparisonBaselineSourceKey], isNull);
    expect((cleared['metrics'] as Map)[aiComparisonBaselineScanIdKey], isNull);
    expect(cleared.containsKey('baseline_metric_matrix'), isFalse);
    expect(cleared.containsKey('trend_status'), isFalse);
    expect(cleared['metric_matrix'], historical['metric_matrix']);
    expect(cleared['imagePath'], 'saved-photo.jpg');
    expect(historical[aiComparisonBaselineScanIdKey], 'oct27-id');
    expect(
      (historical['metrics'] as Map)[aiComparisonBaselineScanIdKey],
      'oct27-id',
    );
  });

  test(
    'reset persists a marker and the next comparison cannot use Oct 27',
    () async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      const key = (
        procedureId: null,
        focusArea: 'full_face',
        poseTemplate: 'front',
        guideType: 'facial',
      );
      final oldScan = ScanHistoryEntry(
        id: 'oct27-id',
        timestamp: DateTime.utc(2026, 10, 27),
        estimatedSkinAge: 0,
        metrics: const {'localized_redness': 4.0},
        focusArea: 'Full Face',
        poseTemplate: 'Front',
        guideType: 'facial',
        captureQuality: 'normal',
        rawPayload: const {
          'metric_extraction_paths': {'localized_redness': 'primary_roi'},
          'metric_formula_versions': {'localized_redness': 4},
        },
      );
      await AppPrefs.setAiBaselineScanId(key, oldScan.id);
      await AppPrefs.clearAiBaselineScanId(
        key,
        resetAt: DateTime.utc(2026, 11, 3),
      );
      final state = await AppPrefs.getAiBaselineRegistryState(key);
      expect(state.baselineScanId, isNull);
      expect(state.isResetPending, isTrue);
      final resolution = resolveAiBaseline(
        key: key,
        keyMatches: [oldScan],
        allScans: [oldScan],
        pinnedScanId: state.baselineScanId,
        registryEntryExists: state.hasEntry,
        resetAt: state.resetAt,
      );
      expect(resolution.baselineScan, isNull);
      expect(resolution.shouldPinResolvedBaseline, isFalse);
      final nextPayload = <String, dynamic>{};
      recordAiComparisonBaseline(
        nextPayload,
        baselineScanId: resolution.baselineScan?.id,
        registryScanId: state.baselineScanId,
      );
      expect(nextPayload[aiComparisonBaselineScanIdKey], isNull);
      expect(await AppPrefs.getAllAiBaselineScanIds(), isEmpty);
    },
  );

  test(
    'Reset Baseline clears cached comparison references without auto-picking',
    () {
      final source = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      final start = source.indexOf(
        'Future<void> _handleBaselineReset() async {',
      );
      final end = source.indexOf(
        'Future<void> _showResetConfirmationDialog(',
        start,
      );
      final reset = source.substring(start, end);
      for (final field in [
        '_previousFocusAreaScan',
        '_baselineFocusAreaScan',
        '_aiBaselineRegistryScanId',
      ]) {
        expect(reset, contains('$field = null;'));
      }
      expect(reset, contains('AppPrefs.clearAiBaselineScanId(key)'));
      expect(reset, contains('clearAiComparisonBaselineForReset('));
      expect(reset, isNot(contains('setAiBaselineScanId')));
      expect(reset, isNot(contains('_getPreviousMetrics')));
    },
  );
}
