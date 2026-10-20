// Main screens at narrow phone widths (320 and 375px) with realistic data:
// each screen is opened and scrolled end to end with no overflow.
import 'dart:convert';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/peptide_model.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/free_local_scan_results_screen.dart';
import 'package:aesthetic_skin_tracker/models/ai_scan_frame_exposure.dart';
import 'package:aesthetic_skin_tracker/screens/home_screen.dart';
import 'package:aesthetic_skin_tracker/screens/product_lookup_detail_screen.dart';
import 'package:aesthetic_skin_tracker/screens/routine_editor_screen.dart';
import 'package:aesthetic_skin_tracker/utils/product_lookup.dart';
import 'package:aesthetic_skin_tracker/screens/onboarding/skin_onboarding_screen.dart';
import 'package:aesthetic_skin_tracker/screens/product_lookup_screen.dart';
import 'package:aesthetic_skin_tracker/screens/progress_report_screen.dart';
import 'package:aesthetic_skin_tracker/screens/progress_summary_screen.dart';
import 'package:aesthetic_skin_tracker/screens/peptide_tracker_screen.dart';
import 'package:aesthetic_skin_tracker/screens/routines_screen.dart';
import 'package:aesthetic_skin_tracker/screens/settings_screen.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/peptide_service.dart';
import 'package:aesthetic_skin_tracker/utils/skincare_style_catalog.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:aesthetic_skin_tracker/widgets/paywall_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _matrix = <String, double>{
  'texture_smoothness': 59.0,
  'pigment_load': 10.2,
  'skin_tone_radiance_evenness': 31.0,
  'structural_firmness_elasticity': 50.5,
  'pore_visibility': 13.1,
  'localized_redness': 8.4,
  'wrinkle_load': 22.7,
  'rosacea_severity': 12.0,
  'diffuse_flushing_erythema': 14.0,
  'under_eye_dark_circle_density': 18.0,
};

ScanHistoryEntry _scan(String id, int day, {String? comparedWith}) =>
    ScanHistoryEntry(
      id: id,
      timestamp: DateTime(2026, 10, day, 9, 30),
      scanType: ScanHistoryEntry.scanTypeAiAnalysis,
      estimatedSkinAge: 34,
      metrics: _matrix,
      poseTemplate: 'Front',
      guideType: 'facial',
      focusArea: 'Full face',
      procedure: 'AI Skin Analysis',
      captureQuality: 'normal',
      lightingConfidence: 0.8,
      rawPayload: <String, dynamic>{
        'metric_matrix': {..._matrix},
        'baseline_metric_matrix': comparedWith == null ? null : {..._matrix},
        'trend_status': {'texture_smoothness': 'improved'},
        'trend_lock_reasons': {'pigment_load': 'lighting_mismatch'},
        aiComparisonBaselineScanIdKey: comparedWith,
      },
    );

