import 'package:flutter_test/flutter_test.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';

void main() {
  group('ScanHistoryEntry', () {
    test('fromJson/toJson round-trip', () {
      final entry = ScanHistoryEntry(
        id: 'test_id_1',
        timestamp: DateTime.parse('2024-01-01T12:00:00Z'),
        procedureId: 'p1',
        imagePath: 'img.png',
        focusArea: 'Buttocks',
        customDescription: 'hips and lower glute transition',
        metrics: {'redness': 2.0, 'texture': 3.0, 'wrinkle': 1.0, 'pore': 4.0},
        estimatedSkinAge: 30.5,
      );
      final json = entry.toJson();
      expect(json['focusArea'], 'Buttocks');
      expect(json['customDescription'], 'hips and lower glute transition');
      final roundTrip = ScanHistoryEntry.fromJson(json);
      expect(roundTrip.isEquivalentTo(entry), true);
      expect(roundTrip.focusArea, 'Buttocks');
      expect(roundTrip.customDescription, 'hips and lower glute transition');
    });

    test('source image dimensions round-trip through JSON', () {
      final entry = ScanHistoryEntry(
        id: 'source_dimensions',
        timestamp: DateTime.parse('2026-09-08T12:00:00Z'),
        estimatedSkinAge: 30,
        metrics: const {'localized_redness': 20},
        sourceImageWidth: 1600,
        sourceImageHeight: 1200,
      );

      final roundTrip = ScanHistoryEntry.fromJson(entry.toJson());
      expect(roundTrip.sourceImageWidth, 1600);
      expect(roundTrip.sourceImageHeight, 1200);
    });

    test('Add scan increases history length', () {
      final history = <ScanHistoryEntry>[];
      final entry = ScanHistoryEntry(
        id: 'test_id_2',
        timestamp: DateTime.now(),
        procedureId: 'p2',
        imagePath: 'img2.png',
        metrics: {'redness': 1.0, 'texture': 2.0, 'wrinkle': 3.0, 'pore': 4.0},
        estimatedSkinAge: 28.0,
      );
      history.add(entry);
      expect(history.length, 1);
    });

    test('Get latest scan returns correct entry', () {
      final entry1 = ScanHistoryEntry(
        id: 'test_id_3',
        timestamp: DateTime.parse('2024-01-01T12:00:00Z'),
        procedureId: 'p1',
        imagePath: 'img1.png',
        metrics: {'redness': 2.0, 'texture': 3.0, 'wrinkle': 1.0, 'pore': 4.0},
        estimatedSkinAge: 30.5,
      );
      final entry2 = ScanHistoryEntry(
        id: 'test_id_4',
        timestamp: DateTime.parse('2024-02-01T12:00:00Z'),
        procedureId: 'p2',
        imagePath: 'img2.png',
        metrics: {'redness': 1.0, 'texture': 2.0, 'wrinkle': 3.0, 'pore': 4.0},
        estimatedSkinAge: 28.0,
      );
      final history = [entry1, entry2];
      final latest = history.reduce(
        (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
      );
      expect(latest, entry2);
    });

    test('bodyReferenceGeometry round-trips through JSON', () {
      final geometry = {
        'shoulderMidX': 0.51,
        'shoulderMidY': 0.34,
        'hipMidX': 0.53,
        'hipMidY': 0.68,
        'shoulderWidthNorm': 0.28,
        'hipWidthNorm': 0.24,
        'shoulderToHipRatio': 1.17,
        'roiX0Norm': 0.14,
        'roiX1Norm': 0.82,
        'roiY0Norm': 0.22,
        'roiY1Norm': 0.91,
      };
      final entry = ScanHistoryEntry(
        id: 'body_ref_geo',
        timestamp: DateTime.parse('2024-05-01T12:00:00Z'),
        procedureId: 'body_proc',
        imagePath: 'body_reference.png',
        metrics: {'redness': 2.0},
        estimatedSkinAge: 29.0,
        bodyReferenceGeometry: geometry,
      );

      final json = entry.toJson();
      expect(json['bodyReferenceGeometry'], geometry);

      final roundTrip = ScanHistoryEntry.fromJson(json);
      expect(roundTrip.bodyReferenceGeometry, geometry);
      expect(roundTrip.isEquivalentTo(entry), true);
    });
  });

  group('ScanHistoryEntry.scanEngine', () {
    test('defaults to unknown when not specified', () {
      final entry = ScanHistoryEntry(
        id: 'no_engine',
        timestamp: DateTime.now(),
        estimatedSkinAge: 0,
        metrics: const {},
      );
      expect(entry.scanEngine, ScanHistoryEntry.engineUnknown);
    });

    test('fromJson defaults legacy scans (no scanEngine key) to unknown '
        'without crashing', () {
      final legacyJson = {
        'id': 'legacy_scan',
        'timestamp': '2023-05-01T09:00:00Z',
        'estimatedSkinAge': 25.0,
        'metrics': {'redness': 3.0},
        // No 'scanEngine' key at all, as pre-existing scans would have.
      };
      final entry = ScanHistoryEntry.fromJson(legacyJson);
      expect(entry.scanEngine, ScanHistoryEntry.engineUnknown);
    });

    test('fromJson/toJson round-trips a known engine tag', () {
      final entry = ScanHistoryEntry(
        id: 'tflite_scan',
        timestamp: DateTime.parse('2024-01-01T12:00:00Z'),
        estimatedSkinAge: 30.0,
        metrics: const {'redness': 2.0},
        scanEngine: ScanHistoryEntry.engineLocalTflite,
      );
      final json = entry.toJson();
      expect(json['scanEngine'], ScanHistoryEntry.engineLocalTflite);
      final roundTrip = ScanHistoryEntry.fromJson(json);
      expect(roundTrip.scanEngine, ScanHistoryEntry.engineLocalTflite);
      expect(roundTrip.isEquivalentTo(entry), true);
    });

    test('resolveScanEngine reads modelUsed from a raw payload', () {
      expect(
        ScanHistoryEntry.resolveScanEngine({
          'modelUsed': 'yolo+mediapipe+opencv-deterministic-v2',
        }),
        'yolo+mediapipe+opencv-deterministic-v2',
      );
      expect(
        ScanHistoryEntry.resolveScanEngine({'model_used': 'local-tflite'}),
        'local-tflite',
      );
    });

    test('resolveScanEngine falls back when payload has no engine tag', () {
      expect(
        ScanHistoryEntry.resolveScanEngine(
          {'status': 'success'},
          fallback: ScanHistoryEntry.engineBackendOpencv,
        ),
        ScanHistoryEntry.engineBackendOpencv,
      );
      expect(
        ScanHistoryEntry.resolveScanEngine(null),
        ScanHistoryEntry.engineUnknown,
      );
      expect(
        ScanHistoryEntry.resolveScanEngine({'modelUsed': '  '}),
        ScanHistoryEntry.engineUnknown,
      );
    });

    test('scanEnginesComparable is true only for matching known engines', () {
      expect(
        ScanHistoryEntry.scanEnginesComparable(
          ScanHistoryEntry.engineLocalTflite,
          ScanHistoryEntry.engineLocalTflite,
        ),
        true,
      );
      expect(
        ScanHistoryEntry.scanEnginesComparable(
          ScanHistoryEntry.engineBackendOpencv,
          ScanHistoryEntry.engineBackendOpencv,
        ),
        true,
      );
    });

    test('scanEnginesComparable is false across different engines', () {
      expect(
        ScanHistoryEntry.scanEnginesComparable(
          ScanHistoryEntry.engineLocalTflite,
          ScanHistoryEntry.engineBackendOpencv,
        ),
        false,
      );
    });

    test('scanEnginesComparable is false whenever either side is unknown '
        '(legacy scans never silently compare as engine-matched)', () {
      expect(
        ScanHistoryEntry.scanEnginesComparable(
          ScanHistoryEntry.engineUnknown,
          ScanHistoryEntry.engineLocalTflite,
        ),
        false,
      );
      expect(
        ScanHistoryEntry.scanEnginesComparable(
          ScanHistoryEntry.engineLocalTflite,
          ScanHistoryEntry.engineUnknown,
        ),
        false,
      );
      expect(
        ScanHistoryEntry.scanEnginesComparable(
          ScanHistoryEntry.engineUnknown,
          ScanHistoryEntry.engineUnknown,
        ),
        false,
      );
    });
  });
}
