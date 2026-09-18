import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aesthetic_skin_tracker/features/procedures/presentation/procedure_profiles_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/capture_consistency.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';

Map<String, dynamic> _oldScanJson({
  String id = 'legacy_scan_2024',
  String? captureQuality,
}) {
  return <String, dynamic>{
    'id': id,
    'timestamp': '2024-01-15T12:00:00.000Z',
    'imagePath': 'legacy_photo.jpg',
    'procedureId': 'legacy_proc',
    'estimatedSkinAge': 31.0,
    'metrics': <String, dynamic>{
      'redness': 2.0,
      'texture': 3.0,
      'wrinkle': 1.0,
      'pore': 4.0,
    },
    if (captureQuality != null) 'captureQuality': captureQuality,
  };
}

void main() {
  group('legacy scan compatibility', () {
    test('old absent-key scan deserializes with new fields absent', () {
      final legacyJson = _oldScanJson();

      for (final key in <String>[
        'faceReferenceGeometry',
        'face_reference_geometry',
        'bodyReferenceGeometry',
        'body_reference_geometry',
        'capture_reference_alignment_score',
        'zone_analysis',
        'sourceImageWidth',
        'sourceImageHeight',
        'source_image_width',
        'source_image_height',
        'trend_lock_reason',
        'trend_lock_reasons',
        'metric_ranges',
        'metric_frame_values',
        'multi_frame_analysis',
      ]) {
        expect(legacyJson.containsKey(key), isFalse, reason: key);
      }

      final entry = ScanHistoryEntry.fromJson(legacyJson);

      expect(entry.id, 'legacy_scan_2024');
      expect(entry.faceReferenceGeometry, isNull);
      expect(entry.bodyReferenceGeometry, isNull);
      expect(entry.sourceImageWidth, isNull);
      expect(entry.sourceImageHeight, isNull);
      expect(entry.captureQuality, isNull);
      expect(entry.metrics['capture_reference_alignment_score'], isNull);
      expect(entry.rawPayload, isNotNull);
      expect(entry.rawPayload!.containsKey('zone_analysis'), isFalse);
      expect(entry.rawPayload!.containsKey('multi_frame_analysis'), isFalse);
      expect(entry.toJson()['faceReferenceGeometry'], isNull);
      expect(entry.toJson()['bodyReferenceGeometry'], isNull);
    });

    test('new comparison helpers degrade gracefully for two legacy scans', () {
      final baseline = ScanHistoryEntry.fromJson(
        _oldScanJson(id: 'legacy_baseline'),
      );
      final latest = ScanHistoryEntry.fromJson(_oldScanJson(id: 'legacy_latest'));

      final eligibility = procedurePhotoComparisonEligibility(
        isBodyProcedure: false,
        baseline: baseline,
        latest: latest,
      );
      expect(eligibility.isComparable, isFalse);
      expect(eligibility.caveat, contains('capture quality was not recorded'));

      final consistency = captureConsistencyForScanPair(
        isBodyProcedure: false,
        baseline: baseline,
        latest: latest,
      );
      expect(consistency.score, isNull);
      expect(consistency.checkCount, 0);
      expect(consistency.lowestCheck, isNull);
      expect(consistency.displayText, 'Capture consistency unavailable');

      final zones = gatedProcedureZoneComparisons(
        eligibility: eligibility,
        baselinePayload: baseline.rawPayload,
        latestPayload: latest.rawPayload,
      );
      expect(zones, isEmpty);
    });

    test('legacy baseline compared with newer scan does not crash', () {
      final legacy = ScanHistoryEntry.fromJson(_oldScanJson(id: 'legacy'));
      final newer = ScanHistoryEntry(
        id: 'newer',
        timestamp: DateTime.parse('2026-09-17T12:00:00Z'),
        estimatedSkinAge: 30,
        metrics: const <String, double>{
          'localized_redness': 22,
          'capture_reference_alignment_score': 91,
        },
        captureQuality: 'normal',
        sourceImageWidth: 1600,
        sourceImageHeight: 1200,
        rawPayload: const <String, dynamic>{
          'metric_extraction_paths': <String, dynamic>{
            'localized_redness': 'cheek_primary',
          },
          'zone_analysis': <String, dynamic>{},
          'multi_frame_analysis': <String, dynamic>{
            'requested_frames': 3,
            'metric_frame_values': <String, dynamic>{
              'localized_redness': <double>[21, 22, 23],
            },
            'metric_ranges': <String, dynamic>{
              'localized_redness': <String, dynamic>{
                'min': 21,
                'max': 23,
                'count': 3,
              },
            },
          },
        },
      );

      final eligibility = procedurePhotoComparisonEligibility(
        isBodyProcedure: false,
        baseline: legacy,
        latest: newer,
      );
      expect(eligibility.isComparable, isFalse);
      expect(eligibility.caveat, isNotNull);

      final consistency = captureConsistencyForScanPair(
        isBodyProcedure: false,
        baseline: legacy,
        latest: newer,
      );
      expect(consistency.score, 91);
      expect(consistency.checkCount, 1);
      expect(consistency.displayText, isNot(contains('mainly due to')));

      expect(
        gatedProcedureZoneComparisons(
          eligibility: eligibility,
          baselinePayload: legacy.rawPayload,
          latestPayload: newer.rawPayload,
        ),
        isEmpty,
      );
    });

    testWidgets('legacy payload renders shared report without new metadata', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LuxeReportLayout(
              rawPayload: <String, dynamic>{
                'initial_baseline': true,
                'metric_matrix': <String, dynamic>{
                  'localized_redness': 20.0,
                  'texture_smoothness': 65.0,
                },
                'metrics': <String, dynamic>{
                  'localized_redness': 20.0,
                  'texture_smoothness': 65.0,
                },
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Baseline scan captured'), findsOneWidget);
      expect(find.textContaining('Capture consistency'), findsNothing);
      expect(find.textContaining('frames'), findsNothing);
      expect(find.textContaining('mainly due to'), findsNothing);
    });
  });
}
