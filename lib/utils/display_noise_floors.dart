/// Display-only noise floors, in each metric's own 0-100 points, measured
/// from same-lamp repeat pairs. On the live results views, an unlocked
/// metric whose absolute change from its baseline is at or below its floor
/// shows its number with no improved/worsened/stable verdict and no
/// percent. These never change a score, a backend trend status, or a lock;
/// they are separate from main.py's METRIC_NOISE_FLOOR_2SD.
const Map<String, double> displayVerdictNoiseFloors = <String, double>{
  'texture_smoothness': 3.0,
  'pigment_load': 3.0,
  'skin_tone_radiance_evenness': 3.0,
  'structural_firmness_elasticity': 4.0,
  'pore_visibility': 2.0,
  'sebum_excess_oil_gloss': 3.0,
  'localized_redness': 5.0,
};
