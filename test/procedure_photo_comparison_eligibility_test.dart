import 'package:aesthetic_skin_tracker/features/procedures/presentation/procedure_profiles_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:flutter_test/flutter_test.dart';

int _idCounter = 0;

/// poseTemplate/guideType default to matching values ('Front'/'facial' for
/// face, 'Front'/'body' for body) so tests exercising the pre-existing
/// capture-quality/extraction-path/capture-mode/scale gates aren't also
/// tripped by the newer angle/guide gate -- see the dedicated
/// "angle/guide" group below for that gate's own coverage. A unique id
/// (rather than one derived from the params) means two scans with
/// identical params are still distinct entries, never short-circuited by
/// the gate's same-id skip.
ScanHistoryEntry _scan({
  String? captureQuality = 'normal',
  String? captureMode,
  Map<String, String>? extractionPaths,
  double? scaleReferencePixels,
  Map<String, double> metrics = const <String, double>{},
  String? poseTemplate = 'Front',
  String? guideType = 'facial',
}) {
  return ScanHistoryEntry(
    id: 'scan_${_idCounter++}',
    timestamp: DateTime(2026, 9, 8),
    estimatedSkinAge: 0,
    metrics: metrics,
    captureQuality: captureQuality,
    captureMode: captureMode,
    poseTemplate: poseTemplate,
    guideType: guideType,
    rawPayload: <String, dynamic>{
      if (extractionPaths != null) 'metric_extraction_paths': extractionPaths,
      if (scaleReferencePixels != null)
        'result': <String, dynamic>{
          'scale_reference_pixels': scaleReferencePixels,
        },
    },
  );
}

