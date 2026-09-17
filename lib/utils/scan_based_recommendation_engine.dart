// lib/utils/scan_based_recommendation_engine.dart
//
// Unified, on-device recommendation engine that combines:
//   • Peptides (curated kPeptideLibrary)
//   • Procedures (curated catalog with metric-trigger rules)
//   • Skincare Products (delegated to AIProductRecommendationEngine)
//
// All output is keyed off a baseline-vs-latest scan comparison and is
// returned with plain-language explanations such as:
//   "Dark Spots only improved 0.2 points — recommend GHK-Cu + Brightening Stack"

library scan_based_recommendation_engine;


import '../models/peptide_model.dart';
import '../models/scan_history.dart';
import 'ai_product_recommendation_engine.dart';

/// One scan-driven peptide recommendation.
class PeptideRecommendation {
  final PeptideLibraryEntry entry;
  final String reason; // why this peptide matches the scan delta
  final String expectedBenefit; // 1-line outcome
  final List<String> matchedMetrics; // metric labels that triggered the match

  const PeptideRecommendation({
    required this.entry,
    required this.reason,
    required this.expectedBenefit,
    required this.matchedMetrics,
  });
}

/// One scan-driven procedure recommendation.
class ProcedureRecommendation {
  final String name; // e.g. "Fractional Laser"
  final String category; // "Laser" | "Microneedling" | "Light-Based" | "Peel"
  final String mechanism; // what the procedure actually does
  final String reason; // tied to the user's metric values
  final List<String> matchedMetrics;
  final String evidenceTier; // Tier 1 / Tier 2

  const ProcedureRecommendation({
    required this.name,
    required this.category,
    required this.mechanism,
    required this.reason,
    required this.matchedMetrics,
    required this.evidenceTier,
  });
}

/// Final bundle returned to the UI.
class ScanRecommendations {
  final String headline; // e.g. "3 areas to focus on"
  final String summary; // free-text explanation tying deltas together
  final List<PeptideRecommendation> peptides;
  final List<ProcedureRecommendation> procedures;
  final List<AIProductRecommendation> products;
  final List<MetricDelta> deltas;
  final List<MetricDelta> bodyDeltas;
  final bool hasEnoughData;

  const ScanRecommendations({
    required this.headline,
    required this.summary,
    required this.peptides,
    required this.procedures,
    required this.products,
    required this.deltas,
    this.bodyDeltas = const [],
    required this.hasEnoughData,
  });
}

class MetricDelta {
  final String label; // e.g. "Dark Spots"
  final String key; // "darkSpots", "redness", ...
  final double latest;
  final double baseline;
  final double delta; // latest - baseline (raw)
  final bool lowerIsBetter;
  final bool improved; // true if direction is healthy
  final double improvement; // signed magnitude in the healthy direction
  final String
  trendLabel; // "Significant improvement" / "Slight progress" / "Plateau" / "Worsening"

  const MetricDelta({
    required this.label,
    required this.key,
    required this.latest,
    required this.baseline,
    required this.delta,
    required this.lowerIsBetter,
    required this.improved,
    required this.improvement,
    required this.trendLabel,
  });
}

class ScanBasedRecommendationEngine {
  const ScanBasedRecommendationEngine._();

