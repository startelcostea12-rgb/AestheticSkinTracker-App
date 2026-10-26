import 'dart:convert';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, String>> _parse(String csv) {
  final rows = csv.split('\r\n');
  final columns = rows.first.split(',');
  return [
    for (final row in rows.skip(1))
      {for (var i = 0; i < columns.length; i++) columns[i]: row.split(',')[i]},
  ];
}

ScanHistoryEntry _scan(Map<String, dynamic> imageQuality) => ScanHistoryEntry(
  id: 'scan-1',
  timestamp: DateTime.parse('2026-10-15T08:00:00'),
  scanType: ScanHistoryEntry.scanTypeAiAnalysis,
  estimatedSkinAge: 0,
  metrics: const <String, double>{},
  rawPayload: <String, dynamic>{
    'metric_matrix': <String, dynamic>{'localized_redness': 5.0},
    'image_quality': imageQuality,
  },
);

const _grayCardColumns = [
  'image_quality.gray_card_marked',
  'image_quality.gray_card_mean_L',
  'image_quality.gray_card_mean_a',
  'image_quality.gray_card_mean_b',
  'image_quality.gray_card_chroma_offset',
  'image_quality.gray_card_scene_disagreement',
  'image_quality.gray_card_correction_applied',
  'image_quality.gray_card_frames_applied',
  'image_quality.gray_card_reason',
  'image_quality.gray_card_region_space',
  'image_quality.gray_card_region_x',
  'image_quality.gray_card_region_y',
  'image_quality.gray_card_region_w',
  'image_quality.gray_card_region_h',
];

Map<String, dynamic> _frame({
  required bool marked,
  bool applied = false,
  double? l,
  double? a,
  double? b,
  String? reason,
  double? offset,
  double? disagreement,
  double redness = 10.0,
}) => <String, dynamic>{
  'metric_matrix': <String, dynamic>{'localized_redness': redness},
  'metric_extraction_paths': <String, dynamic>{
    'localized_redness': 'cheek_primary',
  },
  'image_quality': <String, dynamic>{
    'chroma_cast': 3.1,
    'whole_image_mean_a_before_wb': 9.5,
    'gray_card_marked': marked,
    'gray_card_mean_L': l,
    'gray_card_mean_a': a,
    'gray_card_mean_b': b,
    'gray_card_correction_applied': applied,
    'gray_card_reason': reason,
    'gray_card_chroma_offset': offset,
    'gray_card_scene_disagreement': disagreement,
    if (marked) ..._regionQuality,
  },
};

const _regionQuality = <String, dynamic>{
  'gray_card_region_space': 'full_still',
  'gray_card_region_x': 0.3,
  'gray_card_region_y': 0.82,
  'gray_card_region_w': 0.4,
  'gray_card_region_h': 0.12,
};

