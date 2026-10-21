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

const int stylePicksMin = 4;
const int stylePicksMax = 6;

/// Picks for [styles] given the current [concernTags] (most important
/// first). Products matching a concern come first, ordered by their best
/// concern then by the usual style interleaving; if fewer than
/// [stylePicksMin] match, general picks fill up to that number. With no
/// match at all, the general picks for the styles ([stylePicksMax]).
StylePicks stylePicksFor(Set<SkincareStyle> styles, List<String> concernTags) {
  final general = styleRecommendations(styles, limit: 1000);
  int rank(StyleProduct p) {
    var best = concernTags.length;
    for (final tag in p.concerns) {
      final i = concernTags.indexOf(tag);
      if (i >= 0 && i < best) best = i;
    }
    return best;
  }

  final matched = [
    for (final p in general)
      if (rank(p) < concernTags.length) p,
  ];
  if (matched.isEmpty) {
    return StylePicks(
      products: general.take(stylePicksMax).toList(),
      matchedConcerns: const [],
    );
  }
  // Stable sort by best concern keeps the interleaved style order.
  final indexed = matched.indexed.toList()
    ..sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
  final picks = [for (final e in indexed) e.$2].take(stylePicksMax).toList();
  for (final p in general) {
    if (picks.length >= stylePicksMin) break;
    if (!picks.contains(p)) picks.add(p);
  }
  return StylePicks(
    products: picks,
    matchedConcerns: [
      for (final tag in concernTags)
        if (matched.any((p) => p.concerns.contains(tag))) tag,
    ],
  );
}
