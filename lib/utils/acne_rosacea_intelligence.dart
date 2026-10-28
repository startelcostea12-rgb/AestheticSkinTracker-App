// lib/utils/acne_rosacea_intelligence.dart
//
// Deterministic, on-device intelligence engine for the dedicated Acne &
// Rosacea Tracker. Consumes the user's AcneRosaceaLog history (severity +
// notes + photos), their active TrackedProduct stack, and profile concerns
// to produce a structured insight + healing-plan report.
//
// All logic is rule-based and audit-able — no network calls, no opaque
// machine learning. Tuned from dermatology consensus guidance (AAD, BAD,
// Global Rosacea Consensus 2017).

import '../models/acne_rosacea_log.dart';
import '../models/product_tracker.dart';
import 'natural_skincare.dart';

// ─── PUBLIC TYPES ───────────────────────────────────────────────────────────

enum TrendDirection { improving, worsening, steady, insufficient }

enum SeverityBand { clear, mild, moderate, marked, severe }

enum AcneRosaceaSubtype {
  acne,
  cystic,
  hormonal,
  rosacea,
  flushing,
  visibleVessels,
  sensitivity,
}

class MetricTrend {
  final String metricKey;
  final String metricLabel;
  final TrendDirection direction7d;
  final TrendDirection direction30d;
  final double avgLast7d;
  final double avgPrior7d;
  final double avgLast30d;
  final int sampleCount;
  final double deltaPct7d;
  final String summary;

  const MetricTrend({
    required this.metricKey,
    required this.metricLabel,
    required this.direction7d,
    required this.direction30d,
    required this.avgLast7d,
    required this.avgPrior7d,
    required this.avgLast30d,
    required this.sampleCount,
    required this.deltaPct7d,
    required this.summary,
  });
}

class TriggerHypothesis {
  final String title;
  final String description;
  final double confidence; // 0–1
  final IconCue iconCue;

  const TriggerHypothesis({
    required this.title,
    required this.description,
    required this.confidence,
    required this.iconCue,
  });
}

enum IconCue { calendar, product, stress, diet, weather, pattern }

class ProductRecommendation {
  final String name;
  final String activeIngredient;
  final String rationale;
  final RecommendationPriority priority;

  const ProductRecommendation({
    required this.name,
    required this.activeIngredient,
    required this.rationale,
    required this.priority,
  });
}

enum RecommendationPriority { foundational, supporting, optional }

class CompatibilityWarning {
  final String product;
  final String concern;
  final String reasoning;
  final WarningSeverity severity;

  const CompatibilityWarning({
    required this.product,
    required this.concern,
    required this.reasoning,
    required this.severity,
  });
}

enum WarningSeverity { caution, avoid }

class HealingStage {
  final String weekRange;
  final String title;
  final String description;
  final bool isCurrent;

  const HealingStage({
    required this.weekRange,
    required this.title,
    required this.description,
    this.isCurrent = false,
  });
}

class SubtypePlan {
  final AcneRosaceaSubtype subtype;
  final String subtypeLabel;
  final String overview;
  final List<HealingStage> stages;
  final List<ProductRecommendation> recommendations;

  /// Evidence-based natural / clean alternatives for this subtype —
  /// surfaced as a dedicated "Natural Alternatives" subsection.
  final List<ProductRecommendation> naturalAlternatives;

  const SubtypePlan({
    required this.subtype,
    required this.subtypeLabel,
    required this.overview,
    required this.stages,
    required this.recommendations,
    this.naturalAlternatives = const [],
  });
}

class AcneRosaceaInsightReport {
  final String headline;
  final String subheadline;
  final double overallSeverityIndex; // 0–10 weighted across active metrics
  final SeverityBand overallBand;
  final List<MetricTrend> trends;
  final List<TriggerHypothesis> triggers;
  final List<ProductRecommendation> recommendations;
  final List<CompatibilityWarning> warnings;
  final List<SubtypePlan> subtypePlans;
  final String healingPlanSummary;
  final List<String> dailyActions;
  final List<String> weeklyActions;
  final List<AcneRosaceaSubtype> dominantSubtypes;
  final int photoCount;
  final int totalEntries;
  final bool hasEnoughData;
  final String nextStep;

  const AcneRosaceaInsightReport({
    required this.headline,
    required this.subheadline,
    required this.overallSeverityIndex,
    required this.overallBand,
    required this.trends,
    required this.triggers,
    required this.recommendations,
    required this.warnings,
    required this.subtypePlans,
    required this.healingPlanSummary,
    required this.dailyActions,
    required this.weeklyActions,
    required this.dominantSubtypes,
    required this.photoCount,
    required this.totalEntries,
    required this.hasEnoughData,
    required this.nextStep,
  });
}

// ─── ENGINE ─────────────────────────────────────────────────────────────────

class AcneRosaceaIntelligence {
  AcneRosaceaIntelligence._();

  /// Produce a full insight report from the user's logs + active product
  /// stack + profile concerns. All inputs may be empty — the report
  /// degrades gracefully (`hasEnoughData = false`) when there is no signal.
  static AcneRosaceaInsightReport analyze({
    required Map<String, List<AcneRosaceaLog>> logs,
    List<TrackedProduct> products = const [],
    List<String> profileConcerns = const [],
  }) {
    final now = DateTime.now();
    final allEntries = <AcneRosaceaLog>[];
    for (final list in logs.values) {
      allEntries.addAll(list);
    }
    allEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final photoCount = allEntries.where((e) => e.hasPhoto).length;
    final totalEntries = allEntries.length;
    // AI Healing Plan + Insights unlock once the user has at least two
    // quality entries — enough signal to surface trends, subtype dominance,
    // and a personalized week-by-week protocol without overpromising on
    // single-data-point noise.
    final hasEnoughData = totalEntries >= 2;

    // 1. Per-metric trend computation.
    final trends = <MetricTrend>[];
    for (final entry in _metricCatalog.entries) {
      final list = logs[entry.key] ?? const <AcneRosaceaLog>[];
      if (list.isEmpty) continue;
      final t = _computeTrend(entry.key, entry.value, list, now);
      if (t != null) trends.add(t);
    }

    // 2. Dominant subtype detection.
    final dominantSubtypes = _detectDominantSubtypes(logs, profileConcerns);

    // 3. Severity index — weighted average of latest values across logged
    //    metrics, capped at 10.
    final overallIndex = _overallSeverityIndex(logs);
    final overallBand = _bandForSeverity(overallIndex);

    // 4. Trigger hypotheses.
    final triggers = _identifyTriggers(
      logs: logs,
      products: products,
      now: now,
    );

    // 5. Recommendations + warnings driven by dominant subtype + product
    //    stack interactions.
    final recommendations = <ProductRecommendation>[];
    final warnings = <CompatibilityWarning>[];
    for (final subtype in dominantSubtypes) {
      recommendations.addAll(_subtypeRecommendations(subtype));
    }
    // Deduplicate by name.
    final seen = <String>{};
    final dedupedRecs = <ProductRecommendation>[];
    for (final r in recommendations) {
      if (seen.add(r.name.toLowerCase())) dedupedRecs.add(r);
    }
    warnings.addAll(
      _evaluateCompatibility(
        products: products,
        dominantSubtypes: dominantSubtypes,
        logs: logs,
      ),
    );

    // 6. Per-subtype healing plan with current-stage detection.
    final subtypePlans = <SubtypePlan>[];
    for (final subtype in dominantSubtypes) {
      subtypePlans.add(_planForSubtype(subtype, logs));
    }

    // 7. Headlines + summary.
    final headlineParts = _composeHeadline(
      band: overallBand,
      trends: trends,
      hasEnoughData: hasEnoughData,
      dominantSubtypes: dominantSubtypes,
    );

    final healingPlanSummary = _composeHealingSummary(
      dominantSubtypes: dominantSubtypes,
      band: overallBand,
      warnings: warnings,
      recommendationCount: dedupedRecs.length,
    );

    final dailyActions = _composeDailyActions(dominantSubtypes, overallBand);
    final weeklyActions = _composeWeeklyActions(
      dominantSubtypes,
      overallBand,
      photoCount,
    );

    final nextStep = _composeNextStep(
      hasEnoughData: hasEnoughData,
      photoCount: photoCount,
      trends: trends,
      dominantSubtypes: dominantSubtypes,
    );

    return AcneRosaceaInsightReport(
      headline: headlineParts.$1,
      subheadline: headlineParts.$2,
      overallSeverityIndex: overallIndex,
      overallBand: overallBand,
      trends: trends,
      triggers: triggers,
      recommendations: dedupedRecs,
      warnings: warnings,
      subtypePlans: subtypePlans,
      healingPlanSummary: healingPlanSummary,
      dailyActions: dailyActions,
      weeklyActions: weeklyActions,
      dominantSubtypes: dominantSubtypes,
      photoCount: photoCount,
      totalEntries: totalEntries,
      hasEnoughData: hasEnoughData,
      nextStep: nextStep,
    );
  }
}

