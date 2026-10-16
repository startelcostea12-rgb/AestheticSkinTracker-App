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
  'image_quality.gray_card_used',
  'image_quality.gray_card_gain_r',
  'image_quality.gray_card_gain_g',
  'image_quality.gray_card_gain_b',
  'image_quality.gray_card_reason',
];

void main() {
  test('export logs gray_card_used and the gains', () {
    final csv = AiScanDataCsvExporter.format([
      _scan({
        'gray_card_used': true,
        'gray_card_gain_r': 0.8333,
        'gray_card_gain_g': 1.0,
        'gray_card_gain_b': 1.25,
      }),
    ], registryBaselineScanIds: const {});
    final header = csv.split('\r\n').first.split(',');
    for (final column in _grayCardColumns) {
      expect(header.where((c) => c == column), hasLength(1), reason: column);
    }
    final row = _parse(csv).single;
    expect(row['image_quality.gray_card_used'], 'true');
    expect(row['image_quality.gray_card_gain_r'], '0.8333');
    expect(row['image_quality.gray_card_gain_g'], '1.0');
    expect(row['image_quality.gray_card_gain_b'], '1.25');
  });

  test('skipped or older scans export the skip or empty cells', () {
    final rows = _parse(
      AiScanDataCsvExporter.format([
        _scan({'gray_card_used': false, 'gray_card_reason': 'no_card_region'}),
      ], registryBaselineScanIds: const {}),
    );
    expect(rows.single['image_quality.gray_card_used'], 'false');
    expect(rows.single['image_quality.gray_card_gain_r'], isEmpty);
    expect(rows.single['image_quality.gray_card_reason'], 'no_card_region');

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
