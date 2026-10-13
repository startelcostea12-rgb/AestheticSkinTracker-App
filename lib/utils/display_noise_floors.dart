/// Display-only noise floors, in each metric's own 0-100 points, measured
/// from same-lamp repeat pairs, used on the live results views. They never
/// change a score, a backend trend status, or a lock, and are separate from
/// main.py's METRIC_NOISE_FLOOR_2SD.
///
/// For the metrics in [displayStableFloorMetrics], an unlocked move strictly
/// below the floor shows "Stable" with no percentage -- matching the saved
/// status set by measuredStableNoiseFloors -- and a move at or above it
/// keeps its own verdict. For every other metric here, an unlocked move at
/// or below the floor shows its number with no verdict and no percent.
const Map<String, double> displayVerdictNoiseFloors = <String, double>{
  'texture_smoothness': 2.0,
  'pigment_load': 1.5,
  'skin_tone_radiance_evenness': 3.0,
  'structural_firmness_elasticity': 2.0,
  'pore_visibility': 1.5,
  'sebum_excess_oil_gloss': 3.0,
  'localized_redness': 5.0,
};

/// Metrics whose display floor means "Stable below the floor" rather than
/// "no verdict at or below the floor" (see [displayVerdictNoiseFloors]).
const Set<String> displayStableFloorMetrics = <String>{
  'texture_smoothness',
  'pigment_load',
  'pore_visibility',
  'structural_firmness_elasticity',
};
