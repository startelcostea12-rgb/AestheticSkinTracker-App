import 'package:aesthetic_skin_tracker/utils/untrusted_trend_metrics.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _keys = [
  'texture_smoothness',
  'pigment_load',
  'pore_visibility',
  'skin_tone_radiance_evenness',
  'structural_firmness_elasticity',
  'localized_redness',
  'diffuse_flushing_erythema',
  'rosacea_severity',
  'wrinkle_load',
  'pore_contraction_index',
  'under_eye_dark_circle_density',
  'under_eye_texture_density',
];

LuxeMetric _metric(String key, {required bool stored, bool current = true}) =>
    LuxeMetric(
      key: key,
      name: key,
      baselineScore: 0.0,
      currentScore: 21.0,
      improvementPercent: 0.0,
      lowerIsBetter: true,
      hasComparableCurrentValue: current,
      hasStoredBaselineValue: stored,
    );

void main() {
  test('stored baseline: number, or Recorded for untrusted metrics', () {
    for (final key in _keys) {
      final label = storedBaselineLabelFor(_metric(key, stored: true));
      expect(
        label,
        untrustedTrendVerdictMetrics.contains(key) ? 'Recorded' : '21.0',
        reason: key,
      );
      expect(label, isNot('Starting point'));
    }
    expect(
      storedBaselineLabelFor(
        _metric('pigment_load', stored: true, current: false),
      ),
      'Not compared',
    );
  });

  test('no stored baseline: Starting point stays', () {
    for (final key in _keys) {
      expect(storedBaselineLabelFor(_metric(key, stored: false)), isNull);
    }
  });

  test('the parser flags any stored baseline value, even unusable ones', () {
    for (final stored in [0.3, 20.0, 99.9, 0.0]) {
      final metrics = LuxeMetricParser.parseTimelinePayload({
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': {for (final k in _keys) k: 21.0},
        'baseline_metric_matrix': {for (final k in _keys) k: stored},
      });
      for (final m in metrics) {
        expect(m.hasStoredBaselineValue, isTrue, reason: '${m.key} $stored');
      }
    }
    final missing = LuxeMetricParser.parseTimelinePayload({
      'metric_matrix': {for (final k in _keys) k: 21.0},
    });
    for (final m in missing) {
      expect(m.hasStoredBaselineValue, isFalse, reason: m.key);
    }
  });

  for (final live in [false, true]) {
    for (final followUp in [true, false]) {
      testWidgets('no metric card says Starting point with a stored baseline '
          '(live=$live, follow-up=$followUp)', (tester) async {
        await tester.binding.setSurfaceSize(const Size(500, 6000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final stored in [0.3, 20.0, 99.9]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: LuxeReportLayout(
                    requireBackendVerdict: live,
                    applyDisplayNoiseFloors: live,
                    rawPayload: {
                      'is_follow_up': followUp,
                      'local_history_count': followUp ? 2 : 1,
                      'metric_matrix': {for (final k in _keys) k: 21.0},
                      'baseline_metric_matrix': {
                        for (final k in _keys) k: stored,
                      },
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final key in _keys) {
            final card = find.byKey(ValueKey('result_metric_$key'));
            if (card.evaluate().isEmpty) continue;
            expect(
              find.descendant(
                of: card,
                matching: find.textContaining('Starting point'),
              ),
              findsNothing,
              reason: '$key baseline=$stored',
            );
          }
        }
      });
    }
  }
}
