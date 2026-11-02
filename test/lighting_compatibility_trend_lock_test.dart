import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'dart:io';
import 'package:aesthetic_skin_tracker/utils/trend_lock_reason.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
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
  group('pigment-only scene color comparison', () {
    Map<String, dynamic> payload(double? sceneColor, {double bv = 3.0}) => {
      ...exposurePayload(iso: 100, brightnessValue: bv),
      'image_quality': {
        if (sceneColor != null) 'whole_image_mean_a_before_wb': sceneColor,
        'chroma_cast': 0.0,
      },
    };

    ({
      Map<String, String> trendStatus,
      Map<String, double> trendDeltas,
      Map<String, String> trendLockReasons,
    })
    compare(
      double? baseline,
      double? current, {
      double bv = 3.0,
      bool nested = false,
    }) {
      final baselinePayload = payload(baseline);
      final currentPayload = payload(current, bv: bv);
      final lighting = lockTrendsForLightingMismatch(
        trendStatus: {
          'pigment_load': 'worsened',
          'texture_smoothness': 'stable',
          'localized_redness': 'improved',
        },
        trendDeltas: {
          'pigment_load': -75.3,
          'texture_smoothness': 0.0,
          'localized_redness': 10.0,
        },
        trendLockReasons: {},
        baselinePayload: baselinePayload,
        currentPayload: currentPayload,
      );
      return lockPigmentTrendForSceneColorMismatch(
        trendStatus: lighting.trendStatus,
        trendDeltas: lighting.trendDeltas,
        trendLockReasons: lighting.trendLockReasons,
        baselinePayload: nested
            ? {'metrics': baselinePayload}
            : baselinePayload,
        currentPayload: nested ? {'metrics': currentPayload} : currentPayload,
      );
    }

    test(
      '3.2 locks pigment only while texture stays stable at matching Bv',
      () {
        for (final nested in [false, true]) {
          final result = compare(11.3, 8.1, nested: nested);
          expect(result.trendLockReasons, {
            'pigment_load': 'scene_color_mismatch',
          });
          expect(result.trendStatus, {
            'texture_smoothness': 'stable',
            'localized_redness': 'improved',
          });
          expect(result.trendDeltas, {
            'texture_smoothness': 0.0,
            'localized_redness': 10.0,
          });
        }
      },
    );

    test('2.3 and exactly 3.0 remain comparable in either direction', () {
      for (final current in [7.7, 12.3, 7.0, 13.0]) {
        final result = compare(10.0, current);
        expect(result.trendLockReasons, isEmpty);
        expect(result.trendStatus['pigment_load'], 'worsened');
        expect(result.trendDeltas['pigment_load'], -75.3);
      }
    });

    test('missing or non-finite scene color on either scan does not lock', () {
      for (final missing in [
        null,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        for (final result in [compare(missing, 8.1), compare(11.3, missing)]) {
          expect(result.trendLockReasons, isEmpty);
          expect(result.trendStatus['pigment_load'], 'worsened');
        }
      }
    });

    test('Bv mismatch retains the existing lighting locks', () {
      final result = compare(11.3, 8.1, bv: 4.1);
      expect(result.trendStatus, isEmpty);
      expect(result.trendDeltas, isEmpty);
      expect(result.trendLockReasons, {
        'pigment_load': 'lighting_mismatch',
        'texture_smoothness': 'lighting_mismatch',
        'localized_redness': 'lighting_mismatch',
      });
    });

    testWidgets('locked pigment card shows Not comparable without a verdict', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LuxeReportLayout(
                requireBackendVerdict: true,
                applyDisplayNoiseFloors: true,
                rawPayload: {
                  'is_follow_up': true,
                  'local_history_count': 2,
                  'metric_matrix': {'pigment_load': 13.5},
                  'baseline_metric_matrix': {'pigment_load': 7.7},
                  'metric_extraction_paths': {'pigment_load': 'primary_roi'},
                  'baseline_metric_extraction_paths': {
                    'pigment_load': 'primary_roi',
                  },
                  'trend_status': <String, String>{},
                  'trend_deltas': <String, double>{},
                  'trend_lock_reasons': {
                    'pigment_load': 'scene_color_mismatch',
                  },
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('result_metric_pigment_load'));
      expect(
        find.descendant(of: card, matching: find.text('Not comparable')),
        findsWidgets,
      );
      expect(
        find.descendant(of: card, matching: find.text('Worsened')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Stable')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    test('scene-color lock is recognized and applied before persistence', () {
      expect(trendLockReasonShortLabel('scene_color_mismatch'), isNotNull);
      expect(trendLockReasonDetail('scene_color_mismatch'), isNotNull);
      final source = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      final run = source.indexOf('Future<void> _runAnalysis() async {');
      final lock = source.indexOf(
        '= lockPigmentTrendForSceneColorMismatch(',
        run,
      );
      final save = source.indexOf("backendResponse['trend_status'] =", run);
      expect(lock, greaterThan(run));
      expect(save, greaterThan(lock));
      expect(
        source.substring(lock, save),
        contains('trendStatus: sceneColorAdjustedTrend.trendStatus'),
      );
    });
  });

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
      for (final pair
          in <({Map<String, dynamic> baseline, Map<String, dynamic> current})>[
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

    for (final lockReason in const [
      'lighting_mismatch',
      'formula_version_mismatch',
      'cast_mismatch',
      'cheek_mismatch',
      'path_mismatch',
      'resolution_mismatch',
      'region_mismatch',
      'future_lock_reason',
    ]) {
      test(
        '$lockReason clears status and delta without changing unlocked metrics',
        () {
          final statuses = {
            'localized_redness': 'stable',
            'texture_smoothness': 'improved',
          };
          final deltas = {'localized_redness': 0.0, 'texture_smoothness': 12.0};
          final locks = {'localized_redness': lockReason};
          final result = clearLockedTrendVerdicts(
            trendStatus: statuses,
            trendDeltas: deltas,
            trendLockReasons: locks,
          );

          expect(result.trendStatus.containsKey('localized_redness'), isFalse);
          expect(result.trendDeltas.containsKey('localized_redness'), isFalse);
          expect(result.trendStatus['texture_smoothness'], 'improved');
          expect(result.trendDeltas['texture_smoothness'], 12.0);
          expect(result.trendLockReasons, locks);
          expect(statuses['localized_redness'], 'stable');
          expect(deltas['localized_redness'], 0.0);
        },
      );
    }

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
