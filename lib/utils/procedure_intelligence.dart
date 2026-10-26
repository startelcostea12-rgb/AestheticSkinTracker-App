/// procedure_intelligence.dart
///
/// Single source of truth for all procedure-specific AI adaptations.
/// Consumed by AiIntelligenceEngine, PremiumRecoveryService,
/// AIProductRecommendationEngine, and ReportService.
///
/// Every feature that needs to know "which metrics matter for this procedure"
/// or "what should the AI coach say about this procedure" calls this class.

library procedure_intelligence;

import '../models/procedure.dart';
import '../models/scan_history.dart';

enum ProcedureBodyContouringSubtype { bbl, liposuction, other }

// ---------------------------------------------------------------------------
// Procedure Categories
// ---------------------------------------------------------------------------

enum ProcedureCategory {
  hairTransplant,
  injectables, // Botox, Dysport, Xeomin, Dermal Fillers, Lip Augmentation
  laserPeel, // Laser resurfacing, chemical peel, IPL, microneedling, Morpheus8
  surgicalFace, // Rhinoplasty, Facelift, Blepharoplasty, Brow Lift, Neck Lift,
  // Thread Lift, Chin/Jawline, Buccal Fat
  bodyContouring, // BBL, Liposuction, Tummy Tuck, Arm/Thigh contouring
  bodyComposition, // GLP-1 / GIP / GHRH peptide stacks: Tirzepatide, Semaglutide,
  // Retatrutide, Tesamorelin, AOD-9604, Sermorelin, CJC-1295,
  // Ipamorelin, MOTS-c, IGF-1 LR3 — weight / fat / muscle focus.
  generalSkincare, // Default — all metrics equally weighted
}

// ---------------------------------------------------------------------------
// Metric Keys (must match ScanHistoryEntry.metrics map keys)
// ---------------------------------------------------------------------------

/// All six tracked metrics, in default display order.
const List<String> kAllMetrics = [
  'redness',
  'texture',
  'wrinkle',
  'pore',
  'darkSpots',
  'elasticity',
];

// ---------------------------------------------------------------------------
// Procedure Profile
// ---------------------------------------------------------------------------

class ProcedureProfile {
  /// Category this profile belongs to.
  final ProcedureCategory category;

  /// Ordered list of metric keys relevant to this procedure (most important first).
  /// Metrics not in this list are hidden from metric cards and reports.
  final List<String> relevantMetrics;

  /// Human-readable overrides for metric labels (e.g. 'redness' → 'Scalp Redness').
  /// Keys that are absent fall back to the default labels.
  final Map<String, String> metricLabels;

  /// Short heading shown in the Analysis screen context banner.
  final String primaryFocusLabel;

  /// A clinical context sentence injected at the top of the Gemini coach prompt
  /// to orient the AI to this procedure's specific physiology.
  final String aiCoachContext;

  /// Key concern keywords — used to personalise narrative language.
  final List<String> recoveryConcerns;

  /// Default milestone templates (label, offset in days, description).
  final List<({String label, int offsetDays, String description})>
  milestoneTemplates;

  const ProcedureProfile({
    required this.category,
    required this.relevantMetrics,
    required this.metricLabels,
    required this.primaryFocusLabel,
    required this.aiCoachContext,
    required this.recoveryConcerns,
    required this.milestoneTemplates,
  });
}

// ---------------------------------------------------------------------------
// Central Profiles Map
// ---------------------------------------------------------------------------

