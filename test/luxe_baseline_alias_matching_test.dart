import 'package:flutter_test/flutter_test.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';

void main() {
  group('LuxeMetricParser baseline alias fallback', () {
    test('uses first non-zero alias for texture, pigment, and wrinkle', () {
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

      expect(byKey['localized_redness']?.baselineScore, closeTo(22.5, 0.001));
      expect(byKey['texture_smoothness']?.baselineScore, closeTo(49.0, 0.001));
      expect(byKey['pigment_load']?.baselineScore, closeTo(34.4, 0.001));
      expect(byKey['wrinkle_load']?.baselineScore, closeTo(27.6, 0.001));
    });

    test('skips zero alias and uses next non-zero alias', () {
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

      expect(texture.baselineScore, closeTo(47.3, 0.001));
    });
  });
}
