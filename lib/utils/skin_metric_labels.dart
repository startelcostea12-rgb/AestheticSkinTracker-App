// lib/utils/skin_metric_labels.dart
//
// Single source of truth for clinical metric naming across the patient
// portal. Internal SkinMetrics field keys (redness/texture/wrinkle/pore/
// darkSpots/elasticity) are preserved for backwards-compatible persistence —
// this module maps those keys (and a handful of other tracked signals) to
// the clinical labels surfaced in the UI and PDFs.
//
// USE THIS REGISTRY whenever a metric label is shown to the user.

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Canonical clinical metric specification.
class SkinMetricSpec {
  /// Internal key (matches SkinMetrics field name when applicable).
  final String key;

  /// Clinical-style full name shown in the UI (e.g. "Erythema (Redness)").
  final String clinicalName;

  /// Short clinical name suitable for tight cells/labels.
  final String shortName;

  /// Plain-English term used in body copy and helper text.
  final String plainName;

  /// One-line clinical description for tooltips / helper text.
  final String description;

  /// Ultra-short parenthetical used in compact rows (Home, Before & After).
  /// Examples: "wrinkles", "redness", "dark spots".
  final String shortExplanation;

  /// Longer plain-English explanation used in detailed views (Active
  /// Skincare Details, Reports) and tooltips. Examples:
  /// "fine lines & wrinkles", "redness / inflammation".
  final String friendlyDescription;

  /// True when a lower 0–10 value reflects a clinically better state.
  final bool lowerIsBetter;

  final IconData icon;

  const SkinMetricSpec({
    required this.key,
    required this.clinicalName,
    required this.shortName,
    required this.plainName,
    required this.description,
    required this.shortExplanation,
    required this.friendlyDescription,
    required this.lowerIsBetter,
    required this.icon,
  });

  /// Compact display label (e.g. `"Rhytids (wrinkles)"`).
  /// Use in tight rows where space is limited.
  String get compactLabel => '$clinicalName ($shortExplanation)';

  /// Detailed display label (e.g. `"Rhytids (fine lines & wrinkles)"`).
  /// Use in detailed views and reports.
  String get detailedLabel => '$clinicalName ($friendlyDescription)';

  /// Tooltip body — combines the friendly description with the clinical
  /// description for a single well-rounded explanation on long-press /
  /// hover.
  String get tooltip => '$clinicalName — $friendlyDescription.\n\n$description';
}

/// The 10 canonical clinical metrics used across the portal.
class SkinMetricRegistry {
  static const erythema = SkinMetricSpec(
    key: 'redness',
    clinicalName: 'Erythema',
    shortName: 'Erythema',
    plainName: 'redness',
    description:
        'Quantifies cutaneous vascular response — visible redness from '
        'inflammation, post-procedure healing, or rosacea.',
    shortExplanation: 'redness',
    friendlyDescription: 'redness / inflammation',
    lowerIsBetter: true,
    icon: Icons.local_fire_department_outlined,
  );

  static const skinTextureQuality = SkinMetricSpec(
    key: 'texture',
    clinicalName: 'Skin Texture Quality',
    shortName: 'Skin Texture',
    plainName: 'surface texture',
    description:
        'Assesses surface uniformity, smoothness, and absence of '
        'roughness or microscopic irregularity.',
    shortExplanation: 'smoothness',
    friendlyDescription: 'smoothness / roughness',
    lowerIsBetter: true,
    icon: Icons.texture_outlined,
  );

  static const rhytids = SkinMetricSpec(
    key: 'wrinkle',
    clinicalName: 'Rhytids',
    shortName: 'Rhytids',
    plainName: 'fine lines & wrinkles',
    description:
        'Depth, density, and visibility of dynamic and static rhytids — '
        'a key marker of dermal collagen remodelling.',
    shortExplanation: 'wrinkles',
    friendlyDescription: 'fine lines & wrinkles',
    lowerIsBetter: true,
    icon: Icons.waves_outlined,
  );

