import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/product_lookup.dart';
import 'package:aesthetic_skin_tracker/utils/skincare_style_catalog.dart';
import 'package:aesthetic_skin_tracker/utils/style_concern_recommendations.dart';
import 'package:aesthetic_skin_tracker/widgets/style_recommendations_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _calm = <String, double>{
  'texture_smoothness': 80.0, // texture concern 20
  'pigment_load': 10.0,
  'pore_visibility': 13.0,
  'localized_redness': 8.0,
};

ScanHistoryEntry _scan(Map<String, double> values, {int day = 2}) =>
    ScanHistoryEntry(
      id: 's$day',
      timestamp: DateTime(2026, 10, day, 9),
      scanType: ScanHistoryEntry.scanTypeAiAnalysis,
      estimatedSkinAge: 0,
      metrics: const {},
      poseTemplate: 'Front',
      guideType: 'facial',
      rawPayload: {
        'metric_matrix': {..._calm, ...values},
        aiComparisonBaselineScanIdKey: null,
      },
    );

List<StyleProduct> get _all => [
  for (final list in skincareStyleCatalog.values) ...list,
];

Future<void> _pump(
  WidgetTester tester, {
  required Set<SkincareStyle> styles,
  required bool premium,
  List<ScanHistoryEntry> scans = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StyleRecommendationsSection(
            loadStyles: () async => styles,
            isPremium: () async => premium,
            scans: scans,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('catalog', () {
    test('every product has a brand, category and known concern tags', () {
      expect(_all, hasLength(70));
      expect(
        _all.map((p) => p.name).toSet(),
        hasLength(_all.length),
        reason: 'no duplicate products',
      );
      for (final p in _all) {
        expect(p.brand, isNotEmpty, reason: p.name);
        // The product lookup shows the catalog's brand; the name-prefix
        // fallback never disagrees with it.
        expect(productNamed(p.name)?.brand, p.brand, reason: p.name);
        final prefixBrand = brandForProductName(p.name);
        if (prefixBrand != null) {
          expect(prefixBrand, p.brand, reason: p.name);
        }
        expect(p.reason, p.description, reason: p.name);
        expect(
          styleConcernTags.containsAll(p.concerns),
          isTrue,
          reason: p.name,
        );
      }
      expect(
        _all.map((p) => p.category).toSet(),
        StyleProductCategory.values.toSet(),
      );
    });

    test('style preference saves and loads', () async {
      await saveSkincareStyles({SkincareStyle.korean, SkincareStyle.clinical});
      expect(await loadSkincareStyles(), {
        SkincareStyle.korean,
        SkincareStyle.clinical,
      });
    });
  });

  group('current concerns from the latest scan', () {
    test('elevated concerns as style tags, most elevated first', () {
      expect(
        currentStyleConcernTags([
          _scan({
            'texture_smoothness': 59.0, // 41
            'pore_visibility': 30.0,
            'localized_redness': 26.0,
          }),
        ]),
        ['texture', 'pores', 'redness'],
      );
    });

    test('same cutoff as "For your concerns": 25 is not elevated', () {
      expect(
        currentStyleConcernTags([
          _scan({'pigment_load': 25.0}),
        ]),
        isEmpty,
      );
      expect(
        currentStyleConcernTags([
          _scan({'pigment_load': 26.0}),
        ]),
        ['pigment'],
      );
    });

    test('no scans or nothing elevated: none', () {
      expect(currentStyleConcernTags(const []), isEmpty);
      expect(currentStyleConcernTags([_scan(const {})]), isEmpty);
    });
  });

  group('filtering', () {
    test('matching products first, topped up to 4 with general picks', () {
      final picks = stylePicksFor({SkincareStyle.korean}, ['redness']);
      expect(picks.isFallback, isFalse);
      expect(picks.matchedConcerns, ['redness']);
      expect(picks.products, hasLength(4));
      expect(picks.products.take(2).map((p) => p.name), [
        'Anua Heartleaf 77% Soothing Toner',
        'Purito Centella Unscented Serum',
      ]);
      expect(picks.products.toSet(), hasLength(4), reason: 'no duplicates');
    });

    test('ordered by the most elevated concern, at most 6', () {
      final picks = stylePicksFor(
        {SkincareStyle.clinical},
        ['pigment', 'texture'],
      );
      expect(picks.products, hasLength(6));
      for (final p in picks.products.take(3)) {
        expect(p.concerns, contains('pigment'), reason: p.name);
      }
      for (final p in picks.products) {
        expect(
          p.concerns.any(['pigment', 'texture'].contains),
          isTrue,
          reason: p.name,
        );
      }
      expect(picks.matchedConcerns, ['pigment', 'texture']);
    });

    test('several styles keep both represented among matches', () {
      final picks = stylePicksFor(
        {SkincareStyle.korean, SkincareStyle.westernDrugstore},
        ['pores'],
      );
      expect(picks.products.take(2).map((p) => p.style).toSet(), {
        SkincareStyle.korean,
        SkincareStyle.westernDrugstore,
      });
    });

    test('every style has products for every scan concern', () {
      for (final style in SkincareStyle.values) {
        for (final tag in styleTagForScanConcern.values) {
          expect(
            skincareStyleCatalog[style]!.any((p) => p.concerns.contains(tag)),
            isTrue,
            reason: '${style.label} / $tag',
          );
        }
      }
    });

    test('nothing elevated (or no matching tag) falls back to the general '
        'style picks', () {
      final picks = stylePicksFor({SkincareStyle.clinical}, const []);
      expect(picks.isFallback, isTrue);
      expect(
        picks.products.map((p) => p.name),
        styleRecommendations({
          SkincareStyle.clinical,
        }, limit: 6).map((p) => p.name),
      );
      // A tag no product carries also falls back.
      expect(
        stylePicksFor({SkincareStyle.korean}, ['not_a_tag']).isFallback,
        isTrue,
      );
    });
  });

  group('section', () {
    testWidgets('premium with an elevated concern shows matched picks', (
      tester,
    ) async {
      await _pump(
        tester,
        styles: {SkincareStyle.westernDrugstore},
        premium: true,
        scans: [
          _scan({'texture_smoothness': 59.0}),
        ],
      );
      expect(
        find.text('Matched to your texture from your latest scan.'),
        findsOneWidget,
      );
      // The texture products are listed first, with brand and category.
      expect(
        find.text('Paula’s Choice 2% BHA Liquid Exfoliant'),
        findsOneWidget,
      );
      expect(find.text('Paula’s Choice · Treatment'), findsOneWidget);
      expect(
        find.text('Neutrogena Rapid Wrinkle Repair Retinol'),
        findsOneWidget,
      );
    });

    testWidgets('premium with nothing elevated shows the general picks', (
      tester,
    ) async {
      await _pump(
        tester,
        styles: {SkincareStyle.korean},
        premium: true,
        scans: [_scan(const {})],
      );
      expect(
        find.text(StyleRecommendationsSection.generalPicksText),
        findsOneWidget,
      );
      for (final p in skincareStyleCatalog[SkincareStyle.korean]!.take(6)) {
        expect(find.text(p.name), findsOneWidget, reason: p.name);
      }
    });

    testWidgets('free users see the locked card, even with a match', (
      tester,
    ) async {
      await _pump(
        tester,
        styles: {SkincareStyle.westernDrugstore},
        premium: false,
        scans: [
          _scan({'texture_smoothness': 59.0}),
        ],
      );
      expect(find.byKey(const ValueKey('style_recs_locked')), findsOneWidget);
      expect(find.byKey(const ValueKey('style_recs_list')), findsNothing);
      expect(find.text('Paula’s Choice 2% BHA Liquid Exfoliant'), findsNothing);
    });

    for (final width in [320.0, 375.0]) {
      testWidgets('fits at ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StyleRecommendationsSection(
                  loadStyles: () async => SkincareStyle.values.toSet(),
                  isPremium: () async => true,
                  scans: [
                    _scan({'texture_smoothness': 40.0, 'pigment_load': 30.0}),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
