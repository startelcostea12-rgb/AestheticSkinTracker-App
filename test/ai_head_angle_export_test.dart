import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_head_angle.dart';
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

ScanHistoryEntry _scan(String id, {Map<String, dynamic>? rawPayload}) {
  return ScanHistoryEntry(
    id: id,
    timestamp: DateTime.parse('2026-09-25T06:13:00'),
    scanType: ScanHistoryEntry.scanTypeAiAnalysis,
    estimatedSkinAge: 0,
    metrics: const <String, double>{},
    rawPayload:
        rawPayload ??
        const <String, dynamic>{
          'metric_matrix': <String, dynamic>{'rosacea_severity': 3.0},
        },
  );
}

void main() {
  test('recordAiHeadAngle stores finite yaw/pitch/roll only', () {
    final payload = <String, dynamic>{};
    recordAiHeadAngle(payload, yaw: 1.5, pitch: -2.25, roll: 0.5);
    expect(payload[aiHeadYawKey], 1.5);
    expect(payload[aiHeadPitchKey], -2.25);
    expect(payload[aiHeadRollKey], 0.5);

    final ignored = <String, dynamic>{};
    recordAiHeadAngle(
      ignored,
      yaw: double.nan,
      pitch: double.infinity,
      roll: null,
    );
    expect(ignored, isEmpty);
  });

  test('CSV exports head angles and leaves older scans blank', () {
    final withAngles = _scan(
      'angled',
      rawPayload: {
        'metric_matrix': <String, dynamic>{'rosacea_severity': 3.0},
        aiHeadYawKey: 3.5,
        aiHeadPitchKey: -1.25,
        aiHeadRollKey: 0.75,
        'image_quality': <String, dynamic>{
          'head_pose_pitch': 4.5,
          'head_pose_yaw': -2.0,
        },
      },
    );
    final legacy = _scan('legacy');
    final csv = AiScanDataCsvExporter.format(
      [withAngles, legacy],
      registryBaselineScanIds: const {},
    );
    final header = csv.split('\r\n').first.split(',');
    expect(header, containsAll(['head_yaw', 'head_pitch', 'head_roll']));
    final byId = {for (final row in _parse(csv)) row['scan_id']: row};
    expect(byId['angled']!['head_yaw'], '3.5');
    expect(byId['angled']!['head_pitch'], '-1.25');
    expect(byId['angled']!['head_roll'], '0.75');
    expect(byId['angled']!['image_quality.head_pose_pitch'], '4.5');
    expect(byId['angled']!['image_quality.head_pose_yaw'], '-2.0');
    expect(byId['legacy']!['head_yaw'], isEmpty);
    expect(byId['legacy']!['head_pitch'], isEmpty);
    expect(byId['legacy']!['head_roll'], isEmpty);
  });
}
