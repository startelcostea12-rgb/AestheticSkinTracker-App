import 'package:aesthetic_skin_tracker/models/journal_entry.dart';
import 'package:aesthetic_skin_tracker/models/product_feedback.dart';
import 'package:aesthetic_skin_tracker/models/product_tracker.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/peptide_interactions.dart';
import 'package:aesthetic_skin_tracker/utils/recommendation_context.dart';
import 'package:aesthetic_skin_tracker/utils/scan_based_recommendation_engine.dart';
import 'package:aesthetic_skin_tracker/widgets/scan_based_recommendations_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _latest = SkinMetrics(
  redness: 7.5,
  darkSpots: 7.0,
  texture: 6.5,
  wrinkle: 6.0,
);
const _baseline = SkinMetrics(
  redness: 6.0,
  darkSpots: 7.0,
  texture: 6.0,
  wrinkle: 6.0,
);

TrackedProduct _product(String name, String ingredients, {DateTime? endDate}) =>
    TrackedProduct(
      id: name,
      name: name,
      brand: 'Brand',
      keyIngredients: ingredients,
      startDate: DateTime(2026, 9, 1),
      endDate: endDate,
    );

ProductFeedbackEntry _feedback(
  String productName, {
  required int irritation,
  List<String> warnings = const [],
}) => ProductFeedbackEntry(
  id: 'f-$productName',
  productId: productName,
  productName: productName,
  date: DateTime(2026, 10, 2),
  irritation: irritation,
  hydration: 5,
  textureImprovement: 5,
  redness: 0,
  satisfaction: 5,
  aiRating: 5,
  aiSummary: '',
  compatibilityWarnings: warnings,
);

JournalEntry _journal(String title, String content) =>
    JournalEntry(date: DateTime(2026, 10, 5), title: title, content: content);

Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.binding.setSurfaceSize(const Size(500, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );
  await tester.pumpAndSettle();
}

final _contextBlock = find.byKey(
  const ValueKey('recommendations_context_notes'),
);