  /// Generate the unified scan-based recommendation bundle.
  static ScanRecommendations generate({
    required SkinMetrics latest,
    SkinMetrics? baseline,
    String? procedureType,
    Map<String, double>? latestBody,
    Map<String, double>? baselineBody,
  }) {
    final hasBaseline = baseline != null;
    final deltas = hasBaseline
      ? _buildDeltas(latest, baseline)
        : const <MetricDelta>[];
    final bodyDeltas = _buildBodyDeltas(latestBody, baselineBody);

    final peptides = _recommendPeptides(deltas, latest, bodyDeltas: bodyDeltas);
    final procedures = _recommendProcedures(
      deltas,
      latest,
      bodyDeltas: bodyDeltas,
    );
    final resolvedProcedureType = (() {
      final normalized = (procedureType ?? '').trim();
      if (normalized.isEmpty || normalized.toLowerCase() == 'unknown') {
        return 'General Skincare';
      }
      return normalized;
    })();
    final products = AIProductRecommendationEngine.generateRecommendations(
      latest,
      baselineMetrics: baseline,
      procedureType: resolvedProcedureType,
      maxRecommendations: 4,
      userSkinConcerns: [
        if (latest.redness > 6.0) 'redness',
        if (latest.texture > 6.0) 'texture',
        if (latest.wrinkle > 6.0) 'aging',
        if (latest.pore > 6.0) 'pores',
        if (latest.darkSpots > 6.0) 'pigmentation',
        if (latest.elasticity < 4.8) 'firmness',
        if (latest.redness > 6.0) 'sensitive',
      ],
      recentProcedureTypes:
          resolvedProcedureType.toLowerCase() != 'general skincare'
          ? [resolvedProcedureType]
          : null,
    );

    return ScanRecommendations(
      headline: _buildHeadline(
        deltas,
        bodyDeltas,
        hasBaseline: hasBaseline,
      ),
      summary: _buildSummary(
        deltas,
        bodyDeltas: bodyDeltas,
        hasBaseline: hasBaseline,
      ),
      peptides: peptides,
      procedures: procedures,
      products: products,
      deltas: deltas,
      bodyDeltas: bodyDeltas,
      hasEnoughData: hasBaseline || bodyDeltas.isNotEmpty,
    );
  }

  // ── Deltas ─────────────────────────────────────────────────────────────────
  static List<MetricDelta> _buildDeltas(SkinMetrics l, SkinMetrics b) {
    return [
      _delta('Redness', 'redness', l.redness, b.redness, lowerIsBetter: true),
      _delta('Texture', 'texture', l.texture, b.texture, lowerIsBetter: true),
      _delta('Wrinkles', 'wrinkles', l.wrinkle, b.wrinkle, lowerIsBetter: true),
      _delta('Pores', 'pores', l.pore, b.pore, lowerIsBetter: true),
      _delta(
        'Dark Spots',
        'darkSpots',
        l.darkSpots,
        b.darkSpots,
        lowerIsBetter: true,
      ),
      _delta(
        'Elasticity',
        'elasticity',
        l.elasticity,
        b.elasticity,
        lowerIsBetter: false,
      ),
    ];
  }

  static MetricDelta _delta(
    String label,
    String key,
    double latest,
    double baseline, {
    required bool lowerIsBetter,
  }) {
    final raw = latest - baseline;
    final improvement = lowerIsBetter ? -raw : raw;
    final improved = improvement > 0.05;
    String trend;
    if (improvement >= 1.0) {
      trend = 'Significant improvement';
    } else if (improvement >= 0.4) {
      trend = 'Moderate improvement';
    } else if (improvement >= 0.05) {
      trend = 'Slight progress';
    } else if (improvement > -0.05) {
      trend = 'Plateau';
    } else if (improvement > -0.4) {
      trend = 'Mild worsening';
    } else {
      trend = 'Worsening';
    }
    return MetricDelta(
      label: label,
      key: key,
      latest: latest,
      baseline: baseline,
      delta: raw,
      lowerIsBetter: lowerIsBetter,
      improved: improved,
      improvement: improvement,
      trendLabel: trend,
    );
  }

  // ── Body composition deltas ───────────────────────────────────────────────
  // Body metrics live in the open `ScanHistoryEntry.metrics` map. Each key is
  // optional — we only emit a delta when both baseline and latest provide it.
  static const List<_BodyMetricSpec> _bodySpecs = [
    _BodyMetricSpec(
      'Weight',
      'weight',
      ['weightLbs', 'weight'],
      lowerIsBetter: true,
      signSignificance: 0.5,
    ),
    _BodyMetricSpec(
      'Body Fat %',
      'bodyFat',
      ['bodyFatPct', 'bodyFat'],
      lowerIsBetter: true,
      signSignificance: 0.3,
    ),
    _BodyMetricSpec(
      'Waist',
      'waist',
      ['waistInches', 'waistCm', 'waist'],
      lowerIsBetter: true,
      signSignificance: 0.3,
    ),
    _BodyMetricSpec(
      'Muscle Mass',
      'muscleMass',
      ['muscleMassLbs', 'muscleMass', 'leanMass'],
      lowerIsBetter: false,
      signSignificance: 0.3,
    ),
    _BodyMetricSpec(
      'Appetite Control',
      'appetiteControl',
      ['satietyScore', 'appetiteControl', 'satiety'],
      lowerIsBetter: false,
      signSignificance: 0.3,
    ),
    _BodyMetricSpec(
      'Body Composition Score',
      'bodyCompositionScore',
      ['bodyCompositionScore'],
      lowerIsBetter: false,
      signSignificance: 0.3,
    ),
  ];

