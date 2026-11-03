import 'package:aesthetic_skin_tracker/utils/procedure_intelligence.dart';
import 'package:aesthetic_skin_tracker/utils/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report metric definitions never expose pore contraction', () {
    for (final procedure in const [
      'General Skincare',
      'BBL',
      'Botox',
      'Facelift',
      'Laser Resurfacing',
      'Hair Transplant',
      'Liposuction',
    ]) {
      for (final definition in clinicalMetricsForProcedure(procedure)) {
        expect(definition.sourceKey, isNot('pore_contraction_index'));
        expect(definition.label.toLowerCase(), isNot(contains('contraction')));
        expect(
          reportMetricHasSavedSource(definition, const {
            'pore_contraction_index': 72.0,
          }),
          isFalse,
        );
      }
    }
  });

  test(
    'missing report metric source is omitted instead of defaulting to 5.0',
    () {
      const rosacea = ClinicalMetricDef(
        label: 'Rosacea Severity',
        sourceKey: 'rosacea_severity',
        lowerIsBetter: true,
        clinicalContext: '',
        suggestionImproving: '',
        suggestionWorsening: '',
      );

      expect(reportMetricHasSavedSource(rosacea, const {}), isFalse);
      expect(
        reportMetricHasSavedSource(rosacea, const {'redness': 20.0}),
        isFalse,
      );
    },
  );

  test('saved redness zero remains a report source', () {
    final redness = clinicalMetricsForProcedure(
      'General Skincare',
    ).firstWhere((definition) => definition.sourceKey == 'redness');

    expect(reportMetricHasSavedSource(redness, const {'redness': 0.0}), isTrue);
  });
}
