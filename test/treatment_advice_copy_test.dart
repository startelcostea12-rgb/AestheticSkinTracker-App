import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reachable screens omit listed treatment-advice phrases', () {
    final prohibited = RegExp(
      r'Clinical interpretation|Clinical Recommendation|Clinician-Recommended Products|'
      r'Book a dermatologist appointment — topicals alone rarely control cystic disease\.|'
      r'Intralesional cortisone \(kenalog\)|Prescription topicals: azelaic acid 15%|'
      r'Proven efficacy',
      caseSensitive: false,
    );
    final keep = 'This is not medical advice';
    final paths = [
      'lib/screens/analysis_results_screen.dart',
      'lib/screens/recovery_metric_detail_screen.dart',
      'lib/screens/acne_rosacea_tracker_screen.dart',
      'lib/screens/scar_healing_tracker_screen.dart',
      'lib/widgets/product_recommendation_card.dart',
      'lib/utils/ai_product_recommendation_engine.dart',
      'lib/utils/acne_rosacea_intelligence.dart',
      'lib/utils/skin_metric_labels.dart',
      'lib/utils/procedure_metric_set.dart',
    ];
    for (final path in paths) {
      final code = File(path)
          .readAsLinesSync()
          .map((line) => line.split('//').first)
          .join('\n');
      expect(prohibited.hasMatch(code), isFalse, reason: path);
    }
    final analysis = File('lib/screens/analysis_results_screen.dart').readAsStringSync();
    expect(analysis.contains(keep) || analysis.contains('not medical advice') || analysis.contains('not constitute medical advice'), isTrue);
  });

  test('evidence badges no longer expose Proven efficacy', () {
    final card = File('lib/widgets/product_recommendation_card.dart').readAsStringSync();
    expect(card.contains("'Proven efficacy'"), isFalse);
    final engine = File('lib/utils/ai_product_recommendation_engine.dart')
        .readAsLinesSync()
        .map((line) => line.split('//').first)
        .join('\n');
    expect(engine.contains('Proven efficacy'), isFalse);
    expect(engine.contains('Clinical consensus'), isFalse);
  });
}
