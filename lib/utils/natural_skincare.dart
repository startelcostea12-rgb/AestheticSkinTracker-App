// lib/utils/natural_skincare.dart
//
// Single source of truth for "Natural / Clean" skincare recognition across
// the app. Used by:
//   • ProductFeedbackAnalyzer  → "Natural Alternatives" subsection + warnings.
//   • Active Skincare Details  → "Natural / Clean" header chip.
//   • AcneRosaceaIntelligence  → natural-focused recommendations + warnings
//                                in the Plan tab.
//
// Detection is fully on-device, evidence-based, and conservative. We tag a
// product as "Natural / Clean" only when at least one well-recognized
// botanical / plant-derived active is present. Ingredients are matched as
// case-insensitive substrings against the product name, brand,
// keyIngredients string, and notes.
//
// Disclaimer: this is supportive guidance, not medical advice. Natural
// ingredients are not automatically safer — see [NaturalSkincareAdvisor]
// for caution patterns (essential oils, tea tree, citrus oils, etc.).

/// One canonical natural / clean ingredient with display metadata and
/// evidence-based clinical notes.
class NaturalIngredient {
  /// Canonical display name (e.g. "Bakuchiol").
  final String name;

  /// Short plain-English use case shown next to the badge.
  final String purpose;

  /// Case-insensitive substrings used for detection. Order does not matter.
  final List<String> keywords;

  /// One-line evidence-based clinical note for AI feedback / tooltips.
  final String evidenceNote;

  const NaturalIngredient({
    required this.name,
    required this.purpose,
    required this.keywords,
    required this.evidenceNote,
  });
}

/// Canonical registry of natural / clean ingredients tracked by the app.
class NaturalIngredientCatalog {
  static const bakuchiol = NaturalIngredient(
    name: 'Bakuchiol',
    purpose: 'Plant-based retinol alternative',
    keywords: ['bakuchiol'],
    evidenceNote:
        'Bakuchiol has shown retinol-like benefits (fine lines, '
        'pigmentation) with significantly less irritation in 12-week '
        'split-face trials (Dhaliwal et al., 2019).',
  );

  static const centella = NaturalIngredient(
    name: 'Centella asiatica (Cica)',
    purpose: 'Calms redness and supports barrier repair',
    keywords: [
      'centella',
      'cica',
      'madecassoside',
      'asiaticoside',
      'tiger grass',
      'gotu kola',
    ],
    evidenceNote:
        'Madecassoside and asiaticoside accelerate wound healing and '
        'reduce TEWL — well-tolerated in rosacea and post-procedure skin.',
  );

  static const teaTree = NaturalIngredient(
    name: 'Tea tree oil',
    purpose: 'Natural anti-bacterial for mild acne',
    keywords: ['tea tree', 'melaleuca'],
    evidenceNote:
        '5% tea tree oil performed comparably to 5% benzoyl peroxide for '
        'mild-to-moderate acne with slower onset and lower irritation '
        '(Bassett et al., 1990). Best in leave-on serums at ≤5%.',
  );

  static const aloeVera = NaturalIngredient(
    name: 'Aloe vera',
    purpose: 'Hydrates and soothes',
    keywords: ['aloe', 'aloe vera', 'aloe barbadensis'],
    evidenceNote:
        'Aloe polysaccharides hydrate and accelerate epidermal recovery '
        '— a barrier-friendly humectant for compromised or sun-exposed skin.',
  );

  static const rosehip = NaturalIngredient(
    name: 'Rosehip seed oil',
    purpose: 'Repairs and brightens',
    keywords: ['rosehip', 'rose hip', 'rosa canina', 'rosa rubiginosa'],
    evidenceNote:
        'Cold-pressed rosehip oil delivers trans-retinoic acid precursors '
        'and linoleic acid that support barrier repair and texture.',
  );

