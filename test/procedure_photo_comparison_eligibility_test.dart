import 'package:aesthetic_skin_tracker/features/procedures/presentation/procedure_profiles_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:flutter_test/flutter_test.dart';

ScanHistoryEntry _scan({
  String? captureQuality = 'normal',
  String? captureMode,
  Map<String, String>? extractionPaths,
  double? scaleReferencePixels,
  Map<String, double> metrics = const <String, double>{},
}) {
  return ScanHistoryEntry(
    id: '${captureQuality}_${captureMode}_$scaleReferencePixels',
    timestamp: DateTime(2026, 9, 8),
    estimatedSkinAge: 0,
    metrics: metrics,
    captureQuality: captureQuality,
    captureMode: captureMode,
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
        baseline: _scan(captureMode: 'mirror', scaleReferencePixels: 200),
        latest: _scan(captureMode: 'mirror', scaleReferencePixels: 230),
      );

      expect(result.isComparable, isTrue);
    });

    test('rejects body comparison when capture mode differs', () {
      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: true,
        baseline: _scan(captureMode: 'mirror', scaleReferencePixels: 200),
        latest: _scan(captureMode: 'timer', scaleReferencePixels: 200),
      );

      expect(result.isComparable, isFalse);
      expect(result.caveat, contains('capture methods differed'));
    });

    test('rejects body comparison when scale reference differs by over 20%', () {
      final result = procedurePhotoComparisonEligibility(
        isBodyProcedure: true,
        baseline: _scan(captureMode: 'mirror', scaleReferencePixels: 200),
        latest: _scan(captureMode: 'mirror', scaleReferencePixels: 241),
      );

      expect(result.isComparable, isFalse);
      expect(result.caveat, contains('framing scale differed'));
    });
  });
}