void main() {
  for (final scenario in const [
    (passed: 1, read: 5, status: 'partial'),
    (passed: 2, read: 5, status: 'partial'),
    (passed: 3, read: 5, status: 'applied'),
    (passed: 0, read: 5, status: 'rejected_wrong_area'),
    (passed: 1, read: 1, status: 'applied'),
  ]) {
    test(
      '${scenario.passed} of ${scenario.read} card readings: ${scenario.status}',
      () async {
        final frames = [
          for (var index = 0; index < scenario.read; index++)
            Uint8List.fromList([index, 42]),
        ];
        final retries = <int>[];
        final aggregate = await analyzeBackendFrames(
          frames,
          photoUploadAccepted: true,
          uploadFrame: (frame, number) async {
            final passed = number <= scenario.passed;
            final response = _frame(
              marked: true,
              applied: passed,
              l: 131,
              a: passed ? 0 : 19.0 + number,
              b: passed ? 0 : 9,
              reason: passed ? null : 'implausible_card_color',
              redness: passed ? 20 : 10,
            )..['preprocessed_pixels'] = passed ? [1, 2, 3] : frame.toList();
            return response;
          },
          uploadFrameWithoutGrayCard: (frame, number) async {
            retries.add(number);
            expect(frame, orderedEquals(frames[number - 1]));
            return _frame(marked: false, redness: 10)
              ..['preprocessed_pixels'] = frame.toList();
          },
        );
        final payload = aggregate.response;
        final quality = payload['image_quality'] as Map<String, dynamic>;
        expect(quality['gray_card_status'], scenario.status);
        expect(quality['gray_card_frames_applied'], scenario.passed);
        expect(quality['gray_card_frames_read'], scenario.read);
        final applied = scenario.status == 'applied';
        expect(quality['gray_card_correction_applied'], applied);
        expect(quality['gray_card_retake_recommended'], !applied);
        expect(quality['gray_card_baseline_eligible'], applied);
        expect(payload['gray_card_status'], scenario.status);
        expect(
          (payload['metrics'] as Map)['gray_card_status'],
          scenario.status,
        );
        if (scenario.status == 'partial') {
          expect(retries, [1, 2, 3, 4, 5]);
          expect(payload['preprocessed_pixels'], frames.first.toList());
          expect((payload['metric_matrix'] as Map)['localized_redness'], 10);
          expect(
            quality['gray_card_message'],
            contains('not steady across the burst'),
          );
        } else {
          expect(retries, isEmpty);
          if (applied) {
            expect(payload['preprocessed_pixels'], [1, 2, 3]);
            expect(
              (payload['metric_matrix'] as Map)['localized_redness'],
              greaterThan(10),
            );
          } else {
            expect(payload['preprocessed_pixels'], frames.first.toList());
            expect(quality['gray_card_reason'], 'implausible_card_color');
          }
        }
        final saved = ScanHistoryEntry(
          id: 'burst',
          timestamp: DateTime(2026, 10, 26),
          estimatedSkinAge: 0,
          metrics: const {},
          poseTemplate: 'Front',
          guideType: 'facial',
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          captureQuality: 'normal',
          rawPayload: {
            ...payload,
            'metric_formula_versions': {'localized_redness': 4},
          },
        );
        expect(scanPassesSingleScanBaselineGates(saved), applied);
        final row = _parse(
          AiScanDataCsvExporter.format([
            saved,
          ], registryBaselineScanIds: const {}),
        ).single;
        expect(row['image_quality.gray_card_status'], scenario.status);
        expect(
          row['image_quality.gray_card_frames_applied'],
          '${scenario.passed}',
        );
        expect(row['image_quality.gray_card_frames_read'], '${scenario.read}');
        expect(row['image_quality.gray_card_baseline_eligible'], '$applied');
      },
    );
  }

  for (final missingCallback in const [true, false]) {
    test(
      'partial burst never uses corrected frames if no-card retry fails ($missingCallback)',
      () async {
        await expectLater(
          analyzeBackendFrames(
            [Uint8List(1), Uint8List(1)],
            photoUploadAccepted: true,
            uploadFrame: (_, number) async => _frame(
              marked: true,
              applied: number == 1,
              l: 131,
              a: number == 1 ? 0 : 25,
              b: 0,
            ),
            uploadFrameWithoutGrayCard: missingCallback
                ? null
                : (_, _) async => throw StateError('retry failed'),
          ),
          throwsStateError,
        );
      },
    );
  }

  test('summary: marked, applied on every frame, mean of the raw samples', () {
    final summary = summarizeGrayCardFrames([
      _frame(
        marked: true,
        applied: true,
        l: 120,
        a: 6.0,
        b: 9.0,
        offset: 10.8,
        disagreement: 2.0,
      ),
      _frame(
        marked: true,
        applied: true,
        l: 122,
        a: 5.0,
        b: 8.0,
        offset: 9.4,
        disagreement: 3.0,
      ),
      _frame(
        marked: true,
        applied: true,
        l: 124,
        a: 4.0,
        b: 10.0,
        offset: 10.8,
        disagreement: 4.0,
      ),
    ]);
    expect(summary, {
      'gray_card_marked': true,
      'gray_card_mean_L': 122.0,
      'gray_card_mean_a': 5.0,
      'gray_card_mean_b': 9.0,
      'gray_card_chroma_offset': 10.333,
      'gray_card_scene_disagreement': 3.0,
      'gray_card_correction_applied': true,
      'gray_card_frames_applied': 3,
      'gray_card_frames_read': 3,
      'gray_card_status': 'applied',
      'gray_card_message': null,
      'gray_card_retake_recommended': false,
      'gray_card_baseline_eligible': true,
      'gray_card_reason': null,
      ..._regionQuality,
    });
  });

  test('summary: unreadable frames do not count as card readings', () {
    final summary = summarizeGrayCardFrames([
      _frame(marked: true, applied: true, l: 120, a: 6.0, b: 9.0),
      _frame(marked: true, reason: 'region_out_of_bounds'),
    ]);
    expect(summary['gray_card_correction_applied'], isTrue);
    expect(summary['gray_card_frames_applied'], 1);
    expect(summary['gray_card_frames_read'], 1);
    expect(summary['gray_card_reason'], isNull);
    expect(summary['gray_card_mean_a'], 6.0);
  });

  test('summary: no mark and older backends', () {
    final unmarked = summarizeGrayCardFrames([
      _frame(marked: false),
      _frame(marked: false),
    ]);
    expect(unmarked['gray_card_marked'], isFalse);
    expect(unmarked['gray_card_correction_applied'], isFalse);
    expect(unmarked['gray_card_mean_a'], isNull);
    expect(
      summarizeGrayCardFrames([
        {
          'metric_matrix': {'localized_redness': 1.0},
          'image_quality': {'chroma_cast': 2.0},
        },
      ]),
      isEmpty,
    );
  });

  test('aggregate and export: scan summary and per-frame columns', () {
    final aggregate = averageBackendAnalysisFrames([
      _frame(marked: true, applied: true, l: 120, a: 6.0, b: 9.0),
      _frame(marked: true, applied: true, l: 122, a: 5.0, b: 8.0),
      _frame(marked: true, applied: true, l: 124, a: 4.0, b: 10.0),
    ], requestedFrames: 3);
    final payload = <String, dynamic>{
      ...aggregate.response,
      aiScanPerFrameDiagnosticsKey: buildAiScanPerFrameDiagnostics(
        frameResponses: [
          _frame(marked: true, applied: true, l: 120, a: 6.0, b: 9.0),
          _frame(marked: true, applied: true, l: 122, a: 5.0, b: 8.0),
          _frame(marked: true, applied: true, l: 124, a: 4.0, b: 10.0),
        ],
        frameExposureMetadata: const [],
        frameCount: 3,
      ),
    };
    final csv = AiScanDataCsvExporter.format([
      ScanHistoryEntry(
        id: 'scan-gc',
        timestamp: DateTime.parse('2026-10-16T08:00:00'),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: payload,
      ),
    ], registryBaselineScanIds: const {});
    final header = csv.split('\r\n').first.split(',');
    for (final column in _grayCardColumns) {
      expect(header.where((c) => c == column), hasLength(1), reason: column);
    }
    final row = _parse(csv).single;
    expect(row['image_quality.gray_card_marked'], 'true');
    expect(row['image_quality.gray_card_correction_applied'], 'true');
    expect(row['image_quality.gray_card_frames_applied'], '3');
    expect(row['image_quality.gray_card_mean_a'], '5.0');
    expect(row['image_quality.gray_card_mean_L'], '122.0');
    // Before/after stays visible.
    expect(row['image_quality.chroma_cast'], '3.1');
    expect(row['image_quality.whole_image_mean_a_before_wb'], '9.5');
    // Per frame.
    expect(row['frame1_gray_card_marked'], 'true');
    expect(row['frame2_gray_card_mean_a'], '5.0');
    expect(row['frame3_gray_card_mean_b'], '10.0');
    expect(row['frame3_gray_card_correction_applied'], 'true');
    // Where the box was drawn.
    expect(row['image_quality.gray_card_region_space'], 'full_still');
    expect(row['image_quality.gray_card_region_y'], '0.82');
    expect(row['frame2_gray_card_region_h'], '0.12');
  });

  test('a rejected box still exports a scan with the reason', () {
    final frames = [
      for (var i = 0; i < 3; i++)
        _frame(
          marked: true,
          l: 90,
          a: 40.0,
          b: 20.0,
          reason: 'implausible_card_color',
        ),
    ];
    final aggregate = averageBackendAnalysisFrames(frames, requestedFrames: 3);
    expect(aggregate.successfulFrames, 3);
    final row = _parse(
      AiScanDataCsvExporter.format([
        ScanHistoryEntry(
          id: 'scan-rejected',
          timestamp: DateTime.parse('2026-10-16T09:00:00'),
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          estimatedSkinAge: 0,
          metrics: const <String, double>{},
          rawPayload: <String, dynamic>{
            ...aggregate.response,
            aiScanPerFrameDiagnosticsKey: buildAiScanPerFrameDiagnostics(
              frameResponses: frames,
              frameExposureMetadata: const [],
              frameCount: 3,
            ),
          },
        ),
      ], registryBaselineScanIds: const {}),
    ).single;
    expect(row['localized_redness_value'], '10.0');
    expect(row['image_quality.gray_card_marked'], 'true');
    expect(row['image_quality.gray_card_correction_applied'], 'false');
    expect(row['image_quality.gray_card_frames_applied'], '0');
    expect(row['image_quality.gray_card_reason'], 'implausible_card_color');
    expect(row['frame1_gray_card_reason'], 'implausible_card_color');
    expect(row['image_quality.gray_card_region_x'], '0.3');
  });

  test('a card that disagrees with the scene exports offset and reason', () {
    final frames = [
      for (var i = 0; i < 3; i++)
        _frame(
          marked: true,
          l: 140,
          a: 3.0,
          b: 8.0,
          reason: 'disagrees_with_scene',
          offset: 8.5,
          disagreement: 14.3,
        ),
    ];
    final aggregate = averageBackendAnalysisFrames(frames, requestedFrames: 3);
    final row = _parse(
      AiScanDataCsvExporter.format([
        ScanHistoryEntry(
          id: 'scan-scene',
          timestamp: DateTime.parse('2026-10-16T10:00:00'),
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          estimatedSkinAge: 0,
          metrics: const <String, double>{},
          rawPayload: <String, dynamic>{
            ...aggregate.response,
            aiScanPerFrameDiagnosticsKey: buildAiScanPerFrameDiagnostics(
              frameResponses: frames,
              frameExposureMetadata: const [],
              frameCount: 3,
            ),
          },
        ),
      ], registryBaselineScanIds: const {}),
    ).single;
    expect(row['image_quality.gray_card_correction_applied'], 'false');
    expect(row['image_quality.gray_card_reason'], 'disagrees_with_scene');
    expect(row['image_quality.gray_card_chroma_offset'], '8.5');
    expect(row['image_quality.gray_card_scene_disagreement'], '14.3');
    expect(row['frame2_gray_card_scene_disagreement'], '14.3');
    expect(row['frame3_gray_card_chroma_offset'], '8.5');
  });

  test('no mark: gray_card_marked is false and samples are empty', () {
    final row = _parse(
      AiScanDataCsvExporter.format([
        _scan({
          'gray_card_marked': false,
          'gray_card_correction_applied': false,
        }),
      ], registryBaselineScanIds: const {}),
    ).single;
    expect(row['image_quality.gray_card_marked'], 'false');
    expect(row['image_quality.gray_card_correction_applied'], 'false');
    expect(row['image_quality.gray_card_mean_a'], isEmpty);
  });

  test('older scans export empty gray-card cells', () {
    final old = _parse(
      AiScanDataCsvExporter.format([
        _scan({'chroma_cast': 4.0}),
      ], registryBaselineScanIds: const {}),
    ).single;
    for (final column in _grayCardColumns) {
      expect(old[column], isEmpty, reason: column);
    }
  });

  test('gray card region is sent only when supplied', () {
    final off = buildAiSkinAnalysisBackendFields(focusArea: 'Full face');
    expect(off.containsKey('gray_card_still_region'), isFalse);
    expect(off.containsKey('gray_card_region'), isFalse);

    final on = buildAiSkinAnalysisBackendFields(
      focusArea: 'Full face',
      grayCardRegion: (x: 0.05, y: 0.1, w: 0.2, h: 0.15),
    );
    expect(on.containsKey('gray_card_region'), isFalse);
    expect(jsonDecode(on['gray_card_still_region']!), {
      'x': 0.05,
      'y': 0.1,
      'w': 0.2,
      'h': 0.15,
    });
  });
}