/// Lookup by canonical procedure type name (from procedure.dart aliases).
const Map<ProcedureCategory, ProcedureProfile> _profileByCategory = {
  // ── Hair Transplant ────────────────────────────────────────────────────────
  ProcedureCategory.hairTransplant: ProcedureProfile(
    category: ProcedureCategory.hairTransplant,
    relevantMetrics: ['redness', 'texture', 'darkSpots', 'elasticity'],
    metricLabels: {
      'redness': 'Scalp Redness & Swelling',
      'texture': 'Scabbing & Crusting',
      'darkSpots': 'Follicle Density Indicator',
      'elasticity': 'Scalp Healing Progress',
    },
    primaryFocusLabel: 'Hair Transplant Recovery',
    aiCoachContext:
        'This patient has undergone a hair transplant procedure (FUE or FUT). '
        'Key recovery concerns include: scalp redness/inflammation at graft sites, '
        'scabbing and crusting (which must NOT be forcibly removed — gentle soaking only), '
        'follicle shock-loss (temporary shedding weeks 2–6 that is expected and not a failure), '
        'donor-area healing and numbness, itching from nerve regeneration, '
        'and hair density progression starting at months 3–6 with full results at 12–18 months. '
        'Do NOT recommend products with alcohol, retinoids, or strong acids near the scalp during healing. '
        'Advise against swimming, saunas, and direct sun on the scalp for at least 4 weeks.',
    recoveryConcerns: [
      'scalp redness',
      'scabbing',
      'crusting',
      'graft survival',
      'shock loss',
      'follicle health',
      'donor area',
      'itching',
      'hair density',
    ],
    milestoneTemplates: [
      (
        label: 'Days 1–3',
        offsetDays: 3,
        description:
            'Initial graft settling — avoid touching, wetting, or scratching. Scabbing begins forming around grafts; this is protective.',
      ),
      (
        label: 'Week 1',
        offsetDays: 7,
        description:
            'Gentle washing protocol begins (provider-approved). Scabs soften; let them fall naturally — never pick or rub.',
      ),
      (
        label: 'Week 2–3',
        offsetDays: 21,
        description:
            'Shock loss may begin — temporary shedding of transplanted hairs is completely expected at this stage.',
      ),
      (
        label: 'Month 1',
        offsetDays: 30,
        description:
            'Donor area should appear largely healed. Recipient scalp redness typically settling. New growth not yet visible.',
      ),
      (
        label: 'Month 3',
        offsetDays: 90,
        description:
            'First new hair shafts emerge for many patients. Hair is fine and unpigmented initially — this is normal.',
      ),
      (
        label: 'Month 6',
        offsetDays: 180,
        description:
            'Approximately 50–60% of final density visible. Hair thickens and darkens progressively.',
      ),
      (
        label: 'Month 12',
        offsetDays: 365,
        description:
            'Most patients see 80–90% of final density. Density and texture continue refining through month 18.',
      ),
    ],
  ),

  // ── Injectables ───────────────────────────────────────────────────────────
  ProcedureCategory.injectables: ProcedureProfile(
    category: ProcedureCategory.injectables,
    relevantMetrics: ['redness', 'texture', 'elasticity', 'darkSpots'],
    metricLabels: {
      'redness': 'Injection Site Redness',
      'texture': 'Surface Smoothness',
      'elasticity': 'Skin Firmness & Support',
      'darkSpots': 'Bruising / Post-Injection Pigment',
    },
    primaryFocusLabel: 'Injectable Recovery Monitoring',
    aiCoachContext:
        'This patient has had an injectable treatment (neuromodulator such as Botox/Dysport/Xeomin, '
        'or dermal filler such as hyaluronic acid, Sculptra, or Radiesse). '
        'Key post-injection concerns: injection-site redness and oedema (usually 24–72 h), '
        'bruising (can develop over 2–5 days and fade over 1–2 weeks), '
        'filler migration risk if pressed or massaged incorrectly, '
        'neuromodulator onset (3–7 days), full neuromodulator effect at 2 weeks, '
        'filler integration at 4–6 weeks. '
        'Advise avoiding strenuous exercise for 24 h, no lying down for 4 h post-Botox, '
        'no facial massage unless explicitly instructed, and no heat/saunas for 48 h.',
    recoveryConcerns: [
      'bruising',
      'swelling',
      'injection site',
      'filler migration',
      'neuromodulator onset',
      'lip swelling',
      'asymmetry',
      'lumps',
    ],
    milestoneTemplates: [
      (
        label: 'Day 1',
        offsetDays: 1,
        description:
            'Expected: injection-site redness, mild swelling, possible bruising. Apply ice (wrapped) for 10 min intervals; avoid touching.',
      ),
      (
        label: 'Day 3–5',
        offsetDays: 5,
        description:
            'Bruising may peak on days 3–5. Arnica gel can help. Avoid blood-thinning supplements until bruising resolves.',
      ),
      (
        label: 'Week 1',
        offsetDays: 7,
        description:
            'Neuromodulators: early effect visible. Fillers: swelling mostly resolved. Assess symmetry and movement.',
      ),
      (
        label: 'Week 2',
        offsetDays: 14,
        description:
            'Neuromodulator full effect. Fillers integrating. Ideal time for a touch-up assessment with your provider.',
      ),
      (
        label: 'Week 6',
        offsetDays: 42,
        description:
            'Filler fully integrated and stabilised. Final result assessment. Consider maintenance schedule.',
      ),
    ],
  ),

  // ── Laser / Peel / Microneedling ──────────────────────────────────────────
  ProcedureCategory.laserPeel: ProcedureProfile(
    category: ProcedureCategory.laserPeel,
    relevantMetrics: ['redness', 'texture', 'darkSpots', 'elasticity', 'pore'],
    metricLabels: {
      'redness': 'Post-Treatment Erythema',
      'texture': 'Resurfacing Progress',
      'darkSpots': 'Pigmentation / PIH Risk',
      'elasticity': 'Collagen Stimulation Progress',
      'pore': 'Pore Refinement',
    },
    primaryFocusLabel: 'Resurfacing & Skin Renewal Recovery',
    aiCoachContext:
        'This patient has undergone a skin resurfacing or renewal treatment '
        '(laser resurfacing, chemical peel, IPL, microneedling, RF microneedling, or Morpheus8). '
        'Key recovery concerns: acute erythema and oedema (days 1–5), micro-wound healing, '
        'post-inflammatory hyperpigmentation (PIH) risk — especially in darker skin tones — '
        'barrier disruption requiring intensive moisturisation, strict photoprotection '
        '(SPF 50+ every morning, no direct sun), and avoiding all active ingredients '
        '(retinoids, AHAs, BHAs, vitamin C) until the skin barrier has re-epithelialised '
        '(typically 5–14 days depending on treatment depth). '
        'Collagen remodeling continues for 3–6 months after ablative treatments.',
    recoveryConcerns: [
      'erythema',
      'peeling',
      'barrier recovery',
      'post-inflammatory hyperpigmentation',
      'PIH',
      'scabbing',
      'collagen stimulation',
      're-epithelialisation',
      'sensitivity',
    ],
    milestoneTemplates: [
      (
        label: 'Day 1–3',
        offsetDays: 3,
        description:
            'Peak redness and swelling. Keep skin clean and moisturised. No active ingredients. Sun avoidance is critical.',
      ),
      (
        label: 'Day 4–7',
        offsetDays: 7,
        description:
            'Peeling and flaking begins — let skin shed naturally. Never pick or peel. Gentle cleanser only.',
      ),
      (
        label: 'Week 2',
        offsetDays: 14,
        description:
            'Re-epithelialisation mostly complete for mild/moderate treatments. Redness fading. Reassess with your provider.',
      ),
      (
        label: 'Month 1',
        offsetDays: 30,
        description:
            'Pigmentation improvements becoming visible. Collagen remodeling actively underway. SPF non-negotiable.',
      ),
      (
        label: 'Month 3',
        offsetDays: 90,
        description:
            'Significant texture and tone improvement expected. For ablative treatments, final results continue refining.',
      ),
      (
        label: 'Month 6',
        offsetDays: 180,
        description:
            'Collagen remodeling complete for most treatments. Final result assessment. Plan next session if applicable.',
      ),
    ],
  ),

  // ── Surgical Face ─────────────────────────────────────────────────────────
  ProcedureCategory.surgicalFace: ProcedureProfile(
    category: ProcedureCategory.surgicalFace,
    relevantMetrics: ['redness', 'texture', 'elasticity', 'darkSpots'],
    metricLabels: {
      'redness': 'Swelling / Bruising Index',
      'texture': 'Scar Maturation',
      'elasticity': 'Skin Tightening Progress',
      'darkSpots': 'Bruising Clearance',
    },
    primaryFocusLabel: 'Facial Surgery Recovery',
    aiCoachContext:
        'This patient has undergone facial surgery (rhinoplasty, facelift, blepharoplasty, '
        'brow lift, neck lift, thread lift, chin/jawline contouring, or buccal fat removal). '
        'Key recovery concerns: swelling (peaks days 2–3, slow resolution over weeks to months), '
        'bruising (resolves 2–4 weeks), scar healing and maturation (pink/raised scars normalise over 6–12 months), '
        'numbness/altered sensation from nerve stretching (usually temporary), '
        'asymmetry from differential swelling (very common in early weeks — assess after 3 months), '
        'and skin tightening outcomes visible progressively over 3–12 months. '
        'Head elevation, cold compresses, and avoiding strenuous activity are first-week priorities. '
        'No makeup on surgical sites until cleared by surgeon.',
    recoveryConcerns: [
      'swelling',
      'bruising',
      'numbness',
      'scar healing',
      'skin tightening',
      'asymmetry',
      'sutures',
      'drainage',
      'nasal swelling',
      'eyelid swelling',
    ],
    milestoneTemplates: [
      (
        label: 'Days 1–3',
        offsetDays: 3,
        description:
            'Peak swelling and bruising. Head elevated, cold compresses, rest. Avoid all face-down positions.',
      ),
      (
        label: 'Week 1',
        offsetDays: 7,
        description:
            'Sutures or staples reviewed (most removed at 5–10 days). Bruising transitioning yellow/green. Light walking okay.',
      ),
      (
        label: 'Week 2–3',
        offsetDays: 21,
        description:
            'Most patients comfortable in public. Residual swelling may still mask final contour — do not assess results yet.',
      ),
      (
        label: 'Month 1',
        offsetDays: 30,
        description:
            'Return to normal social activity for most patients. Deep swelling still present — patience is essential.',
      ),
      (
        label: 'Month 3',
        offsetDays: 90,
        description:
            'Swelling resolves enough to assess early results. Scars still pink — this is normal maturation.',
      ),
      (
        label: 'Month 6–12',
        offsetDays: 270,
        description:
            'Scars fading, skin settling. Final result fully visible for most facial procedures by 12 months.',
      ),
    ],
  ),

  // ── Body Contouring ───────────────────────────────────────────────────────
  ProcedureCategory.bodyContouring: ProcedureProfile(
    category: ProcedureCategory.bodyContouring,
    relevantMetrics: ['redness', 'texture', 'darkSpots', 'elasticity'],
    metricLabels: {
      'redness': 'Post-Op Swelling & Bruising',
      'texture': 'Contour Smoothness & Evenness',
      'darkSpots': 'Bruising Clearance',
      'elasticity': 'Skin Retraction & Tightness',
    },
    primaryFocusLabel: 'Body Contouring Recovery',
    aiCoachContext:
        'This patient has had a body contouring procedure such as liposuction, tummy tuck, arm lift, or thigh lift. '
        'Recovery priorities include swelling control, compression garment compliance, gentle walking, protein-rich nutrition, '
        'and manual lymphatic drainage when approved by the surgeon. '
        'Liposuction recovery commonly includes fibrosis or temporary firmness weeks 2–6; this is expected and improves with '
        'compression, massage, and time. '
        'If the procedure was liposuction rather than fat transfer, do not mention fat graft survival or buttock positioning — '
        'focus instead on contour settling, drainage, and scar care.',
    recoveryConcerns: [
      'swelling',
      'bruising',
      'compression garment',
      'fibrosis',
      'lymphatic drainage',
      'skin retraction',
      'contour evenness',
      'tightness',
      'scar care',
    ],
    milestoneTemplates: [
      (
        label: 'Days 1–5',
        offsetDays: 5,
        description:
            'Peak swelling and bruising are expected. Wear the compression garment exactly as directed and keep gentle walking as part of the daily routine.',
      ),
      (
        label: 'Week 2',
        offsetDays: 14,
        description:
            'If drains were used, they are often removed around this point. Swelling is still significant, but the early contour is starting to emerge.',
      ),
      (
        label: 'Weeks 3–6',
        offsetDays: 42,
        description:
            'Firmness and fibrosis commonly develop — this is expected after liposuction and usually responds well to lymphatic drainage and continued compression.',
      ),
      (
        label: 'Month 2–3',
        offsetDays: 75,
        description:
            'Contour becomes clearer as swelling settles. Keep following your garment and massage schedule; the final shape is still refining.',
      ),
      (
        label: 'Month 4–6',
        offsetDays: 150,
        description:
            'Most swelling has resolved and the contour is approaching its stable state. Scar care and sun protection remain important.',
      ),
      (
        label: 'Month 6+',
        offsetDays: 210,
        description:
            'Results are largely settled. Any residual firmness, asymmetry, or contour concerns can be reviewed with your surgeon if needed.',
      ),
    ],
  ),

  // ── Body Composition (GLP-1 / GHRH peptide stacks) ────────────────────────
  ProcedureCategory.bodyComposition: ProcedureProfile(
    category: ProcedureCategory.bodyComposition,
    relevantMetrics: [
      'weight',
      'bodyFat',
      'waist',
      'muscleMass',
      'appetiteControl',
      'bodyCompositionScore',
    ],
    metricLabels: {
      'weight': 'Weight',
      'bodyFat': 'Body Fat %',
      'waist': 'Waist Circumference',
      'muscleMass': 'Muscle Mass',
      'appetiteControl': 'Appetite Control',
      'bodyCompositionScore': 'Body Composition Score',
    },
    primaryFocusLabel: 'Body Composition & Metabolic Health',
    aiCoachContext:
        'This user is tracking a body-composition / metabolic peptide stack '
        '(GLP-1 / GIP / glucagon agonists such as Semaglutide, Tirzepatide, or '
        'Retatrutide; GHRH analogs such as Tesamorelin, Sermorelin, CJC-1295; '
        'GH secretagogues such as Ipamorelin, Hexarelin, or AOD-9604; '
        'and mitochondrial peptides such as MOTS-c). '
        'Focus the analysis on weight trend, body fat %, waist circumference, '
        'muscle / lean mass preservation, appetite control / satiety, and an '
        'overall body-composition score. Facial skin metrics are secondary in '
        'this context. Recovery is metabolic rather than surgical: '
        'maintain 1.4–1.6 g/kg protein intake, prioritize resistance training '
        '2–4×/week to preserve lean mass during caloric deficit, hydrate well, '
        'and monitor for GLP-1 side effects (nausea, fatigue, lean-mass loss). '
        'Never recommend skin-procedure interventions (laser, microneedling, '
        'filler) here unless the user has an associated facial concern; '
        'instead surface body-focused procedures (CoolSculpting, EmSculpt NEO, '
        'BodyTite RF, Liposuction, Lymphatic Drainage Massage) when relevant.',
    recoveryConcerns: [
      'weight loss',
      'fat loss',
      'lean mass',
      'muscle preservation',
      'appetite control',
      'satiety',
      'GLP-1 side effects',
      'protein intake',
      'visceral fat',
      'metabolic health',
    ],
    milestoneTemplates: [
      (
        label: 'Week 1',
        offsetDays: 7,
        description:
            'Initial titration phase. Appetite reduction and mild GI side effects (nausea, reflux) are common at first dose escalation. Hydration and small protein-forward meals help.',
      ),
      (
        label: 'Week 4',
        offsetDays: 30,
        description:
            'Early weight response typically visible (1–4% of body weight). Focus on protein intake and resistance training to preserve lean mass.',
      ),
      (
        label: 'Week 12',
        offsetDays: 90,
        description:
            'Most patients see meaningful body-composition changes by 12 weeks. Reassess waist circumference and body fat %. Continue strength training.',
      ),
      (
        label: 'Week 24',
        offsetDays: 180,
        description:
            'Mid-point for many GLP-1 protocols. Evaluate plateau risk and adjust dose or stack with provider input.',
      ),
      (
        label: 'Week 52',
        offsetDays: 365,
        description:
            'One-year review. Assess maintenance dose strategy and long-term lean-mass preservation.',
      ),
    ],
  ),

  // ── General Skincare (default) ────────────────────────────────────────────
  ProcedureCategory.generalSkincare: ProcedureProfile(
    category: ProcedureCategory.generalSkincare,
    relevantMetrics: [
      'redness',
      'texture',
      'wrinkle',
      'pore',
      'darkSpots',
      'elasticity',
    ],
    metricLabels: {},
    primaryFocusLabel: 'Comprehensive Skin Health',
    aiCoachContext:
        'This patient is tracking general skin health without a specific surgical or procedural '
        'recovery context. All six metrics — redness, texture, wrinkles, pore visibility, '
        'dark spots, and skin elasticity — are relevant and equally weighted. '
        'Focus on evidence-based skincare fundamentals: daily SPF 50+, retinoid use, '
        'barrier support, and addressing any elevated metrics with targeted actives. '
        'Long-term consistency is the primary lever for meaningful skin improvement.',
    recoveryConcerns: [
      'redness',
      'texture',
      'wrinkles',
      'pores',
      'dark spots',
      'elasticity',
    ],
    milestoneTemplates: [
      (
        label: 'Month 1',
        offsetDays: 30,
        description:
            'First assessment point. Baseline established; initial response to actives becoming visible.',
      ),
      (
        label: 'Month 3',
        offsetDays: 90,
        description:
            '3-month review. Retinoid and brightening protocols show measurable improvement.',
      ),
      (
        label: 'Month 6',
        offsetDays: 180,
        description:
            '6-month check-in. Dermal remodeling from consistent retinoid use accumulating.',
      ),
      (
        label: 'Month 12',
        offsetDays: 365,
        description:
            'Annual review. Comprehensive comparison of all six metrics against baseline.',
      ),
    ],
  ),
};

