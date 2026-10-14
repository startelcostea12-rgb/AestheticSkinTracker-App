import 'package:aesthetic_skin_tracker/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: HomePage()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Welcome back appears above the protocol card', (tester) async {
    await pumpHome(tester);
    final welcome = find.text('Welcome back');
    final protocol = find.byKey(const ValueKey('home_protocol_scan_pair'));
    expect(welcome, findsOneWidget);
    expect(protocol, findsOneWidget);
    expect(
      tester.getTopLeft(welcome).dy,
      lessThan(tester.getTopLeft(protocol).dy),
    );
  });
}
