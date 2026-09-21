/// ai_intelligence_engine.dart
///
/// Central on-device AI intelligence layer for AestheticSkinTracker.
/// All logic is deterministic rule-based — no API keys required.
/// Produces clinical-grade narrative interpretations from:
///   • Skin scan metrics (redness, texture, wrinkle, pore, darkSpots, elasticity)
///   • Procedure context (type, recovery day, healing stage)
///   • Scar healing data (scar metrics, baseline comparisons)
///   • Product tracking (routine completeness)
///
/// Design principles:
///   • Professional, clinical tone — not salesy or alarming
///   • References actual user data (real numbers, real procedure names)
///   • Tailored by procedure type, recovery stage, and trend direction
///   • Actionable guidance with appropriate clinical caveats

library ai_intelligence_engine;

import 'package:flutter/material.dart';

import '../models/procedure.dart';
import '../models/product_tracker.dart';
import '../models/scan_history.dart';
import 'app_logger.dart';
import 'procedure_intelligence.dart';
import 'procedure_metric_set.dart';
import 'trend_label_resolver.dart';

// ---------------------------------------------------------------------------
// Data Classes
// ---------------------------------------------------------------------------

enum MetricClinicalLevel { optimal, mild, moderate, elevated }

class MetricInsight {
  const MetricInsight({
    required this.label,
    required this.value,
    required this.level,
    required this.clinicalLabel,
    required this.contextNote,
    required this.suggestion,
    required this.color,
    required this.icon,
    this.trendNote,
    this.isPositiveTrend,
    this.isConcerning = false,
  });

  final String label;
  final double value;
  final MetricClinicalLevel level;
  final String clinicalLabel;
  final String contextNote;
  final String suggestion;
  final Color color;
  final IconData icon;
  final String? trendNote;
  final bool? isPositiveTrend;
  final bool isConcerning;
}

class ScanAiReport {
  const ScanAiReport({
    required this.overallNarrative,
    required this.metricInsights,
    required this.topPriority,
    required this.positiveFindings,
    required this.primaryRecommendation,
    required this.scanQualityNote,
    this.procedureProfile,
  });

  final String overallNarrative;
  final List<MetricInsight> metricInsights;
  final String? topPriority;
  final List<String> positiveFindings;
  final String primaryRecommendation;
  final String? scanQualityNote;

  /// The ProcedureProfile used to filter/label this report. Null for general scans.
  final ProcedureProfile? procedureProfile;
}

enum BriefingPriority { high, medium, low }