  static List<MetricDelta> _buildBodyDeltas(
    Map<String, double>? latest,
    Map<String, double>? baseline,
  ) {
    if (latest == null || latest.isEmpty) return const [];
    final out = <MetricDelta>[];
    double? pick(Map<String, double>? m, List<String> keys) {
      if (m == null) return null;
      for (final k in keys) {
        final v = m[k];
        if (v != null) return v;
      }
      return null;
    }

    for (final spec in _bodySpecs) {
      final l = pick(latest, spec.keys);
      final b = pick(baseline, spec.keys);
      if (l == null || b == null) continue;
      final raw = l - b;
      final improvement = spec.lowerIsBetter ? -raw : raw;
      final improved = improvement > spec.signSignificance / 2;
      String trend;
      if (improvement >= spec.signSignificance * 3) {
        trend = 'Significant improvement';
      } else if (improvement >= spec.signSignificance) {
        trend = 'Moderate improvement';
      } else if (improvement >= spec.signSignificance / 2) {
        trend = 'Slight progress';
      } else if (improvement.abs() < spec.signSignificance / 2) {
        trend = 'Plateau';
      } else if (improvement > -spec.signSignificance) {
        trend = 'Mild worsening';
      } else {
        trend = 'Worsening';
      }
      out.add(
        MetricDelta(
          label: spec.label,
          key: spec.key,
          latest: l,
          baseline: b,
          delta: raw,
          lowerIsBetter: spec.lowerIsBetter,
          improved: improved,
          improvement: improvement,
          trendLabel: trend,
        ),
      );
    }
    return out;
  }

  // ── Headline / Summary ─────────────────────────────────────────────────────
  static String _buildHeadline(
    List<MetricDelta> deltas,
    List<MetricDelta> bodyDeltas,
    {
    required bool hasBaseline,
  }
  ) {
    if (!hasBaseline) {
      return bodyDeltas.isNotEmpty
          ? 'Body trend captured — add a baseline scan to unlock full skin status trends'
          : 'Baseline scan needed to unlock Stable / Improved / Worsened trends';
    }
    final focusAreas = deltas
        .where(
          (d) =>
              d.improvement < 0.4 &&
              (d.lowerIsBetter ? d.latest >= 4.5 : d.latest <= 6.5),
        )
        .length;
    final bodyFocus = bodyDeltas.where((d) => !d.improved).length;
    final total = focusAreas + bodyFocus;
    if (total == 0) return 'Your routine is working — keep building on it';
    if (total == 1) return '1 area to focus on next';
    return '$total areas to focus on next';
  }

