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
    final String? backendTrendStatus = canonicalKey == null
        ? null
        : trendStatus?[canonicalKey];
    final String? backendTrendLockReason = canonicalKey == null
        ? null
        : trendLockReason?[canonicalKey];
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

  // ---------------------------------------------------------------------------
  // Coach Context Builder (for AI Recovery Coach enrichment)
  // ---------------------------------------------------------------------------

  static List<Map<String, dynamic>> buildAiScanContext({
    required List<ScanHistoryEntry> scans,
  }) {
    final sorted = List<ScanHistoryEntry>.from(scans)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return [for (final scan in sorted) _scanContextEntry(scan)];
  }

  static Map<String, dynamic> _scanContextEntry(ScanHistoryEntry scan) {
    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return const <String, dynamic>{};
    }

    final payload = scan.rawPayload ?? const <String, dynamic>{};
    final nestedLuxe = asMap(payload['luxePayload']);
    final matrix = asMap(payload['metric_matrix']).isNotEmpty
        ? asMap(payload['metric_matrix'])
        : asMap(asMap(payload['metrics'])['metric_matrix']);
    final rawLocks = asMap(nestedLuxe['trend_lock_reasons']).isNotEmpty
        ? asMap(nestedLuxe['trend_lock_reasons'])
        : asMap(payload['trend_lock_reasons']);
    final lockReasons =
        rawLocks.values
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final hasPhoto = (scan.imagePath ?? '').trim().isNotEmpty;
    final status = matrix.isNotEmpty ? 'matched' : 'photo_only';

    return {
      'date': scan.timestamp.toIso8601String(),
      if ((scan.procedureId ?? '').trim().isNotEmpty)
        'procedure_id': scan.procedureId!.trim(),
      'status': status,
      if (status == 'photo_only')
        'reason': hasPhoto
            ? 'no recorded metric match'
            : 'no photo or recorded metric match',
      if (lockReasons.isNotEmpty) 'lock_reasons': lockReasons,
    };
  }

  /// Builds a rich metric context string for injecting into the AI coach prompt.
  static String buildCoachMetricContext({
    required List<ScanHistoryEntry> scans,
    String? procedureType,
  }) {
    final entries = buildAiScanContext(scans: scans);
    if (entries.isEmpty) return 'No scan context available yet.';
    return 'Scan context: ${entries.join(' | ')}';
  }
}
