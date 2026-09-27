import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the AI Skin Analysis baseline product rule: the first real,
/// comparable scan for each (procedureId, focusArea, poseTemplate,
/// guideType) key is that key's baseline.
///
///  - ScanHistoryEntry.resolveAiBaselineKey / aiBaselineKey: the key itself
///    (null-significance, focusArea normalization).
///  - scanPassesSingleScanBaselineGates / aiScanExtractionPaths /
///    aiScanFormulaVersions: which scans are even eligible to be a
///    baseline, independent of any specific comparison partner.
///  - resolveAiBaseline: the full precedence (valid pin wins > earliest
///    eligible scan > none yet), including an invalid pin never silently
///    swapping keys or overriding gate failures.
void main() {
  int idCounter = 0;

  ScanHistoryEntry scan({
    String? procedureId = 'proc_1',
    String? focusArea = 'Full Face',
    String? poseTemplate = 'Front',
    String? guideType = 'facial',
    String? captureQuality = 'normal',
    bool withExtractionPaths = true,
    bool withFormulaVersions = true,
    DateTime? timestamp,
  }) {
    final rawPayload = <String, dynamic>{
      if (withExtractionPaths)
        'metric_extraction_paths': const {'localized_redness': 'primary_roi'},
      if (withFormulaVersions)
        'metric_formula_versions': const {'localized_redness': 1},
    };
    return ScanHistoryEntry(
      id: 'scan_${idCounter++}',
      timestamp: timestamp ?? DateTime(2026, 1, 1),
      estimatedSkinAge: 0,
      metrics: const {},
      procedureId: procedureId,
      focusArea: focusArea,
      poseTemplate: poseTemplate,
      guideType: guideType,
      captureQuality: captureQuality,
      rawPayload: rawPayload,
    );
  }

  group('ScanHistoryEntry.resolveAiBaselineKey / aiBaselineKey', () {
    test('same inputs produce equal keys (record structural equality)', () {
      final a = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: 'proc_1',
        focusArea: 'Full Face',
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      final b = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: 'proc_1',
        focusArea: 'full  face', // different case/whitespace
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      expect(a, b);
    });

    test('a null procedureId does not match a real one', () {
      final withProcedure = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: 'proc_1',
        focusArea: 'Full Face',
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      final withoutProcedure = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: null,
        focusArea: 'Full Face',
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      expect(withProcedure, isNot(withoutProcedure));

      final anotherNullProcedure = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: null,
        focusArea: 'Full Face',
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      expect(
        withoutProcedure,
        anotherNullProcedure,
        reason: 'two null procedureIds must match each other',
      );
    });

    test('a null focusArea does not match a real one', () {
      final withFocus = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: 'proc_1',
        focusArea: 'Full Face',
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      final withoutFocus = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: 'proc_1',
        focusArea: null,
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      expect(withFocus, isNot(withoutFocus));

      final anotherNullFocus = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: 'proc_1',
        focusArea: '',
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      expect(
        withoutFocus,
        anotherNullFocus,
        reason: 'an empty focusArea normalizes to null, same as a real null',
      );
    });

    test('"Left 45°" is a different key than "Front" for the same '
        'procedure/focus/guide', () {
      final front = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: 'proc_1',
        focusArea: 'Full Face',
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      final left45 = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: 'proc_1',
        focusArea: 'Full Face',
        poseTemplate: 'Left 45°',
        guideType: 'facial',
      );
      expect(front, isNot(left45));
    });

    test('a scan missing guideType has a key that can never equal a real '
        'capture\'s key', () {
      final realCaptureKey = ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: 'proc_1',
        focusArea: 'Full Face',
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      final entryMissingGuide = scan(guideType: null);
      expect(entryMissingGuide.aiBaselineKey, isNot(realCaptureKey));
    });
  });

  group('scanPassesSingleScanBaselineGates', () {
    test('a well-formed normal scan passes', () {
      expect(scanPassesSingleScanBaselineGates(scan()), isTrue);
    });

    test('a scan without guideType never becomes a baseline', () {
      expect(scanPassesSingleScanBaselineGates(scan(guideType: null)), isFalse);
    });

    test('a scan without poseTemplate never becomes a baseline', () {
      expect(
        scanPassesSingleScanBaselineGates(scan(poseTemplate: null)),
        isFalse,
      );
    });

    test('a scan with non-normal capture quality fails the gate', () {
      expect(
        scanPassesSingleScanBaselineGates(scan(captureQuality: 'blurry')),
        isFalse,
      );
    });

    test('a scan with unrecorded capture quality fails the gate', () {
      expect(
        scanPassesSingleScanBaselineGates(scan(captureQuality: null)),
        isFalse,
      );
    });

    test('a scan with no known analysis method (extraction path) fails', () {
      expect(
        scanPassesSingleScanBaselineGates(scan(withExtractionPaths: false)),
        isFalse,
      );
    });

    test('a scan with no recorded formula version fails', () {
      expect(
        scanPassesSingleScanBaselineGates(scan(withFormulaVersions: false)),
        isFalse,
      );
    });
  });

  group('aiScanExtractionPaths / aiScanFormulaVersions', () {
    test('reads top-level provenance maps', () {
      final entry = scan();
      expect(aiScanExtractionPaths(entry)['localized_redness'], 'primary_roi');
      expect(aiScanFormulaVersions(entry)['localized_redness'], 1);
    });

    test('empty when the scan carries no provenance at all', () {
      final entry = scan(withExtractionPaths: false, withFormulaVersions: false);
      expect(aiScanExtractionPaths(entry), isEmpty);
      expect(aiScanFormulaVersions(entry), isEmpty);
    });

    test('every non-empty extraction-path value is preserved', () {
      const paths = <String>[
        'cheek_primary',
        'cheek_primary_no_skin_mask',
        'full_face_fallback',
        'cheek_expand_no_skin',
        'large_roi_fallback',
        'approximate_face_bbox',
        'laplacian_fallback',
        'full_face_yolo',
        'tzone_landmark_fallback',
        'tzone_face_fallback',
      ];
      for (final path in paths) {
        expect(preservedAiExtractionPath(path), path);
      }
      final entry = ScanHistoryEntry(
        id: 'scan_bad_path',
        timestamp: DateTime(2026, 1, 1),
        estimatedSkinAge: 0,
        metrics: const {},
        poseTemplate: 'Front',
        guideType: 'facial',
        captureQuality: 'normal',
        rawPayload: const {
          'metric_extraction_paths': {'localized_redness': 'made_up_method'},
        },
      );
      expect(
        aiScanExtractionPaths(entry),
        const {'localized_redness': 'made_up_method'},
      );
      expect(preservedAiExtractionPath(' cheek_primary '), 'cheek_primary');
      expect(preservedAiExtractionPath(''), isNull);
    });
  });

  group('resolveAiBaseline precedence', () {
    test(
      'no key-matching scans yet -> isFirstForKey, no baseline (this is '
      '"first Front scan becomes the Front baseline" -- confirmed once the '
      'app registers it after saving)',
      () {
        final key = ScanHistoryEntry.resolveAiBaselineKey(
          procedureId: 'proc_1',
          focusArea: 'Full Face',
          poseTemplate: 'Front',
          guideType: 'facial',
        );
        final resolution = resolveAiBaseline(
          key: key,
          keyMatches: const [],
          allScans: const [],
        );
        expect(resolution.isFirstForKey, isTrue);
        expect(resolution.baselineScan, isNull);
        expect(resolution.ignoredPinReason, isNull);
      },
    );

    test(
      'a second Front scan compares against the earlier eligible Front scan',
      () {
        final baseline = scan(timestamp: DateTime(2026, 1, 1));
        final key = baseline.aiBaselineKey;
        final resolution = resolveAiBaseline(
          key: key,
          keyMatches: [baseline],
          allScans: [baseline],
        );
        expect(resolution.baselineScan?.id, baseline.id);
        expect(resolution.isFirstForKey, isFalse);
      },
    );

    test('the earliest eligible scan wins when there is no pin', () {
      final oldest = scan(timestamp: DateTime(2026, 1, 1));
      final middle = scan(timestamp: DateTime(2026, 1, 5));
      final newest = scan(timestamp: DateTime(2026, 1, 10));
      final key = oldest.aiBaselineKey;
      final resolution = resolveAiBaseline(
        key: key,
        keyMatches: [newest, oldest, middle], // deliberately unsorted
        allScans: [newest, oldest, middle],
      );
      expect(resolution.baselineScan?.id, oldest.id);
    });

    test('a valid pin wins over the earliest scan', () {
      final oldest = scan(timestamp: DateTime(2026, 1, 1));
      final pinnedLater = scan(timestamp: DateTime(2026, 1, 10));
      final key = oldest.aiBaselineKey;
      final resolution = resolveAiBaseline(
        key: key,
        keyMatches: [oldest, pinnedLater],
        allScans: [oldest, pinnedLater],
        pinnedScanId: pinnedLater.id,
      );
      expect(resolution.baselineScan?.id, pinnedLater.id);
      expect(resolution.ignoredPinReason, isNull);
    });

    test(
      'an invalid pin (scan no longer exists) is ignored with a message, '
      'falling back to the earliest eligible scan',
      () {
        final oldest = scan(timestamp: DateTime(2026, 1, 1));
        final key = oldest.aiBaselineKey;
        final resolution = resolveAiBaseline(
          key: key,
          keyMatches: [oldest],
          allScans: [oldest],
          pinnedScanId: 'scan_does_not_exist',
        );
        expect(resolution.baselineScan?.id, oldest.id);
        expect(resolution.ignoredPinReason, isNotNull);
      },
    );

    test(
      'an invalid pin (fails single-scan gates) is ignored with a message, '
      'never becoming the baseline',
      () {
        final oldest = scan(timestamp: DateTime(2026, 1, 1));
        final badPin = scan(
          timestamp: DateTime(2026, 1, 5),
          captureQuality: 'blurry',
        );
        final key = oldest.aiBaselineKey;
        final resolution = resolveAiBaseline(
          key: key,
          keyMatches: [oldest, badPin],
          allScans: [oldest, badPin],
          pinnedScanId: badPin.id,
        );
        expect(resolution.baselineScan?.id, oldest.id);
        expect(resolution.ignoredPinReason, isNotNull);
      },
    );

    test(
      'an invalid pin (key mismatch) is ignored with a message, never '
      'pulling in a scan from a different key',
      () {
        final oldest = scan(timestamp: DateTime(2026, 1, 1));
        final otherKeyScan = scan(
          poseTemplate: 'Left 45°',
          timestamp: DateTime(2026, 1, 5),
        );
        final key = oldest.aiBaselineKey;
        final resolution = resolveAiBaseline(
          key: key,
          keyMatches: [oldest], // otherKeyScan correctly excluded by caller
          allScans: [oldest, otherKeyScan],
          pinnedScanId: otherKeyScan.id,
        );
        expect(resolution.baselineScan?.id, oldest.id);
        expect(resolution.ignoredPinReason, isNotNull);
      },
    );

    test(
      'a scan failing single-scan gates never becomes the baseline, even '
      'as the only/earliest candidate',
      () {
        final onlyCandidate = scan(captureQuality: 'blurry');
        final key = onlyCandidate.aiBaselineKey;
        final resolution = resolveAiBaseline(
          key: key,
          keyMatches: [onlyCandidate],
          allScans: [onlyCandidate],
        );
        expect(resolution.baselineScan, isNull);
        expect(resolution.isFirstForKey, isTrue);
        expect(resolution.eligibleScansForKey, isEmpty);
      },
    );

    test(
      'a Left 45° scan never uses a Front baseline -- the caller only ever '
      'passes key-matching scans into keyMatches, so a differently-keyed '
      'scan in allScans is invisible to resolution unless pinned',
      () {
        final frontBaseline = scan(poseTemplate: 'Front');
        final left45Key = ScanHistoryEntry.resolveAiBaselineKey(
          procedureId: 'proc_1',
          focusArea: 'Full Face',
          poseTemplate: 'Left 45°',
          guideType: 'facial',
        );
        final resolution = resolveAiBaseline(
          key: left45Key,
          keyMatches: const [], // frontBaseline does not match this key
          allScans: [frontBaseline],
        );
        expect(resolution.baselineScan, isNull);
        expect(resolution.isFirstForKey, isTrue);
      },
    );
  });
}
