import 'dart:io';

import 'package:aesthetic_skin_tracker/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('known visible-copy files omit medical validation claims outside comments', () {
    final prohibited = RegExp(
      r'clinically validated|clinically shown|clinically favorable|clinically supported|clinically calming|clinically meaningful size|clinically-studied|clinically elevated|Proven efficacy|Derm Recommended|dermatologist-aligned|clinically relevant',
      caseSensitive: false,
    );
    for (final path in [
      'lib/models/peptide_model.dart', 'lib/models/product.dart',
      'lib/utils/natural_skincare.dart', 'lib/utils/report_service.dart',
      'lib/screens/analysis_results_screen.dart',
      'lib/utils/acne_rosacea_intelligence.dart',
      'lib/utils/scan_based_recommendation_engine.dart',
      'lib/utils/ai_product_recommendation_engine.dart',
      'lib/utils/acne_rosacea_photo_analysis.dart',
      'lib/utils/procedure_intelligence.dart',
      'lib/features/ai_coach/presentation/screens/premium_recovery_hub_screen.dart',
    ]) {
      final code = File(path).readAsLinesSync()
          .map((line) => line.split('//').first).join('\n');
      expect(prohibited.hasMatch(code), isFalse, reason: path);
    }
  });

  test(
    'product badge and visible reasons do not claim clinical endorsement',
    () {
      expect(ProductBadge.dermatologistRecommended.label, 'Catalog Pick');
      final reasons = ProductCatalog.all
          .map((product) => product.whyRecommend)
          .join(' ')
          .toLowerCase();
      expect(reasons, isNot(contains('clinically associated')));
      expect(reasons, isNot(contains('dermatologist-aligned')));
      expect(ProductCatalog.all.map((product) => product.id).toList(), [
        'matrixyl-3000',
        'copper-peptide-ghk',
        'argireline-serum',
        'ha-multi-mw',
        'niacinamide-10',
        'vitamin-c-15',
        'mineral-spf-50',
        'collagen-peptide-powder',
        'arnica-bromelain',
        'centella-cica-cream',
        'led-mask-red',
        'gua-sha-stone',
        'bundle-laser-recovery',
        'bundle-post-lipo',
        'bundle-glow-injectables',
      ]);
    },
  );
}
