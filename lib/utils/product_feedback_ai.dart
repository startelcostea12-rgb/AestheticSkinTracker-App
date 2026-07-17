// lib/utils/product_feedback_ai.dart
//
// Heuristic AI analysis layer for the Product Feedback feature.
// Generates a composite 0–10 rating, a short clinical summary, and
// compatibility warnings + pairing suggestions based on the active
// skincare stack and (when available) the user's most recent scan
// metrics.
//
// Disclaimer: this is on-device heuristic guidance, not medical advice.

import '../models/product_tracker.dart';
import '../models/scan_history.dart';
import 'natural_skincare.dart';

/// Raw user responses captured by the feedback form.
class ProductFeedbackResponses {
  final int irritation; // 0–10, higher = worse
  final int hydration; // 0–10, higher = better
  final int textureImprovement; // 0–10, higher = better
  final int redness; // 0–10, higher = worse
  final int satisfaction; // 0–10, higher = better
  final String notes;

  const ProductFeedbackResponses({
    required this.irritation,
    required this.hydration,
    required this.textureImprovement,
    required this.redness,
    required this.satisfaction,
    this.notes = '',
  });
}

/// Result of the AI analysis for one feedback submission.
class ProductFeedbackAiResult {
  final double rating; // 0.0–10.0 composite score
  final String summary;
  final List<String> compatibilityWarnings;
  final List<String> pairingSuggestions;

  /// Evidence-based natural / clean alternatives surfaced when relevant
  /// (rendered as a dedicated "Natural Alternatives" subsection).
  final List<String> naturalAlternatives;

  const ProductFeedbackAiResult({
    required this.rating,
    required this.summary,
    required this.compatibilityWarnings,
    required this.pairingSuggestions,
    this.naturalAlternatives = const [],
  });
}

/// Pure-Dart, on-device analyzer. No network calls.
class ProductFeedbackAnalyzer {
  /// Analyze a single feedback submission for [product] in the context of
  /// the user's [otherActiveProducts] (used to detect ingredient
  /// interactions) and optionally the latest [scanMetrics].
  static ProductFeedbackAiResult analyze({
    required TrackedProduct product,
    required ProductFeedbackResponses responses,
    List<TrackedProduct> otherActiveProducts = const [],
    SkinMetrics? scanMetrics,
  }) {
    final rating = _computeRating(responses, scanMetrics);
    final summary = _composeSummary(product, responses, rating);
    final warnings = _detectCompatibilityWarnings(
      product,
      otherActiveProducts,
      responses,
    );
    final pairings = _suggestPairings(
      product,
      otherActiveProducts,
      responses,
      scanMetrics,
    );

    // Natural / clean alternatives + natural-specific warnings.
    final stackTexts = <String>[
      '${product.name} ${product.brand} ${product.keyIngredients} ${product.notes}',
      for (final p in otherActiveProducts)
        '${p.name} ${p.brand} ${p.keyIngredients} ${p.notes}',
    ];
    final naturalAlternatives = NaturalSkincareAdvisor.suggestAlternatives(
      stackTexts: stackTexts,
      recentIrritation: responses.irritation,
      recentRedness: responses.redness,
      sensitiveSkin: responses.irritation >= 5 || responses.redness >= 5,
    );
    final naturalWarnings = NaturalSkincareAdvisor.compatibilityWarnings(
      stackTexts: stackTexts,
      sensitiveSkin: responses.irritation >= 5,
      rosaceaProne: responses.redness >= 6,
      recentIrritation: responses.irritation,
      recentRedness: responses.redness,
    );
    final mergedWarnings = <String>[
      ...warnings,
      for (final w in naturalWarnings)
        if (!warnings.contains(w)) w,
    ];

    return ProductFeedbackAiResult(
      rating: rating,
      summary: summary,
      compatibilityWarnings: mergedWarnings,
      pairingSuggestions: pairings,
      naturalAlternatives: naturalAlternatives,
    );
  }

  // ── Rating ────────────────────────────────────────────────────────────────

