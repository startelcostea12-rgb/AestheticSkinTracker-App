import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildBaselineMetricMatrix', () {
    test('keeps canonical reference metrics unchanged over legacy aliases', () {
      final matrix = buildBaselineMetricMatrix(const {
        'localized_redness': 0.4,
        'redness': 8.0,
        'texture_smoothness': 63.2,
        'texture': 2.0,
        'pore_visibility': 7.3,
        'pores': 0.8,
        'breakout_activity': 12.4,
        'acne_severity': 9.0,
      });

      expect(matrix, {
        'localized_redness': 0.4,
        'texture_smoothness': 63.2,
        'pore_visibility': 7.3,
        'breakout_activity': 12.4,
      });
    });

    test('converts only present legacy values', () {
      expect(buildBaselineMetricMatrix(const {'pores': 0.8}), {
        'pore_visibility': 8.0,
      });
      expect(buildBaselineMetricMatrix(const {'redness': 3.0}), {
        'localized_redness': 30.0,
      });
      expect(buildBaselineMetricMatrix(const {'texture': 2.0}), {
        'texture_smoothness': 80.0,
      });
      expect(buildBaselineMetricMatrix(const {'unrelated': 4.0}), isNull);
    });
  });

  test('Track Procedure camera flow contains no backend body upload call', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('SkinAnalysisService.analyzeBodySilhouette')));
    expect(source, isNot(contains("as remote_skin_analysis")));
  });

  group('buildBodySilhouetteRequestParams', () {
    test(
      'pulls captureMode from the selected mode and captureQuality from the last tag',
      () {
        final params = buildBodySilhouetteRequestParams(
          selectedCaptureMode: BodyCaptureMode.mirror,
          lastCaptureQualityTag: 'normal',
          baselineRawPayload: null,
          baselineCaptureMode: null,
          priorConsistentScanCount: 1,
        );

        expect(params.captureMode, 'mirror');
        expect(params.captureQuality, 'normal');
        expect(params.baselineResult, isNull);
        expect(params.baselineCaptureMode, isNull);
        expect(params.currentConsistentScanCount, 2);
        expect(params.baselineConsistentScanCount, 1);
      },
    );

    test('assisted and timer modes map to their storageValue too', () {
      expect(
        buildBodySilhouetteRequestParams(
          selectedCaptureMode: BodyCaptureMode.assisted,
          lastCaptureQualityTag: null,
          baselineRawPayload: null,
          baselineCaptureMode: null,
        ).captureMode,
        'assisted',
      );
      expect(
        buildBodySilhouetteRequestParams(
          selectedCaptureMode: BodyCaptureMode.timer,
          lastCaptureQualityTag: null,
          baselineRawPayload: null,
          baselineCaptureMode: null,
        ).captureMode,
        'timer',
      );
    });

    test('a null selected mode produces a null captureMode', () {
      final params = buildBodySilhouetteRequestParams(
        selectedCaptureMode: null,
        lastCaptureQualityTag: null,
        baselineRawPayload: null,
        baselineCaptureMode: null,
      );
      expect(params.captureMode, isNull);
    });

    test(
      "extracts baselineResult from the reference scan's rawPayload['result'], "
      'not the payload verbatim',
      () {
        final baselineRawPayload = <String, dynamic>{
          'status': 'success',
          'text': 'Body silhouette analysis complete.',
          'result': <String, dynamic>{
            'normalized_area_index': 12.34,
            'scale_reference_pixels': 210.5,
            'roi_pixel_count': 4200,
            'confidence': 0.81,
          },
          'trend_deltas': <String, dynamic>{},
          'trend_status': <String, dynamic>{},
        };

        final params = buildBodySilhouetteRequestParams(
          selectedCaptureMode: BodyCaptureMode.mirror,
          lastCaptureQualityTag: 'normal',
          baselineRawPayload: baselineRawPayload,
          baselineCaptureMode: 'mirror',
        );

        expect(params.baselineResult, isNotNull);
        expect(params.baselineResult!['normalized_area_index'], 12.34);
        expect(params.baselineResult!['scale_reference_pixels'], 210.5);
        expect(params.baselineResult!['roi_pixel_count'], 4200);
        expect(params.baselineResult!['confidence'], 0.81);
        // Only the `result` sub-map travels, not sibling keys like
        // trend_deltas/trend_status/status/text from the prior response.
        expect(params.baselineResult!.containsKey('status'), isFalse);
        expect(params.baselineResult!.containsKey('trend_deltas'), isFalse);
        expect(params.baselineCaptureMode, 'mirror');
      },
    );

    test(
      'a reference scan with no rawPayload yet (legacy scan, or backend call '
      'failed at capture time) yields a null baselineResult, not a crash',
      () {
        final params = buildBodySilhouetteRequestParams(
          selectedCaptureMode: BodyCaptureMode.mirror,
          lastCaptureQualityTag: null,
          baselineRawPayload: null,
          baselineCaptureMode: null,
        );
        expect(params.baselineResult, isNull);
      },
    );

    test(
      "a rawPayload whose 'result' key is missing or not a map yields a null "
      'baselineResult rather than throwing',
      () {
        final missingResult = buildBodySilhouetteRequestParams(
          selectedCaptureMode: BodyCaptureMode.mirror,
          lastCaptureQualityTag: null,
          baselineRawPayload: <String, dynamic>{'status': 'success'},
          baselineCaptureMode: null,
        );
        expect(missingResult.baselineResult, isNull);

        final wrongType = buildBodySilhouetteRequestParams(
          selectedCaptureMode: BodyCaptureMode.mirror,
          lastCaptureQualityTag: null,
          baselineRawPayload: <String, dynamic>{'result': 'not-a-map'},
          baselineCaptureMode: null,
        );
        expect(wrongType.baselineResult, isNull);
      },
    );
  });
}
