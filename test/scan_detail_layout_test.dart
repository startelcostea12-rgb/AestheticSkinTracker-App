import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/screens/progress_report_screen.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An AI scan carrying every optional detail the screen shows: reference
/// flags, makeup note, capture-quality rows, a long focus description and
/// a full metric matrix with trends and lock reasons.
ScanHistoryEntry _richScan(String? mode) => ScanHistoryEntry(
  id: 'rich-$mode',
  timestamp: DateTime(2026, 10, 1, 9, 30),
  scanType: ScanHistoryEntry.scanTypeAiAnalysis,
  estimatedSkinAge: 34,
  metrics: const <String, double>{
    'texture_smoothness': 59.0,
    'pigment_load': 10.2,
  },
  poseTemplate: 'Front',
  guideType: 'facial',
  focusArea:
      'Full face including forehead, glabella, both cheeks and the '
      'under-eye area after a long afternoon outdoors',
  captureQuality: 'normal',
  lightingConfidence: 0.82,
  distanceEstimate: 0.91,
  headTiltAngle: 3.4,
  expressionConfidence: 0.95,
  isBaseline: true,
  preferredReference: true,
  makeupPresent: true,
  rawPayload: <String, dynamic>{
    'metric_matrix': <String, dynamic>{
      'texture_smoothness': 59.0,
      'pigment_load': 10.2,
      'skin_tone_radiance_evenness': 31.0,
      'structural_firmness_elasticity': 50.5,
      'pore_visibility': 13.1,
      'localized_redness': 8.4,
      'wrinkle_load': 22.7,
      'under_eye_darkness': 18.0,
    },
    'baseline_metric_matrix': <String, dynamic>{
      'texture_smoothness': 55.0,
      'pigment_load': 12.0,
    },
    'trend_status': <String, dynamic>{
      'texture_smoothness': 'improved',
      'pigment_load': 'stable',
    },
    'trend_deltas': <String, dynamic>{
      'texture_smoothness': 4.0,
      'pigment_load': -1.8,
    },
    'trend_lock_reasons': <String, dynamic>{
      'wrinkle_load': 'region_position_mismatch',
      'pore_visibility': 'lighting_mismatch',
    },
    'is_follow_up': true,
    'local_history_count': 2,
    if (mode != null) aiScanModeKey: mode,
  },
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [320.0, 375.0, 400.0]) {
    for (final mode in [aiScanModeControlled, aiScanModeQuick, null]) {
      testWidgets('AI scan detail fits at ${width.toInt()}px ($mode)', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(home: ScanDetailScreen(scan: _richScan(mode))),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Scroll the whole list so every section lays out and is checked.
        final list = find.byType(Scrollable).first;
        for (var i = 0; i < 40; i++) {
          await tester.drag(list, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        // Nothing removed: badge, title and timestamp are all still shown.
        final label = mode == aiScanModeQuick
            ? 'AI Quick Scan'
            : 'AI Deep Analysis';
        await tester.drag(list, const Offset(0, 20000));
        await tester.pumpAndSettle();
        expect(find.text(label), findsWidgets);
        expect(find.text('2026-10-01 09:30:00'), findsOneWidget);
        expect(find.text('Baseline reference'), findsOneWidget);
        expect(find.text('Makeup/product noted'), findsOneWidget);
      });
    }
  }
}
