import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';

void main() {
  group('LuxeMetricParser baseline alias fallback', () {
    test('explicit canonical zero wins over non-zero legacy aliases', () {
      final payload = <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 25,
        'initial_baseline': false,
        'metric_matrix': <String, dynamic>{
          'localized_redness': 31.2,
          'texture_smoothness': 58.4,
          'pigment_load': 44.1,
          'wrinkle_load': 36.8,
          'pore_visibility': 52.0,
          'breakout_activity': 18.0,
        },
        'baseline_metric_matrix': <String, dynamic>{
          'localized_redness': 0.0,
          'texture_smoothness': 0.0,
          'pigment_load': 0.0,
          'wrinkle_load': 0.0,
          // Redness existing behavior
          'calibrated_redness_score': 22.5,
          // Texture aliases
          'smoothness_score': 0.0,
          'calibrated_smoothness_score': 49.0,
          // Pigment aliases
          'pigment_score': 0.0,
          'skin_tone_radiance_evenness': 34.4,
          // Wrinkle aliases
          'wrinkle_score': 0.0,
          'glabellar_wrinkle_depth': 27.6,
        },
      };

      final metrics = LuxeMetricParser.parseTimelinePayload(payload);
      final byKey = {for (final m in metrics) m.key: m};

      expect(byKey['localized_redness']?.baselineScore, 0.0);
      expect(byKey['texture_smoothness']?.baselineScore, 0.0);
      expect(byKey['pigment_load']?.baselineScore, 0.0);
      expect(byKey['wrinkle_load']?.baselineScore, 0.0);
    });

    test('keeps explicit canonical zero instead of using a legacy alias', () {
      final payload = <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 25,
        'initial_baseline': false,
        'metric_matrix': <String, dynamic>{
          'texture_smoothness': 61.0,
        },
        'baseline_metric_matrix': <String, dynamic>{
          'texture_smoothness': 0.0,
          'smoothness_score': 0.0,
          'calibrated_smoothness_score': 47.3,
        },
      };

      final metrics = LuxeMetricParser.parseTimelinePayload(payload);
      final texture = metrics.firstWhere((m) => m.key == 'texture_smoothness');

      expect(texture.baselineScore, 0.0);
      expect(texture.hasBaselineValue, isTrue);
    });

    test('pore visibility ignores contraction and legacy pore baselines', () {
      final payload = <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'initial_baseline': false,
        'metric_matrix': <String, dynamic>{'pore_visibility': 52.0},
        'baseline_metric_matrix': <String, dynamic>{
          'pore_contraction_index': 24.0,
          'pore': 36.0,
          'pore_score': 48.0,
        },
      };

      final metrics = LuxeMetricParser.parseTimelinePayload(payload);
      final pores = metrics.firstWhere((m) => m.key == 'pore_visibility');

      expect(pores.hasBaselineValue, isFalse);
      expect(pores.baselineScore, 0.0);
      expect(pores.improvementPercent, 0.0);
    });

    test(
      'pore visibility compares against a canonical visibility baseline',
      () {
        final payload = <String, dynamic>{
          'is_follow_up': true,
          'local_history_count': 2,
          'initial_baseline': false,
          'metric_matrix': <String, dynamic>{'pore_visibility': 52.0},
          'baseline_metric_matrix': <String, dynamic>{'pore_visibility': 40.0},
        };

        final metrics = LuxeMetricParser.parseTimelinePayload(payload);
        final pores = metrics.firstWhere((m) => m.key == 'pore_visibility');

        expect(pores.hasBaselineValue, isTrue);
        expect(pores.baselineScore, 40.0);
        expect(pores.improvementPercent, 30.0);
      },
    );

    testWidgets('missing pore visibility baseline shows no direction', (
      tester,
    ) async {
      final payload = <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'initial_baseline': false,
        'metric_matrix': <String, dynamic>{'pore_visibility': 52.0},
        'baseline_metric_matrix': <String, dynamic>{
          'pore_contraction_index': 24.0,
        },
        'metric_confidence': <String, dynamic>{'pore_visibility': 'high'},
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LuxeReportLayout(rawPayload: payload)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pore Visibility'), findsOneWidget);
      expect(find.text('Improved'), findsNothing);
      expect(find.text('Worsened'), findsNothing);
    });
  });
}