  static const niacinamide = NaturalIngredient(
    name: 'Niacinamide',
    purpose: 'Calms redness and refines pores',
    keywords: ['niacinamide', 'nicotinamide', 'vitamin b3'],
    evidenceNote:
        'A water-soluble vitamin B3 derivative — reduces sebum oxidation, '
        'erythema, and pigmentation with minimal irritation across skin '
        'types (Bissett et al., 2005).',
  );

  static const calendula = NaturalIngredient(
    name: 'Calendula',
    purpose: 'Soothes irritated, reactive skin',
    keywords: ['calendula', 'marigold extract'],
    evidenceNote:
        'Triterpenoid-rich extract with documented anti-inflammatory and '
        'wound-healing actions — gentle for reactive skin.',
  );

  static const chamomile = NaturalIngredient(
    name: 'Chamomile',
    purpose: 'Calms inflammation and redness',
    keywords: ['chamomile', 'matricaria', 'bisabolol', 'chamomilla recutita'],
    evidenceNote:
        'Bisabolol and matricin from chamomile dampen NF-κB-driven '
        'inflammation and improve comfort in sensitive skin.',
  );

  static const licorice = NaturalIngredient(
    name: 'Licorice root',
    purpose: 'Brightens and reduces redness',
    keywords: ['licorice', 'glycyrrhiza', 'liquorice'],
    evidenceNote:
        'Glabridin inhibits tyrosinase (pigment) and dampens UV-induced '
        'erythema — a gentle brightener for melasma and PIH.',
  );

  static const greenTea = NaturalIngredient(
    name: 'Green tea (EGCG)',
    purpose: 'Antioxidant and anti-inflammatory',
    keywords: ['green tea', 'camellia sinensis', 'egcg', 'epigallocatechin'],
    evidenceNote:
        'Polyphenols neutralize ROS and reduce sebaceous inflammation — '
        'topical 3% green tea has measurable effects on mild acne.',
  );

  static const oat = NaturalIngredient(
    name: 'Colloidal oat',
    purpose: 'Soothes and restores barrier',
    keywords: ['colloidal oat', 'avena sativa', 'oat extract', 'oat kernel'],
    evidenceNote:
        'FDA-recognized skin protectant — beta-glucans and avenanthramides '
        'visibly reduce itch and erythema in eczema and rosacea-prone skin.',
  );

  static const squalane = NaturalIngredient(
    name: 'Plant squalane',
    purpose: 'Mimics natural sebum',
    keywords: ['squalane', 'olive squalane', 'sugarcane squalane'],
    evidenceNote:
        'Plant-derived squalane closely matches human sebum lipids — '
        'non-comedogenic occlusion suitable for acne-prone and barrier-'
        'compromised skin.',
  );

  static const jojoba = NaturalIngredient(
    name: 'Jojoba oil',
    purpose: 'Lightweight barrier-friendly oil',
    keywords: ['jojoba', 'simmondsia chinensis'],
    evidenceNote:
        'A liquid wax ester closest to human sebum — supports the lipid '
        'barrier without occluding pores at typical concentrations.',
  );

  static const honey = NaturalIngredient(
    name: 'Manuka honey',
    purpose: 'Antimicrobial humectant',
    keywords: ['manuka', 'honey extract', 'mel'],
    evidenceNote:
        'Medical-grade manuka honey shows antibacterial activity (MGO) '
        'and gentle humectancy — useful as a short-contact mask.',
  );

  static const shea = NaturalIngredient(
    name: 'Shea butter',
    purpose: 'Rich emollient for dry skin',
    keywords: ['shea', 'butyrospermum', 'karite'],
    evidenceNote:
        'Triterpenoid-rich emollient — supports stratum-corneum lipid '
        'balance in dry and mature skin. Comedogenicity is low at typical '
        'percentages.',
  );

  static const turmeric = NaturalIngredient(
    name: 'Turmeric (curcumin)',
    purpose: 'Antioxidant brightener',
    keywords: ['turmeric', 'curcumin', 'curcuma longa'],
    evidenceNote:
        'Curcumin scavenges ROS and modulates inflammatory cascades — '
        'topical preparations support dull, congested skin.',
  );

