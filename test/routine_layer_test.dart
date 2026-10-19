import 'dart:io';

import 'package:aesthetic_skin_tracker/screens/routine_editor_screen.dart';
import 'package:aesthetic_skin_tracker/screens/routines_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/widgets/home_routine_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the editor adds and removes products and saves the routine', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: RoutineEditorScreen(
          initialRoutine: {
            'morningSteps': ['Gentle cleanser'],
            'eveningSteps': <String>[],
            'detectedProducts': ['Gentle cleanser'],
            'notes': 'kept',
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('routine_morning_input')),
      'Mineral SPF 50',
    );
    await tester.tap(find.byKey(const ValueKey('routine_morning_add')));
    await tester.enterText(
      find.byKey(const ValueKey('routine_evening_input')),
      'Barrier cream',
    );
    await tester.tap(find.byKey(const ValueKey('routine_evening_add')));
    await tester.pump();
    expect(find.text('Mineral SPF 50'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('routine_morning_item_0')),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pump();
    expect(find.text('Gentle cleanser'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('routine_save')));
    await tester.pumpAndSettle();
    final saved = (await AppPrefs.getActiveAiRoutine())!;
    expect(saved['morningSteps'], ['Mineral SPF 50']);
    expect(saved['eveningSteps'], ['Barrier cream']);
    expect(saved['source'], 'manual');
    expect(saved['detectedProducts'], ['Gentle cleanser']);
    expect(saved['notes'], 'kept');
  });

  testWidgets('the Routines screen opens the editor', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await AppPrefs.saveActiveAiRoutine({
      'morningSteps': ['Gentle cleanser'],
      'eveningSteps': ['Barrier cream'],
    });
    await tester.pumpWidget(const MaterialApp(home: RoutinesScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('routines_edit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Edit routine'), findsOneWidget);
    expect(find.text('Gentle cleanser'), findsOneWidget);
  });

  testWidgets('the home card shows morning and evening products', (
    tester,
  ) async {
    var opened = false;
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeRoutineCard(
            routine: const {
              'morningSteps': ['Gentle cleanser', 'Mineral SPF 50'],
              'eveningSteps': ['Barrier cream'],
            },
            onOpen: () => opened = true,
          ),
        ),
      ),
    );
    for (final text in [
      'My routine',
      'Morning',
      'Evening',
      'Gentle cleanser',
      'Mineral SPF 50',
      'Barrier cream',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Open'));
    expect(opened, isTrue);
  });

  test('home shows the routine card when a routine is saved', () {
    final source = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(source, contains('HomeRoutineCard('));
    expect(source, contains('await AppPrefs.getActiveAiRoutine();'));
  });

  testWidgets('product notes are saved with the routine; empty is omitted', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> editAndSave(String notes) async {
      final initial =
          await AppPrefs.getActiveAiRoutine() ??
          {
            'morningSteps': ['Gentle cleanser'],
          };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RoutineEditorScreen(initialRoutine: initial),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Product notes'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('routine_notes')),
        notes,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('routine_save')));
      await tester.tap(find.byKey(const ValueKey('routine_save')));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget); // popped back
    }

    await editAndSave('  Started retinol Oct 1  ');
    final saved = (await AppPrefs.getActiveAiRoutine())!;
    expect(saved['notes'], 'Started retinol Oct 1');
    expect(saved['morningSteps'], ['Gentle cleanser']);

    await editAndSave(' ');
    expect(
      (await AppPrefs.getActiveAiRoutine())!.containsKey('notes'),
      isFalse,
    );
  });

  testWidgets('the home card shows product notes when present', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeRoutineCard(
            routine: {
              'morningSteps': ['Gentle cleanser'],
              'notes': 'Started retinol Oct 1',
            },
          ),
        ),
      ),
    );
    expect(find.text('Notes: Started retinol Oct 1'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeRoutineCard(
            routine: {
              'morningSteps': ['Gentle cleanser'],
            },
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('home_routine_notes')), findsNothing);
  });
}
