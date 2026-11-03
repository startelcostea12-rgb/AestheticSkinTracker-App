import 'dart:convert';
import 'dart:io';

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
    final currentDocuments = await Directory.systemTemp.createTemp('scan-photo-documents-');
    addTearDown(() => currentDocuments.delete(recursive: true));
    final photo = File('${currentDocuments.path}/scan_123.jpg');
    await photo.writeAsBytes([1, 2, 3]);
    documents = currentDocuments.path;
    await initializeScanPhotoPaths();
    final loaded = (await AppPrefs.getScanEntries()).single;
    expect(loaded.imagePath, photo.path);
    expect(loaded.id, 'legacy-id');
  });

  test('load finds an old absolute filename in Documents/scans without rewriting storage', () async {
    final currentDocuments = await Directory.systemTemp.createTemp('scan-photo-documents-');
    addTearDown(() => currentDocuments.delete(recursive: true));
    final scans = await Directory('${currentDocuments.path}/scans').create();
    final photo = File('${scans.path}/old-photo.jpg');
    await photo.writeAsBytes([1, 2, 3]);
    const oldPath = '/var/mobile/Containers/Data/Application/OLD/Documents/moved/old-photo.jpg';
    final scan = ScanHistoryEntry(
      id: 'old-photo-scan',
      timestamp: DateTime.utc(2026, 10, 27),
      imagePath: oldPath,
      estimatedSkinAge: 0,
      metrics: const {'texture_smoothness': 55.0},
    );
    final originalStorage = jsonEncode([scan.toJson()]);
    SharedPreferences.setMockInitialValues({AppPrefs.scanHistoryKey: originalStorage});
    documents = currentDocuments.path;
    await initializeScanPhotoPaths();
    final loaded = (await AppPrefs.getScanEntriesWithoutNormalization()).single;
    expect(loaded.imagePath, photo.path);
    expect(loaded.id, scan.id);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppPrefs.scanHistoryKey), originalStorage);
    expect(await photo.exists(), isTrue);
  });

  test('an existing absolute file is preserved even with a Documents match', () async {
    final root = await Directory.systemTemp.createTemp('scan-photo-existing-');
    addTearDown(() => root.delete(recursive: true));
    final oldDocuments = await Directory(
      '${root.path}/Containers/Data/Application/OLD/Documents',
    ).create(recursive: true);
    final currentDocuments = await Directory('${root.path}/current/Documents').create(recursive: true);
    final original = File('${oldDocuments.path}/same-name.jpg');
    final candidate = File('${currentDocuments.path}/same-name.jpg');
    await original.writeAsBytes([1]);
    await candidate.writeAsBytes([2]);
    expect(await loadScanPhotoPath(original.path, currentDocuments.path), original.path);
    expect(await original.readAsBytes(), [1]);
    expect(await candidate.readAsBytes(), [2]);
  });

  test('a missing photo stays missing and does not delete another photo', () async {
    final currentDocuments = await Directory.systemTemp.createTemp('scan-photo-missing-');
    addTearDown(() => currentDocuments.delete(recursive: true));
    final unrelated = File('${currentDocuments.path}/other.jpg');
    await unrelated.writeAsBytes([1]);
    const missing = '/var/mobile/Containers/Data/Application/OLD/Documents/missing.jpg';
    expect(await loadScanPhotoPath(missing, currentDocuments.path), missing);
    expect(await File(missing).exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
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
