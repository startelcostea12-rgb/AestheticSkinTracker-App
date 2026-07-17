// lib/utils/procedure_metric_set.dart
//
// Procedure-aware clinical metric system.
//
// Exposes [getMetricsForProcedure] — the single entry point used by Home,
// Active Skincare Details, Analysis Results, and Reports to render a clinical
// metric panel that adapts to the patient's procedure type.
//
// The returned [ProcedureMetricSet] contains:
//   • core           — the eight canonical clinical metrics (always shown)
//   • additional     — the procedure-specific add-on metrics (may be empty)
//   • eyebrowLabel   — short caption for the procedure-relevant section
//   • sectionTitle   — title for the procedure-relevant section
//   • categoryLabel  — clinical name of the resolved procedure category
//
// Naming and value derivation are deliberately consistent with the existing
// [SkinMetricRegistry], [procedure_intelligence.dart] derivations, and the
// directionality table in [metric_trend.dart].

import 'package:flutter/material.dart';

import '../models/scan_history.dart';
import 'procedure_intelligence.dart';
import 'skin_metric_labels.dart';

/// Coarse procedure family used to pick the procedure-relevant add-on metrics.
enum ProcedureMetricCategory {
  laserResurfacing,
  microneedling,
  injectables,
  bodyContouring,
  generalSkincare,
}

/// A single procedure-specific add-on metric.
///
/// Values are computed from a [SkinMetrics] snapshot via [valueFrom]. The
/// extractors intentionally lean on the existing six persisted signals so
/// every metric in this file is fully audit-able — no hidden state.
class AdditionalProcedureMetric {
  final String label;
  final String shortName;
  final bool lowerIsBetter;
  final IconData icon;
  final String clinicalContext;
  final double Function(SkinMetrics m) valueFrom;
  final double Function(Map<String, double> rawMetrics, SkinMetrics m)?
  rawValueFrom;

  const AdditionalProcedureMetric({
    required this.label,
    required this.shortName,
    required this.lowerIsBetter,
    required this.icon,
    required this.clinicalContext,
    required this.valueFrom,
    this.rawValueFrom,
  });

  double valueFor(SkinMetrics m, {Map<String, double>? rawMetrics}) {
    if (rawMetrics == null || rawValueFrom == null) return valueFrom(m);
    return rawValueFrom!(rawMetrics, m);
  }
}

/// Result of [getMetricsForProcedure].
class ProcedureMetricSet {
  final List<SkinMetricSpec> core;
  final List<AdditionalProcedureMetric> additional;
  final String eyebrowLabel;
  final String sectionTitle;
  final String categoryLabel;
  final ProcedureMetricCategory category;

  const ProcedureMetricSet({
    required this.core,
    required this.additional,
    required this.eyebrowLabel,
    required this.sectionTitle,
    required this.categoryLabel,
    required this.category,
  });