  static const poreVisibility = SkinMetricSpec(
    key: 'pore',
    clinicalName: 'Pore Visibility',
    shortName: 'Pore Visibility',
    plainName: 'pore prominence',
    description:
        'Prominence of follicular openings — influenced by sebum '
        'production, dermal support, and post-procedure remodelling.',
    shortExplanation: 'pore size',
    friendlyDescription: 'visible pore size',
    lowerIsBetter: true,
    icon: Icons.grain_outlined,
  );

  static const hyperpigmentation = SkinMetricSpec(
    key: 'darkSpots',
    clinicalName: 'Hyperpigmentation',
    shortName: 'Hyperpigmentation',
    plainName: 'dark spots',
    description:
        'Excess or uneven melanin distribution — sun damage, PIH, or '
        'melasma. Improves with photoprotection and tyrosinase inhibitors.',
    shortExplanation: 'dark spots',
    friendlyDescription: 'dark spots / sun damage',
    lowerIsBetter: true,
    icon: Icons.circle_outlined,
  );

  static const skinLaxity = SkinMetricSpec(
    key: 'elasticity',
    clinicalName: 'Face Shape Stability',
    shortName: 'Face Shape Stability',
    plainName: 'face shape stability',
    description:
      'Facial landmark geometry across comparable scans.',
    shortExplanation: 'face shape',
    friendlyDescription: 'face shape stability',
    lowerIsBetter: false,
    icon: Icons.fitness_center_outlined,
  );

  static const skinToneUniformity = SkinMetricSpec(
    key: 'toneUniformity',
    clinicalName: 'Skin Tone Uniformity',
    shortName: 'Tone Uniformity',
    plainName: 'tone evenness',
    description:
        'Evenness of pigment distribution across the visible area — a '
        'composite indicator of clarity and luminosity.',
    shortExplanation: 'even tone',
    friendlyDescription: 'evenness of skin color',
    lowerIsBetter: false,
    icon: Icons.palette_outlined,
  );

  static const hydration = SkinMetricSpec(
    key: 'hydration',
    clinicalName: 'Skin Hydration Level',
    shortName: 'Hydration',
    plainName: 'hydration',
    description:
        'Estimated stratum-corneum water content — reflects barrier '
        'function and topical occlusion.',
    shortExplanation: 'moisture',
    friendlyDescription: 'moisture in the skin',
    lowerIsBetter: false,
    icon: Icons.water_drop_outlined,
  );

  static const inflammatoryResponse = SkinMetricSpec(
    key: 'inflammatoryResponse',
    clinicalName: 'Inflammatory Response',
    shortName: 'Inflammation',
    plainName: 'inflammation',
    description:
        'Composite of erythema, swelling, and visible irritation — '
        'tracks acute-phase response after procedures or actives.',
    shortExplanation: 'irritation',
    friendlyDescription: 'redness & sensitivity',
    lowerIsBetter: true,
    icon: Icons.healing_outlined,
  );

  static const globalSkinQuality = SkinMetricSpec(
    key: 'globalSkinQuality',
    clinicalName: 'Global Skin Quality Score',
    shortName: 'Global Score',
    plainName: 'overall skin quality',
    description:
        'Aggregate clinical index combining tone, texture, laxity, and '
        'inflammatory markers into a single 0–10 quality score.',
    shortExplanation: 'overall health',
    friendlyDescription: 'overall skin health',
    lowerIsBetter: false,
    icon: Icons.auto_awesome_outlined,
  );

  // ─── Acne family ────────────────────────────────────────────────────────
  static const acneSeverity = SkinMetricSpec(
    key: 'acneSeverity',
    clinicalName: 'Acne Severity',
    shortName: 'Acne',
    plainName: 'breakouts',
    description:
        'Composite of inflammatory lesions (papules, pustules) and '
        'comedonal load (blackheads, whiteheads). Responds to consistent '
        'topical actives over 8–12 weeks.',
    shortExplanation: 'breakouts',
    friendlyDescription: 'breakouts & inflammation',
    lowerIsBetter: true,
    icon: Icons.coronavirus_outlined,
  );

