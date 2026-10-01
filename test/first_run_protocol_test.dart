import 'package:aesthetic_skin_tracker/screens/onboarding_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('start offers exactly Procedure and Peptide', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FirstRunProtocolScreen()));

    expect(find.text('Procedure'), findsOneWidget);
    expect(find.text('Peptide'), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(2));
    expect(find.text('Skip to Scan'), findsNothing);
  });

  testWidgets('Procedure opens the existing scan route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const FirstRunProtocolScreen(),
        routes: {'/ai-coach': (_) => const Scaffold(body: Text('Scan flow'))},
      ),
    );

    await tester.tap(find.text('Procedure'));
    await tester.pumpAndSettle();
    expect(find.text('Scan flow'), findsOneWidget);
  });

  testWidgets('Peptide opens the existing tracker route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const FirstRunProtocolScreen(),
        routes: {
          '/peptide-tracker': (_) =>
              const Scaffold(body: Text('Peptide tracker')),
        },
      ),
    );

    await tester.tap(find.text('Peptide'));
    await tester.pumpAndSettle();
    expect(find.text('Peptide tracker'), findsOneWidget);
  });

  testWidgets('splash opens the two-door start even with a saved protocol', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AppPrefs.saveProcedureHistory([
      {'id': 'procedure-1', 'type': 'Microneedling'},
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: const SplashScreen(),
        routes: {'/first-run-protocol': (_) => const FirstRunProtocolScreen()},
      ),
    );

    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pumpAndSettle();
    expect(find.text('Procedure'), findsOneWidget);
    expect(find.text('Peptide'), findsOneWidget);
  });
}
