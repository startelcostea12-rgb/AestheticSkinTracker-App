import 'package:aesthetic_skin_tracker/screens/progress_report_screen.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const hiddenMetrics = <String, double>{
  'wrinkle_load': 45.4,
  'rosacea_severity': 0.43,
  'diffuse_flushing_erythema': 1.2,
  'pore_contraction_index': 22.0,
  'under_eye_dark_circle_density': 18.0,
  'under_eye_texture_density': 14.0,
};

Widget harness(Map<String, dynamic> payload, {bool liveDisplay = false}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LuxeReportLayout(
            rawPayload: payload,
            requireBackendVerdict: true,
            applyDisplayNoiseFloors: liveDisplay,
          ),
        ),
      ),
    );

void main() {
  test('worsening progress percent displays magnitude without a minus', () {
    expect(
      formatProgressReportTrendPercent(
        trendLabel: 'Worsened',
        percentDelta: -17.3,
        isWorsened: true,
      ),
      'Worsened 17.3%',
    );
  });

  test('improving progress percent retains its positive sign', () {
    expect(
      formatProgressReportTrendPercent(
        trendLabel: 'Improved',
        percentDelta: 17.3,
        isWorsened: false,
      ),
      'Improved +17.3%',
    );
  });

  for (final delta in const [-17.3, 17.3, -0.01, 0.0]) {
    test('worsening percent badges are unsigned for delta $delta', () {
      final progressBadge = formatProgressReportTrendPercent(
        trendLabel: 'Worsened',
        percentDelta: delta,
        isWorsened: true,
      );
      expect(progressBadge, 'Worsened ${delta.abs().toStringAsFixed(1)}%');
      final resultBadge = LuxeMetricParser.formatDisplayDelta(
        baseline: 40.0,
        current: 47.0,
        deltaPct: delta,
        includeSign: true,
      );
      expect(resultBadge, isNot(contains('-')));
      expect(resultBadge, isNot(contains('\u2212')));
    });
  }

  test(
    'negative percentage cap stays unsigned without changing point display',
    () {
      expect(
        LuxeMetricParser.formatDisplayDelta(
          baseline: 40.0,
          current: 47.0,
          deltaPct: -275.0,
          includeSign: true,
        ),
        '100.0%',
      );
      expect(
        LuxeMetricParser.formatDisplayDelta(
          baseline: 8.0,
          current: 2.0,
          deltaPct: -75.0,
          includeSign: true,
        ),
        '-6.0 pts',
      );
    },
  );

  for (final entry in hiddenMetrics.entries) {
    testWidgets('${entry.key} worsening badge has no percent and keeps locks', (
      tester,
    ) async {
      final payload = <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': {entry.key: entry.value},
        'baseline_metric_matrix': {entry.key: entry.value + 10.0},
        'metric_extraction_paths': {entry.key: 'primary_roi'},
        'baseline_metric_extraction_paths': {entry.key: 'primary_roi'},
        'trend_status': {entry.key: 'worsened'},
        'trend_deltas': {entry.key: -17.3},
      };
      await tester.pumpWidget(harness(payload));
      await tester.pumpAndSettle();

      final card = find.byKey(ValueKey('result_metric_${entry.key}'));
      expect(
        find.descendant(of: card, matching: find.textContaining('%')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Worsened')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text(entry.value.toStringAsFixed(1)),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        harness({
          ...payload,
          'trend_status': {entry.key: 'stable'},
          'trend_deltas': {entry.key: 0.0},
          'trend_lock_reasons': {entry.key: 'path_mismatch'},
        }, liveDisplay: true),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Not comparable'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('%')),
        findsNothing,
      );
    });
  }

  testWidgets('six untrusted metrics show values without verdicts or percent', (
    tester,
  ) async {
    final metricMatrix = <String, dynamic>{
      ...hiddenMetrics,
      'texture_smoothness': 60.0,
    };
    final baselineMatrix = <String, dynamic>{
      for (final entry in hiddenMetrics.entries) entry.key: entry.value + 1.0,
      'texture_smoothness': 60.5,
    };
    final paths = <String, dynamic>{
      for (final key in metricMatrix.keys) key: 'primary_roi',
    };
    final statuses = <String, dynamic>{
      'wrinkle_load': 'worsened',
      'rosacea_severity': 'improved',
      'diffuse_flushing_erythema': 'stable',
      'pore_contraction_index': 'improved',
      'under_eye_dark_circle_density': 'worsened',
      'under_eye_texture_density': 'stable',
      'texture_smoothness': 'stable',
    };
    final deltas = <String, dynamic>{
      'wrinkle_load': -17.3,
      'rosacea_severity': 12.0,
      'diffuse_flushing_erythema': 0.0,
      'pore_contraction_index': 10.0,
      'under_eye_dark_circle_density': -20.0,
      'under_eye_texture_density': 0.0,
      'texture_smoothness': 0.0,
    };

    await tester.pumpWidget(
      harness(<String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': metricMatrix,
        'baseline_metric_matrix': baselineMatrix,
        'metric_extraction_paths': paths,
        'baseline_metric_extraction_paths': paths,
        'trend_status': statuses,
        'trend_deltas': deltas,
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recorded'), findsNothing);
    for (final score in hiddenMetrics.values) {
      expect(find.text(score.toStringAsFixed(1)), findsOneWidget);
    }
    for (final label in const [
      'Wrinkle Load',
      'Rosacea Severity',
      'Diffuse Flushing Erythema',
      'Pore Contraction Index',
      'Under Eye Dark Circle Density',
      'Under Eye Texture Density',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Stable - change within tracking noise'), findsOneWidget);
    expect(find.text('Improved'), findsNothing);
    expect(find.text('Worsened'), findsNothing);
    expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
    expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    expect(find.textContaining('17.3%'), findsNothing);
    expect(find.textContaining('20.0%'), findsNothing);
  });

  testWidgets('real low rosacea baseline shows its value, not Starting point', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': {'rosacea_severity': 0.43333333333333335},
        'baseline_metric_matrix': {'rosacea_severity': 0.3666666666666667},
        'metric_formula_versions': {'rosacea_severity': 2},
        'baseline_metric_formula_versions': {'rosacea_severity': 2},
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recorded'), findsNothing);
    expect(find.text('Starting point'), findsNothing);
    expect(find.text('Rosacea Severity'), findsOneWidget);
    expect(find.text('0.4'), findsOneWidget);
    expect(find.textContaining('4.3'), findsNothing);
  });

  testWidgets('missing rosacea baseline still shows its current value', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': {'rosacea_severity': 0.43333333333333335},
        'metric_formula_versions': {'rosacea_severity': 2},
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Starting point'), findsNothing);
    expect(find.text('Recorded'), findsNothing);
    expect(find.text('Rosacea Severity'), findsOneWidget);
    expect(find.text('0.4'), findsOneWidget);
  });

  testWidgets('stable trusted metric does not say Starting point', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': {'texture_smoothness': 60.0},
        'trend_status': {'texture_smoothness': 'stable'},
        'trend_deltas': {'texture_smoothness': 0.0},
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stable - change within tracking noise'), findsOneWidget);
    expect(find.textContaining('Starting point'), findsNothing);
  });

  test('worsening percentage drops the leading minus sign', () {
    expect(
      LuxeMetricParser.formatDisplayDelta(
        baseline: 40.0,
        current: 47.0,
        deltaPct: -17.3,
        includeSign: true,
      ),
      '17.3%',
    );
  });

  test('progress report keeps canonical rosacea on the backend scale', () {
    final value = ScanDetailScreen.normalizeMetricValueTo100(
      'rosacea_severity',
      0.43333333333333335,
    );
    expect(value.toStringAsFixed(1), '0.4');
  });
}
