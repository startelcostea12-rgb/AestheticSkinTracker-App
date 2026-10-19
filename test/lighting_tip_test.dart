import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/widgets/lighting_tip_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first visit shows the tip; dismissing it keeps it away', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SkinAiAnalysisScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Recommended lighting'), findsOneWidget);
    expect(
      find.textContaining('daylight (neutral white) lamp'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('lighting_tip_dismiss')),
    );
    await tester.tap(find.byKey(const ValueKey('lighting_tip_dismiss')));
    await tester.pump();
    expect(find.text('Recommended lighting'), findsNothing);
    expect(await AppPrefs.getString(lightingTipSeenKey), 'true');

    // Next visit: not shown again.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: SkinAiAnalysisScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Recommended lighting'), findsNothing);
  });

  test('the tip is capture guidance only, no medical claims', () {
    expect(LightingTipCard.tips, hasLength(4));
    final text = LightingTipCard.tips.join(' ').toLowerCase();
    for (final word in ['treat', 'cure', 'diagnos', 'heal', 'clinical']) {
      expect(text, isNot(contains(word)), reason: word);
    }
    expect(text, contains('daylight'));
  });
}
