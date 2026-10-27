import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/services/skin_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the fix for a real fresh-install bug: the very first Front AI
/// Skin Analysis scan showed "Baseline scan captured" on the results card
/// while a snackbar said it failed the quality checks -- because
/// ScanHistoryEntry.captureQuality was never populated for a normally-
/// saved AI Skin Analysis scan (SkinHistoryRepository.saveScan had no
/// captureQuality parameter at all), so scanPassesSingleScanBaselineGates
/// always rejected it even for a genuinely normal capture.
///
///  - aiBaselineRejectionReason: names the exact failing check, and stays
///    perfectly in sync with scanPassesSingleScanBaselineGates (same
///    function, single source of truth).
///  - SkinHistoryRepository.saveScan: captureQuality now round-trips onto
///    the persisted ScanHistoryEntry.
void main() {
  ScanHistoryEntry scan({
    String? poseTemplate = 'Front',
    String? guideType = 'facial',
    String? captureQuality = 'normal',
    bool withExtractionPaths = true,
    bool withFormulaVersions = true,
    Map<String, dynamic> extraPayload = const {},
  }) {
    final rawPayload = <String, dynamic>{
      if (withExtractionPaths)
        'metric_extraction_paths': const {'localized_redness': 'primary_roi'},
      if (withFormulaVersions)
        'metric_formula_versions': const {'localized_redness': 1},
      ...extraPayload,
    };
    return ScanHistoryEntry(
      id: 'scan_1',
      timestamp: DateTime(2026, 1, 1),
      estimatedSkinAge: 0,
      metrics: const {},
      poseTemplate: poseTemplate,
      guideType: guideType,
      captureQuality: captureQuality,
      rawPayload: rawPayload,
    );
  }

  group('aiBaselineRejectionReason', () {
    for (final topLevel in [false, true]) {
      for (final scenario in const [
        (marked: true, applied: false, count: 0, required: 5, status: 'rejected', accepted: false),
        (marked: true, applied: true, count: 3, required: 5, status: 'applied', accepted: false),
        (marked: true, applied: true, count: 5, required: 5, status: 'applied', accepted: true),
        (marked: true, applied: true, count: 1, required: 1, status: 'applied', accepted: true),
        (marked: false, applied: false, count: 0, required: 5, status: 'not_marked', accepted: true),
        (marked: true, applied: true, count: 5, required: 5, status: 'rejected', accepted: false),
      ]) {
        test('marked=${scenario.marked} flag=${scenario.applied} ${scenario.count}/${scenario.required} ${scenario.status} baseline=${scenario.accepted} topLevel=$topLevel', () {
          final card = <String, dynamic>{
            'gray_card_marked': scenario.marked,
            'gray_card_correction_applied': scenario.applied,
            'gray_card_frames_applied': scenario.count,
            'gray_card_frames_read': scenario.count,
            'gray_card_status': scenario.status,
            'gray_card_baseline_eligible': true,
          };
          final candidate = scan(extraPayload: {
            if (topLevel) ...card else 'image_quality': card,
            'multi_frame_analysis': {'requested_frames': scenario.required},
          });
          expect(scanPassesSingleScanBaselineGates(candidate), scenario.accepted);
          expect(aiBaselineRejectionReason(candidate) == null, scenario.accepted);
        });
      }
    }

    test('a marked card without an acceptance flag cannot become a baseline', () {
      expect(scanPassesSingleScanBaselineGates(scan(extraPayload: {
        'image_quality': {'gray_card_marked': true, 'gray_card_frames_applied': 5},
        'multi_frame_analysis': {'requested_frames': 5},
      })), isFalse);
    });

    test('a well-formed normal scan has no rejection reason', () {
      expect(aiBaselineRejectionReason(scan()), isNull);
    });

    test('names a missing pose template', () {
      final reason = aiBaselineRejectionReason(scan(poseTemplate: null));
      expect(reason, isNotNull);
      expect(reason, contains('angle'));
    });

    test('names a missing guide type', () {
      final reason = aiBaselineRejectionReason(scan(guideType: null));
      expect(reason, isNotNull);
      expect(reason, contains('region'));
    });

    test('names an unrecorded capture quality', () {
      final reason = aiBaselineRejectionReason(scan(captureQuality: null));
      expect(reason, isNotNull);
      expect(reason!.toLowerCase(), contains('capture quality'));
      expect(reason.toLowerCase(), contains('not recorded'));
    });

    test('names a non-normal capture quality by its actual value', () {
      final reason = aiBaselineRejectionReason(scan(captureQuality: 'fair'));
      expect(reason, "Not saved as baseline: capture quality was 'fair'.");
    });

    test('names a missing analysis method (extraction path)', () {
      final reason = aiBaselineRejectionReason(
        scan(withExtractionPaths: false),
      );
      expect(reason, isNotNull);
      expect(reason!.toLowerCase(), contains('analysis method'));
    });

    test('names a missing scoring formula version', () {
      final reason = aiBaselineRejectionReason(
        scan(withFormulaVersions: false),
      );
      expect(reason, isNotNull);
      expect(reason!.toLowerCase(), contains('formula version'));
    });

    test(
      'never disagrees with scanPassesSingleScanBaselineGates -- null iff '
      'the gate passes',
      () {
        for (final candidate in [
          scan(),
          scan(poseTemplate: null),
          scan(guideType: null),
          scan(captureQuality: null),
          scan(captureQuality: 'blurry'),
          scan(withExtractionPaths: false),
          scan(withFormulaVersions: false),
        ]) {
          final passes = scanPassesSingleScanBaselineGates(candidate);
          final reason = aiBaselineRejectionReason(candidate);
          expect(
            passes,
            reason == null,
            reason:
                'gate result ($passes) and rejection reason ($reason) must '
                'never disagree',
          );
        }
      },
    );
  });

  group('SkinHistoryRepository.saveScan captureQuality population', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'captureQuality is saved onto the entry and survives a re-read',
      () async {
        final saved = await SkinHistoryRepository.instance.saveScan(
          metrics: const {'localized_redness': 20.0},
          imagePath: 'scan.jpg',
          poseTemplate: 'Front',
          guideType: 'facial',
          captureQuality: 'normal',
        );
        expect(saved.captureQuality, 'normal');

        final reloaded = await SkinHistoryRepository.instance.getAllScans();
        final match = reloaded.singleWhere((s) => s.id == saved.id);
        expect(match.captureQuality, 'normal');
      },
    );

    test('a non-normal captureQuality is saved verbatim, not silently normalized', () async {
      final saved = await SkinHistoryRepository.instance.saveScan(
        metrics: const {'localized_redness': 20.0},
        imagePath: 'scan.jpg',
        poseTemplate: 'Front',
        guideType: 'facial',
        captureQuality: 'blurry',
      );
      expect(saved.captureQuality, 'blurry');
    });

    test('omitting captureQuality leaves it null (legacy behavior unchanged)', () async {
      final saved = await SkinHistoryRepository.instance.saveScan(
        metrics: const {'localized_redness': 20.0},
        imagePath: 'scan.jpg',
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      expect(saved.captureQuality, isNull);
    });

    test(
      'a scan saved with a real captureQuality of "normal" now passes the '
      'single-scan baseline gate end-to-end -- this is the exact scenario '
      'that was previously rejected on a fresh install',
      () async {
        final saved = await SkinHistoryRepository.instance.saveScan(
          metrics: const {'localized_redness': 20.0},
          imagePath: 'scan.jpg',
          poseTemplate: 'Front',
          guideType: 'facial',
          captureQuality: 'normal',
          rawPayload: const {
            'metric_extraction_paths': {'localized_redness': 'primary_roi'},
            'metric_formula_versions': {'localized_redness': 1},
          },
        );
        expect(scanPassesSingleScanBaselineGates(saved), isTrue);
        expect(aiBaselineRejectionReason(saved), isNull);
      },
    );
  });
}
