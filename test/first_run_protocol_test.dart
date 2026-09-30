import 'package:aesthetic_skin_tracker/models/peptide_model.dart';
import 'package:aesthetic_skin_tracker/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first-run offers procedure, peptide, or scan choices', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FirstRunProtocolScreen()));

    expect(find.text('Start a procedure protocol'), findsOneWidget);
    expect(find.text('Start a peptide protocol'), findsOneWidget);
    expect(find.text('Skip to Scan'), findsOneWidget);
  });

  test('saved procedure or peptide bypasses first-run choice', () {
    const noPeptides = <PeptideEntry>[];
    expect(
      hasSavedFirstRunProtocol(
        procedures: <Map<String, dynamic>>[
          {'id': 'procedure-1'},
        ],
        peptides: noPeptides,
      ),
      isTrue,
    );

    expect(
      hasSavedFirstRunProtocol(
        procedures: <Map<String, dynamic>>[],
        peptides: <PeptideEntry>[
          PeptideEntry(
            id: 'peptide-1',
            name: 'Example peptide',
            frequency: 'Weekly',
            startDate: DateTime(2026, 9, 1),
            category: 'other',
          ),
        ],
      ),
      isTrue,
    );
    expect(
      hasSavedFirstRunProtocol(
        procedures: const <Map<String, dynamic>>[],
        peptides: noPeptides,
      ),
      isFalse,
    );
  });
}
