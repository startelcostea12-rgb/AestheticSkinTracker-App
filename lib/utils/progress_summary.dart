/// Trend words for the progress summary of the last comparable pair. A
/// word is shown only when the later scan's stored verdict is valid under
/// the same rules the live results card uses: no lock reason, a stored
/// improved / worsened / stable status, not a number-only metric
/// (displayNoVerdictMetrics), and a move at or above the display noise
/// floor (below it reads "Stable"). Otherwise null -- values only.
library;

import 'display_noise_floors.dart';
import 'last_comparable_pair.dart';

String? progressTrendLabel(ComparablePair pair, String key) {
  final payload = pair.latest.rawPayload ?? const <String, dynamic>{};
  Map<dynamic, dynamic> node(String name) {
    final direct = payload[name];
    if (direct is Map) return direct;
    final metrics = payload['metrics'];
    if (metrics is Map && metrics[name] is Map) return metrics[name] as Map;
    return const {};
  }

  final lock = node('trend_lock_reasons')[key]?.toString().trim() ?? '';
  if (lock.isNotEmpty) return 'Not comparable';
  if (displayNoVerdictMetrics.contains(key)) return null;
  if (pair.baseline == null) return null;
  double? number(dynamic value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  final multiFrame = node('multi_frame_analysis');
  final ranges = multiFrame['metric_ranges'];
  final range = ranges is Map && ranges[key] is Map
      ? ranges[key] as Map
      : const {};
  final counts = multiFrame['metric_contributor_counts'];
  final count = counts is Map ? counts[key] : range['count'];
  if (hasWideDisplayFrameRange(
    min: number(range['min']),
    max: number(range['max']),
    noiseFloor: number(node('metric_noise_floor_2sd')[key]),
    contributors: number(count)?.toInt(),
  ))
    return 'Not comparable';
  final status = node('trend_status')[key]?.toString().trim().toLowerCase();
  if (status != 'improved' && status != 'worsened' && status != 'stable') {
    return null;
  }
  final current = pair.latestValue(key);
  final previous = pair.baselineValue(key);
  if (current == null || previous == null) return null;
  if (previous == 0.0 && current != 0.0) return null;
  if (!exceedsDisplayClaimBar(
    key,
    current,
    previous,
    noiseFloor: number(node('metric_noise_floor_2sd')[key]),
  )) {
    return null;
  }
  if (status == 'stable') return 'Stable';
  return status == 'improved' ? 'Improved' : 'Worsened';
}
