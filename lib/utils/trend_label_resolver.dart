import 'trend_lock_reason.dart';

/// Shared alias map from a screen's short/local metric key (e.g. the
/// SkinMetrics 0-10 field name "redness", or a display key like "pores")
/// to the backend's canonical metric key ("localized_redness") used in
/// trend_status/trend_deltas/trend_lock_reasons. Every screen that needs to
/// look up a metric's backend trend verdict by a short key should resolve
/// through this map first, so the mapping stays in one place rather than
/// being redefined (and risking drift) per screen.
const Map<String, String> shortMetricKeyToCanonical = {
  'redness': 'localized_redness',
  'texture': 'texture_smoothness',
  'wrinkle': 'wrinkle_load',
  'wrinkles': 'wrinkle_load',
  'pore': 'pore_visibility',
  'pores': 'pore_visibility',
  'darkSpots': 'pigment_load',
  'pigment': 'pigment_load',
  'elasticity': 'structural_firmness_elasticity',
  'rosacea_intensity': 'rosacea_severity',
  'acne_severity': 'breakout_activity',
};

Map<String, dynamic> _asDynamicMapForTrendPayload(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

/// Extracts the backend's per-metric `trend_status` map from a scan's raw
/// payload (preferring a nested `luxePayload` if present). Any screen with
/// access to a `ScanHistoryEntry.rawPayload` should use this instead of
/// re-implementing its own extraction logic.
Map<String, String> trendStatusMapFromRawPayload(
  Map<String, dynamic>? rawPayload,
) {
  final payload = _asDynamicMapForTrendPayload(rawPayload);
  final nestedLuxe = _asDynamicMapForTrendPayload(payload['luxePayload']);
  final source = nestedLuxe['trend_status'] != null
      ? _asDynamicMapForTrendPayload(nestedLuxe['trend_status'])
      : _asDynamicMapForTrendPayload(payload['trend_status']);
  return source.map((key, value) => MapEntry(key, value.toString()));
}

/// Extracts the backend's per-metric `trend_lock_reasons` map from a scan's
/// raw payload (preferring a nested `luxePayload` if present).
Map<String, String> trendLockReasonMapFromRawPayload(
  Map<String, dynamic>? rawPayload,
) {
  final payload = _asDynamicMapForTrendPayload(rawPayload);
  final nestedLuxe = _asDynamicMapForTrendPayload(payload['luxePayload']);
  final source = nestedLuxe['trend_lock_reasons'] != null
      ? _asDynamicMapForTrendPayload(nestedLuxe['trend_lock_reasons'])
      : _asDynamicMapForTrendPayload(payload['trend_lock_reasons']);
  return source.map((key, value) => MapEntry(key, value.toString()));
}

/// The ONE authorized outcome of a trend comparison. Must always be derived
/// from the backend's `trend_status`, never recomputed locally from raw
/// metric numbers.
enum TrendDirection { improved, worsened, stable, insufficientSignal }

class ResolvedTrendLabel {
  const ResolvedTrendLabel({
    required this.direction,
    required this.label,
    this.deltaPct,
    this.lockReason,
  });

  final TrendDirection direction;

  /// Plain "Improved" / "Worsened" / "Stable" / "Insufficient signal".
  final String label;

  /// Backend-reported percent delta. Null when [direction] is
  /// [TrendDirection.insufficientSignal] (no number is trustworthy there).
  final double? deltaPct;

  /// Raw backend `trend_lock_reason`, only ever set when [direction] is
  /// [TrendDirection.stable]. Null means a genuine small delta.
  final String? lockReason;

  bool get isImproved => direction == TrendDirection.improved;
  bool get isWorsened => direction == TrendDirection.worsened;
  bool get isStable => direction == TrendDirection.stable;
  bool get isInsufficientSignal =>
      direction == TrendDirection.insufficientSignal;

  /// Terse (headline/badge-safe) replacement for [label] when "stable" was
  /// reached via a capture-provenance mismatch gate; null otherwise
  /// (including for a genuine stable — callers keep [label] unchanged then).
  String? get lockHeadline => trendLockReasonHeadline(lockReason);

  /// Short one-line explanation of the same lock; null otherwise.
  String? get lockShortLabel => trendLockReasonShortLabel(lockReason);

  /// Fuller one-sentence explanation of the same lock; null otherwise.
  String? get lockDetail => trendLockReasonDetail(lockReason);
}

/// The ONE authorized way to turn a backend `trend_status` (plus optional
/// `trend_lock_reason` / numeric delta) into user-facing trend wording.
///
/// Every screen that shows "Improved"/"Worsened"/"Stable" must call this
/// instead of recomputing the judgment locally from raw metric numbers —
/// the backend already applied confidence, capture-quality,
/// extraction-path-consistency, and stable-band gates that this function
/// has no visibility into and must never try to replicate.
///
/// Returns null when [trendStatus] is null/empty, meaning the backend
/// supplied no verdict for this comparison. Callers MUST treat a null
/// result as "no trend can be shown yet" — never fall back to comparing
/// two raw numbers themselves.
ResolvedTrendLabel? resolveTrendLabel({
  required String? trendStatus,
  String? trendLockReason,
  double? trendDeltaPct,
}) {
  final normalizedStatus = trendStatus?.trim().toLowerCase();
  if (normalizedStatus == null || normalizedStatus.isEmpty) return null;

  final TrendDirection direction;
  final String label;
  switch (normalizedStatus) {
    case 'improved':
      direction = TrendDirection.improved;
      label = 'Improved';
      break;
    case 'worsened':
      direction = TrendDirection.worsened;
      label = 'Worsened';
      break;
    case 'stable':
      direction = TrendDirection.stable;
      label = 'Stable';
      break;
    case 'insufficient_signal':
      direction = TrendDirection.insufficientSignal;
      label = 'Insufficient signal';
      break;
    default:
      // Unrecognized backend status: treat as no usable verdict rather than
      // guessing a direction.
      direction = TrendDirection.insufficientSignal;
      label = 'Insufficient signal';
  }

  final normalizedLockReason = trendLockReason?.trim();
  final hasLockReason =
      normalizedLockReason != null && normalizedLockReason.isNotEmpty;

  return ResolvedTrendLabel(
    direction: direction,
    label: label,
    deltaPct: direction == TrendDirection.insufficientSignal
        ? null
        : trendDeltaPct,
    lockReason: (direction == TrendDirection.stable && hasLockReason)
        ? normalizedLockReason
        : null,
  );
}