class BriefingInsight {
  const BriefingInsight({
    required this.icon,
    required this.title,
    required this.body,
    required this.priority,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final BriefingPriority priority;
  final Color color;
}

class AiDailyBriefing {
  const AiDailyBriefing({
    required this.headline,
    required this.subheadline,
    required this.insights,
    required this.todaysFocus,
    required this.hasMeaningfulData,
  });

  final String headline;
  final String subheadline;
  final List<BriefingInsight> insights;
  final String todaysFocus;
  final bool hasMeaningfulData;
}

// ---------------------------------------------------------------------------
// Metric Clinical Thresholds & Interpretation
// ---------------------------------------------------------------------------

const Color _optimalColor = Color(0xFF2E7D32); // dark green
const Color _mildColor = Color(0xFF558B2F); // olive green
const Color _moderateColor = Color(0xFFE65100); // deep orange
const Color _elevatedColor = Color(0xFFB71C1C); // dark red
const Color _elasticityGoodColor = Color(0xFF1565C0); // deep blue
const Color _elasticityFairColor = Color(0xFF6A1B9A); // purple
const Color _elasticityPoorColor = Color(0xFFB71C1C);

MetricInsight _interpretRedness(
  double value, {
  double? baseline,
  String? procedureType,
}) {
  MetricClinicalLevel level;
  String clinicalLabel;
  String contextNote;
  String suggestion;
  Color color;

  // BBL / body contouring override
  final isBodyContouring =
      procedureType != null &&
      (procedureType.toLowerCase().contains('bbl') ||
          procedureType.toLowerCase().contains('liposuction') ||
          procedureType.toLowerCase().contains('lipo') ||
          procedureType.toLowerCase().contains('tummy tuck') ||
          procedureType.toLowerCase().contains('butt lift') ||
          procedureType.toLowerCase().contains('body contour') ||
          procedureType.toLowerCase().contains('arm lift') ||
          procedureType.toLowerCase().contains('thigh lift'));

  if (isBodyContouring) {
    if (value < 3.0) {
      level = MetricClinicalLevel.optimal;
      clinicalLabel = 'Minimal post-op swelling';
      contextNote =
          'Post-op swelling and bruising score of ${value.toStringAsFixed(1)} is in the optimal range for your recovery stage. Clinically, this indicates that the vascular disruption from body contouring surgery has largely resolved and lymphatic drainage is functioning well. Low swelling at this stage is a positive indicator for final contour quality — excess persistent edema can mask the true outcome and impair skin retraction.';
      suggestion =
          'Maintain compression garment compliance and lymphatic drainage massage schedule. Adequate protein intake (1.4–1.6g/kg body weight) continues to support tissue repair and contour recovery.';
      color = _optimalColor;
    } else if (value < 5.0) {
      level = MetricClinicalLevel.mild;
      clinicalLabel = 'Mild residual swelling';
      contextNote =
          'A swelling/bruising score of ${value.toStringAsFixed(1)} reflects mild but measurable post-operative edema. This is expected and normal during active recovery from body contouring. The swelling is caused by surgical disruption of lymphatic channels and increased vascular permeability — both temporary, and both addressable through consistent compression and manual lymphatic drainage (MLD).';
      suggestion =
          'Ensure compression garment is worn as directed (Stage 1: 22+ h/day for 3 weeks, then Stage 2). If you have not already started MLD sessions with a certified therapist (typically weeks 3–4 onward), this is the ideal time. Elevate treated areas when resting to reduce gravitational edema pooling.';
      color = _mildColor;
    } else if (value < 7.0) {
      level = MetricClinicalLevel.moderate;
      clinicalLabel = 'Moderate swelling — active management needed';
      contextNote =
          'Swelling at ${value.toStringAsFixed(1)} indicates sustained post-operative edema that warrants active management. At this level, prolonged swelling can contribute to fibrosis — lymphatic channels that remain congested for extended periods stimulate fibroblast activity, producing the firm, lumpy areas patients describe under the skin. Early, consistent lymphatic drainage is the most impactful intervention to interrupt this pathway.';
      suggestion =
          'Prioritize manual lymphatic drainage (MLD) — 2–3 sessions per week is clinically recommended at this stage. Ensure your compression garment fits correctly (a poorly fitted garment is a common cause of uneven swelling). Discuss this finding with your provider if it persists beyond expected timelines.';
      color = _moderateColor;
    } else {
      level = MetricClinicalLevel.elevated;
      clinicalLabel = 'Significant swelling — clinical review recommended';
      contextNote =
          'A post-op swelling score of ${value.toStringAsFixed(1)} is above what is typical at this stage. Persistent significant edema after body contouring can indicate: insufficient compression garment use, developing fibrosis, lymphatic channel disruption requiring manual intervention, or — rarely — fluid accumulation (seroma) requiring aspiration. Any sudden increase in swelling, asymmetry, warmth, or new pain warrants prompt provider review.';
      suggestion =
          'Contact your surgeon to review this finding, particularly if the swelling is asymmetric, warm, or has increased. Ensure strict compression garment compliance. Pursue MLD sessions immediately if not already in progress — this is a clinical priority at this stage.';
      color = _elevatedColor;
    }
  } else if (value < 3.0) {
    level = MetricClinicalLevel.optimal;
    clinicalLabel = 'Minimal inflammation';
    contextNote =
        'A redness score of ${value.toStringAsFixed(1)} is within the optimal range. Clinically, this indicates that vascular permeability and pro-inflammatory cytokine activity are well-regulated — meaning your skin\'s repair mechanisms are functioning without excessive immune activation. This is the foundation of healthy skin physiology.';
    suggestion =
        'Maintain your current gentle cleansing routine and SPF 50+. No active anti-inflammatory intervention is needed at this stage.';
    color = _optimalColor;
  } else if (value < 5.0) {
    level = MetricClinicalLevel.mild;
    clinicalLabel = 'Mild erythema';
    contextNote =
        'Redness at ${value.toStringAsFixed(1)} reflects mild erythema — a controlled, low-grade inflammatory response. At this level, the skin\'s innate immune system is active but not overwhelmed. If you\'re in a post-procedure phase, this is an expected part of the healing cascade and does not indicate pathology. The key clinical concern is preventing this from escalating via UV exposure or barrier disruption.';
    suggestion =
        'A ceramide-rich moisturizer and daily SPF 50+ are your most impactful tools. Avoid exfoliating acids or retinoids until redness fully settles.';
    color = _mildColor;
  } else if (value < 7.0) {
    level = MetricClinicalLevel.moderate;
    clinicalLabel = 'Moderate inflammation';
    contextNote =
        'A redness reading of ${value.toStringAsFixed(1)} indicates sustained moderate erythema. Clinically, this level of inflammation is associated with elevated pro-inflammatory mediators that can impair collagen synthesis and increase post-inflammatory hyperpigmentation (PIH) risk — especially relevant ${procedureType?.isNotEmpty == true ? 'during $procedureType recovery' : 'post-procedure'}. Early, targeted intervention now reduces the downstream pigmentation burden.';
    suggestion =
        'Introduce azelaic acid (10–20%) or niacinamide 10% to modulate vascular reactivity. Apply SPF 50+ without exception. Hold all retinoids until redness resolves below 5.0.';
    color = _moderateColor;
  } else {
    level = MetricClinicalLevel.elevated;
    clinicalLabel = 'Elevated erythema';
    contextNote =
        'A redness score of ${value.toStringAsFixed(1)} is in the elevated range, indicating significant active inflammation. At this level, the skin barrier is likely compromised — tight junction proteins are disrupted, trans-epidermal water loss is elevated, and the tissue is at meaningful risk of secondary sensitivity reactions. This warrants prompt clinical attention, particularly if redness is spreading, warm to touch, or accompanied by pain.';
    suggestion =
        'Prioritize barrier repair with ceramide-rich emollients and a fragrance-free cleanser. Discontinue all active ingredients. Discuss this finding with your provider if it persists beyond 48–72 hours.';
    color = _elevatedColor;
  }

  String? trendNote;
  if (baseline != null) {
    final delta = value - baseline;
    if (isBodyContouring) {
      if (delta < -0.5) {
        trendNote =
            'Swelling is down ${delta.abs().toStringAsFixed(1)} points from your baseline — a clear sign that edema is resolving and lymphatic drainage is functioning as expected. Continue compression garment compliance to sustain this progress.';
      } else if (delta > 0.5)
        trendNote =
            'Swelling has increased ${delta.toStringAsFixed(1)} points since your baseline. Review compression garment fit and compliance, and ensure MLD sessions are in your schedule — early intervention prevents prolonged edema from converting to fibrosis.';
    } else {
      if (delta < -0.5) {
        trendNote =
            'Redness is down ${delta.abs().toStringAsFixed(1)} points from your baseline — a clear signal that the inflammatory response is calming. This is exactly the trajectory we want to see. Stay consistent.';
      } else if (delta > 0.5)
        trendNote =
            'Redness has risen ${delta.toStringAsFixed(1)} points since your baseline scan. Review any recent product introductions, increased sun exposure, or barrier disruption as likely contributors — early attention here prevents a harder-to-reverse escalation.';
    }
  }

  return MetricInsight(
    label: isBodyContouring ? 'Post-Op Swelling & Bruising' : 'Erythema',
    value: value,
    level: level,
    clinicalLabel: clinicalLabel,
    contextNote: contextNote,
    suggestion: suggestion,
    color: color,
    icon: Icons.water_drop_outlined,
    trendNote: trendNote,
    isPositiveTrend: baseline == null ? null : value < baseline,
    isConcerning: level == MetricClinicalLevel.elevated,
  );
}

MetricInsight _interpretTexture(
  double value, {
  double? baseline,
  String? procedureType,
}) {
  MetricClinicalLevel level;
  String clinicalLabel;
  String contextNote;
  String suggestion;
  Color color;

  // BBL / body contouring override
  final isBodyContouring =
      procedureType != null &&
      (procedureType.toLowerCase().contains('bbl') ||
          procedureType.toLowerCase().contains('liposuction') ||
          procedureType.toLowerCase().contains('lipo') ||
          procedureType.toLowerCase().contains('tummy tuck') ||
          procedureType.toLowerCase().contains('butt lift') ||
          procedureType.toLowerCase().contains('body contour') ||
          procedureType.toLowerCase().contains('arm lift') ||
          procedureType.toLowerCase().contains('thigh lift'));

  if (isBodyContouring) {
    if (value < 3.0) {
      level = MetricClinicalLevel.optimal;
      clinicalLabel = 'Smooth, even contour';
      contextNote =
          'Contour smoothness score of ${value.toStringAsFixed(1)} reflects excellent surface evenness in the treated area. Clinically, this indicates that fibrosis is minimal, swelling is well-controlled, and the skin is retracting uniformly — all positive predictors of high-quality final contour. Smooth, even retraction at this stage is significantly influenced by consistent compression garment use and lymphatic drainage.';
      suggestion =
          'Continue compression garment schedule and lymphatic drainage sessions to maintain this trajectory. High-protein diet supports ongoing tissue integration and healing.';
      color = _optimalColor;
    } else if (value < 5.0) {
      level = MetricClinicalLevel.mild;
      clinicalLabel = 'Mild contour irregularity';
      contextNote =
          'A contour smoothness score of ${value.toStringAsFixed(1)} reflects mild surface irregularity — typical at this stage of body contouring recovery. Minor lumpiness or unevenness is caused by early fibrosis formation and differential swelling resolution across the treated area. This is not a permanent outcome — it is a recoverable finding that responds significantly to manual lymphatic drainage (MLD) and continued compression.';
      suggestion =
          'Increase MLD session frequency if not already at 2–3 per week. Ensure compression garment fits evenly without bunching. Expect continued improvement over the coming weeks as swelling resolves and fibrosis remodels.';
      color = _mildColor;
    } else if (value < 7.0) {
      level = MetricClinicalLevel.moderate;
      clinicalLabel = 'Moderate fibrosis / contour irregularity';
      contextNote =
          'A contour score of ${value.toStringAsFixed(1)} indicates moderate fibrosis or surface irregularity. After liposuction or other contouring surgery, fibroblasts respond to tissue disruption by depositing collagen in a disorganized pattern — creating the firm, lumpy, sometimes tender areas patients notice. This is the most common body contouring recovery concern and is highly responsive to therapeutic intervention. Left untreated, fibrosis can become more resistant to non-surgical approaches over time.';
      suggestion =
          'Manual lymphatic drainage (MLD) is the most evidence-supported intervention for post-liposuction fibrosis. Aim for 3 sessions per week. Ultrasound cavitation (post-6 weeks, provider-approved) can help mobilize established fibrosis. Discuss your progress with your surgeon.';
      color = _moderateColor;
    } else {
      level = MetricClinicalLevel.elevated;
      clinicalLabel = 'Significant fibrosis / surface irregularity';
      contextNote =
          'Contour irregularity at ${value.toStringAsFixed(1)} reflects significant fibrosis or surface disruption. At this level, organized collagen deposition has created structural changes in the subcutaneous tissue that produce visible and palpable irregularity. Early intervention is important: fibrosis that is treated within the first 3 months responds significantly better to MLD and therapeutic approaches than fibrosis that is allowed to mature and harden over months.';
      suggestion =
          'Discuss with your surgeon immediately. Clinical interventions include intensive MLD (daily if possible), provider-supervised ultrasound cavitation, and in some cases, revision procedures. Early action produces substantially better outcomes than delayed treatment.';
      color = _elevatedColor;
    }

    String? trendNote;
    if (baseline != null) {
      final delta = value - baseline;
      if (delta < -0.5) {
        trendNote =
            'Contour smoothness has improved ${delta.abs().toStringAsFixed(1)} points from your baseline — a clear sign that fibrosis is resolving and skin retraction is progressing well. Your MLD and compression compliance are paying off. Keep the schedule.';
      } else if (delta > 0.5)
        trendNote =
            'Surface irregularity has increased ${delta.toStringAsFixed(1)} points since your baseline. This pattern is consistent with developing fibrosis — the most common trajectory when MLD sessions are reduced or compression is inconsistent. Intensifying your MLD schedule now is the highest-impact response.';
    }

    return MetricInsight(
      label: 'Contour Smoothness & Evenness',
      value: value,
      level: level,
      clinicalLabel: clinicalLabel,
      contextNote: contextNote,
      suggestion: suggestion,
      color: color,
      icon: Icons.grain_outlined,
      trendNote: trendNote,
      isPositiveTrend: baseline == null ? null : value < baseline,
      isConcerning: level == MetricClinicalLevel.elevated,
    );
  }

  if (value < 3.0) {
    level = MetricClinicalLevel.optimal;
    clinicalLabel = 'Smooth, refined surface';
    contextNote =
        'Texture at ${value.toStringAsFixed(1)} reflects a well-organized, smooth stratum corneum. Clinically, this indicates that keratinocyte differentiation and desquamation are balanced — the cells at the surface are maturing and shedding in an orderly fashion. A healthy barrier like this also means improved product penetration and reduced sensitivity to active ingredients.';
    suggestion =
        'Continue your current routine. Gentle exfoliation 1–2x weekly maintains this by preventing corneocyte build-up.';
    color = _optimalColor;
  } else if (value < 5.0) {
    level = MetricClinicalLevel.mild;
    clinicalLabel = 'Mildly uneven texture';
    contextNote =
        'A texture score of ${value.toStringAsFixed(1)} reflects mild surface irregularity, typically caused by accelerated or disorganized corneocyte accumulation. Common drivers include dehydration (which impairs natural desquamation enzymes), early post-procedural remodeling, or mild sebaceous congestion. At this stage, the stratum corneum is intact but suboptimal — a responsive window for targeted intervention.';
    suggestion =
        'AHAs (glycolic or lactic acid 5–10%) or enzyme exfoliants 2× weekly can normalize keratinocyte turnover. Consistent hydration is foundational.';
    color = _mildColor;
  } else if (value < 7.0) {
    level = MetricClinicalLevel.moderate;
    clinicalLabel = 'Moderate surface roughness';
    contextNote =
        'Texture at ${value.toStringAsFixed(1)} indicates significant disorganization in stratum corneum architecture. This is clinically meaningful because a disrupted surface barrier allows increased water loss, impairs the skin\'s ability to respond to topical actives, and is often the first visible sign of deeper dermal remodeling deficits${procedureType?.isNotEmpty == true ? ' — common at this stage of $procedureType recovery' : ''}. Retinoids work at the receptor level to re-synchronize keratinocyte turnover and are the most evidence-based intervention here.';
    suggestion =
        'Introduce retinol (0.025–0.05%) at night once inflammation settles. A ceramide moisturizer morning and evening supports barrier integrity during the adjustment period.';
    color = _moderateColor;
  } else {
    level = MetricClinicalLevel.elevated;
    clinicalLabel = 'Significant surface irregularity';
    contextNote =
        'Texture at ${value.toStringAsFixed(1)} indicates substantial stratum corneum disruption. At this level, the barrier\'s protective function is significantly compromised — trans-epidermal water loss is elevated, risk of sensitization is increased, and the skin\'s response to topical treatments becomes unpredictable. Professional resurfacing addresses this at a structural level by triggering controlled, organized re-epithelialization.';
    suggestion =
        'After healing stabilizes, discuss microneedling or fractional laser with your provider. In the interim, a consistent retinoid with barrier-support moisturizer is the most effective home protocol.';
    color = _elevatedColor;
  }

  String? trendNote;
  if (baseline != null) {
    final delta = value - baseline;
    if (delta < -0.5) {
      trendNote =
          'Texture has improved ${delta.abs().toStringAsFixed(1)} points since your baseline — the stratum corneum is organizing more effectively. Consistent exfoliation and hydration are the most likely drivers of this result.';
    } else if (delta > 0.5)
      trendNote =
          'Surface texture has roughened ${delta.toStringAsFixed(1)} points since your baseline reading. This often signals dehydration, barrier disruption, or corneocyte accumulation — review your exfoliation frequency, hydration routine, and any recent product changes.';
  }

  return MetricInsight(
    label: 'Skin Texture Quality',
    value: value,
    level: level,
    clinicalLabel: clinicalLabel,
    contextNote: contextNote,
    suggestion: suggestion,
    color: color,
    icon: Icons.grain_outlined,
    trendNote: trendNote,
    isPositiveTrend: baseline == null ? null : value < baseline,
    isConcerning: level == MetricClinicalLevel.elevated,
  );
}

MetricInsight _interpretWrinkle(double value, {double? baseline}) {
  MetricClinicalLevel level;
  String clinicalLabel;
  String contextNote;
  String suggestion;
  Color color;

  if (value < 3.0) {
    level = MetricClinicalLevel.optimal;
    clinicalLabel = 'Minimal lines present';
    contextNote =
        'A wrinkle score of ${value.toStringAsFixed(1)} indicates minimal dynamic and static line formation. Clinically, this reflects intact dermal collagen and elastin architecture — the scaffold that gives skin its resistance to mechanical deformation. Preserving this is significantly easier than restoring it, making consistent photoprotection and antioxidant defense the highest-value strategy at this stage.';
    suggestion =
        'Prevention is the priority. Daily SPF 50+, vitamin C serum each morning, and consistent moisturization will preserve your dermal architecture long-term.';
    color = _optimalColor;
  } else if (value < 5.0) {
    level = MetricClinicalLevel.mild;
    clinicalLabel = 'Early line formation';
    contextNote =
        'Wrinkle depth at ${value.toStringAsFixed(1)} reflects early dynamic line formation — the creases created by repeated muscle movement beginning to etch into the dermis as collagen density gradually decreases. This is a natural, expected finding and represents the optimal intervention window: retinoids at this stage have clinical evidence demonstrating meaningful collagen stimulation and photoaging reversal, with results that become less dramatic as lines deepen.';
    suggestion =
        'Retinol (0.025–0.1%) nightly is the gold-standard intervention here. Pair with SPF 50+ daily and a peptide moisturizer for synergistic dermal support.';
    color = _mildColor;
  } else if (value < 7.0) {
    level = MetricClinicalLevel.moderate;
    clinicalLabel = 'Moderate line depth';
    contextNote =
        'A wrinkle score of ${value.toStringAsFixed(1)} indicates established line depth where dermal remodeling is needed, not just surface maintenance. At this stage, collagen cross-linking has declined and the reticular dermis shows structural changes that topical actives can partially address — but clinical evidence shows that prescription-strength retinoids, combined approaches, or procedural interventions provide substantially greater improvement than OTC products alone.';
    suggestion =
        'Prescription tretinoin (0.025–0.05%) significantly outperforms OTC retinol at this depth. Discuss neuromodulator options for dynamic lines and resurfacing for static lines with your provider.';
    color = _moderateColor;
  } else {
    level = MetricClinicalLevel.elevated;
    clinicalLabel = 'Deep wrinkle formation';
    contextNote =
        'Wrinkle depth at ${value.toStringAsFixed(1)} reflects significant structural remodeling of the dermis — collagen fibers are substantially depleted, elastin is fragmented, and the dermal-epidermal junction shows characteristic changes of advanced photoaging or chronological aging. At this level, the evidence clearly supports combined approaches: topical retinoids slow further degradation, while energy-based and resurfacing procedures address existing structural changes in ways topicals cannot.';
    suggestion =
        'Discuss combined resurfacing (fractional laser or deep chemical peel) alongside prescription tretinoin with your provider. Dermal filler or biostimulators may be relevant for volumetric loss.';
    color = _elevatedColor;
  }

  String? trendNote;
  if (baseline != null) {
    final delta = value - baseline;
    if (delta < -0.5) {
      trendNote =
          'Line depth has reduced ${delta.abs().toStringAsFixed(1)} points since your baseline — a meaningful sign that your anti-aging protocol is producing genuine dermal remodeling. Retinoid consistency over the next 3–6 months will compound these results considerably.';
    } else if (delta > 0.5)
      trendNote =
          'Lines have deepened ${delta.toStringAsFixed(1)} points since your baseline. Review your retinoid consistency, SPF adherence, and daily hydration — all three directly influence the rate at which the dermis preserves or loses structural integrity.';
  }

  return MetricInsight(
    label: 'Rhytids',
    value: value,
    level: level,
    clinicalLabel: clinicalLabel,
    contextNote: contextNote,
    suggestion: suggestion,
    color: color,
    icon: Icons.timeline_outlined,
    trendNote: trendNote,
    isPositiveTrend: baseline == null ? null : value < baseline,
    isConcerning: level == MetricClinicalLevel.elevated,
  );
}

MetricInsight _interpretPore(double value, {double? baseline}) {
  MetricClinicalLevel level;
  String clinicalLabel;
  String contextNote;
  String suggestion;
  Color color;

  if (value < 3.0) {
    level = MetricClinicalLevel.optimal;
    clinicalLabel = 'Refined pore appearance';
    contextNote =
        'Pore visibility at ${value.toStringAsFixed(1)} indicates minimal visible follicular ostia. Pore size is structurally determined by three factors: sebaceous gland output (which dilates the follicular canal), surrounding collagen density (which provides the walls that keep pores tight), and keratinocyte accumulation within the canal. A score in this range reflects a healthy balance across all three — an outcome that rewards consistent routine adherence.';
    suggestion =
        'Niacinamide 5–10% and consistent gentle cleansing are the most effective maintenance tools. Avoid heavy occlusive products that may promote sebaceous build-up.';
    color = _optimalColor;
  } else if (value < 5.0) {
    level = MetricClinicalLevel.mild;
    clinicalLabel = 'Mildly visible pores';
    contextNote =
        'A pore score of ${value.toStringAsFixed(1)} reflects mild follicular enlargement. This is commonly driven by elevated sebum production distending the follicular opening, and/or the early loss of the collagen scaffolding that holds the pore wall taut. Importantly, pore size is not permanently fixed — targeted interventions that address sebum regulation and collagen support can produce visible refinement within 8–12 weeks.';
    suggestion =
        'Niacinamide (5–10%) reduces sebum secretion and pore visibility. BHA (salicylic acid 0.5–2%) exfoliates within the follicular canal. Use both consistently for best results.';
    color = _mildColor;
  } else if (value < 7.0) {
    level = MetricClinicalLevel.moderate;
    clinicalLabel = 'Moderately enlarged pores';
    contextNote =
        'A pore score of ${value.toStringAsFixed(1)} indicates meaningful follicular enlargement. At this level, the combination of excess sebum distending the canal, reduced perifollicular collagen (often from photoaging or post-inflammatory change), and keratin build-up is creating structurally wider pores. The clinical significance is that enlarged pores are more prone to comedone formation, which perpetuates the cycle of inflammation and further stretching.';
    suggestion =
        'Retinol at night combined with BHA exfoliation and niacinamide forms the evidence-based triad for pore refinement. Consistent, thorough cleansing twice daily removes the sebaceous substrate that drives enlargement.';
    color = _moderateColor;
  } else {
    level = MetricClinicalLevel.elevated;
    clinicalLabel = 'Significantly enlarged pores';
    contextNote =
        'Pore visibility at ${value.toStringAsFixed(1)} reflects substantial follicular enlargement where the structural deficit — loss of perifolicular collagen support — is the dominant driver. At this level, topical-only approaches have limited structural impact on the collagen scaffolding. Professional interventions that directly stimulate new collagen formation around the follicle (microneedling, fractional ablative laser) provide the most meaningful, lasting improvement.';
    suggestion =
        'Discuss professional microneedling or fractional ablative laser with your provider for structural improvement. A consistent home routine with retinol and BHA forms an important adjunct.';
    color = _elevatedColor;
  }

  String? trendNote;
  if (baseline != null) {
    final delta = value - baseline;
    if (delta < -0.5) {
      trendNote =
          'Pore visibility has reduced ${delta.abs().toStringAsFixed(1)} points since your baseline — sebum regulation and perifollicular collagen support are both trending in the right direction. Keep up the consistent routine.';
    } else if (delta > 0.5)
      trendNote =
          'Pore appearance has increased ${delta.toStringAsFixed(1)} points since your baseline. The most common drivers are elevated sebum production and incomplete cleansing — review your niacinamide use and ensure your cleanser is thoroughly clearing sebaceous build-up twice daily.';
  }

  return MetricInsight(
    label: 'Pore Visibility',
    value: value,
    level: level,
    clinicalLabel: clinicalLabel,
    contextNote: contextNote,
    suggestion: suggestion,
    color: color,
    icon: Icons.circle_outlined,
    trendNote: trendNote,
    isPositiveTrend: baseline == null ? null : value < baseline,
    isConcerning: level == MetricClinicalLevel.elevated,
  );
}

MetricInsight _interpretDarkSpots(
  double value, {
  double? baseline,
  String? procedureType,
}) {
  MetricClinicalLevel level;
  String clinicalLabel;
  String contextNote;
  String suggestion;
  Color color;

  // BBL / body contouring override
  final isBodyContouring =
      procedureType != null &&
      (procedureType.toLowerCase().contains('bbl') ||
          procedureType.toLowerCase().contains('liposuction') ||
          procedureType.toLowerCase().contains('lipo') ||
          procedureType.toLowerCase().contains('tummy tuck') ||
          procedureType.toLowerCase().contains('butt lift') ||
          procedureType.toLowerCase().contains('body contour') ||
          procedureType.toLowerCase().contains('arm lift') ||
          procedureType.toLowerCase().contains('thigh lift'));

  if (isBodyContouring) {
    if (value < 3.0) {
      level = MetricClinicalLevel.optimal;
      clinicalLabel = 'Bruising clearing well';
      contextNote =
          'Bruising clearance score of ${value.toStringAsFixed(1)} indicates that post-operative bruising has largely resolved and subcutaneous bleeding has been reabsorbed effectively. Clinically, rapid bruise clearance is a positive indicator for healing velocity — it suggests healthy lymphatic function and good microvascular repair. Low scores at this metric also indicate reduced risk of post-inflammatory hyperpigmentation (PIH) at incision and treated sites.';
      suggestion =
          'Continue arnica supplementation or topical arnica if still in the early recovery phase. SPF 50+ on any healing or recently bruised skin areas is critical — UV exposure on post-bruise tissue triggers melanin upregulation and can cause persistent pigment marks.';
      color = _optimalColor;
    } else if (value < 5.0) {
      level = MetricClinicalLevel.mild;
      clinicalLabel = 'Moderate bruising present';
      contextNote =
          'Bruising at ${value.toStringAsFixed(1)} reflects active resolution of subcutaneous hematoma from surgical trauma. As extravasated red blood cells break down, the characteristic color progression from purple/blue → green → yellow is a normal marker of healthy reabsorption. At this score, bruising is within expected parameters for your recovery stage and should continue resolving progressively.';
      suggestion =
          'Oral arnica montana or bromelain can accelerate bruise resolution by reducing inflammatory mediators. Avoid any pressure or massage directly on bruised areas until they are fully cleared. Protect all bruised areas with SPF 50+ to prevent post-bruise pigmentation.';
      color = _mildColor;
    } else if (value < 7.0) {
      level = MetricClinicalLevel.moderate;
      clinicalLabel = 'Significant bruising — fibrosis risk elevated';
      contextNote =
          'Bruising at ${value.toStringAsFixed(1)} indicates sustained subcutaneous bleeding that may be contributing to fibrosis formation. Prolonged blood breakdown products (hemosiderin) can trigger an inflammatory fibroblast response, producing firm, discolored tissue. The clinical concern at this level is not just cosmetic — organized fibrosis in extensively bruised areas can be more challenging to treat than fibrosis in non-bruised regions.';
      suggestion =
          'Arnica supplementation and topical arnica should be maximized. Ensure MLD sessions are addressing the bruised areas. Discuss the extent of bruising with your surgeon at your next follow-up — particularly if any area shows increasing firmness, worsening color, or is associated with pain.';
      color = _moderateColor;
    } else {
      level = MetricClinicalLevel.elevated;
      clinicalLabel = 'Extensive bruising — clinical review warranted';
      contextNote =
          'A bruising score of ${value.toStringAsFixed(1)} indicates extensive or unusually persistent post-operative bruising. While bruising is universal after body contouring, extensive or worsening bruising beyond expected timelines warrants review. Clinically, this level raises concern for: hematoma formation (requiring surgical drainage), coagulation factors being suboptimal, or tissue disruption greater than anticipated. This finding should be discussed with your surgeon.';
      suggestion =
          'Contact your surgeon to review this finding. Document the distribution, color, and any associated swelling or firmness in your photos. Avoid all aspirin, ibuprofen, or blood-thinning supplements until cleared. This is not a complication you should manage with home care alone.';
      color = _elevatedColor;
    }

    String? trendNote;
    if (baseline != null) {
      final delta = value - baseline;
      if (delta < -0.5) {
        trendNote =
            'Bruising has cleared ${delta.abs().toStringAsFixed(1)} points since your baseline — hematoma reabsorption is progressing as expected. Continue photoprotection on previously bruised areas to prevent post-inflammatory pigmentation.';
      } else if (delta > 0.5)
        trendNote =
            'Bruising has increased ${delta.toStringAsFixed(1)} points since your baseline. New or spreading bruising after the first week warrants prompt provider review — particularly if accompanied by swelling, pain, or skin discoloration in a previously unaffected area.';
    }

    return MetricInsight(
      label: 'Bruising Clearance',
      value: value,
      level: level,
      clinicalLabel: clinicalLabel,
      contextNote: contextNote,
      suggestion: suggestion,
      color: color,
      icon: Icons.brightness_3_outlined,
      trendNote: trendNote,
      isPositiveTrend: baseline == null ? null : value < baseline,
      isConcerning: level == MetricClinicalLevel.elevated,
    );
  }

  if (value < 3.0) {
    level = MetricClinicalLevel.optimal;
    clinicalLabel = 'Minimal hyperpigmentation';
    contextNote =
        'A dark spot score of ${value.toStringAsFixed(1)} reflects well-regulated melanin production across the skin surface. Melanocytes are present in all skin types, but their activity — controlled by UV exposure, inflammatory signals, and hormonal input — determines whether pigmentation becomes visible. A score this low indicates the melanogenesis pathway is not being over-stimulated. This is an outcome worth protecting, as UV exposure can rapidly shift this picture.';
    suggestion =
        'Daily SPF 50+ is the most impactful tool for maintaining this. Vitamin C (10–20%) each morning provides additional antioxidant defense against UV-triggered melanogenesis.';
    color = _optimalColor;
  } else if (value < 5.0) {
    level = MetricClinicalLevel.mild;
    clinicalLabel = 'Mild dyschromia';
    contextNote =
        'A dark spot reading of ${value.toStringAsFixed(1)} reflects discrete areas where melanocyte activity has been upregulated — most commonly by past UV exposure, post-inflammatory signaling (from acne, procedure, or injury), or hormonal changes. Clinically, these spots are typically in the superficial dermis or epidermis and respond well to targeted depigmenting agents. The most important principle: unprotected UV exposure re-stimulates the melanogenesis pathway and rapidly undoes months of treatment progress.';
    suggestion =
        'Niacinamide (5–10%) inhibits melanosome transfer; vitamin C (15–20%) inhibits tyrosinase. Both used consistently alongside SPF 50+ form a proven brightening protocol.';
    color = _mildColor;
  } else if (value < 7.0) {
    level = MetricClinicalLevel.moderate;
    clinicalLabel = 'Moderate pigmentation irregularity';
    contextNote =
        'A dark spot score of ${value.toStringAsFixed(1)} indicates significant melanocyte dysregulation creating visible tone irregularity${procedureType?.isNotEmpty == true ? ', a recognized risk following $procedureType' : ''}. At this level, pigmentation is typically both epidermal and superficial dermal in distribution, requiring interventions that address multiple points in the melanogenesis pathway simultaneously. UV exposure during treatment is the single most common reason for treatment failure — it re-activates the very pathway being suppressed.';
    suggestion =
        'Azelaic acid (10–20%) and alpha-arbutin target tyrosinase activity at the cellular level. Low-dose tretinoin accelerates turnover of pigmented keratinocytes. SPF 50+ daily is non-negotiable.';
    color = _moderateColor;
  } else {
    level = MetricClinicalLevel.elevated;
    clinicalLabel = 'Significant hyperpigmentation';
    contextNote =
        'A dark spot reading of ${value.toStringAsFixed(1)} represents substantial melanin irregularity where the melanogenesis pathway has been persistently over-stimulated. At this level, pigmentation may extend into the mid-dermis, which responds more slowly to topical-only approaches. A systematic, multi-modal treatment strategy — addressing melanin production, accelerating cell turnover, and providing strict photoprotection simultaneously — delivers the most meaningful clinical outcomes.';
    suggestion =
        'Discuss prescription hydroquinone 4% with tretinoin, or a supervised Kligman-type regimen, with your provider. IPL and chemical peels provide adjunctive clearance of established dermal pigment. SPF 50+ every day without exception.';
    color = _elevatedColor;
  }

  String? trendNote;
  if (baseline != null) {
    final delta = value - baseline;
    if (delta < -0.5) {
      trendNote =
          'Pigmentation has faded ${delta.abs().toStringAsFixed(1)} points since your baseline — your depigmentation protocol is working. Protecting this progress with daily SPF is critical: UV exposure can rapidly re-activate the melanogenesis pathway and undo months of improvement.';
    } else if (delta > 0.5)
      trendNote =
          'Dark spots have deepened ${delta.toStringAsFixed(1)} points since your baseline. The most frequent culprit is UV exposure re-stimulating melanocyte activity. Review your SPF application consistency, reapplication frequency, and whether your protection factor is adequate for your daily exposure level.';
  }

  return MetricInsight(
    label: 'Hyperpigmentation',
    value: value,
    level: level,
    clinicalLabel: clinicalLabel,
    contextNote: contextNote,
    suggestion: suggestion,
    color: color,
    icon: Icons.brightness_3_outlined,
    trendNote: trendNote,
    isPositiveTrend: baseline == null ? null : value < baseline,
    isConcerning: level == MetricClinicalLevel.elevated,
  );
}

MetricInsight _interpretElasticity(
  double value, {
  double? baseline,
  String? procedureType,
}) {
  MetricClinicalLevel level;
  String clinicalLabel;
  String contextNote;
  String suggestion;
  Color color;

  // BBL / body contouring override
  final isBodyContouring =
      procedureType != null &&
      (procedureType.toLowerCase().contains('bbl') ||
          procedureType.toLowerCase().contains('liposuction') ||
          procedureType.toLowerCase().contains('lipo') ||
          procedureType.toLowerCase().contains('tummy tuck') ||
          procedureType.toLowerCase().contains('butt lift') ||
          procedureType.toLowerCase().contains('body contour') ||
          procedureType.toLowerCase().contains('arm lift') ||
          procedureType.toLowerCase().contains('thigh lift'));

  if (isBodyContouring) {
    // For body contouring, elasticity tracks skin retraction quality.
    // Higher elasticity = the skin is retracting well around the new contour.
    if (value > 7.0) {
      level = MetricClinicalLevel.optimal;
      clinicalLabel = 'Excellent skin retraction & volume retention';
      contextNote =
          'Skin retraction score of ${value.toStringAsFixed(1)} indicates that the skin is adapting well to the new contour. Clinically, high elasticity post-body-contouring reflects well-preserved dermal collagen and elastin networks — critical for successful skin retraction after liposuction. Good retraction is strongly associated with better final contour quality.';
      suggestion =
          'Maintain compression garment compliance to support uniform retraction. High-protein intake and adequate hydration continue to support tissue repair. Body SPF 50+ on treated areas prevents UV-induced degradation of newly forming collagen.';
      color = _elasticityGoodColor;
    } else if (value > 5.0) {
      level = MetricClinicalLevel.mild;
      clinicalLabel = 'Good retraction — progressing well';
      contextNote =
          'A retraction score of ${value.toStringAsFixed(1)} indicates good skin adaptation with some early changes expected during recovery. At this stage of body contouring recovery, the dermal matrix is actively remodeling in response to the new subcutaneous architecture. Retraction is a gradual process — the collagen and elastin networks require months to fully reorganize around the new contour, and this score reflects healthy early progress.';
      suggestion =
          'Continue compression garment use as scheduled. Manual lymphatic drainage helps promote even retraction by reducing differential swelling. Collagen-support nutrients (vitamin C, zinc) and adequate protein intake support dermal remodeling.';
      color = _elasticityGoodColor;
    } else if (value > 3.0) {
      level = MetricClinicalLevel.moderate;
      clinicalLabel = 'Moderate laxity — retraction in progress';
      contextNote =
          'Skin retraction at ${value.toStringAsFixed(1)} indicates moderate laxity in the treated area. This is common during body contouring recovery, particularly in patients with pre-existing skin laxity, larger volume liposuction, or in areas with naturally thinner dermis. Skin retraction is driven by fibroblast activity stimulated by the dermal disruption from surgery — compression garment use is the most important modifiable factor in supporting this process.';
      suggestion =
          'Ensure consistent compression garment use, as this directly influences retraction quality. Discuss with your surgeon whether any adjunctive treatments (radiofrequency, ultrasound tightening) would be appropriate after the 3-month mark. Maintain high-protein nutrition to support collagen remodeling.';
      color = _elasticityFairColor;
    } else {
      level = MetricClinicalLevel.elevated;
      clinicalLabel = 'Significant laxity — retraction concerns';
      contextNote =
          'A skin retraction score of ${value.toStringAsFixed(1)} indicates significant laxity in the post-operative area. While some laxity is expected during recovery, this level may indicate that skin retraction is not progressing optimally. Contributing factors include significant pre-operative skin laxity, large-volume liposuction, age-related collagen depletion, or insufficient compression garment use. Discussing this trend with your surgeon is important — there are both non-surgical and surgical options to address retraction concerns.';
      suggestion =
          'Consult your surgeon about this finding. Non-surgical options such as radiofrequency (Morpheus8, BodyTite) or HIFU can provide meaningful additional retraction when performed after 3 months. Ensure compression garment compliance is maximized in the interim. Body SPF 50+ on all treated areas is essential.';
      color = _elasticityPoorColor;
    }

    String? trendNote;
    if (baseline != null) {
      final delta = value - baseline;
      if (delta > 0.5) {
        trendNote =
            'Skin retraction has improved ${delta.toStringAsFixed(1)} points since your baseline — the dermal matrix is actively remodeling and adapting to your new contour. This trajectory is associated with better final contour definition. Keep up your compression schedule.';
      } else if (delta < -0.5)
        trendNote =
            'Retraction score has declined ${delta.abs().toStringAsFixed(1)} points since your baseline. In the first weeks of recovery, some fluctuation is normal. If this is a persistent trend beyond 6 weeks, discuss with your surgeon — early intervention with compression optimization or adjunctive tightening produces the best outcomes.';
    }

    return MetricInsight(
      label: 'Skin Retraction & Fat Retention',
      value: value,
      level: level,
      clinicalLabel: clinicalLabel,
      contextNote: contextNote,
      suggestion: suggestion,
      color: color,
      icon: Icons.fitness_center_outlined,
      trendNote: trendNote,
      isPositiveTrend: baseline == null ? null : value > baseline,
      isConcerning: level == MetricClinicalLevel.elevated,
    );
  }

  // Elasticity is inverted: higher is better
  if (value > 7.0) {
    level = MetricClinicalLevel.optimal;
    clinicalLabel = 'Excellent skin firmness';
    contextNote =
        'An elasticity score of ${value.toStringAsFixed(1)} reflects a well-maintained dermal matrix. Clinically, this indicates healthy collagen I/III ratios and intact elastin networks — the structural proteins responsible for skin\'s ability to resist deformation and recoil after movement. Glycosaminoglycans (particularly hyaluronic acid) in the dermis maintain the hydration that keeps these fibers resilient. Preserving this architecture is substantially easier than rebuilding it once lost.';
    suggestion =
        'Vitamin C (10–20%) supports ongoing collagen synthesis by acting as a co-factor for hydroxylation. Peptide serums and adequate hydration preserve glycosaminoglycan content. Consistent SPF prevents UV-induced elastin degradation.';
    color = _elasticityGoodColor;
  } else if (value > 5.0) {
    level = MetricClinicalLevel.mild;
    clinicalLabel = 'Good skin tone';
    contextNote =
        'An elasticity score of ${value.toStringAsFixed(1)} indicates good dermal integrity with some early reduction in collagen and elastin density. This is the most actionable stage for preventive intervention — retinoids have the strongest clinical evidence for directly stimulating fibroblast activity and new collagen I synthesis, and their impact is most pronounced before structural deficits become significant. Think of this as your highest-return investment window.';
    suggestion =
        'Retinol (0.025–0.1%) is the most evidence-based topical for stimulating collagen I and III synthesis via fibroblast activation. Vitamin C and collagen-stimulating peptides provide meaningful synergistic support.';
    color = _elasticityGoodColor;
  } else if (value > 3.0) {
    level = MetricClinicalLevel.moderate;
    clinicalLabel = 'Moderate laxity';
    contextNote =
        'An elasticity score of ${value.toStringAsFixed(1)} indicates moderate dermal laxity, reflecting a meaningful reduction in the structural integrity of the dermal matrix. At this level, collagen fiber density has declined and cross-linking has been disrupted — commonly from cumulative UV exposure, natural aging, or post-procedural remodeling. The significance is that the skin\'s ability to snap back after mechanical stress is reduced, which also affects how it responds to treatment. Topical actives slow progression; energy-based treatments address existing structural deficits.';
    suggestion =
        'Prescription retinoid forms the home-care cornerstone. RF microneedling or HIFU provides direct collagen stimulation at a structural level. Discuss with your provider to determine appropriate timing and modality.';
    color = _elasticityFairColor;
  } else {
    level = MetricClinicalLevel.elevated;
    clinicalLabel = 'Significant skin laxity';
    contextNote =
        'An elasticity score of ${value.toStringAsFixed(1)} reflects significant loss of dermal firmness. At this level, both the collagen scaffold and the elastin network show substantial structural compromise. Glycosaminoglycan content — which normally maintains dermal hydration and fiber spacing — is also typically depleted. This degree of laxity is associated with visible sagging, deepened folds, and volume loss that topical approaches cannot meaningfully reverse; structural interventions are clinically indicated.';
    suggestion =
        'Discuss energy-based tightening (RF, HIFU), thread lift, or surgical consultation with your provider depending on degree and anatomy. A retinoid and peptide home regimen remains an important adjunct to slow ongoing degradation.';
    color = _elasticityPoorColor;
  }

  String? trendNote;
  if (baseline != null) {
    final delta = value - baseline;
    if (delta > 0.5) {
      trendNote =
          'Skin firmness has improved ${delta.toStringAsFixed(1)} points since your baseline — new collagen synthesis is measurably underway. This kind of structural change takes time to build, and your tracking data is capturing it in real time.';
    } else if (delta < -0.5)
      trendNote =
          'Firmness has declined ${delta.abs().toStringAsFixed(1)} points since your baseline. If you are post-procedure, this may reflect normal early remodeling — temporary loss before structural improvement. Otherwise, review your retinoid consistency and collagen-support routine, both of which have the strongest clinical evidence for addressing this.';
  }

  // For elasticity, elevated (low value) is concerning
  return MetricInsight(
    label: 'Skin Laxity',
    value: value,
    level: level,
    clinicalLabel: clinicalLabel,
    contextNote: contextNote,
    suggestion: suggestion,
    color: color,
    icon: Icons.fitness_center_outlined,
    trendNote: trendNote,
    isPositiveTrend: baseline == null ? null : value > baseline,
    isConcerning: level == MetricClinicalLevel.elevated,
  );
}

// ---------------------------------------------------------------------------
// Main Scan Interpretation Engine
// ---------------------------------------------------------------------------

class AiIntelligenceEngine {
  const AiIntelligenceEngine._();

  /// Generates a full AI-interpreted report for a skin scan.
  /// [metrics] is the current scan. [baseline] is the earliest reference scan.
  /// [procedureType] and [daysSinceProcedure] add clinical context.
  ///
  /// [trendStatus] / [trendLockReason] are the backend's own per-metric
  /// trend_status/trend_lock_reason maps (canonical metric key -> value),
  /// e.g. from the latest scan's rawPayload. When supplied, they are the
  /// ONLY source used to decide whether a metric's trend note says
  /// "improvement"/"worsening" — never a locally recomputed threshold on
  /// the raw value delta. A metric with no entry in these maps gets no
  /// trend note at all, even if a numeric baseline is available.
  static ScanAiReport interpretScanMetrics(
    SkinMetrics metrics, {
    SkinMetrics? baseline,
    String? procedureType,
    String? customDescription,
    String? focusArea,
    int? daysSinceProcedure,
    Map<String, double>? rawMetrics,
    Map<String, double>? baselineRawMetrics,
    Map<String, String>? trendStatus,
    Map<String, String>? trendLockReason,
  }) {
    final resolvedProcedureType = (() {
      final normalized = (procedureType ?? '').trim();
      if (normalized.isEmpty || normalized.toLowerCase() == 'unknown') {
        return 'General Skincare';
      }
      return normalized;
    })();
    AppLogger.verbose(
      '[AiIntelligenceEngine.interpretScanMetrics] resolvedProcedureType=$resolvedProcedureType',
    );

    // ── Procedure-aware clinical metric definitions ──
    // Returns 5–7 curated metrics per procedure category with clinical labels.
    final metricProcedureType = procedureMetricContextType(
      procedureType: procedureType,
      customDescription: customDescription,
      focusArea: focusArea,
    );
    final defs = clinicalMetricsForProcedure(metricProcedureType);
    final orderedInsights = defs
        .map(
          (def) => _buildInsightFromDef(
            def,
            metrics: metrics,
            baseline: baseline,
            daysSinceProcedure: daysSinceProcedure,
            rawMetrics: rawMetrics,
            baselineRawMetrics: baselineRawMetrics,
            trendStatus: trendStatus,
            trendLockReason: trendLockReason,
          ),
        )
        .where((insight) => insight != null)
        .cast<MetricInsight>()
        .toList();

    final profile = ProcedureIntelligence.forType(metricProcedureType);

    // Find most concerning metric
    final concerning = orderedInsights.where((i) => i.isConcerning).toList();
    final positiveList = orderedInsights
        .where((i) => i.level == MetricClinicalLevel.optimal)
        .map((i) => '${i.label}: ${i.clinicalLabel}')
        .toList();

    // Build overall narrative
    final String overallNarrative = _buildOverallNarrative(
      insights: orderedInsights,
      procedureType: procedureType,
      customDescription: customDescription,
      focusArea: focusArea,
      daysSinceProcedure: daysSinceProcedure,
      baseline: baseline,
    );

    // Top priority
    String? topPriority;
    if (concerning.isNotEmpty) {
      final worst = concerning.reduce((a, b) => a.value > b.value ? a : b);
      topPriority = '${worst.label}: ${worst.contextNote}';
    }

    // Primary recommendation
    final primaryRec = _primaryRecommendation(
      insights: orderedInsights,
      procedureType: procedureType,
      customDescription: customDescription,
      focusArea: focusArea,
      daysSinceProcedure: daysSinceProcedure,
    );

    return ScanAiReport(
      overallNarrative: overallNarrative,
      metricInsights: orderedInsights,
      topPriority: topPriority,
      positiveFindings: positiveList,
      primaryRecommendation: primaryRec,
      scanQualityNote: null,
      procedureProfile: profile,
    );
  }

  /// Builds a [MetricInsight] from a clinical metric definition, computing
  /// the clinical level, color, icon, narrative and trend note generically
  /// so any procedure-specific label/source pairing works uniformly.
  ///
  /// For body-composition metrics, the raw `ScanHistoryEntry.metrics` map is
  /// preferred over [SkinMetrics] via [def.rawSourceKeys] / [def.extractFromRaw].
  /// Returns null when a raw-sourced metric has no data in either map (so the
  /// caller can drop it from the report rather than showing a placeholder).
  static MetricInsight? _buildInsightFromDef(
    ClinicalMetricDef def, {
    required SkinMetrics metrics,
    SkinMetrics? baseline,
    int? daysSinceProcedure,
    Map<String, double>? rawMetrics,
    Map<String, double>? baselineRawMetrics,
    Map<String, String>? trendStatus,
    Map<String, String>? trendLockReason,
  }) {
    final bool isRawSourced =
        def.rawSourceKeys != null || def.extractFromRaw != null;
    final double? resolvedValue = def.valueFromRaw(rawMetrics, metrics);
    // If a body-sourced metric has no raw value available, skip it entirely
    // rather than emitting a placeholder 5.0 — this keeps the body-comp
    // report clean when only a subset of body fields were logged.
    if (isRawSourced && rawMetrics != null) {
      final hasRawValue =
          (def.extractFromRaw != null &&
              def.extractFromRaw!(rawMetrics) != null) ||
          (def.rawSourceKeys != null &&
              def.rawSourceKeys!.any((k) => rawMetrics.containsKey(k)));
      if (!hasRawValue) return null;
    }
    final double value = resolvedValue ?? def.valueFrom(metrics);
    // Use normalized score (0–10) for level classification when the def
    // supplies one (body metrics with absolute units like lbs / inches).
    final double levelValue = def.normalizeForLevel != null
        ? def.normalizeForLevel!(value)
        : value;
    final level = _levelFor(levelValue, lowerIsBetter: def.lowerIsBetter);

    Color color;
    IconData icon;
    String clinicalLabel;
    switch (level) {
      case MetricClinicalLevel.optimal:
        color = Colors.green.shade600;
        icon = Icons.check_circle_outline;
        clinicalLabel = def.lowerIsBetter
            ? 'Optimal — within healthy clinical range'
            : 'Excellent — strong performance';
        break;
      case MetricClinicalLevel.mild:
        color = Colors.lightGreen.shade700;
        icon = Icons.info_outline;
        clinicalLabel = def.lowerIsBetter
            ? 'Mild — minor elevation, easily managed'
            : 'Good — slightly below ideal, trending well';
        break;
      case MetricClinicalLevel.moderate:
        color = Colors.orange.shade700;
        icon = Icons.warning_amber_outlined;
        clinicalLabel = def.lowerIsBetter
            ? 'Moderate — targeted intervention recommended'
            : 'Moderate — additional support recommended';
        break;
      case MetricClinicalLevel.elevated:
        color = Colors.red.shade700;
        icon = Icons.error_outline;
        clinicalLabel = def.lowerIsBetter
            ? 'Elevated — meaningful clinical concern'
            : 'Concerning — well below expected range';
        break;
    }

    // Trend wording is decided EXCLUSIVELY by the backend's trend_status for
    // this metric (via resolveTrendLabel) — never by locally comparing value
    // vs baselineValue. The point-delta below is only ever used as a
    // descriptive magnitude string once the backend has already authorized
    // a direction; it is never used to pick "improvement" vs "worsening"
    // itself.
    String? trendNote;
    bool? isPositiveTrend;
    final double? baselineValue = def.valueFromRaw(
      baselineRawMetrics,
      baseline,
    );
    final canonicalKey = shortMetricKeyToCanonical[def.sourceKey];
    final String? backendTrendStatus =
        canonicalKey == null ? null : trendStatus?[canonicalKey];
    final String? backendTrendLockReason =
        canonicalKey == null ? null : trendLockReason?[canonicalKey];
    final resolvedTrend = resolveTrendLabel(
      trendStatus: backendTrendStatus,
      trendLockReason: backendTrendLockReason,
    );
    if (resolvedTrend != null &&
        baselineValue != null &&
        (baseline != null || baselineRawMetrics != null)) {
      final delta = value - baselineValue;
      final magnitude = def.valueFormatter != null
          ? def.valueFormatter!(delta.abs())
          : delta.abs().toStringAsFixed(1);
      if (resolvedTrend.isImproved) {
        isPositiveTrend = true;
        trendNote = 'Trend: ↓ $magnitude vs baseline — improvement.';
      } else if (resolvedTrend.isWorsened) {
        isPositiveTrend = false;
        trendNote = 'Trend: ↑ $magnitude vs baseline — worsening.';
      } else if (resolvedTrend.isStable) {
        isPositiveTrend = null;
        trendNote = resolvedTrend.lockDetail ?? 'Trend: stable vs baseline.';
      }
      // insufficientSignal: leave trendNote null, matching "no usable trend".
    }

    // Procedure phase context appended to clinical narrative
    String phaseSuffix = '';
    if (daysSinceProcedure != null) {
      if (daysSinceProcedure <= 7) {
        phaseSuffix = ' (acute healing phase, day $daysSinceProcedure).';
      } else if (daysSinceProcedure <= 30) {
        phaseSuffix = ' (early remodeling, day $daysSinceProcedure).';
      } else if (daysSinceProcedure <= 90) {
        phaseSuffix = ' (active remodeling, day $daysSinceProcedure).';
      } else {
        phaseSuffix = ' (long-term maturation, day $daysSinceProcedure).';
      }
    }

    final isConcerning =
        level == MetricClinicalLevel.elevated ||
        level == MetricClinicalLevel.moderate;
    final suggestion = isConcerning
        ? def.suggestionWorsening
        : def.suggestionImproving;

    return MetricInsight(
      label: def.label,
      value: value,
      level: level,
      clinicalLabel: clinicalLabel,
      contextNote: '${def.clinicalContext}$phaseSuffix',
      suggestion: suggestion,
      color: color,
      icon: icon,
      trendNote: trendNote,
      isPositiveTrend: isPositiveTrend,
      isConcerning: isConcerning,
    );
  }

  /// 0–10 metric value → clinical level, respecting directionality.
  static MetricClinicalLevel _levelFor(
    double value, {
    required bool lowerIsBetter,
  }) {
    if (lowerIsBetter) {
      if (value <= 3.5) return MetricClinicalLevel.optimal;
      if (value <= 5.0) return MetricClinicalLevel.mild;
      if (value <= 6.5) return MetricClinicalLevel.moderate;
      return MetricClinicalLevel.elevated;
    } else {
      if (value >= 6.5) return MetricClinicalLevel.optimal;
      if (value >= 5.0) return MetricClinicalLevel.mild;
      if (value >= 3.5) return MetricClinicalLevel.moderate;
      return MetricClinicalLevel.elevated;
    }
  }

  /// Maps a MetricInsight label back to its storage key for label-override lookup.
  static String _insightKeyFromLabel(String label) {
    switch (label.toLowerCase()) {
      case 'redness':
        return 'redness';
      case 'texture':
        return 'texture';
      case 'wrinkles':
        return 'wrinkle';
      case 'pores':
        return 'pore';
      case 'dark spots':
        return 'darkSpots';
      case 'elasticity':
        return 'elasticity';
      default:
        return label.toLowerCase();
    }
  }

  static String _buildOverallNarrative({
    required List<MetricInsight> insights,
    String? procedureType,
    String? customDescription,
    String? focusArea,
    int? daysSinceProcedure,
    SkinMetrics? baseline,
  }) {
    final elevatedList = insights
        .where((i) => i.level == MetricClinicalLevel.elevated)
        .toList();
    final moderateList = insights
        .where((i) => i.level == MetricClinicalLevel.moderate)
        .toList();
    final optimalList = insights
        .where((i) => i.level == MetricClinicalLevel.optimal)
        .toList();

    final procContext = procedureType?.isNotEmpty == true
        ? procedureType!
        : null;
    final contextLabel = procedureContextLabel(
      procedureType: procedureType,
      customDescription: customDescription,
      focusArea: focusArea,
    );
    final isBodyContouring =
        procContext != null &&
        usesBodyContouringContext(
          procedureType: procedureType,
          customDescription: customDescription,
          focusArea: focusArea,
        );

    // Build a precise, procedure-aware intro
    String intro;
    if (procContext != null && daysSinceProcedure != null) {
      final phase = daysSinceProcedure <= 7
          ? 'acute healing phase'
          : daysSinceProcedure <= 30
          ? 'early remodeling phase'
          : 'active remodeling phase';
      intro = 'At day $daysSinceProcedure of $contextLabel recovery ($phase), ';
    } else if (procContext != null) {
      intro = 'In the context of $contextLabel recovery, ';
    } else {
      intro = 'Your scan today presents a picture where ';
    }

    // Baseline trajectory sentence
    final baselinePhrase = baseline != null
        ? (elevatedList.isEmpty && moderateList.length <= 1
              ? ' Compared to your baseline, the overall trajectory is encouraging — your metrics are heading in the right direction.'
              : ' Compared to your baseline, the picture is mixed — but each concern has a clear driver and a defined path to improvement.')
        : '';

    if (elevatedList.isEmpty && moderateList.isEmpty) {
      final optNames = optimalList
          .take(2)
          .map(
            (i) => '${i.label.toLowerCase()} (${i.value.toStringAsFixed(1)})',
          )
          .join(' and ');
      if (isBodyContouring) {
        return '${intro}the body-contouring recovery metrics are in the optimal-to-mild range${optNames.isNotEmpty ? ', with particularly strong results for $optNames' : ''}.$baselinePhrase This is an encouraging recovery picture: swelling control, contour settling, firmness, bruising, pigment, and overall healing are behaving as expected for this stage. Keep compression, lymphatic drainage guidance, protein intake, hydration, gentle walking, and positioning rules consistent while scan trends continue to mature.';
      }
      return '${intro}all six tracked metrics are in the optimal-to-mild range${optNames.isNotEmpty ? ', with particularly strong results for $optNames' : ''}.$baselinePhrase This is a genuinely positive picture — your skin\'s barrier integrity, inflammatory tone, and structural markers are all behaving as we\'d want to see. The work you\'re putting into consistent tracking and routine adherence is reflected in this data. Stay consistent, and use regular scans to catch any early shifts before they become trends.';
    }

    if (elevatedList.length >= 3) {
      final names = elevatedList
          .map(
            (i) => '${i.label.toLowerCase()} (${i.value.toStringAsFixed(1)})',
          )
          .join(', ');
      final driver = isBodyContouring
          ? 'body-contouring recovery stress'
          : 'physiological stress';
      final reviewNote = isBodyContouring
          ? ' Review compression fit, MLD cadence, positioning, hydration/protein intake, and activity level, and share persistent or worsening findings with your surgical team.'
          : ' Review each metric below for specific guidance, and consider discussing this scan with your provider — particularly if these findings persist beyond expected recovery timelines.';
      return '${intro}several metrics — $names — are in the elevated range, signaling meaningful $driver${procContext != null ? ' at this stage of $procContext recovery' : ''}.$baselinePhrase I want to be direct with you: this picture warrants a structured, targeted response. Each of these metrics has a clear clinical driver, and addressing them systematically will produce real improvement.$reviewNote';
    }

    if (elevatedList.isNotEmpty) {
      final elevNames = elevatedList
          .map((i) => '${i.label} (${i.value.toStringAsFixed(1)})')
          .join(' and ');
      final optPhrase = optimalList.isNotEmpty
          ? ', while ${optimalList.length == 1 ? '${optimalList.first.label} is performing optimally' : '${optimalList.length} metrics remain in the optimal range'}'
          : '';
      return '$intro$elevNames ${elevatedList.length == 1 ? 'is' : 'are'} the primary clinical concern$optPhrase.$baselinePhrase This is a focused picture — the rest of your metrics are holding steady, which gives us a clear priority. Targeted management of ${elevatedList.length == 1 ? 'this metric' : 'these metrics'} is the most impactful thing you can do right now. See the detailed assessment and recommendation below.';
    }

    // Only moderate findings
    final modNames = moderateList
        .map((i) => '${i.label} (${i.value.toStringAsFixed(1)})')
        .join(' and ');
    final optPhrase = optimalList.isNotEmpty
        ? ' ${optimalList.length == 1 ? '${optimalList.first.label} is' : '${optimalList.length} metrics are'} performing optimally, which is encouraging.'
        : '';
    return '$intro$modNames ${moderateList.length == 1 ? 'shows' : 'show'} moderate readings that respond well to proactive, targeted care.$optPhrase$baselinePhrase The good news is that moderate-range metrics are highly responsive to the right interventions — this is the optimal time to act before these readings deepen. See individual assessments below for specific guidance.';
  }

  static String _primaryRecommendation({
    required List<MetricInsight> insights,
    String? procedureType,
    String? customDescription,
    String? focusArea,
    int? daysSinceProcedure,
  }) {
    final proc = procedureType?.isNotEmpty == true ? procedureType! : null;
    final contextLabel = procedureContextLabel(
      procedureType: procedureType,
      customDescription: customDescription,
      focusArea: focusArea,
    );
    final bodySubtype = ProcedureIntelligence.bodyContouringSubtype(proc);
    final isBodyContouring =
        proc != null &&
        usesBodyContouringContext(
          procedureType: procedureType,
          customDescription: customDescription,
          focusArea: focusArea,
        );
    // Safe lookups — metrics may be filtered for procedure type
    MetricInsight? find(String label) => insights
        .where((i) => i.label.toLowerCase().contains(label.toLowerCase()))
        .firstOrNull;

    final redness =
        find('Redness') ??
        find('Swelling') ??
        find('Erythema') ??
        find('Inflammation');
    final texture =
        find('Texture') ??
        find('Surface') ??
        find('Resurfacing') ??
        find('Scar');
    final darkSpots =
        find('Dark Spot') ??
        find('Pigment') ??
        find('Scabbing') ??
        find('Bruising');
    final elasticity =
        find('Elasticity') ??
        find('Firmness') ??
        find('Tension') ??
        find('Tightening') ??
        find('Retraction');
    final wrinkle = find('Wrinkle') ?? find('Lines');

    // Recovery-aware: first two weeks take absolute priority
    if (daysSinceProcedure != null && daysSinceProcedure <= 14) {
      // BBL gets specific first-14-day guidance
      final isEarlyBodyContouring =
          proc != null &&
          (proc.toLowerCase().contains('bbl') ||
              proc.toLowerCase().contains('liposuction') ||
              proc.toLowerCase().contains('lipo') ||
              proc.toLowerCase().contains('tummy tuck') ||
              proc.toLowerCase().contains('butt lift') ||
              proc.toLowerCase().contains('body contour') ||
              proc.toLowerCase().contains('arm lift') ||
              proc.toLowerCase().contains('thigh lift'));
      if (isEarlyBodyContouring) {
        final isBBL = bodySubtype == ProcedureBodyContouringSubtype.bbl;
        final isLipo =
            bodySubtype == ProcedureBodyContouringSubtype.liposuction;
        final subtypePositioning = isBBL
            ? ' BBL: NO sitting directly on your buttocks under any circumstances — use your foam pillow under the thighs only. Every violation risks permanent fat loss.'
            : isLipo
            ? ' Focus on compression, swelling control, and gentle walking; do not use BBL-only positioning language for liposuction recovery.'
            : '';
        return 'In the first two weeks of your body contouring recovery, three things determine long-term outcome: (1) Compression garment worn 22+ hours per day — do not remove it unless showering; (2) Adequate protein intake (1.4–1.6g/kg) daily to fuel tissue repair; (3) Gentle walking each day to promote lymphatic drainage and prevent DVT.$subtypePositioning Avoid strenuous exercise, sun exposure on treated areas, and all non-prescribed supplements.';
      }
      final procStr = proc != null ? contextLabel : 'the recent';
      return 'Within the first two weeks following $procStr procedure, barrier protection is the clinical priority. Use a fragrance-free, ceramide-rich cleanser and moisturizer twice daily, and apply SPF 50+ every morning without exception. Hold all retinoids, exfoliating acids, and vitamin C actives until inflammation fully resolves and your provider has cleared reintroduction.';
    }

    if (isBodyContouring) {
      MetricInsight? bodyFind(String label) => insights
          .where((i) => i.label.toLowerCase().contains(label.toLowerCase()))
          .firstOrNull;
      final swelling = bodyFind('Swelling') ?? bodyFind('Bruising');
      final firmness =
          bodyFind('Firmness') ??
          bodyFind('Retraction') ??
          bodyFind('Tightness');
      final smoothness =
          bodyFind('Smoothness') ?? bodyFind('Texture') ?? bodyFind('Evenness');
      final retention = bodyFind('Fat Retention') ?? bodyFind('Volume');
      final pigment = bodyFind('Hyperpigmentation') ?? bodyFind('Pigment');

      if (swelling?.level == MetricClinicalLevel.elevated ||
          swelling?.level == MetricClinicalLevel.moderate) {
        return 'Swelling and bruising at ${swelling!.value.toStringAsFixed(1)} is the body-contouring priority. Review compression garment fit and wear time, schedule manual lymphatic drainage if cleared by your surgeon, keep gentle walking consistent, and avoid activity spikes that increase edema. Contact your surgical team promptly if swelling is asymmetric, warm, painful, or suddenly worsening.';
      }
      if (retention?.level == MetricClinicalLevel.elevated ||
          retention?.level == MetricClinicalLevel.moderate) {
        final bblNote = bodySubtype == ProcedureBodyContouringSubtype.bbl
            ? ' Continue avoiding direct buttock pressure until cleared; positioning discipline is still one of the strongest protectors of fat graft survival.'
            : '';
        return 'Fat retention is the key recovery signal to protect right now. Prioritize stable calories, adequate protein, hydration, compression as directed, and low-impact movement only.$bblNote If volume loss appears sudden or asymmetric, review the scan with your provider.';
      }
      if (firmness?.level == MetricClinicalLevel.elevated ||
          smoothness?.level == MetricClinicalLevel.elevated ||
          firmness?.level == MetricClinicalLevel.moderate ||
          smoothness?.level == MetricClinicalLevel.moderate) {
        final label =
            (firmness?.level == MetricClinicalLevel.elevated ||
                firmness?.level == MetricClinicalLevel.moderate)
            ? firmness!
            : smoothness!;
        return '${label.label} at ${label.value.toStringAsFixed(1)} is the main contour-quality opportunity. Consistent compression, provider-cleared manual lymphatic drainage, gentle walking, hydration, and protein intake are the highest-value actions. If firmness, lumpiness, or unevenness is increasing after the early swelling phase, ask your surgeon about fibrosis management.';
      }
      if (pigment?.level == MetricClinicalLevel.elevated ||
          pigment?.level == MetricClinicalLevel.moderate) {
        return 'Hyperpigmentation around bruised or incision-adjacent areas is the main focus. Keep treated areas protected from UV exposure, avoid friction from poorly fitted garments, and document any expanding discoloration. Discuss persistent pigment or incision color change with your surgical team.';
      }

      final positioning = bodySubtype == ProcedureBodyContouringSubtype.bbl
          ? ', and strict positioning rules until your surgeon releases them'
          : '';
      return 'Your body-contouring recovery metrics are generally holding in a favorable range for $contextLabel. Keep the fundamentals steady: compression as directed, lymphatic drainage if cleared, gentle walking, adequate protein, hydration$positioning. Consistent scans will show whether swelling, firmness, bruising, pigment, and contour stability continue trending in the right direction.';
    }

    if (redness?.level == MetricClinicalLevel.elevated) {
      final isLegacyBodyContouring =
          proc != null &&
          (proc.toLowerCase().contains('bbl') ||
              proc.toLowerCase().contains('liposuction') ||
              proc.toLowerCase().contains('lipo') ||
              proc.toLowerCase().contains('tummy tuck') ||
              proc.toLowerCase().contains('butt lift') ||
              proc.toLowerCase().contains('body contour') ||
              proc.toLowerCase().contains('arm lift') ||
              proc.toLowerCase().contains('thigh lift'));
      if (isLegacyBodyContouring) {
        return 'Post-op swelling at ${redness!.value.toStringAsFixed(1)} (elevated) is the primary management priority. Compression garment must be worn as directed 24/7 — this is the single most important intervention for controlling edema. Begin or intensify manual lymphatic drainage (MLD) sessions with a certified therapist — 2–3 sessions per week provides the most clinical benefit. Elevate treated areas when resting. Contact your surgeon if swelling is asymmetric, worsening, or associated with new pain or fever.';
      }
      final procNote = proc != null
          ? ' This is particularly important during $proc recovery, where sustained erythema can impair healing quality.'
          : '';
      return 'Redness at ${redness!.value.toStringAsFixed(1)} (elevated) is the immediate clinical priority.$procNote Apply SPF 50+ every morning without exception. Introduce azelaic acid 10–20% or niacinamide 10% twice daily to modulate vascular reactivity. Hold all retinoids and exfoliating acids until redness falls below 5.0 on your next scan.';
    }

    if (elasticity?.level == MetricClinicalLevel.elevated) {
      return 'Skin firmness at ${elasticity!.value.toStringAsFixed(1)} (significant laxity) is the priority concern. A prescription retinoid — the most evidence-based intervention for dermal remodeling — should form the cornerstone of your home protocol. Combine with a collagen-stimulating peptide serum and discuss energy-based tightening options (RF microneedling or HIFU) with your provider for meaningful structural improvement.';
    }

    if (darkSpots?.level == MetricClinicalLevel.elevated) {
      final procNote = proc != null
          ? ' Post-$proc hyperpigmentation is a well-documented risk — diligent photoprotection is the most impactful preventive step.'
          : '';
      return 'Hyperpigmentation at ${darkSpots!.value.toStringAsFixed(1)} (significant) is the primary focus.$procNote Apply SPF 50+ daily and layer vitamin C serum (15–20%) each morning. Discuss prescription-strength depigmentation agents — hydroquinone 4% or a tretinoin-azelaic acid combination — with your provider for accelerated clearance.';
    }

    if (darkSpots?.level == MetricClinicalLevel.moderate ||
        redness?.level == MetricClinicalLevel.moderate) {
      final isDual =
          redness?.level == MetricClinicalLevel.moderate &&
          darkSpots?.level == MetricClinicalLevel.moderate;
      final focus = isDual
          ? 'both pigmentation (${darkSpots!.value.toStringAsFixed(1)}) and redness (${redness!.value.toStringAsFixed(1)})'
          : redness?.level == MetricClinicalLevel.moderate
          ? 'redness at ${redness!.value.toStringAsFixed(1)}'
          : 'hyperpigmentation at ${darkSpots!.value.toStringAsFixed(1)}';
      return 'Addressing $focus is the primary opportunity. Daily SPF 50+ is non-negotiable. Niacinamide 10% twice daily and vitamin C 15% each morning can meaningfully reduce both vascular reactivity and melanin irregularity over 8–12 weeks of consistent use.';
    }

    if (texture?.level == MetricClinicalLevel.elevated ||
        texture?.level == MetricClinicalLevel.moderate) {
      return 'Surface texture at ${texture!.value.toStringAsFixed(1)} (${texture.level == MetricClinicalLevel.elevated ? 'elevated' : 'moderate'}) is the key area for improvement. Introduce retinol (0.025% to start, titrating upward every 4–6 weeks as tolerated) at night, paired with a gentle AHA exfoliant 2× weekly. A ceramide-rich moisturizer used morning and evening supports barrier integrity during the adjustment phase.';
    }

    if (wrinkle?.level == MetricClinicalLevel.moderate ||
        wrinkle?.level == MetricClinicalLevel.elevated) {
      return 'Line depth at ${wrinkle!.value.toStringAsFixed(1)} (${wrinkle.level == MetricClinicalLevel.elevated ? 'elevated' : 'moderate'}) benefits from a targeted anti-aging protocol. Tretinoin or prescription-strength retinoid is the most evidence-based topical intervention available. Combine with daily SPF 50+ and a peptide-rich moisturizer. For dynamic lines, neuromodulator options are worth discussing with your provider.';
    }

    // All metrics mild or optimal
    final procContext = proc != null
        ? ' This consistency is particularly valuable during $proc recovery, when the skin is most biologically receptive to supportive care.'
        : '';
    return 'Your skin metrics are in a genuinely healthy range across the board — and that\'s worth acknowledging. Whatever you\'re doing consistently, it\'s reflected in this data. The evidence-based triad for sustaining and building on this foundation is straightforward: daily SPF 50+ as your most powerful single anti-aging tool, a well-tolerated retinoid at night to drive ongoing dermal renewal, and consistent hydration to preserve barrier integrity. These three, done reliably over time, outperform any collection of targeted actives.$procContext';
  }

  // ---------------------------------------------------------------------------
  // Daily Briefing Generator
  // ---------------------------------------------------------------------------

  /// Generates a personalized daily AI briefing for the home screen.
  static AiDailyBriefing generateDailyBriefing({
    required List<ScanHistoryEntry> scans,
    required List<Procedure> procedures,
    List<TrackedProduct> products = const [],
    String? currentProcedureType,
  }) {
    String? cleanProcedure(String? value) {
      final normalized = (value ?? '').trim();
      if (normalized.isEmpty) return null;
      if (normalized.toLowerCase() == 'unknown') return null;
      return normalized;
    }

    String resolveProcedureType() {
      final fromCurrentContext = cleanProcedure(currentProcedureType);
      if (fromCurrentContext != null) return fromCurrentContext;
      for (final procedure in procedures) {
        final cleaned = cleanProcedure(procedure.type);
        if (cleaned != null) return cleaned;
      }
      final sortedScans = [...scans]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      for (final scan in sortedScans) {
        final cleaned = cleanProcedure(scan.procedure);
        if (cleaned != null) return cleaned;
      }
      return 'General Skincare';
    }

    final resolvedProcedureType = resolveProcedureType();
    final hasProcedure = procedures.isNotEmpty;
    final hasScans = scans.length >= 2;
    final hasProducts = products.isNotEmpty;
    final isBodyProcedure =
        hasProcedure &&
        usesBodyContouringContext(
          procedureType: procedures.first.type,
          customDescription: procedures.first.customDescription,
          focusArea: procedures.first.focusArea,
        );

    if (!hasProcedure && !hasScans && !hasProducts) {
      return const AiDailyBriefing(
        headline: 'Welcome to Your AI Skin Intelligence',
        subheadline: 'Start tracking to unlock personalized insights',
        insights: [
          BriefingInsight(
            icon: Icons.camera_alt_outlined,
            title: 'Take Your First Scan',
            body:
                'Your baseline scan is the reference point every future AI analysis builds from. For the most accurate tracking: consistent angle and lighting, the same time of day, without makeup. This one scan unlocks every trend comparison and recovery tracking feature.',
            priority: BriefingPriority.high,
            color: Color(0xFF6A1B9A),
          ),
        ],
        todaysFocus:
            'Your first scan creates the baseline that all future AI comparisons reference. Take it in good natural light, at a consistent time of day, without makeup — this single scan activates every trend analysis and recovery tracking feature in the app.',
        hasMeaningfulData: false,
      );
    }

    final insights = <BriefingInsight>[];
    String headline = 'Your AI Skin Intelligence';
    String subheadline = 'Personalized insights from your data';
    String todaysFocus =
        'Keep scanning consistently for the most accurate trend analysis.';

    // Procedure-based insights
    if (hasProcedure) {
      final latest = procedures.first;
      final latestLabel = procedureContextLabel(
        procedureType: latest.type,
        customDescription: latest.customDescription,
        focusArea: latest.focusArea,
      );
      final daysSince = DateTime.now().difference(latest.startDate).inDays;
      final weeksSince = (daysSince / 7).floor();

      headline = '$latestLabel Recovery — Day $daysSince';
      subheadline = _recoveryStageLabel(daysSince);

      insights.add(
        _generateRecoveryStageInsight(
          latest.type,
          daysSince,
          customDescription: latest.customDescription,
          focusArea: latest.focusArea,
        ),
      );

      if (isBodyProcedure) {
        final subtype = ProcedureIntelligence.bodyContouringSubtype(
          latest.type,
        );
        final bblPositioning = subtype == ProcedureBodyContouringSubtype.bbl
            ? ' Avoid direct buttock pressure and use your BBL pillow exactly as directed.'
            : '';
        if (daysSince <= 14) {
          todaysFocus =
              'Day $daysSince focus for $latestLabel: compression garment compliance, gentle walking, hydration, protein intake, and swelling/bruising documentation.$bblPositioning Log today\'s scan so swelling, firmness, bruising, pigment, contour, and overall healing can be compared cleanly against baseline.';
        } else if (daysSince <= 56) {
          todaysFocus =
              'This stage is about swelling resolution, lymphatic flow, firmness/fibrosis control, and contour evenness. Keep compression and provider-cleared manual lymphatic drainage consistent, avoid activity spikes, and scan in consistent lighting so body metrics reflect real recovery change.';
        } else {
          todaysFocus =
              'Your contour is settling into its longer-term shape. Track fat retention, firmness, smoothness, bruising, pigment, and overall healing weekly, and bring any persistent asymmetry, new swelling, or volume concern to your surgical team.';
        }
      } else if (daysSince <= 7) {
        todaysFocus =
            'Days 1–7 are the most critical window of your entire recovery. The micro-channels and tissue disruption from your procedure are actively consolidating right now. Keep all active skincare ingredients off completely, cleanse gently twice daily, and apply a fragrance-free moisturizer before bed. Log any symptoms — redness, warmth, unusual swelling — with a scan photo so we can track your healing trajectory accurately.';
      } else if (daysSince <= 21) {
        todaysFocus =
            'You\'re in the inflammation resolution phase, and what you do consistently right now will meaningfully affect your final results. Twice-daily gentle hydration, SPF 50+ every morning without exception, and daily photo logging give us the most reliable data to track your inflammatory curve. Avoid introducing new products until inflammation settles below score 5.0.';
      } else if (daysSince <= 60) {
        todaysFocus =
            'Week ${weeksSince + 1}: collagen remodeling is now the dominant biological process. The new tissue being laid down right now will define your outcome — and scans taken consistently in this window are the only way to capture how your skin is actually responding. This is an ideal time to re-evaluate your active skincare routine with your provider.';
      } else {
        todaysFocus =
            'Final results continue refining for up to 12 months post-procedure — longer than most people expect. Day-to-day changes are subtle, but your cumulative scan data tells the true story. Consistency in scanning now gives you — and your provider — the most accurate picture of your long-term outcome.';
      }
    }

    // Scan-trend insights
    if (hasScans) {
      final sortedScans = List<ScanHistoryEntry>.from(scans)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final latest = sortedScans.first;
      final baseline = sortedScans.last;

      if (baseline.id != latest.id) {
        final latestMetrics = latest.toSkinMetrics();
        final baselineMetrics = baseline.toSkinMetrics();
        if (isBodyProcedure) {
          final bodyMetricSet = getMetricsForProcedure(
            procedureMetricContextType(
              procedureType: procedures.first.type,
              customDescription: procedures.first.customDescription,
              focusArea: procedures.first.focusArea,
            ),
          );
          for (final metric in bodyMetricSet.additional.take(3)) {
            final trendInsight = _generateTrendInsight(
              metricLabel: metric.label,
              latest: metric.valueFor(latestMetrics, rawMetrics: latest.metrics),
              baseline: metric.valueFor(
                baselineMetrics,
                rawMetrics: baseline.metrics,
              ),
              lowerIsBetter: metric.lowerIsBetter,
              bodyRecoveryLanguage: true,
            );
            if (trendInsight != null) insights.add(trendInsight);
          }
        } else {
          final rednessInsight = _generateTrendInsight(
            metricLabel: 'Erythema',
            latest: latestMetrics.redness,
            baseline: baselineMetrics.redness,
            lowerIsBetter: true,
          );
          if (rednessInsight != null) insights.add(rednessInsight);

          final textureInsight = _generateTrendInsight(
            metricLabel: 'Skin Texture Quality',
            latest: latestMetrics.texture,
            baseline: baselineMetrics.texture,
            lowerIsBetter: true,
          );
          if (textureInsight != null) insights.add(textureInsight);
        }
      }

      // Days since last scan
      final daysSinceLastScan = DateTime.now()
          .difference(latest.timestamp)
          .inDays;
      if (daysSinceLastScan >= 7) {
        insights.add(
          BriefingInsight(
            icon: Icons.schedule_outlined,
            title: 'Scan Overdue',
            body:
                'Your last scan was $daysSinceLastScan days ago. Gaps this long create blind spots in the trend analysis — significant skin changes can occur in a week, especially during recovery. Taking a scan today restores the continuity that makes the AI insights most reliable.',
            priority: BriefingPriority.medium,
            color: const Color(0xFFE65100),
          ),
        );
      }
    }

    // Product insights
    if (hasProducts && !isBodyProcedure) {
      final spfProduct = products.any(
        (p) =>
            p.name.toLowerCase().contains('spf') ||
            p.keyIngredients.toLowerCase().contains('spf') ||
            p.name.toLowerCase().contains('sunscreen'),
      );

      if (!spfProduct) {
        insights.add(
          const BriefingInsight(
            icon: Icons.wb_sunny_outlined,
            title: 'SPF Missing from Routine',
            body:
                'Daily SPF 50+ is the most evidence-based anti-aging and post-procedure protective measure available — without it, UV exposure actively works against every other improvement you\'re tracking. Add a sunscreen to your routine and log it here so we can factor it into your analysis.',
            priority: BriefingPriority.high,
            color: Color(0xFFB71C1C),
          ),
        );
      }

      if (products.length >= 4) {
        final hasRetinol = products.any(
          (p) =>
              p.name.toLowerCase().contains('retinol') ||
              p.keyIngredients.toLowerCase().contains('retinol') ||
              p.keyIngredients.toLowerCase().contains('tretinoin'),
        );
        final hasAcid = products.any(
          (p) =>
              p.keyIngredients.toLowerCase().contains('glycolic') ||
              p.keyIngredients.toLowerCase().contains('salicylic') ||
              p.keyIngredients.toLowerCase().contains('aha') ||
              p.keyIngredients.toLowerCase().contains('bha'),
        );

        if (hasRetinol && hasAcid) {
          insights.add(
            const BriefingInsight(
              icon: Icons.warning_amber_outlined,
              title: 'Retinol + Acid Interaction',
              body:
                  'Your routine contains both a retinoid and an exfoliating acid (AHA or BHA). Using both on the same evening reduces the optimal pH for retinoid conversion and can disrupt your skin barrier. Alternating nights — retinoid one evening, acid the next — lets each ingredient work at full efficacy without competing.',
              priority: BriefingPriority.medium,
              color: Color(0xFFE65100),
            ),
          );
        }
      }
    }

    // Cap to 3 most relevant insights
    final sortedInsights = insights.take(3).toList();

    // Scan-only context: override generic todaysFocus with something meaningful
    if (!hasProcedure && hasScans) {
      todaysFocus =
          'The most valuable insight isn\'t any single scan \u2014 it\'s the pattern across multiple scans over time. Weekly check-ins at consistent lighting and time of day build the trend data that transforms raw numbers into a meaningful clinical picture of your skin\'s trajectory. Your most recent scan is already part of that story.';
    }

    return AiDailyBriefing(
      headline: headline,
      subheadline: subheadline,
      insights: sortedInsights,
      todaysFocus: todaysFocus,
      hasMeaningfulData: hasProcedure || hasScans,
    );
  }

  static String _recoveryStageLabel(int days) {
    if (days <= 3) {
      return 'Acute healing phase — follow aftercare protocol strictly';
    }
    if (days <= 14) {
      return 'Active inflammation resolution — day $days of recovery';
    }
    if (days <= 30) {
      return 'Early remodeling phase — week ${(days / 7).ceil()} of recovery';
    }
    if (days <= 90) {
      return 'Tissue remodeling phase — month ${(days / 30).ceil()} of recovery';
    }
    return 'Late remodeling phase — final results still refining';
  }

  static BriefingInsight _generateRecoveryStageInsight(
    String procedureType,
    int daysSince, {
    String? customDescription,
    String? focusArea,
  }) {
    final category =
        usesBodyContouringContext(
          procedureType: procedureType,
          customDescription: customDescription,
          focusArea: focusArea,
        )
        ? ProcedureCategory.bodyContouring
        : ProcedureIntelligence.categoryFor(procedureType);
    final profile = ProcedureIntelligence.forType(procedureType);
    final procLower = procedureType.toLowerCase();
    final contextLabel = procedureContextLabel(
      procedureType: procedureType,
      customDescription: customDescription,
      focusArea: focusArea,
    );
    final isMicroneedling =
        procLower.contains('microneedling') ||
        procLower.contains('micro needling');
    final isPeel = procLower.contains('peel') || procLower.contains('chemical');
    final isLaser =
        procLower.contains('laser') || procLower.contains('resurfac');
    final isInjectables = category == ProcedureCategory.injectables;
    final isHairTransplant = category == ProcedureCategory.hairTransplant;
    final isSurgicalFace = category == ProcedureCategory.surgicalFace;
    final isBodyContouring = category == ProcedureCategory.bodyContouring;

    // ── Hair Transplant ──────────────────────────────────────────────────────
    if (isHairTransplant) {
      if (daysSince <= 7) {
        return BriefingInsight(
          icon: Icons.healing_outlined,
          title: 'Graft Consolidation — Day $daysSince',
          body:
              'Day $daysSince of hair transplant recovery. Scabs are forming around grafts — this is protective. Do NOT pick, rub, or forcibly wet the scabs. Gentle salt-water misting (if provider-approved) only. Scalp redness and slight swelling are expected.',
          priority: BriefingPriority.high,
          color: const Color(0xFFB71C1C),
        );
      } else if (daysSince <= 21) {
        return BriefingInsight(
          icon: Icons.trending_up_outlined,
          title: 'Shock-Loss Phase — Day $daysSince',
          body:
              'Day $daysSince: transplanted hairs may be shedding now — this is completely normal shock loss and does not mean the grafts have failed. The follicle roots remain intact. Donor area healing should be progressing well.',
          priority: BriefingPriority.medium,
          color: const Color(0xFF6A1B9A),
        );
      } else if (daysSince <= 120) {
        return BriefingInsight(
          icon: Icons.auto_awesome_outlined,
          title: 'New Growth Beginning — Day $daysSince',
          body:
              'New hair shafts may be emerging. Initial growth is fine and unpigmented — this is normal. Most patients see visible new hair between months 3–5. Scalp scans now capture baseline density for comparison against your 6- and 12-month results.',
          priority: BriefingPriority.medium,
          color: const Color(0xFF2E7D32),
        );
      } else {
        return BriefingInsight(
          icon: Icons.check_circle_outline,
          title: 'Density Accumulating — Month ${(daysSince / 30).ceil()}',
          body:
              'Month ${(daysSince / 30).ceil()} post-transplant. Hair density is accumulating progressively — final result is typically visible at months 12–18. Your scans document this density journey in real time.',
          priority: BriefingPriority.low,
          color: const Color(0xFF1565C0),
        );
      }
    }

    // ── Surgical Face ────────────────────────────────────────────────────────
    if (isSurgicalFace) {
      if (daysSince <= 7) {
        return BriefingInsight(
          icon: Icons.healing_outlined,
          title: 'Post-Surgical Healing — Day $daysSince',
          body:
              'Day $daysSince of ${profile.primaryFocusLabel}. Peak swelling and bruising are expected now — this is normal physiology, not a complication. Head elevated, cold compresses, rest. Contact your surgeon for fever, worsening pain, spreading redness, or unusual drainage.',
          priority: BriefingPriority.high,
          color: const Color(0xFFB71C1C),
        );
      } else if (daysSince <= 30) {
        return BriefingInsight(
          icon: Icons.trending_up_outlined,
          title: 'Swelling Resolving — Day $daysSince',
          body:
              'Day $daysSince: swelling and bruising are gradually resolving. Most patients are comfortable in public by week 2–3. Deep swelling can persist for months — avoid assessing final results until month 3 at the earliest.',
          priority: BriefingPriority.medium,
          color: const Color(0xFF6A1B9A),
        );
      } else if (daysSince <= 90) {
        return BriefingInsight(
          icon: Icons.auto_awesome_outlined,
          title: 'Scar Maturation — Week ${(daysSince / 7).ceil()}',
          body:
              'Day $daysSince: scars are in active maturation — pink, firm, and slightly raised is completely normal at this stage. They will continue to fade and flatten over 6–12 months. Avoid sun exposure on scars (SPF 50+ daily).',
          priority: BriefingPriority.medium,
          color: const Color(0xFF2E7D32),
        );
      } else {
        return BriefingInsight(
          icon: Icons.check_circle_outline,
          title: 'Late Refinement — Month ${(daysSince / 30).ceil()}',
          body:
              'Month ${(daysSince / 30).ceil()}: final results are coming into focus. Residual swelling resolves slowly — most surgeons evaluate final outcomes at 12 months. Scar assessment and any refinement procedures can be discussed at your next consultation.',
          priority: BriefingPriority.low,
          color: const Color(0xFF1565C0),
        );
      }
    }

    // ── Body Contouring ──────────────────────────────────────────────────────
    if (isBodyContouring) {
      final isBBL =
          !isCustomProcedureType(procedureType) &&
          (procLower.contains('bbl') ||
              procLower.contains('butt lift') ||
              procLower.contains('brazilian'));
      if (daysSince <= 7) {
        final bblNote = isBBL
            ? ' BBL: NO sitting directly on buttocks — foam pillow under thighs only. Sleep face-down or on your sides. Every instance of direct pressure risks fat cell death and permanent volume loss.'
            : ' Liposuction and other contouring procedures should focus on compression, walking, and swelling control instead of BBL-only positioning rules.';
        return BriefingInsight(
          icon: Icons.healing_outlined,
          title: 'Critical Recovery Window — Day $daysSince',
          body:
              'Day $daysSince: This is the most impactful window for $contextLabel. Swelling, bruising, and tissue healing are actively evolving right now — your behavior this week directly affects contour quality and recovery speed. Compression garment 24/7.$bblNote Gentle walking from day 2 reduces DVT risk and promotes lymphatic drainage.',
          priority: BriefingPriority.high,
          color: const Color(0xFFB71C1C),
        );
      } else if (daysSince <= 21) {
        final bblNote = isBBL
            ? ' Fat graft blood supply is consolidating — BBL pillow compliance remains essential. Any direct sitting pressure before week 6 compromises the grafts.'
            : ' Contour settling and fibrosis control are the focus for liposuction and non-fat-transfer procedures.';
        return BriefingInsight(
          icon: Icons.healing_outlined,
          title: 'Graft Consolidation Phase — Day $daysSince',
          body:
              'Day $daysSince: Swelling and bruising are gradually resolving.$bblNote Drains removed around day 10–14 if placed. Transition to Stage 2 compression garment per your provider\'s schedule. Light walking encouraged daily — gentle movement is your best tool for lymphatic drainage right now.',
          priority: BriefingPriority.high,
          color: const Color(0xFFB71C1C),
        );
      } else if (daysSince <= 56) {
        const fibroNote =
            'Fibrosis (firm, lumpy areas under the skin) is developing in most patients now — this is expected and highly treatable. Manual lymphatic drainage (MLD) sessions with a certified therapist are the most effective intervention. Aim for 2–3 sessions per week.';
        final bblNote = isBBL
            ? ' BBL: You are approaching the 6–8 week window when positioning restrictions lift. Continue BBL pillow discipline until your surgeon clears unrestricted sitting.'
            : ' Liposuction recovery should stay focused on compression, drainage, and contour evenness rather than BBL-specific sitting restrictions.';
        return BriefingInsight(
          icon: Icons.trending_up_outlined,
          title: 'Fibrosis & Lymphatic Phase — Day $daysSince',
          body:
              'Day $daysSince: $fibroNote$bblNote Contour assessment is premature — significant swelling remains.',
          priority: BriefingPriority.medium,
          color: const Color(0xFF6A1B9A),
        );
      } else if (daysSince <= 120) {
        final bblNote = isBBL
            ? ' BBL fat retention is now largely determined. The volume you have now reflects approximately 60–80% survival of the originally transferred fat — this is the expected clinical range.'
            : ' Liposuction contour is now mostly driven by swelling resolution and skin retraction rather than fat graft survival.';
        return BriefingInsight(
          icon: Icons.auto_awesome_outlined,
          title:
              'Skin Retraction & Volume Settling — Week ${(daysSince / 7).ceil()}',
          body:
              'Day $daysSince: Skin is actively retracting to your new contour.$bblNote Residual swelling continues resolving — avoid assessing final results before month 4–6. Consistent scanning now captures the retraction and contour-evenness progress that predicts your final outcome.',
          priority: BriefingPriority.medium,
          color: const Color(0xFF2E7D32),
        );
      } else {
        return BriefingInsight(
          icon: Icons.check_circle_outline,
          title: 'Final Contour Refining — Month ${(daysSince / 30).ceil()}',
          body:
              'Month ${(daysSince / 30).ceil()}: Your contour is approaching its permanent settled state. Any remaining irregularity, asymmetry, or volume concerns can now be meaningfully discussed with your surgeon. Scar maturation continues — SPF 50+ on all incision sites daily. If considering refinement procedures, most surgeons prefer to wait until the 6–12 month mark.',
          priority: BriefingPriority.low,
          color: const Color(0xFF1565C0),
        );
      }
    }

    // ── Injectables ──────────────────────────────────────────────────────────
    if (isInjectables) {
      if (daysSince <= 7) {
        return BriefingInsight(
          icon: Icons.healing_outlined,
          title: 'Post-Injectable Care — Day $daysSince',
          body:
              'Day $daysSince post-injectables. Avoid massage, heat, or pressure on treated areas for 24–48 hours. Mild bruising and swelling are normal and typically resolve within 3–5 days. Neuromodulators take 3–7 days to begin working.',
          priority: BriefingPriority.high,
          color: const Color(0xFFB71C1C),
        );
      } else if (daysSince <= 21) {
        return BriefingInsight(
          icon: Icons.trending_up_outlined,
          title: 'Injectable Integration — Day $daysSince',
          body:
              'Day $daysSince: neuromodulator effect reaching its peak (day 14). Fillers integrating and swelling resolved. This is the ideal time to assess symmetry and discuss any touch-up needs with your provider.',
          priority: BriefingPriority.medium,
          color: const Color(0xFF6A1B9A),
        );
      } else {
        return BriefingInsight(
          icon: Icons.check_circle_outline,
          title: 'Stable Result — Day $daysSince',
          body:
              'Day $daysSince: results are stable. Neuromodulators typically last 3–4 months; HA fillers 6–18 months depending on product. Monitor for early return of movement or volume to time your next appointment optimally.',
          priority: BriefingPriority.low,
          color: const Color(0xFF1565C0),
        );
      }
    }

    // ── Laser / Peel / Microneedling ─────────────────────────────────────────
    if (daysSince <= 7) {
      String body;
      if (isMicroneedling) {
        body =
            'Day $daysSince of microneedling recovery. Micro-channels are still consolidating — avoid active ingredients, makeup, and direct sun for at least 72 hours. Keep the treated area clean and well-hydrated with a fragrance-free moisturizer.';
      } else if (isPeel) {
        body =
            'Day $daysSince of chemical peel recovery. Flaking and sensitivity are expected — resist picking or peeling skin manually. Gentle cleanser, barrier moisturizer, and SPF 50+ when outdoors are the only products indicated right now.';
      } else if (isLaser) {
        body =
            'Day $daysSince of laser recovery. Erythema and mild edema are expected at this stage. Strict sun avoidance and SPF 50+ are critical — UV exposure now significantly increases the risk of post-inflammatory hyperpigmentation.';
      } else {
        body =
            'Day $daysSince of $procedureType recovery. Inflammation control and barrier protection are the primary clinical goals. Avoid actives, minimise sun exposure, and cleanse gently twice daily.';
      }
      return BriefingInsight(
        icon: Icons.healing_outlined,
        title: 'Acute Recovery — Day $daysSince',
        body: body,
        priority: BriefingPriority.high,
        color: const Color(0xFFB71C1C),
      );
    } else if (daysSince <= 30) {
      String body;
      if (isMicroneedling) {
        body =
            'Day $daysSince: collagen induction is underway. This is the optimal window to reintroduce supportive actives — vitamin C in the morning and retinol at night if tolerated. Scan regularly to capture early remodeling changes.';
      } else if (isPeel || isLaser) {
        body =
            'Day $daysSince: re-epithelialization is progressing. With provider clearance, you may gently reintroduce antioxidant serums. Continue SPF 50+ without interruption — photoprotection remains the most important daily step.';
      } else {
        body =
            'Day $daysSince: early remodeling is beginning. Establish a consistent scan cadence now to build the most complete baseline-versus-recovery comparison dataset.';
      }
      return BriefingInsight(
        icon: Icons.trending_up_outlined,
        title: 'Inflammation Resolving — Day $daysSince',
        body: body,
        priority: BriefingPriority.medium,
        color: const Color(0xFF6A1B9A),
      );
    } else if (daysSince <= 90) {
      String body;
      if (isMicroneedling) {
        body =
            'Week ${(daysSince / 7).ceil()}: you\'re in the prime collagen induction window. The controlled micro-injury stimulus has activated fibroblasts, and new collagen I and III fibers are being deposited in your dermis right now. The improvements in texture and firmness you may be starting to notice are a direct result of this process — and they\'ll continue developing for another 2–3 months. Consistent scanning captures this remodeling in real time.';
      } else if (isPeel || isLaser) {
        body =
            'Day $daysSince: re-epithelialization is complete, but the deeper collagen remodeling phase has only just begun. Meaningful structural improvement in texture, tone, and elasticity will continue developing for 3–6 months. UV protection remains critical — recently resurfaced skin is especially susceptible to post-inflammatory hyperpigmentation even from brief, unprotected exposures.';
      } else {
        body =
            'Day $daysSince: active remodeling is producing structural changes that may not yet be fully visible. Your scan data over the coming weeks is the most reliable indicator of how your skin is responding to $procedureType recovery.';
      }
      return BriefingInsight(
        icon: Icons.auto_awesome_outlined,
        title: 'Active Remodeling — Week ${(daysSince / 7).ceil()}',
        body: body,
        priority: BriefingPriority.medium,
        color: const Color(0xFF2E7D32),
      );
    } else {
      String body;
      if (isMicroneedling || isPeel || isLaser) {
        body =
            'Month ${(daysSince / 30).ceil()} post $procedureType — you\'re in the late refinement phase. Final skin quality from resurfacing and induction procedures often isn\'t fully apparent until 9–12 months. The elasticity and tone improvements happening now are subtle but real, and your scan timeline documents the full arc of what\'s been achieved.';
      } else {
        body =
            'Month ${(daysSince / 30).ceil()} post $procedureType. Your scan data at this stage captures the refined, stable endpoint of your treatment journey. Comparing your current metrics to your earliest baseline gives you — and your provider — the most complete picture of your outcome.';
      }
      return BriefingInsight(
        icon: Icons.check_circle_outline,
        title: 'Late Remodeling — Month ${(daysSince / 30).ceil()}',
        body: body,
        priority: BriefingPriority.low,
        color: const Color(0xFF1565C0),
      );
    }
  }

  static BriefingInsight? _generateTrendInsight({
    required String metricLabel,
    required double latest,
    required double baseline,
    required bool lowerIsBetter,
    bool bodyRecoveryLanguage = false,
  }) {
    final delta = latest - baseline;
    final improved = lowerIsBetter ? delta < -0.3 : delta > 0.3;
    final worsened = lowerIsBetter ? delta > 0.5 : delta < -0.5;

    if (!improved && !worsened) return null;

    if (improved) {
      final fromTo =
          '${baseline.toStringAsFixed(1)} → ${latest.toStringAsFixed(1)}';
      final magnitude = delta.abs();
      final clinicalContext = bodyRecoveryLanguage
          ? (magnitude >= 1.0
                ? 'A shift of this size usually reflects meaningful recovery progress in swelling control, contour settling, tissue firmness, or graft stability rather than day-to-day variation.'
                : 'Small body-contouring improvements matter when they persist across scans; they are how swelling resolution, firmness, and contour definition build over time.')
          : (magnitude >= 1.0
                ? 'A reduction of this magnitude typically reflects genuine resolution of the underlying inflammatory or structural process — not just day-to-day variation.'
                : 'This type of incremental improvement, sustained across scans, is how meaningful clinical change accumulates.');
      final nextStep = bodyRecoveryLanguage
          ? 'Keep compression, lymphatic drainage, protein intake, hydration, and positioning guidance consistent.'
          : 'Keep your current routine consistent.';
      return BriefingInsight(
        icon: Icons.trending_down_outlined,
        title: '$metricLabel Improving',
        body:
            '$metricLabel has moved from $fromTo — a ${magnitude.toStringAsFixed(1)}-point improvement versus baseline. $clinicalContext $nextStep',
        priority: BriefingPriority.low,
        color: const Color(0xFF2E7D32),
      );
    } else {
      final fromTo =
          '${baseline.toStringAsFixed(1)} → ${latest.toStringAsFixed(1)}';
      final body = bodyRecoveryLanguage
          ? '$metricLabel has shifted from $fromTo (${delta.abs().toStringAsFixed(1)} points in the wrong direction). Review compression fit and wear time, lymphatic drainage cadence, positioning restrictions, hydration/protein intake, and recent activity level. Contact your surgical team if swelling, bruising, asymmetry, warmth, or pain is increasing.'
          : '$metricLabel has risen from $fromTo (+${delta.abs().toStringAsFixed(1)}). An upward shift of this size warrants a review of any recent product changes, environmental exposures (sun, heat, pollution), or disruptions to your routine that may have contributed. Catching this now gives you the best opportunity to course-correct before it becomes a trend.';
      return BriefingInsight(
        icon: Icons.trending_up,
        title: '$metricLabel Needs Attention',
        body: body,
        priority: BriefingPriority.medium,
        color: const Color(0xFFE65100),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Coach Context Builder (for AI Recovery Coach enrichment)
  // ---------------------------------------------------------------------------

  /// Builds a rich metric context string for injecting into the AI coach prompt.
  static String buildCoachMetricContext({
    required List<ScanHistoryEntry> scans,
    String? procedureType,
  }) {
    if (scans.isEmpty) return 'No scan data available yet.';

    final sorted = List<ScanHistoryEntry>.from(scans)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final latest = sorted.first.toSkinMetrics();
    final baseline = sorted.length > 1 ? sorted.last.toSkinMetrics() : null;

    final buf = StringBuffer();
    buf.writeln(
      'Latest skin scan metrics (scale 1-10; redness/texture/wrinkle/pore/darkSpots = lower is better; elasticity = higher is better):',
    );
    buf.writeln(
      '  Redness: ${latest.redness.toStringAsFixed(1)}${_levelSuffix(_interpretRedness(latest.redness).level)}',
    );
    buf.writeln(
      '  Texture: ${latest.texture.toStringAsFixed(1)}${_levelSuffix(_interpretTexture(latest.texture).level)}',
    );
    buf.writeln(
      '  Wrinkles: ${latest.wrinkle.toStringAsFixed(1)}${_levelSuffix(_interpretWrinkle(latest.wrinkle).level)}',
    );
    buf.writeln(
      '  Pores: ${latest.pore.toStringAsFixed(1)}${_levelSuffix(_interpretPore(latest.pore).level)}',
    );
    buf.writeln(
      '  Dark Spots: ${latest.darkSpots.toStringAsFixed(1)}${_levelSuffix(_interpretDarkSpots(latest.darkSpots).level)}',
    );
    buf.writeln(
      '  Elasticity: ${latest.elasticity.toStringAsFixed(1)}${_levelSuffix(_interpretElasticity(latest.elasticity).level)}',
    );

    if (baseline != null) {
      buf.writeln('\nBaseline comparison (earliest scan):');
      final rDelta = latest.redness - baseline.redness;
      final tDelta = latest.texture - baseline.texture;
      final eDelta = latest.elasticity - baseline.elasticity;
      buf.writeln(
        '  Redness trend: ${rDelta < 0
            ? '↓ improved'
            : rDelta > 0.3
            ? '↑ worsened'
            : 'stable'} (${rDelta.toStringAsFixed(1)})',
      );
      buf.writeln(
        '  Texture trend: ${tDelta < 0
            ? '↓ improved'
            : tDelta > 0.3
            ? '↑ worsened'
            : 'stable'} (${tDelta.toStringAsFixed(1)})',
      );
      buf.writeln(
        '  Elasticity trend: ${eDelta > 0
            ? '↑ improved'
            : eDelta < -0.3
            ? '↓ declined'
            : 'stable'} (${eDelta.toStringAsFixed(1)})',
      );
      buf.writeln('  Total scans tracked: ${sorted.length}');
    }

    return buf.toString();
  }

  static String _levelSuffix(MetricClinicalLevel level) {
    switch (level) {
      case MetricClinicalLevel.optimal:
        return ' [optimal]';
      case MetricClinicalLevel.mild:
        return ' [mild]';
      case MetricClinicalLevel.moderate:
        return ' [moderate — monitor]';
      case MetricClinicalLevel.elevated:
        return ' [elevated — address]';
    }
  }
}