  static String _buildSummary(
    List<MetricDelta> deltas, {
    required bool hasBaseline,
    List<MetricDelta> bodyDeltas = const [],
  }) {
    if (!hasBaseline) {
      return 'These recommendations are based on your latest scan. Capture a baseline scan to unlock improvement-over-time tracking.';
    }
    final improving = deltas
        .where((d) => d.improvement >= 0.4)
        .map((d) => d.label)
        .toList();
    final stalling = deltas
        .where((d) => d.improvement.abs() < 0.4 && _needsAttention(d))
        .map((d) => d.label)
        .toList();
    final worsening = deltas
        .where((d) => d.improvement <= -0.4)
        .map((d) => d.label)
        .toList();

    final parts = <String>[];
    if (improving.isNotEmpty) {
      parts.add(
        '${_joinWithAnd(improving)} ${improving.length == 1 ? "is" : "are"} responding well to your current routine',
      );
    }
    if (stalling.isNotEmpty) {
      parts.add(
        '${_joinWithAnd(stalling)} ${stalling.length == 1 ? "has" : "have"} plateaued and would benefit from a targeted addition',
      );
    }
    if (worsening.isNotEmpty) {
      parts.add(
        '${_joinWithAnd(worsening)} ${worsening.length == 1 ? "is" : "are"} trending in the wrong direction and need active intervention',
      );
    }
    if (parts.isEmpty) {
      return 'Your metrics are stable and within healthy ranges. The recommendations below focus on maintenance and prevention.';
    }
    final base =
        '${parts.join('. ').replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase())}.';
    if (bodyDeltas.isEmpty) return base;
    final bodyImproving = bodyDeltas
        .where((d) => d.improved)
        .map((d) => d.label)
        .toList();
    final bodyStuck = bodyDeltas
        .where((d) => !d.improved)
        .map((d) => d.label)
        .toList();
    final bodyParts = <String>[];
    if (bodyImproving.isNotEmpty) {
      bodyParts.add(
        '${_joinWithAnd(bodyImproving)} ${bodyImproving.length == 1 ? "is" : "are"} trending in the right direction',
      );
    }
    if (bodyStuck.isNotEmpty) {
      bodyParts.add(
        '${_joinWithAnd(bodyStuck)} ${bodyStuck.length == 1 ? "needs" : "need"} a targeted protocol',
      );
    }
    if (bodyParts.isEmpty) return base;
    return '$base Body composition: ${bodyParts.join("; ")}.';
  }

  static bool _needsAttention(MetricDelta d) {
    if (d.lowerIsBetter) return d.latest >= 4.5;
    return d.latest <= 6.5;
  }

  static String _joinWithAnd(List<String> items) {
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    return '${items.take(items.length - 1).join(", ")} and ${items.last}';
  }

  // ── Peptide recommendations ───────────────────────────────────────────────
  static List<PeptideRecommendation> _recommendPeptides(
    List<MetricDelta> deltas,
    SkinMetrics latest, {
    List<MetricDelta> bodyDeltas = const [],
  }) {
    final results = <PeptideRecommendation>[];
    final seen = <String>{};

    // Build prioritized concerns
    final concerns = [...deltas]
      ..sort((a, b) {
        // Concerns first (latest value × directionality), with stalled/worsening boost
        double score(MetricDelta d) {
          final severity = d.lowerIsBetter ? d.latest : (10 - d.latest);
          final stallPenalty = d.improvement < 0.4 ? 1.5 : 0.5;
          return severity * stallPenalty;
        }

        return score(b).compareTo(score(a));
      });

    for (final concern in concerns) {
      if (results.length >= 3) break;
      if (!_needsAttention(concern) && concern.improvement >= 0.4) continue;

      final matchTerms = _peptideMatchTermsFor(concern.key);
      final candidates = kPeptideLibrary.where((p) {
        if (seen.contains(p.name)) return false;
        final hay =
            ('${p.primaryMetrics.join(" ")} ${p.category} ${p.mechanism}')
                .toLowerCase();
        return matchTerms.any((t) => hay.contains(t));
      }).toList();
      if (candidates.isEmpty) continue;

      // Prefer Tier 1, then Tier 2
      candidates.sort(
        (a, b) => _tierWeight(
          a.evidenceLevel,
        ).compareTo(_tierWeight(b.evidenceLevel)),
      );

      final pick = candidates.first;
      seen.add(pick.name);

      results.add(
        PeptideRecommendation(
          entry: pick,
          reason: _peptideReason(concern, pick),
          expectedBenefit: _peptideBenefitFor(concern.key),
          matchedMetrics: [concern.label],
        ),
      );
    }

    // Body-composition peptides: drawn from the dedicated 'body-composition'
    // category. We only suggest these when the user has body metrics tracked
    // *and* at least one is stalled or worsening.
    final bodyConcerns = bodyDeltas.where((d) => !d.improved).toList()
      ..sort((a, b) {
        // Higher absolute baseline + worse direction → higher priority.
        double w(MetricDelta d) =>
            (d.improved ? 0 : 1) * 10 + (d.improvement < 0 ? 5 : 0);
        return w(b).compareTo(w(a));
      });

    final bodyLib =
        kPeptideLibrary
            .where((p) => p.category.toLowerCase().contains('body'))
            .toList()
          ..sort(
            (a, b) => _tierWeight(
              a.evidenceLevel,
            ).compareTo(_tierWeight(b.evidenceLevel)),
          );

    for (final concern in bodyConcerns) {
      if (results.length >= 5) break;
      final terms = _bodyPeptideMatchTermsFor(concern.key);
      PeptideLibraryEntry? pick;
      for (final p in bodyLib) {
        if (seen.contains(p.name)) continue;
        final hay =
            '${p.primaryMetrics.join(" ")} ${p.category} ${p.mechanism} ${p.name}'
                .toLowerCase();
        if (terms.any((t) => hay.contains(t))) {
          pick = p;
          break;
        }
      }
      // Fallback: any unused body peptide.
      pick ??= bodyLib.firstWhere(
        (p) => !seen.contains(p.name),
        orElse: () =>
            bodyLib.isNotEmpty ? bodyLib.first : kPeptideLibrary.first,
      );
      if (seen.contains(pick.name)) continue;
      seen.add(pick.name);
      results.add(
        PeptideRecommendation(
          entry: pick,
          reason: _bodyPeptideReason(concern, pick),
          expectedBenefit: _bodyPeptideBenefitFor(concern.key),
          matchedMetrics: [concern.label],
        ),
      );
    }

    return results;
  }

