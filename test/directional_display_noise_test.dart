import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/display_noise_floors.dart';
import 'package:aesthetic_skin_tracker/utils/last_comparable_pair.dart';
import 'package:aesthetic_skin_tracker/utils/progress_summary.dart';
import 'package:aesthetic_skin_tracker/widgets/last_comparable_pair_card.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payload(
  String key,
  double move,
  String status, {
  String? lock,
  bool wide = false,
}) => {
  'is_follow_up': true,
  'local_history_count': 2,
  'metric_matrix': {key: 20.0 + move},
  'baseline_metric_matrix': {key: 20.0},
  'metric_extraction_paths': {key: 'primary_roi'},
  'baseline_metric_extraction_paths': {key: 'primary_roi'},
  'trend_status': {key: status},
  'trend_deltas': {key: move * 5.0},
  'trend_lock_reasons': {if (lock != null) key: lock},
  if (wide) 'metric_noise_floor_2sd': {key: 4.0},
  if (wide)
    'multi_frame_analysis': {
      'metric_ranges': {
        key: {'min': 5.0, 'max': 45.0, 'count': 3},
      },
      'metric_contributor_counts': {key: 3},
    },
};

ComparablePair _pair(Map<String, dynamic> payload, String key) =>
    ComparablePair(
      baseline: ScanHistoryEntry(
        id: 'baseline',
        timestamp: DateTime.utc(2026, 11, 1),
        estimatedSkinAge: 0,
        metrics: const {},
        rawPayload: {
          'metric_matrix': {key: 20.0},
        },
      ),
      latest: ScanHistoryEntry(
        id: 'latest',
        timestamp: DateTime.utc(2026, 11, 2),
        estimatedSkinAge: 0,
        metrics: const {},
        rawPayload: payload,
      ),
    );

