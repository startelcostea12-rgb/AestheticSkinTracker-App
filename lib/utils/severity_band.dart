/// Kesty-style 5-band severity label for a 0-100 metric score
/// (Clear / Almost Clear / Mild / Moderate / Severe).
///
/// PROVISIONAL: derived from a small 4-photo manual sample against the
/// published Kesty severity scale (Draelos et al. 2025): 0=clear,
/// 1=almost clear (<10% area), 2=mild (10-25%), 3=moderate (25-50%),
/// 4=severe (>50%) -- not a formal validation. The sample used to place
/// these boundaries (all localized_redness scores from real pipeline
/// runs, with an honest visual severity read for each):
///   score=28.7 -> visually Clear/Almost Clear (Kesty 0-1)
///   score=49.3 -> visually Mild-Moderate (Kesty 2), boundary case
///   score=51.3 -> visually Mild-Moderate (Kesty 2), boundary case,
///                 consistent with the above
///   score=72.7 -> visually Severe (Kesty 3-4)
/// Boundaries below are placed at/near the midpoints between these
/// anchors, not the published area-percentage cutoffs directly -- this
/// is a display-only label layered on top of the existing score, it
/// does not change any scoring formula or gating logic. Revisit once
/// more real photo/visual-read pairs exist.
library;

/// Score <= this is "Clear". Not directly sample-derived (the 4-photo
/// sample didn't include a near-zero reading) -- a small provisional
/// floor consistent with Kesty's "0 = clear" definition.
const double kSeverityBandClearMax = 5.0;

/// Score <= this (and > [kSeverityBandClearMax]) is "Almost Clear".
/// Midpoint between the sample's 28.7 (Clear/Almost Clear) and 49.3
/// (Mild-Moderate) readings.
const double kSeverityBandAlmostClearMax = 39.0;

/// Score <= this (and > [kSeverityBandAlmostClearMax]) is "Mild". Placed
/// between the sample's two boundary-case readings, 49.3 and 51.3 --
/// both called "Mild-Moderate" -- effectively splitting them at their
/// midpoint (~50.3, rounded to a clean 50.0).
const double kSeverityBandMildMax = 50.0;

/// Score <= this (and > [kSeverityBandMildMax]) is "Moderate". Placed
/// with margin below the sample's confirmed Severe reading (72.7),
/// scaled roughly proportionally to the published Kesty band-width
/// ratios (Moderate is the widest band in the original 0/10/25/50
/// percent-area scale).
const double kSeverityBandModerateMax = 65.0;

/// Metric keys this provisional mapping currently applies to. Limited to
/// localized_redness for now -- the 4-photo calibration sample above was
/// specifically localized_redness scores. pigment_load support is
/// planned but needs its own calibration sample before reusing these
/// boundaries would be honest.
const Set<String> kSeverityBandSupportedMetricKeys = {'localized_redness'};

/// Returns the 5-band severity label for [score], or null if [score] is
/// null/non-finite. Purely additive display-layer translation -- never
/// use this to gate, filter, or recompute anything; it only formats an
/// already-computed score for display.
String? severityBandLabel(double? score) {
  if (score == null || !score.isFinite) return null;
  if (score <= kSeverityBandClearMax) return 'Clear';
  if (score <= kSeverityBandAlmostClearMax) return 'Almost Clear';
  if (score <= kSeverityBandMildMax) return 'Mild';
  if (score <= kSeverityBandModerateMax) return 'Moderate';
  return 'Severe';
}

/// Convenience formatter: "Mild (32.0)" style display text combining the
/// band label with the raw score -- or just the plain score formatted to
/// one decimal place when [metricKey] isn't in
/// [kSeverityBandSupportedMetricKeys], keeping every other metric's
/// display completely unchanged.
String formatScoreWithSeverityBand(String metricKey, double score) {
  final formattedScore = score.toStringAsFixed(1);
  if (!kSeverityBandSupportedMetricKeys.contains(metricKey)) {
    return formattedScore;
  }
  final band = severityBandLabel(score);
  if (band == null) return formattedScore;
  return '$band ($formattedScore)';
}
