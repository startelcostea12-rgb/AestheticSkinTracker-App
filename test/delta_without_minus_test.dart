import 'dart:io';

import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDisplayDeltaWithoutMinus', () {
    test('a worsening points delta has no leading minus', () {
      expect(
        LuxeMetricParser.formatDisplayDeltaWithoutMinus(
          baseline: 8.0,
          current: 2.0,
          deltaPct: -75.0,
        ),
        '6.0 pts',
      );
    });

    test('a worsening percent has no leading minus', () {
      expect(
        LuxeMetricParser.formatDisplayDeltaWithoutMinus(
          baseline: 40.0,
          current: 33.1,
          deltaPct: -17.3,
        ),
        '17.3%',
      );
    });

    test('an improvement keeps its plus sign', () {
      expect(
        LuxeMetricParser.formatDisplayDeltaWithoutMinus(
          baseline: 3.6,
          current: 80.0,
          deltaPct: 2122.2,
        ),
        '+76.4 pts',
      );
      expect(
        LuxeMetricParser.formatDisplayDeltaWithoutMinus(
          baseline: 50.0,
          current: 56.0,
          deltaPct: 12.0,
        ),
        '+12.0%',
      );
    });

    test('the shared signed formatter (and so every delta) is unchanged', () {
      expect(
        LuxeMetricParser.formatDisplayDelta(
          baseline: 8.0,
          current: 2.0,
          deltaPct: -75.0,
          includeSign: true,
        ),
        '-6.0 pts',
      );
    });
  });

  test('Track Procedure tags and cards and the results badge use the '
      'no-minus form', () {
    final procedure = File(
      'lib/features/procedures/presentation/procedure_profiles_screen.dart',
    ).readAsStringSync();
    expect(procedure, isNot(contains('includeSign: true')));
    expect(
      'formatDisplayDeltaWithoutMinus('.allMatches(procedure),
      hasLength(1),
    );
    expect(
      'procedureMetricDeltaText(metric)'.allMatches(procedure),
      hasLength(3),
    );
    expect(procedure, contains('!metric.hasStoredBaselineValue'));
    expect(procedure, contains('if (deltaText != null)'));
    final layout = File(
      'lib/widgets/luxe_report_layout.dart',
    ).readAsStringSync();
    expect(
      layout,
      contains(
        'badgeValueText = LuxeMetricParser.formatDisplayDeltaWithoutMinus(',
      ),
    );
  });
}