// ─── METRIC CATALOG ─────────────────────────────────────────────────────────

const Map<String, String> _metricCatalog = {
  'acneSeverity': 'Acne Severity',
  'cysticAcneSeverity': 'Cystic Acne Severity',
  'hormonalAcneSeverity': 'Hormonal Acne Severity',
  'rosaceaSeverity': 'Rosacea Severity',
  'rosaceaFlushing': 'Rosacea Flushing',
  'visibleBloodVessels': 'Visible Blood Vessels',
  'skinSensitivity': 'Skin Sensitivity',
};

const Map<String, AcneRosaceaSubtype> _metricToSubtype = {
  'acneSeverity': AcneRosaceaSubtype.acne,
  'cysticAcneSeverity': AcneRosaceaSubtype.cystic,
  'hormonalAcneSeverity': AcneRosaceaSubtype.hormonal,
  'rosaceaSeverity': AcneRosaceaSubtype.rosacea,
  'rosaceaFlushing': AcneRosaceaSubtype.flushing,
  'visibleBloodVessels': AcneRosaceaSubtype.visibleVessels,
  'skinSensitivity': AcneRosaceaSubtype.sensitivity,
};

// ─── TREND COMPUTATION ──────────────────────────────────────────────────────

MetricTrend? _computeTrend(
  String key,
  String label,
  List<AcneRosaceaLog> sorted,
  DateTime now,
) {
  if (sorted.isEmpty) return null;
  final last7 = sorted
      .where((e) => now.difference(e.timestamp).inDays <= 7)
      .toList();
  final prior7 = sorted.where((e) {
    final d = now.difference(e.timestamp).inDays;
    return d > 7 && d <= 14;
  }).toList();
  final last30 = sorted
      .where((e) => now.difference(e.timestamp).inDays <= 30)
      .toList();
  final prior30 = sorted.where((e) {
    final d = now.difference(e.timestamp).inDays;
    return d > 30 && d <= 60;
  }).toList();

  double avg(List<AcneRosaceaLog> l) =>
      l.isEmpty ? 0 : l.map((e) => e.value).reduce((a, b) => a + b) / l.length;

  final a7 = avg(last7);
  final p7 = avg(prior7);
  final a30 = avg(last30);
  final p30 = avg(prior30);

  TrendDirection dir(
    double current,
    double prior,
    int currCount,
    int priorCount,
  ) {
    if (currCount < 1 || priorCount < 1) return TrendDirection.insufficient;
    final delta = current - prior;
    if (delta.abs() < 0.6) return TrendDirection.steady;
    // Acne/Rosacea metrics are lower-is-better — decreasing is improving.
    return delta < 0 ? TrendDirection.improving : TrendDirection.worsening;
  }

  final dir7 = dir(a7, p7, last7.length, prior7.length);
  final dir30 = dir(a30, p30, last30.length, prior30.length);

  final deltaPct = (p7 == 0) ? 0.0 : ((a7 - p7) / p7) * 100.0;

  String summary;
  if (dir7 == TrendDirection.improving) {
    summary =
        '$label improving ${deltaPct.abs().toStringAsFixed(0)}% '
        'vs last week';
  } else if (dir7 == TrendDirection.worsening) {
    summary =
        '$label worsening ${deltaPct.abs().toStringAsFixed(0)}% '
        'vs last week';
  } else if (dir7 == TrendDirection.steady) {
    summary = '$label holding steady week-over-week';
  } else if (dir30 == TrendDirection.improving) {
    summary = '$label trending down over the past month';
  } else if (dir30 == TrendDirection.worsening) {
    summary = '$label trending up over the past month';
  } else {
    summary = '$label — need a few more entries for a reliable trend';
  }

  return MetricTrend(
    metricKey: key,
    metricLabel: label,
    direction7d: dir7,
    direction30d: dir30,
    avgLast7d: a7,
    avgPrior7d: p7,
    avgLast30d: a30,
    sampleCount: sorted.length,
    deltaPct7d: deltaPct,
    summary: summary,
  );
}

// ─── DOMINANT SUBTYPE ───────────────────────────────────────────────────────

List<AcneRosaceaSubtype> _detectDominantSubtypes(
  Map<String, List<AcneRosaceaLog>> logs,
  List<String> profileConcerns,
) {
  // Score per metric = recent (≤ 30d) average severity × density weight.
  // Density is anchored at 0.5 so even a single recent entry meaningfully
  // scores its subtype (otherwise the AI plan never unlocks for new users).
  final now = DateTime.now();
  final scores = <AcneRosaceaSubtype, double>{};
  final fallback = <AcneRosaceaSubtype, double>{};
  logs.forEach((key, list) {
    if (list.isEmpty) return;
    final subtype = _metricToSubtype[key];
    if (subtype == null) return;
    final recent = list
        .where((e) => now.difference(e.timestamp).inDays <= 30)
        .toList();
    final avgAll =
        list.map((e) => e.value).reduce((a, b) => a + b) / list.length;
    fallback[subtype] = (fallback[subtype] ?? 0) + avgAll;
    if (recent.isEmpty) return;
    final avg =
        recent.map((e) => e.value).reduce((a, b) => a + b) / recent.length;
    // Floor density at 0.5 so a single fresh entry registers; cap at 1.0.
    final density = (0.5 + (recent.length / 30.0)).clamp(0.5, 1.0);
    scores[subtype] = (scores[subtype] ?? 0) + avg * density;
  });

  // Always include subtypes the user has flagged in profile concerns.
  final concernLower = profileConcerns.map((c) => c.toLowerCase()).toList();
  if (concernLower.any((c) => c.contains('cystic'))) {
    scores[AcneRosaceaSubtype.cystic] =
        (scores[AcneRosaceaSubtype.cystic] ?? 0) + 1.5;
  }
  if (concernLower.any((c) => c.contains('hormonal'))) {
    scores[AcneRosaceaSubtype.hormonal] =
        (scores[AcneRosaceaSubtype.hormonal] ?? 0) + 1.5;
  }
  if (concernLower.any((c) => c.contains('rosacea'))) {
    scores[AcneRosaceaSubtype.rosacea] =
        (scores[AcneRosaceaSubtype.rosacea] ?? 0) + 1.5;
  }
  if (concernLower.any((c) => c.contains('acne')) &&
      !concernLower.any(
        (c) => c.contains('cystic') || c.contains('hormonal'),
      )) {
    scores[AcneRosaceaSubtype.acne] =
        (scores[AcneRosaceaSubtype.acne] ?? 0) + 1.5;
  }
  if (concernLower.any((c) => c.contains('sensitiv'))) {
    scores[AcneRosaceaSubtype.sensitivity] =
        (scores[AcneRosaceaSubtype.sensitivity] ?? 0) + 1.0;
  }

  // Threshold of 0.5 — a single mild reading is enough to unlock its plan.
  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final picked = sorted
      .where((e) => e.value >= 0.5)
      .take(3)
      .map((e) => e.key)
      .toList();
  if (picked.isNotEmpty) return picked;

  // Safety net: if user has logged ANYTHING but scoring missed (e.g. all
  // entries older than 30 days), surface the highest-historical subtype so
  // the AI plan still appears.
  if (fallback.isNotEmpty) {
    final f = fallback.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [f.first.key];
  }
  return const [];
}

