import 'package:flutter_test/flutter_test.dart';

import 'package:aesthetic_skin_tracker/utils/trend_label_resolver.dart';

void main() {
  group('resolveTrendLabel', () {
    test('returns null when trendStatus is null (no backend verdict)', () {
      expect(resolveTrendLabel(trendStatus: null), isNull);
    });

    test('returns null when trendStatus is empty', () {
      expect(resolveTrendLabel(trendStatus: ''), isNull);
    });

    test('maps "improved" to Improved with the delta', () {
      final resolved = resolveTrendLabel(
        trendStatus: 'improved',
        trendDeltaPct: -12.5,
      );
      expect(resolved!.direction, TrendDirection.improved);
      expect(resolved.label, 'Improved');
      expect(resolved.deltaPct, -12.5);
      expect(resolved.lockReason, isNull);
    });

    test('maps "worsened" to Worsened with the delta', () {
      final resolved = resolveTrendLabel(
        trendStatus: 'worsened',
        trendDeltaPct: 9.0,
      );
      expect(resolved!.direction, TrendDirection.worsened);
      expect(resolved.label, 'Worsened');
      expect(resolved.deltaPct, 9.0);
    });

    test('maps "stable" with no lock reason to a genuine Stable', () {
      final resolved = resolveTrendLabel(trendStatus: 'stable');
      expect(resolved!.direction, TrendDirection.stable);
      expect(resolved.label, 'Stable');
      expect(resolved.lockReason, isNull);
      expect(resolved.lockHeadline, isNull);
    });

    test('maps "stable" + a recognized lock reason to a standalone-entry lock', () {
      final resolved = resolveTrendLabel(
        trendStatus: 'stable',
        trendLockReason: 'capture_quality_mismatch',
      );
      expect(resolved!.direction, TrendDirection.stable);
      expect(resolved.lockReason, 'capture_quality_mismatch');
      expect(resolved.lockHeadline, 'Standalone entry');
      expect(resolved.lockShortLabel, isNotNull);
      expect(resolved.lockDetail, isNotNull);
    });

    test(
      'maps "stable" + "formula_version_mismatch" (a backend scoring-'
      'formula change) to a standalone-entry lock with its own copy',
      () {
        final resolved = resolveTrendLabel(
          trendStatus: 'stable',
          trendLockReason: 'formula_version_mismatch',
        );
        expect(resolved!.direction, TrendDirection.stable);
        expect(resolved.lockReason, 'formula_version_mismatch');
        expect(resolved.lockHeadline, 'Standalone entry');
        expect(resolved.lockShortLabel, isNotNull);
        expect(resolved.lockDetail, isNotNull);
      },
    );

    test(
      'maps "stable" + "frame_range_overlap" (the client-side frame-range '
      'downgrade lock) to a standalone-entry lock with its own copy',
      () {
        final resolved = resolveTrendLabel(
          trendStatus: 'stable',
          trendLockReason: 'frame_range_overlap',
        );
        expect(resolved!.direction, TrendDirection.stable);
        expect(resolved.lockReason, 'frame_range_overlap');
        expect(resolved.lockHeadline, 'Standalone entry');
        expect(resolved.lockShortLabel, isNotNull);
        expect(resolved.lockDetail, isNotNull);
      },
    );

    test(
      'maps "stable" + "below_noise_floor" (the client-side measured-noise-'
      'floor downgrade lock) to a standalone-entry lock with its own copy',
      () {
        final resolved = resolveTrendLabel(
          trendStatus: 'stable',
          trendLockReason: 'below_noise_floor',
        );
        expect(resolved!.direction, TrendDirection.stable);
        expect(resolved.lockReason, 'below_noise_floor');
        expect(resolved.lockHeadline, 'Standalone entry');
        expect(resolved.lockShortLabel, isNotNull);
        expect(resolved.lockDetail, isNotNull);
      },
    );

    test('maps "insufficient_signal" to no usable delta', () {
      final resolved = resolveTrendLabel(
        trendStatus: 'insufficient_signal',
        trendDeltaPct: 40.0,
      );
      expect(resolved!.direction, TrendDirection.insufficientSignal);
      expect(resolved.label, 'Insufficient signal');
      expect(resolved.deltaPct, isNull);
    });

    test('is case/whitespace tolerant', () {
      final resolved = resolveTrendLabel(trendStatus: '  Improved  ');
      expect(resolved!.direction, TrendDirection.improved);
    });

    test('unrecognized status string is treated as insufficient signal, not guessed', () {
      final resolved = resolveTrendLabel(trendStatus: 'bogus_status');
      expect(resolved!.direction, TrendDirection.insufficientSignal);
    });

    test('lock reason is ignored unless status is stable', () {
      final resolved = resolveTrendLabel(
        trendStatus: 'improved',
        trendLockReason: 'capture_quality_mismatch',
      );
      expect(resolved!.lockReason, isNull);
      expect(resolved.lockHeadline, isNull);
    });

    test('stable backend payload never becomes improved or worsened', () {
      final payload = <String, dynamic>{
        'trend_status': {'localized_redness': 'stable'},
        'trend_deltas': {'localized_redness': 42.0},
      };
      final status = trendStatusMapFromRawPayload(payload)['localized_redness'];
      final delta = payload['trend_deltas']['localized_redness'] as double;
      final resolved = resolveTrendLabel(
        trendStatus: status,
        trendDeltaPct: delta,
      );

      expect(resolved!.isStable, isTrue);
      expect(resolved.isImproved, isFalse);
      expect(resolved.isWorsened, isFalse);
    });

    test('locked stable backend payload preserves the lock explanation', () {
      final payload = <String, dynamic>{
        'luxePayload': {
          'trend_status': {'texture_smoothness': 'stable'},
          'trend_lock_reasons': {
            'texture_smoothness': 'resolution_mismatch',
          },
        },
      };
      final status = trendStatusMapFromRawPayload(payload)['texture_smoothness'];
      final reason = trendLockReasonMapFromRawPayload(
        payload,
      )['texture_smoothness'];
      final resolved = resolveTrendLabel(
        trendStatus: status,
        trendLockReason: reason,
      );

      expect(resolved!.label, 'Stable');
      expect(resolved.lockHeadline, 'Standalone entry');
      expect(resolved.isImproved, isFalse);
      expect(resolved.isWorsened, isFalse);
    });
  });
}
