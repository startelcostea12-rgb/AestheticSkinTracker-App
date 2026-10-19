import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _frame(Map<String, double> values) => <String, dynamic>{
  'metric_matrix': values,
};

/// Five frames: the four noisy metrics vary; pigment_load is 10/12/14 in
/// frames 1-3 and a wild 40 in frames 4-5.
List<Map<String, dynamic>> _fiveFrames() => [
  for (final (i, wrinkle) in const [
    (0, 30.0),
    (1, 34.0),
    (2, 50.0),
    (3, 31.0),
    (4, 33.0),
  ])
    _frame({
      'wrinkle_load': wrinkle,
      'pore_contraction_index': 60.0 + i,
      'under_eye_dark_circle_density': 20.0 + i * 2,
      'under_eye_texture_density': 50.0 - i,
      'pigment_load': i < 3 ? 10.0 + i * 2 : 40.0,
    }),
];

void main() {
  test('the four noisy metrics are the median of five; versions noted', () {
    expect(fiveFrameMedianMetricKeys, {
      'wrinkle_load',
      'pore_contraction_index',
      'under_eye_dark_circle_density',
      'under_eye_texture_density',
    });
    expect(aiScanCaptureFrameCount, 5);
    final matrix =
        averageBackendAnalysisFrames(
              _fiveFrames(),
              requestedFrames: 5,
            ).response['metric_matrix']
            as Map;
    // wrinkle [30, 34, 50, 31, 33] -> median 33 (the mean would be 35.6).
    expect(matrix['wrinkle_load'], 33.0);
    expect(matrix['pore_contraction_index'], 62.0);
    expect(matrix['under_eye_dark_circle_density'], 24.0);
    expect(matrix['under_eye_texture_density'], 48.0);
  });

  test('every other metric keeps the three-frame mean of frames 1-3', () {
    final aggregate = averageBackendAnalysisFrames(
      _fiveFrames(),
      requestedFrames: 5,
    );
    final matrix = aggregate.response['metric_matrix'] as Map;
    expect(matrix['pigment_load'], 12.0); // frames 4-5 (40.0) ignored
    expect(aggregate.metricContributorCounts['pigment_load'], 3);
    expect(aggregate.metricContributorCounts['wrinkle_load'], 5);
    final ranges =
        (aggregate.response['multi_frame_analysis'] as Map)['metric_ranges']
            as Map;
    expect((ranges['pigment_load'] as Map)['max'], 14.0);
  });

  test('a failed frame shifts nothing: frame numbers decide', () {
    final frames = _fiveFrames();
    // Frame 2 failed: responses are frames 1, 3, 4, 5.
    final aggregate = averageBackendAnalysisFrames(
      [frames[0], frames[2], frames[3], frames[4]],
      requestedFrames: 5,
      frameNumbers: const [1, 3, 4, 5],
    );
    final matrix = aggregate.response['metric_matrix'] as Map;
    expect(matrix['pigment_load'], 12.0); // mean of frames 1 and 3 only
    // Only four frames for the noisy metrics: omitted, never a fallback.
    for (final key in fiveFrameMedianMetricKeys) {
      expect(matrix.containsKey(key), isFalse, reason: key);
      expect(aggregate.response.containsKey(key), isFalse, reason: key);
      expect(
        (aggregate.response['metric_extraction_paths'] as Map)[key],
        'skipped',
      );
    }
    expect(
      (aggregate.response['multi_frame_analysis']
          as Map)['five_frame_median_omitted'],
      [
        'pore_contraction_index',
        'under_eye_dark_circle_density',
        'under_eye_texture_density',
        'wrinkle_load',
      ],
    );
  });

  test('a single gallery frame omits the four, keeps the rest', () {
    final matrix =
        averageBackendAnalysisFrames([
              _fiveFrames().first,
            ], requestedFrames: 1).response['metric_matrix']
            as Map;
    expect(matrix.keys, ['pigment_load']);
  });

  test('the export carries five frames of per-frame columns', () {
    final aggregate = averageBackendAnalysisFrames(
      _fiveFrames(),
      requestedFrames: 5,
    );
    final payload = <String, dynamic>{
      ...aggregate.response,
      aiScanPerFrameDiagnosticsKey: buildAiScanPerFrameDiagnostics(
        frameResponses: _fiveFrames(),
        frameExposureMetadata: const [],
        frameCount: 5,
      ),
    };
    final rows = AiScanDataCsvExporter.format([
      ScanHistoryEntry(
        id: 'five',
        timestamp: DateTime.parse('2026-10-19T09:00:00'),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: payload,
      ),
    ], registryBaselineScanIds: const {}).split('\r\n');
    final header = rows.first.split(',');
    expect(header, contains('frame5_brightness_value'));
    expect(header, isNot(contains('frame6_brightness_value')));
    final values = rows[1].split(',');
    expect(values[header.indexOf('wrinkle_load_value')], '33.0');
    expect(values[header.indexOf('pigment_load_value')], '12.0');
  });
}
