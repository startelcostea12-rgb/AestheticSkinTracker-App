/// Default for the `rosacea_score` safety field sent with a scan when the user
/// has no stored `rosaceaSeverity` tracker value.
const double kDefaultRosaceaSafetyScore = 2.5;

/// Resolves the `rosacea_score` safety field from the most recent stored
/// `rosaceaSeverity` value only. Profile / notes / goals text is deliberately
/// never an input: words such as "redness", "flushing", "rosacea" or
/// "vascular" must not raise the score. With nothing stored this returns the
/// existing [kDefaultRosaceaSafetyScore] default; no score is invented.
double resolveRosaceaSafetyScore(double? storedSeverity) {
  return (storedSeverity ?? kDefaultRosaceaSafetyScore).clamp(0.0, 10.0).toDouble();
}