  bool get hasAdditional => additional.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Core metrics — the eight always-shown canonical clinical signals.
// ---------------------------------------------------------------------------

const List<SkinMetricSpec> _coreMetrics = [
  SkinMetricRegistry.erythema,
  SkinMetricRegistry.skinTextureQuality,
  SkinMetricRegistry.rhytids,
  SkinMetricRegistry.poreVisibility,
  SkinMetricRegistry.hyperpigmentation,
  SkinMetricRegistry.skinLaxity,
  SkinMetricRegistry.hydration,
  SkinMetricRegistry.globalSkinQuality,
];

double _clamp10(double v) => v.clamp(0.0, 10.0).toDouble();

// ---------------------------------------------------------------------------
// Add-on metric definitions
// ---------------------------------------------------------------------------

// Laser resurfacing (Halo, Fraxel, CO₂, IPL, chemical peel).
const _laserAdditional = <AdditionalProcedureMetric>[
  AdditionalProcedureMetric(
    label: 'Swelling',
    shortName: 'Swelling',
    lowerIsBetter: true,
    icon: Icons.bubble_chart_outlined,
    clinicalContext:
        'Swelling is expected in early laser recovery and typically peaks 24–72 h post-treatment.',
    valueFrom: _swelling,
  ),
  AdditionalProcedureMetric(
    label: 'Redness Intensity',
    shortName: 'Redness',
    lowerIsBetter: true,
    icon: Icons.local_fire_department_outlined,
    clinicalContext:
        'Post-laser erythema reflects controlled thermal injury — it should steadily fade across the first 7–10 days.',
    valueFrom: _rednessIntensity,
  ),
  AdditionalProcedureMetric(
    label: 'Healing Progress',
    shortName: 'Healing',
    lowerIsBetter: false,
    icon: Icons.healing_outlined,
    clinicalContext:
        'A composite of declining inflammation and improving texture — tracks barrier re-epithelialization.',
    valueFrom: _healingProgress,
  ),
];

// Microneedling / RF Microneedling (Morpheus8, SkinPen, Vivace).
const _microneedlingAdditional = <AdditionalProcedureMetric>[
  AdditionalProcedureMetric(
    label: 'Inflammatory Response',
    shortName: 'Inflammation',
    lowerIsBetter: true,
    icon: Icons.whatshot_outlined,
    clinicalContext:
        'Acute inflammation is the trigger for neocollagenesis — it should resolve within 48–72 h.',
    valueFrom: _inflammatoryResponse,
  ),
  AdditionalProcedureMetric(
    label: 'Texture Recovery',
    shortName: 'Texture Recovery',
    lowerIsBetter: false,
    icon: Icons.auto_fix_high_outlined,
    clinicalContext:
        'Surface smoothing as dermal remodelling progresses — expect meaningful gains around week 4–6.',
    valueFrom: _textureRecovery,
  ),
  AdditionalProcedureMetric(
    label: 'Pore Refinement',
    shortName: 'Pore Refinement',
    lowerIsBetter: false,
    icon: Icons.blur_on_outlined,
    clinicalContext:
        'Follicular tightening from collagen remodelling — most pronounced after the second or third session.',
    valueFrom: _poreRefinement,
  ),
];

// Injectables (Botox, Dysport, Xeomin, fillers).
const _injectablesAdditional = <AdditionalProcedureMetric>[
  AdditionalProcedureMetric(
    label: 'Facial Volume Changes',
    shortName: 'Volume',
    lowerIsBetter: false,
    icon: Icons.face_retouching_natural_outlined,
    clinicalContext:
        'Filler volumization typically settles by day 14 as bound water and tissue integration equalize.',
    valueFrom: _facialVolumeChanges,
  ),
  AdditionalProcedureMetric(
    label: 'Symmetry',
    shortName: 'Symmetry',
    lowerIsBetter: false,
    icon: Icons.balance_outlined,
    clinicalContext:
        'Even distribution across both sides of the face is the key clinical marker of a successful result.',
    valueFrom: _symmetry,
  ),
  AdditionalProcedureMetric(
    label: 'Jawline Definition',
    shortName: 'Jawline',
    lowerIsBetter: false,
    icon: Icons.architecture_outlined,
    clinicalContext:
        'Lower-face contouring sharpens as filler integrates and surrounding tissue lifts.',
    valueFrom: _jawlineDefinition,
  ),
  AdditionalProcedureMetric(
    label: 'Under-Eye Darkness',
    shortName: 'Under-Eye',
    lowerIsBetter: true,
    icon: Icons.remove_red_eye_outlined,
    clinicalContext:
        'Tear-trough shadowing reduces as filler corrects volume loss and improves light reflection.',
    valueFrom: _underEyeDarkness,
  ),
];

// Body contouring (BBL, liposuction, tummy tuck, arm/thigh contouring).
const _bodyContouringAdditional = <AdditionalProcedureMetric>[
  AdditionalProcedureMetric(
    label: 'Fat Retention',
    shortName: 'Fat Retention',
    lowerIsBetter: false,
    icon: Icons.bubble_chart_outlined,
    clinicalContext:
        'For fat-transfer procedures, higher retention suggests better volume preservation; for non-transfer body procedures this is a contour-stability proxy.',
    valueFrom: _fatRetention,
    rawValueFrom: _fatRetentionFromRaw,
  ),
  AdditionalProcedureMetric(
    label: 'Swelling',
    shortName: 'Swelling',
    lowerIsBetter: true,
    icon: Icons.water_drop_outlined,
    clinicalContext:
        'Post-procedure swelling should trend down with time, compression compliance, walking, and surgeon-approved lymphatic care.',
    valueFrom: _bodySwelling,
    rawValueFrom: _bodySwellingFromRaw,
  ),
  AdditionalProcedureMetric(
    label: 'Skin Laxity / Firmness',
    shortName: 'Firmness',
    lowerIsBetter: false,
    icon: Icons.fitness_center_outlined,
    clinicalContext:
        'Firmness reflects tissue support and skin retraction as swelling resolves and collagen remodels.',
    valueFrom: _bodyFirmness,
    rawValueFrom: _bodyFirmnessFromRaw,
  ),
  AdditionalProcedureMetric(
    label: 'Texture / Smoothness',
    shortName: 'Smoothness',
    lowerIsBetter: false,
    icon: Icons.auto_fix_high_outlined,
    clinicalContext:
        'Smoothness captures surface evenness and temporary firmness or fibrosis after body contouring.',
    valueFrom: _bodySmoothness,
    rawValueFrom: _bodySmoothnessFromRaw,
  ),
  AdditionalProcedureMetric(
    label: 'Scarring / Bruising',
    shortName: 'Bruising',
    lowerIsBetter: true,
    icon: Icons.healing_outlined,
    clinicalContext:
        'Bruising and incision discoloration should gradually fade; sudden worsening should be reviewed by the surgical team.',
    valueFrom: _scarringBruising,
    rawValueFrom: _scarringBruisingFromRaw,
  ),
  AdditionalProcedureMetric(
    label: 'Hyperpigmentation',
    shortName: 'Pigment',
    lowerIsBetter: true,
    icon: Icons.tonality_outlined,
    clinicalContext:
        'Tracks post-inflammatory pigment around bruised, irritated, or incision-adjacent areas.',
    valueFrom: _bodyHyperpigmentation,
    rawValueFrom: _bodyHyperpigmentationFromRaw,
  ),
  AdditionalProcedureMetric(
    label: 'Overall Healing Score',
    shortName: 'Healing',
    lowerIsBetter: false,
    icon: Icons.monitor_heart_outlined,
    clinicalContext:
        'Composite recovery score combining swelling, firmness, smoothness, bruising, pigment, and contour stability.',
    valueFrom: _overallBodyHealing,
    rawValueFrom: _overallBodyHealingFromRaw,
  ),
];

// General skincare (no procedure, OTC actives, retinoids, daily routine).
const _skincareAdditional = <AdditionalProcedureMetric>[
  AdditionalProcedureMetric(
    label: 'Acne Severity',
    shortName: 'Acne',
    lowerIsBetter: true,
    icon: Icons.coronavirus_outlined,
    clinicalContext:
        'Composite of active inflammation and surface irregularity — responds to consistent actives over 8–12 weeks.',
    valueFrom: _acneSeverity,
  ),
  AdditionalProcedureMetric(
    label: 'Skin Tone Uniformity',
    shortName: 'Tone Uniformity',
    lowerIsBetter: false,
    icon: Icons.palette_outlined,
    clinicalContext:
        'Even pigment distribution across the face — improves with SPF compliance and tyrosinase inhibitors.',
    valueFrom: _skinToneUniformity,
  ),
];

// Acne-focused add-ons — surfaced when the user is tracking acne-related
// products (BPO, salicylic acid, tretinoin, adapalene, isotretinoin,
// niacinamide, azelaic acid, spironolactone) or an acne-focused procedure.
const _acneAdditional = <AdditionalProcedureMetric>[
  AdditionalProcedureMetric(
    label: 'Acne Severity',
    shortName: 'Acne',
    lowerIsBetter: true,
    icon: Icons.coronavirus_outlined,
    clinicalContext:
        'Composite of inflammatory lesions and comedonal load — responds to consistent topical actives over 8–12 weeks.',
    valueFrom: _acneSeverity,
  ),
  AdditionalProcedureMetric(
    label: 'Cystic Acne Severity',
    shortName: 'Cystic Acne',
    lowerIsBetter: true,
    icon: Icons.bubble_chart_outlined,
    clinicalContext:
        'Deep painful nodules — typically need systemic therapy. Track tenderness and node count, not just surface appearance.',
    valueFrom: _cysticAcneSeverity,
  ),
  AdditionalProcedureMetric(
    label: 'Hormonal Acne Severity',
    shortName: 'Hormonal Acne',
    lowerIsBetter: true,
    icon: Icons.calendar_month_outlined,
    clinicalContext:
        'Cycle-related jawline / chin breakouts — flares 7–10 days pre-menses; improves with hormonal modulation.',
    valueFrom: _hormonalAcneSeverity,
  ),
  AdditionalProcedureMetric(
    label: 'Skin Sensitivity',
    shortName: 'Sensitivity',
    lowerIsBetter: true,
    icon: Icons.flash_on_outlined,
    clinicalContext:
        'Many acne actives (retinoids, BPO, acids) compromise the barrier — watch reactivity and pace introductions.',
    valueFrom: _skinSensitivity,
  ),
];

// Rosacea-focused add-ons — surfaced when the user has a rosacea
// diagnosis context or is tracking rosacea-relevant products (azelaic
// acid, ivermectin, metronidazole, brimonidine, low-dose doxycycline).
const _rosaceaAdditional = <AdditionalProcedureMetric>[
  AdditionalProcedureMetric(
    label: 'Rosacea Severity',
    shortName: 'Rosacea',
    lowerIsBetter: true,
    icon: Icons.local_florist_outlined,
    clinicalContext:
        'Persistent central-face erythema and papulopustules — managed with gentle barrier care and prescription topicals.',
    valueFrom: _rosaceaSeverity,
  ),
  AdditionalProcedureMetric(
    label: 'Rosacea Flushing Episodes',
    shortName: 'Flushing',
    lowerIsBetter: true,
    icon: Icons.thermostat_outlined,
    clinicalContext:
        'Transient flushing — triggered by heat, spicy food, alcohol, stress, or UV. Trigger journaling is the strongest tool.',
    valueFrom: _rosaceaFlushing,
  ),
  AdditionalProcedureMetric(
    label: 'Visible Blood Vessels',
    shortName: 'Telangiectasia',
    lowerIsBetter: true,
    icon: Icons.account_tree_outlined,
    clinicalContext:
        'Fine dilated capillaries — responds well to vascular laser or IPL once inflammation is well controlled.',
    valueFrom: _visibleBloodVessels,
  ),
  AdditionalProcedureMetric(
    label: 'Skin Sensitivity',
    shortName: 'Sensitivity',
    lowerIsBetter: true,
    icon: Icons.flash_on_outlined,
    clinicalContext:
        'Reactivity to topicals and triggers — the most actionable rosacea signal. Improves with strict barrier-first routines.',
    valueFrom: _skinSensitivity,
  ),
];

// ---------------------------------------------------------------------------
// Value extractors — pure functions over the six persisted SkinMetrics fields.
// ---------------------------------------------------------------------------

double _swelling(SkinMetrics m) =>
    _clamp10(m.redness * 0.65 + m.texture * 0.35);

double _rednessIntensity(SkinMetrics m) => _clamp10(m.redness);

double _healingProgress(SkinMetrics m) =>
    _clamp10(10 - (m.redness * 0.55 + m.texture * 0.25 + m.wrinkle * 0.20));

double _inflammatoryResponse(SkinMetrics m) =>
    _clamp10(m.redness * 0.70 + m.texture * 0.30);

double _textureRecovery(SkinMetrics m) => _clamp10(10 - m.texture);

double _poreRefinement(SkinMetrics m) => _clamp10(10 - m.pore);

double _facialVolumeChanges(SkinMetrics m) =>
    _clamp10(m.elasticity * 0.7 + (10 - m.wrinkle) * 0.3);

double _symmetry(SkinMetrics m) =>
    _clamp10(10 - (m.texture * 0.5 + m.wrinkle * 0.5));

double _jawlineDefinition(SkinMetrics m) =>
    _clamp10(m.elasticity * 0.8 + (10 - m.texture) * 0.2);

double _underEyeDarkness(SkinMetrics m) => _clamp10(m.darkSpots);

double _acneSeverity(SkinMetrics m) =>
    _clamp10(m.redness * 0.55 + m.texture * 0.35 + m.pore * 0.10);

double _cysticAcneSeverity(SkinMetrics m) =>
    _clamp10(m.redness * 0.50 + m.texture * 0.45 + m.pore * 0.05);

double _hormonalAcneSeverity(SkinMetrics m) =>
    _clamp10(m.redness * 0.45 + m.texture * 0.40 + m.pore * 0.15);

double _rosaceaSeverity(SkinMetrics m) =>
    _clamp10(m.redness * 0.75 + m.texture * 0.25);

double _rosaceaFlushing(SkinMetrics m) =>
    _clamp10(m.redness * 0.85 + m.texture * 0.15);

double _visibleBloodVessels(SkinMetrics m) =>
    _clamp10(m.redness * 0.65 + (10 - m.elasticity) * 0.35);

double _skinSensitivity(SkinMetrics m) =>
    _clamp10(m.redness * 0.55 + m.texture * 0.30 + (10 - m.elasticity) * 0.15);

double _skinToneUniformity(SkinMetrics m) => _clamp10(10 - m.darkSpots);

double _scoreFromRaw(Map<String, double> raw, List<String> keys) {
  for (final key in keys) {
    final value = raw[key];
    if (value == null) continue;
    return (value <= 1.0 ? value * 10 : value).clamp(0, 10).toDouble();
  }
  return double.nan;
}

double _rawOrDerived(
  Map<String, double> raw,
  SkinMetrics m,
  List<String> keys,
  double Function(SkinMetrics m) fallback,
) {
  final rawScore = _scoreFromRaw(raw, keys);
  return rawScore.isNaN ? fallback(m) : rawScore;
}

double _bodySwelling(SkinMetrics m) =>
    _clamp10(m.redness * 0.50 + m.texture * 0.30 + m.darkSpots * 0.20);

double _bodyFirmness(SkinMetrics m) => _clamp10(
  m.elasticity * 0.55 + (10 - m.texture) * 0.30 + (10 - m.wrinkle) * 0.15,
);

double _bodySmoothness(SkinMetrics m) => _clamp10(10 - m.texture);

double _scarringBruising(SkinMetrics m) =>
    _clamp10(m.darkSpots * 0.45 + m.redness * 0.35 + m.texture * 0.20);

double _bodyHyperpigmentation(SkinMetrics m) => _clamp10(m.darkSpots);

double _fatRetention(SkinMetrics m) => _clamp10(
  10 -
      (_bodySwelling(m) * 0.30 +
          _scarringBruising(m) * 0.20 +
          m.texture * 0.15 +
          (10 - m.elasticity) * 0.20),
);

double _overallBodyHealing(SkinMetrics m) {
  final swelling = _bodySwelling(m);
  final firmness = _bodyFirmness(m);
  final smoothness = _bodySmoothness(m);
  final bruising = _scarringBruising(m);
  final pigment = _bodyHyperpigmentation(m);
  final retention = _fatRetention(m);
  return _clamp10(
    (10 - swelling) * 0.22 +
        firmness * 0.18 +
        smoothness * 0.16 +
        (10 - bruising) * 0.18 +
        (10 - pigment) * 0.12 +
        retention * 0.14,
  );
}

double _fatRetentionFromRaw(Map<String, double> raw, SkinMetrics m) =>
    _rawOrDerived(raw, m, const [
      'fatRetention',
      'fat_retention',
    ], _fatRetention);

double _bodySwellingFromRaw(Map<String, double> raw, SkinMetrics m) =>
    _rawOrDerived(raw, m, const ['swelling', 'edema'], _bodySwelling);

double _bodyFirmnessFromRaw(Map<String, double> raw, SkinMetrics m) =>
    _rawOrDerived(raw, m, const [
      'firmness',
      'skinFirmness',
      'bodyFirmness',
      'skinLaxityFirmness',
    ], _bodyFirmness);

double _bodySmoothnessFromRaw(Map<String, double> raw, SkinMetrics m) =>
    _rawOrDerived(raw, m, const [
      'smoothness',
      'bodySmoothness',
      'textureSmoothness',
    ], _bodySmoothness);

double _scarringBruisingFromRaw(Map<String, double> raw, SkinMetrics m) =>
    _rawOrDerived(raw, m, const [
      'scarringBruising',
      'scarring_bruising',
      'bruising',
      'scarring',
    ], _scarringBruising);

double _bodyHyperpigmentationFromRaw(Map<String, double> raw, SkinMetrics m) =>
    _rawOrDerived(raw, m, const [
      'hyperpigmentation',
      'pigment',
      'pigmentation',
      'darkSpots',
    ], _bodyHyperpigmentation);

double _overallBodyHealingFromRaw(Map<String, double> raw, SkinMetrics m) =>
    _rawOrDerived(raw, m, const [
      'overallHealingScore',
      'overall_healing_score',
      'bodyHealingScore',
    ], _overallBodyHealing);

// ---------------------------------------------------------------------------
// Category resolution
// ---------------------------------------------------------------------------

/// Resolves the coarse [ProcedureMetricCategory] for a procedure-type string.
///
/// Distinguishes Halo/Laser resurfacing from Microneedling/RF — both of which
/// the existing [ProcedureIntelligence] groups under [ProcedureCategory.laserPeel].
ProcedureMetricCategory resolveProcedureMetricCategory(String? procedureType) {
  final raw = procedureType?.trim().toLowerCase();
  if (raw == null || raw.isEmpty) {
    return ProcedureMetricCategory.generalSkincare;
  }

  if (ProcedureIntelligence.categoryFor(procedureType) ==
      ProcedureCategory.bodyContouring) {
    return ProcedureMetricCategory.bodyContouring;
  }

  // Microneedling family — check BEFORE laser so "rf microneedling" doesn't
  // mis-route via the "rf " keyword.
  if (raw.contains('microneedl') ||
      raw.contains('morpheus') ||
      raw.contains('skinpen') ||
      raw.contains('vivace') ||
      raw.contains('secret rf')) {
    return ProcedureMetricCategory.microneedling;
  }

  // Laser resurfacing family.
  if (raw.contains('halo') ||
      raw.contains('laser') ||
      raw.contains('fraxel') ||
      raw.contains('co2') ||
      raw.contains('ipl') ||
      raw.contains(
        'bbl ',
      ) || // BroadBand Light (intense pulsed) — trailing space avoids BBL surgery.
      raw.contains('peel') ||
      raw.contains('resurfac')) {
    return ProcedureMetricCategory.laserResurfacing;
  }

  // Injectables.
  if (raw.contains('botox') ||
      raw.contains('dysport') ||
      raw.contains('xeomin') ||
      raw.contains('jeuveau') ||
      raw.contains('filler') ||
      raw.contains('injectabl') ||
      raw.contains('sculptra') ||
      raw.contains('radiesse') ||
      raw.contains('kybella') ||
      raw.contains('toxin')) {
    return ProcedureMetricCategory.injectables;
  }

  return ProcedureMetricCategory.generalSkincare;
}

String _sectionTitleFor(ProcedureMetricCategory c) {
  switch (c) {
    case ProcedureMetricCategory.laserResurfacing:
      return 'Laser Recovery Metrics';
    case ProcedureMetricCategory.microneedling:
      return 'Microneedling Recovery Metrics';
    case ProcedureMetricCategory.injectables:
      return 'Injectable-Specific Metrics';
    case ProcedureMetricCategory.bodyContouring:
      return 'Body Recovery Metrics';
    case ProcedureMetricCategory.generalSkincare:
      return 'Skincare Routine Metrics';
  }
}

String _categoryLabelFor(ProcedureMetricCategory c) {
  switch (c) {
    case ProcedureMetricCategory.laserResurfacing:
      return 'Laser Resurfacing';
    case ProcedureMetricCategory.microneedling:
      return 'Microneedling';
    case ProcedureMetricCategory.injectables:
      return 'Injectables';
    case ProcedureMetricCategory.bodyContouring:
      return 'Body Contouring';
    case ProcedureMetricCategory.generalSkincare:
      return 'General Skincare';
  }
}

List<AdditionalProcedureMetric> _additionalFor(ProcedureMetricCategory c) {
  switch (c) {
    case ProcedureMetricCategory.laserResurfacing:
      return _laserAdditional;
    case ProcedureMetricCategory.microneedling:
      return _microneedlingAdditional;
    case ProcedureMetricCategory.injectables:
      return _injectablesAdditional;
    case ProcedureMetricCategory.bodyContouring:
      return _bodyContouringAdditional;
    case ProcedureMetricCategory.generalSkincare:
      return _skincareAdditional;
  }
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Returns the procedure-aware metric set for [procedureType].
///
/// The result always contains the eight core canonical clinical metrics,
/// plus a procedure-specific list of add-on metrics when the procedure type
/// resolves to a known family (laser, microneedling, injectables, skincare).
///
/// When [skincareContext] indicates the user is tracking acne- or
/// rosacea-relevant products / concerns, the matching acne or rosacea
/// add-on metrics are *prepended* to the additional list so they appear
/// first — clinical signals the user is actively managing.
ProcedureMetricSet getMetricsForProcedure(
  String? procedureType, {
  SkincareContext? skincareContext,
}) {
  final category = resolveProcedureMetricCategory(procedureType);
  final base = _additionalFor(category);

  final ctx =
      skincareContext ?? SkincareContext.detect(procedureType: procedureType);

  final contextual = <AdditionalProcedureMetric>[];
  if (ctx.hasAcne) {
    contextual.addAll(_acneAdditional);
  }
  if (ctx.hasRosacea) {
    contextual.addAll(_rosaceaAdditional);
  }

  // Dedupe by label so an acne context layered on the general-skincare
  // bucket doesn't duplicate "Acne Severity" / "Skin Sensitivity".
  final seen = <String>{};
  final merged = <AdditionalProcedureMetric>[];
  for (final m in [...contextual, ...base]) {
    if (seen.add(m.label)) merged.add(m);
  }

  return ProcedureMetricSet(
    core: category == ProcedureMetricCategory.bodyContouring
        ? const []
        : _coreMetrics,
    additional: merged,
    eyebrowLabel: 'Procedure-Relevant Metrics',
    sectionTitle: _sectionTitleFor(category),
    categoryLabel: _categoryLabelFor(category),
    category: category,
  );
}

// ---------------------------------------------------------------------------
// Skincare context detection — keyword-based, deliberately conservative.
// ---------------------------------------------------------------------------

/// Lightweight context flags used to surface acne / rosacea metrics only
/// when the user is actually engaging with those concerns.
///
/// Detect from any combination of:
///   • the active procedure type ("Acne Treatment", "Rosacea Therapy", …),
///   • currently-tracked skincare product names / ingredients,
///   • the user's profile-level skin concerns.
class SkincareContext {
  final bool hasAcne;
  final bool hasRosacea;

  const SkincareContext({this.hasAcne = false, this.hasRosacea = false});

  bool get isEmpty => !hasAcne && !hasRosacea;

  static const _acneKeywords = <String>[
    'acne',
    'breakout',
    'pimple',
    'blemish',
    'comedone',
    'blackhead',
    'whitehead',
    'cystic',
    'nodular',
    'hormonal',
    'benzoyl peroxide',
    'salicylic',
    'tretinoin',
    'retin-a',
    'retin a',
    'adapalene',
    'differin',
    'isotretinoin',
    'accutane',
    'spironolactone',
    'niacinamide',
    'clindamycin',
    'epiduo',
    'tazarotene',
    'azelaic', // shared with rosacea — context-aware below
  ];

  static const _rosaceaKeywords = <String>[
    'rosacea',
    'flushing',
    'telangiectasia',
    'broken capillar',
    'ivermectin',
    'soolantra',
    'metronidazole',
    'metrogel',
    'metrocream',
    'mirvaso',
    'brimonidine',
    'rhofade',
    'oxymetazoline',
    'finacea',
    'azelaic',
    'doxycycline',
    'oracea',
    'sensitive skin',
    'reactive skin',
  ];

  /// Detect context from any combination of inputs. All parameters are
  /// optional — pass whatever signal is available at the call site.
  factory SkincareContext.detect({
    String? procedureType,
    Iterable<String> productNames = const [],
    Iterable<String> productIngredients = const [],
    Iterable<String> profileConcerns = const [],
  }) {
    final corpus = <String>[
      if (procedureType != null) procedureType,
      ...productNames,
      ...productIngredients,
      ...profileConcerns,
    ].map((s) => s.toLowerCase()).toList(growable: false);

    if (corpus.isEmpty) return const SkincareContext();

    bool matches(List<String> keywords) {
      for (final entry in corpus) {
        for (final kw in keywords) {
          if (entry.contains(kw)) return true;
        }
      }
      return false;
    }

    return SkincareContext(
      hasAcne: matches(_acneKeywords),
      hasRosacea: matches(_rosaceaKeywords),
    );
  }
}
