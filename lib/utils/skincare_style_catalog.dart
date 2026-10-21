/// Style-based skincare picks: the user's preferred skincare styles (asked
/// in onboarding, editable in Settings) and a short curated list per style.
/// Separate from the metric-based AIProductRecommendationEngine, which is
/// unchanged. Each product has a name, brand, one-line reason, category and
/// the concerns it is generally used for (style_concern_recommendations.dart
/// matches those to the latest scan) -- no ingredient analysis, no claims
/// about a user's skin.
library;

import 'dart:convert';

import 'app_prefs.dart';

enum SkincareStyle { korean, naturalClean, westernDrugstore, clinical }

extension SkincareStyleInfo on SkincareStyle {
  /// Stable id stored in preferences.
  String get id => switch (this) {
    SkincareStyle.korean => 'korean',
    SkincareStyle.naturalClean => 'natural_clean',
    SkincareStyle.westernDrugstore => 'western_drugstore',
    SkincareStyle.clinical => 'clinical',
  };

  String get label => switch (this) {
    SkincareStyle.korean => 'Korean',
    SkincareStyle.naturalClean => 'Natural / Clean',
    SkincareStyle.westernDrugstore => 'Western / Drugstore',
    SkincareStyle.clinical => 'Clinical',
  };
}

/// Product type for a style pick.
enum StyleProductCategory { cleanser, serum, moisturizer, spf, treatment }

extension StyleProductCategoryInfo on StyleProductCategory {
  String get label => switch (this) {
    StyleProductCategory.cleanser => 'Cleanser',
    StyleProductCategory.serum => 'Serum',
    StyleProductCategory.moisturizer => 'Moisturizer',
    StyleProductCategory.spf => 'SPF',
    StyleProductCategory.treatment => 'Treatment',
  };
}

/// Concern tags a style product can match. The first four correspond to
/// the scan concerns shown in "For your concerns"; the rest only describe
/// the product.
const Set<String> styleConcernTags = {
  'redness',
  'pigment',
  'texture',
  'pores',
  'hydration',
  'barrier',
  'aging',
};

class StyleProduct {
  const StyleProduct(
    this.name,
    this.description,
    this.style, {
    required this.brand,
    required this.category,
    this.concerns = const [],
  });

  final String name;

  /// Short reason (one line), as written for the catalog.
  final String description;
  final SkincareStyle style;
  final String brand;
  final StyleProductCategory category;

  /// What the product is generally used for (styleConcernTags); empty for
  /// general products such as plain cleansers.
  final List<String> concerns;

  String get reason => description;
}

const String skincareStyleQuestion = 'What type of skincare do you prefer?';

/// AppPrefs key holding the selected style ids as a JSON list.
const String skincareStylePreferenceKey = 'skincare_style_preferences';

