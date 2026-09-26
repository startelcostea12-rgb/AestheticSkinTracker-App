import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aesthetic_skin_tracker/features/procedures/presentation/procedure_profiles_screen.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
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

    test('recovery plan activation is opt-in procedure metadata only', () async {
      await AppPrefs.saveProcedureHistory([
        {
          'id': 'proc_halo',
          'type': 'Halo Laser',
          'provider': 'Self / At-Home',
          'startDate': DateTime(2026, 9, 18).toIso8601String(),
          'numSessions': 1,
        },
      ]);

      var procedures = await AppPrefs.getProcedureEntries();
      expect(procedures.single.containsKey('recoveryPlanId'), isFalse);

      await AppPrefs.activateRecoveryPlanForProcedure(
        procedureId: 'proc_halo',
        recoveryPlanId: 'halo_laser_7_day_first_draft',
      );
      procedures = await AppPrefs.getProcedureEntries();
      expect(
        procedures.single['recoveryPlanId'],
        'halo_laser_7_day_first_draft',
      );

      await AppPrefs.clearRecoveryPlanForProcedure('proc_halo');
      procedures = await AppPrefs.getProcedureEntries();
      expect(procedures.single.containsKey('recoveryPlanId'), isFalse);
    });

    test('reminder notifications toggle persists and defaults off', () async {
      expect(await AppPrefs.getNotificationsEnabled(), isFalse);

      await AppPrefs.setNotificationsEnabled(true);
      expect(await AppPrefs.getNotificationsEnabled(), isTrue);

      await AppPrefs.setNotificationsEnabled(false);
      expect(await AppPrefs.getNotificationsEnabled(), isFalse);
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

    test('locked baseline preserves body reference geometry after normalization', () async {
      const procedureId = 'proc_body_reference_geometry';
      const geometry = <String, double>{
        'shoulderWidthNorm': 0.40,
        'hipWidthNorm': 0.36,
        'shoulderToHipRatio': 1.11,
        'centerOffsetX': 0.01,
        'centerOffsetY': -0.02,
      };

      await AppPrefs.addScanEntry(
        ScanHistoryEntry(
          id: 'body_baseline',
          timestamp: DateTime.parse('2026-06-20T10:00:00.000Z'),
          procedureId: procedureId,
          imagePath: 'body_baseline.jpg',
          estimatedSkinAge: 0,
          metrics: const {'capture_pose_similarity': 95.0},
          bodyReferenceGeometry: geometry,
        ),
      );
      await AppPrefs.addScanEntry(
        ScanHistoryEntry(
          id: 'body_followup',
          timestamp: DateTime.parse('2026-06-21T10:00:00.000Z'),
          procedureId: procedureId,
          imagePath: 'body_followup.jpg',
          estimatedSkinAge: 0,
          metrics: const {
            'capture_pose_similarity': 90.0,
            'capture_reference_alignment_score': 88.0,
          },
          bodyReferenceGeometry: const {
            'shoulderWidthNorm': 0.41,
            'hipWidthNorm': 0.35,
            'shoulderToHipRatio': 1.10,
            'centerOffsetX': 0.02,
            'centerOffsetY': -0.01,
          },
        ),
      );

      await AppPrefs.patchScanMetrics(
        'body_baseline',
        const {'waist_measurement': 31.5},
      );

      final scans = await AppPrefs.getScanEntries();
      final baseline = scans.singleWhere((entry) => entry.id == 'body_baseline');
      final followup = scans.singleWhere((entry) => entry.id == 'body_followup');

      expect(baseline.isBaseline, isTrue);
      expect(baseline.bodyReferenceGeometry, geometry);
      expect(baseline.metrics['waist_measurement'], 31.5);
      expect(followup.parentBaselineId, 'body_baseline');
      expect(followup.metrics['capture_reference_alignment_score'], 88.0);
    });

    test('poor body follow-up alignment survives storage and gates comparison', () async {
      const procedureId = 'proc_body_alignment_gate';
      const baselineGeometry = <String, double>{
        'shoulderWidthNorm': 0.40,
        'hipWidthNorm': 0.36,
        'shoulderToHipRatio': 1.11,
        'centerOffsetX': 0.0,
        'centerOffsetY': 0.0,
      };
      const poorGeometry = <String, double>{
        'shoulderWidthNorm': 0.18,
        'hipWidthNorm': 0.62,
        'shoulderToHipRatio': 0.35,
        'centerOffsetX': 0.30,
        'centerOffsetY': 0.25,
      };
      final poorScore = bodyReferenceAlignmentScore(
        baselineGeometry,
        poorGeometry,
      )!;

      await AppPrefs.addScanEntry(
        ScanHistoryEntry(
          id: 'body_gate_baseline',
          timestamp: DateTime.parse('2026-07-01T10:00:00.000Z'),
          procedureId: procedureId,
          imagePath: 'baseline.jpg',
          estimatedSkinAge: 0,
          metrics: const {},
          bodyReferenceGeometry: baselineGeometry,
          captureQuality: 'normal',
          captureMode: 'mirror',
          poseTemplate: 'Front',
          guideType: 'body',
          rawPayload: const {
            'result': {'scale_reference_pixels': 200.0},
          },
        ),
      );
      await AppPrefs.addScanEntry(
        ScanHistoryEntry(
          id: 'body_gate_followup',
          timestamp: DateTime.parse('2026-07-02T10:00:00.000Z'),
          procedureId: procedureId,
          imagePath: 'followup.jpg',
          estimatedSkinAge: 0,
          metrics: {'capture_reference_alignment_score': poorScore},
          bodyReferenceGeometry: poorGeometry,
          captureQuality: 'normal',
          captureMode: 'mirror',
          poseTemplate: 'Front',
          guideType: 'body',
          rawPayload: const {
            'result': {'scale_reference_pixels': 205.0},
          },
        ),
      );

      final scans = (await AppPrefs.getScanEntries())
          .where((entry) => entry.procedureId == procedureId)
          .toList();
      final baseline = lockedProcedureReference(scans, procedureId);
      final followup = scans.singleWhere(
        (entry) => entry.id == 'body_gate_followup',
      );
      final eligibility = procedurePhotoComparisonEligibility(
        isBodyProcedure: true,
        baseline: baseline,
        latest: followup,
      );

      expect(baseline?.id, 'body_gate_baseline');
      expect(baseline?.bodyReferenceGeometry, baselineGeometry);
      expect(poorScore, lessThan(minimumComparableReferenceAlignmentScore));
      expect(
        followup.metrics['capture_reference_alignment_score'],
        poorScore,
      );
      expect(eligibility.isComparable, isFalse);
      expect(eligibility.caveat, contains('locked reference'));
    });

    test('poor face follow-up alignment survives storage and gates comparison', () async {
      const procedureId = 'proc_face_alignment_gate';
      const baselineGeometry = <String, double>{
        'eyeDistanceNorm': 0.22,
        'faceWidthNorm': 0.48,
        'faceHeightNorm': 0.62,
        'faceAspectRatio': 0.77,
        'centerOffsetX': 0.0,
        'centerOffsetY': 0.0,
      };
      const poorGeometry = <String, double>{
        'eyeDistanceNorm': 0.08,
        'faceWidthNorm': 0.25,
        'faceHeightNorm': 0.30,
        'faceAspectRatio': 1.30,
        'centerOffsetX': 0.30,
        'centerOffsetY': 0.25,
      };
      final poorScore = faceReferenceAlignmentScore(
        baselineGeometry,
        poorGeometry,
      )!;
      const extractionPaths = <String, dynamic>{
        'metric_extraction_paths': {
          'localized_redness': 'primary_roi',
        },
      };

      await AppPrefs.addScanEntry(
        ScanHistoryEntry(
          id: 'face_gate_baseline',
          timestamp: DateTime.parse('2026-07-10T10:00:00.000Z'),
          procedureId: procedureId,
          imagePath: 'face_baseline.jpg',
          estimatedSkinAge: 0,
          metrics: const {},
          faceReferenceGeometry: baselineGeometry,
          captureQuality: 'normal',
          poseTemplate: 'Front',
          guideType: 'facial',
          rawPayload: extractionPaths,
        ),
      );
      await AppPrefs.addScanEntry(
        ScanHistoryEntry(
          id: 'face_gate_followup',
          timestamp: DateTime.parse('2026-07-11T10:00:00.000Z'),
          procedureId: procedureId,
          imagePath: 'face_followup.jpg',
          estimatedSkinAge: 0,
          metrics: {'capture_reference_alignment_score': poorScore},
          faceReferenceGeometry: poorGeometry,
          captureQuality: 'normal',
          poseTemplate: 'Front',
          guideType: 'facial',
          rawPayload: extractionPaths,
        ),
      );
      await AppPrefs.patchScanMetrics(
        'face_gate_baseline',
        const {'provider_note_count': 1.0},
      );

      final scans = (await AppPrefs.getScanEntries())
          .where((entry) => entry.procedureId == procedureId)
          .toList();
      final baseline = lockedProcedureReference(scans, procedureId);
      final followup = scans.singleWhere(
        (entry) => entry.id == 'face_gate_followup',
      );
      final eligibility = procedurePhotoComparisonEligibility(
        isBodyProcedure: false,
        baseline: baseline,
        latest: followup,
      );

      expect(baseline?.id, 'face_gate_baseline');
      expect(baseline?.faceReferenceGeometry, baselineGeometry);
      expect(baseline?.metrics['provider_note_count'], 1.0);
      expect(poorScore, lessThan(minimumComparableReferenceAlignmentScore));
      expect(
        followup.metrics['capture_reference_alignment_score'],
        poorScore,
      );
      expect(eligibility.isComparable, isFalse);
      expect(eligibility.caveat, contains('locked reference'));
    });
  });

  group('AppPrefs AI Skin Analysis baseline registry', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    const key = (
      procedureId: 'proc_1',
      focusArea: 'full face',
      poseTemplate: 'Front',
      guideType: 'facial',
    );
    const otherKey = (
      procedureId: 'proc_1',
      focusArea: 'full face',
      poseTemplate: 'Left 45°',
      guideType: 'facial',
    );

    test('returns null for a key that was never set', () async {
      expect(await AppPrefs.getAiBaselineScanId(key), isNull);
    });

    test('set then get round-trips the scan id for that exact key', () async {
      await AppPrefs.setAiBaselineScanId(key, 'scan_front_1');
      expect(await AppPrefs.getAiBaselineScanId(key), 'scan_front_1');
    });

    test('setting one key\'s baseline never affects a different key', () async {
      await AppPrefs.setAiBaselineScanId(key, 'scan_front_1');
      await AppPrefs.setAiBaselineScanId(otherKey, 'scan_left45_1');

      expect(await AppPrefs.getAiBaselineScanId(key), 'scan_front_1');
      expect(await AppPrefs.getAiBaselineScanId(otherKey), 'scan_left45_1');
    });

    test('setting the same key again replaces its previous baseline', () async {
      await AppPrefs.setAiBaselineScanId(key, 'scan_front_1');
      await AppPrefs.setAiBaselineScanId(key, 'scan_front_2');
      expect(await AppPrefs.getAiBaselineScanId(key), 'scan_front_2');
    });

    test('getAllAiBaselineScanIds returns every key\'s current baseline', () async {
      expect(await AppPrefs.getAllAiBaselineScanIds(), isEmpty);

      await AppPrefs.setAiBaselineScanId(key, 'scan_front_1');
      await AppPrefs.setAiBaselineScanId(otherKey, 'scan_left45_1');
      await AppPrefs.setAiBaselineScanId(key, 'scan_front_2');
      expect(
        await AppPrefs.getAllAiBaselineScanIds(),
        {'scan_front_2', 'scan_left45_1'},
      );

      await AppPrefs.clearAiBaselineScanId(otherKey);
      expect(await AppPrefs.getAllAiBaselineScanIds(), {'scan_front_2'});
    });

    test('clearAiBaselineScanId clears only that key', () async {
      await AppPrefs.setAiBaselineScanId(key, 'scan_front_1');
      await AppPrefs.setAiBaselineScanId(otherKey, 'scan_left45_1');

      await AppPrefs.clearAiBaselineScanId(key);

      expect(await AppPrefs.getAiBaselineScanId(key), isNull);
      expect(await AppPrefs.getAiBaselineScanId(otherKey), 'scan_left45_1');
    });

    test(
      'the old device-global cached matrix is ignored: clearing it removes '
      'the legacy key without touching the new per-key registry',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          AppPrefs.legacyAiManualBaselineMetricMatrixKey,
          '{"localized_redness": 42.0}',
        );
        await AppPrefs.setAiBaselineScanId(key, 'scan_front_1');

        await AppPrefs.clearLegacyAiManualBaselineMetricMatrix();

        expect(
          prefs.getString(AppPrefs.legacyAiManualBaselineMetricMatrixKey),
          isNull,
        );
        expect(await AppPrefs.getAiBaselineScanId(key), 'scan_front_1');
      },
    );
  });
}
