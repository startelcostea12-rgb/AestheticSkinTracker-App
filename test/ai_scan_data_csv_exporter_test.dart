import 'package:flutter_test/flutter_test.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';

/// Header + rows as name -> cell maps. Test values never contain commas or
/// quotes, so a plain split is exact here.
List<Map<String, String>> _parse(String csv) {
  final rows = csv.split('\r\n');
  final columns = rows.first.split(',');
  return [
    for (final row in rows.skip(1))
      {
        for (var i = 0; i < columns.length; i++) columns[i]: row.split(',')[i],
      },
  ];
}

ScanHistoryEntry _aiScan(
  String id, {
  Map<String, dynamic>? rawPayload,
  bool isBaseline = false,
  String? parentBaselineId,
}) {
  return ScanHistoryEntry(
    id: id,
    timestamp: DateTime.parse('2026-09-25T06:13:00'),
    scanType: ScanHistoryEntry.scanTypeAiAnalysis,
    estimatedSkinAge: 0,
    metrics: const <String, double>{},
    isBaseline: isBaseline,
    parentBaselineId: parentBaselineId,
    rawPayload:
        rawPayload ??
        const <String, dynamic>{
          'metric_matrix': <String, dynamic>{'rosacea_severity': 3.0},
        },
  );
}

void main() {
  group('AiScanDataCsvExporter', () {
    test('missing stored values remain empty CSV cells', () {
      final scan = _aiScan(
        'scan-1',
        rawPayload: const <String, dynamic>{
          'metric_matrix': <String, dynamic>{'rosacea_severity': 3.0},
          'image_quality': <String, dynamic>{
            'white_balance_profile': <String, dynamic>{
              'reference_found': false,
              'reason': 'disabled',
            },
          },
        },
      );

      final row = _parse(
        AiScanDataCsvExporter.format([scan], registryBaselineScanIds: const {}),
      ).single;

      expect(row['guideType'], isEmpty);
      expect(row['image_quality.lighting_mean_l'], isEmpty);
      expect(row['rosacea_severity_trend_status'], isEmpty);
      expect(row['comparison_baseline_scan_id'], isEmpty);
      expect(row['image_quality.white_balance_profile.reason'], 'disabled');
      expect(row['rosacea_severity_value'], '3.0');
    });

    test('exports real extraction paths verbatim', () {
      final scan = _aiScan(
        'scan-paths',
        rawPayload: const <String, dynamic>{
          'metric_matrix': <String, dynamic>{
            'localized_redness': 20.0,
            'texture_smoothness': 30.0,
            'pigment_load': 40.0,
            'breakout_activity': 10.0,
          },
          'metric_extraction_paths': <String, dynamic>{
            'localized_redness': 'cheek_primary',
            'texture_smoothness': 'laplacian_fallback',
            'pigment_load': 'full_face_fallback',
            'breakout_activity': 'full_face_yolo',
          },
        },
      );

      final row = _parse(
        AiScanDataCsvExporter.format([scan], registryBaselineScanIds: const {}),
      ).single;

      expect(row['localized_redness_extraction_path'], 'cheek_primary');
      expect(row['texture_smoothness_extraction_path'], 'laplacian_fallback');
      expect(row['pigment_load_extraction_path'], 'full_face_fallback');
      expect(row['breakout_activity_extraction_path'], 'full_face_yolo');
    });

    test('AI scan with no backend rawPayload is skipped', () {
      final scan = ScanHistoryEntry(
        id: 'scan-without-payload',
        timestamp: DateTime.parse('2026-09-25T06:00:00'),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{'localized_redness': 12},
      );

      final rows = AiScanDataCsvExporter.format(
        [scan],
        registryBaselineScanIds: const {},
      ).split('\r\n');

      expect(rows, hasLength(1));
      expect(rows.single, contains('scan_id'));
      expect(AiScanDataCsvExporter.exportableScans([scan]), isEmpty);
    });

    test('new color and redness-branch fields export as their own columns', () {
      final scan = _aiScan(
        'scan-new',
        rawPayload: const <String, dynamic>{
          'metric_matrix': <String, dynamic>{'localized_redness': 52.6},
          'image_quality': <String, dynamic>{
            'chroma_cast': 15.22,
            'white_balance_profile': <String, dynamic>{
              'applied': true,
              'a_adjustment': -3.5,
              'b_adjustment': 0.7,
            },
            'color_lab_units': 'signed_a_b_neutral_0',
            'whole_image_mean_a_before_wb': 9.5,
            'whole_image_mean_b_before_wb': 11.25,
            'whole_image_mean_a_after_wb': 12.75,
            'whole_image_mean_b_after_wb': 10.5,
            'wb_a_adjustment_post_clip': -3.5,
            'wb_b_adjustment_post_clip': 0.7,
            'redness_branch': 'within_cheek_spread',
            'redness_cheek_side': 'right',
            'redness_cheek_roi_pixels': 2833,
            'redness_cheek_mean_a_after_wb': 26.9,
            'redness_cheek_mean_b_after_wb': 8.18,
            'redness_cheek_p10_a_after_wb': 22.4,
            'redness_cheek_p95_a_after_wb': 37.65,
            'redness_cheek_p10_a_before_wb': 20.9,
            'redness_cheek_p95_a_before_wb': 34.15,
            'redness_baseline_cheek_p95_a': null,
          },
        },
      );

      final csv = AiScanDataCsvExporter.format(
        [scan],
        registryBaselineScanIds: const {},
      );
      final header = csv.split('\r\n').first.split(',');
      for (final column in AiScanDataCsvExporter.colorDiagnosticColumns) {
        expect(
          header.where((c) => c == column),
          hasLength(1),
          reason: '$column must appear exactly once',
        );
      }
      final row = _parse(csv).single;

      expect(row['image_quality.whole_image_mean_a_before_wb'], '9.5');
      expect(row['image_quality.whole_image_mean_b_before_wb'], '11.25');
      expect(row['image_quality.whole_image_mean_a_after_wb'], '12.75');
      expect(row['image_quality.whole_image_mean_b_after_wb'], '10.5');
      expect(row['image_quality.redness_branch'], 'within_cheek_spread');
      expect(row['image_quality.redness_cheek_side'], 'right');
      expect(row['image_quality.redness_cheek_roi_pixels'], '2833');
      expect(row['image_quality.redness_cheek_mean_a_after_wb'], '26.9');
      expect(row['image_quality.redness_cheek_mean_b_after_wb'], '8.18');
      expect(row['image_quality.redness_cheek_p10_a_after_wb'], '22.4');
      expect(row['image_quality.redness_cheek_p95_a_after_wb'], '37.65');
      expect(row['image_quality.redness_cheek_p10_a_before_wb'], '20.9');
      expect(row['image_quality.redness_cheek_p95_a_before_wb'], '34.15');
      expect(row['image_quality.redness_baseline_cheek_p95_a'], isEmpty);
      // Post-clip adjustments are new columns; the existing
      // white_balance_profile columns are still exported unchanged.
      expect(row['image_quality.wb_a_adjustment_post_clip'], '-3.5');
      expect(row['image_quality.wb_b_adjustment_post_clip'], '0.7');
      expect(row['image_quality.white_balance_profile.a_adjustment'], '-3.5');
      expect(row['image_quality.white_balance_profile.b_adjustment'], '0.7');
    });

    test('exports three frame-local response and EXIF column groups', () {
      final scan = _aiScan(
        'scan-frames',
        rawPayload: const <String, dynamic>{
          'metric_matrix': <String, dynamic>{'localized_redness': 30.0},
          'per_frame_diagnostics': <Map<String, dynamic>>[
            <String, dynamic>{
              'frame_number': 1,
              'cheek_side': 'left',
              'mask_pixel_count': 2100,
              'cheek_p95_a_after_wb': 31.5,
              'cheek_p10_a_after_wb': 20.5,
              'cheek_p10_a_before_wb': 19.5,
              'localized_redness': 20.0,
              'iso': 100,
              'exposure_bias': -0.3,
              'shutter_seconds': 0.008333333333333333,
              'brightness_value': 4.5,
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
            <String, dynamic>{
              'frame_number': 2,
              'cheek_side': null,
              'mask_pixel_count': null,
              'cheek_p95_a_after_wb': null,
              'cheek_p10_a_after_wb': null,
              'cheek_p10_a_before_wb': null,
              'localized_redness': null,
              'iso': 125,
              'exposure_bias': null,
              'shutter_seconds': null,
              'brightness_value': null,
            },
          ],
        },
      );

      final csv = AiScanDataCsvExporter.format(
        [scan],
        registryBaselineScanIds: const {},
      );
      final header = csv.split('\r\n').first.split(',');
      final row = _parse(csv).single;

      for (var frame = 1; frame <= 3; frame++) {
        for (final field in AiScanDataCsvExporter.perFrameFields) {
          expect(header, contains('frame${frame}_$field'));
        }
      }
      expect(row['frame1_cheek_side'], 'left');
      expect(row['frame1_cheek_p10_a_after_wb'], '20.5');
      expect(row['frame1_shutter_seconds'], '0.008333333333333333');
      expect(row['frame1_face_skin_pixels'], '18000');
      expect(row['frame1_pore_roi_pixels'], '6200');
      expect(row['frame1_u_zone_pixels'], '9500');
      expect(row['frame1_localized_redness_mask_kind'], 'cheek_primary');
      expect(row['frame1_pore_visibility_mask_kind'], 'tzone_pore');
      expect(
        row['frame1_diffuse_flushing_erythema_mask_pixels'],
        '10200',
      );
      expect(row['frame2_localized_redness'], isEmpty);
      expect(row['frame2_brightness_value'], isEmpty);
      expect(row['frame3_iso'], isEmpty);
    });

    test('old scans leave only the new color columns and comparison id empty', () {
      final oldScan = _aiScan(
        'scan-old',
        rawPayload: const <String, dynamic>{
          'metric_matrix': <String, dynamic>{'localized_redness': 5.3},
          'image_quality': <String, dynamic>{'chroma_cast': 7.31},
        },
      );

      final row = _parse(
        AiScanDataCsvExporter.format(
          [oldScan],
          registryBaselineScanIds: const {'scan-old'},
        ),
      ).single;

      for (final column in AiScanDataCsvExporter.colorDiagnosticColumns) {
        expect(row[column], isEmpty, reason: column);
      }
      expect(row['comparison_baseline_scan_id'], isEmpty);
      expect(row['comparison_baseline_source'], isEmpty);
      expect(row['is_baseline'], 'true');
      expect(row['image_quality.chroma_cast'], '7.31');
      expect(row['localized_redness_value'], '5.3');
    });

    test('is_baseline comes from the AI baseline registry, not isBaseline', () {
      final procedureBaseline = _aiScan('scan-procedure', isBaseline: true);
      final registryBaseline = _aiScan('scan-registry');
      final neither = _aiScan('scan-neither');

      final rows = _parse(
        AiScanDataCsvExporter.format(
          [procedureBaseline, registryBaseline, neither],
          registryBaselineScanIds: const {'scan-registry', 'scan-deleted'},
        ),
      );
      final byId = {for (final row in rows) row['scan_id']: row};

      expect(byId['scan-procedure']!['is_baseline'], 'false');
      expect(byId['scan-registry']!['is_baseline'], 'true');
      expect(byId['scan-neither']!['is_baseline'], 'false');
    });

    test('comparison_baseline_scan_id reads only the newly saved field', () {
      final legacy = _aiScan(
        'scan-legacy',
        parentBaselineId: 'procedure-parent',
        rawPayload: const <String, dynamic>{
          'metric_matrix': <String, dynamic>{'rosacea_severity': 3.0},
          'comparison_baseline_scan_id': 'legacy-key',
          'baseline_scan_id': 'legacy-key-2',
        },
      );
      final recorded = _aiScan(
        'scan-recorded',
        parentBaselineId: 'procedure-parent',
        rawPayload: <String, dynamic>{
          'metric_matrix': <String, dynamic>{'rosacea_severity': 3.0},
          aiComparisonBaselineScanIdKey: 'scan-front-baseline',
          aiComparisonBaselineSourceKey: aiComparisonBaselineSourceRegistry,
        },
      );

      final rows = _parse(
        AiScanDataCsvExporter.format(
          [legacy, recorded],
          registryBaselineScanIds: const {},
        ),
      );
      final byId = {for (final row in rows) row['scan_id']: row};

      expect(byId['scan-legacy']!['comparison_baseline_scan_id'], isEmpty);
      expect(
        byId['scan-recorded']!['comparison_baseline_scan_id'],
        'scan-front-baseline',
      );
      expect(byId['scan-recorded']!['comparison_baseline_source'], 'registry');
    });
  });

  group('recordAiComparisonBaseline', () {
    test('baseline equal to the registry pin is recorded as registry', () {
      final payload = <String, dynamic>{};
      recordAiComparisonBaseline(
        payload,
        baselineScanId: 'scan-a',
        registryScanId: 'scan-a',
      );
      expect(payload[aiComparisonBaselineScanIdKey], 'scan-a');
      expect(
        payload[aiComparisonBaselineSourceKey],
        aiComparisonBaselineSourceRegistry,
      );
    });

    test('baseline that is not the pin is recorded as earliest eligible', () {
      final payload = <String, dynamic>{};
      recordAiComparisonBaseline(
        payload,
        baselineScanId: 'scan-b',
        registryScanId: 'scan-ignored-pin',
      );
      expect(payload[aiComparisonBaselineScanIdKey], 'scan-b');
      expect(
        payload[aiComparisonBaselineSourceKey],
        aiComparisonBaselineSourceEarliestEligible,
      );
    });

    test('no comparison records explicit nulls', () {
      final payload = <String, dynamic>{};
      recordAiComparisonBaseline(
        payload,
        baselineScanId: null,
        registryScanId: 'scan-a',
      );
      expect(payload.containsKey(aiComparisonBaselineScanIdKey), isTrue);
      expect(payload[aiComparisonBaselineScanIdKey], isNull);
      expect(payload[aiComparisonBaselineSourceKey], isNull);
    });
  });
}