// ─── SEVERITY INDEX ─────────────────────────────────────────────────────────

double _overallSeverityIndex(Map<String, List<AcneRosaceaLog>> logs) {
  final now = DateTime.now();
  final latestValues = <double>[];
  logs.forEach((key, list) {
    if (list.isEmpty) return;
    // Use most-recent entry from within last 21 days.
    final recent = list
        .where((e) => now.difference(e.timestamp).inDays <= 21)
        .toList();
    if (recent.isEmpty) return;
    latestValues.add(recent.first.value.toDouble());
  });
  if (latestValues.isEmpty) return 0;
  // Weighted: take max + average to reflect both worst-symptom and overall.
  final maxV = latestValues.reduce((a, b) => a > b ? a : b);
  final avg = latestValues.reduce((a, b) => a + b) / latestValues.length;
  return ((maxV * 0.55) + (avg * 0.45)).clamp(0, 10);
}

SeverityBand _bandForSeverity(double v) {
  if (v <= 2.0) return SeverityBand.clear;
  if (v <= 4.5) return SeverityBand.mild;
  if (v <= 6.5) return SeverityBand.moderate;
  if (v <= 8.0) return SeverityBand.marked;
  return SeverityBand.severe;
}

// ─── TRIGGER HYPOTHESES ─────────────────────────────────────────────────────

const _stressKeywords = [
  'stress',
  'tired',
  'exam',
  'deadline',
  'anxious',
  'busy',
  'travel',
];
const _dietKeywords = [
  'dairy',
  'milk',
  'cheese',
  'sugar',
  'chocolate',
  'wine',
  'spicy',
];
const _weatherKeywords = ['heat', 'humid', 'cold', 'wind', 'sun'];

List<TriggerHypothesis> _identifyTriggers({
  required Map<String, List<AcneRosaceaLog>> logs,
  required List<TrackedProduct> products,
  required DateTime now,
}) {
  final out = <TriggerHypothesis>[];

  // 1. Hormonal cycle pattern in hormonalAcneSeverity logs.
  final hormonal = logs['hormonalAcneSeverity'] ?? const <AcneRosaceaLog>[];
  if (hormonal.length >= 3) {
    final spikes = hormonal.where((e) => e.value >= 5).toList();
    if (spikes.length >= 2) {
      final gaps = <int>[];
      for (int i = 0; i < spikes.length - 1; i++) {
        gaps.add(
          spikes[i].timestamp.difference(spikes[i + 1].timestamp).inDays.abs(),
        );
      }
      final avgGap = gaps.isEmpty
          ? 0
          : gaps.reduce((a, b) => a + b) ~/ gaps.length;
      if (avgGap >= 21 && avgGap <= 35) {
        out.add(
          TriggerHypothesis(
            title: 'Cyclical hormonal pattern',
            description:
                'Hormonal flares appear roughly every $avgGap days — '
                'consistent with the luteal-phase androgen surge. Pre-emptive '
                'spironolactone or BHA timing may help.',
            confidence: 0.78,
            iconCue: IconCue.calendar,
          ),
        );
      }
    }
  }

  // 2. Stress / diet / weather keyword scan across recent notes (≤ 21d).
  final recentNotes = <String>[];
  logs.forEach((_, list) {
    for (final e in list) {
      if (now.difference(e.timestamp).inDays <= 21 && e.note.isNotEmpty) {
        recentNotes.add(e.note.toLowerCase());
      }
    }
  });
  final stressHits = recentNotes
      .where((n) => _stressKeywords.any(n.contains))
      .length;
  if (stressHits >= 2) {
    out.add(
      TriggerHypothesis(
        title: 'Stress correlation',
        description:
            'Stress-related language appears in $stressHits recent '
            'entries. Cortisol elevates sebum and inflammatory cytokines — '
            'consider sleep + magnesium + mindfulness adjuncts.',
        confidence: 0.62,
        iconCue: IconCue.stress,
      ),
    );
  }
  final dietHits = recentNotes
      .where((n) => _dietKeywords.any(n.contains))
      .length;
  if (dietHits >= 2) {
    out.add(
      TriggerHypothesis(
        title: 'Dietary trigger possible',
        description:
            'Mentions of dairy / high-glycemic / spicy / alcohol '
            'cluster with $dietHits flare entries. Trial a 4-week reduction '
            'and re-log to confirm.',
        confidence: 0.55,
        iconCue: IconCue.diet,
      ),
    );
  }
  final weatherHits = recentNotes
      .where((n) => _weatherKeywords.any(n.contains))
      .length;
  if (weatherHits >= 2) {
    out.add(
      const TriggerHypothesis(
        title: 'Environmental trigger',
        description:
            'Heat / wind / sun mentions correlate with flare entries. '
            'Mineral SPF + barrier-first routine recommended.',
        confidence: 0.50,
        iconCue: IconCue.weather,
      ),
    );
  }

  // 3. Recent product addition coincides with worsening.
  final lastWeekSpike = _hasRecentWorsening(logs, now);
  if (lastWeekSpike && products.isNotEmpty) {
    out.add(
      const TriggerHypothesis(
        title: 'Product-routine link',
        description:
            'Severity climbed in the past 7 days. Cross-check active '
            'products for new additions or strength changes — purge vs. '
            'genuine irritation diverge after 6 weeks.',
        confidence: 0.58,
        iconCue: IconCue.product,
      ),
    );
  }

  return out;
}

bool _hasRecentWorsening(Map<String, List<AcneRosaceaLog>> logs, DateTime now) {
  for (final list in logs.values) {
    final last7 = list
        .where((e) => now.difference(e.timestamp).inDays <= 7)
        .toList();
    final prior7 = list.where((e) {
      final d = now.difference(e.timestamp).inDays;
      return d > 7 && d <= 14;
    }).toList();
    if (last7.isEmpty || prior7.isEmpty) continue;
    final a = last7.map((e) => e.value).reduce((a, b) => a + b) / last7.length;
    final p =
        prior7.map((e) => e.value).reduce((a, b) => a + b) / prior7.length;
    if (a - p >= 1.0) return true;
  }
  return false;
}

// ─── RECOMMENDATIONS ────────────────────────────────────────────────────────

