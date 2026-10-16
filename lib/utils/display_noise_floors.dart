/// Display-only noise floors, in each metric's own 0-100 points, from the
/// 62-pair same-session repeat data, used on the live results views. They
/// never change a score, a backend trend status, or a lock, and are separate
/// from main.py's METRIC_NOISE_FLOOR_2SD and from the saved-status
/// measuredStableNoiseFloors.
///
/// For the metrics in [displayStableFloorMetrics], an unlocked move strictly
/// below the floor shows "Stable" with no percentage, and a move at or above
/// it keeps its own verdict. Any other metric listed here would show its
/// number with no verdict and no percent at or below the floor.
const Map<String, double> displayVerdictNoiseFloors = <String, double>{
  'pigment_load': 2.0,
  'pore_visibility': 2.0,
  'skin_tone_radiance_evenness': 4.5,
  'diffuse_flushing_erythema': 2.0,
  'glabellar_wrinkle_depth': 3.5,
  'structural_firmness_elasticity': 4.0,
  'sebum_excess_oil_gloss': 4.0,
  'texture_smoothness': 3.0,
};

/// Metrics whose display floor means "Stable below the floor" rather than
/// "no verdict at or below the floor" (see [displayVerdictNoiseFloors]).
const Set<String> displayStableFloorMetrics = <String>{
  'pigment_load',
  'pore_visibility',
  'skin_tone_radiance_evenness',
  'diffuse_flushing_erythema',
  'glabellar_wrinkle_depth',
  'structural_firmness_elasticity',
  'sebum_excess_oil_gloss',
  'texture_smoothness',
};

/// Metrics shown on the live results views with their number only: no
/// improved / worsened / stable and no percent. They are still computed,
/// saved, and exported, and a backend lock still shows "Not comparable".
const Set<String> displayNoVerdictMetrics = <String>{
  'under_eye_dark_circle_density',
  'under_eye_texture_density',
  'pore_contraction_index',
  'localized_redness',
  'rosacea_severity',
  'wrinkle_load',
};