const Map<SkincareStyle, List<StyleProduct>> skincareStyleCatalog = {
  SkincareStyle.korean: [
    StyleProduct(
      'COSRX Advanced Snail 96 Mucin Power Essence',
      'Hydration and barrier support',
      SkincareStyle.korean,
      brand: 'COSRX',
      category: StyleProductCategory.serum,
      concerns: ['hydration', 'barrier', 'texture'],
    ),
    StyleProduct(
      'Beauty of Joseon Relief Sun: Rice + Probiotics SPF50+',
      'Lightweight daily sunscreen',
      SkincareStyle.korean,
      brand: 'Beauty of Joseon',
      category: StyleProductCategory.spf,
      concerns: ['pigment'],
    ),
    StyleProduct(
      'Anua Heartleaf 77% Soothing Toner',
      'Calming for redness and sensitivity',
      SkincareStyle.korean,
      brand: 'Anua',
      category: StyleProductCategory.treatment,
      concerns: ['redness', 'barrier'],
    ),
    StyleProduct(
      'Some By Mi AHA BHA PHA 30 Days Miracle Toner',
      'Gentle exfoliation',
      SkincareStyle.korean,
      brand: 'Some By Mi',
      category: StyleProductCategory.treatment,
      concerns: ['texture', 'pores'],
    ),
    StyleProduct(
      'Laneige Water Sleeping Mask',
      'Overnight hydration',
      SkincareStyle.korean,
      brand: 'Laneige',
      category: StyleProductCategory.moisturizer,
      concerns: ['hydration'],
    ),
    StyleProduct(
      'Innisfree Green Tea Seed Serum',
      'Lightweight moisture',
      SkincareStyle.korean,
      brand: 'Innisfree',
      category: StyleProductCategory.serum,
      concerns: ['hydration'],
    ),
    StyleProduct(
      'Round Lab Birch Juice Moisturizing Cream',
      'Light barrier cream',
      SkincareStyle.korean,
      brand: 'Round Lab',
      category: StyleProductCategory.moisturizer,
      concerns: ['hydration', 'barrier'],
    ),
    StyleProduct(
      'Torriden Dive-In Low Molecular Hyaluronic Acid Serum',
      'Deep hydration',
      SkincareStyle.korean,
      brand: 'Torriden',
      category: StyleProductCategory.serum,
      concerns: ['hydration', 'texture'],
    ),
    StyleProduct(
      'Isntree Hyaluronic Acid Watery Sun Gel',
      'Hydrating sunscreen',
      SkincareStyle.korean,
      brand: 'Isntree',
      category: StyleProductCategory.spf,
      concerns: ['pigment', 'hydration'],
    ),
    StyleProduct(
      'Purito Centella Unscented Serum',
      'Soothing and barrier repair',
      SkincareStyle.korean,
      brand: 'Purito',
      category: StyleProductCategory.serum,
      concerns: ['redness', 'barrier'],
    ),
  ],
  SkincareStyle.naturalClean: [
    StyleProduct(
      'Youth To The People Superfood Cleanser',
      'Gentle daily cleanse',
      SkincareStyle.naturalClean,
      brand: 'Youth To The People',
      category: StyleProductCategory.cleanser,
      concerns: [],
    ),
    StyleProduct(
      'Biossance Squalane + Omega Repair Cream',
      'Barrier and moisture',
      SkincareStyle.naturalClean,
      brand: 'Biossance',
      category: StyleProductCategory.moisturizer,
      concerns: ['barrier', 'hydration'],
    ),
    StyleProduct(
      'The Ordinary Niacinamide 10% + Zinc 1%',
      'Simple, transparent formula',
      SkincareStyle.naturalClean,
      brand: 'The Ordinary',
      category: StyleProductCategory.serum,
      concerns: ['pores', 'texture'],
    ),
    StyleProduct(
      'Herbivore Botanicals Pink Cloud Cream',
      'Soft, plant-based moisturizer',
      SkincareStyle.naturalClean,
      brand: 'Herbivore Botanicals',
      category: StyleProductCategory.moisturizer,
      concerns: ['hydration'],
    ),
    StyleProduct(
      'True Botanicals Pure Radiance Oil',
      'Nourishing facial oil',
      SkincareStyle.naturalClean,
      brand: 'True Botanicals',
      category: StyleProductCategory.moisturizer,
      concerns: ['hydration', 'barrier'],
    ),
    StyleProduct(
      'Tata Harper Regenerating Cleanser',
      'Clean, effective cleanse',
      SkincareStyle.naturalClean,
      brand: 'Tata Harper',
      category: StyleProductCategory.cleanser,
      concerns: [],
    ),
    StyleProduct(
      'Cocokind Ceramide Barrier Serum',
      'Barrier support',
      SkincareStyle.naturalClean,
      brand: 'Cocokind',
      category: StyleProductCategory.serum,
      concerns: ['barrier'],
    ),
    StyleProduct(
      'Farmacy Green Clean Makeup Removing Balm',
      'Gentle cleansing balm',
      SkincareStyle.naturalClean,
      brand: 'Farmacy',
      category: StyleProductCategory.cleanser,
      concerns: [],
    ),
    StyleProduct(
      'Summer Fridays Jet Lag Mask',
      'Hydrating overnight mask',
      SkincareStyle.naturalClean,
      brand: 'Summer Fridays',
      category: StyleProductCategory.moisturizer,
      concerns: ['hydration'],
    ),
    StyleProduct(
      'Versed Press Restart Gentle Retinol Serum',
      'Clean retinoid option',
      SkincareStyle.naturalClean,
      brand: 'Versed',
      category: StyleProductCategory.treatment,
      concerns: ['texture', 'aging'],
    ),
  ],
  SkincareStyle.westernDrugstore: [
    StyleProduct(
      'CeraVe Moisturizing Cream',
      'Ceramide barrier repair',
      SkincareStyle.westernDrugstore,
      brand: 'CeraVe',
      category: StyleProductCategory.moisturizer,
      concerns: ['barrier', 'hydration'],
    ),
    StyleProduct(
      'La Roche-Posay Toleriane Double Repair Moisturizer',
      'Gentle daily moisturizer',
      SkincareStyle.westernDrugstore,
      brand: 'La Roche-Posay',
      category: StyleProductCategory.moisturizer,
      concerns: ['barrier', 'hydration'],
    ),
    StyleProduct(
      'Paula’s Choice 2% BHA Liquid Exfoliant',
      'Pore and texture improvement',
      SkincareStyle.westernDrugstore,
      brand: 'Paula’s Choice',
      category: StyleProductCategory.treatment,
      concerns: ['pores', 'texture'],
    ),
    StyleProduct(
      'Neutrogena Hydro Boost Water Gel',
      'Lightweight hydration',
      SkincareStyle.westernDrugstore,
      brand: 'Neutrogena',
      category: StyleProductCategory.moisturizer,
      concerns: ['hydration'],
    ),
    StyleProduct(
      'Vanicream Moisturizing Cream',
      'Minimal-ingredient option',
      SkincareStyle.westernDrugstore,
      brand: 'Vanicream',
      category: StyleProductCategory.moisturizer,
      concerns: ['barrier'],
    ),
    StyleProduct(
      'Cetaphil Gentle Skin Cleanser',
      'Simple, non-stripping cleanse',
      SkincareStyle.westernDrugstore,
      brand: 'Cetaphil',
      category: StyleProductCategory.cleanser,
      concerns: [],
    ),
    StyleProduct(
      'CeraVe Hydrating Cleanser',
      'Non-foaming cleanse',
      SkincareStyle.westernDrugstore,
      brand: 'CeraVe',
      category: StyleProductCategory.cleanser,
      concerns: ['barrier'],
    ),
    StyleProduct(
      'La Roche-Posay Anthelios Melt-in Milk Sunscreen SPF 60',
      'Reliable daily SPF',
      SkincareStyle.westernDrugstore,
      brand: 'La Roche-Posay',
      category: StyleProductCategory.spf,
      concerns: ['pigment'],
    ),
    StyleProduct(
      'Neutrogena Rapid Wrinkle Repair Retinol',
      'Accessible retinoid',
      SkincareStyle.westernDrugstore,
      brand: 'Neutrogena',
      category: StyleProductCategory.treatment,
      concerns: ['texture', 'aging'],
    ),
    StyleProduct(
      'Aveeno Calm + Restore Oat Gel Moisturizer',
      'Soothing moisturizer',
      SkincareStyle.westernDrugstore,
      brand: 'Aveeno',
      category: StyleProductCategory.moisturizer,
      concerns: ['redness', 'barrier'],
    ),
  ],
  SkincareStyle.clinical: [
    StyleProduct(
      'SkinCeuticals C E Ferulic',
      'Antioxidant serum',
      SkincareStyle.clinical,
      brand: 'SkinCeuticals',
      category: StyleProductCategory.serum,
      concerns: ['pigment', 'aging'],
    ),
    StyleProduct(
      'SkinCeuticals Triple Lipid Restore',
      'Barrier support cream',
      SkincareStyle.clinical,
      brand: 'SkinCeuticals',
      category: StyleProductCategory.moisturizer,
      concerns: ['barrier', 'aging'],
    ),
    StyleProduct(
      'Alastin Restorative Skin Complex',
      'Peptide-based serum',
      SkincareStyle.clinical,
      brand: 'Alastin',
      category: StyleProductCategory.serum,
      concerns: ['texture', 'aging'],
    ),
    StyleProduct(
      'ZO Skin Health Daily Power Defense',
      'Daily antioxidant serum',
      SkincareStyle.clinical,
      brand: 'ZO Skin Health',
      category: StyleProductCategory.serum,
      concerns: ['aging', 'texture'],
    ),
    StyleProduct(
      'Obagi Nu-Derm',
      'Prescription pigment system (consult a provider)',
      SkincareStyle.clinical,
      brand: 'Obagi',
      category: StyleProductCategory.treatment,
      concerns: ['pigment'],
    ),
    StyleProduct(
      'Differin Gel (adapalene)',
      'Over-the-counter retinoid',
      SkincareStyle.clinical,
      brand: 'Differin',
      category: StyleProductCategory.treatment,
      concerns: ['texture', 'pores'],
    ),
    StyleProduct(
      'SkinCeuticals HA Intensifier',
      'Hyaluronic acid serum',
      SkincareStyle.clinical,
      brand: 'SkinCeuticals',
      category: StyleProductCategory.serum,
      concerns: ['hydration'],
    ),
    StyleProduct(
      'Alastin Regenerating Skin Nectar',
      'Post-procedure serum',
      SkincareStyle.clinical,
      brand: 'Alastin',
      category: StyleProductCategory.serum,
      concerns: ['barrier'],
    ),
    StyleProduct(
      'ZO Skin Health Growth Factor Serum',
      'Peptide serum',
      SkincareStyle.clinical,
      brand: 'ZO Skin Health',
      category: StyleProductCategory.serum,
      concerns: ['aging', 'texture'],
    ),
    StyleProduct(
      'Revision Skincare C+ Correcting Complex 30%',
      'Vitamin C serum',
      SkincareStyle.clinical,
      brand: 'Revision Skincare',
      category: StyleProductCategory.serum,
      concerns: ['pigment', 'aging'],
    ),
  ],
};

