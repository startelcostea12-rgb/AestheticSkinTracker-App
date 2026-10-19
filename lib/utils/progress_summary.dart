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
  final baseline = pair.baseline;
  if (baseline == null) return null;
  if (displayNoVerdictMetrics.contains(key)) return null;
  final payload = pair.latest.rawPayload ?? const <String, dynamic>{};
  Map<dynamic, dynamic> node(String name) {
    final direct = payload[name];
    if (direct is Map) return direct;
    final metrics = payload['metrics'];
    if (metrics is Map && metrics[name] is Map) return metrics[name] as Map;
    return const {};
  }

  final lock = node('trend_lock_reasons')[key]?.toString().trim() ?? '';
  if (lock.isNotEmpty) return null;
  final status = node('trend_status')[key]?.toString().trim().toLowerCase();
  if (status != 'improved' && status != 'worsened' && status != 'stable') {
    return null;
  }
  final current = pair.latestValue(key);
  final previous = pair.baselineValue(key);
  if (current == null || previous == null) return null;
  if (status == 'stable') return 'Stable';
  final floor = displayVerdictNoiseFloors[key];
  if (floor != null &&
      displayStableFloorMetrics.contains(key) &&
      (current - previous).abs() < floor) {
    return 'Stable';
  }
  return status == 'improved' ? 'Improved' : 'Worsened';
}
