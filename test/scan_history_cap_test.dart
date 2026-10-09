import 'dart:convert';

import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final DateTime _start = DateTime.utc(2026, 1, 1);

ScanHistoryEntry _aiScan(int index, {bool isBaseline = false}) =>
    ScanHistoryEntry(
      id: 'scan_${index.toString().padLeft(3, '0')}',
      timestamp: _start.add(Duration(minutes: index)),
      scanType: ScanHistoryEntry.scanTypeAiAnalysis,
      estimatedSkinAge: 0,
      metrics: const <String, double>{'texture_smoothness': 57.0},
      isBaseline: isBaseline,
    );

/// Seeds scans 0..count-1 (scan_000 is the oldest) directly into storage.
void _seed(int count, {Set<int> flaggedBaselines = const <int>{}}) {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AppPrefs.scanHistoryKey: jsonEncode([
      for (var i = 0; i < count; i++)
        _aiScan(i, isBaseline: flaggedBaselines.contains(i)).toJson(),
    ]),
  });
}

const AiBaselineKey _frontKey = (
  procedureId: null,
  focusArea: 'full_face',
  poseTemplate: 'front',
  guideType: 'facial',
);

const AiBaselineKey _leftKey = (
  procedureId: null,
  focusArea: 'full_face',
  poseTemplate: 'left_profile',
  guideType: 'facial',
);

Set<String> _ids(List<ScanHistoryEntry> history) =>
    history.map((scan) => scan.id).toSet();

void main() {
  test('the cap is 200 scans', () {
    expect(AppPrefs.maxStoredScans, 200);
  });

  test('scan 201 drops the oldest unpinned scan', () async {
    _seed(200);
    final history = await AppPrefs.addScanEntry(_aiScan(200));

    expect(history, hasLength(200));
    final ids = _ids(history);
    expect(ids, isNot(contains('scan_000')));
    expect(ids, contains('scan_001'));
    expect(ids, contains('scan_200'));
    expect(_ids(await AppPrefs.getScanEntries()), ids);
  });

  test('200 stored scans are left as they are', () async {
    _seed(200);
    final history = await AppPrefs.getScanEntries();
    expect(history, hasLength(200));
    expect(_ids(history), contains('scan_000'));
  });

  test('a pinned baseline older than the cap is not dropped', () async {
    _seed(200);
    await AppPrefs.setAiBaselineScanId(_leftKey, 'scan_000');

    final history = await AppPrefs.addScanEntry(_aiScan(200));
    final ids = _ids(history);

    expect(ids, contains('scan_000'));
    // The oldest UNPINNED scan goes instead.
    expect(ids, isNot(contains('scan_001')));
    expect(ids, contains('scan_200'));
    expect(history, hasLength(200));
  });

  test('the current Front baseline id is not dropped', () async {
    _seed(200);
    await AppPrefs.setAiBaselineScanId(_frontKey, 'scan_000');

    // Several more scans than the cap allows past the baseline.
    var history = <ScanHistoryEntry>[];
    for (var i = 200; i < 205; i++) {
      history = await AppPrefs.addScanEntry(_aiScan(i));
    }

    expect(_ids(history), contains('scan_000'));
    expect(_ids(await AppPrefs.getScanEntries()), contains('scan_000'));
    expect(await AppPrefs.getAllAiBaselineScanIds(), contains('scan_000'));
  });

  test('a scan flagged isBaseline is not dropped', () async {
    _seed(200, flaggedBaselines: {0});

    final history = await AppPrefs.addScanEntry(_aiScan(200));
    final ids = _ids(history);

    expect(ids, contains('scan_000'));
    expect(ids, isNot(contains('scan_001')));
    expect(
      history.firstWhere((scan) => scan.id == 'scan_000').isBaseline,
      isTrue,
    );
  });
}
