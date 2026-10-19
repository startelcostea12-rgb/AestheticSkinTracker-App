/// Metrics whose trend verdict is never kept (the multi-frame aggregate
/// drops their status and delta; a lock reason is still kept). Shared by
/// the AI scan screen (untrustedTrendVerdictMetricKeys) and the results
/// layout, which shows "Recorded" for these instead of "Starting point"
/// when the baseline has a stored value.
const Set<String> untrustedTrendVerdictMetrics = <String>{
  'pore_contraction_index',
  'under_eye_dark_circle_density',
  'under_eye_texture_density',
  'wrinkle_load',
  'rosacea_severity',
  'diffuse_flushing_erythema',
};
