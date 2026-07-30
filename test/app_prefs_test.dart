import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'dart:convert';

void main() {
  group('AppPrefs', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('saveUserName and getUserName', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppPrefs.userNameKey, 'Alice');
      expect(prefs.getString(AppPrefs.userNameKey), 'Alice');
    });

    test('isOnboardingComplete true after save, false after clear', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppPrefs.onboardingCompleteKey, true);
      expect(await AppPrefs.isOnboardingComplete(), true);
      await prefs.setBool(AppPrefs.onboardingCompleteKey, false);
      expect(await AppPrefs.isOnboardingComplete(), false);
    });

    test('procedure_history: save/load JSON list', () async {
      final prefs = await SharedPreferences.getInstance();
      final history = [
        {
          'id': 'p1',
          'type': 'Laser',
          'startDate': DateTime(2024, 1, 1).toIso8601String(),
          'sessions': 3,
          'clinic': 'Skin Clinic',
          'notes': 'Initial session',
        },
        {
          'id': 'p2',
          'type': 'Peel',
          'startDate': DateTime(2024, 2, 1).toIso8601String(),
          'sessions': 2,
          'clinic': 'Beauty Spa',
          'notes': 'Follow-up',
        },
      ];
      await prefs.setString(AppPrefs.procedureHistoryKey, jsonEncode(history));
      final loaded = jsonDecode(prefs.getString(AppPrefs.procedureHistoryKey)!);
      expect(loaded.length, 2);
      expect(loaded[0]['id'], 'p1');
      expect(loaded[1]['type'], 'Peel');
    });

    test('set/getTrackedProcedure persists and clears', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppPrefs.trackedProcedureKey, 'Laser');
      expect(prefs.getString(AppPrefs.trackedProcedureKey), 'Laser');
      await prefs.remove(AppPrefs.trackedProcedureKey);
      expect(prefs.getString(AppPrefs.trackedProcedureKey), null);
    });

    test(
      'first procedure photo remains the only baseline across later uploads',
      () async {
        const procedureId = 'proc_baseline_test';

        await AppPrefs.addScanEntry(
          ScanHistoryEntry(
            id: 'scan_first',
            timestamp: DateTime.parse('2026-05-01T00:00:00.000Z'),
            procedureId: procedureId,
            imagePath: 'data:image/jpeg;base64,first',
            estimatedSkinAge: 30,
            metrics: const {'redness': 4.0},
          ),
        );
        await AppPrefs.addScanEntry(
          ScanHistoryEntry(
            id: 'scan_second',
            timestamp: DateTime.parse('2026-05-02T00:00:00.000Z'),
            procedureId: procedureId,
            imagePath: 'data:image/jpeg;base64,second',
            estimatedSkinAge: 30,
            metrics: const {'redness': 3.0},
          ),
        );
        await AppPrefs.addScanEntry(
          ScanHistoryEntry(
            id: 'scan_third',
            timestamp: DateTime.parse('2026-05-03T00:00:00.000Z'),
            procedureId: procedureId,
            imagePath: 'data:image/jpeg;base64,third',
            estimatedSkinAge: 30,
            metrics: const {'redness': 2.0},
          ),
        );

        final procedureScans = (await AppPrefs.getScanEntries())
            .where((entry) => entry.procedureId == procedureId)
            .toList();

        expect(procedureScans.length, 3);
        expect(procedureScans.where((entry) => entry.isBaseline).length, 1);
        expect(procedureScans.first.imagePath, 'data:image/jpeg;base64,third');
        expect(procedureScans.last.imagePath, 'data:image/jpeg;base64,first');
        expect(
          procedureScans.singleWhere((entry) => entry.isBaseline).imagePath,
          'data:image/jpeg;base64,first',
        );

        final comparison = await AppPrefs.getProcedurePhotoComparison(
          procedureId,
        );
        expect(comparison['baselineImagePath'], 'data:image/jpeg;base64,first');
        expect(comparison['latestImagePath'], 'data:image/jpeg;base64,third');
      },
    );

    test(
      'legacy procedure scans normalize baseline to absolute oldest scan',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          AppPrefs.scanHistoryKey,
          jsonEncode([
            ScanHistoryEntry(
              id: 'newest',
              timestamp: DateTime.parse('2026-05-03T00:00:00.000Z'),
              procedureId: 'proc_legacy',
              imagePath: 'third',
              estimatedSkinAge: 30,
              metrics: const {'redness': 3.0},
              isBaseline: true,
            ).toJson(),
            ScanHistoryEntry(
              id: 'middle',
              timestamp: DateTime.parse('2026-05-02T00:00:00.000Z'),
              procedureId: 'proc_legacy',
              imagePath: 'second',
              estimatedSkinAge: 31,
              metrics: const {'redness': 4.0},
            ).toJson(),
            ScanHistoryEntry(
              id: 'oldest',
              timestamp: DateTime.parse('2026-05-01T00:00:00.000Z'),
              procedureId: 'proc_legacy',
              imagePath: 'first',
              estimatedSkinAge: 32,
              metrics: const {'redness': 5.0},
            ).toJson(),
          ]),
        );

        final procedureScans = (await AppPrefs.getScanEntries())
            .where((entry) => entry.procedureId == 'proc_legacy')
            .toList();

        expect(procedureScans.length, 3);
        expect(procedureScans.where((entry) => entry.isBaseline).length, 1);
        expect(
          procedureScans.singleWhere((entry) => entry.isBaseline).imagePath,
          'first',
        );

        final comparison = await AppPrefs.getProcedurePhotoComparison(
          'proc_legacy',
        );
        expect(comparison['baselineImagePath'], 'first');
        expect(comparison['latestImagePath'], 'third');
      },
    );

    test(
      'addScanEntry keeps oldest baseline while latest stays newest scan',
      () async {
        const procedureId = 'proc_add_scan_entry_pin_baseline';
        final t0 = DateTime.parse('2026-06-01T10:00:00.000Z');
        final t0b = DateTime.parse('2026-06-01T10:00:01.000Z');
        final t1 = DateTime.parse('2026-06-02T10:00:00.000Z');

        final baselineEntry = ScanHistoryEntry(
          id: 'scan_b',
          timestamp: t0,
          procedureId: procedureId,
          imagePath: 'baseline.jpg',
          estimatedSkinAge: 30,
          metrics: const {'redness': 5.0},
          isBaseline: false,
        );
        final firstHistory = await AppPrefs.addScanEntry(baselineEntry);
        expect(firstHistory.length, 1);

        final firstComparison = await AppPrefs.getProcedurePhotoComparison(
          procedureId,
        );
        expect(firstComparison['baselineScanId'], 'scan_b');
        expect(firstComparison['latestScanId'], 'scan_b');

        final sameDayFollowUp = ScanHistoryEntry(
          id: 'scan_a',
          timestamp: t0b,
          procedureId: procedureId,
          imagePath: 'followup_same_day.jpg',
          estimatedSkinAge: 30,
          metrics: const {'redness': 4.0},
          isBaseline: true,
        );
        await AppPrefs.addScanEntry(sameDayFollowUp);

        final secondComparison = await AppPrefs.getProcedurePhotoComparison(
          procedureId,
        );
        expect(secondComparison['baselineScanId'], 'scan_b');
        expect(secondComparison['latestScanId'], 'scan_a');

        final newestFollowUp = ScanHistoryEntry(
          id: 'scan_z',
          timestamp: t1,
          procedureId: procedureId,
          imagePath: 'followup_newest.jpg',
          estimatedSkinAge: 29,
          metrics: const {'redness': 3.0},
          isBaseline: true,
        );
        await AppPrefs.addScanEntry(newestFollowUp);

        final thirdComparison = await AppPrefs.getProcedurePhotoComparison(
          procedureId,
        );
        expect(thirdComparison['baselineScanId'], 'scan_b');
        expect(thirdComparison['latestScanId'], 'scan_z');

        final intermediateUploadedLater = ScanHistoryEntry(
          id: 'scan_m',
          timestamp: DateTime.parse('2026-06-01T15:00:00.000Z'),
          procedureId: procedureId,
          imagePath: 'intermediate.jpg',
          estimatedSkinAge: 29,
          metrics: const {'redness': 3.5},
          isBaseline: true,
        );
        await AppPrefs.addScanEntry(intermediateUploadedLater);

        final fourthComparison = await AppPrefs.getProcedurePhotoComparison(
          procedureId,
        );
        expect(fourthComparison['baselineScanId'], 'scan_b');
        expect(fourthComparison['latestScanId'], 'scan_z');

        final procedureScans = (await AppPrefs.getScanEntries())
            .where((entry) => entry.procedureId == procedureId)
            .toList();
        expect(procedureScans.length, 4);
        expect(procedureScans.where((entry) => entry.isBaseline).length, 1);
        expect(
          procedureScans.singleWhere((entry) => entry.isBaseline).id,
          'scan_b',
        );
      },
    );

    test(
      'addScanEntry follow-ups keep parentBaselineId and never flip baseline',
      () async {
        const procedureId = 'proc_followup_parent_link';
        final t0 = DateTime.parse('2026-06-10T10:00:00.000Z');
        final t1 = DateTime.parse('2026-06-11T10:00:00.000Z');
        final t2 = DateTime.parse('2026-06-12T10:00:00.000Z');

        await AppPrefs.addScanEntry(
          ScanHistoryEntry(
            id: 'baseline_scan',
            timestamp: t0,
            procedureId: procedureId,
            imagePath: 'baseline.jpg',
            estimatedSkinAge: 30,
            metrics: const {'redness': 5.0},
            isBaseline: false,
          ),
        );

        await AppPrefs.addScanEntry(
          ScanHistoryEntry(
            id: 'followup_second',
            timestamp: t1,
            procedureId: procedureId,
            imagePath: 'followup_second.jpg',
            estimatedSkinAge: 29,
            metrics: const {'redness': 4.0},
            isBaseline: true,
          ),
        );

        await AppPrefs.addScanEntry(
          ScanHistoryEntry(
            id: 'followup_third',
            timestamp: t2,
            procedureId: procedureId,
            imagePath: 'followup_third.jpg',
            estimatedSkinAge: 28,
            metrics: const {'redness': 3.0},
            isBaseline: true,
          ),
        );

        final procedureScans = (await AppPrefs.getScanEntries())
            .where((entry) => entry.procedureId == procedureId)
            .toList();

        final baseline = procedureScans.singleWhere(
          (entry) => entry.id == 'baseline_scan',
        );
        final second = procedureScans.singleWhere(
          (entry) => entry.id == 'followup_second',
        );
        final third = procedureScans.singleWhere(
          (entry) => entry.id == 'followup_third',
        );

        expect(baseline.isBaseline, isTrue);
        expect(baseline.parentBaselineId, isNull);

        expect(second.isBaseline, isFalse);
        expect(second.parentBaselineId, 'baseline_scan');

        expect(third.isBaseline, isFalse);
        expect(third.parentBaselineId, 'baseline_scan');

        expect(procedureScans.where((entry) => entry.isBaseline).length, 1);
        expect(
          procedureScans.singleWhere((entry) => entry.isBaseline).id,
          'baseline_scan',
        );

        final comparison = await AppPrefs.getProcedurePhotoComparison(
          procedureId,
        );
        expect(comparison['baselineScanId'], 'baseline_scan');
        expect(comparison['latestScanId'], 'followup_third');
      },
    );
  });
}
