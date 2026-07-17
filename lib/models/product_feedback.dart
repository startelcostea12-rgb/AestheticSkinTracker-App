// lib/models/product_feedback.dart
//
// User-logged feedback for a tracked skincare product, plus the AI-derived
// rating / summary / compatibility warnings computed at the time of logging.
//
// Persisted via [AppPrefs] under the `product_feedback_entries` key in the
// same `setStringList(jsonEncode(...))` pattern used for TrackedProduct.

class ProductFeedbackEntry {
  final String id;
  final String productId;
  final String productName;
  final DateTime date;

  // ── User responses (0–10 each) ────────────────────────────────────────────
  /// 0 = none, 10 = severe irritation / stinging / burning.
  final int irritation;

  /// 0 = very dry / tight, 10 = optimally hydrated and comfortable.
  final int hydration;

  /// 0 = no change, 10 = dramatic texture improvement.
  final int textureImprovement;

  /// 0 = none, 10 = severe redness / flushing.
  final int redness;

  /// 0 = strongly dislike, 10 = love it.
  final int satisfaction;

  /// Optional free-text impressions.
  final String notes;

  // ── AI-derived analysis (computed at submit time) ─────────────────────────
  /// Composite 0–10 product score blending the five user responses.
  final double aiRating;

  /// Short plain-language summary of how the product is performing for the user.
  final String aiSummary;

  /// Compatibility warnings flagged against the user's other active products.
  final List<String> compatibilityWarnings;

  /// Suggested pairings, swaps, or routine adjustments.
  final List<String> pairingSuggestions;

  /// Evidence-based natural / clean alternatives surfaced when relevant
  /// (e.g. bakuchiol as a retinol alternative for irritated skin).
  final List<String> naturalAlternatives;

  const ProductFeedbackEntry({
    required this.id,
    required this.productId,
    required this.productName,
    required this.date,
    required this.irritation,
    required this.hydration,
    required this.textureImprovement,
    required this.redness,
    required this.satisfaction,
    this.notes = '',
    required this.aiRating,
    required this.aiSummary,
    this.compatibilityWarnings = const [],
    this.pairingSuggestions = const [],
    this.naturalAlternatives = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'productName': productName,
    'date': date.toIso8601String(),
    'irritation': irritation,
    'hydration': hydration,
    'textureImprovement': textureImprovement,
    'redness': redness,
    'satisfaction': satisfaction,
    'notes': notes,
    'aiRating': aiRating,
    'aiSummary': aiSummary,
    'compatibilityWarnings': compatibilityWarnings,
    'pairingSuggestions': pairingSuggestions,
    'naturalAlternatives': naturalAlternatives,
  };

  factory ProductFeedbackEntry.fromJson(Map<String, dynamic> json) {
    List<String> stringList(dynamic raw) {
      if (raw is List) {
        return raw.whereType<String>().toList();
      }
      return const [];
    }

    return ProductFeedbackEntry(
      id: json['id'] as String,
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      irritation: (json['irritation'] as num?)?.toInt() ?? 0,
      hydration: (json['hydration'] as num?)?.toInt() ?? 5,
      textureImprovement: (json['textureImprovement'] as num?)?.toInt() ?? 5,
      redness: (json['redness'] as num?)?.toInt() ?? 0,
      satisfaction: (json['satisfaction'] as num?)?.toInt() ?? 5,
      notes: json['notes'] as String? ?? '',
      aiRating: (json['aiRating'] as num?)?.toDouble() ?? 0.0,
      aiSummary: json['aiSummary'] as String? ?? '',
      compatibilityWarnings: stringList(json['compatibilityWarnings']),
      pairingSuggestions: stringList(json['pairingSuggestions']),
      naturalAlternatives: stringList(json['naturalAlternatives']),
    );
  }
}
