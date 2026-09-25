import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers ScanHistoryEntry.scansComparableByAngleAndGuide -- the shared
/// pure function behind the "only compare scans with matching angle and
/// region" rule, used by both the AI Skin Analysis candidate-selection
/// loop (skin_ai_analysis_screen.dart) and the Track Procedure
/// baseline/latest gate (procedure_profiles_screen.dart's
/// procedurePhotoComparisonEligibility). This is in ADDITION to, never a
/// replacement for, the pre-existing procedureId/focusArea gates -- those
/// are ANDed with this result by every caller, never ORed.
void main() {
  group('scansComparableByAngleAndGuide', () {
    test('same pose template and guide type -> comparable', () {
      final result = ScanHistoryEntry.scansComparableByAngleAndGuide(
        poseTemplateA: 'Front',
        guideTypeA: 'facial',
        poseTemplateB: 'Front',
        guideTypeB: 'facial',
      );
      expect(result, isTrue);
    });

    test(
      '"Left 45°" is never treated as "Left Profile" -- different angle '
      '-> not comparable',
      () {
        final result = ScanHistoryEntry.scansComparableByAngleAndGuide(
          poseTemplateA: 'Left 45°',
          guideTypeA: 'facial',
          poseTemplateB: 'Left Profile',
          guideTypeB: 'facial',
        );
        expect(result, isFalse);
      },
    );

    test('same pose template but different guide type -> not comparable', () {
      final result = ScanHistoryEntry.scansComparableByAngleAndGuide(
        poseTemplateA: 'Front',
        guideTypeA: 'facial',
        poseTemplateB: 'Front',
        guideTypeB: 'body',
      );
      expect(result, isFalse);
    });

    test('missing pose template on side A -> not comparable', () {
      final result = ScanHistoryEntry.scansComparableByAngleAndGuide(
        poseTemplateA: null,
        guideTypeA: 'facial',
        poseTemplateB: 'Front',
        guideTypeB: 'facial',
      );
      expect(result, isFalse);
    });

    test('missing pose template on side B -> not comparable', () {
      final result = ScanHistoryEntry.scansComparableByAngleAndGuide(
        poseTemplateA: 'Front',
        guideTypeA: 'facial',
        poseTemplateB: null,
        guideTypeB: 'facial',
      );
      expect(result, isFalse);
    });

    test('missing guide type on either side -> not comparable', () {
      final result = ScanHistoryEntry.scansComparableByAngleAndGuide(
        poseTemplateA: 'Front',
        guideTypeA: null,
        poseTemplateB: 'Front',
        guideTypeB: 'facial',
      );
      expect(result, isFalse);
    });

    test(
      'both sides missing pose template and guide type -> still not '
      'comparable (unknown never matches unknown, no fallback)',
      () {
        final result = ScanHistoryEntry.scansComparableByAngleAndGuide(
          poseTemplateA: null,
          guideTypeA: null,
          poseTemplateB: null,
          guideTypeB: null,
        );
        expect(result, isFalse);
      },
    );
  });

  group('ScanHistoryEntry.guideType field', () {
    test('round-trips through toJson/fromJson', () {
      final entry = ScanHistoryEntry(
        id: 'scan_1',
        timestamp: DateTime(2026, 1, 1),
        estimatedSkinAge: 0,
        metrics: const {},
        poseTemplate: 'Front',
        guideType: 'facial',
      );
      final restored = ScanHistoryEntry.fromJson(entry.toJson());
      expect(restored.guideType, 'facial');
      expect(restored.poseTemplate, 'Front');
    });

    test('defaults to null for entries saved before this field existed', () {
      final restored = ScanHistoryEntry.fromJson(<String, dynamic>{
        'id': 'legacy_scan',
        'timestamp': DateTime(2025, 1, 1).toIso8601String(),
        'estimatedSkinAge': 0,
        'metrics': <String, dynamic>{},
      });
      expect(restored.guideType, isNull);
    });
  });
}
