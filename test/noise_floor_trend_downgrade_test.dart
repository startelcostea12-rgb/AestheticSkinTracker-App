import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for downgradeTrendBelowMeasuredNoiseFloor: the
/// client-side honesty gate that re-applies the backend's measured
/// noise-floor policy against the AVERAGED metric_matrix value actually
/// shown on screen.
///
/// Root cause this exists for: _trend_delta_and_status (main.py) runs once
/// per backend call, and the app calls the backend once PER CAPTURED FRAME,
/// then averages the frames client-side into the number that's displayed.
/// The backend's own noise-floor check (and every other gate in
/// _trend_delta_and_status) therefore only ever sees a single frame's raw
/// value, never the average -- so a frame that happens to be nearest to the
/// average (see averageBackendAnalysisFrames's nearest-frame trend
/// selection) can still independently clear the floor on its own value even
/// though the average does not. texture_smoothness frames [20.0, 33.0,
/// 37.6] average to 30.2 -- a 3.2 delta against a 27.0 baseline, below the
/// 5.4 floor -- but the nearest-to-average frame (33.0) has its own delta
/// of 6.0, which clears both the floor and the relative honesty band on its
/// own and reports "Improved" for a number that isn't the one displayed.
void main() {
  group('downgradeTrendBelowMeasuredNoiseFloor', () {
    test(
      'reproduces the reported bug: the averaged value is below the floor '
      'even though the selected per-frame verdict cleared it',
      () {
        // The frame nearest to the 30.2 average was 33.0, whose own delta
        // (6.0 against baseline 27.0) cleared texture_smoothness's 5.4
        // floor, so averageBackendAnalysisFrames's nearest-frame selection
        // surfaced that frame's "improved" verdict.
        final result = downgradeTrendBelowMeasuredNoiseFloor(
          trendStatus: {'texture_smoothness': 'improved'},
          trendDeltas: {'texture_smoothness': 11.8},
          trendLockReasons: <String, String>{},
          averagedMetricMatrix: {'texture_smoothness': 30.2},
          baselineMetricMatrix: {'texture_smoothness': 27.0},
          metricNoiseFloor2sd: {'texture_smoothness': 5.4},
          trendNoiseFloorExceedsUsefulRange: const <String>{},
          trendNoiseFloorExcludedMultiplier: 3.0,
        );

        expect(result.trendStatus['texture_smoothness'], 'stable');
        expect(result.trendDeltas['texture_smoothness'], 0.0);
        expect(
          result.trendLockReasons['texture_smoothness'],
          'below_noise_floor',
        );
      },
    );

    test(
      'the exact [20.0, 33.0, 37.6] frame set: nearest-to-average frame '
      'clears the floor on its own value, but the true average does not',
      () {
        final frames = [20.0, 33.0, 37.6];
        final average = frames.reduce((a, b) => a + b) / frames.length;
        const baseline = 27.0;
        const floor = 5.4;

        // Confirms the scenario is real: the nearest-to-average frame's own
        // delta clears the floor even though the average's does not.
        final nearest = frames.reduce(
          (a, b) => (a - average).abs() < (b - average).abs() ? a : b,
        );
        expect(nearest, 33.0);
        expect((nearest - baseline).abs(), greaterThanOrEqualTo(floor));
        expect((average - baseline).abs(), lessThan(floor));

        final result = downgradeTrendBelowMeasuredNoiseFloor(
          trendStatus: {'texture_smoothness': 'improved'},
          trendDeltas: {'texture_smoothness': 22.2},
          trendLockReasons: <String, String>{},
          averagedMetricMatrix: {'texture_smoothness': average},
          baselineMetricMatrix: {'texture_smoothness': baseline},
          metricNoiseFloor2sd: {'texture_smoothness': floor},
          trendNoiseFloorExceedsUsefulRange: const <String>{},
          trendNoiseFloorExcludedMultiplier: 3.0,
        );

        expect(result.trendStatus['texture_smoothness'], 'stable');
        expect(result.trendDeltas['texture_smoothness'], 0.0);
        expect(
          result.trendLockReasons['texture_smoothness'],
          'below_noise_floor',
        );
      },
    );

    test(
      'an averaged value that clears the floor is left as the reported '
      'direction, untouched',
      () {
        final result = downgradeTrendBelowMeasuredNoiseFloor(
          trendStatus: {'wrinkle_load': 'improved'},
          trendDeltas: {'wrinkle_load': 40.0},
          trendLockReasons: <String, String>{},
          averagedMetricMatrix: {'wrinkle_load': 10.0},
          baselineMetricMatrix: {'wrinkle_load': 20.0},
          metricNoiseFloor2sd: {'wrinkle_load': 3.7},
          trendNoiseFloorExceedsUsefulRange: const <String>{},
          trendNoiseFloorExcludedMultiplier: 3.0,
        );

        expect(result.trendStatus['wrinkle_load'], 'improved');
        expect(result.trendDeltas['wrinkle_load'], 40.0);
        expect(result.trendLockReasons.containsKey('wrinkle_load'), isFalse);
      },
    );

    test(
      'an excluded metric below 3x its floor is corrected to '
      'insufficient_signal, not stable',
      () {
        final result = downgradeTrendBelowMeasuredNoiseFloor(
          trendStatus: {'localized_redness': 'improved'},
          trendDeltas: {'localized_redness': -50.0},
          trendLockReasons: <String, String>{},
          averagedMetricMatrix: {'localized_redness': 15.0},
          baselineMetricMatrix: {'localized_redness': 10.0},
          metricNoiseFloor2sd: {'localized_redness': 6.4},
          trendNoiseFloorExceedsUsefulRange: {'localized_redness'},
          trendNoiseFloorExcludedMultiplier: 3.0,
        );

        expect(result.trendStatus['localized_redness'], 'insufficient_signal');
        expect(result.trendDeltas['localized_redness'], 0.0);
        expect(
          result.trendLockReasons.containsKey('localized_redness'),
          isFalse,
        );
      },
    );

    test(
      'an excluded metric currently "stable" below 3x its floor is also '
      'corrected to insufficient_signal',
      () {
        // Mirrors main.py's own unconditional behavior for excluded
        // metrics: below-3x-floor is never "stable", regardless of which
        // gate originally produced that label.
        final result = downgradeTrendBelowMeasuredNoiseFloor(
          trendStatus: {'rosacea_severity': 'stable'},
          trendDeltas: {'rosacea_severity': 0.0},
          trendLockReasons: <String, String>{},
          averagedMetricMatrix: {'rosacea_severity': 12.0},
          baselineMetricMatrix: {'rosacea_severity': 10.0},
          metricNoiseFloor2sd: {'rosacea_severity': 3.5},
          trendNoiseFloorExceedsUsefulRange: {'rosacea_severity'},
          trendNoiseFloorExcludedMultiplier: 3.0,
        );

        expect(result.trendStatus['rosacea_severity'], 'insufficient_signal');
      },
    );

    test(
      'an excluded metric at or above 3x its floor still reports its '
      'direction, untouched',
      () {
        final result = downgradeTrendBelowMeasuredNoiseFloor(
          trendStatus: {'rosacea_severity': 'worsened'},
          trendDeltas: {'rosacea_severity': -250.0},
          trendLockReasons: <String, String>{},
          averagedMetricMatrix: {'rosacea_severity': 35.0},
          baselineMetricMatrix: {'rosacea_severity': 10.0},
          metricNoiseFloor2sd: {'rosacea_severity': 3.5},
          trendNoiseFloorExceedsUsefulRange: {'rosacea_severity'},
          trendNoiseFloorExcludedMultiplier: 3.0,
        );

        expect(result.trendStatus['rosacea_severity'], 'worsened');
        expect(result.trendDeltas['rosacea_severity'], -250.0);
      },
    );

    test('an "insufficient_signal" verdict is never touched', () {
      final result = downgradeTrendBelowMeasuredNoiseFloor(
        trendStatus: {'pigment_load': 'insufficient_signal'},
        trendDeltas: <String, double>{},
        trendLockReasons: <String, String>{},
        averagedMetricMatrix: {'pigment_load': 10.0},
        baselineMetricMatrix: {'pigment_load': 5.0},
        metricNoiseFloor2sd: {'pigment_load': 2.0},
        trendNoiseFloorExceedsUsefulRange: const <String>{},
        trendNoiseFloorExcludedMultiplier: 3.0,
      );

      expect(result.trendStatus['pigment_load'], 'insufficient_signal');
    });

    group('missing thresholds fall back to existing behavior', () {
      test('a metric missing from metricNoiseFloor2sd is left untouched', () {
        final result = downgradeTrendBelowMeasuredNoiseFloor(
          trendStatus: {'pore_visibility': 'improved'},
          trendDeltas: {'pore_visibility': 17.0},
          trendLockReasons: <String, String>{},
          averagedMetricMatrix: {'pore_visibility': 10.0},
          baselineMetricMatrix: {'pore_visibility': 8.5},
          metricNoiseFloor2sd: const <String, dynamic>{},
          trendNoiseFloorExceedsUsefulRange: const <String>{},
          trendNoiseFloorExcludedMultiplier: 3.0,
        );

        expect(result.trendStatus['pore_visibility'], 'improved');
        expect(result.trendDeltas['pore_visibility'], 17.0);
      });

      test(
        'an excluded metric missing the multiplier is left untouched, not '
        'forced to insufficient_signal or stable',
        () {
          final result = downgradeTrendBelowMeasuredNoiseFloor(
            trendStatus: {'localized_redness': 'improved'},
            trendDeltas: {'localized_redness': -50.0},
            trendLockReasons: <String, String>{},
            averagedMetricMatrix: {'localized_redness': 15.0},
            baselineMetricMatrix: {'localized_redness': 10.0},
            metricNoiseFloor2sd: {'localized_redness': 6.4},
            trendNoiseFloorExceedsUsefulRange: {'localized_redness'},
            trendNoiseFloorExcludedMultiplier: null,
          );

          expect(result.trendStatus['localized_redness'], 'improved');
          expect(result.trendDeltas['localized_redness'], -50.0);
        },
      );

      test(
        'entirely empty threshold payload (older backend build) leaves '
        'every metric exactly as reported upstream',
        () {
          final result = downgradeTrendBelowMeasuredNoiseFloor(
            trendStatus: {
              'texture_smoothness': 'improved',
              'localized_redness': 'improved',
            },
            trendDeltas: {
              'texture_smoothness': 11.8,
              'localized_redness': -50.0,
            },
            trendLockReasons: <String, String>{},
            averagedMetricMatrix: {
              'texture_smoothness': 30.2,
              'localized_redness': 15.0,
            },
            baselineMetricMatrix: {
              'texture_smoothness': 27.0,
              'localized_redness': 10.0,
            },
            metricNoiseFloor2sd: const <String, dynamic>{},
            trendNoiseFloorExceedsUsefulRange: const <String>{},
            trendNoiseFloorExcludedMultiplier: null,
          );

          expect(result.trendStatus['texture_smoothness'], 'improved');
          expect(result.trendStatus['localized_redness'], 'improved');
        },
      );

      test('a metric missing from the averaged matrix is left untouched', () {
        final result = downgradeTrendBelowMeasuredNoiseFloor(
          trendStatus: {'texture_smoothness': 'improved'},
          trendDeltas: {'texture_smoothness': 11.8},
          trendLockReasons: <String, String>{},
          averagedMetricMatrix: const <String, dynamic>{},
          baselineMetricMatrix: {'texture_smoothness': 27.0},
          metricNoiseFloor2sd: {'texture_smoothness': 5.4},
          trendNoiseFloorExceedsUsefulRange: const <String>{},
          trendNoiseFloorExcludedMultiplier: 3.0,
        );

        expect(result.trendStatus['texture_smoothness'], 'improved');
      });

      test('a metric missing from the baseline matrix is left untouched', () {
        final result = downgradeTrendBelowMeasuredNoiseFloor(
          trendStatus: {'texture_smoothness': 'improved'},
          trendDeltas: {'texture_smoothness': 11.8},
          trendLockReasons: <String, String>{},
          averagedMetricMatrix: {'texture_smoothness': 30.2},
          baselineMetricMatrix: const <String, dynamic>{},
          metricNoiseFloor2sd: {'texture_smoothness': 5.4},
          trendNoiseFloorExceedsUsefulRange: const <String>{},
          trendNoiseFloorExcludedMultiplier: 3.0,
        );

        expect(result.trendStatus['texture_smoothness'], 'improved');
      });
    });
  });
}
