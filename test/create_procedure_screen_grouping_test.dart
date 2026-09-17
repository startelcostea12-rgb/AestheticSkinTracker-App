import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/screens/create_procedure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateProcedureScreen region grouping', () {
    test('prioritizes face vs body region and falls back general to face', () {
      expect(procedureSelectionGroupForType('Microneedling'),
          ProcedureBodyRegion.face);
      expect(procedureSelectionGroupForType('Botox / Dysport / Xeomin'),
          ProcedureBodyRegion.face);
      expect(procedureSelectionGroupForType('Liposuction'),
          ProcedureBodyRegion.body);
      expect(procedureSelectionGroupForType('BBL'), ProcedureBodyRegion.body);
      expect(procedureSelectionGroupForType('Other'), ProcedureBodyRegion.face);
    });

    test('Face + each category combination is deduplicated and non-crashing', () {
      // Face is the only region that still routes through the category
      // filter, so this only needs to cover Face now — Body bypasses
      // buildVisibleProcedureTypesForSelection entirely (see below).
      final categoryOptions = [
        medicalAestheticCategory,
        cosmeticCategory,
        atHomeCategory,
      ];

      for (final category in categoryOptions) {
        final items = buildVisibleProcedureTypesForSelection(
          bodyRegion: ProcedureBodyRegion.face,
          category: category,
        );

        expect(items.toSet().length, items.length,
            reason: 'Duplicate procedure values should not exist for face + $category');
        expect(items, isNotEmpty,
            reason: 'All combos should still produce a valid menu list for face + $category');
      }
    });

    test(
        'the surgical body procedures live only in cosmeticProcedureTypes now that '
        'Body skips the category filter', () {
      const surgicalBodyTypes = [
        'BBL',
        'Liposuction',
        'Tummy Tuck',
        'Arm Contouring',
        'Thigh Lift',
      ];

      for (final type in surgicalBodyTypes) {
        expect(medicalAestheticProcedureTypes.contains(type), isFalse,
            reason: '$type no longer needs dual-listing in medicalAestheticProcedureTypes '
                'since Body pulls directly from buildBodyProcedureTypes(), not the category filter');
        expect(cosmeticProcedureTypes.contains(type), isTrue,
            reason: '$type should remain in cosmeticProcedureTypes, its original source list');
      }
    });

    test('buildBodyProcedureTypes returns the full body list directly, no category filter, deduplicated', () {
      final bodyItems = buildBodyProcedureTypes();

      expect(
        bodyItems.toSet(),
        {
          'BBL',
          'Liposuction',
          'Tummy Tuck',
          'Arm Contouring',
          'Thigh Lift',
          'Other',
        },
        reason: 'Body Procedures should show all 5 surgical types plus Other, '
            'regardless of category — the category sub-step is skipped entirely',
      );
      expect(bodyItems.toSet().length, bodyItems.length,
          reason: 'No duplicate values in the body list');
    });

    testWidgets('Face shows the Medical/Cosmetic/At-Home category chips', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CreateProcedureScreen()),
      );

      // Face is the default region on a fresh screen.
      expect(find.text('Medical'), findsOneWidget);
      expect(find.text('Cosmetic'), findsOneWidget);
      expect(find.text('At-Home'), findsOneWidget);
    });

    testWidgets(
        'Body hides the category chips entirely and shows the full body item list directly, no crash',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CreateProcedureScreen()),
      );

      await tester.tap(find.text('Body Procedures'));
      await tester.pumpAndSettle();

      // The category sub-step should be gone entirely for Body.
      expect(find.text('Medical'), findsNothing);
      expect(find.text('Cosmetic'), findsNothing);
      expect(find.text('At-Home'), findsNothing);

      // The dropdown itself should still be present and open cleanly —
      // no duplicate-value / missing-value DropdownButton assertion crash.
      expect(find.byType(DropdownButton<String>), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      for (final label in [
        'BBL',
        'Liposuction',
        'Tummy Tuck',
        'Arm Contouring',
        'Thigh Lift',
      ]) {
        expect(find.text(label), findsWidgets,
            reason: '$label should be directly selectable under Body with no category step');
      }
    });
  });
}
