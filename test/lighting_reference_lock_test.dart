import 'package:aesthetic_skin_tracker/utils/lighting_reference_check.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> qualityPayload({
  double? lightingMeanL,
  double? aAfterWb,
  double? bAfterWb,
  bool nested = false,
}) {
  final quality = <String, dynamic>{
    if (lightingMeanL != null) 'lighting_mean_l': lightingMeanL,
    if (aAfterWb != null) 'whole_image_mean_a_after_wb': aAfterWb,
    if (bAfterWb != null) 'whole_image_mean_b_after_wb': bAfterWb,
  };
  final payload = <String, dynamic>{'image_quality': quality};
  if (nested) return {'metrics': payload};
  return payload;
}

const baseline = (l: 122.92, a: 5.689, b: 9.788);
// Nov 7 23:55 same session: color distance ~0.90.
const matching = (l: 122.83, a: 6.55, b: 9.529);
// Nov 9 21:41: color distance ~8.33.
const mismatch = (l: 123.98, a: 12.03, b: 4.38);

void main() {
  group('evaluateLightingReferenceCheck', () {
    test('same-session lighting matches with margin', () {
      final check = evaluateLightingReferenceCheck(
        currentPayload: qualityPayload(
          lightingMeanL: matching.l,
          aAfterWb: matching.a,
          bAfterWb: matching.b,
        ),
        baselinePayload: qualityPayload(
          lightingMeanL: baseline.l,
          aAfterWb: baseline.a,
          bAfterWb: baseline.b,
        ),
      );
      expect(check.status, 'match');
      expect(check.lockReason, isNull);
      expect(check.colorDeltaAfterWb, lessThan(lightingRefColorAfterWbLimit));
      expect(check.lightingMeanLDelta, lessThan(lightingRefMeanLLimit));
    });

    test('Nov 9-style color shift is a mismatch', () {
      final check = evaluateLightingReferenceCheck(
        currentPayload: qualityPayload(
          lightingMeanL: mismatch.l,
          aAfterWb: mismatch.a,
          bAfterWb: mismatch.b,
        ),
        baselinePayload: qualityPayload(
          lightingMeanL: baseline.l,
          aAfterWb: baseline.a,
          bAfterWb: baseline.b,
        ),
      );
      expect(check.status, 'mismatch');
      expect(check.lockReason, 'lighting_mismatch');
      expect(
        check.colorDeltaAfterWb,
        greaterThan(lightingRefColorAfterWbLimit),
      );
      expect(check.failedSignals, contains('color_after_wb'));
    });

    test('missing references fail open', () {
      final noBaseline = evaluateLightingReferenceCheck(
        currentPayload: qualityPayload(
          lightingMeanL: matching.l,
          aAfterWb: matching.a,
          bAfterWb: matching.b,
        ),
        baselinePayload: const <String, dynamic>{},
      );
      expect(noBaseline.status, 'no_baseline');
      expect(noBaseline.lockReason, isNull);

      final missingFields = evaluateLightingReferenceCheck(
        currentPayload: qualityPayload(),
        baselinePayload: qualityPayload(),
      );
      expect(missingFields.status, lightingReferenceUnavailableStatus);
      expect(missingFields.lockReason, isNull);
    });
  });

  group('lockTrendsForLightingReferenceMismatch', () {
    const status = {
      'texture_smoothness': 'stable',
      'pigment_load': 'worsened',
      'localized_redness': 'improved',
      'under_eye_dark_circle_density': 'worsened',
    };
    const deltas = {
      'texture_smoothness': 0.0,
      'pigment_load': -75.3,
      'localized_redness': 10.0,
      'under_eye_dark_circle_density': -12.6,
    };

    test('mismatch clears verdicts, keeps raw-claim numbers path, leaves under-eye', () {
      for (final nested in [false, true]) {
        final result = lockTrendsForLightingReferenceMismatch(
          trendStatus: status,
          trendDeltas: deltas,
          trendLockReasons: const {},
          currentPayload: qualityPayload(
            lightingMeanL: mismatch.l,
            aAfterWb: mismatch.a,
            bAfterWb: mismatch.b,
            nested: nested,
          ),
          baselinePayload: qualityPayload(
            lightingMeanL: baseline.l,
            aAfterWb: baseline.a,
            bAfterWb: baseline.b,
            nested: nested,
          ),
        );
        expect(result.trendStatus, {
          'under_eye_dark_circle_density': 'worsened',
        });
        expect(result.trendDeltas, {'under_eye_dark_circle_density': -12.6});
        expect(result.trendLockReasons, {
          'texture_smoothness': 'lighting_mismatch',
          'pigment_load': 'lighting_mismatch',
          'localized_redness': 'lighting_mismatch',
        });
      }
    });

    test('matching lighting leaves verdicts unchanged', () {
      final result = lockTrendsForLightingReferenceMismatch(
        trendStatus: status,
        trendDeltas: deltas,
        trendLockReasons: const {},
        currentPayload: qualityPayload(
          lightingMeanL: matching.l,
          aAfterWb: matching.a,
          bAfterWb: matching.b,
        ),
        baselinePayload: qualityPayload(
          lightingMeanL: baseline.l,
          aAfterWb: baseline.a,
          bAfterWb: baseline.b,
        ),
      );
      expect(result.trendStatus, status);
      expect(result.trendDeltas, deltas);
      expect(result.trendLockReasons, isEmpty);
    });
  });
}
