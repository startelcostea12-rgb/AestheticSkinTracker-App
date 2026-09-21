import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('averages each metric over only frames with a finite value', () {
    final aggregate = averageBackendAnalysisFrames(
      [
        {
          'status': 'success',
          'metric_confidence': {
            'localized_redness': 'high',
            'pigment_load': 'medium',
          },
          'metric_matrix': {
            'localized_redness': 10.0,
            'pigment_load': 20.0,
          },
        },
        {
          'status': 'success',
          'metrics': {
            'metric_confidence': {
              'localized_redness': 'medium',
              'texture_smoothness': 'low',
            },
            'metric_matrix': {
              'localized_redness': 20.0,
              'pigment_load': null,
              'texture_smoothness': 60.0,
            },
          },
        },
        {
          'status': 'success',
          'metric_confidence': {'localized_redness': 'high'},
          'metric_matrix': {
            'localized_redness': 30.0,
            'pigment_load': 'invalid',
          },
        },
        {'status': 'error', 'metric_matrix': <String, dynamic>{}},
      ],
      requestedFrames: 4,
    );

    final matrix = aggregate.response['metric_matrix'] as Map<String, double>;
    expect(matrix['localized_redness'], 20.0);
    expect(matrix['pigment_load'], 20.0);
    expect(matrix['texture_smoothness'], 60.0);
    expect(aggregate.metricContributorCounts['localized_redness'], 3);
    expect(aggregate.metricContributorCounts['pigment_load'], 1);
    expect(aggregate.metricContributorCounts['texture_smoothness'], 1);
    expect(aggregate.successfulFrames, 3);
    expect(aggregate.requestedFrames, 4);
    final nestedMetrics = aggregate.response['metrics'] as Map<String, dynamic>;
    expect(nestedMetrics['metric_matrix'], matrix);
    expect(nestedMetrics['localized_redness'], 20.0);
    expect(aggregate.response['multi_frame_analysis'], {
      'requested_frames': 4,
      'successful_frames': 3,
      'metric_contributor_counts': {
        'localized_redness': 3,
        'pigment_load': 1,
        'texture_smoothness': 1,
      },
      'metric_frame_values': {
        'localized_redness': [10.0, 20.0, 30.0],
        'pigment_load': [20.0],
        'texture_smoothness': [60.0],
      },
      'metric_ranges': {
        'localized_redness': {'min': 10.0, 'max': 30.0, 'count': 3},
        'pigment_load': {'min': 20.0, 'max': 20.0, 'count': 1},
        'texture_smoothness': {'min': 60.0, 'max': 60.0, 'count': 1},
      },
    });
    expect(aggregate.response['metric_confidence'], {
      'localized_redness': 'high',
      'pigment_load': 'medium',
      'texture_smoothness': 'low',
    });
    expect(nestedMetrics['metric_confidence'], {
      'localized_redness': 'high',
      'pigment_load': 'medium',
      'texture_smoothness': 'low',
    });
  });

  test('confidence is taken only from a frame that contributed the metric', () {
    final aggregate = averageBackendAnalysisFrames(
      [
        {
          'metric_matrix': {'localized_redness': 10.0},
          'metric_confidence': {
            'localized_redness': 'high',
            'pigment_load': 'low',
          },
        },
        {
          'metric_matrix': {'pigment_load': 24.0},
          'metric_confidence': {'pigment_load': 'high'},
        },
      ],
      requestedFrames: 2,
    );

    expect(aggregate.response['metric_confidence'], {
      'localized_redness': 'high',
      'pigment_load': 'high',
    });
  });

  test('throws when no frame contributes a finite metric', () {
    expect(
      () => averageBackendAnalysisFrames(
        [
          {
            'metric_matrix': {'localized_redness': null},
          },
        ],
        requestedFrames: 1,
      ),
      throwsStateError,
    );
  });

  test('uploads all three frames and excludes a failed frame from averages', () async {
    final requestedFrameNumbers = <int>[];
    final aggregate = await analyzeBackendFrames(
      [
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
        Uint8List.fromList([3]),
      ],
      uploadFrame: (frame, frameNumber) async {
        requestedFrameNumbers.add(frameNumber);
        if (frameNumber == 2) throw Exception('no face detected');
        return {
          'status': 'success',
          'metric_matrix': {
            'localized_redness': frameNumber == 1 ? 20.0 : 40.0,
            if (frameNumber == 1) 'pigment_load': 12.0,
          },
        };
      },
    );

    expect(requestedFrameNumbers, [1, 2, 3]);
    expect(aggregate.requestedFrames, 3);
    expect(aggregate.successfulFrames, 2);
    expect(aggregate.response['metric_matrix'], {
      'localized_redness': 30.0,
      'pigment_load': 12.0,
    });
    expect(aggregate.metricContributorCounts, {
      'localized_redness': 2,
      'pigment_load': 1,
    });
  });

  test('AI multi-frame mode is opt-in and Track Procedure remains single-path', () {
    const trackProcedure = CameraScreen();
    const aiAnalysis = CameraScreen(
      isSkincareScan: true,
      aiMultiFrameCapture: true,
      capturePurpose: CameraCapturePurpose.aiSkinAnalysis,
    );

    expect(trackProcedure.aiMultiFrameCapture, isFalse);
    expect(aiAnalysis.aiMultiFrameCapture, isTrue);

    final source = File(
      'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
    ).readAsStringSync();
    expect(source, contains('Future<XFile?> _captureFromLiveCamera()'));
    expect(source, contains('navigator.pop(imagePathToSave);'));
    expect(source, contains('Future<void> _captureAiSkinAnalysisFrames()'));
    expect(source, contains('for (var index = 0; index < 3; index++)'));
    expect(source, contains('AiSkinAnalysisCaptureResult('));
  });

  test('AI backend fields carry distinct current and previous capture quality tags', () {
    final fields = buildAiSkinAnalysisBackendFields(
      focusArea: 'Full Face',
      currentCaptureQuality: 'normal',
      baselineCaptureQuality: 'normal',
    );

    expect(fields['capture_quality'], 'normal');
    expect(fields['baseline_capture_quality'], 'normal');
    expect(fields['capture_quality'], fields['baseline_capture_quality']);

    final mismatched = buildAiSkinAnalysisBackendFields(
      focusArea: 'Full Face',
      currentCaptureQuality: 'normal',
      baselineCaptureQuality: 'low_light',
    );
    expect(mismatched['capture_quality'], 'normal');
    expect(mismatched['baseline_capture_quality'], 'low_light');
  });
}