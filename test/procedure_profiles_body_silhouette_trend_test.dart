import 'package:aesthetic_skin_tracker/features/procedures/presentation/procedure_profiles_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payload({
  required String status,
  double? delta,
  int? requiredScans,
  String? lockReason,
}) => <String, dynamic>{
  'status': 'success',
  'result': <String, dynamic>{'normalized_area_index': 42.0},
  'trend_status': <String, dynamic>{'normalized_area_index': status},
  'trend_deltas': <String, dynamic>{
    if (delta != null) 'normalized_area_index': delta,
  },
  'trend_lock_reasons': <String, dynamic>{
    if (lockReason != null) 'normalized_area_index': lockReason,
  },
  if (requiredScans != null) 'consistent_scan_requirement': requiredScans,
};

void main() {
  group('bodySilhouetteTrendSummary', () {
    test('"improved" shows a real positive percentage change', () {
      final summary = bodySilhouetteTrendSummary(
        isBodyContouringProcedure: true,
        rawPayload: _payload(status: 'improved', delta: 8.3),
      );

      expect(summary, isNotNull);
      expect(summary!.kind, BodySilhouetteTrendKind.improved);
      expect(summary.headline, contains('8.3%'));
      expect(summary.headline, contains('+'));
    });

    test('"worsened" shows a real negative percentage change', () {
      final summary = bodySilhouetteTrendSummary(
        isBodyContouringProcedure: true,
        rawPayload: _payload(status: 'worsened', delta: -6.1),
      );

      expect(summary, isNotNull);
      expect(summary!.kind, BodySilhouetteTrendKind.worsened);
      expect(summary.headline, contains('6.1%'));
      expect(summary.headline, contains('-'));
    });

    test(
      '"insufficient_signal" shows the actual consistent_scan_requirement number',
      () {
        final summary = bodySilhouetteTrendSummary(
          isBodyContouringProcedure: true,
          rawPayload: _payload(
            status: 'insufficient_signal',
            requiredScans: 3,
          ),
        );

        expect(summary, isNotNull);
        expect(summary!.kind, BodySilhouetteTrendKind.insufficientSignal);
        expect(summary.headline, 'Not enough consistent scans yet');
        expect(summary.detail, contains('3 consistent-condition'));
      },
    );

    test(
      '"insufficient_signal" without a requirement number still renders '
      'sensible copy instead of a literal null',
      () {
        final summary = bodySilhouetteTrendSummary(
          isBodyContouringProcedure: true,
          rawPayload: _payload(status: 'insufficient_signal'),
        );

        expect(summary, isNotNull);
        expect(summary!.detail, isNot(contains('null')));
      },
    );

    test(
      'a genuine "stable" (no trend_lock_reason) keeps the plain '
      '"holding stable" language unchanged',
      () {
        final summary = bodySilhouetteTrendSummary(
          isBodyContouringProcedure: true,
          rawPayload: _payload(status: 'stable'),
        );

        expect(summary, isNotNull);
        expect(summary!.kind, BodySilhouetteTrendKind.stable);
        expect(summary.headline, 'Silhouette holding stable');
        expect(summary.detail, isNot(contains('Standalone entry')));
      },
    );

    test(
      '"stable" forced by a capture_quality_mismatch shows a distinct '
      'standalone-entry label instead of generic "stable"',
      () {
        final summary = bodySilhouetteTrendSummary(
          isBodyContouringProcedure: true,
          rawPayload: _payload(
            status: 'stable',
            lockReason: 'capture_quality_mismatch',
          ),
        );

        expect(summary, isNotNull);
        expect(summary!.kind, BodySilhouetteTrendKind.stable);
        expect(summary.headline, isNot('Silhouette holding stable'));
        expect(summary.headline, contains('Standalone entry'));
        expect(summary.detail, contains('lighting or capture conditions'));
      },
    );

    test(
      '"stable" forced by a resolution_mismatch shows a distinct '
      'standalone-entry label instead of generic "stable"',
      () {
        final summary = bodySilhouetteTrendSummary(
          isBodyContouringProcedure: true,
          rawPayload: _payload(
            status: 'stable',
            lockReason: 'resolution_mismatch',
          ),
        );

        expect(summary, isNotNull);
        expect(summary!.kind, BodySilhouetteTrendKind.stable);
        expect(summary.headline, isNot('Silhouette holding stable'));
        expect(summary.headline, contains('Standalone entry'));
        expect(summary.detail, contains('resolution'));
      },
    );

    test(
      '"stable" forced by a capture_mode_mismatch shows a distinct '
      'standalone-entry label instead of generic "stable"',
      () {
        final summary = bodySilhouetteTrendSummary(
          isBodyContouringProcedure: true,
          rawPayload: _payload(
            status: 'stable',
            lockReason: 'capture_mode_mismatch',
          ),
        );

        expect(summary, isNotNull);
        expect(summary!.kind, BodySilhouetteTrendKind.stable);
        expect(summary.headline, isNot('Silhouette holding stable'));
        expect(summary.headline, contains('Standalone entry'));
        expect(summary.detail, contains('capture setup'));
      },
    );

    test(
      '"stable" forced by a scale_mismatch shows a distinct standalone-entry '
      'label instead of generic "stable"',
      () {
        final summary = bodySilhouetteTrendSummary(
          isBodyContouringProcedure: true,
          rawPayload: _payload(
            status: 'stable',
            lockReason: 'scale_mismatch',
          ),
        );

        expect(summary, isNotNull);
        expect(summary!.kind, BodySilhouetteTrendKind.stable);
        expect(summary.headline, isNot('Silhouette holding stable'));
        expect(summary.headline, contains('Standalone entry'));
        expect(summary.detail, contains('Framing or distance'));
      },
    );

    test(
      'a missing normalized_area_index key in trend_status defaults to '
      'insufficient_signal rather than throwing',
      () {
        final summary = bodySilhouetteTrendSummary(
          isBodyContouringProcedure: true,
          rawPayload: <String, dynamic>{
            'result': <String, dynamic>{'normalized_area_index': 1.0},
            'trend_status': <String, dynamic>{},
            'trend_deltas': <String, dynamic>{},
          },
        );

        expect(summary, isNotNull);
        expect(summary!.kind, BodySilhouetteTrendKind.insufficientSignal);
      },
    );

    test(
      'a genuinely unrecognized status string (not one of the four known '
      'values) falls back to the stable case rather than throwing',
      () {
        final summary = bodySilhouetteTrendSummary(
          isBodyContouringProcedure: true,
          rawPayload: _payload(status: 'some_future_backend_status'),
        );

        expect(summary, isNotNull);
        expect(summary!.kind, BodySilhouetteTrendKind.stable);
      },
    );

    test('returns null when the procedure is not body-contouring category', () {
      final summary = bodySilhouetteTrendSummary(
        isBodyContouringProcedure: false,
        rawPayload: _payload(status: 'improved', delta: 8.3),
      );

      expect(summary, isNull);
    });

    test('returns null when rawPayload is null (no data yet)', () {
      final summary = bodySilhouetteTrendSummary(
        isBodyContouringProcedure: true,
        rawPayload: null,
      );

      expect(summary, isNull);
    });

    test(
      "returns null when rawPayload has no usable 'result' map (legacy scan, "
      'or the backend call failed at capture time)',
      () {
        expect(
          bodySilhouetteTrendSummary(
            isBodyContouringProcedure: true,
            rawPayload: <String, dynamic>{'status': 'success'},
          ),
          isNull,
        );
        expect(
          bodySilhouetteTrendSummary(
            isBodyContouringProcedure: true,
            rawPayload: <String, dynamic>{'result': 'not-a-map'},
          ),
          isNull,
        );
      },
    );

    test(
      'returns null when neither condition is met, not just when one is',
      () {
        final summary = bodySilhouetteTrendSummary(
          isBodyContouringProcedure: false,
          rawPayload: null,
        );
        expect(summary, isNull);
      },
    );
  });
}
