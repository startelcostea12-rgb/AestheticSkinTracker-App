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
    expect(source, contains('locked: resolvedTrend?.lockShortLabel != null'));
  });
}