List<ProductRecommendation> _subtypeRecommendations(AcneRosaceaSubtype s) {
  switch (s) {
    case AcneRosaceaSubtype.acne:
      return const [
        ProductRecommendation(
          name: 'Adapalene 0.1% gel',
          activeIngredient: 'Adapalene',
          rationale:
              'Third-gen retinoid — comedolytic, low irritation. '
              'OTC and supported by AAD as first-line for comedonal acne.',
          priority: RecommendationPriority.foundational,
        ),
        ProductRecommendation(
          name: 'Salicylic acid 2% (BHA)',
          activeIngredient: 'Salicylic acid',
          rationale:
              'Lipid-soluble — clears the follicular plug. '
              'Use 3-4x/week or as a leave-on toner.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Niacinamide 4-5% serum',
          activeIngredient: 'Niacinamide',
          rationale:
              'Reduces sebum oxidation + inflammatory papules without '
              'compromising the barrier.',
          priority: RecommendationPriority.supporting,
        ),
      ];
    case AcneRosaceaSubtype.cystic:
      return const [
        ProductRecommendation(
          name: 'Azelaic acid 15-20%',
          activeIngredient: 'Azelaic acid',
          rationale:
              'Anti-inflammatory + anti-bacterial — safe with cystic '
              'lesions, supports post-inflammatory pigment recovery.',
          priority: RecommendationPriority.foundational,
        ),
        ProductRecommendation(
          name: 'Hydrocolloid pimple patches',
          activeIngredient: 'Hydrocolloid',
          rationale:
              'Reduce mechanical trauma to deep lesions. Never extract '
              'cystic acne manually.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Oral isotretinoin (consult)',
          activeIngredient: 'Isotretinoin',
          rationale:
              'For nodulocystic acne unresponsive to topicals — '
              'requires board-certified dermatologist + iPLEDGE program.',
          priority: RecommendationPriority.optional,
        ),
      ];
    case AcneRosaceaSubtype.hormonal:
      return const [
        ProductRecommendation(
          name: 'Spironolactone 50-100mg (consult)',
          activeIngredient: 'Spironolactone',
          rationale:
              'Androgen-receptor antagonist — gold standard for adult '
              'female hormonal acne. Prescription only.',
          priority: RecommendationPriority.foundational,
        ),
        ProductRecommendation(
          name: 'Tretinoin 0.025-0.05%',
          activeIngredient: 'Tretinoin',
          rationale:
              'Normalizes follicular turnover; introduce slowly '
              '(2x/week) and buffer with moisturizer.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Azelaic acid 15%',
          activeIngredient: 'Azelaic acid',
          rationale:
              'Useful adjunct — calms inflammatory papules along the '
              'jawline and chin without dryness.',
          priority: RecommendationPriority.supporting,
        ),
      ];
    case AcneRosaceaSubtype.rosacea:
      return const [
        ProductRecommendation(
          name: 'Azelaic acid 15% gel',
          activeIngredient: 'Azelaic acid',
          rationale:
              'A common over-the-counter and prescription option for '
              'persistent redness and bumps — calms inflammation and evens '
              'tone. Ask a clinician whether it suits you.',
          priority: RecommendationPriority.foundational,
        ),
        ProductRecommendation(
          name: 'Ivermectin 1% cream',
          activeIngredient: 'Ivermectin',
          rationale:
              'Targets Demodex mites + inflammation — effective for '
              'persistent papules. Prescription.',
          priority: RecommendationPriority.foundational,
        ),
        ProductRecommendation(
          name: 'Metronidazole 0.75% gel',
          activeIngredient: 'Metronidazole',
          rationale:
              'Classic anti-inflammatory for rosacea — well-tolerated '
              'long-term. Prescription.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Mineral SPF 30+ (zinc oxide)',
          activeIngredient: 'Zinc oxide',
          rationale:
              'UV is a top rosacea trigger. Mineral filters tolerate '
              'inflamed skin better than chemical UV filters.',
          priority: RecommendationPriority.foundational,
        ),
      ];
    case AcneRosaceaSubtype.flushing:
      return const [
        ProductRecommendation(
          name: 'Brimonidine 0.33% gel',
          activeIngredient: 'Brimonidine',
          rationale:
              'α-adrenergic agonist — vasoconstricts cutaneous '
              'vessels; reduces flushing for 8-12 hours. Prescription.',
          priority: RecommendationPriority.foundational,
        ),
        ProductRecommendation(
          name: 'Oxymetazoline 1% cream',
          activeIngredient: 'Oxymetazoline',
          rationale:
              'Alternative α-agonist — comparable efficacy with a '
              'longer onset to avoid rebound erythema.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Low-dose β-blocker (consult)',
          activeIngredient: 'Propranolol / Carvedilol',
          rationale:
              'Off-label oral option for severe blushing tied to '
              'autonomic triggers. Cardiology-aware prescribing.',
          priority: RecommendationPriority.optional,
        ),
      ];
    case AcneRosaceaSubtype.visibleVessels:
      return const [
        ProductRecommendation(
          name: 'KTP / Nd:YAG vascular laser (consult)',
          activeIngredient: 'Vascular laser',
          rationale:
              'Definitive treatment for telangiectasia. 1-3 sessions '
              'typically resolve visible vessels.',
          priority: RecommendationPriority.foundational,
        ),
        ProductRecommendation(
          name: 'IPL (intense pulsed light)',
          activeIngredient: 'IPL',
          rationale:
              'Reduces background erythema + smaller vessels. Plan '
              '3-5 sessions, 4 weeks apart.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Mineral SPF 30+ daily',
          activeIngredient: 'Zinc oxide',
          rationale:
              'UV worsens vessel dilation — SPF preserves laser '
              'results long-term.',
          priority: RecommendationPriority.foundational,
        ),
      ];
    case AcneRosaceaSubtype.sensitivity:
      return const [
        ProductRecommendation(
          name: 'Ceramide-rich moisturizer',
          activeIngredient: 'Ceramides + cholesterol + fatty acids',
          rationale:
              'Restores the 3:1:1 lipid ratio of healthy stratum '
              'corneum — top recovery for compromised barrier.',
          priority: RecommendationPriority.foundational,
        ),
        ProductRecommendation(
          name: 'Centella asiatica serum',
          activeIngredient: 'Madecassoside / asiaticoside',
          rationale:
              'Wound-healing botanicals — soothe TEWL-elevated skin '
              'without active load.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Panthenol 5% lotion',
          activeIngredient: 'Panthenol (provitamin B5)',
          rationale:
              'Humectant + soothing; great morning step during a '
              'sensitivity flare.',
          priority: RecommendationPriority.supporting,
        ),
      ];
  }
}

// ─── COMPATIBILITY WARNINGS ─────────────────────────────────────────────────

const _retinoidKeywords = [
  'retinol',
  'retinal',
  'retinoid',
  'tretinoin',
  'adapalene',
  'tazarotene',
];
const _strongAcidKeywords = ['glycolic', 'lactic acid', 'mandelic', 'tca'];
const _bpoKeywords = ['benzoyl peroxide', 'bpo'];
const _fragranceKeywords = [
  'parfum',
  'fragrance',
  'essential oil',
  'limonene',
  'linalool',
  'citronellol',
];
const _alcoholKeywords = ['alcohol denat', 'denatured alcohol', 'sd alcohol'];
const _physicalScrubKeywords = [
  'scrub',
  'microbead',
  'walnut shell',
  'apricot',
];

