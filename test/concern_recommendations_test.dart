import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/screens/product_lookup_detail_screen.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/ai_product_recommendation_engine.dart';
import 'package:aesthetic_skin_tracker/utils/concern_recommendations.dart';
import 'package:aesthetic_skin_tracker/widgets/concern_recommendations_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _calm = <String, double>{
  'texture_smoothness': 59.0, // texture concern 4.1
  'pigment_load': 10.2,
  'skin_tone_radiance_evenness': 31.0,
  'structural_firmness_elasticity': 50.5,
  'pore_visibility': 13.1,
  'localized_redness': 8.4,
};

ScanHistoryEntry _scan(
  String id,
  int day, {
  String? comparedWith,
  Map<String, double> values = _calm,
}) => ScanHistoryEntry(
  id: id,
  timestamp: DateTime(2026, 10, day, 9, 30),
  scanType: ScanHistoryEntry.scanTypeAiAnalysis,
  estimatedSkinAge: 0,
  metrics: const <String, double>{},
  poseTemplate: 'Front',
  guideType: 'facial',
  rawPayload: <String, dynamic>{
    'metric_matrix': <String, dynamic>{...values},
    aiComparisonBaselineScanIdKey: comparedWith,
  },
);

/// Baseline plus a follow-up compared with it.
List<ScanHistoryEntry> _comparable(Map<String, double> latest) => [
  _scan('base', 1),
  _scan('later', 2, comparedWith: 'base', values: {..._calm, ...latest}),
];

Future<void> _pump(
  WidgetTester tester,
  List<ScanHistoryEntry> scans, {
  bool premium = false,
  ConcernProductSource? productsFor,
}) async {
  await tester.binding.setSurfaceSize(const Size(375, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: productsFor == null
              ? ConcernRecommendationsSection(
                  scans: scans,
                  isPremium: () async => premium,
                )
              : ConcernRecommendationsSection(
                  scans: scans,
                  isPremium: () async => premium,
                  productsFor: productsFor,
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('grouping', () {
    test('elevated redness gives a "For your redness" group from the '
        'engine product list', () {
      final groups = concernGroupsForScans(
        _comparable({'localized_redness': 72.0}),
      )!;
      expect(groups.map((g) => g.concern.heading), ['For your redness']);
      final engine = AIProductRecommendationEngine.productsForConcern(
        'redness',
        7.2,
      );
      expect(
        groups.single.products.map((p) => p.productName),
        engine.map((p) => p.productName),
      );
      expect(groups.single.products, isNotEmpty);
    });

    test('uses the existing > 6.0 cutoff on the engine scale; texture is '
        'inverted smoothness', () {
      // 60 is not above the cutoff; 61 is.
      expect(
        concernGroupsForScans(_comparable({'pigment_load': 60.0})),
        isEmpty,
      );
      final groups = concernGroupsForScans(
        _comparable({
          'pigment_load': 61.0,
          'texture_smoothness': 20.0, // concern 8.0
          'pore_visibility': 65.0,
        }),
      )!;
      // Most elevated first.
      expect(groups.map((g) => g.concern.heading), [
        'For your texture',
        'For your pores',
        'For your pigment',
      ]);
    });

    test('concerns with no matching products create no group', () {
      final groups = concernGroupsForScans(
        _comparable({'localized_redness': 80.0, 'pore_visibility': 80.0}),
        productsFor: (key, level) => key == 'pores'
            ? const []
            : AIProductRecommendationEngine.productsForConcern(key, level),
      )!;
      expect(groups.map((g) => g.concern.engineKey), ['redness']);
    });

    test('no comparable scan gives null', () {
      expect(concernGroupsForScans(const []), isNull);
      // A lone scan has no baseline to be comparable with.
      expect(
        concernGroupsForScans([
          _scan('only', 1, values: {..._calm, 'localized_redness': 90.0}),
        ]),
        isNull,
      );
    });

    test('engine productsForConcern puts its metric-based pick first and '
        'keeps every listed product', () {
      for (final key in ['redness', 'darkSpots', 'texture', 'pores']) {
        final high = AIProductRecommendationEngine.productsForConcern(key, 9);
        final mid = AIProductRecommendationEngine.productsForConcern(key, 6);
        expect(high, hasLength(3), reason: key);
        expect(
          high.map((p) => p.productName).toSet(),
          mid.map((p) => p.productName).toSet(),
          reason: key,
        );
      }
      expect(
        AIProductRecommendationEngine.productsForConcern('nope', 9),
        isEmpty,
      );
    });
  });

  group('section', () {
    testWidgets('elevated redness shows the redness group; free users get '
        'one product per concern and an upgrade prompt', (tester) async {
      await _pump(tester, _comparable({'localized_redness': 72.0}));
      expect(find.text('For your redness'), findsOneWidget);
      expect(find.text('For your pores'), findsNothing);
      expect(find.text('For your pigment'), findsNothing);
      expect(find.text('For your texture'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'concern_product_redness_',
              ),
        ),
        findsOneWidget,
      );
      expect(find.text('See 2 more picks with Premium'), findsOneWidget);
    });

    testWidgets('premium users see the full list per concern', (tester) async {
      await _pump(
        tester,
        _comparable({'localized_redness': 72.0}),
        premium: true,
      );
      final names = AIProductRecommendationEngine.productsForConcern(
        'redness',
        7.2,
      ).map((p) => p.productName);
      for (final name in names) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.byKey(const ValueKey('concern_recs_upgrade')), findsNothing);
    });

    testWidgets('a concern without products shows no empty heading', (
      tester,
    ) async {
      await _pump(
        tester,
        _comparable({'pore_visibility': 80.0}),
        productsFor: (key, level) => const [],
      );
      expect(find.text('For your pores'), findsNothing);
      expect(
        find.byKey(const ValueKey('concern_recs_none_elevated')),
        findsOneWidget,
      );
    });

    testWidgets('no comparable scan shows the empty-state message', (
      tester,
    ) async {
      await _pump(tester, [_scan('only', 1)]);
      expect(
        find.text(ConcernRecommendationsSection.noComparableText),
        findsOneWidget,
      );
      for (final concern in skinConcerns) {
        expect(find.text(concern.heading), findsNothing);
      }
    });

    testWidgets('nothing elevated says so', (tester) async {
      await _pump(tester, _comparable(const {}));
      expect(
        find.text(ConcernRecommendationsSection.noneElevatedText),
        findsOneWidget,
      );
    });

    testWidgets('tapping a product opens the lookup detail with its name, '
        'brand and stored description', (tester) async {
      await _pump(tester, _comparable({'localized_redness': 72.0}));
      final pick = AIProductRecommendationEngine.productsForConcern(
        'redness',
        7.2,
      ).first;
      await tester.tap(find.text(pick.productName));
      await tester.pumpAndSettle();
      expect(find.byType(ProductLookupDetailScreen), findsOneWidget);
      expect(find.text('Brand: ${pick.brand}'), findsOneWidget);
      expect(find.text(pick.clinicalReason), findsOneWidget);
      expect(
        find.byKey(const ValueKey('product_save_for_later')),
        findsOneWidget,
      );
    });
  });
}
