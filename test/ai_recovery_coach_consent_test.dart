import 'package:aesthetic_skin_tracker/screens/ai_recovery_coach_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/premium_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PremiumAccess.debugTesterPremiumUnlockOverride = true;
  });

  tearDown(() {
    PremiumAccess.debugTesterPremiumUnlockOverride = null;
  });

  Future<void> pumpCoachScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Avoid pumpAndSettle: the loading/consent-pending state uses a
    // continuously repeating animation that never settles.
    await tester.pumpWidget(const MaterialApp(home: AIRecoveryCoachScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
    'shows the consent dialog on first use and unlocks chat on accept',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await pumpCoachScreen(tester);

      expect(find.text('Before you chat with AI Coach'), findsOneWidget);
      expect(find.textContaining('Gemini API'), findsOneWidget);

      await tester.tap(find.text('Accept & Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Before you chat with AI Coach'), findsNothing);
      expect(await AppPrefs.getAiCoachConsent(), isTrue);
    },
  );

  testWidgets(
    'system back does not dismiss the consent dialog',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await pumpCoachScreen(tester);

      expect(find.text('Before you chat with AI Coach'), findsOneWidget);

      // Simulates the Android system back button/gesture, which routes
      // through PopScope exactly like a hardware back press would.
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Before you chat with AI Coach'), findsOneWidget);
    },
  );

  testWidgets(
    'declining consent blocks AI Coach and explains why',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await pumpCoachScreen(tester);

      await tester.tap(find.text('Decline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('AI Coach unavailable'), findsOneWidget);
      expect(
        find.textContaining("You declined sharing recovery/scan metrics"),
        findsOneWidget,
      );
      expect(await AppPrefs.getAiCoachConsent(), isFalse);
    },
  );
}