List<CompatibilityWarning> _evaluateCompatibility({
  required List<TrackedProduct> products,
  required List<AcneRosaceaSubtype> dominantSubtypes,
  required Map<String, List<AcneRosaceaLog>> logs,
}) {
  if (products.isEmpty || dominantSubtypes.isEmpty) return const [];
  final hasCystic = dominantSubtypes.contains(AcneRosaceaSubtype.cystic);
  final hasRosacea =
      dominantSubtypes.contains(AcneRosaceaSubtype.rosacea) ||
      dominantSubtypes.contains(AcneRosaceaSubtype.flushing) ||
      dominantSubtypes.contains(AcneRosaceaSubtype.visibleVessels);
  final hasSensitivity = dominantSubtypes.contains(
    AcneRosaceaSubtype.sensitivity,
  );

  bool hasActiveSeverity(String key, double threshold) {
    final list = logs[key] ?? const [];
    if (list.isEmpty) return false;
    return list.first.value >= threshold;
  }

  final cysticActive = hasCystic && hasActiveSeverity('cysticAcneSeverity', 4);
  final rosaceaActive =
      hasRosacea &&
      (hasActiveSeverity('rosaceaSeverity', 4) ||
          hasActiveSeverity('rosaceaFlushing', 4));
  final sensitivityActive =
      hasSensitivity && hasActiveSeverity('skinSensitivity', 4);

  final out = <CompatibilityWarning>[];
  for (final p in products) {
    final hay = '${p.name} ${p.brand} ${p.keyIngredients} ${p.notes}'
        .toLowerCase();
    final isRetinoid = _retinoidKeywords.any(hay.contains);
    final isStrongAcid = _strongAcidKeywords.any(hay.contains);
    final isBPO = _bpoKeywords.any(hay.contains);
    final hasFragrance = _fragranceKeywords.any(hay.contains);
    final hasDrydAlcohol = _alcoholKeywords.any(hay.contains);
    final isScrub = _physicalScrubKeywords.any(hay.contains);

    if (cysticActive && isRetinoid) {
      out.add(
        CompatibilityWarning(
          product: p.name,
          concern: 'Active cystic lesions',
          reasoning:
              'Retinoids increase epidermal turnover and inflammatory '
              'cytokines for the first 6-8 weeks — may aggravate active cysts. '
              'Consider azelaic acid 15-20% in parallel and re-introduce the '
              'retinoid once cysts settle.',
          severity: WarningSeverity.caution,
        ),
      );
    }
    if (rosaceaActive && isRetinoid) {
      out.add(
        CompatibilityWarning(
          product: p.name,
          concern: 'Active rosacea',
          reasoning:
              'Retinoids commonly provoke rosacea papules and barrier '
              'flushing in the first 8 weeks. Pause until rosacea is calm or '
              'switch to bakuchiol / azelaic acid.',
          severity: WarningSeverity.avoid,
        ),
      );
    }
    if (rosaceaActive && (isBPO || isStrongAcid)) {
      out.add(
        CompatibilityWarning(
          product: p.name,
          concern: 'Active rosacea',
          reasoning:
              'Benzoyl peroxide and strong AHAs reliably flare rosacea. '
              'Substitute with azelaic acid or ivermectin while rosacea is '
              'symptomatic.',
          severity: WarningSeverity.avoid,
        ),
      );
    }
    if ((rosaceaActive || sensitivityActive) &&
        (hasFragrance || hasDrydAlcohol)) {
      out.add(
        CompatibilityWarning(
          product: p.name,
          concern: rosaceaActive ? 'Rosacea barrier' : 'Sensitive skin barrier',
          reasoning:
              'Fragrance and denatured alcohol disrupt the lipid '
              'barrier and trigger neurogenic flushing. Choose fragrance-free '
              'formulations during flares.',
          severity: WarningSeverity.caution,
        ),
      );
    }
    if ((cysticActive || sensitivityActive) && isScrub) {
      out.add(
        CompatibilityWarning(
          product: p.name,
          concern: cysticActive ? 'Active cystic acne' : 'Compromised barrier',
          reasoning:
              'Physical scrubs rupture inflamed follicles and worsen '
              'cystic and sensitive skin. Substitute with enzyme exfoliation '
              '1-2x/week if needed.',
          severity: WarningSeverity.avoid,
        ),
      );
    }
  }

  // Natural / clean ingredient cautions — surfaces when essential oils,
  // tea tree, citrus oils, or fragrance overlap with rosacea, sensitivity,
  // or recent flare-ups.
  final rosaceaProne =
      dominantSubtypes.contains(AcneRosaceaSubtype.rosacea) ||
      dominantSubtypes.contains(AcneRosaceaSubtype.flushing) ||
      dominantSubtypes.contains(AcneRosaceaSubtype.visibleVessels);
  final sensitiveSkin = dominantSubtypes.contains(
    AcneRosaceaSubtype.sensitivity,
  );
  final stackTexts = products
      .map((p) => '${p.name} ${p.brand} ${p.keyIngredients} ${p.notes}')
      .toList();
  final naturalWarnings = NaturalSkincareAdvisor.compatibilityWarnings(
    stackTexts: stackTexts,
    rosaceaProne: rosaceaProne,
    sensitiveSkin: sensitiveSkin,
  );
  for (final w in naturalWarnings) {
    out.add(
      CompatibilityWarning(
        product: 'Routine',
        concern: 'Natural ingredient sensitivity',
        reasoning: w,
        severity: WarningSeverity.caution,
      ),
    );
  }
  return out;
}

// ─── HEALING PLAN ───────────────────────────────────────────────────────────

SubtypePlan _planForSubtype(
  AcneRosaceaSubtype s,
  Map<String, List<AcneRosaceaLog>> logs,
) {
  switch (s) {
    case AcneRosaceaSubtype.acne:
      return SubtypePlan(
        subtype: s,
        subtypeLabel: 'Inflammatory & Comedonal Acne',
        overview:
            'Treatment goal: normalize follicular turnover and reduce '
            'P. acnes load. Expect a true response by week 8-12 — patience '
            'and consistency outperform stacking strong actives.',
        stages: _acneStages(logs),
        recommendations: _subtypeRecommendations(s),
        naturalAlternatives: _subtypeNaturalAlternatives(s),
      );
    case AcneRosaceaSubtype.cystic:
      return SubtypePlan(
        subtype: s,
        subtypeLabel: 'Cystic & Nodular Acne',
        overview:
            'Cysts live deep in the dermis and scar easily. Topicals alone '
            'rarely suffice — pair anti-inflammatory topicals with a '
            'dermatology consult for oral options.',
        stages: _cysticStages(logs),
        recommendations: _subtypeRecommendations(s),
        naturalAlternatives: _subtypeNaturalAlternatives(s),
      );
    case AcneRosaceaSubtype.hormonal:
      return SubtypePlan(
        subtype: s,
        subtypeLabel: 'Hormonal Acne',
        overview:
            'Flares cluster on the jawline / chin in the luteal phase. The '
            'most reliable response comes from systemic anti-androgen '
            'therapy + nightly retinoid.',
        stages: _hormonalStages(logs),
        recommendations: _subtypeRecommendations(s),
        naturalAlternatives: _subtypeNaturalAlternatives(s),
      );
    case AcneRosaceaSubtype.rosacea:
      return SubtypePlan(
        subtype: s,
        subtypeLabel: 'Persistent redness & bumps',
        overview:
            'Barrier-first care + a single targeted active. Strong actives '
            'flare rosacea — slow, calm, and consistent wins.',
        stages: _rosaceaStages(logs),
        recommendations: _subtypeRecommendations(s),
        naturalAlternatives: _subtypeNaturalAlternatives(s),
      );
    case AcneRosaceaSubtype.flushing:
      return SubtypePlan(
        subtype: s,
        subtypeLabel: 'Flushing & Erythema',
        overview:
            'Track personal triggers (heat, alcohol, spicy food, stress) '
            'and trial topical α-agonists. Vascular laser is the '
            'definitive intervention for persistent erythema.',
        stages: _flushingStages(logs),
        recommendations: _subtypeRecommendations(s),
        naturalAlternatives: _subtypeNaturalAlternatives(s),
      );
    case AcneRosaceaSubtype.visibleVessels:
      return SubtypePlan(
        subtype: s,
        subtypeLabel: 'Visible Blood Vessels (Telangiectasia)',
        overview:
            'Topicals do not erase fixed vessels. Vascular laser (KTP / '
            'Nd:YAG) is the definitive treatment; SPF preserves results.',
        stages: _vesselStages(logs),
        recommendations: _subtypeRecommendations(s),
        naturalAlternatives: _subtypeNaturalAlternatives(s),
      );
    case AcneRosaceaSubtype.sensitivity:
      return SubtypePlan(
        subtype: s,
        subtypeLabel: 'Skin Sensitivity',
        overview:
            'Strip the routine to barrier essentials for 2 weeks: gentle '
            'cleanser, ceramide moisturizer, mineral SPF. Re-introduce '
            'one active at a time after the barrier resets.',
        stages: _sensitivityStages(logs),
        recommendations: _subtypeRecommendations(s),
        naturalAlternatives: _subtypeNaturalAlternatives(s),
      );
  }
}

// Stage tables — current-phase highlight chosen by latest severity bucket.