  static double _computeRating(
    ProductFeedbackResponses r,
    SkinMetrics? metrics,
  ) {
    // Positive contributors (0–10 higher = better).
    final hyd = r.hydration.toDouble();
    final tex = r.textureImprovement.toDouble();
    final sat = r.satisfaction.toDouble();

    // Negative contributors (invert).
    final irrInv = (10 - r.irritation).toDouble();
    final redInv = (10 - r.redness).toDouble();

    // Weighted blend. Satisfaction dominates because it's the user's
    // holistic verdict. Tolerability (irritation/redness) is heavily
    // weighted because a product that triggers reactivity is rarely worth
    // continuing regardless of cosmetic outcome.
    final composite =
        (sat * 0.30) +
        (irrInv * 0.22) +
        (redInv * 0.18) +
        (hyd * 0.15) +
        (tex * 0.15);

    // Gentle nudge from current scan: if the user's redness is high and
    // the product is well-tolerated, reward it slightly.
    double adj = 0;
    if (metrics != null) {
      if (metrics.redness >= 7 && r.irritation <= 3 && r.redness <= 3) {
        adj += 0.3;
      }
      if (metrics.texture >= 7 && r.textureImprovement >= 6) {
        adj += 0.2;
      }
    }

    final score = (composite + adj).clamp(0.0, 10.0);
    // Round to one decimal place for display (e.g. 8.4 / 10).
    return (score * 10).round() / 10;
  }

  // ── Summary ───────────────────────────────────────────────────────────────

  static String _composeSummary(
    TrackedProduct product,
    ProductFeedbackResponses r,
    double rating,
  ) {
    final tone = rating >= 8.5
        ? 'excellent'
        : rating >= 7.0
        ? 'strong'
        : rating >= 5.5
        ? 'mixed'
        : rating >= 3.5
        ? 'underperforming'
        : 'poor';

    final parts = <String>[];
    parts.add(
      '${product.name} is showing a $tone response in your routine right now.',
    );

    if (r.irritation >= 7 || r.redness >= 7) {
      parts.add(
        'You\'re reporting notable irritation or flushing — consider reducing frequency or pulling the product for a 7-day reset.',
      );
    } else if (r.irritation >= 4 || r.redness >= 4) {
      parts.add(
        'Mild reactivity is present. Buffer with a ceramide moisturizer and watch over the next week.',
      );
    } else {
      parts.add('Tolerability is good — no significant reactivity logged.');
    }

    if (r.hydration <= 3) {
      parts.add('Hydration feels low — layer in a humectant before applying.');
    } else if (r.hydration >= 7) {
      parts.add('Barrier hydration feels well supported.');
    }

    if (r.textureImprovement >= 7) {
      parts.add('Texture and surface quality are improving meaningfully.');
    } else if (r.textureImprovement >= 4) {
      parts.add(
        'Texture is trending upward but may need 4–8 more weeks to show clearly.',
      );
    } else {
      parts.add(
        'Texture improvement is minimal so far — give the routine 8–12 weeks at full compliance before reassessing.',
      );
    }

    return parts.join(' ');
  }

  // ── Compatibility warnings ────────────────────────────────────────────────

  /// Detect well-known ingredient interactions that are worth flagging.
  /// Conservative — only fires when both ingredients are present in the
  /// active stack.
  static List<String> _detectCompatibilityWarnings(
    TrackedProduct subject,
    List<TrackedProduct> others,
    ProductFeedbackResponses r,
  ) {
    final stack = <TrackedProduct>[subject, ...others];
    final corpus = stack
        .map(
          (p) => '${p.name} ${p.brand} ${p.keyIngredients} ${p.notes}'
              .toLowerCase(),
        )
        .toList();

    bool stackHas(List<String> keywords) {
      for (final c in corpus) {
        for (final k in keywords) {
          if (c.contains(k)) return true;
        }
      }
      return false;
    }

    final hasRetinoid = stackHas([
      'retinol',
      'retinal',
      'retinaldehyde',
      'retinoic',
      'tretinoin',
      'adapalene',
      'differin',
      'tazarotene',
      'retin-a',
      'retin a',
    ]);
    final hasAha = stackHas([
      'glycolic',
      'lactic',
      'mandelic',
      'aha',
      'alpha hydroxy',
    ]);
    final hasBha = stackHas(['salicylic', 'bha', 'beta hydroxy']);
    final hasBpo = stackHas(['benzoyl peroxide', 'bpo']);
    final hasVitC = stackHas([
      'ascorbic',
      'vitamin c',
      'l-ascorbic',
      'ascorbyl',
    ]);
    final hasNiacinamide = stackHas(['niacinamide', 'nicotinamide']);
    final hasPeptides = stackHas(['peptide', 'matrixyl', 'argireline']);
    final hasFragrance = stackHas([
      'fragrance',
      'parfum',
      'essential oil',
      'limonene',
      'linalool',
    ]);

    final warnings = <String>[];

    if (hasRetinoid && hasAha) {
      warnings.add(
        'Retinoid + AHA in the same routine can stack irritation. Alternate nights (retinoid one evening, AHA the next) rather than layering.',
      );
    }
    if (hasRetinoid && hasBha) {
      warnings.add(
        'Retinoid + BHA together often compromises the barrier. Consider BHA in the AM and retinoid in the PM, or alternate evenings.',
      );
    }
    if (hasRetinoid && hasBpo) {
      warnings.add(
        'Most retinoids (especially tretinoin) are inactivated by benzoyl peroxide if applied together. Separate by 12 hours — BPO in the morning, retinoid at night.',
      );
    }
    if (hasVitC && hasRetinoid) {
      warnings.add(
        'Vitamin C and retinoids are most stable when split AM (vitamin C) and PM (retinoid). Layering them sometimes increases stinging.',
      );
    }
    if (hasAha && hasBha) {
      warnings.add(
        'AHA + BHA on the same day can over-exfoliate. Alternate days or stick to one acid family at a time.',
      );
    }
    if (hasBpo && hasAha) {
      warnings.add(
        'Benzoyl peroxide + AHA can dry the skin quickly. Watch for stinging and pull back to alternating days if reactivity climbs.',
      );
    }
    if (hasFragrance && (r.irritation >= 5 || r.redness >= 5)) {
      warnings.add(
        'A product in your stack contains fragrance or essential oils, which commonly drive the reactivity you\'re reporting. Try a 2-week fragrance-free trial.',
      );
    }
    if (hasNiacinamide && hasVitC && r.irritation >= 6) {
      warnings.add(
        'Modern formulations of niacinamide and vitamin C are generally compatible, but at high concentrations some users see flushing. Try spacing them 30 minutes apart.',
      );
    }
    if (hasPeptides && hasAha) {
      warnings.add(
        'Acidic environments can hydrolyze copper peptides and weaken signal peptides. Apply peptides on non-AHA nights for best results.',
      );
    }

    return warnings;
  }

