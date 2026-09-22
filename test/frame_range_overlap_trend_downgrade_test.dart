import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for downgradeTrendForOverlappingFrameRanges: the
/// client-side honesty gate that runs on top of the backend's trend_status
/// to catch exactly the bug reported live -- two scans of the same face
/// minutes apart reported "Texture Smoothness: Improved by 100.0%"
/// (19.4 -> 39.4) even though the within-scan frame spreads (28.7-50.2
/// current, 11.2-30.3 baseline) overlapped from 28.7-30.3, meaning the two
/// scans were not reliably distinguishable from frame-to-frame capture
/// noise. The backend's honesty gate never saw this spread (it only ever
/// compares two point values), so this layer exists purely client-side to
/// catch it after the fact.
void main() {
  group('downgradeTrendForOverlappingFrameRanges', () {
    test(
      'reproduces the reported bug: overlapping texture_smoothness frame '
      'ranges force stable even though the averaged values read "improved"',
      () {
        final result = downgradeTrendForOverlappingFrameRanges(
          trendStatus: {'texture_smoothness': 'improved'},
          trendDeltas: {'texture_smoothness': 100.0},
          trendLockReasons: <String, String>{},
          currentMetricRanges: {
            'texture_smoothness': {'min': 28.7, 'max': 50.2, 'count': 3},
          },
          baselineMetricRanges: {
            'texture_smoothness': {'min': 11.2, 'max': 30.3, 'count': 3},
          },
        );

        expect(result.trendStatus['texture_smoothness'], 'stable');
        expect(result.trendDeltas['texture_smoothness'], 0.0);
        expect(
          result.trendLockReasons['texture_smoothness'],
          'frame_range_overlap',
        );
      },
    );

    test('a worsened verdict is downgraded the same way as improved', () {
      final result = downgradeTrendForOverlappingFrameRanges(
        trendStatus: {'wrinkle_load': 'worsened'},
        trendDeltas: {'wrinkle_load': -26.1},
        trendLockReasons: <String, String>{},
        currentMetricRanges: {
          'wrinkle_load': {'min': 10.0, 'max': 25.0},
        },
        baselineMetricRanges: {
          'wrinkle_load': {'min': 20.0, 'max': 35.0},
        },
      );

      expect(result.trendStatus['wrinkle_load'], 'stable');
      expect(result.trendDeltas['wrinkle_load'], 0.0);
      expect(result.trendLockReasons['wrinkle_load'], 'frame_range_overlap');
    });

    test('cleanly separated ranges are left as improved, untouched', () {
      final result = downgradeTrendForOverlappingFrameRanges(
        trendStatus: {'texture_smoothness': 'improved'},
        trendDeltas: {'texture_smoothness': 60.0},
        trendLockReasons: <String, String>{},
        currentMetricRanges: {
          'texture_smoothness': {'min': 40.0, 'max': 50.0},
        },
        baselineMetricRanges: {
          'texture_smoothness': {'min': 10.0, 'max': 20.0},
        },
      );

      expect(result.trendStatus['texture_smoothness'], 'improved');
      expect(result.trendDeltas['texture_smoothness'], 60.0);
      expect(
        result.trendLockReasons.containsKey('texture_smoothness'),
        isFalse,
      );
    });

    test(
      'ranges that merely touch at a shared boundary do not count as '
      'substantial overlap',
      () {
        final result = downgradeTrendForOverlappingFrameRanges(
          trendStatus: {'pigment_load': 'improved'},
          trendDeltas: {'pigment_load': 50.0},
          trendLockReasons: <String, String>{},
          currentMetricRanges: {
            'pigment_load': {'min': 30.0, 'max': 40.0},
          },
          baselineMetricRanges: {
            'pigment_load': {'min': 20.0, 'max': 30.0},
          },
        );

        expect(result.trendStatus['pigment_load'], 'improved');
        expect(result.trendDeltas['pigment_load'], 50.0);
      },
    );

    test(
      'a "stable" verdict is never touched even when ranges overlap heavily',
      () {
        final result = downgradeTrendForOverlappingFrameRanges(
          trendStatus: {'localized_redness': 'stable'},
          trendDeltas: {'localized_redness': 2.0},
          trendLockReasons: <String, String>{},
          currentMetricRanges: {
            'localized_redness': {'min': 10.0, 'max': 40.0},
          },
          baselineMetricRanges: {
            'localized_redness': {'min': 10.0, 'max': 40.0},
          },
        );

        expect(result.trendStatus['localized_redness'], 'stable');
        expect(result.trendDeltas['localized_redness'], 2.0);
        expect(
          result.trendLockReasons.containsKey('localized_redness'),
          isFalse,
        );
      },
    );

    test(
      'an "insufficient_signal" verdict is never touched',
      () {
        final result = downgradeTrendForOverlappingFrameRanges(
          trendStatus: {'rosacea_severity': 'insufficient_signal'},
          trendDeltas: <String, double>{},
          trendLockReasons: <String, String>{},
          currentMetricRanges: {
            'rosacea_severity': {'min': 10.0, 'max': 40.0},
          },
          baselineMetricRanges: {
            'rosacea_severity': {'min': 10.0, 'max': 40.0},
          },
        );

        expect(
          result.trendStatus['rosacea_severity'],
          'insufficient_signal',
        );
      },
    );

    test(
      'a missing current range falls back to current behavior rather than '
      'forcing stable',
      () {
        final result = downgradeTrendForOverlappingFrameRanges(
          trendStatus: {'texture_smoothness': 'improved'},
          trendDeltas: {'texture_smoothness': 100.0},
          trendLockReasons: <String, String>{},
          currentMetricRanges: const <String, dynamic>{},
          baselineMetricRanges: {
            'texture_smoothness': {'min': 11.2, 'max': 30.3},
          },
        );

        expect(result.trendStatus['texture_smoothness'], 'improved');
        expect(result.trendDeltas['texture_smoothness'], 100.0);
        expect(
          result.trendLockReasons.containsKey('texture_smoothness'),
          isFalse,
        );
      },
    );

    test(
      'a missing baseline range (older scan with no persisted spread) '
      'falls back to current behavior rather than forcing stable',
      () {
        final result = downgradeTrendForOverlappingFrameRanges(
          trendStatus: {'texture_smoothness': 'improved'},
          trendDeltas: {'texture_smoothness': 100.0},
          trendLockReasons: <String, String>{},
          currentMetricRanges: {
            'texture_smoothness': {'min': 28.7, 'max': 50.2},
          },
          baselineMetricRanges: const <String, dynamic>{},
        );

        expect(result.trendStatus['texture_smoothness'], 'improved');
        expect(result.trendDeltas['texture_smoothness'], 100.0);
      },
    );

    test(
      'downgrade never flips or invents a direction: only "improved" or '
      '"worsened" are ever rewritten, and only ever to "stable"',
      () {
        final result = downgradeTrendForOverlappingFrameRanges(
          trendStatus: {
            'localized_redness': 'improved',
            'wrinkle_load': 'worsened',
            'pigment_load': 'stable',
            'breakout_activity': 'insufficient_signal',
          },
          trendDeltas: {
            'localized_redness': 90.0,
            'wrinkle_load': -40.0,
            'pigment_load': 3.0,
          },
          trendLockReasons: <String, String>{},
          // All four metrics have heavily overlapping ranges -- only the
          // improved/worsened ones may end up rewritten.
          currentMetricRanges: {
            for (final key in [
              'localized_redness',
              'wrinkle_load',
              'pigment_load',
              'breakout_activity',
            ])
              key: {'min': 10.0, 'max': 40.0},
          },
          baselineMetricRanges: {
            for (final key in [
              'localized_redness',
              'wrinkle_load',
              'pigment_load',
              'breakout_activity',
            ])
              key: {'min': 10.0, 'max': 40.0},
          },
        );

        expect(result.trendStatus['localized_redness'], 'stable');
        expect(result.trendStatus['wrinkle_load'], 'stable');
        // Untouched: was never improved/worsened to begin with.
        expect(result.trendStatus['pigment_load'], 'stable');
        expect(result.trendStatus['breakout_activity'], 'insufficient_signal');
        expect(
          result.trendLockReasons.containsKey('pigment_load'),
          isFalse,
        );
        expect(
          result.trendLockReasons.containsKey('breakout_activity'),
          isFalse,
        );
        // Every status in the output is one the input already contained or
        // "stable" -- never a value invented from nothing.
        for (final status in result.trendStatus.values) {
          expect(
            ['improved', 'worsened', 'stable', 'insufficient_signal'],
            contains(status),
          );
        }
      },
    );

    test('a metric absent from trendStatus entirely is left absent', () {
      final result = downgradeTrendForOverlappingFrameRanges(
        trendStatus: const <String, String>{},
        trendDeltas: const <String, double>{},
        trendLockReasons: const <String, String>{},
        currentMetricRanges: {
          'texture_smoothness': {'min': 28.7, 'max': 50.2},
        },
        baselineMetricRanges: {
          'texture_smoothness': {'min': 11.2, 'max': 30.3},
        },
      );

      expect(result.trendStatus, isEmpty);
      expect(result.trendLockReasons, isEmpty);
    });
  });
}
