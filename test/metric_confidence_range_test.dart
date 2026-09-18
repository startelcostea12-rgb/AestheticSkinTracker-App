import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LuxeMetric _metric({
  Object? confidence,
  double? min,
  double? max,
  int? contributors,
  int? requested,
}) => LuxeMetric(
  key: 'localized_redness',
  name: 'Localized Redness',
  baselineScore: 40,
  currentScore: 44,
  improvementPercent: 10,
  lowerIsBetter: true,
  currentConfidence: confidence,
  hasDetectedCurrentValue: true,
  currentRangeMin: min,
  currentRangeMax: max,
  contributorCount: contributors,
  requestedFrameCount: requested,
);

void main() {
  group('metric precision display', () {
    test('1 preserves real samples and derives mean min max and count', () {
      final aggregate = averageBackendAnalysisFrames(
        [
          {'metric_matrix': {'localized_redness': 42.0}},
          {'metric_matrix': {'localized_redness': 45.0}},
          {'metric_matrix': {'localized_redness': 44.0}},
        ],
        requestedFrames: 3,
      );

      expect(aggregate.response['metric_matrix'], {'localized_redness': 131 / 3});
      final multi = aggregate.response['multi_frame_analysis'] as Map;
      expect(multi['metric_frame_values'], {
        'localized_redness': [42.0, 45.0, 44.0],
      });
      expect(multi['metric_ranges'], {
        'localized_redness': {'min': 42.0, 'max': 45.0, 'count': 3},
      });
    });

    test('2 excludes missing values independently for each metric', () {
      final aggregate = averageBackendAnalysisFrames(
        [
          {
            'metric_matrix': {
              'localized_redness': 40.0,
              'pigment_load': 10.0,
            },
          },
          {
            'metric_matrix': {
              'localized_redness': null,
              'pigment_load': 20.0,
            },
          },
          {
            'metric_matrix': {
              'localized_redness': 50.0,
              'pigment_load': 'invalid',
            },
          },
        ],
        requestedFrames: 3,
      );

      expect(aggregate.response['metric_matrix'], {
        'localized_redness': 45.0,
        'pigment_load': 15.0,
      });
      expect(aggregate.metricContributorCounts, {
        'localized_redness': 2,
        'pigment_load': 2,
      });
    });

    test('3 attributes confidence only from a contributing frame', () {
      final aggregate = averageBackendAnalysisFrames(
        [
          {
            'metric_matrix': {'localized_redness': 20.0},
            'metric_confidence': {'pigment_load': 'low'},
          },
          {
            'metric_matrix': {'pigment_load': 30.0},
            'metric_confidence': {'pigment_load': 'high'},
          },
        ],
        requestedFrames: 2,
      );

      expect(aggregate.response['metric_confidence'], {'pigment_load': 'high'});
    });

    test('4 two or more contributors display the real range', () {
      final presentation = metricPrecisionPresentation(
        _metric(confidence: 'high', min: 42, max: 45, contributors: 3, requested: 3),
      );

      expect(presentation.hasRealRange, isTrue);
      expect(presentation.rangeSuffix, ' (42.0–45.0)');
      expect(presentation.detailText, '3/3 frames');
    });

    test('5 one contributor displays confidence and no numeric range', () {
      final presentation = metricPrecisionPresentation(
        _metric(confidence: 'medium', min: 44, max: 44, contributors: 1, requested: 3),
      );

      expect(presentation.hasRealRange, isFalse);
      expect(presentation.rangeSuffix, isEmpty);
      expect(presentation.detailText, 'Confidence: Medium · 1/3 frames');
    });

    test('6 normal single-frame payload displays existing confidence only', () {
      final presentation = metricPrecisionPresentation(
        _metric(confidence: 'high'),
      );

      expect(presentation.rangeSuffix, isEmpty);
      expect(presentation.detailText, 'Confidence: High');
    });

    test('7 absent confidence displays unavailable without a fabricated range', () {
      final presentation = metricPrecisionPresentation(_metric());

      expect(presentation.hasRealRange, isFalse);
      expect(presentation.rangeSuffix, isEmpty);
      expect(presentation.detailText, 'Confidence unavailable');
    });

    test('8 precision metadata leaves scores trends and honesty inputs unchanged', () {
      final basePayload = <String, dynamic>{
        'metric_matrix': {'localized_redness': 44.0},
        'baseline_metric_matrix': {'localized_redness': 40.0},
        'metric_confidence': {'localized_redness': 'medium'},
        'metric_extraction_paths': {'localized_redness': 'primary_roi'},
        'baseline_metric_extraction_paths': {'localized_redness': 'primary_roi'},
        'trend_deltas': {'localized_redness': 10.0},
        'trend_status': {'localized_redness': 'worsened'},
      };
      final enriched = <String, dynamic>{
        ...basePayload,
        ...luxePrecisionMetadataFromBackend({
          'metric_confidence': {'localized_redness': 'medium'},
          'multi_frame_analysis': {
            'requested_frames': 3,
            'metric_contributor_counts': {'localized_redness': 3},
            'metric_ranges': {
              'localized_redness': {'min': 42.0, 'max': 45.0, 'count': 3},
            },
          },
        }),
      };

      final before = LuxeMetricParser.parseTimelinePayload(basePayload).single;
      final after = LuxeMetricParser.parseTimelinePayload(enriched).single;
      expect(after.currentScore, before.currentScore);
      expect(after.baselineScore, before.baselineScore);
      expect(after.improvementPercent, before.improvementPercent);
      expect(after.currentConfidence, before.currentConfidence);
      expect(after.currentExtractionPath, before.currentExtractionPath);
      expect(after.baselineExtractionPath, before.baselineExtractionPath);
      expect(after.backendTrendDeltaPct, before.backendTrendDeltaPct);
      expect(after.backendTrendStatus, before.backendTrendStatus);
      expect(after.currentRangeMin, 42.0);
      expect(after.currentRangeMax, 45.0);
      expect(after.contributorCount, 3);
      expect(after.requestedFrameCount, 3);
    });

    test('precision parser ignores wrong-level range and count decoys', () {
      final metric = LuxeMetricParser.parseTimelinePayload({
        'metric_matrix': {'localized_redness': 44.0},
        'baseline_metric_matrix': {'localized_redness': 40.0},
        'metric_confidence': {'localized_redness': 'medium'},
        'metric_ranges': {
          'localized_redness': {'min': 1.0, 'max': 99.0, 'count': 99},
        },
        'metric_contributor_counts': {'localized_redness': 99},
        'multi_frame_analysis': {
          'requested_frames': 3,
          'metric_contributor_counts': {'localized_redness': 2},
          'metric_ranges': {
            'localized_redness': {'min': 42.0, 'max': 45.0, 'count': 2},
          },
        },
      }).single;

      expect(metric.currentRangeMin, 42.0);
      expect(metric.currentRangeMax, 45.0);
      expect(metric.contributorCount, 2);
      expect(metric.requestedFrameCount, 3);
    });

    testWidgets('shared metric card visibly renders a real multi-frame range', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LuxeReportLayout(
              rawPayload: {
                'metric_matrix': {'localized_redness': 44.0},
                'metric_confidence': {'localized_redness': 'high'},
                'multi_frame_analysis': {
                  'requested_frames': 3,
                  'metric_contributor_counts': {'localized_redness': 3},
                  'metric_ranges': {
                    'localized_redness': {
                      'min': 42.0,
                      'max': 45.0,
                      'count': 3,
                    },
                  },
                },
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('(42.0–45.0)'), findsOneWidget);
      expect(find.text('3/3 frames'), findsOneWidget);
    });

    testWidgets(
      'shared metric card shows confidence only for a normal single frame',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LuxeReportLayout(
                rawPayload: {
                  'metric_matrix': {'localized_redness': 44.0},
                  'metric_confidence': {'localized_redness': 'medium'},
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Confidence: Medium'), findsOneWidget);
        expect(find.textContaining('–'), findsNothing);
      },
    );
  });
}