Future<void> _results(WidgetTester tester, Map<String, dynamic> payload) async {
  await tester.binding.setSurfaceSize(const Size(600, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LuxeReportLayout(
            rawPayload: payload,
            requireBackendVerdict: true,
            applyDisplayNoiseFloors: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

String _cardText(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey('result_metric_$key')),
        matching: find.byType(Text),
      ),
    )
    .map((widget) => widget.data ?? '')
    .join('\n');

void main() {
  test('texture uses its existing 5.4 floor above the lamp drift', () {
    expect(displayVerdictNoiseFloors['texture_smoothness'], 5.4);
    expect(exceedsDisplayClaimBar('texture_smoothness', 25.4, 20), isFalse);
    expect(exceedsDisplayClaimBar('texture_smoothness', 25.5, 20), isTrue);
    expect(lampScanDriftSource, contains('ISO 100 or 125'));
    expect(lampScanDriftSource, contains('gray card not applied'));
  });

  final cases = [
    (
      key: 'glabellar_wrinkle_depth',
      move: 6.4,
      status: 'worsened',
      label: null,
    ),
    (
      key: 'glabellar_wrinkle_depth',
      move: 7.0,
      status: 'worsened',
      label: 'Worsened',
    ),
    (
      key: 'skin_tone_radiance_evenness',
      move: 0.8,
      status: 'improved',
      label: null,
    ),
    (
      key: 'skin_tone_radiance_evenness',
      move: 8.0,
      status: 'improved',
      label: 'Improved',
    ),
    (key: 'pigment_load', move: 5.0, status: 'worsened', label: null),
    (key: 'pigment_load', move: 6.0, status: 'worsened', label: 'Worsened'),
    (
      key: 'structural_firmness_elasticity',
      move: 4.5,
      status: 'improved',
      label: null,
    ),
    (
      key: 'structural_firmness_elasticity',
      move: 9.0,
      status: 'improved',
      label: 'Improved',
    ),
    (key: 'texture_smoothness', move: 5.3, status: 'improved', label: null),
    (
      key: 'texture_smoothness',
      move: 5.5,
      status: 'improved',
      label: 'Improved',
    ),
    (key: 'pore_visibility', move: 4.5, status: 'worsened', label: null),
    (key: 'pore_visibility', move: 5.0, status: 'worsened', label: 'Worsened'),
  ];
  for (final sample in cases) {
    testWidgets(
      '${sample.key} move ${sample.move} agrees on all three surfaces',
      (tester) async {
        final payload = _payload(sample.key, sample.move, sample.status);
        await _results(tester, payload);
        final text = _cardText(tester, sample.key);
        if (sample.label != null) expect(text, contains(sample.label!));
        expect(text, contains((20.0 + sample.move).toStringAsFixed(1)));
        if (sample.label != null) {
          expect(
            find.textContaining(
              '${liveResultsShortLabels[sample.key]}: ${sample.label}.',
            ),
            findsWidgets,
          );
        } else {
          expect(text, isNot(contains('%')));
          expect(text, isNot(contains('Improved')));
          expect(text, isNot(contains('Worsened')));
          expect(text, isNot(contains('Stable')));
          expect(text, isNot(contains('->')));
        }
        final pair = _pair(payload, sample.key);
        expect(progressTrendLabel(pair, sample.key), sample.label);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: LastComparablePairCard(pair: pair)),
          ),
        );
        await tester.pumpAndSettle();
        final trend = find.byKey(ValueKey('last_pair_trend_${sample.key}'));
        if (sample.label == null) {
          expect(trend, findsNothing);
        } else {
          expect(tester.widget<Text>(trend).data, sample.label);
        }
        expect(find.textContaining('%'), findsNothing);
        expect(payload['metric_matrix'], {sample.key: 20.0 + sample.move});
        expect(payload['trend_status'], {sample.key: sample.status});
      },
    );
  }

  for (final entry in lampScanDriftSpans.entries) {
    testWidgets('${entry.key} at the exact drift has no claim', (tester) async {
      final payload = _payload(entry.key, entry.value, 'worsened');
      await _results(tester, payload);
      final text = _cardText(tester, entry.key);
      expect(text, isNot(contains('Stable')));
      expect(text, isNot(contains('Worsened')));
      expect(text, isNot(contains('%')));
      expect(progressTrendLabel(_pair(payload, entry.key), entry.key), isNull);
    });
  }

  for (final lock in ['lighting_mismatch', 'formula_version_mismatch']) {
    testWidgets('$lock beats the display floor', (tester) async {
      final payload = _payload('pigment_load', 2.5, 'improved', lock: lock);
      await _results(tester, payload);
      final text = _cardText(tester, 'pigment_load');
      expect(text, contains('Not comparable'));
      expect(text, isNot(contains('Stable')));
      expect(text, isNot(contains('Improved')));
      expect(
        progressTrendLabel(_pair(payload, 'pigment_load'), 'pigment_load'),
        'Not comparable',
      );
    });
  }

  testWidgets('a measured-zero Elevens card renders under its short label', (
    tester,
  ) async {
    final payload = _payload('glabellar_wrinkle_depth', 0, 'stable');
    payload['metric_matrix'] = {'glabellar_wrinkle_depth': 0.0};
    payload['baseline_metric_matrix'] = {'glabellar_wrinkle_depth': 0.0};
    await _results(tester, payload);
    final text = _cardText(tester, 'glabellar_wrinkle_depth');
    expect(text, contains('Elevens'));
    expect(text, contains('0.0'));
    expect(text, isNot(contains('Glabellar Wrinkle Depth')));
    expect(text, isNot(contains('Stable')));
    expect(text, isNot(contains('%')));
  });

  test(
    'Elevens is independent from the wrinkles baseline and has no drift entry',
    () {
      final metrics = LuxeMetricParser.parseTimelinePayload({
        'metric_matrix': {'wrinkle_load': 40.0, 'glabellar_wrinkle_depth': 0.0},
        'baseline_metric_matrix': {'glabellar_wrinkle_depth': 20.0},
      });
      final wrinkles = metrics.singleWhere(
        (metric) => metric.key == 'wrinkle_load',
      );
      final elevens = metrics.singleWhere(
        (metric) => metric.key == 'glabellar_wrinkle_depth',
      );
      expect(wrinkles.hasBaselineValue, isFalse);
      expect(wrinkles.hasStoredBaselineValue, isFalse);
      expect(elevens.name, 'Elevens');
      expect(elevens.currentScore, 0.0);
      expect(elevens.baselineScore, 20.0);
      expect(displayVerdictNoiseFloors['glabellar_wrinkle_depth'], 6.4);
      expect(
        lampScanDriftSpans.containsKey('glabellar_wrinkle_depth'),
        isFalse,
      );
    },
  );

  testWidgets('a locked Elevens row stays Not comparable', (tester) async {
    final payload = _payload(
      'glabellar_wrinkle_depth',
      7,
      'improved',
      lock: 'lighting_mismatch',
    );
    await _results(tester, payload);
    final text = _cardText(tester, 'glabellar_wrinkle_depth');
    expect(text, contains('Not comparable'));
    expect(text, isNot(contains('Glabellar Wrinkle Depth')));
    expect(text, isNot(contains('Improved')));
    expect(text, isNot(contains('Stable')));
    expect(text, isNot(contains('%')));
    expect(
      progressTrendLabel(
        _pair(payload, 'glabellar_wrinkle_depth'),
        'glabellar_wrinkle_depth',
      ),
      'Not comparable',
    );
  });

  testWidgets('a locked row without a stored baseline stays Not comparable', (
    tester,
  ) async {
    final payload = _payload(
      'wrinkle_load',
      50,
      'improved',
      lock: 'lighting_mismatch',
    )..remove('baseline_metric_matrix');
    await _results(tester, payload);
    final text = _cardText(tester, 'wrinkle_load');
    expect(text, contains('Not comparable'));
    expect(text, isNot(contains('Improved')));
    expect(text, isNot(contains('Stable')));
    expect(text, isNot(contains('%')));
  });

  testWidgets('a locked wrinkle row stays Not comparable', (tester) async {
    final payload = _payload(
      'wrinkle_load',
      50,
      'improved',
      lock: 'lighting_mismatch',
    );
    await _results(tester, payload);
    final text = _cardText(tester, 'wrinkle_load');
    expect(text, contains('Not comparable'));
    expect(text, isNot(contains('Improved')));
    expect(text, isNot(contains('Stable')));
    expect(text, isNot(contains('%')));
    expect(
      progressTrendLabel(_pair(payload, 'wrinkle_load'), 'wrinkle_load'),
      'Not comparable',
    );
  });

  testWidgets(
    'wide frame range is Not comparable despite a large average move',
    (tester) async {
      final payload = _payload(
        'skin_tone_radiance_evenness',
        10.0,
        'improved',
        wide: true,
      );
      await _results(tester, payload);
      final text = _cardText(tester, 'skin_tone_radiance_evenness');
      expect(text, contains('Not comparable'));
      expect(text, isNot(contains('Improved')));
      expect(find.textContaining('Radiance: Not comparable'), findsWidgets);
      final pair = _pair(payload, 'skin_tone_radiance_evenness');
      expect(
        progressTrendLabel(pair, 'skin_tone_radiance_evenness'),
        'Not comparable',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LastComparablePairCard(pair: pair)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const ValueKey('last_pair_trend_skin_tone_radiance_evenness'),
              ),
            )
            .data,
        'Not comparable',
      );
    },
  );

  for (final key in [
    'wrinkle_load',
    'rosacea_severity',
    'diffuse_flushing_erythema',
    'under_eye_dark_circle_density',
    'under_eye_texture_density',
    'pore_contraction_index',
  ]) {
    testWidgets('$key stays number-only', (tester) async {
      await _results(tester, _payload(key, 15.0, 'improved'));
      final text = _cardText(tester, key);
      expect(text, isNot(contains('Improved')));
      expect(text, isNot(contains('Worsened')));
      expect(text, isNot(contains('%')));
    });
  }
}
