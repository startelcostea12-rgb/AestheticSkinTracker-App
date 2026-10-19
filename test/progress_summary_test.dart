import 'dart:io';

import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/screens/progress_summary_screen.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/last_comparable_pair.dart';
import 'package:aesthetic_skin_tracker/utils/progress_summary.dart';
import 'package:aesthetic_skin_tracker/widgets/last_comparable_pair_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScanHistoryEntry _scan(
  String id,
  int day, {
  required Map<String, double> values,
  String? comparedWith,
  Map<String, String> status = const {},
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
    'metric_matrix': values,
    'trend_status': status,
    'trend_lock_reasons': locks,
    aiComparisonBaselineScanIdKey: comparedWith,
  },
);

const _before = <String, double>{
  'texture_smoothness': 59.0,
  'pigment_load': 10.2,
  'skin_tone_radiance_evenness': 31.0,
  'structural_firmness_elasticity': 50.5,
  'pore_visibility': 13.1,
  'localized_redness': 8.4,
};
const _after = <String, double>{
  'texture_smoothness': 63.0, // +4.0, floor 3.0
  'pigment_load': 11.2, // +1.0, floor 2.5
  'skin_tone_radiance_evenness': 31.5,
  'structural_firmness_elasticity': 50.0,
  'pore_visibility': 16.1, // +3.0, floor 2.5
  'localized_redness': 5.0,
};
const _status = <String, String>{
  'texture_smoothness': 'improved',
  'pigment_load': 'worsened',
  'skin_tone_radiance_evenness': 'insufficient_signal',
  'pore_visibility': 'worsened',
  'localized_redness': 'improved',
};

List<ScanHistoryEntry> _history() => [
  _scan('base', 1, values: _before),
  _scan('later', 2, values: _after, comparedWith: 'base', status: _status),
];

void main() {
  test('trend words only where the stored verdict is valid', () {
    final pair = lastComparablePair(_history())!;
    expect(progressTrendLabel(pair, 'texture_smoothness'), 'Improved');
    // Below its 2.5 display floor: Stable, as on the live card.
    expect(progressTrendLabel(pair, 'pigment_load'), 'Stable');
    expect(progressTrendLabel(pair, 'pore_visibility'), 'Worsened');
    // Not a valid verdict: insufficient signal / no status.
    expect(progressTrendLabel(pair, 'skin_tone_radiance_evenness'), isNull);
    expect(progressTrendLabel(pair, 'structural_firmness_elasticity'), isNull);
    // Number-only on the live card: never a trend word.
    expect(progressTrendLabel(pair, 'localized_redness'), isNull);
  });

  test('a lock or a missing baseline means no trend word', () {
    final scans = _history();
    final locked = ComparablePair(
      latest: _scan(
        'later',
        2,
        values: _after,
        comparedWith: 'base',
        status: _status,
        locks: {'texture_smoothness': 'lighting_mismatch'},
      ),
      baseline: scans.first,
    );
    expect(progressTrendLabel(locked, 'texture_smoothness'), isNull);
    final alone = ComparablePair(latest: scans.last);
    expect(progressTrendLabel(alone, 'texture_smoothness'), isNull);
    // A pair with a lock on a shown metric is never the summary's pair.
    expect(
      lastComparablePair([
        scans.first,
        _scan(
          'locked',
          3,
          values: _after,
          comparedWith: 'base',
          locks: {'pigment_load': 'formula_version_mismatch'},
        ),
      ])!.hasBaseline,
      isFalse,
    );
  });

  testWidgets('the screen shows values, valid trends, and value-only rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: ProgressSummaryScreen(scans: _history())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Progress summary'), findsOneWidget);
    String trend(String key) =>
        tester.widget<Text>(find.byKey(ValueKey('progress_trend_$key'))).data!;
    expect(trend('texture_smoothness'), 'Improved');
    expect(trend('pigment_load'), 'Stable');
    expect(trend('localized_redness'), 'Value only');
    expect(trend('skin_tone_radiance_evenness'), 'Value only');
    expect(find.text('59.0  ·  63.0'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a comparable pair: latest values, no trends', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProgressSummaryScreen(
          scans: [_scan('only', 1, values: _before, status: _status)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No prior comparable scan.'), findsOneWidget);
    for (final key in comparablePairMetricKeys) {
      expect(
        tester.widget<Text>(find.byKey(ValueKey('progress_trend_$key'))).data,
        'Value only',
      );
    }
  });

  testWidgets('the home pair card opens the summary', (tester) async {
    var opened = false;
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LastComparablePairCard(
            pair: lastComparablePair(_history())!,
            onOpenSummary: () => opened = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open_progress_summary')));
    expect(opened, isTrue);
    final source = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(source, contains('builder: (_) => const ProgressSummaryScreen(),'));
  });
}
