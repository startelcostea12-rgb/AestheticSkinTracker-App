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

        await AppPrefs.addScanMetric(
          const SkinMetrics(redness: 4.0),
          procedureId: procedureId,
          imagePath: 'data:image/jpeg;base64,first',
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await AppPrefs.addScanMetric(
          const SkinMetrics(redness: 3.0),
          procedureId: procedureId,
          imagePath: 'data:image/jpeg;base64,second',
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await AppPrefs.addScanMetric(
          const SkinMetrics(redness: 2.0),
          procedureId: procedureId,
          imagePath: 'data:image/jpeg;base64,third',
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
      'legacy procedure scans are normalized so the oldest photo becomes baseline',
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
  });
}
