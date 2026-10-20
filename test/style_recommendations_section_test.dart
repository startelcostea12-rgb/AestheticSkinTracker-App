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

  testWidgets('free: the first $kFreeStylePicks picks and a Premium link '
      'for the rest', (tester) async {
    await _pump(tester, styles: {SkincareStyle.korean}, premium: false);
    final all = styleRecommendations({SkincareStyle.korean});
    for (final product in all.take(kFreeStylePicks)) {
      expect(find.text(product.name), findsOneWidget, reason: product.name);
    }
    for (final product in all.skip(kFreeStylePicks)) {
      expect(find.text(product.name), findsNothing, reason: product.name);
    }
    expect(
      find.text('See ${all.length - kFreeStylePicks} more picks with Premium'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('style_recs_upgrade')), findsOneWidget);
    expect(find.text(StyleRecommendationsSection.disclaimer), findsOneWidget);
  });

  testWidgets('premium: no upgrade link', (tester) async {
    await _pump(tester, styles: {SkincareStyle.korean}, premium: true);
    expect(find.byKey(const ValueKey('style_recs_upgrade')), findsNothing);
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