Future<void> _seed() async {
  SharedPreferences.setMockInitialValues({
    AppPrefs.scanHistoryKey: jsonEncode([
      _scan('base', 1).toJson(),
      _scan('later', 2, comparedWith: 'base').toJson(),
    ]),
    AppPrefs.activeAiRoutineKey: jsonEncode({
      'id': 'r1',
      'source': 'manual',
      'generatedAt': '2026-10-01T09:00:00.000',
      'morningSteps': [
        'Gentle hydrating cleanser',
        'Vitamin C serum 15%',
        'Mineral SPF 50',
      ],
      'eveningSteps': [
        'Cleansing balm',
        'Retinol 0.3% night serum',
        'Barrier cream',
      ],
      'notes': 'Started retinol Oct 1',
    }),
    skincareStylePreferenceKey: jsonEncode([
      for (final s in SkincareStyle.values) s.id,
    ]),
  });
  final stack = await PeptideService.createStack(
    'Collagen & Firmness Evening Stack',
  );
  for (final (i, lib) in kPeptideLibrary.take(3).indexed) {
    await PeptideService.upsert(
      PeptideEntry(
        id: 'p$i',
        name: lib.name,
        concentration: 2.5,
        frequency: 'Once daily',
        startDate: DateTime(2026, 9, 1),
        notes: 'Benefits: ${lib.primaryMetrics.join(', ')}',
        category: lib.category,
        stackId: i < 2 ? stack.id : null,
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the screen top to bottom, failing on any layout exception
/// (overflow) along the way.
Future<void> _scrollAll(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  for (var i = 0; i < 25; i++) {
    final s = find.byType(Scrollable);
    if (s.evaluate().isEmpty) return;
    await tester.drag(s.first, const Offset(0, -300), warnIfMissed: false);
    await _settle(tester);
    expect(tester.takeException(), isNull);
  }
}

void main() {
  final screens = <String, Widget Function()>{
    'home': () => const HomePage(),
    'history': () => const ProgressReportScreen(),
    'routines': () => const RoutinesScreen(),
    'settings': () => const SettingsScreen(),
    'peptides0': () => const PeptideTrackerScreen(initialTab: 0),
    'peptides1': () => const PeptideTrackerScreen(initialTab: 1),
    'peptides2': () => const PeptideTrackerScreen(initialTab: 2),
    'peptides3': () => const PeptideTrackerScreen(initialTab: 3),
    'lookup': () => const ProductLookupScreen(),
    'summary': () => const ProgressSummaryScreen(),
    'paywall': () => const PaywallScreen(),
    'onboarding': () => const SkinOnboardingScreen(),
    'scan': () => const SkinAiAnalysisScreen(),
    'productDetail': () => const ProductLookupDetailScreen(
      product: LookupProduct(
        name:
            'La Roche-Posay Toleriane Double Repair Face Moisturizer UV SPF 30',
        brand: 'La Roche-Posay, L\'Oréal Dermatological Beauty',
        barcode: '3337875597197',
        ingredients: ['Aqua', 'Glycerin', 'Niacinamide', 'Ceramide NP'],
        source: LookupSource.openBeautyFacts,
      ),
    ),
    'freeResults': () => FreeLocalScanResultsScreen(
      summary: FreeLocalScanSummary.fromLocal(
        faceFound: true,
        faceCoverage: 0.42,
        symmetryScore: 0.91,
        captureQuality: 'Good framing, slight tilt',
        hasBaseline: true,
        lightingCheck: (
          wouldLock: true,
          missingExposure: false,
          currentBrightnessValue: 3.1,
          baselineBrightnessValue: 5.0,
        ),
        frames: const [
          AiScanFrameExposure(iso: 64, brightnessValue: 3.05),
          AiScanFrameExposure(iso: 800, brightnessValue: 3.2),
        ],
        scansUsed: 3,
      ),
    ),
    'routineEditor': () => const RoutineEditorScreen(
      initialRoutine: {
        'morningSteps': ['Gentle hydrating cleanser', 'Vitamin C serum 15%'],
        'eveningSteps': <String>[],
      },
    ),
    'results': () => Scaffold(
      body: SingleChildScrollView(
        child: LuxeReportLayout(
          rawPayload: {
            'is_follow_up': true,
            'local_history_count': 2,
            'metric_matrix': const {..._matrix},
            'baseline_metric_matrix': {..._matrix, 'texture_smoothness': 50.0},
            'metric_extraction_paths': {
              for (final k in _matrix.keys) k: 'primary_roi',
            },
            'baseline_metric_extraction_paths': {
              for (final k in _matrix.keys) k: 'primary_roi',
            },
            'trend_status': const {'texture_smoothness': 'improved'},
            'trend_deltas': const {'texture_smoothness': 18.0},
            'trend_lock_reasons': const {'pigment_load': 'lighting_mismatch'},
          },
          requireBackendVerdict: true,
          applyDisplayNoiseFloors: true,
        ),
      ),
    ),
  };
  for (final width in [320.0, 375.0]) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} fits at ${width.toInt()}px', (tester) async {
        await _seed();
        await tester.binding.setSurfaceSize(Size(width, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: entry.value()));
        await _settle(tester);
        await _scrollAll(tester);
      });
    }
  }
}