  static const cysticAcneSeverity = SkinMetricSpec(
    key: 'cysticAcneSeverity',
    clinicalName: 'Cystic Acne Severity',
    shortName: 'Cystic Acne',
    plainName: 'cystic acne',
    description:
        'Deep, painful, inflamed nodules and cysts beneath the skin. '
        'Typically requires systemic therapy (oral antibiotics, '
        'isotretinoin, or hormonal treatment) for meaningful resolution.',
    shortExplanation: 'deep painful nodules',
    friendlyDescription: 'deep painful nodules & inflammation',
    lowerIsBetter: true,
    icon: Icons.bubble_chart_outlined,
  );

  static const hormonalAcneSeverity = SkinMetricSpec(
    key: 'hormonalAcneSeverity',
    clinicalName: 'Hormonal Acne Severity',
    shortName: 'Hormonal Acne',
    plainName: 'hormonal breakouts',
    description:
        'Cycle-related breakouts concentrated along the lower face, '
        'jawline, chin, and neck. Often flares 7–10 days before menses '
        'and improves with hormonal modulation or spironolactone.',
    shortExplanation: 'cycle-related jawline breakouts',
    friendlyDescription: 'cycle-related jawline & chin breakouts',
    lowerIsBetter: true,
    icon: Icons.calendar_month_outlined,
  );

  // ─── Rosacea family ─────────────────────────────────────────────────────
  static const rosaceaSeverity = SkinMetricSpec(
    key: 'rosaceaSeverity',
    clinicalName: 'Rosacea Severity',
    shortName: 'Rosacea',
    plainName: 'rosacea',
    description:
        'Persistent central-face erythema, papulopustules, and '
        'sensitivity characteristic of rosacea. Managed with gentle '
        'barrier-focused skincare and prescription topicals such as '
        'azelaic acid, ivermectin, or metronidazole.',
    shortExplanation: 'persistent central redness',
    friendlyDescription: 'persistent central-face redness & flushing',
    lowerIsBetter: true,
    icon: Icons.local_florist_outlined,
  );

  static const rosaceaFlushing = SkinMetricSpec(
    key: 'rosaceaFlushing',
    clinicalName: 'Rosacea Flushing Episodes',
    shortName: 'Flushing',
    plainName: 'flushing episodes',
    description:
        'Frequency and intensity of transient flushing — triggered by '
        'heat, spicy food, alcohol, stress, or UV exposure. Trigger '
        'avoidance is the cornerstone of long-term control.',
    shortExplanation: 'flushing frequency',
    friendlyDescription: 'how often the skin flushes red',
    lowerIsBetter: true,
    icon: Icons.thermostat_outlined,
  );

  static const visibleBloodVessels = SkinMetricSpec(
    key: 'visibleBloodVessels',
    clinicalName: 'Visible Blood Vessels',
    shortName: 'Telangiectasia',
    plainName: 'visible vessels',
    description:
        'Telangiectasia — fine, dilated capillaries visible at the '
        'skin surface (commonly on the cheeks and nose). Responds well '
        'to vascular laser or IPL once active inflammation is controlled.',
    shortExplanation: 'visible capillaries',
    friendlyDescription: 'visible broken capillaries (telangiectasia)',
    lowerIsBetter: true,
    icon: Icons.account_tree_outlined,
  );

  static const skinSensitivity = SkinMetricSpec(
    key: 'skinSensitivity',
    clinicalName: 'Skin Sensitivity',
    shortName: 'Sensitivity',
    plainName: 'reactivity',
    description:
        'Reactivity to topicals, environmental triggers, and physical '
        'contact — stinging, burning, tightness, or visible flare. '
        'Improves with barrier repair (ceramides, niacinamide) and '
        'simplifying the routine.',
    shortExplanation: 'stinging & reactivity',
    friendlyDescription: 'stinging, burning, or reactive skin',
    lowerIsBetter: true,
    icon: Icons.flash_on_outlined,
  );

