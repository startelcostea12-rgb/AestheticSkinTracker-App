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

Widget harness(Map<String, dynamic> payload) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: LuxeReportLayout(
        rawPayload: payload,
        requireBackendVerdict: true,
      ),
    ),
  ),
);

void main() {
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

    for (final score in hiddenMetrics.values) {
      expect(find.text(score.toStringAsFixed(1)), findsOneWidget);
    }
    expect(find.text('Recorded'), findsNothing);
    expect(find.text('Starting point'), findsNothing);
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
        'baseline_metric_matrix': {
          'rosacea_severity': 0.3666666666666667,
        },
        'metric_formula_versions': {'rosacea_severity': 2},
        'baseline_metric_formula_versions': {'rosacea_severity': 2},
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('0.4'), findsOneWidget);
    expect(find.text('Recorded'), findsNothing);
    expect(find.text('Starting point'), findsNothing);
  });

  testWidgets('missing rosacea baseline remains Starting point', (tester) async {
    await tester.pumpWidget(
      harness(const <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': {'rosacea_severity': 0.43333333333333335},
        'metric_formula_versions': {'rosacea_severity': 2},
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('0.4'), findsOneWidget);
    expect(find.text('Starting point'), findsOneWidget);
    expect(find.text('Recorded'), findsNothing);
  });

  testWidgets('stable trusted card has no Starting point subtitle', (
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
}
