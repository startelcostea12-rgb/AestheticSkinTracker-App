import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_product_recommendation_engine.dart';
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

AIProductRecommendation _product(String name, String category) =>
    AIProductRecommendation(
      productName: name,
      brand: 'Brand',
      clinicalReason: 'supports the barrier',
      usageGuidance: 'once daily',
      evidenceLevel: 'Evidence-backed',
      affiliateLink: '',
      imageUrl: '',
      category: category,
    );

Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.binding.setSurfaceSize(const Size(500, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );
  await tester.pumpAndSettle();
}

const _disclaimer =
    'These are general patterns, not personalized medical advice. Talk with '
    'a licensed provider before starting anything new.';

void main() {
  test('selection is unchanged: same peptides and procedures as before', () {
    final rec = ScanBasedRecommendationEngine.generate(
      latest: _latest,
      baseline: _baseline,
      procedureType: 'Microneedling',
    );
    expect(rec.peptides.map((p) => p.entry.name).toList(), [
      'GHK-Cu (Copper Tripeptide-1)',
      'Tetrapeptide-30',
      'Matrixyl 3000',
    ]);
    expect(rec.procedures.map((p) => '${p.name}|${p.category}').toList(), [
      'Halo Hybrid Laser|Laser',
      'BBL / BroadBand Light|Light-Based',
      'IPL Photofacial|Light-Based',
    ]);
    expect(rec.deltas, hasLength(6));
    expect(rec.hasEnoughData, isTrue);

    final latestOnly = ScanBasedRecommendationEngine.generate(
      latest: _latest,
      procedureType: 'Microneedling',
    );
    expect(latestOnly.peptides, isEmpty);
    expect(latestOnly.procedures, isEmpty);
    expect(latestOnly.hasEnoughData, isFalse);
  });

  testWidgets('card appears with softer wording and the disclaimer on every tab', (
    tester,
  ) async {
    await _pump(
      tester,
      ScanBasedRecommendationsCard(
        latest: _latest,
        baseline: _baseline,
        procedureType: 'Microneedling',
        aiCoachProducts: [
          _product('Barrier Cream', 'Recovery Support'),
          _product('Mineral SPF 50', 'Prevention'),
        ],
      ),
    );

    expect(find.byType(ScanBasedRecommendationsCard), findsOneWidget);
    expect(
      find.text('Ideas people with similar readings explore'),
      findsOneWidget,
    );
    expect(find.text('AI Recommendations from Your Scan'), findsNothing);

    // Peptides (default tab).
    expect(find.textContaining('Many users watching'), findsWidgets);
    expect(
      find.textContaining(
        'such as GHK-Cu (Copper Tripeptide-1), Tetrapeptide-30, and Matrixyl 3000',
      ),
      findsOneWidget,
    );
    expect(find.text(_disclaimer), findsOneWidget);

    await tester.tap(find.text('Procedures · 3'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Common options discussed for dark spots and texture readings include Laser and Light-Based',
      ),
      findsOneWidget,
    );
    expect(find.text(_disclaimer), findsOneWidget);

    await tester.tap(find.text('Products · 2'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'People tracking similar readings often look at product options such as Barrier Cream and Mineral SPF 50',
      ),
      findsOneWidget,
    );
    expect(find.text(_disclaimer), findsOneWidget);
  });

  testWidgets('latest scan only: card still shows with the disclaimer', (
    tester,
  ) async {
    await _pump(
      tester,
      ScanBasedRecommendationsCard(
        latest: _latest,
        aiCoachProducts: [_product('Barrier Cream', 'Recovery Support')],
      ),
    );
    expect(find.byType(ScanBasedRecommendationsCard), findsOneWidget);
    expect(
      find.text('Ideas people with similar readings explore'),
      findsOneWidget,
    );
    expect(
      find.text('No peptide ideas to show for these readings.'),
      findsOneWidget,
    );
    expect(find.textContaining('healthy range across the board'), findsNothing);
    expect(find.text(_disclaimer), findsOneWidget);
  });
}
