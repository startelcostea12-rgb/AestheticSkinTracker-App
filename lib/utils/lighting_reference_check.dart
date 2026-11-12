import 'dart:math' as math;

import 'untrusted_trend_metrics.dart';

// Lighting/color reference check for a follow-up vs the baseline night.
//
// Thresholds match main.py's LIGHTING_REF_* constants and the comment
// there. Whole-image mean a*/b* after white balance is the primary
// signal (always computed). lighting_mean_l is the brightness backup.
// Missing references fail open: the check does not lock.

/// After-WB Euclidean color distance hypot(Δa, Δb) at or above this is a
/// mismatch. Same-night non-card p90 was 1.34 and p95 1.78; Nov 7 same
/// session vs baseline was 0.61–0.94; Nov 9 was 7.91–8.33; Nov 10 19:57 was
/// 4.81–4.83. Tightened from 3.0 after Nov 11 21:12 follow-ups at 2.51 and
/// 2.62 passed while pigment still moved past its floor.
const double lightingRefColorAfterWbLimit = 2.0;

/// |Δlighting_mean_l| above this is a mismatch. Same-night max was 6.93.
const double lightingRefMeanLLimit = 8.0;

const String lightingReferenceUnavailableStatus =
    'lighting_reference_unavailable';

double? _finiteDouble(dynamic value) {
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

Map<String, dynamic> _imageQuality(Map<String, dynamic> payload) {
  final direct = payload['image_quality'];
  if (direct is Map) return Map<String, dynamic>.from(direct);
  final metrics = payload['metrics'];
  if (metrics is Map) {
    final nested = metrics['image_quality'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
  }
  return const <String, dynamic>{};
}

/// Diagnostic result of comparing two scans' lighting/color references.
class LightingReferenceCheck {
  const LightingReferenceCheck({
    required this.status,
    this.colorDeltaAfterWb,
    this.lightingMeanLDelta,
    this.unavailableReason,
    this.failedSignals = const <String>[],
  });

  /// "match", "mismatch", "no_baseline", or "lighting_reference_unavailable".
  final String status;
  final double? colorDeltaAfterWb;
  final double? lightingMeanLDelta;
  final String? unavailableReason;
  final List<String> failedSignals;

  bool get isMismatch => status == 'mismatch';
  String? get lockReason => isMismatch ? 'lighting_mismatch' : null;
}

LightingReferenceCheck evaluateLightingReferenceCheck({
  required Map<String, dynamic> currentPayload,
  required Map<String, dynamic> baselinePayload,
}) {
  if (baselinePayload.isEmpty) {
    return const LightingReferenceCheck(status: 'no_baseline');
  }
  final current = _imageQuality(currentPayload);
  final baseline = _imageQuality(baselinePayload);

  final currentA = _finiteDouble(current['whole_image_mean_a_after_wb']);
  final currentB = _finiteDouble(current['whole_image_mean_b_after_wb']);
  final baselineA = _finiteDouble(baseline['whole_image_mean_a_after_wb']);
  final baselineB = _finiteDouble(baseline['whole_image_mean_b_after_wb']);
  final currentL = _finiteDouble(current['lighting_mean_l']);
  final baselineL = _finiteDouble(baseline['lighting_mean_l']);

  final double? colorDelta =
      (currentA != null &&
          currentB != null &&
          baselineA != null &&
          baselineB != null)
      ? math.sqrt(
          math.pow(currentA - baselineA, 2) + math.pow(currentB - baselineB, 2),
        )
      : null;
  final lDelta = (currentL != null && baselineL != null)
      ? (currentL - baselineL).abs()
      : null;

  if (colorDelta == null && lDelta == null) {
    return const LightingReferenceCheck(
      status: lightingReferenceUnavailableStatus,
      unavailableReason: 'missing_lighting_or_color_reference',
    );
  }

  final failed = <String>[];
  if (colorDelta != null && colorDelta >= lightingRefColorAfterWbLimit) {
    failed.add('color_after_wb');
  }
  if (lDelta != null && lDelta > lightingRefMeanLLimit) {
    failed.add('lighting_mean_l');
  }
  return LightingReferenceCheck(
    status: failed.isNotEmpty ? 'mismatch' : 'match',
    colorDeltaAfterWb: colorDelta,
    lightingMeanLDelta: lDelta,
    failedSignals: failed,
  );
}

/// Compact image_quality map the backend lighting check needs. Sends only
/// the always-computed reference fields, not the rest of the quality blob.
Map<String, dynamic> baselineImageQualityForLightingCheck(
  Map<String, dynamic>? payload,
) {
  if (payload == null || payload.isEmpty) return const <String, dynamic>{};
  final quality = _imageQuality(payload);
  final compact = <String, dynamic>{};
  for (final key in <String>[
    'lighting_mean_l',
    'whole_image_mean_a_after_wb',
    'whole_image_mean_b_after_wb',
  ]) {
    final value = _finiteDouble(quality[key]);
    if (value != null) compact[key] = value;
  }
  return compact;
}

/// When the follow-up's lighting/color reference differs from the baseline,
/// clear trend_status and trend_deltas (raw metric numbers stay visible)
/// and set lighting_mismatch. Claim-free metrics, including under-eye, are
/// left unchanged. Missing references fail open.
({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, String> trendLockReasons,
})
lockTrendsForLightingReferenceMismatch({
  required Map<String, String> trendStatus,
  required Map<String, double> trendDeltas,
  required Map<String, String> trendLockReasons,
  required Map<String, dynamic> currentPayload,
  required Map<String, dynamic> baselinePayload,
}) {
  final updatedStatus = Map<String, String>.from(trendStatus);
  final updatedDeltas = Map<String, double>.from(trendDeltas);
  final updatedLockReasons = Map<String, String>.from(trendLockReasons);
  final check = evaluateLightingReferenceCheck(
    currentPayload: currentPayload,
    baselinePayload: baselinePayload,
  );
  if (!check.isMismatch) {
    return (
      trendStatus: updatedStatus,
      trendDeltas: updatedDeltas,
      trendLockReasons: updatedLockReasons,
    );
  }
  for (final metricKey in trendStatus.keys.toList()) {
    if (untrustedTrendVerdictMetrics.contains(metricKey)) continue;
    updatedStatus.remove(metricKey);
    updatedDeltas.remove(metricKey);
    updatedLockReasons[metricKey] = 'lighting_mismatch';
  }
  return (
    trendStatus: updatedStatus,
    trendDeltas: updatedDeltas,
    trendLockReasons: updatedLockReasons,
  );
}
