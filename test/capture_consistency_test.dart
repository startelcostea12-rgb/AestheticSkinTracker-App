import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:aesthetic_skin_tracker/utils/capture_consistency.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';

void main() {
  test('face score equal-weights matching quality, path, resolution, and pose', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_capture_quality': 'normal',
        'capture_quality': 'normal',
        'baseline_source_image_width': 1000,
        'baseline_source_image_height': 1000,
        'source_image_width': 1080,
        'source_image_height': 1000,
        'baseline_metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'capture_reference_alignment_score': 92,
      },
      isBodyProcedure: false,
    );

    expect(result.checkCount, 4);
    expect(result.score, 88.0);
    expect(
      result.displayText,
      'Capture consistency: 88% · 4 checks — mainly due to photo resolution differing from your baseline',
    );
  });

  test('quality match is 100 and known quality mismatch is zero', () {
    final matching = captureConsistencyForPayload(
      {'baseline_capture_quality': 'normal', 'capture_quality': 'normal'},
      isBodyProcedure: false,
    );
    final mismatch = captureConsistencyForPayload(
      {'baseline_capture_quality': 'normal', 'capture_quality': 'low_light'},
      isBodyProcedure: false,
    );

    expect(matching.score, 100);
    expect(mismatch.score, 0);
  });

  test('capture quality is identified as the lowest face consistency factor', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_capture_quality': 'normal',
        'capture_quality': 'low_light',
        'baseline_metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'capture_reference_alignment_score': 90,
      },
      isBodyProcedure: false,
    );

    expect(result.lowestCheck?.factor, CaptureConsistencyFactor.captureQuality);
    expect(result.displayText, contains('capture conditions differing from your baseline'));
  });

  test('unavailable quality is omitted rather than zeroed or perfected', () {
    final result = captureConsistencyForPayload(
      {'capture_quality': 'normal'},
      isBodyProcedure: false,
    );

    expect(result.score, isNull);
    expect(result.checkCount, 0);
    expect(result.displayText, 'Capture consistency unavailable');
  });

  test('path match is 100, path mismatch is zero, and missing paths are omitted', () {
    final matching = captureConsistencyForPayload(
      {
        'baseline_metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'metric_extraction_paths': {'pigment_load': 'cheek_primary'},
      },
      isBodyProcedure: false,
    );
    final mismatch = captureConsistencyForPayload(
      {
        'baseline_metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'metric_extraction_paths': {'pigment_load': 'full_face_fallback'},
      },
      isBodyProcedure: false,
    );
    final missing = captureConsistencyForPayload(
      {'metric_extraction_paths': {'pigment_load': 'cheek_primary'}},
      isBodyProcedure: false,
    );

    expect(matching.score, 100);
    expect(mismatch.score, 0);
    expect(missing.score, isNull);
  });

  test('resolution uses the existing 20 percent threshold continuously', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_source_image_width': 1000,
        'baseline_source_image_height': 1000,
        'source_image_width': 1080,
        'source_image_height': 1000,
      },
      isBodyProcedure: false,
    );

    expect(result.checkCount, 1);
    expect(result.score, closeTo(60.0, 0.0001));
  });

  test('body scores mode and scale as separate checks', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_capture_quality': 'normal',
        'capture_quality': 'normal',
        'baseline_capture_mode': 'mirror',
        'capture_mode': 'mirror',
        'baseline_result': {'scale_reference_pixels': 100.0},
        'result': {'scale_reference_pixels': 110.0},
        'capture_reference_alignment_score': 80,
      },
      isBodyProcedure: true,
    );

    expect(result.checkCount, 4);
  expect(result.score, 82.5);
  });

  test('body mode mismatch contributes zero without changing comparison gates', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_capture_mode': 'mirror',
        'capture_mode': 'timer',
      },
      isBodyProcedure: true,
    );

    expect(result.score, 0);
    expect(result.checkCount, 1);
  });

  test('body scale at the existing mismatch threshold contributes zero', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_result': {'scale_reference_pixels': 100.0},
        'result': {'scale_reference_pixels': 120.0},
      },
      isBodyProcedure: true,
    );

    expect(result.score, 0);
    expect(result.checkCount, 1);
  });

  test('missing pose is omitted while an available pose score is preserved', () {
    final omitted = captureConsistencyForPayload(
      {'baseline_capture_quality': 'normal', 'capture_quality': 'normal'},
      isBodyProcedure: false,
    );
    final available = captureConsistencyForPayload(
      {
        'baseline_capture_quality': 'normal',
        'capture_quality': 'normal',
        'capture_reference_alignment_score': 70,
      },
      isBodyProcedure: false,
    );

    expect(omitted.checkCount, 1);
    expect(omitted.score, 100);
    expect(available.checkCount, 2);
    expect(available.score, 85);
  });

  test('resolution is identified as the lowest face consistency factor', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_capture_quality': 'normal',
        'capture_quality': 'normal',
        'baseline_source_image_width': 1000,
        'baseline_source_image_height': 1000,
        'source_image_width': 1080,
        'source_image_height': 1000,
        'baseline_metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'capture_reference_alignment_score': 90,
      },
      isBodyProcedure: false,
    );

    expect(result.lowestCheck?.factor, CaptureConsistencyFactor.sourceResolution);
    expect(result.displayText, contains('photo resolution differing from your baseline'));
  });

  test('reference pose is identified as the lowest face consistency factor', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_capture_quality': 'normal',
        'capture_quality': 'normal',
        'baseline_metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'capture_reference_alignment_score': 55,
      },
      isBodyProcedure: false,
    );

    expect(result.lowestCheck?.factor, CaptureConsistencyFactor.referencePose);
    expect(result.displayText, contains('your positioning differing from your reference pose'));
  });

  test('extraction path is identified as the lowest face consistency factor', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_capture_quality': 'normal',
        'capture_quality': 'normal',
        'baseline_metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'metric_extraction_paths': {'pigment_load': 'full_face_fallback'},
        'capture_reference_alignment_score': 90,
      },
      isBodyProcedure: false,
    );

    expect(result.lowestCheck?.factor, CaptureConsistencyFactor.extractionPath);
    expect(result.displayText, contains('a different analysis method being used for this comparison'));
  });

  test('body capture mode is identified as the lowest factor', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_capture_quality': 'normal',
        'capture_quality': 'normal',
        'baseline_capture_mode': 'mirror',
        'capture_mode': 'timer',
        'baseline_result': {'scale_reference_pixels': 100.0},
        'result': {'scale_reference_pixels': 100.0},
        'capture_reference_alignment_score': 90,
      },
      isBodyProcedure: true,
    );

    expect(result.lowestCheck?.factor, CaptureConsistencyFactor.captureMode);
    expect(result.displayText, contains('capture method or framing differing from your baseline'));
  });

  test('body scale reference is identified as the lowest factor', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_capture_quality': 'normal',
        'capture_quality': 'normal',
        'baseline_capture_mode': 'mirror',
        'capture_mode': 'mirror',
        'baseline_result': {'scale_reference_pixels': 100.0},
        'result': {'scale_reference_pixels': 120.0},
        'capture_reference_alignment_score': 90,
      },
      isBodyProcedure: true,
    );

    expect(result.lowestCheck?.factor, CaptureConsistencyFactor.scaleReference);
    expect(result.displayText, contains('capture method or framing differing from your baseline'));
  });

  test('high consistency does not add a mainly-due explanation', () {
    final result = captureConsistencyForPayload(
      {
        'baseline_capture_quality': 'normal',
        'capture_quality': 'normal',
        'baseline_source_image_width': 1000,
        'baseline_source_image_height': 1000,
        'source_image_width': 1000,
        'source_image_height': 1000,
        'baseline_metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        'capture_reference_alignment_score': 92,
      },
      isBodyProcedure: false,
    );

    expect(result.score, 98.0);
    expect(result.displayText, 'Capture consistency: 98% · 4 checks');
    expect(result.displayText, isNot(contains('mainly due to')));
  });

  testWidgets('Luxe comparison visibly renders capture consistency and check count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LuxeReportLayout(
            rawPayload: const {
              'local_history_count': 2,
              'metric_matrix': {'localized_redness': 44.0},
              'baseline_metric_matrix': {'localized_redness': 40.0},
              'trend_deltas': {'localized_redness': -10.0},
              'trend_status': {'localized_redness': 'improved'},
              'capture_quality': 'normal',
              'baseline_capture_quality': 'normal',
              'baseline_source_image_width': 1000,
              'baseline_source_image_height': 1000,
              'source_image_width': 1080,
              'source_image_height': 1000,
              'baseline_metric_extraction_paths': {
                'localized_redness': 'cheek_primary',
              },
              'metric_extraction_paths': {
                'localized_redness': 'cheek_primary',
              },
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Capture consistency: 87% · 3 checks — mainly due to photo resolution differing from your baseline',
      ),
      findsOneWidget,
    );
  });
}