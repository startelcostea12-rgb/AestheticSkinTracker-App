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
