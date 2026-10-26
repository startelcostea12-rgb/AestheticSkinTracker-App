import 'dart:io';

import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/last_comparable_pair.dart';
import 'package:aesthetic_skin_tracker/utils/skin_metric_labels.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:aesthetic_skin_tracker/widgets/last_comparable_pair_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScanHistoryEntry _scan(
  String id,
  int day, {
  String? comparedWith,
  String pose = 'Front',
  Map<String, String> locks = const {},
  double offset = 0,
}) => ScanHistoryEntry(
  id: id,
  timestamp: DateTime(2026, 10, day, 9, 30),
  scanType: ScanHistoryEntry.scanTypeAiAnalysis,
  estimatedSkinAge: 0,
  metrics: const <String, double>{},
  poseTemplate: pose,
  guideType: 'facial',
  rawPayload: <String, dynamic>{
    'metric_matrix': <String, dynamic>{
      'texture_smoothness': 59.0 + offset,
      'pigment_load': 10.2 + offset,
      'skin_tone_radiance_evenness': 31.0 + offset,
      'structural_firmness_elasticity': 50.5 + offset,
      'pore_visibility': 13.1 + offset,
      'localized_redness': 8.4 + offset,
      'wrinkle_load': 28.0,
    },
    'trend_lock_reasons': locks,
    aiComparisonBaselineScanIdKey: comparedWith,
  },
);

void main() {
  test('face shape label preserves its canonical key and measured value', () {
    const key = 'structural_firmness_elasticity';
    expect(comparablePairMetricLabels[key], 'Face Shape Stability');
    expect(SkinMetricRegistry.skinLaxity.clinicalName, 'Face Shape Stability');
    expect(SkinMetricRegistry.skinLaxity.key, 'elasticity');
    final metrics = LuxeMetricParser.parseTimelinePayload({
      'metric_matrix': {key: 53.2},
      'baseline_metric_matrix': {key: 52.0},
    });
    final metric = metrics.singleWhere((metric) => metric.key == key);
    expect(metric.name, 'Face Shape Stability');
    expect(metric.currentScore, 53.2);
    expect(metric.baselineScore, 52.0);
    expect(metricCardLabel(metric, liveDisplay: true), 'Face Shape Stability');
  });

  group('lastComparablePair', () {
    test('picks the newest compared pair with the same pose and no lock '
        'on the six metrics', () {
      final pair = lastComparablePair([
        _scan('base', 1),
        _scan('a', 2, comparedWith: 'base', offset: 1),
        // Newer, but redness (shown) was locked: not comparable.
        _scan(
          'b',
          3,
          comparedWith: 'base',
          locks: {'localized_redness': 'cheek_mismatch'},
        ),
        // Newer still, different pose than its baseline.
        _scan('c', 4, comparedWith: 'base', pose: 'Left 45°'),
        // Newest, never compared.
        _scan('d', 5),
      ])!;
      expect(pair.latest.id, 'a');
      expect(pair.baseline!.id, 'base');
      expect(pair.latestValue('pigment_load'), closeTo(11.2, 1e-9));
      expect(pair.baselineValue('pigment_load'), closeTo(10.2, 1e-9));
    });

    test('reports lock reasons that applied to other metrics', () {
      final pair = lastComparablePair([
        _scan('base', 1),
        _scan(
          'a',
          2,
          comparedWith: 'base',
          locks: {'wrinkle_load': 'region_position_mismatch'},
        ),
      ])!;
      expect(pair.lockReasons, {'wrinkle_load': 'region_position_mismatch'});
    });

    test('no comparable pair: the latest scan alone', () {
      final pair = lastComparablePair([
        _scan('base', 1),
        _scan('a', 2, comparedWith: 'missing-baseline'),
      ])!;
      expect(pair.hasBaseline, isFalse);
      expect(pair.latest.id, 'a');
      expect(lastComparablePair(const []), isNull);
    });
  });

  group('LastComparablePairCard', () {
    Future<void> pump(WidgetTester tester, ComparablePair pair) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LastComparablePairCard(pair: pair)),
        ),
      );
    }

    testWidgets('shows both timestamps, six absolute values and locks', (
      tester,
    ) async {
      await pump(
        tester,
        lastComparablePair([
          _scan('base', 1),
          _scan(
            'a',
            2,
            comparedWith: 'base',
            offset: 1,
            locks: {'wrinkle_load': 'region_position_mismatch'},
          ),
        ])!,
      );
      expect(find.text('Last comparable pair'), findsOneWidget);
      expect(
        find.text('Oct 1, 2026 · 9:30 AM  and  Oct 2, 2026 · 9:30 AM'),
        findsOneWidget,
      );
      for (final label in comparablePairMetricLabels.values) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('59.0'), findsOneWidget);
      expect(find.text('60.0'), findsOneWidget);
      expect(find.text('9.4'), findsOneWidget); // redness 8.4 + 1
      expect(
        find.textContaining('wrinkle load (region position mismatch)'),
        findsOneWidget,
      );
      expect(find.textContaining('%'), findsNothing);
      for (final icon in const [
        Icons.arrow_upward,
        Icons.arrow_downward,
        Icons.trending_up_rounded,
        Icons.trending_down_rounded,
      ]) {
        expect(find.byIcon(icon), findsNothing);
      }
    });

    testWidgets('alone: latest scan with the no-prior text', (tester) async {
      await pump(tester, lastComparablePair([_scan('only', 3)])!);
      expect(find.text('Latest scan'), findsOneWidget);
      expect(find.text('No prior comparable scan.'), findsOneWidget);
      expect(find.text('Oct 3, 2026 · 9:30 AM'), findsOneWidget);
      expect(find.text('59.0'), findsOneWidget);
    });
  });

  test('home shows the card as the primary card under Welcome back', () {
    final source = File('lib/screens/home_screen.dart').readAsStringSync();
    final welcome = source.indexOf('                _buildWelcomeSection(),');
    final card = source.indexOf('LastComparablePairCard(');
    final protocol = source.indexOf(
      '                _buildProtocolHomeCard(),',
    );
    expect(welcome, isNonNegative);
    expect(card, greaterThan(welcome));
    expect(protocol, greaterThan(card));
  });
}