void main() {
  group('RecommendationContext.notes', () {
    test('missing data produces no notes', () {
      expect(RecommendationContext.notes(), isEmpty);
      expect(
        RecommendationContext.notes(
          journalEntries: [_journal('General Note', 'Skin felt great today')],
          trackedProducts: [_product('Glow Serum', 'Niacinamide')],
          productFeedback: [_feedback('Glow Serum', irritation: 2)],
          recommendedPeptideNames: const ['Tetrapeptide-30'],
        ),
        isEmpty,
      );
    });

    test('journal irritation note naming a tracked product', () {
      final notes = RecommendationContext.notes(
        journalEntries: [
          _journal('General Note', 'Some stinging after Glow Serum tonight'),
        ],
        trackedProducts: [_product('Glow Serum', 'Vitamin E')],
      );
      expect(notes, [
        'You previously noted irritation with Glow Serum in your journal '
            '(Oct 5).',
      ]);
    });

    test('Reaction-tagged note with no product stays general', () {
      final notes = RecommendationContext.notes(
        journalEntries: [_journal('Reaction', 'Cheeks felt hot')],
      );
      expect(notes, ['You noted a reaction in your journal on Oct 5.']);
    });

    test('per-product journal irritation note', () {
      final notes = RecommendationContext.notes(
        productJournals: {
          'Barrier Balm': [_journal('Day 3', 'Mild itching around the nose')],
        },
      );
      expect(
        notes.single,
        'You previously noted irritation with Barrier Balm in your journal '
        '(Oct 5).',
      );
    });

    test('feedback irritation flag and saved compatibility warning', () {
      final notes = RecommendationContext.notes(
        productFeedback: [
          _feedback(
            'Retinol Night Cream',
            irritation: 7,
            warnings: const ['Retinol and AHA in the same night can irritate.'],
          ),
        ],
      );
      expect(notes, [
        'You previously logged irritation (7/10) with Retinol Night Cream on '
            'Oct 2.',
        'When you logged Retinol Night Cream, the app noted: Retinol and AHA '
            'in the same night can irritate.',
      ]);
    });

    test('ingredient from an earlier irritation note in another product', () {
      final notes = RecommendationContext.notes(
        journalEntries: [
          _journal('Reaction', 'Rash after a niacinamide toner'),
        ],
        trackedProducts: [
          _product('Daily Serum', 'Niacinamide, Zinc'),
          _product('Old Toner', 'Niacinamide', endDate: DateTime(2026, 9, 20)),
        ],
      );
      expect(
        notes,
        contains(
          'Daily Serum contains Niacinamide, which appeared in an earlier '
          'irritation note.',
        ),
      );
      // Products no longer in use are not flagged.
      expect(notes.where((n) => n.startsWith('Old Toner')), isEmpty);
    });

    test('existing interaction rule across a product and a recommendation', () {
      final notes = RecommendationContext.notes(
        trackedProducts: [_product('Night Cream', 'Retinol, Squalane')],
        recommendedPeptideNames: const ['Matrixyl 3000'],
      );
      expect(notes, [
        'Matrixyl 3000 and Night Cream are often discussed as a potential '
            'interaction. Matrixyl + retinoids: watch for irritation if '
            'combined; consider alternating evenings.',
      ]);
    });

    test('peptide warnings are unchanged by the move', () {
      expect(peptideInteractionWarnings(['GHK-Cu', 'Vitamin C serum']), [
        'GHK-Cu and Vitamin C (ascorbic acid) can deactivate each other — '
            'apply at different times of day.',
      ]);
      expect(peptideInteractionWarnings(['Argireline']), isEmpty);
    });
  });

  group('ScanBasedRecommendationsCard context', () {
    testWidgets('journal irritation note and flagged product appear in card', (
      tester,
    ) async {
      await _pump(
        tester,
        ScanBasedRecommendationsCard(
          latest: _latest,
          baseline: _baseline,
          journalEntries: [
            _journal('General Note', 'Burning after Glow Serum this morning'),
          ],
          trackedProducts: [_product('Glow Serum', 'Vitamin E')],
          productFeedback: [_feedback('Retinol Night Cream', irritation: 6)],
        ),
      );
      expect(_contextBlock, findsOneWidget);
      expect(find.text('From your logs'), findsOneWidget);
      expect(
        find.text(
          'You previously noted irritation with Glow Serum in your journal '
          '(Oct 5).',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'You previously logged irritation (6/10) with Retinol Night Cream '
          'on Oct 2.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no logged data: no context block, recommendations as before', (
      tester,
    ) async {
      await _pump(
        tester,
        const ScanBasedRecommendationsCard(
          latest: _latest,
          baseline: _baseline,
        ),
      );
      expect(_contextBlock, findsNothing);
      expect(find.text('From your logs'), findsNothing);

      final rec = ScanBasedRecommendationEngine.generate(
        latest: _latest,
        baseline: _baseline,
      );
      expect(rec.peptides, isNotEmpty);
      for (final p in rec.peptides) {
        expect(find.text(p.entry.name), findsWidgets);
      }
    });

    testWidgets('logged data does not change which recommendations show', (
      tester,
    ) async {
      final before = ScanBasedRecommendationEngine.generate(
        latest: _latest,
        baseline: _baseline,
      );
      await _pump(
        tester,
        ScanBasedRecommendationsCard(
          latest: _latest,
          baseline: _baseline,
          journalEntries: [_journal('Reaction', 'Matrixyl made me itchy')],
          trackedProducts: [_product('Night Cream', 'Retinol')],
          activePeptideNames: const ['Argireline'],
        ),
      );
      expect(_contextBlock, findsOneWidget);
      expect(
        find.text('Matrixyl 3000 appeared in an earlier irritation note.'),
        findsOneWidget,
      );
      for (final p in before.peptides) {
        expect(find.text(p.entry.name), findsWidgets);
      }
      expect(find.text('Peptides · ${before.peptides.length}'), findsOneWidget);
      expect(
        find.text('Procedures · ${before.procedures.length}'),
        findsOneWidget,
      );
    });
  });
}
