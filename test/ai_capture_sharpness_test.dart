import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_capture_sharpness.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

ScanHistoryEntry _savedScan(Map<String, dynamic> payload) =>
    ScanHistoryEntry.fromJson(
      ScanHistoryEntry(
        id: 'sharpness-scan',
        timestamp: DateTime.utc(2026, 10, 10, 9),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        captureQuality: 'normal',
        rawPayload: payload,
      ).toJson(),
    );

Map<String, String> _exportRow(ScanHistoryEntry scan) {
  final rows = AiScanDataCsvExporter.format([
    scan,
  ], registryBaselineScanIds: const {}).split('\r\n');
  final header = rows.first.split(',');
  final values = rows[1].split(',');
  return {for (var i = 0; i < header.length; i++) header[i]: values[i]};
}

void main() {
  test('capture sharpness round-trips onto the saved scan and the export', () {
    final payload = <String, dynamic>{
      'metric_matrix': <String, dynamic>{'texture_smoothness': 57.2},
    };
    recordAiCaptureSharpness(
      payload,
      cropSharpness: 412.37,
      fullStillSharpness: 21.5,
      sharpnessFloor: 36.0,
    );

    final saved = _savedScan(payload);
    expect(saved.rawPayload![aiCaptureCropSharpnessKey], 412.37);
    expect(saved.rawPayload![aiCaptureFullStillSharpnessKey], 21.5);
    expect(saved.rawPayload![aiCaptureSharpnessFloorKey], 36.0);

    final row = _exportRow(saved);
    expect(row['crop_sharpness'], '412.37');
    expect(row['full_still_sharpness'], '21.5');
    expect(row['sharpness_floor'], '36.0');
    expect(row['captureQuality'], 'normal');
  });

  test('older scans without the fields export empty cells', () {
    final row = _exportRow(
      _savedScan(<String, dynamic>{
        'metric_matrix': <String, dynamic>{'texture_smoothness': 57.2},
      }),
    );
    expect(row['crop_sharpness'], isEmpty);
    expect(row['full_still_sharpness'], isEmpty);
    expect(row['sharpness_floor'], isEmpty);
  });

  test('the capture result carries the three values', () {
    final result = AiSkinAnalysisCaptureResult(
      primaryImagePath: 'frame_1.jpg',
      croppedFrames: [Uint8List(0)],
      captureQuality: 'normal',
      poseTemplate: 'Front',
      guideType: 'facial',
      cropSharpness: 412.37,
      fullStillSharpness: 21.5,
      sharpnessFloor: 36.0,
    );
    expect(result.cropSharpness, 412.37);
    expect(result.fullStillSharpness, 21.5);
    expect(result.sharpnessFloor, 36.0);
  });

  test('camera passes, and the screen saves, the tag-deciding values', () {
    final camera = File(
      'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
    ).readAsStringSync();
    expect(camera, contains('cropSharpness: qualityTag.cropSharpness'));
    expect(
      camera,
      contains('fullStillSharpness: qualityTag.fullStillSharpness'),
    );
    expect(camera, contains('sharpnessFloor: _sharpnessVarianceFloor'));
    // The existing burst debug log line is still written.
    expect(camera, contains('full_still_sharpness='));

    final screen = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    expect(
      screen,
      contains('recordAiCaptureSharpness(\n        persistencePayload,'),
    );
  });
}
