import 'dart:convert';

import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/scan_photo_paths.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  var documents = '/var/mobile/Containers/Data/Application/OLD/Documents';

  setUp(() async {
    documents = '/var/mobile/Containers/Data/Application/OLD/Documents';
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents;
          }
          return null;
        });
    await initializeScanPhotoPaths();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'saves relative paths and loads against the current Documents',
    () async {
      final scan = ScanHistoryEntry(
        id: 'preserved-scan-id',
        timestamp: DateTime.utc(2026, 11, 3),
        imagePath: '$documents/scan_photos/face photo.jpg',
        estimatedSkinAge: 0,
        metrics: const {
          'calibrated_redness_score': 96.0,
          'calibrated_smoothness_score': 61.0,
          'pore_visibility': 12.0,
        },
      );
      await AppPrefs.addScanEntry(scan);
      final prefs = await SharedPreferences.getInstance();
      final stored =
          (jsonDecode(prefs.getString(AppPrefs.scanHistoryKey)!) as List).single
              as Map;
      expect(stored['imagePath'], 'scan_photos/face photo.jpg');
      expect(stored['id'], scan.id);

      documents = '/var/mobile/Containers/Data/Application/NEW/Documents';
      await initializeScanPhotoPaths();
      for (final loaded in [
        (await AppPrefs.getScanEntries()).single,
        (await AppPrefs.getScanEntriesWithoutNormalization()).single,
      ]) {
        expect(loaded.imagePath, '$documents/scan_photos/face photo.jpg');
        expect(loaded.id, scan.id);
        expect(loaded.metrics['calibrated_redness_score'], 96.0);
        expect(loaded.metrics['calibrated_smoothness_score'], 61.0);
        expect(loaded.metrics['pore_visibility'], 12.0);
      }
      expect(scan.imagePath, contains('/OLD/'));
    },
  );

  test('rebases legacy absolute iOS paths without changing scan IDs', () async {
    final scan = ScanHistoryEntry(
      id: 'legacy-id',
      timestamp: DateTime.utc(2026, 10, 27),
      imagePath: '$documents/scan_123.jpg',
      estimatedSkinAge: 0,
      metrics: const {'texture_smoothness': 55.0},
    );
    SharedPreferences.setMockInitialValues({
      AppPrefs.scanHistoryKey: jsonEncode([scan.toJson()]),
    });
    documents = '/var/mobile/Containers/Data/Application/NEW/Documents';
    await initializeScanPhotoPaths();
    final loaded = (await AppPrefs.getScanEntries()).single;
    expect(loaded.imagePath, '$documents/scan_123.jpg');
    expect(loaded.id, 'legacy-id');
  });

  test('keeps external, data, missing and unrelated absolute paths intact', () {
    for (final path in <String?>[
      null,
      '',
      'data:image/jpeg;base64,abc',
      'https://example.com/face.jpg',
      'blob:https://example.com/photo',
      '/tmp/face.jpg',
      '/external/Documents/face.jpg',
      '${documents}Elsewhere/face.jpg',
    ]) {
      expect(storedScanPhotoPath(path, documents), path);
      expect(resolvedScanPhotoPath(path, documents), path);
    }
    expect(
      resolvedScanPhotoPath('../outside.jpg', documents),
      '../outside.jpg',
    );
    expect(storedScanPhotoPath('scan.jpg', null), 'scan.jpg');
    expect(resolvedScanPhotoPath('scan.jpg', null), 'scan.jpg');
  });
}