  static List<String> _bodyPeptideMatchTermsFor(String key) {
    switch (key) {
      case 'weight':
        return ['glp-1', 'glp1', 'tirzepatide', 'semaglutide', 'retatrutide'];
      case 'bodyFat':
        return ['fat', 'lipolysis', 'aod', 'tesamorelin'];
      case 'waist':
        return ['visceral', 'tesamorelin', 'fat'];
      case 'muscleMass':
        return ['cjc', 'ipamorelin', 'ghrh', 'igf', 'sermorelin', 'hexarelin'];
      case 'appetiteControl':
        return ['glp-1', 'glp1', 'semaglutide', 'tirzepatide'];
      case 'bodyCompositionScore':
        return ['body composition', 'mots', 'recomp'];
      default:
        return ['body'];
    }
  }

  static String _bodyPeptideReason(MetricDelta d, PeptideLibraryEntry p) {
    final latest = d.latest.toStringAsFixed(1);
    final improvementStr = d.improvement.abs().toStringAsFixed(1);
    if (d.improvement.abs() < 0.05) {
      return 'Your ${d.label} has plateaued at $latest. ${p.name} introduces a clinically-supported mechanism to restart progress.';
    }
    if (!d.improved) {
      return '${d.label} moved $improvementStr in the wrong direction (now $latest). ${p.name} directly targets this pathway.';
    }
    return 'Your ${d.label} is at $latest. ${p.name} can compound the trajectory you\'re already on.';
  }

  static String _bodyPeptideBenefitFor(String key) {
    switch (key) {
      case 'weight':
        return 'Reduces appetite and caloric intake via incretin pathways.';
      case 'bodyFat':
        return 'Targets adipose tissue lipolysis without affecting lean mass.';
      case 'waist':
        return 'Specifically reduces visceral adipose tissue (VAT).';
      case 'muscleMass':
        return 'Stimulates GH/IGF-1 axis to preserve and build lean tissue.';
      case 'appetiteControl':
        return 'Improves satiety signaling and reduces craving frequency.';
      case 'bodyCompositionScore':
        return 'Supports a recomposition phenotype — fat down, lean up.';
      default:
        return 'Targets the underlying biology of this concern.';
    }
  }

  static List<String> _peptideMatchTermsFor(String key) {
    switch (key) {
      case 'darkSpots':
        return ['dark spot', 'pigment', 'brighten'];
      case 'redness':
        return ['redness', 'inflammation', 'swelling', 'healing'];
      case 'texture':
        return ['texture', 'barrier', 'healing'];
      case 'wrinkles':
        return ['wrinkle', 'fine line', 'anti-aging'];
      case 'pores':
        return ['pore'];
      case 'elasticity':
        return ['elasticity', 'firmness', 'firming', 'anti-aging'];
      default:
        return [key.toLowerCase()];
    }
  }

