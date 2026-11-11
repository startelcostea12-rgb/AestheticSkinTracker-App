/// Display-only noise floors, in each metric's own 0-100 points, from the
/// 62-pair same-session repeat data, used on the live results views. They
/// never change a score, a backend trend status, or a lock, and are separate
/// from main.py's METRIC_NOISE_FLOOR_2SD and from the saved-status
/// measuredStableNoiseFloors.
///
/// Scan detail, summary, and cards use [exceedsDisplayClaimBar] as the
/// single verdict source of truth. The numeric values in the tables below
/// are unchanged; when they disagree, the strictest bar wins.
///
/// For the metrics in [displayStableFloorMetrics], an unlocked move strictly
/// below the floor shows "Stable" with no percentage, and a move at or above
/// it keeps its own verdict. Any other metric listed here would show its
/// number with no verdict and no percent at or below the floor.
///
/// The directional display floors below are for cards and summaries only;
/// at or below them an existing verdict reads Stable with no percentage.
/// They do not change saved comparison floors or CSV metadata.
const Map<String, double> directionalDisplayNoiseFloors = <String, double>{
  'texture_smoothness': 4.0,
  'pigment_load': 3.0,
  'pore_visibility': 4.0,
  'skin_tone_radiance_evenness': 4.0,
  'structural_firmness_elasticity': 5.0,
};

const String lampScanDriftSource =
    'Oct 25-Nov 6 lamp scans: daily median, ISO 100 or 125, '
    'Bv 3.0-3.6, gray card not applied.';

const Map<String, double> lampScanDriftSpans = <String, double>{
  'localized_redness': 12.3,
  'rosacea_severity': 9.9,
  'structural_firmness_elasticity': 8.3,
  'skin_tone_radiance_evenness': 7.6,
  'pigment_load': 5.5,
  'texture_smoothness': 5.1,
  'pore_visibility': 4.6,
  'chin_pore_visibility': 3.4,
  'wrinkle_load': 4.2,
  'diffuse_flushing_erythema': 3.4,
};

/// Known conflicts among the unchanged tables (the authoritative claim bar
/// is the maximum, i.e. the strictest [exceedsDisplayClaimBar] rule):
/// - texture_smoothness: display 5.4, lamp 5.1, directional 4.0 → 5.4
/// - pore_visibility: display 3.0, directional 4.0, lamp 4.6 → 4.6
/// - pigment_load: display/directional 3.0, lamp 5.5 → 5.5
/// - skin_tone_radiance_evenness: display/directional 4.0, lamp 7.6 → 7.6
/// - structural_firmness_elasticity: display/directional 5.0, lamp 8.3 → 8.3
/// - glabellar_wrinkle_depth: display 6.4 only → 6.4
/// - measuredStableNoiseFloors has no Elevens entry; live display uses 6.4
bool exceedsDisplayClaimBar(
  String key,
  double current,
  double baseline, {
  double? noiseFloor,
}) {
  if (displayNoVerdictMetrics.contains(key) ||
      !current.isFinite ||
      !baseline.isFinite) {
    return false;
  }
  final bars = <double>[
    if (lampScanDriftSpans[key] case final double span) span,
    if (displayVerdictNoiseFloors[key] case final double floor) floor,
    if (directionalDisplayNoiseFloors[key] case final double floor) floor,
    if (noiseFloor != null && noiseFloor.isFinite) noiseFloor,
  ];
  return bars.every(
    (bar) => current > baseline + bar || baseline > current + bar,
  );
}

/// The largest existing display bar for [key], or null when [key] is
/// claim-free or has no bar. Table values are not changed.
double? displayClaimBar(String key, {double? noiseFloor}) {
  if (displayNoVerdictMetrics.contains(key)) return null;
  final bars = <double>[
    if (lampScanDriftSpans[key] case final double span) span,
    if (displayVerdictNoiseFloors[key] case final double floor) floor,
    if (directionalDisplayNoiseFloors[key] case final double floor) floor,
    if (noiseFloor != null && noiseFloor.isFinite) noiseFloor,
  ];
  if (bars.isEmpty) return null;
  return bars.reduce((a, b) => a > b ? a : b);
}

bool isWithinDirectionalDisplayNoise(
  String key,
  double current,
  double baseline,
) {
  final floor = directionalDisplayNoiseFloors[key];
  return floor != null && (current - baseline).abs() <= floor;
}

bool hasWideDisplayFrameRange({
  double? min,
  double? max,
  double? noiseFloor,
  int? contributors,
}) =>
    contributors != null &&
    contributors >= 2 &&
    min != null &&
    max != null &&
    noiseFloor != null &&
    min.isFinite &&
    max.isFinite &&
    noiseFloor.isFinite &&
    max - min > noiseFloor;

/// Existing display/CSV noise-floor metadata, independent of the visual
/// directional suppression above.
const Map<String, double> displayVerdictNoiseFloors = <String, double>{
  'pigment_load': 3.0,
  'pore_visibility': 3.0,
  'skin_tone_radiance_evenness': 4.0,
  'diffuse_flushing_erythema': 2.0,
  'glabellar_wrinkle_depth': 6.4,
  'structural_firmness_elasticity': 5.0,
  'sebum_excess_oil_gloss': 4.0,
  'texture_smoothness': 5.4,
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
  'rosacea_severity',
  'wrinkle_load',
  'diffuse_flushing_erythema',
};
