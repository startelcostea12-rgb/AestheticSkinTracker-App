import 'package:aesthetic_skin_tracker/models/peptide_model.dart';
import 'package:aesthetic_skin_tracker/screens/peptide_tracker_screen.dart';
import 'package:aesthetic_skin_tracker/utils/peptide_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens Add Peptide from the peptide tracker (My Peptides tab FAB).
Future<void> _openAddPeptide(
  WidgetTester tester, {
  Size size = const Size(400, 1000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    const MaterialApp(home: PeptideTrackerScreen(initialTab: 0)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FloatingActionButton, 'Add Peptide'));
  await tester.pumpAndSettle();
  expect(find.text('Manual Entry'), findsOneWidget);
}

String? _fieldWithText(WidgetTester tester, String text) {
  for (final e in find.byType(EditableText).evaluate()) {
    final value = (e.widget as EditableText).controller.text;
    if (value == text) return value;
  }
  return null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('picking a peptide in the Library tab fills Manual Entry', (
    tester,
  ) async {
    await _openAddPeptide(tester);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    final lib = kPeptideLibrary.first;
    await tester.tap(find.text(lib.name).first);
    await tester.pumpAndSettle();
    // Back on Manual Entry with the picked peptide's name filled in.
    expect(_fieldWithText(tester, lib.name), lib.name);
  });

  testWidgets('a picked peptide is added to the list on save, as before', (
    tester,
  ) async {
    await _openAddPeptide(tester);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    final lib = kPeptideLibrary.first;
    await tester.tap(find.text(lib.name).first);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(ElevatedButton, 'Add Peptide');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Manual Entry'), findsNothing, reason: 'page closed');
    final saved = await PeptideService.loadAll();
    expect(saved.map((p) => p.name), contains(lib.name));
    expect(saved.firstWhere((p) => p.name == lib.name).category, lib.category);
  });

  testWidgets('text typed in Manual Entry survives a visit to Library', (
    tester,
  ) async {
    await _openAddPeptide(tester);
    final nameField = find.byType(TextFormField).first;
    await tester.enterText(nameField, 'My custom serum');
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual Entry'));
    await tester.pumpAndSettle();
    expect(_fieldWithText(tester, 'My custom serum'), 'My custom serum');
  });

  for (final width in [320.0, 375.0]) {
    testWidgets('Library tab fits at ${width.toInt()}px; the count line '
        'stays visible', (tester) async {
      await _openAddPeptide(tester, size: Size(width, 900));
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final line = find.byKey(const ValueKey('peptide_library_count_line'));
      expect(
        tester.widget<Text>(line).data,
        '${kPeptideLibrary.length} peptides \u00b7 sorted by popularity',
      );
      expect(tester.getRect(line).right, lessThanOrEqualTo(width));
      // Scroll the list too.
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final width in [320.0, 375.0]) {
    testWidgets('the detail screen opened after saving fits at '
        '${width.toInt()}px', (tester) async {
      await _openAddPeptide(tester, size: Size(width, 900));
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kPeptideLibrary.first.name).first);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(ElevatedButton, 'Add Peptide');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The detail screen is open (its Take New Scan and Timeline parts).
      expect(find.text('Take New Scan'), findsWidgets);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('· updates your insights'), findsOneWidget);
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
