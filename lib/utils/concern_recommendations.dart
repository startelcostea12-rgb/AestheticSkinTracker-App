/// "For your redness / pigment / texture / pores": the metric-based
/// product recommendations grouped by concern, from the latest comparable
/// AI scan (lastComparablePair with a baseline).
///
/// - A concern is shown when its 0-100 concern value is above
///   [elevatedConcernCutoff] (texture concern = 100 - texture_smoothness).
/// - The value is passed to the recommendation engine on its 0-10 scale,
///   the inverse of ScanHistoryEntry.migrateMetricsForLuxe (concern / 10).
/// - Products and their order come from
///   AIProductRecommendationEngine.productsForConcern.
library;

import '../models/scan_history.dart';
import 'ai_product_recommendation_engine.dart';
import 'last_comparable_pair.dart';

/// A concern is shown above this value on the scan's 0-100 scale. Set so
/// groups appear at realistic scan values (the progress report's "> 6.0"
/// userSkinConcerns rule, i.e. 60, almost never matched real AI scans).
const double elevatedConcernCutoff = 25.0;

class SkinConcern {
  const SkinConcern({
    required this.metricKey,
    required this.engineKey,
    required this.heading,
    this.higherIsBetter = false,
  });

  /// Key in the scan's metric_matrix (0-100).
  final String metricKey;

  /// Key in the recommendation engine's product data.
  final String engineKey;
  final String heading;

  /// True when a higher metric value means less concern (smoothness).
  final bool higherIsBetter;

  /// The concern on the scan's 0-100 scale, or null when missing.
  double? concernValue(ScanHistoryEntry scan) {
    final value = scanMetricValue(scan, metricKey);
    if (value == null) return null;
    return (higherIsBetter ? 100 - value : value).clamp(0.0, 100.0).toDouble();
  }

  /// The concern on the engine's 0-10 scale, or null when missing.
  double? concernLevel(ScanHistoryEntry scan) {
    final value = concernValue(scan);
    return value == null ? null : value / 10;
  }
}

const List<SkinConcern> skinConcerns = [
  SkinConcern(
    metricKey: 'localized_redness',
    engineKey: 'redness',
    heading: 'For your redness',
  ),
  SkinConcern(
    metricKey: 'pigment_load',
    engineKey: 'darkSpots',
    heading: 'For your pigment',
  ),
  SkinConcern(
    metricKey: 'texture_smoothness',
    engineKey: 'texture',
    heading: 'For your texture',
    higherIsBetter: true,
  ),
  SkinConcern(
    metricKey: 'pore_visibility',
    engineKey: 'pores',
    heading: 'For your pores',
  ),
];

class ConcernGroup {
  const ConcernGroup({
    required this.concern,
    required this.level,
    required this.products,
  });

  final SkinConcern concern;
  final double level;

  /// Never empty; the first is the engine's pick for [level].
  final List<AIProductRecommendation> products;
}

typedef ConcernProductSource =
    List<AIProductRecommendation> Function(String engineKey, double level);

/// The concern groups for the latest comparable scan, most elevated first.
/// Null when there is no comparable scan (a scan compared against a
/// baseline, without locks); empty when nothing is elevated. Concerns
/// without products are left out.
List<ConcernGroup>? concernGroupsForScans(
  Iterable<ScanHistoryEntry> scans, {
  ConcernProductSource productsFor =
      AIProductRecommendationEngine.productsForConcern,
}) {
  final pair = lastComparablePair(scans);
  if (pair == null || pair.baseline == null) return null;
  final groups = <ConcernGroup>[];
  for (final concern in skinConcerns) {
    final value = concern.concernValue(pair.latest);
    if (value == null || value <= elevatedConcernCutoff) continue;
    final level = value / 10;
    final products = productsFor(concern.engineKey, level);
    if (products.isEmpty) continue;
    groups.add(
      ConcernGroup(concern: concern, level: level, products: products),
    );
  }
  groups.sort((a, b) => b.level.compareTo(a.level));
  return groups;
}
