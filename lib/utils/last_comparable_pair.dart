/// The most recent pair of AI scans that were actually compared: the later
/// scan recorded which baseline it was compared against
/// (ai_comparison_baseline_scan_id), both scans share a pose, and none of
/// the six [comparablePairMetricKeys] carries a lock reason on the later
/// scan. Display only -- values and lock reasons are read as stored.
library;

import '../models/scan_history.dart';
import 'ai_comparison_baseline.dart';

/// The six metrics shown for a comparable pair (home card and PDF).
const List<String> comparablePairMetricKeys = <String>[
  'texture_smoothness',
  'pigment_load',
  'skin_tone_radiance_evenness',
  'structural_firmness_elasticity',
  'pore_visibility',
  'localized_redness',
];

const Map<String, String> comparablePairMetricLabels = <String, String>{
  'texture_smoothness': 'Texture',
  'pigment_load': 'Pigment',
  'skin_tone_radiance_evenness': 'Radiance',
  'structural_firmness_elasticity': 'Firmness',
  'pore_visibility': 'Pore visibility',
  'localized_redness': 'Redness',
};

class ComparablePair {
  const ComparablePair({
    required this.latest,
    this.baseline,
    this.lockReasons = const <String, String>{},
  });

  final ScanHistoryEntry latest;

  /// Null when no comparable pair exists: [latest] is then the latest AI
  /// scan alone ("No prior comparable scan.").
  final ScanHistoryEntry? baseline;

  /// Lock reasons the later scan recorded for metrics other than the six
  /// shown (the six themselves are never locked in a comparable pair).
  final Map<String, String> lockReasons;

  bool get hasBaseline => baseline != null;

  double? latestValue(String key) => scanMetricValue(latest, key);
  double? baselineValue(String key) =>
      baseline == null ? null : scanMetricValue(baseline!, key);
}

Map<String, dynamic> _node(Map<String, dynamic>? payload, String key) {
  if (payload == null) return const <String, dynamic>{};
  final direct = payload[key];
  if (direct is Map && direct.isNotEmpty) {
    return Map<String, dynamic>.from(direct);
  }
  final metrics = payload['metrics'];
  if (metrics is Map && metrics[key] is Map) {
    return Map<String, dynamic>.from(metrics[key] as Map);
  }
  return const <String, dynamic>{};
}

/// A scan's stored canonical value for [key] (metric_matrix), or null.
double? scanMetricValue(ScanHistoryEntry scan, String key) {
  final raw = _node(scan.rawPayload, 'metric_matrix')[key];
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  return value != null && value.isFinite ? value : null;
}

Map<String, String> _lockReasons(ScanHistoryEntry scan) => {
  for (final entry in _node(scan.rawPayload, 'trend_lock_reasons').entries)
    if ((entry.value?.toString().trim() ?? '').isNotEmpty)
      entry.key: entry.value.toString().trim(),
};

/// See the library comment. Null when there is no AI scan at all.
ComparablePair? lastComparablePair(Iterable<ScanHistoryEntry> scans) {
  final aiScans =
      scans
          .where(
            (scan) =>
                scan.scanType == ScanHistoryEntry.scanTypeAiAnalysis &&
                scan.rawPayload != null,
          )
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  if (aiScans.isEmpty) return null;
  final byId = {for (final scan in aiScans) scan.id: scan};

  for (final scan in aiScans) {
    final baselineId = scan.rawPayload?[aiComparisonBaselineScanIdKey]
        ?.toString();
    final baseline = baselineId == null ? null : byId[baselineId];
    if (baseline == null || baseline.id == scan.id) continue;
    final pose = scan.poseTemplate?.trim();
    if (pose == null || pose.isEmpty || pose != baseline.poseTemplate?.trim()) {
      continue;
    }
    final locks = _lockReasons(scan);
    if (comparablePairMetricKeys.any(locks.containsKey)) continue;
    return ComparablePair(latest: scan, baseline: baseline, lockReasons: locks);
  }
  return ComparablePair(latest: aiScans.first);
}
