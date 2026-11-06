import 'dart:io';

import 'package:aesthetic_skin_tracker/utils/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a decline has no leading minus', () {
    expect(reportChangeText(-17.3), '17.3%');
    expect(reportChangeText(-0.04), '0.0%');
  });

  test('an improvement keeps its plus sign', () {
    expect(reportChangeText(12.0), '+12.0%');
    expect(reportChangeText(0.0), '+0.0%');
  });

  test('a locked comparison shows no percent', () {
    expect(reportChangeText(-17.3, locked: true), '—');
    expect(reportChangeText(12.0, locked: true), '—');
  });

  test('every report change cell uses the helper; no signed minus remains', () {
    final source = File('lib/utils/report_service.dart').readAsStringSync();
    expect('reportChangeText('.allMatches(source).length, 4); // 1 def + 3 uses
    expect(source, isNot(contains("? '+' : '-'")));
    expect(source, contains('reportDisplayClaimAllowed('));
    expect(source, contains("? 'Not comparable'"));
  });

  test(
    'PDF claims use the drift and existing floor without changing values',
    () {
      expect(reportDisplayClaimAllowed('pigment_load', 20, 25), isFalse);
      expect(reportDisplayClaimAllowed('pigment_load', 20, 26), isTrue);
      expect(reportDisplayClaimAllowed('darkSpots', 2, 2.5), isFalse);
      expect(reportDisplayClaimAllowed('darkSpots', 2, 2.6), isTrue);
      expect(
        reportDisplayClaimAllowed('texture_smoothness', 20, 25.4),
        isFalse,
      );
      expect(reportDisplayClaimAllowed('texture_smoothness', 20, 25.5), isTrue);
      expect(reportDisplayClaimAllowed('wrinkle_load', 20, 90), isFalse);
      expect(
        reportDisplayClaimAllowed(
          'pigment_load',
          20,
          90,
          lockReason: 'lighting_mismatch',
        ),
        isFalse,
      );
    },
  );
}