  /// All ten canonical metrics, in their preferred display order.
  static const List<SkinMetricSpec> all = [
    erythema,
    skinTextureQuality,
    rhytids,
    poreVisibility,
    hyperpigmentation,
    skinLaxity,
    skinToneUniformity,
    hydration,
    inflammatoryResponse,
    globalSkinQuality,
  ];

  /// Acne- and rosacea-focused metrics surfaced contextually when the
  /// user is tracking products or procedures targeting those conditions.
  /// These are intentionally NOT in [all] so they only appear where
  /// clinically relevant (Active Skincare Details, Log Recovery Assessment
  /// for acne/rosacea contexts, the Reports/Timeline summary when present).
  static const List<SkinMetricSpec> acneAndRosacea = [
    acneSeverity,
    cysticAcneSeverity,
    hormonalAcneSeverity,
    rosaceaSeverity,
    rosaceaFlushing,
    visibleBloodVessels,
    skinSensitivity,
  ];

  /// Every registered spec — canonical + acne/rosacea — used for label
  /// and tooltip resolution across the app.
  static const List<SkinMetricSpec> registered = [...all, ...acneAndRosacea];

  /// Lookup by internal field key. Tolerant of legacy aliases such as
  /// "wrinkles", "pores", "fineLines" so older persisted data still maps.
  static SkinMetricSpec? byKey(String key) {
    final normalized = key.toLowerCase().trim();
    for (final m in registered) {
      if (m.key.toLowerCase() == normalized) return m;
    }
    switch (normalized) {
      case 'wrinkles':
      case 'fine lines':
      case 'finelines':
      case 'fine_lines':
        return rhytids;
      case 'pores':
        return poreVisibility;
      case 'dark spots':
      case 'darkspots':
      case 'pigmentation':
      case 'hyperpigmentation':
        return hyperpigmentation;
      case 'firmness':
      case 'laxity':
      case 'elasticity':
        return skinLaxity;
      case 'redness':
      case 'erythema':
        return erythema;
      case 'texture':
      case 'skintexture':
        return skinTextureQuality;
      case 'tone':
      case 'toneuniformity':
        return skinToneUniformity;
      case 'barrier':
      case 'hydration':
        return hydration;
      case 'acne':
      case 'acne severity':
      case 'breakouts':
        return acneSeverity;
      case 'cystic':
      case 'cystic acne':
      case 'nodulocystic':
        return cysticAcneSeverity;
      case 'hormonal':
      case 'hormonal acne':
      case 'jawline acne':
        return hormonalAcneSeverity;
      case 'rosacea':
      case 'rosacea severity':
        return rosaceaSeverity;
      case 'flushing':
      case 'rosacea flushing':
        return rosaceaFlushing;
      case 'telangiectasia':
      case 'broken capillaries':
      case 'visible capillaries':
      case 'spider veins':
        return visibleBloodVessels;
      case 'sensitivity':
      case 'reactivity':
      case 'skin reactivity':
        return skinSensitivity;
    }
    return null;
  }

  /// Resolves the clinical full name for a key, falling back to a
  /// sentence-cased version of the key when no match is found.
  static String clinicalNameFor(String key, {String? fallback}) {
    final spec = byKey(key);
    if (spec != null) return spec.clinicalName;
    if (fallback != null) return fallback;
    return key;
  }

  /// Case-insensitive lookup by *any* known label string for a metric:
  /// `clinicalName`, `shortName`, or `plainName`. Also tolerates the
  /// internal key (so existing callers passing 'Erythema', 'redness', or
  /// 'erythema' all resolve correctly). Returns `null` for unknown labels.
  static SkinMetricSpec? byLabel(String label) {
    final n = label.toLowerCase().trim();
    for (final m in registered) {
      if (m.clinicalName.toLowerCase() == n) return m;
      if (m.shortName.toLowerCase() == n) return m;
      if (m.plainName.toLowerCase() == n) return m;
      if (m.key.toLowerCase() == n) return m;
    }
    return byKey(label);
  }

