/// Suggestions for the routine product-name field: common skincare
/// ingredients and product types. Suggestions only; any name can still be
/// typed. Add new entries anywhere in the list.
library;

const List<String> skincareNameSuggestionList = <String>[
  // Ingredients
  'Hyaluronic acid',
  'Niacinamide',
  'Retinol',
  'Retinal',
  'Tretinoin',
  'Vitamin C',
  'Vitamin E',
  'Peptides',
  'Copper peptides',
  'GHK-Cu',
  'Matrixyl',
  'Ceramides',
  'Salicylic acid',
  'Glycolic acid',
  'Lactic acid',
  'Mandelic acid',
  'Azelaic acid',
  'Benzoyl peroxide',
  'Collagen',
  'Centella',
  'Snail mucin',
  'Bakuchiol',
  'Tranexamic acid',
  'Kojic acid',
  'Alpha arbutin',
  'Squalane',
  'Glycerin',
  'Panthenol',
  'Allantoin',
  'Tea tree',
  'Zinc',
  'Zinc oxide',
  'Sulfur',
  'Urea',
  'Licorice root',
  'Green tea',
  'Ferulic acid',
  'Adapalene',
  'PHA',
  // Product types
  'Sunscreen',
  'Mineral sunscreen',
  'Moisturizer',
  'Cleanser',
  'Oil cleanser',
  'Toner',
  'Essence',
  'Serum',
  'Eye cream',
  'Face oil',
  'Exfoliant',
  'Sheet mask',
  'Clay mask',
  'Sleeping mask',
  'Lip balm',
  'Spot treatment',
  'Micellar water',
];

/// Names in [skincareNameSuggestionList] containing [query]
/// (case-insensitive substring), best first: names starting with the query,
/// then names with a word starting with it, then any other match; list
/// order within each group. Empty for a blank query. At most [limit].
List<String> skincareNameSuggestions(
  String query, {
  int limit = 6,
  List<String> names = skincareNameSuggestionList,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const <String>[];
  int rank(String lower) {
    if (lower.startsWith(q)) return 0;
    if (RegExp(
      r'[\s\-]',
    ).allMatches(lower).any((m) => lower.startsWith(q, m.end))) {
      return 1;
    }
    return 2;
  }

  final matches =
      [
        for (final (index, name) in names.indexed)
          if (name.toLowerCase().contains(q))
            (name: name, index: index, rank: rank(name.toLowerCase())),
      ]..sort((a, b) {
        final byRank = a.rank.compareTo(b.rank);
        return byRank != 0 ? byRank : a.index.compareTo(b.index);
      });
  return [for (final m in matches.take(limit)) m.name];
}
