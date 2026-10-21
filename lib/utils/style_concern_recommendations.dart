/// "Recommended for your style", filtered by the latest scan: style picks
/// whose concern tags match the user's current top concerns, else the
/// general picks for the selected styles.
///
/// Current concerns use the same rule as the home "For your concerns"
/// section (concern_recommendations.dart): redness, pigment, texture and
/// pores whose 0-100 concern value is above elevatedConcernCutoff (texture
/// concern = 100 - texture_smoothness), most elevated first. The
/// metric-based AIProductRecommendationEngine is not used or changed here.
library;

import '../models/scan_history.dart';
import 'concern_recommendations.dart';
import 'last_comparable_pair.dart';
import 'skincare_style_catalog.dart';

/// Style concern tag for each scan concern (SkinConcern.engineKey).
const Map<String, String> styleTagForScanConcern = {
  'redness': 'redness',
  'darkSpots': 'pigment',
  'texture': 'texture',
  'pores': 'pores',
};

/// The latest AI scan's elevated concerns as style tags, most elevated
/// first; empty when there is no AI scan or nothing is elevated.
List<String> currentStyleConcernTags(Iterable<ScanHistoryEntry> scans) {
  final latest = lastComparablePair(scans)?.latest;
  if (latest == null) return const [];
  final elevated = <({String tag, double value})>[];
  for (final concern in skinConcerns) {
    final value = concern.concernValue(latest);
    final tag = styleTagForScanConcern[concern.engineKey];
    if (value == null || tag == null || value <= elevatedConcernCutoff) {
      continue;
    }
    elevated.add((tag: tag, value: value));
  }
  elevated.sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in elevated) e.tag];
}

class StylePicks {
  const StylePicks({required this.products, required this.matchedConcerns});

  final List<StyleProduct> products;

  /// The concerns the picks were matched to; empty for the general
  /// fallback.
  final List<String> matchedConcerns;

  bool get isFallback => matchedConcerns.isEmpty;
}

/// At most this many picks are shown.
const int stylePicksMax = 6;

/// Weight of a primary match on the most elevated concern; each lower
/// concern is worth one step less (see [styleRelevanceScore]).
const int stylePrimaryMatchWeight = 10;

/// Supporting (descriptive) tags that relate to each scan concern. Each
/// adds [styleSupportingMatchWeight], so they only order products within
/// the same primary score and never outrank a primary match.
const Map<String, Set<String>> styleSupportingTagsFor = {
  'redness': {'barrier'},
  'pigment': {'sun', 'radiance'},
  'texture': {'hydration', 'aging'},
  'pores': <String>{},
};

const int styleSupportingMatchWeight = 1;

/// How well [product] fits this scan. [concernTags] are the elevated scan
/// concerns, most elevated first.
///
/// - Primary: for each of the product's tags that is an elevated concern
///   at position i (0 = most elevated) of n, add
///   [stylePrimaryMatchWeight] * (n - i). Matching more elevated concerns
///   adds up, and the most elevated concern weighs most.
/// - Supporting: for each distinct supporting tag related to an elevated
///   concern ([styleSupportingTagsFor]), add [styleSupportingMatchWeight].
///   The most a product can get this way (5) stays below the smallest
///   primary match (10).
///
/// 0 means the product is not relevant to this scan.
int styleRelevanceScore(StyleProduct product, List<String> concernTags) {
  final n = concernTags.length;
  var score = 0;
  for (final tag in product.concerns.toSet()) {
    final i = concernTags.indexOf(tag);
    if (i >= 0) score += stylePrimaryMatchWeight * (n - i);
  }
  final supporting = {
    for (final concern in concernTags) ...?styleSupportingTagsFor[concern],
  };
  for (final tag in product.concerns.toSet()) {
    if (supporting.contains(tag) && !concernTags.contains(tag)) {
      score += styleSupportingMatchWeight;
    }
  }
  return score;
}

/// Picks for [styles] given the current [concernTags] (elevated scan
/// concerns, most elevated first).
///
/// Every product is scored with [styleRelevanceScore] and the relevant
/// ones (score > 0) are shown highest score first, up to
/// [stylePicksMax]. Ties keep the usual style interleaving (one product
/// per selected style in turn, each in catalog order), so the order is
/// deterministic and every style stays represented among equal scores.
/// Products with no relevant tag are not shown while something is
/// elevated.
///
/// With nothing elevated, or no product matching any elevated concern,
/// the general picks for the styles ([stylePicksMax]), as before.
/// [general] overrides the candidate list (tests).
StylePicks stylePicksFor(
  Set<SkincareStyle> styles,
  List<String> concernTags, {
  List<StyleProduct>? general,
}) {
  final candidates = general ?? styleRecommendations(styles, limit: 1000);
  final hasPrimaryMatch = candidates.any(
    (p) => p.concerns.any(concernTags.contains),
  );
  if (concernTags.isEmpty || !hasPrimaryMatch) {
    return StylePicks(
      products: candidates.take(stylePicksMax).toList(),
      matchedConcerns: const [],
    );
  }
  final scored =
      [
          for (final (index, product) in candidates.indexed)
            (
              index: index,
              product: product,
              score: styleRelevanceScore(product, concernTags),
            ),
        ].where((e) => e.score > 0).toList()
        // Highest score first; ties by interleaved position.
        ..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : a.index.compareTo(b.index);
        });
  final picks = [for (final e in scored.take(stylePicksMax)) e.product];
  return StylePicks(
    products: picks,
    matchedConcerns: [
      for (final tag in concernTags)
        if (picks.any((p) => p.concerns.contains(tag))) tag,
    ],
  );
}