  static String _peptideReason(MetricDelta d, PeptideLibraryEntry p) {
    final latest = d.latest.toStringAsFixed(1);
    final improvementStr = d.improvement.abs().toStringAsFixed(1);
    if (d.improvement < 0.4 && d.improvement >= -0.05) {
      return 'Your ${d.label} score only improved $improvementStr points (now $latest). ${p.name} directly targets this pathway and is a strong next step.';
    }
    if (d.improvement < -0.05) {
      return 'Your ${d.label} has worsened by $improvementStr points (now $latest). ${p.name} adds a clinically-validated mechanism to reverse the trend.';
    }
    return 'Your ${d.label} is currently at $latest. Adding ${p.name} can compound the improvements you\'re already seeing.';
  }

  static String _peptideBenefitFor(String key) {
    switch (key) {
      case 'darkSpots':
        return 'Inhibits melanogenesis and accelerates fading of pigmentation.';
      case 'redness':
        return 'Calms inflammatory signaling and supports barrier resilience.';
      case 'texture':
        return 'Promotes orderly keratinocyte renewal and a smoother surface.';
      case 'wrinkles':
        return 'Stimulates collagen synthesis to soften static and dynamic lines.';
      case 'pores':
        return 'Regulates sebum and supports perifollicular collagen structure.';
      case 'elasticity':
        return 'Drives collagen I/III synthesis for measurable firming.';
      default:
        return 'Targets the underlying biology of this concern.';
    }
  }

  static int _tierWeight(String tier) {
    switch (tier) {
      case 'Tier 1':
        return 0;
      case 'Tier 2':
        return 1;
      case 'Tier 3':
        return 2;
      default:
        return 3;
    }
  }