/// Evidence-based natural / clean alternatives surfaced per subtype.
/// These are *supporting* options for users who prefer naturally-derived
/// actives — they are NOT a substitute for foundational prescription care.
List<ProductRecommendation> _subtypeNaturalAlternatives(AcneRosaceaSubtype s) {
  switch (s) {
    case AcneRosaceaSubtype.acne:
      return const [
        ProductRecommendation(
          name: 'Tea tree 5% serum',
          activeIngredient: 'Melaleuca alternifolia 5%',
          rationale:
              'A randomized trial in *Med J Aust* found 5% tea tree '
              'oil cut inflammatory lesions comparably to 5% BPO with less '
              'dryness. Pair with a ceramide moisturizer.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Green tea polyphenol toner',
          activeIngredient: 'EGCG (Camellia sinensis 2-3%)',
          rationale:
              'EGCG modulates sebum and 5α-reductase activity in '
              'sebocytes (J Invest Dermatol, 2013). Useful adjunct to '
              'evening retinoid or azelaic acid.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Niacinamide 4-5% (B3)',
          activeIngredient: 'Vitamin B3',
          rationale:
              'Naturally occurring vitamer; reduces inflammatory '
              'papules by ~50% over 8 weeks (Int J Dermatol, 1995). Layers '
              'cleanly with most acne actives.',
          priority: RecommendationPriority.supporting,
        ),
      ];
    case AcneRosaceaSubtype.cystic:
      return const [
        ProductRecommendation(
          name: 'Centella asiatica + azelaic combo',
          activeIngredient: 'Madecassoside + azelaic acid',
          rationale:
              'Centella triterpenes calm dermal inflammation while '
              'azelaic acid (naturally derived from grains) targets P. acnes '
              'and PIH without the dryness of BPO.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Manuka honey overnight mask',
          activeIngredient: 'Manuka honey (MGO 250+)',
          rationale:
              'Methylglyoxal in medical-grade manuka has shown '
              'antibacterial activity vs. P. acnes (Asian Pac J Trop Biomed, '
              '2011). Spot-apply to active cysts; rinse AM.',
          priority: RecommendationPriority.optional,
        ),
        ProductRecommendation(
          name: 'Zinc PCA serum',
          activeIngredient: 'Zinc PCA 1%',
          rationale:
              'Zinc reduces sebaceous output and supports wound '
              'healing — useful adjunct alongside prescription oral therapy.',
          priority: RecommendationPriority.optional,
        ),
      ];
    case AcneRosaceaSubtype.hormonal:
      return const [
        ProductRecommendation(
          name: 'Spearmint tea (oral, 2 cups/day)',
          activeIngredient: 'Mentha spicata polyphenols',
          rationale:
              'A 30-day RCT (Phytother Res, 2010) showed spearmint '
              'tea lowered free testosterone and acne lesion counts in women '
              'with hirsutism. Discuss with a clinician if on hormonal '
              'medications.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Bakuchiol 0.5-1% nightly',
          activeIngredient: 'Bakuchiol (Psoralea corylifolia)',
          rationale:
              'Plant-based retinol analogue — comparable wrinkle and '
              'pigment improvement to 0.5% retinol with less irritation '
              '(Br J Dermatol, 2019). Safer in pregnancy planning.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Niacinamide 5% + zinc',
          activeIngredient: 'Vitamin B3 + Zinc PCA',
          rationale:
              'Modulates sebum production and inflammation along the '
              'jawline. Layers cleanly with prescription spironolactone or '
              'OCPs.',
          priority: RecommendationPriority.supporting,
        ),
      ];
    case AcneRosaceaSubtype.rosacea:
      return const [
        ProductRecommendation(
          name: 'Centella + aloe vera barrier serum',
          activeIngredient: 'Asiaticoside + Aloe barbadensis',
          rationale:
              'Centella asiatica calms TRPV1-mediated flushing and '
              'restores ceramide synthesis (Exp Dermatol, 2018). Aloe adds '
              'humectant relief without occlusion.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Licorice root 2% serum',
          activeIngredient: 'Glycyrrhiza glabra (licochalcone A)',
          rationale:
              'Licochalcone A inhibits inflammatory cascades and '
              'reduced rosacea erythema in a 2008 randomized trial. A '
              'reliable adjunct to topical metronidazole or ivermectin.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Colloidal oat ceramide cream',
          activeIngredient: 'Avena sativa + ceramides',
          rationale:
              'Avenanthramides bind TLR4 and reduce neurogenic '
              'inflammation; clinically validated for rosacea barrier '
              'restoration.',
          priority: RecommendationPriority.supporting,
        ),
      ];
    case AcneRosaceaSubtype.flushing:
      return const [
        ProductRecommendation(
          name: 'Green tea EGCG cream',
          activeIngredient: 'Camellia sinensis 2-5%',
          rationale:
              'EGCG reduces vascular endothelial reactivity and '
              'redness in rosacea-prone skin (J Am Acad Dermatol, 2012). '
              'Layer under SPF.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Chamomile (bisabolol) calming serum',
          activeIngredient: 'α-Bisabolol 0.5-1%',
          rationale:
              'Reduces histamine-driven flushing and improves '
              'erythema scores in sensitive skin trials.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Colloidal oat moisturizer',
          activeIngredient: 'Avena sativa',
          rationale:
              'Avenanthramides dampen neurogenic flushing — useful '
              'AM/PM during high-trigger seasons.',
          priority: RecommendationPriority.optional,
        ),
      ];
    case AcneRosaceaSubtype.visibleVessels:
      return const [
        ProductRecommendation(
          name: 'Licorice + niacinamide brightening serum',
          activeIngredient: 'Glycyrrhiza glabra + B3',
          rationale:
              'Reduces perivascular pigment that emphasizes vessels. '
              'Pair with daily mineral SPF; will not replace vascular laser '
              'for fixed telangiectasia.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Centella asiatica calming gel',
          activeIngredient: 'Madecassoside 0.2%',
          rationale:
              'Strengthens microvascular wall integrity (Phytomedicine, '
              '2010). Supportive between laser sessions.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Sea buckthorn oil (1-2 drops, PM)',
          activeIngredient: 'Hippophae rhamnoides (omega-7)',
          rationale:
              'Palmitoleic acid supports endothelial repair. Use '
              'sparingly — patch-test for rosacea-prone skin.',
          priority: RecommendationPriority.optional,
        ),
      ];
    case AcneRosaceaSubtype.sensitivity:
      return const [
        ProductRecommendation(
          name: 'Colloidal oat barrier balm',
          activeIngredient: 'Avena sativa + panthenol',
          rationale:
              'Restores stratum corneum integrity within 2-3 days. '
              'First-line during barrier reset weeks.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Centella asiatica recovery serum',
          activeIngredient: 'Asiaticoside + madecassoside',
          rationale:
              'Accelerates barrier and stratum corneum lipid '
              'recovery without irritation potential.',
          priority: RecommendationPriority.supporting,
        ),
        ProductRecommendation(
          name: 'Calendula + chamomile cream',
          activeIngredient: 'Calendula officinalis + Matricaria',
          rationale:
              'Mild anti-inflammatory blend tolerated even on '
              'eczema-prone skin. Fragrance-free formulations only.',
          priority: RecommendationPriority.optional,
        ),
      ];
  }
}

List<HealingStage> _acneStages(Map<String, List<AcneRosaceaLog>> logs) {
  final sev = (logs['acneSeverity'] ?? const []).isEmpty
      ? 0
      : logs['acneSeverity']!.first.value;
  return [
    HealingStage(
      weekRange: 'Week 1-4',
      title: 'Stabilize',
      description:
          'Start one topical (adapalene OR azelaic acid). Buffer '
          'with moisturizer. Expect a mild purge — comedonal load surfaces '
          'before it clears.',
      isCurrent: sev >= 6,
    ),
    HealingStage(
      weekRange: 'Week 5-8',
      title: 'Inflammation drops',
      description:
          'Active papule count typically falls 30-50%. Add 4-5% '
          'niacinamide AM. Avoid layering multiple new actives.',
      isCurrent: sev >= 3 && sev < 6,
    ),
    HealingStage(
      weekRange: 'Week 9-12',
      title: 'Tone evens',
      description:
          'Post-inflammatory marks fade. Maintain the routine — '
          'discontinuing now triggers rebound.',
      isCurrent: sev > 0 && sev < 3,
    ),
    HealingStage(
      weekRange: 'Month 4+',
      title: 'Maintenance',
      description:
          'Continue retinoid 3-5x/week. Add tretinoin 0.025% if '
          'response plateaus before clear.',
      isCurrent: sev == 0,
    ),
  ];
}

