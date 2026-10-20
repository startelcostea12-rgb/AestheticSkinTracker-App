import 'package:aesthetic_skin_tracker/screens/routine_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(
  WidgetTester tester,
  double width,
  Map<String, dynamic>? routine,
) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: RoutineEditorScreen(initialRoutine: routine)),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollThrough(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  for (var i = 0; i < 8; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty routine shows an empty state per period', (tester) async {
    await _pump(tester, 375, null);
    expect(find.byKey(const ValueKey('routine_morning_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('routine_evening_empty')), findsOneWidget);
    expect(find.text('No steps'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('routine_editor_hint')), findsOneWidget);
    await _scrollThrough(tester);
  });

  testWidgets('steps are numbered cards with a remove button and a count', (
    tester,
  ) async {
    await _pump(tester, 375, {
      'morningSteps': ['Gentle cleanser', 'Vitamin C serum'],
      'eveningSteps': ['Night cream'],
    });
    expect(find.text('2 steps'), findsOneWidget);
    expect(find.text('1 step'), findsOneWidget);
    expect(find.byKey(const ValueKey('routine_morning_empty')), findsNothing);
    final second = find.byKey(const ValueKey('routine_morning_item_1'));
    expect(
      find.descendant(of: second, matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: second, matching: find.byTooltip('Remove')),
      findsOneWidget,
    );
  });

  for (final width in [320.0, 375.0]) {
    testWidgets('fits at ${width.toInt()}px with long product names', (
      tester,
    ) async {
      await _pump(tester, width, {
        'morningSteps': [
          'La Roche-Posay Toleriane Double Repair Face Moisturizer with '
              'Ceramides and Niacinamide',
          'SPF 50',
        ],
        'eveningSteps': <String>[],
        'notes': 'Started retinol Oct 1',
      });
      await _scrollThrough(tester);
    });
  }
}