  /// Short parenthetical text for a label (e.g. `"wrinkles"` for `"Rhytids"`).
  /// Returns `null` when the label is not a known clinical metric.
  static String? shortExplanationFor(String label) =>
      byLabel(label)?.shortExplanation;

  /// Full plain-English description for a label
  /// (e.g. `"fine lines & wrinkles"` for `"Rhytids"`).
  /// Returns `null` when the label is not a known clinical metric.
  static String? friendlyDescriptionFor(String label) =>
      byLabel(label)?.friendlyDescription;

  /// Tooltip text suitable for `Tooltip(message: …)`. Combines the friendly
  /// description and the clinical description into a single warm sentence
  /// plus context — keeps the patient-facing tone approachable while still
  /// professional.
  static String? tooltipFor(String label) => byLabel(label)?.tooltip;

  /// Compact display string for a label, e.g. `"Rhytids (wrinkles)"`.
  /// Falls back to the label unchanged when it isn't a known metric.
  static String compactLabelFor(String label) {
    final spec = byLabel(label);
    if (spec == null) return label;
    return spec.compactLabel;
  }

  /// Detailed display string for a label, e.g.
  /// `"Rhytids (fine lines & wrinkles)"`. Falls back to the label
  /// unchanged when it isn't a known metric.
  static String detailedLabelFor(String label) {
    final spec = byLabel(label);
    if (spec == null) return label;
    return spec.detailedLabel;
  }
}

/// Visual delta representation used by metric panels — pairs a directional
/// arrow with the clinically appropriate accent colour.
class MetricDelta {
  final String arrow;
  final String text;
  final Color color;
  final bool improved;
  final bool unchanged;

  const MetricDelta._({
    required this.arrow,
    required this.text,
    required this.color,
    required this.improved,
    required this.unchanged,
  });

  /// Computes the delta between [previous] and [current] using the metric's
  /// directionality. Returns `null` when no previous value is available.
  ///
  /// [previous] and [current] are expected on a 0–10 scale.
  static MetricDelta? compute({
    required double? previous,
    required double current,
    required bool lowerIsBetter,
    int decimals = 1,
  }) {
    if (previous == null) return null;
    final raw = current - previous;
    if (raw.abs() < 0.05) {
      return MetricDelta._(
        arrow: '→',
        text: 'no change',
        color: MyApp.clinicalMuted,
        improved: false,
        unchanged: true,
      );
    }
    final improved = lowerIsBetter ? raw < 0 : raw > 0;
    final arrow = raw > 0 ? '↑' : '↓';
    final amount = raw.abs().toStringAsFixed(decimals);
    return MetricDelta._(
      arrow: arrow,
      text: '$arrow $amount',
      color: improved ? MyApp.clinicalTeal : MyApp.roseGold,
      improved: improved,
      unchanged: false,
    );
  }

  /// As above, but expresses change as a percentage of the baseline.
  static MetricDelta? computePercent({
    required double? previous,
    required double current,
    required bool lowerIsBetter,
    int decimals = 1,
  }) {
    if (previous == null || previous == 0) return null;
    final pct = ((current - previous) / previous) * 100;
    if (pct.abs() < 0.5) {
      return MetricDelta._(
        arrow: '→',
        text: 'no change',
        color: MyApp.clinicalMuted,
        improved: false,
        unchanged: true,
      );
    }
    final improved = lowerIsBetter ? pct < 0 : pct > 0;
    final arrow = pct > 0 ? '↑' : '↓';
    final amount = pct.abs().toStringAsFixed(decimals);
    return MetricDelta._(
      arrow: arrow,
      text: '$arrow $amount%',
      color: improved ? MyApp.clinicalTeal : MyApp.roseGold,
      improved: improved,
      unchanged: false,
    );
  }
}
