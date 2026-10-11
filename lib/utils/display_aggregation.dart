/// Metrics whose displayed current value on the live results views is the
/// median of the scan's frame values instead of their mean, so a single
/// outlier frame does not move the number shown. Display only: the saved
/// metric_matrix (and the exported *_value) stays the mean, and history,
/// Track Procedure, and the progress report are unchanged.
const Set<String> medianDisplayMetricKeys = <String>{
  'wrinkle_load',
  'pore_contraction_index',
  'under_eye_dark_circle_density',
  'under_eye_texture_density',
  'diffuse_flushing_erythema',
  'rosacea_severity',
};

/// How the live results views aggregate [metricKey]'s frames for display.
String liveDisplayAggregationFor(String metricKey) =>
    medianDisplayMetricKeys.contains(metricKey) ? 'median' : 'mean';

/// Median of [values]; the mean of the two middle values for an even count.
/// Null when [values] is empty.
double? medianOf(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return null;
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2.0;
}
