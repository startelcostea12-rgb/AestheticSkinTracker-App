import 'dart:convert';
import 'dart:io';

import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/comparable_pair_pdf.dart';
import 'package:aesthetic_skin_tracker/utils/last_comparable_pair.dart';
import 'package:flutter_test/flutter_test.dart';

ScanHistoryEntry _scan(
  String id,
  int day, {
  String? comparedWith,
  double offset = 0,
  Map<String, String> locks = const {},
}) => ScanHistoryEntry(
  id: id,
  timestamp: DateTime(2026, 10, day, 9, 30),
  scanType: ScanHistoryEntry.scanTypeAiAnalysis,
  estimatedSkinAge: 0,
  metrics: const <String, double>{},
  poseTemplate: 'Front',
  guideType: 'facial',
  rawPayload: <String, dynamic>{
    'metric_matrix': <String, dynamic>{
      'texture_smoothness': 59.0 + offset,
      'pigment_load': 10.2 + offset,
      'skin_tone_radiance_evenness': 31.0 + offset,
      'structural_firmness_elasticity': 50.5 + offset,
      'pore_visibility': 13.1 + offset,
      'localized_redness': 8.4 + offset,
    },
    'trend_status': {'texture_smoothness': 'improved'},
    'trend_deltas': {'texture_smoothness': 12.5},
    'trend_lock_reasons': locks,
    aiComparisonBaselineScanIdKey: comparedWith,
  },
);

/// The raw (uncompressed) PDF, and its drawn words joined in order -- the
/// PDF library draws each word as its own `[(word)]TJ`.
Future<({String raw, String text})> _pdf(ComparablePair pair) async {
  final raw = latin1.decode(
    await buildComparablePairPdf(pair, compress: false),
  );
  final words = RegExp(r'\[\((.*?)\)\]TJ')
      .allMatches(raw)
      .map((m) => m.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')'))
      .join(' ');
  return (raw: raw, text: words);
}

void main() {
  test(
    'one page with clinic, both dates, six values and lock reasons',
    () async {
      final pair = lastComparablePair([
        _scan('base', 1),
        _scan(
          'later',
          2,
          comparedWith: 'base',
          offset: 1,
          locks: {'wrinkle_load': 'region_position_mismatch'},
        ),
      ])!;
      final pdf = await _pdf(pair);
      final text = pdf.text;
      expect(pdf.raw, startsWith('%PDF'));
      expect(RegExp(r'/Type\s*/Page\b(?!s)').allMatches(pdf.raw).length, 1);
      for (final expected in [
        '[Clinic name]',
        'Earlier scan: Oct 1, 2026 9:30 AM',
        'Later scan: Oct 2, 2026 9:30 AM',
        ...comparablePairMetricLabels.values,
        '59.0',
        '60.0',
        '8.4',
        '9.4',
        'wrinkle load: region position mismatch',
      ]) {
        expect(text, contains(expected), reason: expected);
      }
    },
  );

  test('no verdicts, arrows or percentages', () async {
    final text = (await _pdf(
      lastComparablePair([
        _scan('base', 1),
        _scan('later', 2, comparedWith: 'base', offset: 1),
      ])!,
    )).text;
    for (final word in ['Improved', 'Worsened', 'Stable', '12.5']) {
      expect(text, isNot(contains(word)), reason: word);
    }
    expect(text, isNot(contains('%')));
    for (final arrow in ['->', '<-', '+']) {
      expect(text, isNot(contains(arrow)), reason: arrow);
    }
  });

  test('the latest scan alone says no prior comparable scan', () async {
    final pdf = await _pdf(lastComparablePair([_scan('only', 3)])!);
    expect(pdf.text, contains('Scan: Oct 3, 2026 9:30 AM'));
    expect(pdf.text, contains('No prior comparable scan.'));
    expect(RegExp(r'/Type\s*/Page\b(?!s)').allMatches(pdf.raw).length, 1);
  });

  test('exported from the scan screen like the CSV (temp dir + share)', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    expect(source, contains("'Export Comparison PDF',"));
    final start = source.indexOf('Future<void> _exportComparisonPdf(');
    final body = source.substring(start, start + 2200);
    expect(body, contains('buildComparablePairPdf(pair)'));
    expect(body, contains('getTemporaryDirectory()'));
    expect(body, contains('Share.shareXFiles('));
  });
}