  // ── Procedure recommendations ─────────────────────────────────────────────
  static List<ProcedureRecommendation> _recommendProcedures(
    List<MetricDelta> deltas,
    SkinMetrics latest, {
    List<MetricDelta> bodyDeltas = const [],
  }) {
    final triggers = <String, MetricDelta>{
      for (final d in deltas) d.key: d,
      for (final d in bodyDeltas) d.key: d,
    };

    final candidates = <_ProcedureRule>[
      // Brightening / pigment
      const _ProcedureRule(
        name: 'BBL / BroadBand Light',
        category: 'Light-Based',
        mechanism:
            'Selective photothermolysis targets melanin and vascular lesions; clinically validated for sunspots, redness and tone evenness.',
        tier: 'Tier 1',
        triggerKeys: ['darkSpots', 'redness'],
        threshold: 5.0,
        stallSensitive: true,
      ),
      const _ProcedureRule(
        name: 'IPL Photofacial',
        category: 'Light-Based',
        mechanism:
            'Broad-spectrum light dissipates excess melanin and reduces vascular redness across the face.',
        tier: 'Tier 1',
        triggerKeys: ['darkSpots', 'redness'],
        threshold: 4.5,
        stallSensitive: true,
      ),
      const _ProcedureRule(
        name: 'Chemical Peel (Medium Depth)',
        category: 'Peel',
        mechanism:
            'Controlled epidermal/papillary dermal exfoliation accelerates pigmented keratinocyte turnover.',
        tier: 'Tier 1',
        triggerKeys: ['darkSpots', 'texture'],
        threshold: 5.0,
        stallSensitive: true,
      ),
      // Texture / wrinkles
      const _ProcedureRule(
        name: 'Fractional Non-Ablative Laser (e.g. Fraxel)',
        category: 'Laser',
        mechanism:
            'Creates microscopic thermal zones that trigger collagen remodeling and refine surface texture and fine lines.',
        tier: 'Tier 1',
        triggerKeys: ['texture', 'wrinkles'],
        threshold: 5.0,
      ),
      const _ProcedureRule(
        name: 'CO2 Laser Resurfacing',
        category: 'Laser',
        mechanism:
            'Ablative fractional resurfacing for deep wrinkles, photodamage and significant textural concerns; longer downtime, deeper impact.',
        tier: 'Tier 1',
        triggerKeys: ['wrinkles', 'texture'],
        threshold: 6.5,
      ),
      const _ProcedureRule(
        name: 'Microneedling (SkinPen)',
        category: 'Microneedling',
        mechanism:
            'Controlled micro-channels trigger fibroblast activation for collagen induction with minimal downtime.',
        tier: 'Tier 1',
        triggerKeys: ['texture', 'pores', 'wrinkles'],
        threshold: 4.5,
      ),
      // Firming / elasticity / pores
      const _ProcedureRule(
        name: 'RF Microneedling (Morpheus8)',
        category: 'Microneedling',
        mechanism:
            'Combines bipolar RF energy with micro-needles to remodel deep dermis and SMAS — meaningful for elasticity and enlarged pores.',
        tier: 'Tier 1',
        triggerKeys: ['elasticity', 'pores', 'wrinkles'],
        threshold: 5.0,
      ),
      const _ProcedureRule(
        name: 'HIFU (Ultherapy)',
        category: 'Energy-Based',
        mechanism:
            'Micro-focused ultrasound deposits thermal energy at SMAS depth, stimulating sustained collagen contraction and lift.',
        tier: 'Tier 1',
        triggerKeys: ['elasticity'],
        threshold: 5.5,
      ),
      // Combo / maintenance
      const _ProcedureRule(
        name: 'Halo Hybrid Laser',
        category: 'Laser',
        mechanism:
            'Combines ablative and non-ablative wavelengths in one pass — addresses pigment, texture and tone simultaneously.',
        tier: 'Tier 1',
        triggerKeys: ['darkSpots', 'texture', 'wrinkles'],
        threshold: 5.5,
      ),
      const _ProcedureRule(
        name: 'HydraFacial',
        category: 'Maintenance',
        mechanism:
            'Multi-step cleanse / exfoliate / extract / hydrate; an evidence-based maintenance facial between deeper procedures.',
        tier: 'Tier 2',
        triggerKeys: ['pores', 'texture'],
        threshold: 4.0,
      ),
    ];

    final scored = <_ScoredProcedure>[];
    for (final rule in candidates) {
      double score = 0;
      final matched = <String>[];
      for (final key in rule.triggerKeys) {
        final d = triggers[key];
        if (d == null) continue;
        final severity = d.lowerIsBetter ? d.latest : (10 - d.latest);
        if (severity < rule.threshold) continue;
        matched.add(d.label);
        score += severity;
        if (rule.stallSensitive && d.improvement < 0.4) score += 1.5;
      }
      if (matched.isEmpty) continue;
      // Tier weight slightly boosts Tier 1
      if (rule.tier == 'Tier 1') score += 0.5;
      scored.add(_ScoredProcedure(rule: rule, score: score, matched: matched));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final skinTop = scored.take(3).map((s) {
      return ProcedureRecommendation(
        name: s.rule.name,
        category: s.rule.category,
        mechanism: s.rule.mechanism,
        evidenceTier: s.rule.tier,
        matchedMetrics: s.matched,
        reason: _procedureReason(s, triggers),
      );
    }).toList();

    // Body procedures: rule-based, severity inferred from non-improvement
    // rather than a 0-10 scale.
    final bodyResults = _recommendBodyProcedures(bodyDeltas);
    return [...skinTop, ...bodyResults];
  }

  static List<ProcedureRecommendation> _recommendBodyProcedures(
    List<MetricDelta> bodyDeltas,
  ) {
    if (bodyDeltas.isEmpty) return const [];
    final byKey = {for (final d in bodyDeltas) d.key: d};
    final results = <ProcedureRecommendation>[];

    void emit({
      required String name,
      required String category,
      required String mechanism,
      required String tier,
      required List<String> triggerKeys,
      required String reasonTemplate,
    }) {
      final matched = <String>[];
      for (final k in triggerKeys) {
        final d = byKey[k];
        if (d != null && !d.improved) matched.add(d.label);
      }
      if (matched.isEmpty) return;
      results.add(
        ProcedureRecommendation(
          name: name,
          category: category,
          mechanism: mechanism,
          evidenceTier: tier,
          matchedMetrics: matched,
          reason: reasonTemplate.replaceAll('{m}', matched.join(' and ')),
        ),
      );
    }

    emit(
      name: 'CoolSculpting (Cryolipolysis)',
      category: 'Body Contouring',
      mechanism:
          'Targeted cooling induces apoptosis of subcutaneous adipocytes — non-invasive fat reduction.',
      tier: 'Tier 1',
      triggerKeys: const ['bodyFat', 'waist'],
      reasonTemplate:
          '{m} is not responding to current protocol — CoolSculpting directly reduces stubborn subcutaneous fat depots.',
    );
    emit(
      name: 'EmSculpt NEO',
      category: 'Body Contouring',
      mechanism:
          'Combined HIFEM + RF: simultaneous muscle hypertrophy and adipose reduction in one session.',
      tier: 'Tier 1',
      triggerKeys: const ['muscleMass', 'bodyFat'],
      reasonTemplate:
          '{m} would benefit from a recomposition-focused intervention — EmSculpt NEO builds muscle while reducing overlying fat.',
    );
    emit(
      name: 'BodyTite (RF Lipo)',
      category: 'Body Contouring',
      mechanism:
          'Minimally invasive radiofrequency-assisted lipolysis with simultaneous dermal tightening.',
      tier: 'Tier 1',
      triggerKeys: const ['waist', 'bodyFat'],
      reasonTemplate:
          '{m} stalled — BodyTite addresses both adiposity and overlying skin laxity in one procedure.',
    );
    emit(
      name: 'Liposuction (Tumescent)',
      category: 'Surgical',
      mechanism:
          'Surgical removal of localized adipose deposits for definitive contour reshaping.',
      tier: 'Tier 1',
      triggerKeys: const ['bodyFat'],
      reasonTemplate:
          '{m} is significantly elevated and not responding — liposuction is the definitive surgical option for localized fat.',
    );
    emit(
      name: 'Lymphatic Drainage Massage',
      category: 'Recovery',
      mechanism:
          'Manual lymph mobilization to reduce post-procedure swelling and improve fluid retention.',
      tier: 'Tier 2',
      triggerKeys: const ['waist'],
      reasonTemplate:
          '{m} may reflect fluid retention — lymphatic drainage accelerates resolution alongside body-comp protocols.',
    );

    return results.take(3).toList();
  }

  static String _procedureReason(
    _ScoredProcedure s,
    Map<String, MetricDelta> triggers,
  ) {
    final parts = <String>[];
    for (final key in s.rule.triggerKeys) {
      final d = triggers[key];
      if (d == null || !s.matched.contains(d.label)) continue;
      final latest = d.latest.toStringAsFixed(1);
      if (d.improvement < 0.4) {
        parts.add('${d.label} is plateaued at $latest');
      } else {
        parts.add('${d.label} sits at $latest');
      }
    }
    if (parts.isEmpty) {
      return 'Your scan profile aligns with the clinical indications for this procedure.';
    }
    return '${parts.join(" and ")} — ${s.rule.name} directly targets ${s.matched.length == 1 ? "this" : "these"} concern${s.matched.length == 1 ? "" : "s"}.';
  }
}

class _ProcedureRule {
  final String name;
  final String category;
  final String mechanism;
  final String tier;
  final List<String> triggerKeys;
  final double threshold; // severity threshold to trigger
  final bool stallSensitive;

  const _ProcedureRule({
    required this.name,
    required this.category,
    required this.mechanism,
    required this.tier,
    required this.triggerKeys,
    required this.threshold,
    this.stallSensitive = false,
  });
}

class _ScoredProcedure {
  final _ProcedureRule rule;
  final double score;
  final List<String> matched;

  const _ScoredProcedure({
    required this.rule,
    required this.score,
    required this.matched,
  });
}

class _BodyMetricSpec {
  final String label;
  final String key;
  final List<String> keys; // raw map keys to read in priority order
  final bool lowerIsBetter;
  // Smallest change considered meaningful (units depend on the metric:
  // lbs for weight, % for body fat, inches/cm for waist, pts for scores).
  final double signSignificance;

  const _BodyMetricSpec(
    this.label,
    this.key,
    this.keys, {
    required this.lowerIsBetter,
    required this.signSignificance,
  });
}
