/// Style-based skincare picks: the user's preferred skincare styles (asked
/// in onboarding, editable in Settings) and a short curated list per style.
/// Separate from the metric-based AIProductRecommendationEngine, which is
/// unchanged. Names and one-line descriptions only -- no ingredient
/// analysis, no claims about a user's skin.
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

class StyleProduct {
  const StyleProduct(this.name, this.description, this.style);

  final String name;
  final String description;
  final SkincareStyle style;
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
    ),
    StyleProduct(
      'Beauty of Joseon Relief Sun: Rice + Probiotics SPF50+',
      'Lightweight daily sunscreen',
      SkincareStyle.korean,
    ),
    StyleProduct(
      'Anua Heartleaf 77% Soothing Toner',
      'Calming for redness and sensitivity',
      SkincareStyle.korean,
    ),
    StyleProduct(
      'Some By Mi AHA BHA PHA 30 Days Miracle Toner',
      'Gentle exfoliation',
      SkincareStyle.korean,
    ),
    StyleProduct(
      'Laneige Water Sleeping Mask',
      'Overnight hydration',
      SkincareStyle.korean,
    ),
    StyleProduct(
      'Innisfree Green Tea Seed Serum',
      'Lightweight moisture',
      SkincareStyle.korean,
    ),
    StyleProduct(
      'Round Lab Birch Juice Moisturizing Cream',
      'Light barrier cream',
      SkincareStyle.korean,
    ),
    StyleProduct(
      'Torriden Dive-In Low Molecular Hyaluronic Acid Serum',
      'Deep hydration',
      SkincareStyle.korean,
    ),
    StyleProduct(
      'Isntree Hyaluronic Acid Watery Sun Gel',
      'Hydrating sunscreen',
      SkincareStyle.korean,
    ),
    StyleProduct(
      'Purito Centella Unscented Serum',
      'Soothing and barrier repair',
      SkincareStyle.korean,
    ),
  ],
  SkincareStyle.naturalClean: [
    StyleProduct(
      'Youth To The People Superfood Cleanser',
      'Gentle daily cleanse',
      SkincareStyle.naturalClean,
    ),
    StyleProduct(
      'Biossance Squalane + Omega Repair Cream',
      'Barrier and moisture',
      SkincareStyle.naturalClean,
    ),
    StyleProduct(
      'The Ordinary Niacinamide 10% + Zinc 1%',
      'Simple, transparent formula',
      SkincareStyle.naturalClean,
    ),
    StyleProduct(
      'Herbivore Botanicals Pink Cloud Cream',
      'Soft, plant-based moisturizer',
      SkincareStyle.naturalClean,
    ),
    StyleProduct(
      'True Botanicals Pure Radiance Oil',
      'Nourishing facial oil',
      SkincareStyle.naturalClean,
    ),
    StyleProduct(
      'Tata Harper Regenerating Cleanser',
      'Clean, effective cleanse',
      SkincareStyle.naturalClean,
    ),
    StyleProduct(
      'Cocokind Ceramide Barrier Serum',
      'Barrier support',
      SkincareStyle.naturalClean,
    ),
    StyleProduct(
      'Farmacy Green Clean Makeup Removing Balm',
      'Gentle cleansing balm',
      SkincareStyle.naturalClean,
    ),
    StyleProduct(
      'Summer Fridays Jet Lag Mask',
      'Hydrating overnight mask',
      SkincareStyle.naturalClean,
    ),
    StyleProduct(
      'Versed Press Restart Gentle Retinol Serum',
      'Clean retinoid option',
      SkincareStyle.naturalClean,
    ),
  ],
  SkincareStyle.westernDrugstore: [
    StyleProduct(
      'CeraVe Moisturizing Cream',
      'Ceramide barrier repair',
      SkincareStyle.westernDrugstore,
    ),
    StyleProduct(
      'La Roche-Posay Toleriane Double Repair Moisturizer',
      'Gentle daily moisturizer',
      SkincareStyle.westernDrugstore,
    ),
    StyleProduct(
      'Paula’s Choice 2% BHA Liquid Exfoliant',
      'Pore and texture improvement',
      SkincareStyle.westernDrugstore,
    ),
    StyleProduct(
      'Neutrogena Hydro Boost Water Gel',
      'Lightweight hydration',
      SkincareStyle.westernDrugstore,
    ),
    StyleProduct(
      'Vanicream Moisturizing Cream',
      'Minimal-ingredient option',
      SkincareStyle.westernDrugstore,
    ),
    StyleProduct(
      'Cetaphil Gentle Skin Cleanser',
      'Simple, non-stripping cleanse',
      SkincareStyle.westernDrugstore,
    ),
    StyleProduct(
      'CeraVe Hydrating Cleanser',
      'Non-foaming cleanse',
      SkincareStyle.westernDrugstore,
    ),
    StyleProduct(
      'La Roche-Posay Anthelios Melt-in Milk Sunscreen SPF 60',
      'Reliable daily SPF',
      SkincareStyle.westernDrugstore,
    ),
    StyleProduct(
      'Neutrogena Rapid Wrinkle Repair Retinol',
      'Accessible retinoid',
      SkincareStyle.westernDrugstore,
    ),
    StyleProduct(
      'Aveeno Calm + Restore Oat Gel Moisturizer',
      'Soothing moisturizer',
      SkincareStyle.westernDrugstore,
    ),
  ],
  SkincareStyle.clinical: [
    StyleProduct(
      'SkinCeuticals C E Ferulic',
      'Antioxidant serum',
      SkincareStyle.clinical,
    ),
    StyleProduct(
      'SkinCeuticals Triple Lipid Restore',
      'Barrier repair',
      SkincareStyle.clinical,
    ),
    StyleProduct(
      'Alastin Restorative Skin Complex',
      'Collagen support',
      SkincareStyle.clinical,
    ),
    StyleProduct(
      'ZO Skin Health Daily Power Defense',
      'Antioxidant and repair',
      SkincareStyle.clinical,
    ),
    StyleProduct(
      'Obagi Nu-Derm',
      'Pigment and texture system',
      SkincareStyle.clinical,
    ),
    StyleProduct(
      'Differin Gel (adapalene)',
      'Over-the-counter retinoid',
      SkincareStyle.clinical,
    ),
    StyleProduct(
      'SkinCeuticals HA Intensifier',
      'Hyaluronic acid booster',
      SkincareStyle.clinical,
    ),
    StyleProduct(
      'Alastin Regenerating Skin Nectar',
      'Post-procedure recovery',
      SkincareStyle.clinical,
    ),
    StyleProduct(
      'ZO Skin Health Growth Factor Serum',
      'Repair and renewal',
      SkincareStyle.clinical,
    ),
    StyleProduct(
      'Revision Skincare C+ Correcting Complex 30%',
      'Strong vitamin C',
      SkincareStyle.clinical,
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
