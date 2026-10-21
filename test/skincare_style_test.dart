import 'package:aesthetic_skin_tracker/screens/onboarding_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/skincare_style_catalog.dart';
import 'package:aesthetic_skin_tracker/widgets/skincare_style_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('preference', () {
    test('saved and loaded; unknown ids ignored', () async {
      expect(await loadSkincareStyles(), isEmpty);
      await saveSkincareStyles({SkincareStyle.clinical, SkincareStyle.korean});
      expect(await loadSkincareStyles(), {
        SkincareStyle.korean,
        SkincareStyle.clinical,
      });
      expect(
        await AppPrefs.getString(skincareStylePreferenceKey),
        '["korean","clinical"]',
      );
      await AppPrefs.setString(
        skincareStylePreferenceKey,
        '["natural_clean","not_a_style"]',
      );
      expect(await loadSkincareStyles(), {SkincareStyle.naturalClean});
      await saveSkincareStyles({});
      expect(await loadSkincareStyles(), isEmpty);
    });
  });

  group('catalog and recommendations', () {
    test('curated products per style: the original ten first, then the '
        'added ones', () {
      const counts = {
        SkincareStyle.korean: 43,
        SkincareStyle.naturalClean: 44,
        SkincareStyle.westernDrugstore: 43,
        SkincareStyle.clinical: 43,
      };
      for (final style in SkincareStyle.values) {
        final list = skincareStyleCatalog[style]!;
        expect(list, hasLength(counts[style]), reason: style.label);
        expect(list.every((p) => p.style == style), isTrue);
      }
      expect(
        skincareStyleCatalog[SkincareStyle.korean]!.first.name,
        'COSRX Advanced Snail 96 Mucin Power Essence',
      );
      // The original tenth Clinical product is still in place.
      expect(
        skincareStyleCatalog[SkincareStyle.clinical]![9].description,
        'Vitamin C serum',
      );
      expect(
        skincareStyleCatalog[SkincareStyle.clinical]!.last.name,
        'Neocutis Bio-Serum Firm',
      );
    });

    test('one style: its own top products in order', () {
      final picks = styleRecommendations({SkincareStyle.westernDrugstore});
      expect(picks, hasLength(8));
      expect(
        picks.every((p) => p.style == SkincareStyle.westernDrugstore),
        isTrue,
      );
      expect(picks.first.name, 'CeraVe Moisturizing Cream');
    });

    test('several styles: mixed one per style at a time', () {
      final picks = styleRecommendations({
        SkincareStyle.clinical,
        SkincareStyle.korean,
      }, limit: 6);
      expect(
        [for (final p in picks) p.style],
        [
          SkincareStyle.korean,
          SkincareStyle.clinical,
          SkincareStyle.korean,
          SkincareStyle.clinical,
          SkincareStyle.korean,
          SkincareStyle.clinical,
        ],
      );
      expect(picks[0].name, 'COSRX Advanced Snail 96 Mucin Power Essence');
      expect(picks[1].name, 'SkinCeuticals C E Ferulic');
      expect(styleRecommendations(const {}), isEmpty);
    });
  });

  testWidgets('onboarding asks the style question and saves the answer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: OnboardingFlowScreen()));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Nicole');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('What type of skincare do you prefer?'), findsOneWidget);
    expect(find.text('STEP 2 OF 3'), findsOneWidget);
    for (final label in const [
      'Korean',
      'Natural / Clean',
      'Western / Drugstore',
      'Clinical',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.byKey(const ValueKey('style_chip_korean')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('style_chip_clinical')));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(await loadSkincareStyles(), {
      SkincareStyle.korean,
      SkincareStyle.clinical,
    });
    expect(find.text('STEP 3 OF 3'), findsOneWidget);
  });

  testWidgets('the preference can be changed later in Settings', (
    tester,
  ) async {
    await saveSkincareStyles({SkincareStyle.korean});
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SkincareStyleSettingsTile())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Korean'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings_skincare_style')));
    await tester.pumpAndSettle();
    expect(find.text('What type of skincare do you prefer?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('style_chip_korean')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('style_chip_natural_clean')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('style_settings_save')));
    await tester.pumpAndSettle();

    expect(await loadSkincareStyles(), {SkincareStyle.naturalClean});
    expect(find.text('Natural / Clean'), findsOneWidget);
  });
}
