import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> exposurePayload({
  required double? iso,
  required double? brightnessValue,
}) => <String, dynamic>{
  aiScanPerFrameDiagnosticsKey: <Map<String, dynamic>>[
    <String, dynamic>{'iso': iso, 'brightness_value': brightnessValue},
    <String, dynamic>{'iso': iso, 'brightness_value': brightnessValue},
    <String, dynamic>{'iso': iso, 'brightness_value': brightnessValue},
  ],
};

void main() {
  group('lockTrendsForLightingMismatch', () {
    test('Bv 0.92 vs 3.77 locks every compared metric', () {
      final result = lockTrendsForLightingMismatch(
        trendStatus: const <String, String>{
          'localized_redness': 'improved',
          'texture_smoothness': 'improved',
          'pigment_load': 'improved',
          'skin_tone_radiance_evenness': 'improved',
          'structural_firmness_elasticity': 'stable',
          'rosacea_severity': 'improved',
          'wrinkle_load': 'worsened',
          'pore_visibility': 'stable',
        },
        trendDeltas: const <String, double>{
          'localized_redness': 25.0,
          'texture_smoothness': 12.0,
          'pigment_load': 51.4,
          'skin_tone_radiance_evenness': 15.0,
          'structural_firmness_elasticity': 0.0,
          'rosacea_severity': 93.1,
          'wrinkle_load': -20.7,
          'pore_visibility': 0.0,
        },
        trendLockReasons: const <String, String>{},
        baselinePayload: exposurePayload(iso: 160, brightnessValue: 0.92),
        currentPayload: exposurePayload(iso: 80, brightnessValue: 3.77),
      );

      for (final metric in const <String>[
        'localized_redness',
        'texture_smoothness',
        'pigment_load',
        'skin_tone_radiance_evenness',
        'structural_firmness_elasticity',
        'rosacea_severity',
        'wrinkle_load',
        'pore_visibility',
      ]) {
        expect(result.trendStatus.containsKey(metric), isFalse);
        expect(result.trendDeltas.containsKey(metric), isFalse);
        expect(result.trendLockReasons[metric], 'lighting_mismatch');
      }
    });

    test('Bv 3.49 vs 3.77 remains comparable', () {
      final result = lockTrendsForLightingMismatch(
        trendStatus: const {'pore_visibility': 'stable'},
        trendDeltas: const {'pore_visibility': 0.0},
        trendLockReasons: const <String, String>{},
        baselinePayload: exposurePayload(iso: 100, brightnessValue: 3.49),
        currentPayload: exposurePayload(iso: 100, brightnessValue: 3.77),
      );

      expect(result.trendStatus, {'pore_visibility': 'stable'});
      expect(result.trendDeltas, {'pore_visibility': 0.0});
      expect(result.trendLockReasons, isEmpty);
    });

    test('missing ISO or Bv locks comparisons', () {
      for (final pair in <({Map<String, dynamic> baseline, Map<String, dynamic> current})>[
        (
          baseline: exposurePayload(iso: null, brightnessValue: 3.5),
          current: exposurePayload(iso: 100, brightnessValue: 3.6),
        ),
        (
          baseline: exposurePayload(iso: 100, brightnessValue: null),
          current: exposurePayload(iso: 100, brightnessValue: 3.6),
        ),
        (
          baseline: exposurePayload(iso: 100, brightnessValue: 3.5),
          current: exposurePayload(iso: null, brightnessValue: null),
        ),
      ]) {
        final result = lockTrendsForLightingMismatch(
          trendStatus: const {'texture_smoothness': 'improved'},
          trendDeltas: const {'texture_smoothness': 12.0},
          trendLockReasons: const <String, String>{},
          baselinePayload: pair.baseline,
          currentPayload: pair.current,
        );
        expect(result.trendStatus.containsKey('texture_smoothness'), isFalse);
        expect(result.trendDeltas.containsKey('texture_smoothness'), isFalse);
        expect(
          result.trendLockReasons['texture_smoothness'],
          'lighting_mismatch',
        );
      }
    });

    test('any existing lock reason clears status and delta', () {
      final result = clearLockedTrendVerdicts(
        trendStatus: const {
          'localized_redness': 'stable',
          'texture_smoothness': 'improved',
        },
        trendDeltas: const {
          'localized_redness': 0.0,
          'texture_smoothness': 12.0,
        },
        trendLockReasons: const {
          'localized_redness': 'cheek_mismatch',
        },
      );

      expect(result.trendStatus.containsKey('localized_redness'), isFalse);
      expect(result.trendDeltas.containsKey('localized_redness'), isFalse);
      expect(result.trendStatus['texture_smoothness'], 'improved');
      expect(result.trendDeltas['texture_smoothness'], 12.0);
    });

    test('exactly one Bv unit remains comparable', () {
      final result = lockTrendsForLightingMismatch(
        trendStatus: const {'pigment_load': 'improved'},
        trendDeltas: const {'pigment_load': 10.0},
        trendLockReasons: const <String, String>{},
        baselinePayload: exposurePayload(iso: 100, brightnessValue: 2.0),
        currentPayload: exposurePayload(iso: 100, brightnessValue: 3.0),
      );

      expect(result.trendStatus['pigment_load'], 'improved');
      expect(result.trendLockReasons, isEmpty);
    });
  });
}