List<HealingStage> _cysticStages(Map<String, List<AcneRosaceaLog>> logs) {
  final sev = (logs['cysticAcneSeverity'] ?? const []).isEmpty
      ? 0
      : logs['cysticAcneSeverity']!.first.value;
  return [
    HealingStage(
      weekRange: 'Week 1-2',
      title: 'Triage active cysts',
      description:
          'Cold compress for 10 min twice daily. Hydrocolloid '
          'patches. Never extract. Book a dermatology consult.',
      isCurrent: sev >= 7,
    ),
    HealingStage(
      weekRange: 'Week 3-6',
      title: 'Anti-inflammatory base',
      description:
          'Azelaic acid 15-20% twice daily. If prescribed: oral '
          'doxycycline 50-100mg can bridge until topicals plateau.',
      isCurrent: sev >= 4 && sev < 7,
    ),
    HealingStage(
      weekRange: 'Week 7-12',
      title: 'Systemic consideration',
      description:
          'If cysts persist, board-certified derm may initiate '
          'isotretinoin or spironolactone. Track scarring risk.',
      isCurrent: sev >= 2 && sev < 4,
    ),
    HealingStage(
      weekRange: 'Month 4+',
      title: 'Scar repair window',
      description:
          'Once active disease quiets, microneedling + chemical '
          'peels are appropriate for atrophic scars. SPF non-negotiable.',
      isCurrent: sev < 2,
    ),
  ];
}

List<HealingStage> _hormonalStages(Map<String, List<AcneRosaceaLog>> logs) {
  final sev = (logs['hormonalAcneSeverity'] ?? const []).isEmpty
      ? 0
      : logs['hormonalAcneSeverity']!.first.value;
  return [
    HealingStage(
      weekRange: 'Week 1-2',
      title: 'Log the cycle',
      description:
          'Track flare day vs. menstrual day. Two cycles of data '
          'predicts the next luteal window so you can pre-empt actives.',
      isCurrent: sev >= 5,
    ),
    HealingStage(
      weekRange: 'Week 3-8',
      title: 'Systemic option',
      description:
          'Discuss spironolactone 50-100mg with a clinician. '
          'Nightly tretinoin 0.025-0.05% if barrier allows.',
      isCurrent: sev >= 3 && sev < 5,
    ),
    HealingStage(
      weekRange: 'Week 9-16',
      title: 'Pattern dampens',
      description:
          'Premenstrual cysts typically lose 50-70% of their '
          'severity on spironolactone by month 4.',
      isCurrent: sev >= 1 && sev < 3,
    ),
    HealingStage(
      weekRange: 'Month 5+',
      title: 'Maintenance',
      description:
          'Maintain spiro + retinoid. Trial annual taper to assess '
          'whether endogenous hormones have normalized.',
      isCurrent: sev < 1,
    ),
  ];
}

List<HealingStage> _rosaceaStages(Map<String, List<AcneRosaceaLog>> logs) {
  final sev = (logs['rosaceaSeverity'] ?? const []).isEmpty
      ? 0
      : logs['rosaceaSeverity']!.first.value;
  return [
    HealingStage(
      weekRange: 'Week 1-2',
      title: 'Calm the barrier',
      description:
          'Strip routine to gentle cleanser + ceramide moisturizer '
          '+ mineral SPF. Pause all actives.',
      isCurrent: sev >= 6,
    ),
    HealingStage(
      weekRange: 'Week 3-6',
      title: 'Targeted active',
      description:
          'Introduce ONE: azelaic acid 15%, ivermectin 1%, or '
          'metronidazole 0.75%. Daily. Patch-test if needed.',
      isCurrent: sev >= 3 && sev < 6,
    ),
    HealingStage(
      weekRange: 'Week 7-12',
      title: 'Papules clear',
      description:
          'Expect 60-70% reduction in inflammatory lesions. Keep '
          'fragrance-free and barrier-first.',
      isCurrent: sev >= 1 && sev < 3,
    ),
    HealingStage(
      weekRange: 'Month 4+',
      title: 'Maintenance + vascular',
      description:
          'Maintain the targeted active. Persistent erythema or '
          'vessels — consider IPL / vascular laser.',
      isCurrent: sev < 1,
    ),
  ];
}

List<HealingStage> _flushingStages(Map<String, List<AcneRosaceaLog>> logs) {
  final sev = (logs['rosaceaFlushing'] ?? const []).isEmpty
      ? 0
      : logs['rosaceaFlushing']!.first.value;
  return [
    HealingStage(
      weekRange: 'Week 1-2',
      title: 'Trigger inventory',
      description:
          'Log every flush with the trigger (heat / wine / spicy / '
          'stress / sun). Patterns emerge in 10-14 days.',
      isCurrent: sev >= 6,
    ),
    HealingStage(
      weekRange: 'Week 3-6',
      title: 'Topical α-agonist trial',
      description:
          'Brimonidine 0.33% or oxymetazoline 1% — daily. Apply a '
          'thin layer; rebound erythema can occur with too-frequent use.',
      isCurrent: sev >= 4 && sev < 6,
    ),
    HealingStage(
      weekRange: 'Week 7-12',
      title: 'Trigger avoidance entrenched',
      description:
          'Flushing frequency typically halves. If episodes remain '
          'severe, discuss low-dose β-blockers with a clinician.',
      isCurrent: sev >= 2 && sev < 4,
    ),
    HealingStage(
      weekRange: 'Month 4+',
      title: 'Long-term management',
      description:
          'Vascular laser for persistent background erythema. SPF '
          'preserves results.',
      isCurrent: sev < 2,
    ),
  ];
}

List<HealingStage> _vesselStages(Map<String, List<AcneRosaceaLog>> logs) {
  final sev = (logs['visibleBloodVessels'] ?? const []).isEmpty
      ? 0
      : logs['visibleBloodVessels']!.first.value;
  return [
    HealingStage(
      weekRange: 'Week 1-2',
      title: 'Baseline + photos',
      description:
          'Standardized lighting + close-up photos. Vessels rarely '
          'change without intervention — document for tracking.',
      isCurrent: sev >= 5,
    ),
    HealingStage(
      weekRange: 'Week 3-8',
      title: 'Vascular consult',
      description:
          'KTP 532nm or Nd:YAG 1064nm laser. Typically 1-3 '
          'sessions at 4-6 week intervals.',
      isCurrent: sev >= 3 && sev < 5,
    ),
    HealingStage(
      weekRange: 'Week 9-16',
      title: 'Visible clearance',
      description:
          'Most vessels resolve fully. IPL can add background '
          'redness reduction.',
      isCurrent: sev >= 1 && sev < 3,
    ),
    HealingStage(
      weekRange: 'Month 4+',
      title: 'Preservation',
      description:
          'Daily mineral SPF + avoidance of heat triggers prevent '
          'new vessel formation.',
      isCurrent: sev < 1,
    ),
  ];
}

List<HealingStage> _sensitivityStages(Map<String, List<AcneRosaceaLog>> logs) {
  final sev = (logs['skinSensitivity'] ?? const []).isEmpty
      ? 0
      : logs['skinSensitivity']!.first.value;
  return [
    HealingStage(
      weekRange: 'Week 1-2',
      title: 'Barrier reset',
      description:
          'Pause every active. Cleanser + ceramide moisturizer + '
          'mineral SPF only. Lukewarm water; pat dry.',
      isCurrent: sev >= 6,
    ),
    HealingStage(
      weekRange: 'Week 3-4',
      title: 'Soothing add-ons',
      description:
          'Centella asiatica serum and panthenol 5%. Hydrating mask '
          '2-3x/week.',
      isCurrent: sev >= 4 && sev < 6,
    ),
    HealingStage(
      weekRange: 'Week 5-8',
      title: 'Re-introduce one active',
      description:
          'Single active, 2x/week, buffered. Wait 4 weeks before '
          'adding a second.',
      isCurrent: sev >= 2 && sev < 4,
    ),
    HealingStage(
      weekRange: 'Month 3+',
      title: 'Resilient routine',
      description:
          'Full routine restored. If sensitivity recurs, suspect '
          'over-exfoliation or fragrance load.',
      isCurrent: sev < 2,
    ),
  ];
}

