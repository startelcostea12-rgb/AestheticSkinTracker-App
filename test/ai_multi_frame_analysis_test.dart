import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/ai_scan_frame_exposure.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI baseline metric matrix source', () {
    test('matrix value wins over a conflicting metrics value', () {
      final baseline = aiBaselineMetricMatrixFromPayload({
        'metric_matrix': {'texture_smoothness': 57.3},
        'metrics': {'texture_smoothness': 25.23},
      });

      expect(baseline['texture_smoothness'], 57.3);
    });

    test('metrics-only value is not used as a baseline', () {
      final baseline = aiBaselineMetricMatrixFromPayload({
        'metrics': {'texture_smoothness': 25.23},
      });

      expect(baseline.containsKey('texture_smoothness'), isFalse);
    });
  });

  Map<String, dynamic> rednessPayload({
    required String cheekSide,
    required double p10,
    required double p95,
    required List<double> frameP95,
    String? cheekSideConvention = cheekSideConventionSubjectAnatomical,
    bool? bothCheeksInDeadZone,
  }) => <String, dynamic>{
    'image_quality': <String, dynamic>{
      'redness_cheek_side': cheekSide,
      if (cheekSideConvention != null)
        'cheek_side_convention': cheekSideConvention,
      if (bothCheeksInDeadZone != null)
        'redness_both_cheeks_in_dead_zone': bothCheeksInDeadZone,
      'redness_cheek_p10_a_after_wb': p10,
      'redness_cheek_p95_a_after_wb': p95,
    },
    aiScanPerFrameDiagnosticsKey: <Map<String, dynamic>>[
      for (var index = 0; index < frameP95.length; index++)
        <String, dynamic>{
          'frame_number': index + 1,
          'cheek_p95_a_after_wb': frameP95[index],
        },
    ],
  };

  group('redness capture mismatch trend lock', () {
    test(
      'cheek-side matcher requires two known, different physical cheeks',
      () {
        final baseline = rednessPayload(
          cheekSide: 'right',
          frameP95: const [10.0, 10.0],
          p10: 4.0,
          p95: 10.0,
        );
        expect(
          aiScanHasCheekSideMismatch(
            currentPayload: rednessPayload(
              cheekSide: 'left',
              frameP95: const [10.0, 10.0],
              p10: 4.0,
              p95: 10.0,
            ),
            baselinePayload: baseline,
          ),
          isTrue,
        );
        expect(
          aiScanHasCheekSideMismatch(
            currentPayload: rednessPayload(
              cheekSide: 'left',
              frameP95: const [10.0, 10.0],
              p10: 4.0,
              p95: 10.0,
            ),
            baselinePayload: rednessPayload(
              cheekSide: 'left',
              frameP95: const [10.0, 10.0],
              p10: 4.0,
              p95: 10.0,
            ),
          ),
          isFalse,
        );
        expect(
          aiScanHasCheekSideMismatch(
            currentPayload: rednessPayload(
              cheekSide: '',
              frameP95: const [10.0, 10.0],
              p10: 4.0,
              p95: 10.0,
            ),
            baselinePayload: baseline,
          ),
          isFalse,
        );
      },
    );

    test('does not create a lock when no redness trend verdict exists', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {},
        trendDeltas: const {},
        trendLockReasons: const {},
        baselinePayload: const {},
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [12.0, 12.5, 12.2],
          p10: 4.5,
          p95: 12.0,
        ),
      );

      expect(result.rednessLockReasons, isEmpty);
      expect(result.trendStatus, isEmpty);
      expect(result.trendDeltas, isEmpty);
    });

    test('today\'s cheek and cast mismatches lock with no percent', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'improved'},
        trendDeltas: const {'localized_redness': 84.0},
        trendLockReasons: const {'localized_redness': 'path_mismatch'},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          frameP95: const [13.382, 13.202, 11.368],
          p10: 2.52,
          p95: 13.382,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [20.89, 20.391, 20.70],
          p10: 10.396,
          p95: 20.89,
        ),
      );

      expect(
        result.rednessLockReasons,
        containsAll(<String>[
          'path_mismatch',
          'cheek_mismatch',
          'cast_mismatch',
        ]),
      );
      expect(result.trendStatus.containsKey('localized_redness'), isFalse);
      expect(result.trendDeltas.containsKey('localized_redness'), isFalse);
      expect(result.trendLockReasons['localized_redness'], 'cheek_mismatch');
    });

    test('same cheek and deltas inside the larger p95 range may trend', () {
      expect(preservedAiExtractionPath('cheek_primary'), 'cheek_primary');
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {
          'localized_redness': 'improved',
          'texture_smoothness': 'stable',
        },
        trendDeltas: const {
          'localized_redness': 12.0,
          'texture_smoothness': 0.0,
        },
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [10.0, 12.0, 11.0],
          p10: 4.0,
          p95: 11.0,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [11.0, 13.0, 12.0],
          p10: 5.0,
          p95: 12.0,
        ),
      );

      expect(result.rednessLockReasons, isEmpty);
      expect(result.trendStatus['localized_redness'], 'improved');
      expect(result.trendStatus['texture_smoothness'], 'stable');
      expect(result.trendDeltas['localized_redness'], 12.0);
      expect(result.trendLockReasons, isEmpty);
    });

    test('new scan and legacy baseline of the same physical cheek compare', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'improved'},
        trendDeltas: const {'localized_redness': 12.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          cheekSideConvention: null,
          frameP95: const [10.0, 12.0, 11.0],
          p10: 4.0,
          p95: 11.0,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [11.0, 13.0, 12.0],
          p10: 5.0,
          p95: 12.0,
        ),
      );

      expect(result.rednessLockReasons, isEmpty);
      expect(result.trendStatus['localized_redness'], 'improved');
    });

    test('different physical cheeks lock redness only', () {
      const otherMetrics = [
        'texture_smoothness',
        'pigment_load',
        'pore_visibility',
        'skin_tone_radiance_evenness',
        'structural_firmness_elasticity',
      ];
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: <String, String>{
          'localized_redness': 'improved',
          for (final metric in otherMetrics) metric: 'improved',
        },
        trendDeltas: <String, double>{
          'localized_redness': 12.0,
          for (final metric in otherMetrics) metric: 12.0,
        },
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          frameP95: const [10.0, 12.0, 11.0],
          p10: 4.0,
          p95: 11.0,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [11.0, 13.0, 12.0],
          p10: 5.0,
          p95: 12.0,
        ),
      );

      expect(result.rednessLockReasons, contains('cheek_mismatch'));
      expect(result.trendStatus.containsKey('localized_redness'), isFalse);
      expect(result.trendDeltas.containsKey('localized_redness'), isFalse);
      expect(result.trendLockReasons['localized_redness'], 'cheek_mismatch');
      for (final metric in otherMetrics) {
        expect(result.trendStatus[metric], 'improved');
        expect(result.trendDeltas[metric], 12.0);
        expect(result.trendLockReasons.containsKey(metric), isFalse);
      }
    });

    test('side-independent redness skips cheek mismatch', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'stable'},
        trendDeltas: const {'localized_redness': 0.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          bothCheeksInDeadZone: true,
          frameP95: const [10.0, 10.2, 10.1],
          p10: 4.0,
          p95: 10.1,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          bothCheeksInDeadZone: true,
          frameP95: const [10.0, 10.2, 10.1],
          p10: 4.0,
          p95: 10.1,
        ),
      );

      expect(result.rednessLockReasons, isEmpty);
      expect(result.trendLockReasons, isEmpty);
    });

    test('missing side-independent flag keeps cheek mismatch', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'stable'},
        trendDeltas: const {'localized_redness': 0.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          frameP95: const [10.0, 10.2, 10.1],
          p10: 4.0,
          p95: 10.1,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [10.0, 10.2, 10.1],
          p10: 4.0,
          p95: 10.1,
        ),
      );

      expect(result.rednessLockReasons, contains('cheek_mismatch'));
      expect(result.trendLockReasons['localized_redness'], 'cheek_mismatch');
    });

    test('different cheeks with real redness still lock', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'worsened'},
        trendDeltas: const {'localized_redness': -20.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          bothCheeksInDeadZone: false,
          frameP95: const [18.0, 18.2, 18.1],
          p10: 6.0,
          p95: 18.1,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          bothCheeksInDeadZone: false,
          frameP95: const [18.0, 18.2, 18.1],
          p10: 6.0,
          p95: 18.1,
        ),
      );

      expect(result.rednessLockReasons, contains('cheek_mismatch'));
      expect(result.trendLockReasons['localized_redness'], 'cheek_mismatch');
    });

    test('path mismatch alone leaves redness status and delta empty', () {
      final payload = rednessPayload(
        cheekSide: 'left',
        frameP95: const [10.0, 12.0, 11.0],
        p10: 4.0,
        p95: 11.0,
      );
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'stable'},
        trendDeltas: const {'localized_redness': 0.0},
        trendLockReasons: const {'localized_redness': 'path_mismatch'},
        baselinePayload: payload,
        currentPayload: payload,
      );

      expect(result.rednessLockReasons, {'path_mismatch'});
      expect(result.trendStatus.containsKey('localized_redness'), isFalse);
      expect(result.trendDeltas.containsKey('localized_redness'), isFalse);
      expect(result.trendLockReasons['localized_redness'], 'path_mismatch');
    });

    test('fewer than two frame p95 values locks as cast mismatch', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'worsened'},
        trendDeltas: const {'localized_redness': -15.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [11.0],
          p10: 4.0,
          p95: 11.0,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [12.0, 12.5, 12.2],
          p10: 4.5,
          p95: 12.0,
        ),
      );

      expect(result.rednessLockReasons, {'cast_mismatch'});
      expect(result.trendStatus.containsKey('localized_redness'), isFalse);
      expect(result.trendDeltas.containsKey('localized_redness'), isFalse);
      expect(result.trendLockReasons['localized_redness'], 'cast_mismatch');
    });
  });

  test('averages each metric over only frames with a finite value', () {
    final aggregate = averageBackendAnalysisFrames([
      {
        'status': 'success',
        'metric_confidence': {
          'localized_redness': 'high',
          'pigment_load': 'medium',
        },
        'metric_matrix': {'localized_redness': 10.0, 'pigment_load': 20.0},
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
        'metric_matrix': {'localized_redness': 30.0, 'pigment_load': 'invalid'},
      },
      {'status': 'error', 'metric_matrix': <String, dynamic>{}},
    ], requestedFrames: 4);

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
    final aggregate = averageBackendAnalysisFrames([
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
    ], requestedFrames: 2);

    expect(aggregate.response['metric_confidence'], {
      'localized_redness': 'high',
      'pigment_load': 'high',
    });
  });

  test('trend verdict for a metric is taken from the frame whose own value is '
      'closest to the displayed average, not always frame 1', () {
    // texture_smoothness values 28.7, 39.5, 50.2 average to 39.466..., so
    // frame 2 (39.5) is the nearest contributor -- its own backend-computed
    // trend fields for texture_smoothness must be the ones surfaced,
    // reproducing the bug where frame 1's "improved" was shown next to the
    // averaged value even though frame 1's own raw value never justified it.
    final aggregate = averageBackendAnalysisFrames([
      {
        'metric_matrix': {'texture_smoothness': 28.7},
        'metric_extraction_paths': {'texture_smoothness': 'primary_roi'},
        'baseline_metric_extraction_paths': {
          'texture_smoothness': 'primary_roi',
        },
        'trend_status': {'texture_smoothness': 'improved'},
        'trend_deltas': {'texture_smoothness': 100.0},
        'trend_lock_reasons': <String, dynamic>{},
      },
      {
        'metric_matrix': {'texture_smoothness': 39.5},
        'metric_extraction_paths': {'texture_smoothness': 'laplacian_fallback'},
        'baseline_metric_extraction_paths': {
          'texture_smoothness': 'primary_roi',
        },
        'trend_status': {'texture_smoothness': 'stable'},
        'trend_deltas': {'texture_smoothness': 5.0},
        'trend_lock_reasons': <String, dynamic>{},
      },
      {
        'metric_matrix': {'texture_smoothness': 50.2},
        'metric_extraction_paths': {'texture_smoothness': 'large_roi_fallback'},
        'baseline_metric_extraction_paths': {
          'texture_smoothness': 'primary_roi',
        },
        'trend_status': {'texture_smoothness': 'improved'},
        'trend_deltas': {'texture_smoothness': 158.0},
        'trend_lock_reasons': <String, dynamic>{},
      },
    ], requestedFrames: 3);

    expect(aggregate.response['trend_status'], {
      'texture_smoothness': 'stable',
    });
    expect(aggregate.response['trend_deltas'], {'texture_smoothness': 5.0});
    expect(aggregate.response['metric_extraction_paths'], {
      'texture_smoothness': 'laplacian_fallback',
      'pore_visibility': 'skipped',
    });
    expect(aggregate.response['baseline_metric_extraction_paths'], {
      'texture_smoothness': 'primary_roi',
    });
    final nestedMetrics = aggregate.response['metrics'] as Map<String, dynamic>;
    expect(nestedMetrics['trend_status'], {'texture_smoothness': 'stable'});
    expect(nestedMetrics['trend_deltas'], {'texture_smoothness': 5.0});
    expect(nestedMetrics['metric_extraction_paths'], {
      'texture_smoothness': 'laplacian_fallback',
      'pore_visibility': 'skipped',
    });
  });

  test(
    'pore visibility omissions retain their path without a metric value',
    () {
      for (final reason in ['pose', 'dog_spread', 'crop', 'skipped']) {
        final aggregate = averageBackendAnalysisFrames([
          {
            'metric_matrix': {'localized_redness': 20.0},
            'metric_extraction_paths': {'pore_visibility': reason},
          },
        ], requestedFrames: 1);

        expect(
          aggregate.response['metric_matrix'],
          isNot(contains('pore_visibility')),
          reason: reason,
        );
        expect(
          (aggregate.response['metric_extraction_paths']
              as Map)['pore_visibility'],
          reason,
          reason: reason,
        );
        final metrics = aggregate.response['metrics'] as Map<String, dynamic>;
        expect(
          (metrics['metric_extraction_paths'] as Map)['pore_visibility'],
          reason,
          reason: reason,
        );
      }
    },
  );

  test('averages raw LAB a_p95 without applying the 0-100 score clamp', () {
    final aggregate = averageBackendAnalysisFrames([
      {
        'status': 'success',
        'metric_matrix': {'localized_redness': 20.0, 'a_p95': 128.25},
      },
      {
        'status': 'success',
        'metric_matrix': {'localized_redness': 22.0, 'a_p95': 130.25},
      },
    ], requestedFrames: 2);

    final matrix = aggregate.response['metric_matrix'] as Map<String, double>;
    expect(matrix['a_p95'], 129.25);
    expect(aggregate.metricContributorCounts['a_p95'], 2);
  });

  test('scored pore visibility remains primary_roi through aggregation', () {
    final aggregate = averageBackendAnalysisFrames([
      {
        'metric_matrix': {'pore_visibility': 79.6},
        'metric_extraction_paths': {'pore_visibility': 'primary_roi'},
      },
    ], requestedFrames: 1);

    expect(aggregate.response['metric_matrix'], {'pore_visibility': 79.6});
    expect(
      (aggregate.response['metric_extraction_paths'] as Map)['pore_visibility'],
      'primary_roi',
    );
  });

  test('trend fields read from a nested metrics node are honored the same as '
      'top-level ones when picking the nearest frame', () {
    final aggregate = averageBackendAnalysisFrames([
      {
        'metrics': {
          'metric_matrix': {'localized_redness': 10.0},
          'trend_status': {'localized_redness': 'worsened'},
          'trend_deltas': {'localized_redness': -40.0},
          'trend_lock_reasons': {'localized_redness': 'some_reason'},
        },
      },
      {
        'metrics': {
          'metric_matrix': {'localized_redness': 30.0},
          'trend_status': {'localized_redness': 'stable'},
          'trend_deltas': {'localized_redness': 2.0},
        },
      },
    ], requestedFrames: 2);

    // Average is 20.0, exactly between the two frames' own values (10.0
    // and 30.0) -- both are equally close, so the tie-break (first
    // strictly-smaller distance wins) keeps frame 1's worsened verdict.
    expect(aggregate.response['metric_matrix'], {'localized_redness': 20.0});
    expect(aggregate.response['trend_status'], {
      'localized_redness': 'worsened',
    });
    expect(aggregate.response['trend_lock_reasons'], {
      'localized_redness': 'some_reason',
    });
  });

  test('throws when no frame contributes a finite metric', () {
    expect(
      () => averageBackendAnalysisFrames([
        {
          'metric_matrix': {'localized_redness': null},
        },
      ], requestedFrames: 1),
      throwsStateError,
    );
  });

  test(
    'missing upload acknowledgment never calls the frame uploader',
    () async {
      var uploadCalls = 0;
      await expectLater(
        analyzeBackendFrames(
          [
            Uint8List.fromList([1]),
          ],
          photoUploadAccepted: false,
          uploadFrame: (frame, frameNumber) async {
            uploadCalls++;
            return {
              'metric_matrix': {'localized_redness': 20.0},
            };
          },
        ),
        throwsStateError,
      );
      expect(uploadCalls, 0);
    },
  );

  test(
    'uploads all three frames after acceptance and excludes a failed frame from averages',
    () async {
      final requestedFrameNumbers = <int>[];
      final aggregate = await analyzeBackendFrames(
        [
          Uint8List.fromList([1]),
          Uint8List.fromList([2]),
          Uint8List.fromList([3]),
        ],
        photoUploadAccepted: true,
        frameExposureMetadata: const [
          AiScanFrameExposure(
            iso: 100,
            exposureBias: -0.3,
            shutterSeconds: 1 / 120,
            brightnessValue: 4.5,
            flashFired: false,
          ),
          AiScanFrameExposure(iso: 125),
          AiScanFrameExposure(
            iso: 160,
            exposureBias: 0.0,
            shutterSeconds: 1 / 60,
          ),
        ],
        uploadFrame: (frame, frameNumber) async {
          requestedFrameNumbers.add(frameNumber);
          if (frameNumber == 2) throw Exception('no face detected');
          return {
            'status': 'success',
            'image_quality': {
              'redness_cheek_side': frameNumber == 1 ? 'left' : 'right',
              'cheek_side_convention': cheekSideConventionSubjectAnatomical,
              'redness_both_cheeks_in_dead_zone': false,
              'redness_cheek_roi_pixels': frameNumber == 1 ? 2100 : 2300,
              'redness_cheek_p95_a_after_wb': frameNumber == 1 ? 31.5 : 33.5,
              'redness_cheek_p10_a_after_wb': frameNumber == 1 ? 20.5 : 21.5,
              'redness_cheek_p10_a_before_wb': frameNumber == 1 ? 19.5 : 20.5,
              'face_skin_pixels': 18000,
              'pore_roi_pixels': 6200,
              'u_zone_pixels': 9500,
              'localized_redness_mask_kind': 'cheek_primary',
              'localized_redness_mask_pixels': 9500,
              'texture_smoothness_mask_kind': 'face_skin',
              'texture_smoothness_mask_pixels': 18000,
              'pigment_load_mask_kind': 'cheek_primary',
              'pigment_load_mask_pixels': 9500,
              'pore_visibility_mask_kind': 'tzone_pore',
              'pore_visibility_mask_pixels': 6200,
              'diffuse_flushing_erythema_mask_kind': 'face_skin',
              'diffuse_flushing_erythema_mask_pixels': 10200,
            },
            'metric_extraction_paths': {
              'pore_visibility': frameNumber == 1 ? 'pose' : 'dog_spread',
            },
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
      final diagnostics =
          aggregate.response[aiScanPerFrameDiagnosticsKey] as List<dynamic>;
      expect(diagnostics, hasLength(3));
      expect(diagnostics[0], containsPair('cheek_side', 'left'));
      expect(
        diagnostics[0],
        containsPair(
          'cheek_side_convention',
          cheekSideConventionSubjectAnatomical,
        ),
      );
      expect(
        diagnostics[0],
        containsPair('redness_both_cheeks_in_dead_zone', isFalse),
      );
      expect(diagnostics[0], containsPair('localized_redness', 20.0));
      expect(diagnostics[0], containsPair('cheek_p10_a_after_wb', 20.5));
      expect(diagnostics[0], containsPair('shutter_seconds', 1 / 120));
      expect(diagnostics[0], containsPair('flash_fired', isFalse));
      expect(diagnostics[0], containsPair('face_skin_pixels', 18000));
      expect(
        diagnostics[0],
        containsPair('localized_redness_mask_kind', 'cheek_primary'),
      );
      expect(
        diagnostics[0],
        containsPair('pore_visibility_mask_kind', 'tzone_pore'),
      );
      expect(
        diagnostics[0],
        containsPair('pore_visibility_extraction_path', 'pose'),
      );
      expect(diagnostics[1], containsPair('cheek_side', isNull));
      expect(diagnostics[1], containsPair('localized_redness', isNull));
      expect(diagnostics[1], containsPair('iso', 125));
      expect(diagnostics[1], containsPair('brightness_value', isNull));
      expect(diagnostics[2], containsPair('cheek_side', 'right'));
      expect(diagnostics[2], containsPair('localized_redness', 40.0));
      expect(diagnostics[2], containsPair('brightness_value', isNull));

      final saved = ScanHistoryEntry.fromJson(
        ScanHistoryEntry(
          id: 'three-frame-scan',
          timestamp: DateTime.parse('2026-09-26T06:13:00Z'),
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          estimatedSkinAge: 0,
          metrics: const <String, double>{},
          rawPayload: aggregate.response,
        ).toJson(),
      );
      final storedDiagnostics =
          saved.rawPayload![aiScanPerFrameDiagnosticsKey] as List<dynamic>;
      expect(storedDiagnostics, hasLength(3));
      expect(storedDiagnostics[1], containsPair('localized_redness', isNull));
      expect(storedDiagnostics[1], containsPair('brightness_value', isNull));
    },
  );

  test(
    'AI multi-frame mode is opt-in and Track Procedure remains single-path',
    () {
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
    },
  );

  test(
    'AI backend fields carry distinct current and previous capture quality tags',
    () {
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
    },
  );

  test(
    'AI backend fields carry pose template and guide type for both scans',
    () {
      final fields = buildAiSkinAnalysisBackendFields(
        focusArea: 'Full Face',
        poseTemplate: 'Front',
        baselinePoseTemplate: 'Front',
        guideType: 'facial',
        baselineGuideType: 'facial',
      );

      expect(fields['pose_template'], 'Front');
      expect(fields['baseline_pose_template'], 'Front');
      expect(fields['guide_type'], 'facial');
      expect(fields['baseline_guide_type'], 'facial');
    },
  );

  test('AI backend fields omit pose/guide keys entirely when unknown', () {
    final fields = buildAiSkinAnalysisBackendFields(focusArea: 'Full Face');

    expect(fields.containsKey('pose_template'), isFalse);
    expect(fields.containsKey('baseline_pose_template'), isFalse);
    expect(fields.containsKey('guide_type'), isFalse);
    expect(fields.containsKey('baseline_guide_type'), isFalse);
  });
}
