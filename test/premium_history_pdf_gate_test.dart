import 'package:aesthetic_skin_tracker/utils/premium_access.dart';
import 'package:aesthetic_skin_tracker/widgets/paywall_screen.dart';
import 'package:aesthetic_skin_tracker/widgets/premium_feature_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool originalRevenueCatConfigured;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PremiumAccess.debugTesterPremiumUnlockOverride = false;
    originalRevenueCatConfigured = PremiumAccess.revenueCatConfigured;
    PremiumAccess.revenueCatConfigured = false;
  });

  tearDown(() {
    PremiumAccess.debugTesterPremiumUnlockOverride = null;
    PremiumAccess.revenueCatConfigured = originalRevenueCatConfigured;
  });

  for (final destination in ['History', 'PDF']) {
    testWidgets('free user cannot open $destination', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PremiumRouteGate(child: Text(destination))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(destination), findsNothing);
    });

    testWidgets('premium user can open $destination', (tester) async {
      SharedPreferences.setMockInitialValues({'premium_unlocked': 'true'});
      await tester.pumpWidget(
        MaterialApp(home: PremiumRouteGate(child: Text(destination))),
      );
      await tester.pumpAndSettle();

      expect(find.text(destination), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);
    });
  }

  testWidgets('tester define resolves as Premium for history and PDF', (
    tester,
  ) async {
    PremiumAccess.debugTesterPremiumUnlockOverride = true;
    for (final destination in ['History', 'PDF']) {
      await tester.pumpWidget(
        MaterialApp(home: PremiumRouteGate(child: Text(destination))),
      );
      await tester.pumpAndSettle();
      expect(find.text(destination), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('premium_unlocked'), isNull);
  });

  testWidgets('free user cannot start PDF export and is sent to paywall', (
    tester,
  ) async {
    var exported = false;
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/paywall': (_) => const PaywallScreen()},
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (await requirePremiumAccess(context)) exported = true;
              },
              child: const Text('Export PDF'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Export PDF'));
    await tester.pumpAndSettle();
    expect(exported, isFalse);
    expect(find.byType(PaywallScreen), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('premium_unlocked'), isNull);
  });

  testWidgets('premium user can start PDF export', (tester) async {
    SharedPreferences.setMockInitialValues({'premium_unlocked': 'true'});
    var exported = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (await requirePremiumAccess(context)) exported = true;
              },
              child: const Text('Export PDF'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Export PDF'));
    await tester.pumpAndSettle();
    expect(exported, isTrue);
    expect(find.byType(PaywallScreen), findsNothing);
  });
}