/// Top picks for [styles]: with one style, its list in order; with several,
/// the lists interleaved one product per style at a time (in catalog
/// order), so every selected style is represented. Up to [limit].
List<StyleProduct> styleRecommendations(
  Iterable<SkincareStyle> styles, {
  int limit = 8,
}) {
  final ordered = SkincareStyle.values.where(styles.contains).toList();
  if (ordered.isEmpty || limit <= 0) return const <StyleProduct>[];
  final out = <StyleProduct>[];
  for (var round = 0; out.length < limit; round++) {
    var added = false;
    for (final style in ordered) {
      final list = skincareStyleCatalog[style]!;
      if (round < list.length && out.length < limit) {
        out.add(list[round]);
        added = true;
      }
    }
    if (!added) break;
  }
  return out;
}

Future<Set<SkincareStyle>> loadSkincareStyles() async {
  final raw = await AppPrefs.getString(skincareStylePreferenceKey);
  if (raw == null || raw.trim().isEmpty) return <SkincareStyle>{};
  try {
    final ids = (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    return {
      for (final style in SkincareStyle.values)
        if (ids.contains(style.id)) style,
    };
  } catch (_) {
    return <SkincareStyle>{};
  }
}

Future<void> saveSkincareStyles(Set<SkincareStyle> styles) =>
    AppPrefs.setString(
      skincareStylePreferenceKey,
      jsonEncode([
        for (final style in SkincareStyle.values)
          if (styles.contains(style)) style.id,
      ]),
    );
