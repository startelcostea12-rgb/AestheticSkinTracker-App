// ignore_for_file: unused_element
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

enum EvidenceLevel { gradeA, gradeB, expertConsensus }

extension EvidenceLevelExt on EvidenceLevel {
  String get label {
    switch (this) {
      case EvidenceLevel.gradeA:
        return 'Grade A';
      case EvidenceLevel.gradeB:
        return 'Grade B';
      case EvidenceLevel.expertConsensus:
        return 'Expert Consensus';
    }
  }

  Color get color {
    switch (this) {
      case EvidenceLevel.gradeA:
        return const Color(0xFF2E7D32);
      case EvidenceLevel.gradeB:
        return const Color(0xFFE65100);
      case EvidenceLevel.expertConsensus:
        return const Color(0xFF1565C0);
    }
  }
}

enum IssueSeverity { mild, moderate, severe }

extension IssueSeverityExt on IssueSeverity {
  String get label {
    switch (this) {
      case IssueSeverity.mild:
        return 'Mild';
      case IssueSeverity.moderate:
        return 'Moderate';
      case IssueSeverity.severe:
        return 'Severe';
    }
  }

  Color get color {
    switch (this) {
      case IssueSeverity.mild:
        return const Color(0xFFFF8F00);
      case IssueSeverity.moderate:
        return const Color(0xFFE65100);
      case IssueSeverity.severe:
        return const Color(0xFFB71C1C);
    }
  }

  Color get bgColor {
    switch (this) {
      case IssueSeverity.mild:
        return const Color(0xFFFFF8E1);
      case IssueSeverity.moderate:
        return const Color(0xFFFBE9E7);
      case IssueSeverity.severe:
        return const Color(0xFFFFEBEE);
    }
  }
}

class ScarDetectedIssue {
  final String name;
  final IssueSeverity severity;
  final IconData icon;
  final String clinicalNote;
  final String metricValue;

  const ScarDetectedIssue({
    required this.name,
    required this.severity,
    required this.icon,
    required this.clinicalNote,
    required this.metricValue,
  });
}

class ScarProductRecommendation {
  final String productName;
  final String brandExamples;
  final String category;
  final IconData icon;
  final Color accentColor;
  final String indication; // the scar finding that triggers this
  final String mechanism; // brief clinical rationale
  final String applicationNote;
  final EvidenceLevel evidenceLevel;
  final int priorityScore; // 1–100 (higher = listed first)
  final bool prescriptionOnly;

  const ScarProductRecommendation({
    required this.productName,
    required this.brandExamples,
    required this.category,
    required this.icon,
    required this.accentColor,
    required this.indication,
    required this.mechanism,
    required this.applicationNote,
    required this.evidenceLevel,
    required this.priorityScore,
    this.prescriptionOnly = false,
  });
}

class ScarAiAnalysisResult {
  final String overallAssessment;
  final String healingPhaseContext;
  final List<ScarDetectedIssue> detectedIssues;
  final List<ScarProductRecommendation> recommendations;
  final String clinicalDisclaimer;

