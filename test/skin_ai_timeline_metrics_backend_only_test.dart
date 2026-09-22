import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the persistence-layer fix flagged in 9cd496f: [timelineMetricsFromBackend]
/// used to fall back to AcneRosaceaPhotoAnalyzer's local pixel heuristic
/// (and, separately, the on-device EfficientNet quality scores, and a
/// stale previous scan's cached reading) whenever the backend's
/// metric_matrix didn't have a value for a metric — persisting a
/// fabricated or stale number into the estimated-skin-age calculation
/// (via estimateVisualSkinAgeFromAiMetrics) with no way to tell it apart
/// from a real reading. It now takes ONLY a backend-shaped
/// metric_matrix map and nothing else — that signature is itself the
/// guarantee: there is no PhotoAnalysisResult/local-heuristic parameter
/// through which a substitute could reach it.
void main() {
  group('timelineMetricsFromBackend (persisted timeline / skin-age input)', () {
    test('a completely empty backend map persists nothing, not a heuristic '
        'fallback filled with zeros', () {
      final metrics = timelineMetricsFromBackend(const {});

      expect(metrics, isEmpty);
    });

    test('a null backend map (no response at all) also persists nothing', () {
      final metrics = timelineMetricsFromBackend(null);

      expect(metrics, isEmpty);
    });

    test('only the metrics the backend actually returned are persisted -- '
        'a missing key is absent, never filled with a substitute 0.0', () {
      final metrics = timelineMetricsFromBackend(const {'redness': 0.8});

      expect(metrics['redness'], closeTo(8.0, 0.001));
      expect(metrics.containsKey('pigment'), isFalse);
      expect(metrics.containsKey('texture'), isFalse);
      expect(metrics.containsKey('wrinkle'), isFalse);
      expect(metrics.containsKey('acne_severity'), isFalse);
      expect(metrics.containsKey('rosacea_intensity'), isFalse);
    });

    test('every alias of a present metric is populated, but only that '
        "metric's aliases -- not every alias in the map", () {
      final metrics = timelineMetricsFromBackend(const {'pigment': 0.5});

      expect(metrics['pigment'], closeTo(5.0, 0.001));
      for (final alias in ['pigmentation', 'darkSpots', 'hyperpigmentation']) {
        expect(metrics[alias], closeTo(5.0, 0.001), reason: 'alias "$alias"');
      }
      expect(metrics.containsKey('erythema'), isFalse); // redness alias
      expect(metrics.containsKey('wrinkles'), isFalse); // wrinkle alias
    });

    test('an aggregate metric (swelling) is omitted unless every one of its '
        'inputs (redness, texture, pigment) is itself backend-derived', () {
      final missingPigment = timelineMetricsFromBackend(const {
        'redness': 0.5,
        'texture': 0.5,
      });
      expect(missingPigment.containsKey('swelling'), isFalse);

      final allThree = timelineMetricsFromBackend(const {
        'redness': 0.5,
        'texture': 0.5,
        'pigment': 0.5,
      });
      expect(allThree.containsKey('swelling'), isTrue);
    });

    test('overallHealingScore cascades through the full aggregate chain -- '
        'omitted unless pigment, redness, texture, and wrinkle are ALL '
        'present (swelling/firmness/scarringBruising/fatRetention all '
        'derive from them)', () {
      final allFour = timelineMetricsFromBackend(const {
        'pigment': 0.3,
        'redness': 0.3,
        'texture': 0.3,
        'wrinkle': 0.3,
      });
      expect(allFour.containsKey('overallHealingScore'), isTrue);

      final missingWrinkle = timelineMetricsFromBackend(const {
        'pigment': 0.3,
        'redness': 0.3,
        'texture': 0.3,
      });
      expect(missingWrinkle.containsKey('firmness'), isFalse);
      expect(missingWrinkle.containsKey('overallHealingScore'), isFalse);
    });

    test('sourceSkinAiAnalysis marker is only set when at least one real '
        'metric was persisted', () {
      expect(
        timelineMetricsFromBackend(const {}).containsKey('sourceSkinAiAnalysis'),
        isFalse,
      );
      expect(
        timelineMetricsFromBackend(const {
          'redness': 0.1,
        }).containsKey('sourceSkinAiAnalysis'),
        isTrue,
      );
    });

    test('NaN/infinite backend values are treated as absent, not persisted '
        'as a broken number', () {
      final metrics = timelineMetricsFromBackend(const {
        'redness': double.nan,
        'texture': double.infinity,
        'pigment': 0.4,
      });

      expect(metrics.containsKey('redness'), isFalse);
      expect(metrics.containsKey('texture'), isFalse);
      expect(metrics['pigment'], closeTo(4.0, 0.001));
    });
  });
}