  static const seaBuckthorn = NaturalIngredient(
    name: 'Sea buckthorn',
    purpose: 'Repairs and replenishes',
    keywords: ['sea buckthorn', 'hippophae'],
    evidenceNote:
        'Rich in omega-7 (palmitoleic acid) and carotenoids — supports '
        'barrier repair and visible radiance.',
  );

  /// All natural ingredients in registry order.
  static const List<NaturalIngredient> all = [
    bakuchiol,
    centella,
    niacinamide,
    aloeVera,
    rosehip,
    teaTree,
    calendula,
    chamomile,
    licorice,
    greenTea,
    oat,
    squalane,
    jojoba,
    honey,
    shea,
    turmeric,
    seaBuckthorn,
  ];
}

/// Detection result for one product.
class NaturalDetection {
  /// All natural ingredients matched in the product's name / brand /
  /// keyIngredients / notes.
  final List<NaturalIngredient> matched;

  const NaturalDetection(this.matched);

  bool get isNatural => matched.isNotEmpty;

  /// Compact comma-separated display label (e.g. "Bakuchiol · Centella").
  String get displayLabel => matched.map((m) => m.name).take(3).join(' · ');
}

/// Stateless detector / advisor used everywhere we need natural skincare
/// support.
class NaturalSkincareAdvisor {
  /// Detect natural ingredients in arbitrary free-text (name + brand +
  /// keyIngredients + notes already concatenated by the caller).
  static NaturalDetection detectFromText(String haystack) {
    final hay = haystack.toLowerCase();
    if (hay.isEmpty) return const NaturalDetection([]);
    final matched = <NaturalIngredient>[];
    for (final ing in NaturalIngredientCatalog.all) {
      for (final kw in ing.keywords) {
        if (hay.contains(kw)) {
          matched.add(ing);
          break;
        }
      }
    }
    return NaturalDetection(matched);
  }

  /// Convenience wrapper for a TrackedProduct-like bundle.
  static NaturalDetection detectFromFields({
    String name = '',
    String brand = '',
    String keyIngredients = '',
    String notes = '',
  }) {
    return detectFromText('$name $brand $keyIngredients $notes');
  }

  // ── Natural-specific compatibility warnings ───────────────────────────

  /// Detect risky natural-ingredient patterns in a stack of free-text
  /// product descriptors. Always tone-balanced — natural ≠ automatically
  /// safer. Returns plain-string warnings suitable for product feedback.
  static List<String> compatibilityWarnings({
    required List<String> stackTexts,
    bool rosaceaProne = false,
    bool sensitiveSkin = false,
    int recentIrritation = 0,
    int recentRedness = 0,
  }) {
    final corpus = stackTexts.map((s) => s.toLowerCase()).toList();
    bool stackHas(List<String> kws) {
      for (final c in corpus) {
        for (final k in kws) {
          if (c.contains(k)) return true;
        }
      }
      return false;
    }

    final hasEssentialOil = stackHas([
      'essential oil',
      'lavender oil',
      'peppermint oil',
      'rosemary oil',
      'eucalyptus oil',
      'limonene',
      'linalool',
      'citronellol',
      'geraniol',
    ]);
    final hasTeaTree = stackHas(['tea tree', 'melaleuca']);
    final hasCitrusOil = stackHas([
      'bergamot oil',
      'lemon oil',
      'lime oil',
      'orange oil',
      'grapefruit oil',
    ]);
    final hasFragrance = stackHas(['parfum', 'fragrance']);

    final out = <String>[];

    if (hasEssentialOil &&
        (rosaceaProne || sensitiveSkin || recentRedness >= 5)) {
      out.add(
        'Essential oils (lavender, peppermint, rosemary, eucalyptus) can '
        'trigger flushing and neurogenic stinging in rosacea-prone and '
        'sensitive skin. Consider fragrance-free, essential-oil-free '
        'formulations during flares.',
      );
    }
    if (hasTeaTree && recentIrritation >= 6) {
      out.add(
        'Tea tree oil can be drying when used daily or above 5%. '
        'Step back to 3 nights per week and pair with a ceramide '
        'moisturizer to protect the barrier.',
      );
    }
    if (hasCitrusOil) {
      out.add(
        'Citrus essential oils (bergamot, lemon, lime) are photosensitizing '
        '(furocoumarins) — avoid daytime application without SPF 50, or '
        'reserve for night use.',
      );
    }
    if (hasFragrance && (sensitiveSkin || recentIrritation >= 5)) {
      out.add(
        'Even botanically-derived fragrance components (limonene, linalool) '
        'are common reactivity triggers. A 2-week fragrance-free trial is '
        'a clean way to confirm or rule them out.',
      );
    }
    return out;
  }

