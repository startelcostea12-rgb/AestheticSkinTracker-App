import 'dart:convert';

import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/screens/home_screen.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/skincare_style_catalog.dart';
import 'package:aesthetic_skin_tracker/widgets/concern_recommendations_section.dart';
import 'package:aesthetic_skin_tracker/widgets/home_routine_card.dart';
import 'package:aesthetic_skin_tracker/widgets/last_comparable_pair_card.dart';
import 'package:aesthetic_skin_tracker/widgets/style_recommendations_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScanHistoryEntry _scan(String id, int day, {String? comparedWith}) =>
    ScanHistoryEntry(
      id: id,
      timestamp: DateTime(2026, 10, day, 9, 30),
      scanType: ScanHistoryEntry.scanTypeAiAnalysis,
      estimatedSkinAge: 0,
      metrics: const <String, double>{'texture_smoothness': 59.0},
      poseTemplate: 'Front',
      guideType: 'facial',
      focusArea: 'Full face',
      rawPayload: <String, dynamic>{
        'metric_matrix': <String, dynamic>{
          'texture_smoothness': 59.0, // texture concern 41: one group
          'pigment_load': 10.2,
          'skin_tone_radiance_evenness': 31.0,
          'structural_firmness_elasticity': 50.5,
          'pore_visibility': 13.1,
          'localized_redness': 8.4,
        },
        aiComparisonBaselineScanIdKey: comparedWith,
      },
    );

Future<void> _pumpHome(
  WidgetTester tester,
  double width, {
  bool withData = true,
}) async {
  SharedPreferences.setMockInitialValues({
    if (withData) ...{
      AppPrefs.scanHistoryKey: jsonEncode([
        _scan('base', 1).toJson(),
        _scan('later', 2, comparedWith: 'base').toJson(),
      ]),
      AppPrefs.activeAiRoutineKey: jsonEncode({
        'id': 'r1',
        'source': 'manual',
        'morningSteps': ['Gentle cleanser', 'Vitamin C serum', 'SPF 50'],
        'eveningSteps': ['Cleansing balm', 'Night cream'],
      }),
      skincareStylePreferenceKey: jsonEncode([
        for (final style in SkincareStyle.values) style.id,
      ]),
    },
  });
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: HomePage()));
  await tester.pumpAndSettle();
}

/// Scrolls the home column end to end, failing on any layout exception.
Future<void> _scrollThrough(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 30; i++) {
    await tester.drag(scrollable, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  for (final width in [320.0, 375.0]) {
    testWidgets('home fits at ${width.toInt()}px with every new section', (
      tester,
    ) async {
      await _pumpHome(tester, width);
      expect(find.byType(LastComparablePairCard), findsOneWidget);
      expect(find.byType(HomeRoutineCard), findsOneWidget);
      expect(find.text('For your texture'), findsOneWidget);
      expect(find.byType(StyleRecommendationsSection), findsOneWidget);
      await _scrollThrough(tester);
    });
  }

  testWidgets('home fits at 320px with empty states', (tester) async {
    await _pumpHome(tester, 320, withData: false);
    expect(find.byType(HomeRoutineCard), findsNothing);
    expect(
      find.text(ConcernRecommendationsSection.noComparableText),
      findsOneWidget,
    );
    await _scrollThrough(tester);
  });
}
