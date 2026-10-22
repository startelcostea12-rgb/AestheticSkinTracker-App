import 'package:aesthetic_skin_tracker/screens/routine_editor_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/skincare_name_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _morningInput = ValueKey('routine_morning_input');

Future<void> _pumpEditor(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    const MaterialApp(
      home: RoutineEditorScreen(
        initialRoutine: {
          'morningSteps': <String>[],
          'eveningSteps': <String>[],
        },
      ),
    ),
  );
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_morningInput)).controller!.text;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('suggestion list', () {
    test('includes every required name', () {
      final lower = {
        for (final n in skincareNameSuggestionList) n.toLowerCase(),
      };
      for (final name in const [
        'hyaluronic acid',
        'niacinamide',
        'retinol',
        'vitamin c',
        'peptides',
        'ghk-cu',
        'ceramides',
        'salicylic acid',
        'glycolic acid',
        'lactic acid',
        'azelaic acid',
        'benzoyl peroxide',
        'sunscreen',
        'moisturizer',
        'cleanser',
        'toner',
        'serum',
        'eye cream',
        'face oil',
        'collagen',
        'centella',
        'snail mucin',
        'bakuchiol',
        'tranexamic acid',
        'kojic acid',
        'alpha arbutin',
        'vitamin e',
        'squalane',
        'glycerin',
        'panthenol',
        'allantoin',
        'tea tree',
        'zinc',
        'copper peptides',
      ]) {
        expect(lower, contains(name), reason: name);
      }
      expect(lower.length, skincareNameSuggestionList.length, reason: 'dupes');
    });

    test('case-insensitive substring, starts-with first, limited', () {
      expect(skincareNameSuggestions('hya'), ['Hyaluronic acid']);
      expect(skincareNameSuggestions('HYA'), ['Hyaluronic acid']);
      // Substring inside a word.
      expect(skincareNameSuggestions('luron'), ['Hyaluronic acid']);
      // "peptides" starts a name before it appears as a later word.
      expect(skincareNameSuggestions('pept'), ['Peptides', 'Copper peptides']);
      expect(skincareNameSuggestions('acid').length, lessThanOrEqualTo(6));
      expect(skincareNameSuggestions('  '), isEmpty);
      expect(skincareNameSuggestions('xyzzy'), isEmpty);
    });
  });

  testWidgets('typing "hya" shows Hyaluronic acid', (tester) async {
    await _pumpEditor(tester);
    await tester.enterText(find.byKey(_morningInput), 'hya');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('routine_suggestion_Hyaluronic acid')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('routine_suggestion_Niacinamide')),
      findsNothing,
    );
  });

  testWidgets('selecting a suggestion fills the field, Add saves it', (
    tester,
  ) async {
    await _pumpEditor(tester);
    await tester.enterText(find.byKey(_morningInput), 'niac');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('routine_suggestion_Niacinamide')),
    );
    await tester.pumpAndSettle();
    expect(_fieldText(tester), 'Niacinamide');
    expect(
      find.byKey(const ValueKey('routine_morning_suggestions')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('routine_morning_add')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('routine_morning_item_0')),
      findsOneWidget,
    );
    expect(find.text('Niacinamide'), findsOneWidget);
  });

  testWidgets('a custom name not on the list is still accepted', (
    tester,
  ) async {
    await _pumpEditor(tester);
    await tester.enterText(find.byKey(_morningInput), 'My Grandma Rose Balm');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('routine_morning_suggestions')),
      findsNothing,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('My Grandma Rose Balm'), findsOneWidget);
    expect(_fieldText(tester), isEmpty);

    await tester.tap(find.text('Save routine').hitTestable().first);
    await tester.pumpAndSettle();
    final saved = await AppPrefs.getActiveAiRoutine();
    expect(saved?['morningSteps'], ['My Grandma Rose Balm']);
  });
}
