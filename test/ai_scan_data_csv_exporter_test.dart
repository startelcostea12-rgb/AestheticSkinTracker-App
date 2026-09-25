import 'package:flutter_test/flutter_test.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';

void main() {
  group('AiScanDataCsvExporter', () {
    test('missing stored values remain empty CSV cells', () {
      final scan = ScanHistoryEntry(
        id: 'scan-1',
        timestamp: DateTime.parse('2026-09-25T06:13:00'),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
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

      final rows = AiScanDataCsvExporter.format([scan]).split('\r\n');
      final columns = rows.first.split(',');
      final values = rows[1].split(',');

      expect(values[columns.indexOf('guideType')], isEmpty);
      expect(values[columns.indexOf('image_quality.lighting_mean_l')], isEmpty);
      expect(values[columns.indexOf('rosacea_severity_trend_status')], isEmpty);
      expect(values[columns.indexOf('comparison_baseline_scan_id')], isEmpty);
      expect(
        values[columns.indexOf('image_quality.white_balance_profile.reason')],
        'disabled',
      );
      expect(values[columns.indexOf('rosacea_severity_value')], '3.0');
    });

    test('AI scan with no backend rawPayload is skipped', () {
      final scan = ScanHistoryEntry(
        id: 'scan-without-payload',
        timestamp: DateTime.parse('2026-09-25T06:00:00'),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{'localized_redness': 12},
      );

      final rows = AiScanDataCsvExporter.format([scan]).split('\r\n');

      expect(rows, hasLength(1));
      expect(rows.single, contains('scan_id'));
      expect(AiScanDataCsvExporter.exportableScans([scan]), isEmpty);
    });
  });
}
