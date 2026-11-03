/// rawPayload key holding the id of the AI baseline scan this scan was
/// actually compared against when it was analyzed (null when no comparison
/// was made). Absent on scans saved before this field existed.
const String aiComparisonBaselineScanIdKey = 'ai_comparison_baseline_scan_id';

/// rawPayload key saying where [aiComparisonBaselineScanIdKey] came from:
/// [aiComparisonBaselineSourceRegistry] when it was the per-key AI baseline
/// registry's pin, [aiComparisonBaselineSourceEarliestEligible] when no valid
/// pin existed and the earliest eligible scan for the key was used instead.
const String aiComparisonBaselineSourceKey = 'ai_comparison_baseline_source';

const String aiComparisonBaselineSourceRegistry = 'registry';
const String aiComparisonBaselineSourceEarliestEligible = 'earliest_eligible';

/// Records on [payload], at comparison time, which baseline scan the backend
/// comparison used. [baselineScanId] is the scan whose metrics were sent as
/// the comparison baseline (null when none were sent); [registryScanId] is
/// the id the per-key AI baseline registry held for this scan's key.
void recordAiComparisonBaseline(
  Map<String, dynamic> payload, {
  required String? baselineScanId,
  required String? registryScanId,
}) {
  payload[aiComparisonBaselineScanIdKey] = baselineScanId;
  payload[aiComparisonBaselineSourceKey] = baselineScanId == null
      ? null
      : baselineScanId == registryScanId
      ? aiComparisonBaselineSourceRegistry
      : aiComparisonBaselineSourceEarliestEligible;
}

Map<String, dynamic> clearAiComparisonBaselineForReset(
  Map<String, dynamic> payload,
) {
  final cleared = Map<String, dynamic>.from(payload);
  recordAiComparisonBaseline(
    cleared,
    baselineScanId: null,
    registryScanId: null,
  );
  for (final key in const [
    'baseline_metric_matrix',
    'baseline_metric_extraction_paths',
    'baseline_metric_formula_versions',
    'baseline_source_image_width',
    'baseline_source_image_height',
    'trend_status',
    'trend_deltas',
    'trend_lock_reasons',
  ]) {
    cleared.remove(key);
  }
  for (final key in const ['metrics', 'luxePayload']) {
    final nested = cleared[key];
    if (nested is Map) {
      cleared[key] = clearAiComparisonBaselineForReset(
        Map<String, dynamic>.from(nested),
      );
    }
  }
  return cleared;
}