  const ScarAiAnalysisResult({
    required this.overallAssessment,
    required this.healingPhaseContext,
    required this.detectedIssues,
    required this.recommendations,
    required this.clinicalDisclaimer,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  ANALYSIS ENGINE
// ═══════════════════════════════════════════════════════════════════════════

// Minimal ScarMetrics interface — matched to the one defined in
// scar_healing_tracker_screen.dart to avoid a circular dependency.
// The engine works purely on the numeric values passed to it.

class ScarAiAnalysisEngine {
  ScarAiAnalysisEngine._();

  static ScarAiAnalysisResult analyze({
    required double redness,
    required double elevation,
    required double colorMatch,
    required double texture,
    required double pliability,
    required double itchiness,
    required double pain,
    required double healingScore,
    // baseline values for delta context
    required double baseRedness,
    required double baseElevation,
    required double baseColorMatch,
    required double baseTexture,
    required double basePliability,
    required double baseItchiness,
    required double basePain,
    required double baseHealingScore,
    required int daysSinceBaseline,
    required String healingStageLabel,
  }) {
    final issues = <ScarDetectedIssue>[];
    final Set<String> triggeredCategories = {};
    final recMap = <String, ScarProductRecommendation>{};

    // ── Helper: add recommendation (deduplicates by productName) ──────────
    void addRec(ScarProductRecommendation rec) {
      recMap.putIfAbsent(rec.productName, () => rec);
    }

    // ── Helper: bump priority of an existing recommendation ───────────────
    void bumpPriority(String productName, int bonus) {
      if (recMap.containsKey(productName)) {
        final existing = recMap[productName]!;
        recMap[productName] = ScarProductRecommendation(
          productName: existing.productName,
          brandExamples: existing.brandExamples,
          category: existing.category,
          icon: existing.icon,
          accentColor: existing.accentColor,
          indication: existing.indication,
          mechanism: existing.mechanism,
          applicationNote: existing.applicationNote,
          evidenceLevel: existing.evidenceLevel,
          priorityScore: (existing.priorityScore + bonus).clamp(0, 100),
          prescriptionOnly: existing.prescriptionOnly,
        );
      }
    }

    // ── 1. ERYTHEMA / REDNESS ─────────────────────────────────────────────
    if (redness >= 8.0) {
      issues.add(
        ScarDetectedIssue(
          name: 'Severe Erythema',
          severity: IssueSeverity.severe,
          icon: Icons.local_fire_department_outlined,
          clinicalNote:
              'Intense vascular activity consistent with active inflammatory or early proliferative phase. Microvascular density remains markedly elevated.',
          metricValue: '${redness.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('erythema_severe');
    } else if (redness >= 6.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Moderate-to-High Erythema',
          severity: IssueSeverity.moderate,
          icon: Icons.local_fire_department_outlined,
          clinicalNote:
              'Persistent post-inflammatory erythema (PIE) or active neovascularisation. Risk of worsening with UV exposure and thermal stimuli.',
          metricValue: '${redness.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('erythema_moderate');
    }

    if (triggeredCategories.contains('erythema_severe') ||
        triggeredCategories.contains('erythema_moderate')) {
      addRec(
        const ScarProductRecommendation(
          productName: 'Silicone Gel (topical film)',
          brandExamples: 'Kelo-Cote, Dermatix Ultra, ScarGel',
          category: 'Topical Scar Therapy',
          icon: Icons.science_outlined,
          accentColor: Color(0xFF6A1B9A),
          indication: 'Active erythema & post-inflammatory vascular excess',
          mechanism:
              'Forms an occlusive silicone film over the scar surface, normalising transepidermal water loss (TEWL), modulating fibroblast cytokine output, and dampening neovascularisation. RCT data show 40–50% reduction in erythema over 12 weeks of continuous use.',
          applicationNote:
              'Apply a thin layer twice daily to fully epithelialised scar. Allow to dry 2 min before clothing contact. Use for a minimum of 3 months.',
          evidenceLevel: EvidenceLevel.gradeA,
          priorityScore: 88,
        ),
      );
      triggeredCategories.add('silicone_gel');
    }

    // PIE-specific: persistent high redness with poor color match
    if (redness >= 7.0 && colorMatch <= 4.0) {
      addRec(
        const ScarProductRecommendation(
          productName: 'Azelaic Acid 20% Cream',
          brandExamples: 'Finacea, Azelex, Skinoren',
          category: 'Pigmentation Management',
          icon: Icons.colorize_outlined,
          accentColor: Color(0xFF6A1B9A),
          indication:
              'Post-inflammatory erythema (PIE) with concurrent pigmentation mismatch',
          mechanism:
              'Inhibits tyrosinase and mitochondrial oxidoreductases selectively in hyperactive melanocytes, reducing both erythema-related chromophore deposition and melanin overproduction. Anti-inflammatory secondary pathway via neutrophil inhibition.',
          applicationNote:
              'Apply twice daily after cleansing. Combine with SPF 50+ (applied last). Full effect typically seen at 8–12 weeks.',
          evidenceLevel: EvidenceLevel.gradeA,
          priorityScore: 75,
        ),
      );
    }

    // ── 2. ELEVATION / SCAR HEIGHT ────────────────────────────────────────
    if (elevation >= 7.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Markedly Raised Scar Profile',
          severity: IssueSeverity.severe,
          icon: Icons.layers_outlined,
          clinicalNote:
              'Scar height consistent with hypertrophic pattern. Excessive type-III collagen deposition without adequate remodelling. Contracture risk if overlying a joint.',
          metricValue: '${elevation.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('elevation_severe');
    } else if (elevation >= 5.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Elevated Scar Profile',
          severity: daysSinceBaseline > 60
              ? IssueSeverity.moderate
              : IssueSeverity.mild,
          icon: Icons.layers_outlined,
          clinicalNote:
              'Above-baseline elevation with active collagen deposition. Normal in the proliferative phase (day 22–60); persistence beyond 60 days warrants compression intervention.',
          metricValue: '${elevation.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('elevation_moderate');
    }

    if (triggeredCategories.contains('elevation_severe') ||
        triggeredCategories.contains('elevation_moderate')) {
      addRec(
        const ScarProductRecommendation(
          productName: 'Silicone Gel Sheeting',
          brandExamples: 'Mepiform, ScarAway Silicone Sheets, Cica-Care',
          category: 'Occlusive Compression Therapy',
          icon: Icons.compress_outlined,
          accentColor: Color(0xFF0277BD),
          indication: 'Raised / hypertrophic scar profile',
          mechanism:
              'Sustained semi-occlusion creates a negative-pressure microenvironment that mechanically flattens elevated collagen. Silicone polymers inhibit TGF-β1-driven fibroblast proliferation and promote collagenase activity, with ≥12 RCTs demonstrating 50–60% reduction in scar height vs. untreated controls.',
          applicationNote:
              'Apply directly to closed scar for ≥12 h/day (ideally 22–23 h). Wash daily with mild soap. Begin as soon as wound is fully epithelialised. Minimum treatment course: 3 months; continue to 6–12 months for best outcomes.',
          evidenceLevel: EvidenceLevel.gradeA,
          priorityScore: 95,
        ),
      );

      if (triggeredCategories.contains('elevation_severe') &&
          daysSinceBaseline > 60) {
        addRec(
          const ScarProductRecommendation(
            productName: 'Medical Compression Garment',
            brandExamples: 'Jobskin, Medi, JUZO',
            category: 'Pressure Therapy',
            icon: Icons.airline_seat_flat_angled,
            accentColor: Color(0xFF0277BD),
            indication: 'Persistent hypertrophic elevation beyond 60 days',
            mechanism:
                'Delivers controlled sustained pressure (15–40 mmHg) that increases collagenase activity, reduces collagen fibre density, and inhibits fibrovascular proliferation. Prospective trials report 60–70% scar height reduction for burn scars treated within the proliferative window.',
            applicationNote:
                'Custom-fitted garment worn 23 h/day for 6–12 months. Remove only for hygiene. Consult an occupational therapist or certified orthotist for correct pressure calibration.',
            evidenceLevel: EvidenceLevel.gradeA,
            priorityScore: 82,
          ),
        );
      }
    }

    // ── 3. POOR COLOUR MATCH / PIGMENTATION ──────────────────────────────
    if (colorMatch <= 2.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Significant Pigmentation Mismatch',
          severity: IssueSeverity.severe,
          icon: Icons.palette_outlined,
          clinicalNote:
              'Marked dyschromia indicating post-inflammatory hyperpigmentation (PIH) or hypopigmentation. Unprotected UV exposure is the primary modifiable driver.',
          metricValue: '${colorMatch.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('pigment_severe');
    } else if (colorMatch <= 4.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Colour Mismatch',
          severity: IssueSeverity.moderate,
          icon: Icons.palette_outlined,
          clinicalNote:
              'Noticeable deviation from surrounding skin tone, consistent with active post-inflammatory pigmentation. SPF protection is critical at this stage.',
          metricValue: '${colorMatch.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('pigment_moderate');
    }

    if (triggeredCategories.contains('pigment_severe') ||
        triggeredCategories.contains('pigment_moderate')) {
      addRec(
        const ScarProductRecommendation(
          productName: 'Broad-Spectrum Mineral SPF 50+',
          brandExamples:
              'EltaMD UV Clear, La Roche-Posay Anthelios, ISDIN Eryfotona',
          category: 'Photoprotection',
          icon: Icons.wb_sunny_outlined,
          accentColor: Color(0xFFF57F17),
          indication:
              'Active pigmentation mismatch and post-inflammatory dyschromia',
          mechanism:
              'UV radiation activates melanocytes in the regenerating dermis, triggering melanin overproduction and permanent post-inflammatory hyperpigmentation (PIH). Mineral SPF (zinc oxide / titanium dioxide) provides broad-spectrum UVA+UVB attenuation without chemical penetration, making it safe for healing skin. Single most evidence-supported intervention for preventing PIH deterioration.',
          applicationNote:
              'Apply 15 min before sun exposure, every morning without exception. Reapply every 2 hours during outdoor activity. Use for a minimum of 12 months post-injury — scar dermis remains photosensitive long after clinical closure.',
          evidenceLevel: EvidenceLevel.gradeA,
          priorityScore: 90,
        ),
      );

      addRec(
        const ScarProductRecommendation(
          productName: 'Niacinamide 10% Serum',
          brandExamples:
              'The Ordinary Niacinamide 10% + Zinc, Paula\'s Choice 10% Niacinamide Booster',
          category: 'Pigmentation & Barrier Support',
          icon: Icons.opacity_outlined,
          accentColor: Color(0xFF00695C),
          indication:
              'Post-inflammatory hyperpigmentation and barrier disruption',
          mechanism:
              'Inhibits melanosome transfer from melanocytes to keratinocytes, reducing melanin deposition in the epidermis. Concurrently upregulates ceramide synthesis, reinforcing barrier integrity and reducing TEWL. Non-irritating at 10% concentration, compatible with all Fitzpatrick skin types.',
          applicationNote:
              'Apply once daily to scar and surrounding skin before SPF. Can be layered under silicone gel formulations. Allow 60 seconds of absorption time before next product.',
          evidenceLevel: EvidenceLevel.gradeB,
          priorityScore: 68,
        ),
      );

      if (triggeredCategories.contains('pigment_severe')) {
        addRec(
          const ScarProductRecommendation(
            productName: 'Hydroquinone 4% Cream',
            brandExamples: 'Tri-Luma (Rx), generic hydroquinone 4% (Rx)',
            category: 'Depigmentation Agent',
            icon: Icons.colorize_outlined,
            accentColor: Color(0xFF4A148C),
            indication:
                'Confirmed post-inflammatory hyperpigmentation (PIH) — moderate-to-severe',
            mechanism:
                'Gold-standard tyrosinase inhibitor. Competitively inhibits conversion of L-DOPA to melanin in melanosomes, with progressive pigment lightening over 8–12 weeks. More potent than azelaic acid for established PIH.',
            applicationNote:
                'Apply a pea-sized amount to hyperpigmented areas only, twice daily. Not for use on unhealed skin. Use concurrently with SPF 50+. Limit continuous use to 5 months; cycle off to prevent ochronosis. Prescription required.',
            evidenceLevel: EvidenceLevel.gradeA,
            priorityScore: 72,
            prescriptionOnly: true,
          ),
        );
      }
    }

    // ── 4. ROUGH TEXTURE / SURFACE IRREGULARITY ───────────────────────────
    if (texture <= 2.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Significant Surface Irregularity',
          severity: IssueSeverity.severe,
          icon: Icons.texture_outlined,
          clinicalNote:
              'Coarse fibrous surface indicating dense cross-linked type-III collagen matrix. Epithelial architecture is markedly disrupted.',
          metricValue: '${texture.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('texture_severe');
    } else if (texture <= 4.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Surface Roughness',
          severity: IssueSeverity.moderate,
          icon: Icons.texture_outlined,
          clinicalNote:
              'Above-normal surface irregularity consistent with active fibroblastic activity and incomplete epidermal resurfacing.',
          metricValue: '${texture.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('texture_moderate');
    }

    if (triggeredCategories.contains('texture_severe') ||
        triggeredCategories.contains('texture_moderate')) {
      addRec(
        const ScarProductRecommendation(
          productName: 'Onion Extract + Heparin Gel',
          brandExamples: 'Contractubex, Mederma Advanced Scar Gel',
          category: 'Topical Scar Softening',
          icon: Icons.eco_outlined,
          accentColor: Color(0xFF33691E),
          indication: 'Surface texture irregularity and fibrotic scar activity',
          mechanism:
              'Quercetin (Allium cepa extract) exerts anti-proliferative effects on fibroblasts and inhibits histamine-driven collagen synthesis. Heparin enhances tissue hydration and disrupts organised collagen fibres. Allantoin promotes keratinocyte differentiation and surface cell turnover. Most effective when combined with regular cross-friction massage.',
          applicationNote:
              'Apply to scar 3× daily and massage firmly in circular motions for 4–5 minutes per session. Begin after full epithelialisation. Combine with silicone gel for additive benefit. Treatment course: minimum 3 months.',
          evidenceLevel: EvidenceLevel.gradeB,
          priorityScore: 62,
        ),
      );

      if (daysSinceBaseline >= 70) {
        addRec(
          const ScarProductRecommendation(
            productName: 'Tretinoin 0.025% Cream',
            brandExamples: 'Retin-A, Stieva-A (prescription)',
            category: 'Topical Retinoid',
            icon: Icons.science_outlined,
            accentColor: Color(0xFF880E4F),
            indication:
                'Persistent surface irregularity in the remodelling phase (10+ weeks post-closure)',
            mechanism:
                'Accelerates keratinocyte turnover via RAR-β/γ nuclear receptor activation, reducing corneocyte accumulation on the scar surface. Upregulates type-I collagen synthesis and suppresses MMP-mediated degradation, improving overall architectural quality. Reduces post-acne and surgical scar depth in randomised trials.',
            applicationNote:
                'Apply a rice-grain amount every other night. Do not use on actively inflamed or unhealed skin. Full onset of benefit at 12–16 weeks. Must be used with daily SPF 50+. Prescription required.',
            evidenceLevel: EvidenceLevel.gradeB,
            priorityScore: 65,
            prescriptionOnly: true,
          ),
        );
      }
    }

    // ── 5. REDUCED PLIABILITY / STIFFNESS ─────────────────────────────────
    if (pliability <= 2.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Severe Scar Stiffness',
          severity: IssueSeverity.severe,
          icon: Icons.compress_outlined,
          clinicalNote:
              'Dense cross-linked collagen with markedly restricted extensibility. High risk of functional contracture, especially in periarticular locations.',
          metricValue: '${pliability.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('pliability_severe');
    } else if (pliability <= 4.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Reduced Pliability',
          severity: IssueSeverity.moderate,
          icon: Icons.compress_outlined,
          clinicalNote:
              'Fibrotic collagen organisation reducing scar extensibility. Cross-friction massage and occlusive therapy are first-line interventions.',
          metricValue: '${pliability.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('pliability_moderate');
    }

    if (triggeredCategories.contains('pliability_severe') ||
        triggeredCategories.contains('pliability_moderate')) {
      // Silicone sheeting covers both elevation and pliability
      if (!recMap.containsKey('Silicone Gel Sheeting')) {
        addRec(
          const ScarProductRecommendation(
            productName: 'Silicone Gel Sheeting',
            brandExamples: 'Mepiform, ScarAway Silicone Sheets, Cica-Care',
            category: 'Occlusive Compression Therapy',
            icon: Icons.compress_outlined,
            accentColor: Color(0xFF0277BD),
            indication: 'Reduced scar pliability and fibrotic collagen binding',
            mechanism:
                'Sustained semi-occlusion creates a negative-pressure microenvironment that mechanically flattens elevated collagen. Silicone polymers inhibit TGF-β1-driven fibroblast proliferation and promote collagenase activity, improving extensibility in 3–6 months of consistent use.',
            applicationNote:
                'Apply directly to closed scar for ≥12 h/day. Wash daily with mild soap. Begin as soon as wound is fully epithelialised. Minimum treatment course: 3 months.',
            evidenceLevel: EvidenceLevel.gradeA,
            priorityScore: 85,
          ),
        );
      } else {
        bumpPriority('Silicone Gel Sheeting', 10);
      }

      addRec(
        const ScarProductRecommendation(
          productName: 'Silicone Massage Oil',
          brandExamples: 'Bio-Oil, Dermatix Silicone Gel (as massage medium)',
          category: 'Massage Therapy Medium',
          icon: Icons.water_drop_outlined,
          accentColor: Color(0xFF0277BD),
          indication: 'Stiff scar requiring mechanical mobilisation',
          mechanism:
              'Provides a low-friction lubrication medium for cross-friction massage, enabling sustained mechanical loading of the dermal collagen matrix without surface trauma. Silicone vehicle simultaneously delivers occlusive therapy. Daily massage (4–5 min, circular cross-friction technique) increases collagenase activity and reorients collagen fibres towards a more parallel, pliable architecture.',
          applicationNote:
              'Apply 1–2 drops to the scar surface. Massage using firm circular or cross-friction strokes for 4–5 minutes, twice daily. Best combined with silicone sheeting for 12+ hours thereafter.',
          evidenceLevel: EvidenceLevel.gradeB,
          priorityScore: 70,
        ),
      );
    }

    if (triggeredCategories.contains('pliability_severe')) {
      addRec(
        const ScarProductRecommendation(
          productName: 'Physiotherapy — Therapeutic Ultrasound',
          brandExamples: 'Clinical procedure (1 MHz pulsed US, 1.0 W/cm²)',
          category: 'Physical Therapy',
          icon: Icons.sensors_outlined,
          accentColor: Color(0xFF01579B),
          indication:
              'Severe scar stiffness and deep fibrosis unresponsive to topical measures',
          mechanism:
              'Pulsed therapeutic ultrasound (1 MHz, 1.0 W/cm², 50% duty cycle) generates micro-vibrations that increase collagen fibre extensibility, disrupt cross-linked fibrous adhesions, and improve tissue perfusion. Penetrates 2–3 cm, reaching deep dermal and subdermal fibrosis inaccessible to topical agents.',
          applicationNote:
              'Administered by a physiotherapist or rehabilitation specialist. Typical protocol: 5 minutes per session, 3× weekly for 6–8 weeks. Combine with progressive stretching exercises to consolidate range-of-motion gains.',
          evidenceLevel: EvidenceLevel.gradeB,
          priorityScore: 60,
        ),
      );
    }

    // ── 6. HIGH ITCHINESS / PRURITUS ─────────────────────────────────────
    if (itchiness >= 8.0) {
      issues.add(
        ScarDetectedIssue(
          name: 'Severe Scar Pruritus',
          severity: IssueSeverity.severe,
          icon: Icons.back_hand_outlined,
          clinicalNote:
              'Intense neurogenic itch consistent with active C-fibre regeneration through the healing dermis. Scratching amplifies mast-cell degranulation and perpetuates a neurogenic inflammatory loop.',
          metricValue: '${itchiness.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('itch_severe');
    } else if (itchiness >= 6.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Elevated Pruritus',
          severity: IssueSeverity.moderate,
          icon: Icons.back_hand_outlined,
          clinicalNote:
              'Moderate scar itch, likely driven by nerve fibre regeneration and inflammatory mediator release. Consistent itch control reduces secondary trauma from scratching.',
          metricValue: '${itchiness.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('itch_moderate');
    }

    if (triggeredCategories.contains('itch_severe') ||
        triggeredCategories.contains('itch_moderate')) {
      addRec(
        const ScarProductRecommendation(
          productName: '1% Hydrocortisone Cream',
          brandExamples: 'Cortaid Maximum Strength, Aveeno 1% HC, Dermacort',
          category: 'Topical Anti-inflammatory',
          icon: Icons.local_pharmacy_outlined,
          accentColor: Color(0xFFAD1457),
          indication: 'Neurogenic inflammatory scar itch',
          mechanism:
              'Low-potency topical corticosteroid that reduces local mast-cell degranulation and suppresses the release of histamine, substance P, and prostaglandins into the healing dermis. Breaks the itch–scratch neurogenic feedback cycle. Suitable for short-course use on intact scar surface.',
          applicationNote:
              'Apply a thin layer to the itchy scar area 1–2× daily. Do not use under occlusion. Limit to 5–7 consecutive days without medical review. Do not apply to open or actively inflamed wounds.',
          evidenceLevel: EvidenceLevel.gradeB,
          priorityScore: 72,
        ),
      );

      if (triggeredCategories.contains('itch_severe')) {
        addRec(
          const ScarProductRecommendation(
            productName: 'Non-sedating Oral Antihistamine (Cetirizine 10 mg)',
            brandExamples:
                'Zyrtec (cetirizine), Claritin (loratadine), Xyzal (levocetirizine)',
            category: 'Systemic Antipruritic',
            icon: Icons.medication_outlined,
            accentColor: Color(0xFFAD1457),
            indication: 'Severe histamine-mediated scar pruritus',
            mechanism:
                'H1-receptor antagonism reduces systemic and peripheral histamine-driven itch. Cetirizine has a preferential affinity for peripheral H1 receptors, minimising sedation while providing sustained 24-hour antipruritic coverage. Nocte dosing (bedtime) leverages mild sedative effect to improve itch-disrupted sleep.',
            applicationNote:
                'Take 10 mg once daily, preferably at bedtime. Continue for 2–4 weeks then reassess. Safe for long-term use under physician guidance. Loratadine 10 mg/day is a non-sedating alternative for daytime use.',
            evidenceLevel: EvidenceLevel.gradeB,
            priorityScore: 65,
          ),
        );
      }
    }

    // ── 7. HIGH PAIN LEVEL ────────────────────────────────────────────────
    if (pain >= 7.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Significant Scar Tenderness',
          severity: IssueSeverity.severe,
          icon: Icons.sentiment_very_dissatisfied_outlined,
          clinicalNote:
              'High nociceptive activity consistent with elevated prostaglandin and bradykinin levels in the healing tissue. Persistent tenderness beyond 12 weeks warrants neuropathic pain assessment.',
          metricValue: '${pain.toStringAsFixed(1)}/10',
        ),
      );
      triggeredCategories.add('pain_severe');
      addRec(
        const ScarProductRecommendation(
          productName: 'Topical Diclofenac 1% Gel',
          brandExamples:
              'Voltaren Arthritis Pain Gel, Solaraze, generic diclofenac 1%',
          category: 'Topical NSAID',
          icon: Icons.healing_outlined,
          accentColor: Color(0xFFC62828),
          indication: 'Scar tenderness and localised nociceptive inflammation',
          mechanism:
              'Cyclooxygenase-1/2 inhibition in the scar tissue reduces prostaglandin E2 synthesis, directly attenuating sensitisation of nociceptors without significant systemic absorption. Avoids GI side effects associated with oral NSAIDs. Penetrates to a depth of 3–4 mm.',
          applicationNote:
              'Apply 2–4 g to the scar and surrounding tissue, 4× daily. Rub in gently — do not massage aggressively over highly tender areas. Wash hands after application. Avoid use on broken skin. Maximum 2 g per application site per dose.',
          evidenceLevel: EvidenceLevel.gradeB,
          priorityScore: 74,
        ),
      );
    } else if (pain >= 5.5) {
      issues.add(
        ScarDetectedIssue(
          name: 'Moderate Scar Sensitivity',
          severity: IssueSeverity.moderate,
          icon: Icons.sentiment_dissatisfied_outlined,
          clinicalNote:
              'Moderate nociceptive sensitivity; likely prostaglandin-mediated. Gentle mechanical desensitisation may reduce allodynic response over time.',
          metricValue: '${pain.toStringAsFixed(1)}/10',
        ),
      );
    }

    // ── 8. UNIVERSAL SILICONE GEL (if no scar-specific ones added yet) ───
    // Ensure silicone gel is always recommended for any active scar with >1 metric flagged
    if (issues.isNotEmpty &&
        !recMap.containsKey('Silicone Gel (topical film)')) {
      addRec(
        const ScarProductRecommendation(
          productName: 'Silicone Gel (topical film)',
          brandExamples: 'Kelo-Cote, Dermatix Ultra, ScarGel',
          category: 'Topical Scar Therapy',
          icon: Icons.science_outlined,
          accentColor: Color(0xFF6A1B9A),
          indication: 'Multi-domain scar management',
          mechanism:
              'Forms an occlusive silicone film over the scar surface, normalising transepidermal water loss (TEWL), modulating fibroblast cytokine output, and dampening neovascularisation. Grade A evidence across redness, elevation, and pliability outcomes.',
          applicationNote:
              'Apply a thin layer twice daily to fully epithelialised scar. Allow to dry 2 min before clothing contact. Use for a minimum of 3 months.',
          evidenceLevel: EvidenceLevel.gradeA,
          priorityScore: 80,
        ),
      );
    }

    // ── Build sorted recommendation list ──────────────────────────────────
    final recommendations = recMap.values.toList()
      ..sort((a, b) => b.priorityScore.compareTo(a.priorityScore));

    // ── Generate overall assessment text ──────────────────────────────────
    final String overallAssessment = _generateAssessmentText(
      redness: redness,
      elevation: elevation,
      colorMatch: colorMatch,
      texture: texture,
      pliability: pliability,
      itchiness: itchiness,
      pain: pain,
      healingScore: healingScore,
      baseHealingScore: baseHealingScore,
      daysSinceBaseline: daysSinceBaseline,
      healingStageLabel: healingStageLabel,
      issueCount: issues.length,
    );

    final String phaseContext = _phaseContextText(
      healingStageLabel: healingStageLabel,
      daysSinceBaseline: daysSinceBaseline,
    );

    return ScarAiAnalysisResult(
      overallAssessment: overallAssessment,
      healingPhaseContext: phaseContext,
      detectedIssues: issues,
      recommendations: recommendations,
      clinicalDisclaimer:
          'This analysis is generated from photo-derived metric data and is intended for informational purposes only. It does not constitute medical advice, diagnosis, or a prescription. Consult a licensed dermatologist or plastic surgeon before commencing any new treatment, especially prescription products.',
    );
  }

  static String _generateAssessmentText({
    required double redness,
    required double elevation,
    required double colorMatch,
    required double texture,
    required double pliability,
    required double itchiness,
    required double pain,
    required double healingScore,
    required double baseHealingScore,
    required int daysSinceBaseline,
    required String healingStageLabel,
    required int issueCount,
  }) {
    final scoreDelta = healingScore - baseHealingScore;
    final scoreStr = healingScore.round().toString();

    if (issueCount == 0) {
      if (healingScore >= 70) {
        return 'Scar Maturity Score of $scoreStr/100 with no significant metric deviations detected. '
            'All seven assessment domains are within acceptable parameters for the $healingStageLabel phase. '
            'Continue your established scar management protocol and maintain photoprotection.';
      }
      return 'No critical metric thresholds exceeded. Scar profile ($scoreStr/100) is within expected range for this healing stage. '
          'Continue current protocol; schedule next assessment in 2–4 weeks to capture the next measurable change window.';
    }

    final dominantIssue = redness >= 7.0
        ? 'active erythema'
        : elevation >= 6.0
        ? 'raised scar profile'
        : pliability <= 3.5
        ? 'reduced pliability'
        : colorMatch <= 3.5
        ? 'pigmentation mismatch'
        : 'residual surface irregularity';

    final progressNote = scoreDelta >= 5
        ? 'Scar Maturity Score has improved ${scoreDelta.round()} pts from baseline ($scoreStr/100), '
              'indicating positive healing trajectory. '
        : scoreDelta <= -5
        ? 'Maturity Score shows a ${scoreDelta.abs().round()}-pt regression from baseline ($scoreStr/100), '
              'warranting a protocol review. '
        : 'Maturity Score of $scoreStr/100 with minimal net change from baseline. ';

    return '${progressNote}Analysis has identified $issueCount area${issueCount == 1 ? '' : 's'} of clinical concern, '
        'with $dominantIssue as the primary finding in the $healingStageLabel phase. '
        'Evidence-based product recommendations are ranked below by clinical priority.';
  }

  static String _phaseContextText({
    required String healingStageLabel,
    required int daysSinceBaseline,
  }) {
    if (daysSinceBaseline <= 21) {
      return 'Day $daysSinceBaseline · $healingStageLabel — Angiogenesis and cellular debris clearance are the primary biological activities. Topical silicone therapy should begin as soon as epidermal closure is confirmed.';
    } else if (daysSinceBaseline <= 60) {
      return 'Day $daysSinceBaseline · $healingStageLabel — Fibroblasts are actively synthesising type-III collagen and new vasculature is forming. This window is critical for compression and occlusion therapy to limit hypertrophic progression.';
    } else if (daysSinceBaseline <= 180) {
      return 'Day $daysSinceBaseline · $healingStageLabel — Type-III collagen is converting to stronger type-I fibrils. Scar height, redness, and pliability should improve measurably across this phase with consistent therapy.';
    } else {
      return 'Day $daysSinceBaseline · $healingStageLabel — Collagen alignment is optimising and vascularity is regressing. This is the optimal window for aesthetic refinement procedures (fractional laser, RF microneedling) if residual texture or pigmentation remains.';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  UI: MODAL BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════

class ScarAiAnalysisSheet extends StatefulWidget {
  final ScarAiAnalysisResult result;
  final Uint8List? latestImage;
  final Uint8List? baselineImage;

  const ScarAiAnalysisSheet({
    super.key,
    required this.result,
    this.latestImage,
    this.baselineImage,
  });

  static Future<void> show(
    BuildContext context, {
    required ScarAiAnalysisResult result,
    Uint8List? latestImage,
    Uint8List? baselineImage,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScarAiAnalysisSheet(
        result: result,
        latestImage: latestImage,
        baselineImage: baselineImage,
      ),
    );
  }

  @override
  State<ScarAiAnalysisSheet> createState() => _ScarAiAnalysisSheetState();
}

class _ScarAiAnalysisSheetState extends State<ScarAiAnalysisSheet>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.93,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              // Header
              _buildHeader(),
              const Divider(height: 1, thickness: 1),
              // Scrollable body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Phase context chip
                      _buildPhaseContextBanner(result.healingPhaseContext),
                      const SizedBox(height: 16),
                      // Overall Assessment
                      _buildAssessmentCard(result.overallAssessment),
                      const SizedBox(height: 20),
                      // Detected Issues
                      if (result.detectedIssues.isNotEmpty) ...[
                        _sectionLabel(
                          'Detected Clinical Findings',
                          Icons.find_in_page_outlined,
                          'Scan results',
                        ),
                        const SizedBox(height: 10),
                        _buildIssuesList(result.detectedIssues),
                        const SizedBox(height: 22),
                      ],
                      // Product Recommendations
                      if (result.recommendations.isNotEmpty) ...[
                        _sectionLabel(
                          'Evidence-Based Product Recommendations',
                          Icons.medication_liquid_outlined,
                          'Curated protocol',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ranked by clinical priority based on detected findings',
                          style: TextStyle(
                            fontSize: 12,
                            color: MyApp.textBrown.withValues(alpha: 0.50),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...result.recommendations.asMap().entries.map(
                          (e) => _buildProductCard(e.value, e.key + 1),
                        ),
                      ],
                      // Disclaimer
                      const SizedBox(height: 8),
                      _buildDisclaimer(result.clinicalDisclaimer),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6A1B9A).withValues(alpha: 0.15),
                  MyApp.roseGold.withValues(alpha: 0.15),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.biotech_outlined,
              color: Color(0xFF6A1B9A),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Scar Analysis',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3F2A2A),
                  ),
                ),
                Text(
                  'Dermatology-grade assessment · Photo metric analysis',
                  style: TextStyle(
                    fontSize: 12,
                    color: MyApp.textBrown.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close_rounded,
              color: MyApp.textBrown.withValues(alpha: 0.45),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseContextBanner(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.schedule_outlined,
            size: 16,
            color: Color(0xFF2E7D32),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: MyApp.textBrown.withValues(alpha: 0.80),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssessmentCard(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6A1B9A).withValues(alpha: 0.07),
            MyApp.roseGold.withValues(alpha: 0.07),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF6A1B9A).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.summarize_outlined,
                size: 16,
                color: Color(0xFF6A1B9A),
              ),
              const SizedBox(width: 8),
              Text(
                'Clinical Assessment Summary',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF6A1B9A).withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: MyApp.textBrown.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssuesList(List<ScarDetectedIssue> issues) {
    return Column(
      children: issues.map((issue) => _buildIssueRow(issue)).toList(),
    );
  }

  Widget _buildIssueRow(ScarDetectedIssue issue) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: issue.severity.bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: issue.severity.color.withValues(alpha: 0.35),
          width: 1.4,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: issue.severity.color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(issue.icon, size: 17, color: issue.severity.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        issue.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: MyApp.textBrown,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Severity badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: issue.severity.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: issue.severity.color.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        issue.severity.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: issue.severity.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Metric value badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        issue.metricValue,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: MyApp.textBrown.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  issue.clinicalNote,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: MyApp.textBrown.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(ScarProductRecommendation rec, int rank) {
    final isRx = rec.prescriptionOnly;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: rec.accentColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: rec.accentColor.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: rec.accentColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(17),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rank circle
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: rec.accentColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              rec.productName,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: MyApp.textBrown,
                              ),
                            ),
                          ),
                          // Evidence badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: rec.evidenceLevel.color.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: rec.evidenceLevel.color.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            ),
                            child: Text(
                              rec.evidenceLevel.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: rec.evidenceLevel.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: rec.accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              rec.category,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: rec.accentColor,
                              ),
                            ),
                          ),
                          if (isRx) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFB71C1C,
                                ).withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(
                                    0xFFB71C1C,
                                  ).withValues(alpha: 0.45),
                                ),
                              ),
                              child: const Text(
                                'Rx — Prescription Required',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB71C1C),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Card body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand examples
                _infoRow(
                  Icons.local_pharmacy_outlined,
                  'Examples',
                  rec.brandExamples,
                  MyApp.roseGold,
                ),
                const SizedBox(height: 10),
                // Why this is recommended
                _bodySection(
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: const Color(0xFF2E7D32),
                  label: 'Why recommended',
                  body: 'Indicated for: ${rec.indication}.',
                ),
                const SizedBox(height: 8),
                // Mechanism
                _bodySection(
                  icon: Icons.biotech_outlined,
                  iconColor: rec.accentColor,
                  label: 'Clinical mechanism',
                  body: rec.mechanism,
                ),
                const SizedBox(height: 8),
                // Application note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F8FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.assignment_outlined,
                        size: 15,
                        color: Color(0xFF1565C0),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Application & Dosing',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              rec.applicationNote,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.5,
                                color: MyApp.textBrown.withValues(alpha: 0.78),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodySection({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: MyApp.textBrown.withValues(alpha: 0.78),
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color iconColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 7),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 12.5,
                color: MyApp.textBrown.withValues(alpha: 0.78),
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisclaimer(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: Colors.grey.shade500,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, IconData icon, [String? eyebrow]) {
    return ClinicalSectionHeader(icon: icon, title: title, eyebrow: eyebrow);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  INLINE BANNER CARD (shown in the main screen before tapping into the sheet)
// ═══════════════════════════════════════════════════════════════════════════

class ScarAiAnalysisBannerCard extends StatelessWidget {
  final ScarAiAnalysisResult result;
  final VoidCallback onTap;

  const ScarAiAnalysisBannerCard({
    super.key,
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final issueCount = result.detectedIssues.length;
    final recCount = result.recommendations.length;
    final hasFindings = issueCount > 0;

    final Color headerColor = hasFindings
        ? const Color(0xFF6A1B9A)
        : const Color(0xFF2E7D32);
    final Color headerBg = hasFindings
        ? const Color(0xFF6A1B9A).withValues(alpha: 0.07)
        : const Color(0xFF2E7D32).withValues(alpha: 0.07);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: headerColor.withValues(alpha: 0.28),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: headerColor.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: headerBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(19),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: headerColor.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.biotech_outlined,
                      size: 18,
                      color: headerColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Dermatology Assessment',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: headerColor,
                          ),
                        ),
                        Text(
                          'Photo metric analysis · ${result.recommendations.isNotEmpty ? recCount.toString() : "No"} product recommendation${recCount == 1 ? "" : "s"}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: headerColor.withValues(alpha: 0.70),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: headerColor.withValues(alpha: 0.50),
                  ),
                ],
              ),
            ),
            // Issue chips
            if (result.detectedIssues.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: result.detectedIssues.take(4).map((issue) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: issue.severity.bgColor,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: issue.severity.color.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            issue.icon,
                            size: 11,
                            color: issue.severity.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            issue.name,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: issue.severity.color,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            if (result.detectedIssues.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'No critical metric deviations detected',
                      style: TextStyle(
                        fontSize: 13,
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            // Summary line + top recommendation
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.overallAssessment,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: MyApp.textBrown.withValues(alpha: 0.72),
                    ),
                  ),
                  if (result.recommendations.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    // Top recommendation preview
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: result.recommendations.first.accentColor
                            .withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: result.recommendations.first.accentColor
                              .withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            result.recommendations.first.icon,
                            size: 15,
                            color: result.recommendations.first.accentColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '#1 — ${result.recommendations.first.productName}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: result
                                        .recommendations
                                        .first
                                        .accentColor,
                                  ),
                                ),
                                Text(
                                  result.recommendations.first.indication,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: MyApp.textBrown.withValues(
                                      alpha: 0.55,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: result
                                  .recommendations
                                  .first
                                  .evidenceLevel
                                  .color
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              result.recommendations.first.evidenceLevel.label,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: result
                                    .recommendations
                                    .first
                                    .evidenceLevel
                                    .color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Tap to view full analysis & all recommendations',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: headerColor.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