// ─── HEADLINES / SUMMARIES ──────────────────────────────────────────────────

(String, String) _composeHeadline({
  required SeverityBand band,
  required List<MetricTrend> trends,
  required bool hasEnoughData,
  required List<AcneRosaceaSubtype> dominantSubtypes,
}) {
  if (!hasEnoughData) {
    return (
      'Start your symptom journal',
      'Log severity + a photo to unlock personalized AI insights and a tailored healing plan.',
    );
  }
  final improving = trends
      .where((t) => t.direction7d == TrendDirection.improving)
      .toList();
  final worsening = trends
      .where((t) => t.direction7d == TrendDirection.worsening)
      .toList();
  String headline;
  String sub;
  switch (band) {
    case SeverityBand.clear:
      headline = 'Skin is calm';
      sub =
          'No active acne or rosacea signals in your recent logs. '
          'Maintain the routine that got you here.';
      break;
    case SeverityBand.mild:
      headline = 'Mild activity — stable territory';
      sub = improving.isNotEmpty
          ? '${improving.first.summary}. Keep the current routine consistent.'
          : 'A few low-grade entries. Small, steady actives outperform stacking.';
      break;
    case SeverityBand.moderate:
      headline = 'Moderate activity — focus phase';
      sub = worsening.isNotEmpty
          ? 'Heads-up: ${worsening.first.summary}. Now is the time to tighten '
                'the plan.'
          : 'Hold your current actives. Pair with a barrier-first cleanser and SPF.';
      break;
    case SeverityBand.marked:
      headline = 'Marked activity — escalate care';
      sub =
          'Topicals alone may not suffice. Consider a board-certified derm '
          'consult for systemic options.';
      break;
    case SeverityBand.severe:
      headline = 'Severe activity — seek care';
      sub =
          'Track scarring risk. A dermatologist can fast-track '
          'systemic treatment.';
      break;
  }
  if (dominantSubtypes.isNotEmpty) {
    sub =
        '${_subtypeLabel(dominantSubtypes.first)} is your primary signal. $sub';
  }
  return (headline, sub);
}

String _subtypeLabel(AcneRosaceaSubtype s) {
  switch (s) {
    case AcneRosaceaSubtype.acne:
      return 'Inflammatory acne';
    case AcneRosaceaSubtype.cystic:
      return 'Cystic acne';
    case AcneRosaceaSubtype.hormonal:
      return 'Hormonal acne';
    case AcneRosaceaSubtype.rosacea:
      return 'Rosacea';
    case AcneRosaceaSubtype.flushing:
      return 'Flushing';
    case AcneRosaceaSubtype.visibleVessels:
      return 'Visible vessels';
    case AcneRosaceaSubtype.sensitivity:
      return 'Skin sensitivity';
  }
}

String _composeHealingSummary({
  required List<AcneRosaceaSubtype> dominantSubtypes,
  required SeverityBand band,
  required List<CompatibilityWarning> warnings,
  required int recommendationCount,
}) {
  if (dominantSubtypes.isEmpty) {
    return 'Add a few severity entries so we can build a personalized plan.';
  }
  final subtypes = dominantSubtypes.map(_subtypeLabel).join(' · ');
  final warningCount = warnings.length;
  final warningPart = warningCount == 0
      ? 'Your current product stack looks compatible.'
      : '$warningCount compatibility issue${warningCount == 1 ? '' : 's'} '
            'flagged — see warnings below.';
  return 'Plan focus: $subtypes. $recommendationCount targeted product '
      'options. $warningPart';
}

String _composeNextStep({
  required bool hasEnoughData,
  required int photoCount,
  required List<MetricTrend> trends,
  required List<AcneRosaceaSubtype> dominantSubtypes,
}) {
  if (!hasEnoughData) {
    return 'Tap "Quick Log" to record your first severity reading and add a photo.';
  }
  if (photoCount == 0) {
    return 'Capture a baseline photo today — before/after comparison unlocks at 2 photos.';
  }
  if (photoCount == 1) {
    return 'Add a second photo to unlock the Before/After comparison.';
  }
  final worsening = trends
      .where((t) => t.direction7d == TrendDirection.worsening)
      .toList();
  if (worsening.isNotEmpty) {
    return 'Pause new actives this week. Cross-check the Warnings list for triggers.';
  }
  if (dominantSubtypes.isEmpty) {
    return 'Log a few more entries so we can pinpoint your dominant subtype.';
  }
  return 'Stay consistent — re-log in 7 days and let the trend chart confirm progress.';
}

// ─── DAILY / WEEKLY ACTION PLAN ─────────────────────────────────────────────

List<String> _composeDailyActions(
  List<AcneRosaceaSubtype> subtypes,
  SeverityBand band,
) {
  // Foundational daily ritual — everyone gets these.
  final actions = <String>[
    'AM: gentle non-foaming cleanser → barrier moisturizer → mineral SPF 30+.',
    'PM: double cleanse only if wearing SPF/makeup → barrier moisturizer.',
    'Hands off the face — no picking, popping, or unnecessary touching.',
  ];
  final s = subtypes.toSet();
  if (s.contains(AcneRosaceaSubtype.acne) ||
      s.contains(AcneRosaceaSubtype.cystic) ||
      s.contains(AcneRosaceaSubtype.hormonal)) {
    actions.add(
      'PM (alt nights): adapalene 0.1% pea-sized over the entire affected area — buffer with moisturizer if irritated.',
    );
    actions.add(
      'Spot-treat new lesions with benzoyl peroxide 2.5% (5 min short-contact rinse-off if sensitive).',
    );
  }
  if (s.contains(AcneRosaceaSubtype.rosacea) ||
      s.contains(AcneRosaceaSubtype.flushing) ||
      s.contains(AcneRosaceaSubtype.visibleVessels)) {
    actions.add(
      'PM: azelaic acid 10–15% across the central face — anti-inflammatory + tone-evening.',
    );
    actions.add(
      'Cool compress 5–10 minutes after any flushing trigger (heat, alcohol, spicy food).',
    );
  }
  if (s.contains(AcneRosaceaSubtype.sensitivity)) {
    actions.add(
      'Skip actives today if skin stings on cleanse — anchor on ceramides + panthenol only.',
    );
  }
  if (band == SeverityBand.marked || band == SeverityBand.severe) {
    actions.add(
      'Photograph the most affected zone in morning daylight — your dermatologist will use this.',
    );
  }
  return actions;
}

List<String> _composeWeeklyActions(
  List<AcneRosaceaSubtype> subtypes,
  SeverityBand band,
  int photoCount,
) {
  final actions = <String>[
    'Log severity 2–3× this week so the AI engine can detect a real trend.',
    photoCount < 2
        ? 'Capture a progress photo (same lighting, same angle, no makeup).'
        : 'Capture 1–2 progress photos in the same morning lighting.',
    'Review your Trigger Hypotheses tab and note any pattern (cycle, stress, diet, weather).',
  ];
  final s = subtypes.toSet();
  if (s.contains(AcneRosaceaSubtype.hormonal)) {
    actions.add(
      'Mark cycle day in each note — hormonal flares peak 7–10 days pre-menses.',
    );
  }
  if (s.contains(AcneRosaceaSubtype.cystic)) {
    actions.add(
      'If a cyst persists >2 weeks: book a dermatologist consult for intralesional triamcinolone.',
    );
  }
  if (s.contains(AcneRosaceaSubtype.rosacea)) {
    actions.add(
      'Audit your trigger log — eliminate the top-2 most-tagged triggers for 14 days.',
    );
  }
  if (s.contains(AcneRosaceaSubtype.sensitivity)) {
    actions.add(
      'Patch-test any new product on the inner forearm for 3 nights before face use.',
    );
  }
  if (band == SeverityBand.marked || band == SeverityBand.severe) {
    actions.add(
      'Book or confirm a dermatologist appointment — systemic options may accelerate healing.',
    );
  } else {
    actions.add(
      'Hold the line: changing your routine every 2 weeks resets the 6–12 week response window.',
    );
  }
  return actions;
}