  // ── Pairings & alternatives ───────────────────────────────────────────────

  static List<String> _suggestPairings(
    TrackedProduct subject,
    List<TrackedProduct> others,
    ProductFeedbackResponses r,
    SkinMetrics? metrics,
  ) {
    final stack = <TrackedProduct>[subject, ...others];
    final corpus = stack
        .map(
          (p) => '${p.name} ${p.brand} ${p.keyIngredients} ${p.notes}'
              .toLowerCase(),
        )
        .toList();

    bool stackHas(List<String> keywords) {
      for (final c in corpus) {
        for (final k in keywords) {
          if (c.contains(k)) return true;
        }
      }
      return false;
    }

    final hasCeramide = stackHas(['ceramide']);
    final hasHA = stackHas(['hyaluronic', 'sodium hyaluronate']);
    final hasNiacinamide = stackHas(['niacinamide', 'nicotinamide']);
    final hasSpf = stackHas(['spf', 'sunscreen', 'zinc oxide', 'titanium']);
    final hasRetinoid = stackHas([
      'retinol',
      'retinal',
      'tretinoin',
      'adapalene',
      'tazarotene',
    ]);
    final hasAzelaic = stackHas(['azelaic']);

    final tips = <String>[];

    if (r.irritation >= 5 && !hasCeramide) {
      tips.add(
        'Add a ceramide-rich moisturizer (look for ceramide NP/AP/EOP + cholesterol) to buffer reactivity within 7 days.',
      );
    }
    if (r.hydration <= 4 && !hasHA) {
      tips.add(
        'Layer a hyaluronic acid serum on damp skin before your moisturizer to restore comfort.',
      );
    }
    if (r.redness >= 5 && !hasAzelaic && !hasNiacinamide) {
      tips.add(
        'Niacinamide 4% or azelaic acid 10% can calm visible redness over 4–6 weeks without aggravating sensitive skin.',
      );
    }
    if (hasRetinoid && !hasSpf) {
      tips.add(
        'Daily mineral SPF 30+ is non-negotiable while using a retinoid — photosensitivity persists for the duration of treatment.',
      );
    }
    if (metrics != null && metrics.darkSpots >= 6 && !hasVitCInStack(corpus)) {
      tips.add(
        'A morning antioxidant (10–15% L-ascorbic acid or a stable derivative) pairs well with your current routine to target pigment.',
      );
    }
    if (r.satisfaction <= 4 && r.irritation <= 3 && r.textureImprovement <= 3) {
      tips.add(
        'If you don\'t see meaningful change by week 12 at consistent use, consider stepping up to a stronger active class (e.g., move from retinol to adapalene 0.1%).',
      );
    }
    if (r.satisfaction >= 8 && r.irritation <= 3) {
      tips.add(
        'This product is performing well for you — keep it as a routine anchor and avoid stacking new actives that could destabilize the response.',
      );
    }

    return tips;
  }

  static bool hasVitCInStack(List<String> corpus) {
    for (final c in corpus) {
      if (c.contains('ascorbic') ||
          c.contains('vitamin c') ||
          c.contains('ascorbyl')) {
        return true;
      }
    }
    return false;
  }
}
