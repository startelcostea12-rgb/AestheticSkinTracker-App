// Regression test for the Priority-2 peptide cleanup: confirms the
// reconstitution dataset is now a real typed model (not a bare untyped
// Map dataset), the dosing calculator math is unchanged, and typed data
// still renders correctly in the UI.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aesthetic_skin_tracker/screens/peptide_reconstitution_sheet.dart';

void main() {
  group('ReconstitutionPeptideReference data', () {
    test('allPeptides is a real typed list with every entry fully populated', () {
      expect(allPeptides, isNotEmpty);
      for (final peptide in allPeptides) {
        expect(peptide.name, isNotEmpty);
        expect(peptide.category, isNotEmpty);
        expect(peptide.vialSizes, isNotEmpty);
        expect(peptide.reconstitution, isNotEmpty);
        expect(peptide.stability, isNotEmpty);
        expect(peptide.dosage, isNotEmpty);
        expect(peptide.benefits, isNotEmpty);
        expect(peptide.notes, isNotEmpty);
      }
    });

    test('at least one entry is featured (drives the Favorites strip)', () {
      expect(allPeptides.any((p) => p.featured), isTrue);
    });

    test('fromMap parses every field correctly', () {
      final parsed = ReconstitutionPeptideReference.fromMap(const {
        'name': 'Test Peptide',
        'category': 'Recovery',
        'featured': true,
        'vialSizes': '5mg',
        'reconstitution': 'Add 5ml BAC',
        'stability': 'Fridge: 30 days',
        'dosage': '100mcg daily',
        'benefits': 'Test benefit',
        'notes': 'Test note',
      });

      expect(parsed.name, 'Test Peptide');
      expect(parsed.category, 'Recovery');
      expect(parsed.featured, isTrue);
      expect(parsed.vialSizes, '5mg');
      expect(parsed.searchHaystack, contains('test peptide'));
    });

    test('fromMap defaults featured to false when absent', () {
      final parsed = ReconstitutionPeptideReference.fromMap(const {
        'name': 'Test Peptide',
        'category': 'Recovery',
        'vialSizes': '5mg',
        'reconstitution': 'Add 5ml BAC',
        'stability': 'Fridge: 30 days',
        'dosage': '100mcg daily',
        'benefits': 'Test benefit',
        'notes': 'Test note',
      });
      expect(parsed.featured, isFalse);
    });
  });

  group('PeptideReconstitutionSheet widget', () {
    testWidgets('dosing calculator math is unchanged (10mg / 2mg per ml = 5.00 ml)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: PeptideReconstitutionSheet()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('5.00 ml'), findsWidgets);
    });

    testWidgets('a known featured peptide renders from the typed dataset', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PeptideReconstitutionSheet()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('BPC-157'), findsWidgets);
    });
  });
}