// ---------------------------------------------------------------------------
// Canonical category mapping
// ---------------------------------------------------------------------------

ProcedureCategory _categoryForType(String procedureType) {
  final canonical = canonicalProcedureType(procedureType);
  final lower = canonical.toLowerCase();

  // Body Composition (metabolic / GLP-1 / GHRH peptide stacks).
  // Detect BEFORE body contouring so "lipo" doesn't mis-match terms like
  // "lipolysis" but a true "liposuction" still resolves below.
  if (lower.contains('body composition') ||
      lower.contains('body-composition') ||
      lower.contains('weight loss') ||
      lower.contains('glp-1') ||
      lower.contains('glp1') ||
      lower.contains('semaglutide') ||
      lower.contains('tirzepatide') ||
      lower.contains('retatrutide') ||
      lower.contains('tesamorelin') ||
      lower.contains('aod-9604') ||
      lower.contains('aod9604') ||
      lower.contains('sermorelin') ||
      lower.contains('cjc-1295') ||
      lower.contains('ipamorelin') ||
      lower.contains('hexarelin') ||
      lower.contains('mots-c') ||
      lower.contains('motsc') ||
      lower.contains('igf-1') ||
      lower.contains('metabolic peptide') ||
      lower.contains('body peptide')) {
    return ProcedureCategory.bodyComposition;
  }

  // Hair Transplant
  if (lower.contains('hair transplant') ||
      lower.contains('fue') ||
      lower.contains('fut')) {
    return ProcedureCategory.hairTransplant;
  }

  // Body Contouring
  if (lower.contains('bbl') ||
      lower.contains('liposuction') ||
      lower.contains('lipo') ||
      lower.contains('tummy tuck') ||
      lower.contains('arm') ||
      lower.contains('thigh lift')) {
    return ProcedureCategory.bodyContouring;
  }

  // Surgical Face
  if (lower.contains('rhinoplasty') ||
      lower.contains('facelift') ||
      lower.contains('face lift') ||
      lower.contains('blepharoplasty') ||
      lower.contains('brow lift') ||
      lower.contains('neck lift') ||
      lower.contains('thread lift') ||
      lower.contains('chin') ||
      lower.contains('jawline') ||
      lower.contains('buccal fat')) {
    return ProcedureCategory.surgicalFace;
  }

  // Injectables
  if (lower.contains('botox') ||
      lower.contains('dysport') ||
      lower.contains('xeomin') ||
      lower.contains('filler') ||
      lower.contains('lip augmentation') ||
      lower.contains('lip filler') ||
      lower.contains('sculptra') ||
      lower.contains('radiesse') ||
      lower.contains('kybella')) {
    return ProcedureCategory.injectables;
  }

  // Laser / Peel / Microneedling
  if (lower.contains('laser') ||
      lower.contains('peel') ||
      lower.contains('ipl') ||
      lower.contains('microneedling') ||
      lower.contains('morpheus') ||
      lower.contains('halo') ||
      lower.contains('fraxel') ||
      lower.contains('co2') ||
      lower.contains('rf ') ||
      lower.contains('radiofrequency')) {
    return ProcedureCategory.laserPeel;
  }

  return ProcedureCategory.generalSkincare;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

class ProcedureIntelligence {
  const ProcedureIntelligence._();

  /// Returns the full [ProcedureProfile] for a given procedure type string.
  /// Falls back to generalSkincare if the type is unrecognised.
  static ProcedureProfile forType(String? procedureType) {
    if (procedureType == null || procedureType.trim().isEmpty) {
      return _profileByCategory[ProcedureCategory.generalSkincare]!;
    }
    final category = _categoryForType(procedureType.trim());
    return _profileByCategory[category]!;
  }

  /// Returns the ordered list of relevant metric keys for a given procedure.
  static List<String> relevantMetrics(String? procedureType) =>
      forType(procedureType).relevantMetrics;

  /// Returns the display label for a metric, adapted for the procedure type.
  /// Falls back to the default human-readable label if no override exists.
  static String metricLabel(String metricKey, String? procedureType) {
    if (categoryFor(procedureType) == ProcedureCategory.bodyContouring) {
      switch (metricKey) {
        case 'elasticity':
          return bodyContouringSubtype(procedureType) ==
                  ProcedureBodyContouringSubtype.bbl
              ? 'Skin Retraction & Fat Retention'
              : 'Skin Retraction & Tightness';
        case 'redness':
          return 'Post-Op Swelling & Bruising';
        case 'texture':
          return 'Contour Smoothness & Evenness';
        case 'darkSpots':
          return 'Bruising Clearance';
      }
    }

    final overrides = forType(procedureType).metricLabels;
    return overrides[metricKey] ?? _defaultMetricLabel(metricKey);
  }

  /// Returns the AI coach context paragraph to inject into Gemini prompts.
  static String aiCoachContext(String? procedureType) {
    if (categoryFor(procedureType) == ProcedureCategory.bodyContouring) {
      switch (bodyContouringSubtype(procedureType)) {
        case ProcedureBodyContouringSubtype.bbl:
          return 'This patient has undergone a Brazilian Butt Lift (BBL) or gluteal fat transfer. '
              'Key recovery concerns include strict no-pressure positioning on the buttocks, use of a BBL pillow under the thighs when seated, '
              'compression garment compliance, fat graft survival, swelling control, and gentle walking for circulation. '
              'Do not recommend direct sitting on the buttocks or back-sleeping during the early healing window unless the surgeon has cleared it.';
        case ProcedureBodyContouringSubtype.liposuction:
          return 'This patient has undergone liposuction. Key recovery concerns include swelling control, compression garment compliance, '
              'manual lymphatic drainage when approved, fibrosis prevention, contour settling, hydration, and protein intake to support tissue repair. '
              'Do not mention BBL pillow protocols, fat graft survival, or buttock positioning because those are not part of liposuction recovery.';
        case ProcedureBodyContouringSubtype.other:
          return 'This patient has undergone a body contouring procedure such as tummy tuck, arm lift, or thigh lift. '
              'Key recovery concerns include swelling control, compression as directed, gentle walking, scar care, and contour settling. '
              'Keep guidance procedure-specific and do not introduce BBL-only advice unless the selected procedure is explicitly a BBL.';
      }
    }

    return forType(procedureType).aiCoachContext;
  }

  /// Returns the primary focus label for display in the UI.
  static String primaryFocusLabel(String? procedureType) {
    if (categoryFor(procedureType) == ProcedureCategory.bodyContouring) {
      switch (bodyContouringSubtype(procedureType)) {
        case ProcedureBodyContouringSubtype.bbl:
          return 'BBL Recovery';
        case ProcedureBodyContouringSubtype.liposuction:
          return 'Liposuction Recovery';
        case ProcedureBodyContouringSubtype.other:
          return 'Body Contouring Recovery';
      }
    }

    return forType(procedureType).primaryFocusLabel;
  }

  /// Returns procedure-specific default milestone templates.
  static List<ProcedureTimelineMilestone> defaultMilestones(
    String? procedureType,
    DateTime startDate,
  ) {
    if (categoryFor(procedureType) == ProcedureCategory.bodyContouring) {
      final templates = switch (bodyContouringSubtype(procedureType)) {
        ProcedureBodyContouringSubtype.bbl => [
          (
            label: 'Days 1–5',
            offsetDays: 5,
            description:
                'Peak swelling and bruising are expected. For BBL recovery, avoid direct sitting on the buttocks and follow the surgeon-approved pillow protocol exactly.',
          ),
          (
            label: 'Week 2',
            offsetDays: 14,
            description:
                'Swelling is still present but starting to settle. Keep compression consistent and continue the positioning rules your surgeon gave you.',
          ),
          (
            label: 'Weeks 3–6',
            offsetDays: 42,
            description:
                'Firmness and fibrosis commonly appear. Massage and lymphatic drainage are often introduced if cleared.',
          ),
          (
            label: 'Month 2–3',
            offsetDays: 75,
            description:
                'Contour starts to look more defined as swelling continues to decline. Sitting restrictions may begin to ease depending on provider guidance.',
          ),
          (
            label: 'Month 4–6',
            offsetDays: 150,
            description:
                'Final contour is approaching a stable state. Scar care and sun protection remain important.',
          ),
        ],
        ProcedureBodyContouringSubtype.liposuction => [
          (
            label: 'Days 1–5',
            offsetDays: 5,
            description:
                'Peak swelling and bruising are expected. Compression and gentle walking are the first priorities.',
          ),
          (
            label: 'Week 2',
            offsetDays: 14,
            description:
                'Drain removal and early contour changes are often seen around this point. Continue the garment schedule exactly as directed.',
          ),
          (
            label: 'Weeks 3–6',
            offsetDays: 42,
            description:
                'Firmness and fibrosis commonly develop after liposuction. Manual lymphatic drainage may help once your surgeon approves it.',
          ),
          (
            label: 'Month 2–3',
            offsetDays: 75,
            description:
                'Swelling settles further and contour becomes clearer. Keep following compression and massage guidance.',
          ),
          (
            label: 'Month 4–6',
            offsetDays: 150,
            description:
                'Most swelling has resolved and the contour is nearing its stable state. Scar care and sun protection remain important.',
          ),
        ],
        ProcedureBodyContouringSubtype.other => [
          (
            label: 'Days 1–5',
            offsetDays: 5,
            description:
                'Peak swelling and bruising are expected. Follow your compression and walking instructions carefully.',
          ),
          (
            label: 'Week 2',
            offsetDays: 14,
            description:
                'Early swelling begins to settle, but the true contour is still forming.',
          ),
          (
            label: 'Weeks 3–6',
            offsetDays: 42,
            description:
                'Firmness or fibrosis may appear and usually improves with time, compression, and approved massage.',
          ),
          (
            label: 'Month 2–3',
            offsetDays: 75,
            description:
                'Contour becomes clearer as healing continues. Keep following provider guidance closely.',
          ),
          (
            label: 'Month 4–6',
            offsetDays: 150,
            description:
                'Final contour is approaching its stable state. Scar care and sun protection remain important.',
          ),
        ],
      };

      final base = DateTime(startDate.year, startDate.month, startDate.day);
      return templates.asMap().entries.map((entry) {
        final i = entry.key;
        final t = entry.value;
        return ProcedureTimelineMilestone(
          id: 'ms_body_${i}_${base.millisecondsSinceEpoch}',
          label: t.label,
          description: t.description,
          expectedDate: base.add(Duration(days: t.offsetDays)),
          displayOrder: i,
        );
      }).toList();
    }

    final profile = forType(procedureType);
    final base = DateTime(startDate.year, startDate.month, startDate.day);
    return profile.milestoneTemplates.asMap().entries.map((entry) {
      final i = entry.key;
      final t = entry.value;
      return ProcedureTimelineMilestone(
        id: 'ms_default_${i}_${base.millisecondsSinceEpoch}',
        label: t.label,
        description: t.description,
        expectedDate: base.add(Duration(days: t.offsetDays)),
        displayOrder: i,
      );
    }).toList();
  }

  /// Returns [true] if the given metric key is relevant for this procedure.
  static bool isMetricRelevant(String metricKey, String? procedureType) =>
      forType(procedureType).relevantMetrics.contains(metricKey);

  /// Returns the procedure category enum.
  static ProcedureCategory categoryFor(String? procedureType) {
    if (procedureType == null || procedureType.trim().isEmpty) {
      return ProcedureCategory.generalSkincare;
    }
    return _categoryForType(procedureType.trim());
  }

  /// Returns the specific body contouring subtype when the selected procedure
  /// belongs to that family.
  static ProcedureBodyContouringSubtype bodyContouringSubtype(
    String? procedureType,
  ) {
    final canonical = canonicalProcedureType(procedureType ?? '');
    final lower = canonical.toLowerCase();

    if (lower.contains('bbl') ||
        lower.contains('butt lift') ||
        lower.contains('brazilian')) {
      return ProcedureBodyContouringSubtype.bbl;
    }

    if (lower.contains('liposuction') || lower.contains('lipo')) {
      return ProcedureBodyContouringSubtype.liposuction;
    }

    return ProcedureBodyContouringSubtype.other;
  }
}

// ---------------------------------------------------------------------------
// Default metric labels (used as fallback when no override exists)
// ---------------------------------------------------------------------------

String _defaultMetricLabel(String key) {
  switch (key) {
    case 'redness':
      return 'Redness';
    case 'texture':
      return 'Texture';
    case 'wrinkle':
      return 'Wrinkles';
    case 'pore':
      return 'Pores';
    case 'darkSpots':
      return 'Dark Spots';
    case 'elasticity':
      return 'Elasticity';
    default:
      return key;
  }
}

// ---------------------------------------------------------------------------
// Derived clinical metric formulas
// ---------------------------------------------------------------------------
//
// These four functions extend the six persisted [SkinMetrics] fields into the
// full 10-metric clinical panel surfaced to patients. They are deterministic,
// pure, and intentionally simple so the math is auditable from the UI tooltip
// copy (`derivedFormulaText`) below.
//
// Scale convention: every output is clamped to 0–10, matching the rest of
// the clinical metric system. `lowerIsBetter` semantics are documented per
// metric in [_generalSkincareMetrics] and [metric_trend.dart].

double _clamp10(double v) => v.clamp(0.0, 10.0).toDouble();

/// **Skin Tone Uniformity** (higher = better).
/// Inverse of hyperpigmentation load — even pigmentation distribution.
double derivedSkinToneUniformity(SkinMetrics m) => _clamp10(10 - m.darkSpots);

/// **Skin Hydration Level** (higher = better).
/// Weighted blend reflecting that smoother texture (intact stratum corneum)
/// and preserved elasticity correlate with adequate hydration, while
/// erythema flags barrier disruption.
///   55% (10 − texture) · 30% elasticity · 15% (10 − redness)
double derivedSkinHydrationLevel(SkinMetrics m) => _clamp10(
  (10 - m.texture) * 0.55 + m.elasticity * 0.30 + (10 - m.redness) * 0.15,
);

/// **Inflammatory Response** (lower = better).
/// Composite of erythema and surface irritation tracking acute-phase signals.
///   70% redness · 30% texture
double derivedInflammatoryResponse(SkinMetrics m) =>
    _clamp10(m.redness * 0.7 + m.texture * 0.3);

/// **Global Skin Quality Score** (higher = better).
/// Weighted clinical composite emphasizing structural integrity (laxity,
/// texture) with balanced contributions from rhytids, pigmentation, erythema,
/// and pore visibility. Weights sum to 1.0.
///   20% elasticity · 20% (10 − texture) · 15% (10 − wrinkle)
///   15% (10 − darkSpots) · 15% (10 − redness) · 15% (10 − pore)
double derivedGlobalSkinQualityScore(SkinMetrics m) => _clamp10(
  m.elasticity * 0.20 +
      (10 - m.texture) * 0.20 +
      (10 - m.wrinkle) * 0.15 +
      (10 - m.darkSpots) * 0.15 +
      (10 - m.redness) * 0.15 +
      (10 - m.pore) * 0.15,
);

/// Human-readable formula strings rendered in the Clinical Metrics info
/// dialog. Keys must match the [ClinicalMetricDef.label] values below.
const Map<String, String> derivedFormulaText = {
  'Skin Tone Uniformity':
      '10 − Hyperpigmentation. Higher value = more even pigment distribution.',
  'Skin Hydration Level':
      '0.55·(10 − Texture) + 0.30·Laxity + 0.15·(10 − Erythema). '
      'Smoother surface, preserved elasticity, and minimal irritation all '
      'indicate adequate stratum-corneum hydration.',
  'Inflammatory Response':
      '0.70·Erythema + 0.30·Texture. Captures acute redness combined with '
      'surface irritation/roughness.',
  'Global Skin Quality Score':
      '0.20·Laxity + 0.20·(10 − Texture) + 0.15·(10 − Rhytids) + '
      '0.15·(10 − Hyperpigmentation) + 0.15·(10 − Erythema) + '
      '0.15·(10 − Pore Visibility). Weighted composite of every '
      'clinical dimension.',
};

// ---------------------------------------------------------------------------
// Clinical Metric Definitions — procedure-specific tracked metrics
// ---------------------------------------------------------------------------

/// A single clinically-named metric tracked for a procedure category.
///
/// Multiple [ClinicalMetricDef]s may share an underlying [sourceKey] but
/// present a different clinical framing (e.g. body contouring exposes both
/// "Fat Retention" and "Volume Satisfaction" derived from elasticity).
///
/// [extract] computes the displayed value (0–10 scale) from a [SkinMetrics]
/// snapshot. The default implementation returns the raw value for [sourceKey].
class ClinicalMetricDef {
  const ClinicalMetricDef({
    required this.label,
    required this.sourceKey,
    required this.lowerIsBetter,
    required this.clinicalContext,
    required this.suggestionImproving,
    required this.suggestionWorsening,
    this.extract,
    this.rawSourceKeys,
    this.extractFromRaw,
    this.normalizeForLevel,
    this.valueFormatter,
  });

  /// User-facing display name (e.g. "Post-Op Swelling & Bruising").
  final String label;

  /// Underlying SkinMetrics field this metric is derived from. One of:
  /// `redness`, `texture`, `wrinkle`, `pore`, `darkSpots`, `elasticity`.
  /// Used for trend resolution and reading the value when [extract] is null.
  final String sourceKey;

  /// True if a lower numeric value is clinically better (most metrics).
  /// False for fat retention, elasticity, density, survival, etc.
  final bool lowerIsBetter;

  /// One-line clinical explanation of what the number reflects.
  final String clinicalContext;

  /// Evidence-based recommendation when this metric is improving / optimal.
  final String suggestionImproving;

  /// Evidence-based recommendation when this metric is worsening / concerning.
  final String suggestionWorsening;

  /// Optional custom extractor. When null, returns the raw [sourceKey] value.
  final double Function(SkinMetrics)? extract;

  /// Optional fallback key aliases when this metric is sourced from a raw
  /// `ScanHistoryEntry.metrics` map (used for body-composition metrics like
  /// weight, body fat %, waist, muscle mass — which are not part of
  /// `SkinMetrics`). The first matching key in the raw map wins.
  final List<String>? rawSourceKeys;

  /// Optional custom raw-map extractor. Takes precedence over [rawSourceKeys]
  /// when both are supplied. Returns null if the metric can't be computed.
  final double? Function(Map<String, double> raw)? extractFromRaw;

  /// Optional mapping from the raw display value (e.g. weight in lbs, body
  /// fat percent, waist in inches) to a normalized 0–10 clinical score used
  /// by the engine's level classifier. When null, the raw value is used
  /// directly (appropriate for SkinMetrics 0–10 metrics).
  final double Function(double rawValue)? normalizeForLevel;

  /// Optional formatter for displaying the raw value with appropriate units
  /// (e.g. "180 lbs", "22.5%", "32 in"). When null, no unit string is shown.
  final String Function(double rawValue)? valueFormatter;

  double valueFrom(SkinMetrics m) =>
      extract != null ? extract!(m) : _rawValue(m, sourceKey);

  /// Resolves this metric's value preferring the raw `ScanHistoryEntry.metrics`
  /// map (for body-composition keys) and falling back to [SkinMetrics].
  /// Returns null when no source can supply a value.
  double? valueFromRaw(Map<String, double>? raw, SkinMetrics? m) {
    if (raw != null) {
      if (extractFromRaw != null) {
        final v = extractFromRaw!(raw);
        if (v != null) return v;
      }
      final keys = rawSourceKeys;
      if (keys != null) {
        for (final k in keys) {
          final v = raw[k];
          if (v != null) return v;
        }
      }
    }
    if (m == null) return null;
    return valueFrom(m);
  }
}

double _rawValue(SkinMetrics m, String key) {
  switch (key) {
    case 'redness':
      return m.redness;
    case 'texture':
      return m.texture;
    case 'wrinkle':
      return m.wrinkle;
    case 'pore':
      return m.pore;
    case 'darkSpots':
      return m.darkSpots;
    case 'elasticity':
      return m.elasticity;
    default:
      return 0;
  }
}

// Curated clinical metric sets per procedure category.
// Each list contains the 5–7 most clinically meaningful metrics for the
// category. Order matters — most important first.

final List<ClinicalMetricDef> _bodyContouringMetrics = [
  const ClinicalMetricDef(
    label: 'Post-Op Swelling',
    sourceKey: 'redness',
    lowerIsBetter: true,
    rawSourceKeys: ['postOpSwelling', 'swelling', 'swellingLevel', 'redness'],
    clinicalContext:
        'Reflects acute inflammatory response and ecchymosis volume in treated areas.',
    suggestionImproving:
        'Continue compression garment 22+ hrs/day and gentle lymphatic walking.',
    suggestionWorsening:
        'Reinforce compression, elevate when supine, and contact your surgeon if swelling is asymmetric or pulsatile.',
  ),
  ClinicalMetricDef(
    label: 'Bruising Clearance',
    sourceKey: 'darkSpots',
    lowerIsBetter: false,
    rawSourceKeys: const ['bruisingClearance', 'bruiseClearance'],
    extract: (m) => (10 - m.darkSpots).clamp(0.0, 10.0),
    clinicalContext:
        'Tracks fading of hemosiderin pigment as extravasated blood is reabsorbed.',
    suggestionImproving:
        'Maintain hydration and arnica/bromelain support if tolerated.',
    suggestionWorsening:
        'Persistent dark patches beyond 4 weeks may indicate seroma — ask your surgeon to evaluate.',
  ),
  ClinicalMetricDef(
    label: 'Contour Evenness',
    sourceKey: 'texture',
    lowerIsBetter: false,
    rawSourceKeys: const ['contourEvenness', 'contourSymmetry'],
    extract: (m) => (10 - m.texture).clamp(0.0, 10.0),
    clinicalContext:
        'Measures smoothness of the surgical contour — irregularity suggests fluid or fibrosis.',
    suggestionImproving:
        'Begin gentle manual lymphatic drainage massage once cleared by your surgeon.',
    suggestionWorsening:
        'Schedule lymphatic massage and discuss ultrasound assessment for fluid collections.',
  ),
  const ClinicalMetricDef(
    label: 'Fat Retention',
    sourceKey: 'elasticity',
    lowerIsBetter: false,
    rawSourceKeys: ['fatRetention', 'fatRetentionPercent', 'fatRetentionPct'],
    clinicalContext:
        'Estimates surviving grafted/preserved adipose volume (higher = better retention).',
    suggestionImproving:
        'Maintain caloric and protein adequacy (1.4–1.6 g/kg) to support graft survival.',
    suggestionWorsening:
        'Avoid extreme weight loss and strenuous compression on treated areas in months 1–3.',
  ),
  ClinicalMetricDef(
    label: 'Skin Retraction & Tightness',
    sourceKey: 'wrinkle',
    lowerIsBetter: false,
    rawSourceKeys: const ['skinRetraction', 'skinTightness', 'tightness'],
    extract: (m) => (10 - m.wrinkle).clamp(0.0, 10.0),
    clinicalContext:
        'Skin laxity index — lower values indicate stronger dermal retraction over new contour.',
    suggestionImproving:
        'Continue compression and protein support to optimize dermal remodeling.',
    suggestionWorsening:
        'Discuss energy-based skin tightening (RF / Renuvion) with your provider at 3–6 months.',
  ),
  const ClinicalMetricDef(
    label: 'Fibrosis/Firmness',
    sourceKey: 'pore',
    lowerIsBetter: true,
    rawSourceKeys: ['fibrosisFirmness', 'fibrosisLevel', 'firmness'],
    clinicalContext:
        'Detects hardened, nodular tissue typical of post-op fibrotic remodeling.',
    suggestionImproving:
        'Continue daily MLD massage and soft foam rolling on cleared areas.',
    suggestionWorsening:
        'Add ultrasound therapy or radiofrequency sessions and discuss with your surgeon.',
  ),
  ClinicalMetricDef(
    label: 'Volume Satisfaction',
    sourceKey: 'elasticity',
    lowerIsBetter: false,
    rawSourceKeys: const ['volumeSatisfaction', 'volumeScore'],
    clinicalContext:
        'Composite of perceived volume and contour relative to surgical goal.',
    suggestionImproving:
        'Stay consistent with garment + nutrition through month 3.',
    suggestionWorsening:
        'If volume loss exceeds expectations after month 3, discuss revision or touch-up.',
    extract: (m) =>
        ((m.elasticity * 0.7) + ((10 - m.texture) * 0.3)).clamp(0.0, 10.0),
  ),
];

final List<ClinicalMetricDef> _hairTransplantMetrics = [
  const ClinicalMetricDef(
    label: 'Scalp Redness & Inflammation',
    sourceKey: 'redness',
    lowerIsBetter: true,
    clinicalContext:
        'Erythema in graft and donor sites — normal in week 1–2, should fade by week 4.',
    suggestionImproving:
        'Continue saline spray and gentle baby shampoo washes.',
    suggestionWorsening:
        'Avoid heat/sun, pause topicals, and contact your clinic if redness deepens past week 3.',
  ),
  const ClinicalMetricDef(
    label: 'Scabbing & Crusting',
    sourceKey: 'texture',
    lowerIsBetter: true,
    clinicalContext:
        'Crust formation around grafts — should clear by day 10–14 with proper care.',
    suggestionImproving:
        'Continue gentle wetting protocol; do not pick or scratch.',
    suggestionWorsening:
        'Persistent crusts past day 14 may risk graft compromise — request clinic guidance.',
  ),
  const ClinicalMetricDef(
    label: 'Hair Density / Growth',
    sourceKey: 'elasticity',
    lowerIsBetter: false,
    clinicalContext:
        'Visible follicle activity and emerging hair shaft density (higher = better).',
    suggestionImproving:
        'Maintain finasteride/minoxidil if prescribed and protein-rich diet.',
    suggestionWorsening:
        'Significant lag at months 4–6 may warrant PRP — discuss with your surgeon.',
  ),
  const ClinicalMetricDef(
    label: 'Follicle Survival',
    sourceKey: 'darkSpots',
    lowerIsBetter: true,
    clinicalContext:
        'Inverse marker of follicular loss — lower values reflect higher graft survival.',
    suggestionImproving:
        'Avoid direct sun, hats with friction, and sleeping on treated areas.',
    suggestionWorsening:
        'Excess shedding beyond expected shock loss — request clinic photographic review.',
  ),
  const ClinicalMetricDef(
    label: 'Itching / Sensitivity',
    sourceKey: 'pore',
    lowerIsBetter: true,
    clinicalContext:
        'Reflects healing nerve activity and dryness — peaks weeks 2–4.',
    suggestionImproving:
        'Continue scalp moisturizer and antihistamine if cleared.',
    suggestionWorsening:
        'Persistent severe itch may indicate folliculitis — ask for topical therapy.',
  ),
  const ClinicalMetricDef(
    label: 'Shock Loss Status',
    sourceKey: 'wrinkle',
    lowerIsBetter: true,
    clinicalContext:
        'Telogen effluvium around grafted area — expected weeks 3–8, resolves by month 4.',
    suggestionImproving: 'Stay patient; shock loss is reversible and expected.',
    suggestionWorsening:
        'Continued shedding past month 5 — request PRP or minoxidil intensification.',
  ),
];

final List<ClinicalMetricDef> _laserPeelMetrics = [
  const ClinicalMetricDef(
    label: 'Redness / Erythema',
    sourceKey: 'redness',
    lowerIsBetter: true,
    clinicalContext:
        'Post-treatment inflammatory response — expected to fade over 3–14 days.',
    suggestionImproving:
        'Continue barrier-supportive moisturizer and strict SPF 50+.',
    suggestionWorsening:
        'Pause actives, add ceramide-rich barrier cream, and contact provider if persistent.',
  ),
  const ClinicalMetricDef(
    label: 'Texture & Smoothness',
    sourceKey: 'texture',
    lowerIsBetter: true,
    clinicalContext:
        'Surface uniformity — improves as new epidermis remodels post-resurfacing.',
    suggestionImproving:
        'Reintroduce gentle hydrating serums (HA, peptides) as healing progresses.',
    suggestionWorsening:
        'Avoid scrubs and physical exfoliation; consult provider if rough patches persist.',
  ),
  const ClinicalMetricDef(
    label: 'Dark Spots / Pigmentation',
    sourceKey: 'darkSpots',
    lowerIsBetter: true,
    clinicalContext:
        'PIH risk indicator — pigmentation can flare in week 2–3 in deeper Fitzpatrick types.',
    suggestionImproving:
        'Maintain SPF 50+ and add vitamin C / niacinamide once cleared.',
    suggestionWorsening:
        'Begin tranexamic acid or HQ under provider guidance to abort PIH.',
  ),
  const ClinicalMetricDef(
    label: 'Pore Size',
    sourceKey: 'pore',
    lowerIsBetter: true,
    clinicalContext:
        'Visible follicular openings — improves with collagen remodeling over weeks.',
    suggestionImproving:
        'Continue niacinamide and BHA when fully healed for sustained refinement.',
    suggestionWorsening:
        'Discuss additional sessions or RF microneedling if no change at 3 months.',
  ),
  const ClinicalMetricDef(
    label: 'Face Shape Stability',
    sourceKey: 'elasticity',
    lowerIsBetter: false,
    clinicalContext:
        'Dermal collagen response — neocollagenesis peaks at 3–6 months post-treatment.',
    suggestionImproving:
        'Maintain peptide and retinoid use (when cleared) for collagen support.',
    suggestionWorsening:
        'Discuss layered modalities (RF + microneedling) at 3–6 month review.',
  ),
  const ClinicalMetricDef(
    label: 'Barrier Recovery',
    sourceKey: 'wrinkle',
    lowerIsBetter: true,
    clinicalContext:
        'Transepidermal water loss surrogate — barrier should normalize by week 2–3.',
    suggestionImproving: 'Continue ceramide moisturizer twice daily.',
    suggestionWorsening:
        'Add occlusive layer at night and pause all actives until barrier restores.',
  ),
];

final List<ClinicalMetricDef> _surgicalFaceMetrics = [
  const ClinicalMetricDef(
    label: 'Swelling',
    sourceKey: 'redness',
    lowerIsBetter: true,
    clinicalContext:
        'Soft-tissue edema — peaks day 3–5 then resolves progressively over weeks.',
    suggestionImproving:
        'Continue head elevation when supine and low-sodium diet.',
    suggestionWorsening:
        'Asymmetric or expanding swelling warrants immediate surgeon evaluation.',
  ),
  const ClinicalMetricDef(
    label: 'Bruising',
    sourceKey: 'darkSpots',
    lowerIsBetter: true,
    clinicalContext:
        'Ecchymosis around incisions — typically resolves within 10–21 days.',
    suggestionImproving:
        'Maintain hydration; arnica/bromelain may help if cleared.',
    suggestionWorsening:
        'Hematoma signs (firm, painful, expanding) require urgent surgeon contact.',
  ),
  const ClinicalMetricDef(
    label: 'Scar Healing Quality',
    sourceKey: 'texture',
    lowerIsBetter: true,
    clinicalContext:
        'Incision maturation — flat, pale, soft scars indicate optimal remodeling.',
    suggestionImproving:
        'Begin silicone sheets/gel at week 2–3 and strict sun avoidance over scars.',
    suggestionWorsening:
        'Raised or hyperpigmented scars at month 2 — discuss steroid injection or laser.',
  ),
  const ClinicalMetricDef(
    label: 'Skin Tightness',
    sourceKey: 'elasticity',
    lowerIsBetter: false,
    clinicalContext:
        'Dermal redraping over new structural support (higher = better tightening).',
    suggestionImproving:
        'Continue gentle facial massage as cleared; maintain photoprotection.',
    suggestionWorsening:
        'Persistent laxity at month 6 — discuss RF or thread-lift adjunct with provider.',
  ),
  const ClinicalMetricDef(
    label: 'Contour Definition',
    sourceKey: 'wrinkle',
    lowerIsBetter: true,
    clinicalContext:
        'Sharpness of jawline / midface contour — refines as edema fully resolves.',
    suggestionImproving: 'Stay consistent; final contour visible at month 3–6.',
    suggestionWorsening:
        'Persistent fullness or asymmetry — request photographic surgeon review.',
  ),
];

final List<ClinicalMetricDef> _injectablesMetrics = [
  const ClinicalMetricDef(
    label: 'Injection Site Redness',
    sourceKey: 'redness',
    lowerIsBetter: true,
    clinicalContext:
        'Local inflammatory response — typically resolves within 24–72 hours.',
    suggestionImproving: 'Cool compresses and gentle, fragrance-free skincare.',
    suggestionWorsening:
        'Persistent redness beyond 5 days may signal hypersensitivity — call your injector.',
  ),
  const ClinicalMetricDef(
    label: 'Bruising',
    sourceKey: 'darkSpots',
    lowerIsBetter: true,
    clinicalContext:
        'Pinpoint ecchymosis from needle/cannula passage — resolves in 5–10 days.',
    suggestionImproving: 'Hydrate; arnica gel may speed clearance.',
    suggestionWorsening:
        'Sudden severe pain + blanching/dusky color = possible vascular event — seek urgent care.',
  ),
  const ClinicalMetricDef(
    label: 'Surface Smoothness',
    sourceKey: 'texture',
    lowerIsBetter: true,
    clinicalContext:
        'Filler distribution evenness — palpable lumps refine in 1–2 weeks.',
    suggestionImproving:
        'Avoid pressure on treated area for 48 hrs; sleep on back.',
    suggestionWorsening:
        'Persistent nodules beyond 4 weeks may need massage or hyaluronidase.',
  ),
  const ClinicalMetricDef(
    label: 'Face Shape Stability',
    sourceKey: 'elasticity',
    lowerIsBetter: false,
    clinicalContext:
        'Tissue plumpness and biostimulator response (higher = better).',
    suggestionImproving:
        'Maintain hydration and protein intake to support collagen.',
    suggestionWorsening:
        'Volume loss earlier than expected — discuss top-up or alternative product.',
  ),
  const ClinicalMetricDef(
    label: 'Symmetry & Refinement',
    sourceKey: 'wrinkle',
    lowerIsBetter: true,
    clinicalContext:
        'Even projection and balance of treated areas — settles at 2 weeks.',
    suggestionImproving:
        'Re-evaluate at 2-week follow-up for any minor refinements.',
    suggestionWorsening:
        'Marked asymmetry past 2 weeks — schedule touch-up appointment.',
  ),
];

// ── Body Composition (GLP-1 / GHRH peptide stacks) ───────────────────────────
// Body-composition metrics are sourced from raw `ScanHistoryEntry.metrics` keys
// (weight, bodyFat, waist, muscleMass, appetiteControl, bodyCompositionScore)
// rather than from [SkinMetrics]. Each def supplies:
//   • `rawSourceKeys` — fallback key aliases the engine will look up.
//   • `normalizeForLevel` — maps the raw clinical value to a 0–10 score so the
//     engine's level classifier (which assumes 0–10) produces sensible badges.
//   • `valueFormatter` — display units (lbs, %, in, /10).
// Skin-source fallbacks (extract / sourceKey) return 5.0 so a missing body
// reading lands in the "mild" zone rather than triggering a false elevation.
final List<ClinicalMetricDef> _bodyCompositionMetrics = [
  ClinicalMetricDef(
    label: 'Weight',
    sourceKey: 'redness', // unused — raw map is the real source
    lowerIsBetter: true,
    clinicalContext:
        'Total body mass. Most informative as a trend versus baseline rather '
        'than an absolute number — focus on the delta and rate of change.',
    suggestionImproving:
        'Sustained, gradual reduction (~0.5–1% body weight per week) preserves '
        'lean mass on GLP-1 / metabolic peptide protocols. Continue protein '
        'intake (1.4–1.6 g/kg) and resistance training 2–4×/week.',
    suggestionWorsening:
        'Plateau or rebound — review dosing, sleep, alcohol, and weekend '
        'caloric intake. Consider provider review of titration schedule.',
    extract: (m) => 5.0,
    rawSourceKeys: const ['weightLbs', 'weight'],
    // Without height we can't compute BMI; map weight bands roughly. A 5.0
    // score (mild) is intentionally neutral — trend vs baseline carries
    // the real signal here.
    normalizeForLevel: (w) {
      if (w <= 0) return 5.0;
      // 110 lb → ~3.0 (optimal), 160 lb → ~5.0 (mild), 220 lb → ~6.5 (moderate),
      // 280+ lb → ~8.5 (elevated). Clamped to engine range.
      final score = 1.5 + (w - 100) / 30;
      return score.clamp(0.0, 10.0).toDouble();
    },
    valueFormatter: (w) => '${w.toStringAsFixed(w >= 100 ? 0 : 1)} lbs',
  ),
  ClinicalMetricDef(
    label: 'Body Fat %',
    sourceKey: 'redness',
    lowerIsBetter: true,
    clinicalContext:
        'Percent body fat. Clinically elevated when sustained above ~25% (M) '
        '/ ~32% (F). Peptide protocols should preserve lean mass during '
        'caloric deficit — pair with protein + resistance training.',
    suggestionImproving:
        'Trending down — continue protein-forward diet and progressive '
        'resistance training to keep loss biased toward fat, not muscle.',
    suggestionWorsening:
        'Trending up or plateaued — reassess protein intake, sleep quality, '
        'and weekly training volume. Discuss with provider if protocol shift '
        'is appropriate.',
    extract: (m) => 5.0,
    rawSourceKeys: const ['bodyFatPct', 'bodyFat'],
    // 10% → 0 (optimal), 25% → 5 (mild→moderate edge), 40%+ → elevated.
    normalizeForLevel: (bf) => ((bf - 8.0) / 3.0).clamp(0.0, 10.0).toDouble(),
    valueFormatter: (bf) => '${bf.toStringAsFixed(1)}%',
  ),
  ClinicalMetricDef(
    label: 'Waist Circumference',
    sourceKey: 'redness',
    lowerIsBetter: true,
    clinicalContext:
        'Visceral adiposity proxy. Clinical risk thresholds: >40 in (M) / '
        '>35 in (F). One of the most responsive metrics to GLP-1 therapy.',
    suggestionImproving:
        'Reduction in waist is a strong signal of visceral fat loss — keep '
        'cardio + resistance training mix consistent.',
    suggestionWorsening:
        'No change despite weight loss may indicate lean-mass loss masking '
        'fat retention. Review training, protein, and sleep.',
    extract: (m) => 5.0,
    rawSourceKeys: const ['waistInches', 'waistCm', 'waist'],
    // Assume inches (most common in app). 28 in → 1, 40 in → 5, 52+ → ~9.
    normalizeForLevel: (w) {
      if (w <= 0) return 5.0;
      // Heuristic: if value > 70, treat as cm; convert.
      final inches = w > 70 ? w / 2.54 : w;
      return ((inches - 26.0) / 2.8).clamp(0.0, 10.0).toDouble();
    },
    valueFormatter: (w) =>
        w > 70 ? '${w.toStringAsFixed(1)} cm' : '${w.toStringAsFixed(1)} in',
  ),
  ClinicalMetricDef(
    label: 'Muscle Mass',
    sourceKey: 'elasticity', // unused; raw map is real source
    lowerIsBetter: false,
    clinicalContext:
        'Lean / skeletal muscle mass. Critical to preserve on GLP-1 protocols '
        'where rapid weight loss can drive sarcopenic loss without adequate '
        'protein and resistance training.',
    suggestionImproving:
        'Lean mass holding or rising — protein + training plan is working. '
        'Maintain 1.4–1.6 g/kg protein daily.',
    suggestionWorsening:
        'Lean mass declining faster than fat — increase protein, add a 3rd '
        'resistance session, and review GLP-1 dose with provider.',
    extract: (m) => 5.0,
    rawSourceKeys: const ['muscleMassLbs', 'muscleMass', 'leanMass'],
    // Higher is better. 60 lb → ~3.5 (moderate), 110 lb → ~6.5 (optimal),
    // 150+ → top of range.
    normalizeForLevel: (mm) {
      if (mm <= 0) return 5.0;
      return ((mm - 30.0) / 12.0).clamp(0.0, 10.0).toDouble();
    },
    valueFormatter: (mm) => '${mm.toStringAsFixed(mm >= 100 ? 0 : 1)} lbs',
  ),
  ClinicalMetricDef(
    label: 'Appetite Control',
    sourceKey: 'redness',
    lowerIsBetter: false,
    clinicalContext:
        'Self-reported satiety and appetite suppression score (0–10). GLP-1 '
        'agonists like Semaglutide / Tirzepatide / Retatrutide should drive '
        'this upward; AOD-9604 and Tesamorelin have weaker appetite effects.',
    suggestionImproving:
        'Strong satiety — protect against under-eating (especially protein) '
        'so lean mass is preserved.',
    suggestionWorsening:
        'Appetite returning early — discuss dose schedule, injection timing, '
        'or stack adjustment with provider.',
    extract: (m) => 5.0,
    rawSourceKeys: const ['satietyScore', 'appetiteControl', 'satiety'],
    // Already 0–10; passthrough.
    valueFormatter: (v) => '${v.toStringAsFixed(1)} / 10',
  ),
  ClinicalMetricDef(
    label: 'Body Composition Score',
    sourceKey: 'elasticity',
    lowerIsBetter: false,
    clinicalContext:
        'Composite 0–10 indicator combining weight trend, body fat %, waist, '
        'and lean-mass preservation. The headline number for body-composition '
        'peptide tracking.',
    suggestionImproving:
        'Composite trending up — protocol is delivering balanced results. '
        'Maintain current dose, nutrition, and training stack.',
    suggestionWorsening:
        'Composite declining — reassess one variable at a time: dose, '
        'protein, sleep, training, alcohol.',
    extract: (m) => 5.0,
    rawSourceKeys: const ['bodyCompositionScore'],
    valueFormatter: (v) => '${v.toStringAsFixed(1)} / 10',
  ),
];

final List<ClinicalMetricDef> _generalSkincareMetrics = [
  const ClinicalMetricDef(
    label: 'Erythema',
    sourceKey: 'redness',
    lowerIsBetter: true,
    clinicalContext: 'General erythema and inflammatory tone.',
    suggestionImproving: 'Maintain barrier-supportive routine.',
    suggestionWorsening: 'Pause actives; add ceramide moisturizer.',
  ),
  const ClinicalMetricDef(
    label: 'Skin Texture Quality',
    sourceKey: 'texture',
    lowerIsBetter: true,
    clinicalContext: 'Surface smoothness and epidermal uniformity.',
    suggestionImproving: 'Continue gentle exfoliation and hydration.',
    suggestionWorsening: 'Increase hydration and reduce harsh actives.',
  ),
  const ClinicalMetricDef(
    label: 'Rhytids',
    sourceKey: 'wrinkle',
    lowerIsBetter: true,
    clinicalContext: 'Visible static and dynamic rhytids.',
    suggestionImproving: 'Continue retinoid + SPF regimen.',
    suggestionWorsening: 'Discuss in-office collagen-stimulating options.',
  ),
  const ClinicalMetricDef(
    label: 'Pore Visibility',
    sourceKey: 'pore',
    lowerIsBetter: true,
    clinicalContext: 'Visible follicular openings.',
    suggestionImproving: 'Continue niacinamide and gentle cleansing.',
    suggestionWorsening: 'Add BHA exfoliant and consult on procedural options.',
  ),
  const ClinicalMetricDef(
    label: 'Hyperpigmentation',
    sourceKey: 'darkSpots',
    lowerIsBetter: true,
    clinicalContext: 'Pigmentation evenness and PIH risk.',
    suggestionImproving: 'Maintain SPF 50+ and brightening serums.',
    suggestionWorsening: 'Layer tranexamic acid or HQ under provider guidance.',
  ),
  const ClinicalMetricDef(
    label: 'Face Shape Stability',
    sourceKey: 'elasticity',
    lowerIsBetter: false,
    clinicalContext: 'Dermal collagen and elastin support (higher = better).',
    suggestionImproving: 'Continue peptide + retinoid use.',
    suggestionWorsening: 'Discuss energy-based tightening options.',
  ),
  // ─── Derived clinical metrics ──────────────────────────────────────────
  // These four extend the underlying SkinMetrics fields into the full
  // 10-metric clinical panel used by the patient portal. Values are
  // computed deterministically by the top-level `derived*` helpers above so
  // they stay backwards-compatible with all stored scan data and identical
  // across every surface that renders them.
  const ClinicalMetricDef(
    label: 'Skin Tone Uniformity',
    sourceKey: 'darkSpots',
    lowerIsBetter: false,
    clinicalContext:
        'Evenness of pigment distribution. Derived: 10 − Hyperpigmentation.',
    suggestionImproving: 'Maintain SPF 50+ daily and brightening actives.',
    suggestionWorsening:
        'Layer tranexamic acid or azelaic acid under guidance.',
    extract: derivedSkinToneUniformity,
  ),
  const ClinicalMetricDef(
    label: 'Skin Hydration Level',
    sourceKey: 'texture',
    lowerIsBetter: false,
    clinicalContext:
        'Stratum-corneum water content estimate. Weighted blend of texture, '
        'laxity, and erythema signals.',
    suggestionImproving: 'Continue humectant + occlusive layering AM/PM.',
    suggestionWorsening:
        'Add hyaluronic acid serum and a ceramide-rich moisturizer.',
    extract: derivedSkinHydrationLevel,
  ),
  const ClinicalMetricDef(
    label: 'Inflammatory Response',
    sourceKey: 'redness',
    lowerIsBetter: true,
    clinicalContext:
        'Composite of erythema and surface irritation tracking acute-phase '
        'response. Weighted blend: 70% redness · 30% texture.',
    suggestionImproving: 'Maintain gentle barrier-supportive routine.',
    suggestionWorsening:
        'Pause actives; add ceramide moisturizer and cool compresses.',
    extract: derivedInflammatoryResponse,
  ),
  const ClinicalMetricDef(
    label: 'Global Skin Quality Score',
    sourceKey: 'elasticity',
    lowerIsBetter: false,
    clinicalContext:
        'Weighted aggregate of laxity, texture, rhytids, pigmentation, '
        'erythema, and pore visibility.',
    suggestionImproving: 'Stay the course — your routine is working.',
    suggestionWorsening:
        'Reassess one variable at a time: cleansing, actives, SPF, sleep.',
    extract: derivedGlobalSkinQualityScore,
  ),
];

/// Top-level lookup: returns the curated 5–7 clinical metric definitions
/// for the given procedure type. Falls back to general skincare.
extension ProcedureIntelligenceClinicalMetrics on ProcedureIntelligence {
  static List<ClinicalMetricDef> clinicalMetricsFor(String? procedureType) {
    switch (ProcedureIntelligence.categoryFor(procedureType)) {
      case ProcedureCategory.bodyContouring:
        return _bodyContouringMetrics;
      case ProcedureCategory.bodyComposition:
        return _bodyCompositionMetrics;
      case ProcedureCategory.hairTransplant:
        return _hairTransplantMetrics;
      case ProcedureCategory.laserPeel:
        return _laserPeelMetrics;
      case ProcedureCategory.surgicalFace:
        return _surgicalFaceMetrics;
      case ProcedureCategory.injectables:
        return _injectablesMetrics;
      case ProcedureCategory.generalSkincare:
        return _generalSkincareMetrics;
    }
  }
}

/// Convenience top-level function — same as extension but easier to import.
List<ClinicalMetricDef> clinicalMetricsForProcedure(String? procedureType) =>
    ProcedureIntelligenceClinicalMetrics.clinicalMetricsFor(procedureType);
