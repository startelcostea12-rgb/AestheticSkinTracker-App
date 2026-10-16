import 'dart:convert';

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
  'image_quality.gray_card_correction_applied',
  'image_quality.gray_card_frames_applied',
  'image_quality.gray_card_reason',
];

Map<String, dynamic> _frame({
  required bool marked,
  bool applied = false,
  double? l,
  double? a,
  double? b,
  String? reason,
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
  },
};

void main() {
  test('summary: marked, applied on every frame, mean of the raw samples', () {
    final summary = summarizeGrayCardFrames([
      _frame(marked: true, applied: true, l: 120, a: 6.0, b: 9.0),
      _frame(marked: true, applied: true, l: 122, a: 5.0, b: 8.0),
      _frame(marked: true, applied: true, l: 124, a: 4.0, b: 10.0),
    ]);
    expect(summary, {
      'gray_card_marked': true,
      'gray_card_mean_L': 122.0,
      'gray_card_mean_a': 5.0,
      'gray_card_mean_b': 9.0,
      'gray_card_correction_applied': true,
      'gray_card_frames_applied': 3,
      'gray_card_reason': null,
    });
  });

  test('summary: applied only if every frame applied it', () {
    final summary = summarizeGrayCardFrames([
      _frame(marked: true, applied: true, l: 120, a: 6.0, b: 9.0),
      _frame(marked: true, reason: 'region_out_of_bounds'),
    ]);
    expect(summary['gray_card_correction_applied'], isFalse);
    expect(summary['gray_card_frames_applied'], 1);
    expect(summary['gray_card_reason'], 'region_out_of_bounds');
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
    expect(off.containsKey('gray_card_region'), isFalse);

    final on = buildAiSkinAnalysisBackendFields(
      focusArea: 'Full face',
      grayCardRegion: (x: 0.05, y: 0.1, w: 0.2, h: 0.15),
    );
    expect(jsonDecode(on['gray_card_region']!), {
      'x': 0.05,
      'y': 0.1,
      'w': 0.2,
      'h': 0.15,
    });
  });
}