  // ── Natural alternative suggestions ───────────────────────────────────

  /// Suggest evidence-based natural swaps based on what's already in the
  /// stack. Returns plain-string suggestions for the AI Feedback panel.
  static List<String> suggestAlternatives({
    required List<String> stackTexts,
    int recentIrritation = 0,
    int recentRedness = 0,
    bool rosaceaProne = false,
    bool sensitiveSkin = false,
  }) {
    final corpus = stackTexts.map((s) => s.toLowerCase()).toList();
    bool stackHas(List<String> kws) {
      for (final c in corpus) {
        for (final k in kws) {
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
      'tazarotene',
    ]);
    final hasStrongAcid = stackHas([
      'glycolic',
      'lactic',
      'mandelic',
      'salicylic',
    ]);
    final hasBakuchiol = stackHas(['bakuchiol']);
    final hasCentella = stackHas([
      'centella',
      'cica',
      'madecassoside',
      'tiger grass',
    ]);
    final hasNiacinamide = stackHas(['niacinamide', 'nicotinamide']);
    final hasGreenTea = stackHas(['green tea', 'egcg', 'camellia sinensis']);

    final out = <String>[];

    if (hasRetinoid && (recentIrritation >= 5 || sensitiveSkin)) {
      if (!hasBakuchiol) {
        out.add(
          'Bakuchiol 0.5–1% is an evidence-supported plant-based retinol '
          'alternative — retinol-like benefits on fine lines and tone with '
          'significantly less irritation in 12-week split-face trials.',
        );
      }
    }
    if ((rosaceaProne || recentRedness >= 5) && !hasCentella) {
      out.add(
        'Centella asiatica (cica) + aloe vera is a clinically calming pair '
        'for rosacea-prone skin — wound-healing botanicals that reduce '
        'TEWL without active load.',
      );
    }
    if (recentIrritation >= 5 && !hasNiacinamide) {
      out.add(
        'Niacinamide 4% is a well-tolerated natural-source vitamin B3 — '
        'visibly reduces erythema, sebum oxidation, and pigmentation '
        'without compromising the barrier.',
      );
    }
    if (hasStrongAcid && recentIrritation >= 5) {
      out.add(
        'Consider alternating chemical exfoliation with a gentler natural '
        'enzyme mask (papaya / pineapple bromelain) 1–2x per week to give '
        'the barrier recovery windows.',
      );
    }
    if (!hasGreenTea && recentRedness >= 5) {
      out.add(
        'Topical green tea (EGCG) is a polyphenol antioxidant — calms '
        'background erythema and sebaceous inflammation as a gentle '
        'morning add-on.',
      );
    }
    if (sensitiveSkin && !stackHas(['oat', 'avena', 'colloidal oat'])) {
      out.add(
        'Colloidal oat is FDA-recognized as a skin protectant — '
        'beta-glucans and avenanthramides measurably reduce itch and '
        'erythema in compromised barriers.',
      );
    }
    return out;
  }
}