void main() {
  group('procedurePhotoComparisonEligibility', () {
    test('poor face reference alignment makes the comparison non-comparable', () {
      final baseline = _scan(
        extractionPaths: const {'localized_redness': 'primary_roi'},
      );
      final latest = _scan(
        extractionPaths: const {'localized_redness': 'primary_roi'},
        metrics: const {'capture_reference_alignment_score': 45.0},
      );

      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: false,
        baseline: baseline,
        latest: latest,
      );

      expect(result.isComparable, isFalse);
      expect(result.caveat, contains('locked reference'));
    });

    test('poor body reference alignment makes the comparison non-comparable', () {
      final baseline = _scan(
        captureQuality: 'normal',
        captureMode: 'mirror',
        scaleReferencePixels: 200,
      );
      final latest = _scan(
        captureQuality: 'normal',
        captureMode: 'mirror',
        scaleReferencePixels: 205,
        metrics: const {'capture_reference_alignment_score': 42.0},
      );

      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: true,
        baseline: baseline,
        latest: latest,
      );

      expect(result.isComparable, isFalse);
      expect(result.caveat, contains('locked reference'));
    });

    test('allows face comparison with equal quality and extraction paths', () {
      final baseline = _scan(
        extractionPaths: const {'pigment_load': 'cheek_primary'},
      );
      final latest = _scan(
        extractionPaths: const {'pigment_load': 'cheek_primary'},
      );

      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: false,
        baseline: baseline,
        latest: latest,
      );

      expect(result.isComparable, isTrue);
      expect(result.caveat, isNull);
    });

    test('allows a well-aligned face follow-up with matching provenance', () {
      final baseline = _scan(
        extractionPaths: const {'localized_redness': 'primary_roi'},
      );
      final latest = _scan(
        extractionPaths: const {'localized_redness': 'primary_roi'},
        metrics: const {'capture_reference_alignment_score': 90.0},
      );

      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: false,
        baseline: baseline,
        latest: latest,
      );

      expect(result.isComparable, isTrue);
      expect(result.caveat, isNull);
    });

    test('rejects face comparison when capture quality differs', () {
      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: false,
        baseline: _scan(extractionPaths: const {'pigment_load': 'cheek_primary'}),
        latest: _scan(
          captureQuality: 'low_light',
          extractionPaths: const {'pigment_load': 'cheek_primary'},
        ),
      );

      expect(result.isComparable, isFalse);
      expect(result.caveat, contains('conditions differed'));
    });

    test('rejects face comparison when extraction paths differ', () {
      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: false,
        baseline: _scan(extractionPaths: const {'texture_smoothness': 'primary_roi'}),
        latest: _scan(extractionPaths: const {'texture_smoothness': 'laplacian_fallback'}),
      );

      expect(result.isComparable, isFalse);
      expect(result.caveat, contains('analysis paths differed'));
    });

    test('allows body comparison with matching mode and close scale reference', () {
      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: true,
        baseline: _scan(captureMode: 'mirror', scaleReferencePixels: 200, guideType: 'body'),
        latest: _scan(captureMode: 'mirror', scaleReferencePixels: 230, guideType: 'body'),
      );

      expect(result.isComparable, isTrue);
    });

    test('rejects body comparison when capture mode differs', () {
      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: true,
        baseline: _scan(captureMode: 'mirror', scaleReferencePixels: 200, guideType: 'body'),
        latest: _scan(captureMode: 'timer', scaleReferencePixels: 200, guideType: 'body'),
      );

      expect(result.isComparable, isFalse);
      expect(result.caveat, contains('capture methods differed'));
    });

    test('rejects body comparison when scale reference differs by over 20%', () {
      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: true,
        baseline: _scan(captureMode: 'mirror', scaleReferencePixels: 200, guideType: 'body'),
        latest: _scan(captureMode: 'mirror', scaleReferencePixels: 241, guideType: 'body'),
      );

      expect(result.isComparable, isFalse);
      expect(result.caveat, contains('framing scale differed'));
    });
  });

  group('procedurePhotoComparisonEligibility angle/guide gate', () {
    test('same pose template and guide type -> comparable', () {
      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: false,
        baseline: _scan(
          extractionPaths: const {'pigment_load': 'cheek_primary'},
          poseTemplate: 'Front',
          guideType: 'facial',
        ),
        latest: _scan(
          extractionPaths: const {'pigment_load': 'cheek_primary'},
          poseTemplate: 'Front',
          guideType: 'facial',
        ),
      );

      expect(result.isComparable, isTrue);
    });

    test(
      'different pose template ("Left 45°" vs "Left Profile") -> not '
      'comparable, even with everything else matching',
      () {
        final result = procedurePhotoComparisonEligibility(
          isBodyProcedure: false,
          baseline: _scan(
            extractionPaths: const {'pigment_load': 'cheek_primary'},
            poseTemplate: 'Left 45°',
            guideType: 'facial',
          ),
          latest: _scan(
            extractionPaths: const {'pigment_load': 'cheek_primary'},
            poseTemplate: 'Left Profile',
            guideType: 'facial',
          ),
        );

        expect(result.isComparable, isFalse);
        expect(result.caveat, contains('capture angle'));
      },
    );

    test('different guide type -> not comparable', () {
      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: false,
        baseline: _scan(
          extractionPaths: const {'pigment_load': 'cheek_primary'},
          poseTemplate: 'Front',
          guideType: 'facial',
        ),
        latest: _scan(
          extractionPaths: const {'pigment_load': 'cheek_primary'},
          poseTemplate: 'Front',
          guideType: 'body',
        ),
      );

      expect(result.isComparable, isFalse);
      expect(result.caveat, contains('capture angle'));
    });

    test(
      'missing pose template on either side -> not comparable (unknown is '
      'never treated as a match)',
      () {
        final missingOnBaseline = procedurePhotoComparisonEligibility(
          isBodyProcedure: false,
          baseline: _scan(
            extractionPaths: const {'pigment_load': 'cheek_primary'},
            poseTemplate: null,
            guideType: 'facial',
          ),
          latest: _scan(
            extractionPaths: const {'pigment_load': 'cheek_primary'},
            poseTemplate: 'Front',
            guideType: 'facial',
          ),
        );
        expect(missingOnBaseline.isComparable, isFalse);

        final missingOnBoth = procedurePhotoComparisonEligibility(
          isBodyProcedure: false,
          baseline: _scan(
            extractionPaths: const {'pigment_load': 'cheek_primary'},
            poseTemplate: null,
            guideType: null,
          ),
          latest: _scan(
            extractionPaths: const {'pigment_load': 'cheek_primary'},
            poseTemplate: null,
            guideType: null,
          ),
        );
        expect(
          missingOnBoth.isComparable,
          isFalse,
          reason: 'both null is still not a match -- unknown never matches unknown',
        );
      },
    );

    test(
      'missing guide type on either side -> not comparable',
      () {
        final result = procedurePhotoComparisonEligibility(
          isBodyProcedure: false,
          baseline: _scan(
            extractionPaths: const {'pigment_load': 'cheek_primary'},
            poseTemplate: 'Front',
            guideType: null,
          ),
          latest: _scan(
            extractionPaths: const {'pigment_load': 'cheek_primary'},
            poseTemplate: 'Front',
            guideType: 'facial',
          ),
        );

        expect(result.isComparable, isFalse);
      },
    );
  });
}
