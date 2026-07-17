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
  });
}
