import 'dart:io';

import 'package:aesthetic_skin_tracker/utils/skincare_style_catalog.dart';
import 'package:aesthetic_skin_tracker/widgets/style_recommendations_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Set<SkincareStyle> styles,
  required bool premium,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StyleRecommendationsSection(
            loadStyles: () async => styles,
            isPremium: () async => premium,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('premium: products from the selected style', (tester) async {
    await _pump(tester, styles: {SkincareStyle.korean}, premium: true);
    expect(find.text('Recommended for your style'), findsOneWidget);
    expect(find.byKey(const ValueKey('style_recs_list')), findsOneWidget);
    for (final product in skincareStyleCatalog[SkincareStyle.korean]!.take(8)) {
      expect(find.text(product.name), findsOneWidget, reason: product.name);
    }
    expect(find.text('CeraVe Moisturizing Cream'), findsNothing);
    expect(find.text(StyleRecommendationsSection.disclaimer), findsOneWidget);
  });

  testWidgets('premium: several styles are mixed', (tester) async {
    await _pump(
      tester,
      styles: {SkincareStyle.naturalClean, SkincareStyle.clinical},
      premium: true,
    );
    for (final name in const [
      'Youth To The People Superfood Cleanser',
      'SkinCeuticals C E Ferulic',
      'Biossance Squalane + Omega Repair Cream',
      'SkinCeuticals Triple Lipid Restore',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.textContaining('· Natural / Clean'), findsNWidgets(4));
    expect(find.textContaining('· Clinical'), findsNWidgets(4));
  });

  testWidgets('free: locked card with an upgrade prompt, no picks', (
    tester,
  ) async {
    await _pump(tester, styles: {SkincareStyle.korean}, premium: false);
    expect(find.byKey(const ValueKey('style_recs_locked')), findsOneWidget);
    expect(
      find.text('Curated picks for Korean are part of Premium.'),
      findsOneWidget,
    );
    // Same lock-icon link style as the concerns section's "See N more".
    final link = find.byKey(const ValueKey('style_recs_upgrade'));
    expect(
      find.descendant(
        of: link,
        matching: find.text('See your style picks with Premium'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: link,
        matching: find.byIcon(Icons.lock_outline_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('style_recs_list')), findsNothing);
    for (final product in skincareStyleCatalog[SkincareStyle.korean]!) {
      expect(find.text(product.name), findsNothing, reason: product.name);
    }
    expect(find.textContaining('more pick'), findsNothing);
  });

  testWidgets('premium: full list, no locked card or upsell', (tester) async {
    await _pump(tester, styles: {SkincareStyle.korean}, premium: true);
    final all = styleRecommendations({SkincareStyle.korean});
    for (final product in all) {
      expect(find.text(product.name), findsOneWidget, reason: product.name);
    }
    expect(find.byKey(const ValueKey('style_recs_locked')), findsNothing);
    expect(find.byKey(const ValueKey('style_recs_upgrade')), findsNothing);
    expect(
      find.text(StyleRecommendationsSection.lockedLinkLabel),
      findsNothing,
    );
    expect(find.textContaining('with Premium'), findsNothing);
  });

  testWidgets('no style chosen: a prompt instead of products', (tester) async {
    await _pump(tester, styles: const {}, premium: true);
    expect(find.byKey(const ValueKey('style_recs_no_style')), findsOneWidget);
    expect(find.byKey(const ValueKey('style_recs_list')), findsNothing);
  });

  test('shown on home; metric-based engine left alone', () {
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(home, contains('const StyleRecommendationsSection(),'));
    // The metric-based recommendations are still on home, unchanged.
    expect(home, contains('ScanBasedRecommendationsCard('));
    final engine = File(
      'lib/utils/ai_product_recommendation_engine.dart',
    ).readAsStringSync();
    expect(engine, isNot(contains('skincare_style')));
  });
}
