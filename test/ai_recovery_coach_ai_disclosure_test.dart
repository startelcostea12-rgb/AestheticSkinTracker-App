import 'package:aesthetic_skin_tracker/screens/ai_recovery_coach_screen.dart';
import 'package:aesthetic_skin_tracker/utils/premium_access.dart';
import 'package:aesthetic_skin_tracker/utils/premium_recovery_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ai_coach_consent_granted': true,
    });
    PremiumAccess.debugTesterPremiumUnlockOverride = true;
    await PremiumRecoveryService.saveCoachMessages([
      {
        'id': 'test_assistant_message',
        'role': 'assistant',
        'text': 'Swelling like this is common in week one.',
        'createdAt': DateTime.now().toIso8601String(),
        'imageRef': null,
      },
    ]);
  });

  tearDown(() {
    PremiumAccess.debugTesterPremiumUnlockOverride = null;
  });

  testWidgets(
    'AI Recovery Coach shows a persistent AI-generated label on assistant replies',
    (tester) async {
      // Tall, wide surface: the real screen's header (context chips, coach
      // intelligence card, suggested prompts) overflows a small/narrow
      // test viewport at default sizes.
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(home: AIRecoveryCoachScreen()),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Swelling like this is common in week one.'),
        findsOneWidget,
      );
      expect(find.text('AI-generated'), findsOneWidget);
    },
  );
}
