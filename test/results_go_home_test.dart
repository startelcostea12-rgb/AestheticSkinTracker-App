import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in app: `/home` is HomePage, `/picker` stands in for the
/// procedure/peptide picker, `/scan` for the Skin Scan results screen, which
/// has a Home button calling navigateHomeFrom.
Widget _app(GlobalKey<NavigatorState> navigatorKey, {required String first}) {
  Widget page(String name) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('page:$name'),
          if (name == 'scan')
            Builder(
              builder: (context) => TextButton(
                onPressed: () => navigateHomeFrom(Navigator.of(context)),
                child: const Text('Home'),
              ),
            ),
        ],
      ),
    ),
  );
  return MaterialApp(
    navigatorKey: navigatorKey,
    initialRoute: first,
    // Exactly one initial route (Flutter would otherwise also build '/'
    // underneath a '/home' initial route).
    onGenerateInitialRoutes: (name) => [
      MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => page(name.substring(1)),
      ),
    ],
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => page(settings.name!.substring(1)),
    ),
  );
}

Future<void> _push(
  WidgetTester tester,
  GlobalKey<NavigatorState> key,
  String name, {
  bool replace = false,
}) async {
  if (replace) {
    key.currentState!.pushReplacementNamed(name);
  } else {
    key.currentState!.pushNamed(name);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home in the stack: returns to that HomePage', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key, first: '/home'));
    await _push(tester, key, '/picker');
    await _push(tester, key, '/scan');

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('page:home'), findsOneWidget);
    expect(find.text('page:picker'), findsNothing);
    expect(key.currentState!.canPop(), isFalse);
  });

  testWidgets(
    'picker replaced HomePage (bottom nav): lands on Home, not the picker',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(key, first: '/home'));
      // The bottom navigation uses pushReplacement, so the picker becomes
      // the first route and HomePage leaves the stack.
      await _push(tester, key, '/picker', replace: true);
      await _push(tester, key, '/scan');

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.text('page:home'), findsOneWidget);
      expect(find.text('page:picker'), findsNothing);
      expect(key.currentState!.canPop(), isFalse);
    },
  );

  testWidgets('scan is the first route: lands on Home', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(key, first: '/scan'));

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('page:home'), findsOneWidget);
    expect(find.text('page:scan'), findsNothing);
  });

  test('results stage shows Done, which goes home', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    final done = source.indexOf("ValueKey('results_done_button')");
    expect(done, isNonNegative);
    final doneBlock = source.substring(done - 200, done + 300);
    expect(doneBlock, contains('if (_stage == _Stage.results)'));
    expect(doneBlock, contains('onPressed: _goHome'));
    expect(doneBlock, contains("'Done'"));

    expect(
      source,
      contains('void _goHome() => navigateHomeFrom(Navigator.of(context));'),
    );
  });
}
