// lib/models/product.dart
//
// Product model + curated catalog for the in-app Product Store.
//
// The store is a clinical-aesthetic curation of peptide serums, hydrators,
// SPF, supportive recovery products, and signature recovery bundles.

import 'package:flutter/material.dart';

enum ProductCategory {
  peptides,
  serums,
  hydration,
  spf,
  recovery,
  supplements,
  tools,
  bundles,
}

extension ProductCategoryX on ProductCategory {
  String get label {
    switch (this) {
      case ProductCategory.peptides:
        return 'Peptides';
      case ProductCategory.serums:
        return 'Serums';
      case ProductCategory.hydration:
        return 'Hydration';
      case ProductCategory.spf:
        return 'Sunscreen';
      case ProductCategory.recovery:
        return 'Recovery';
      case ProductCategory.supplements:
        return 'Supplements';
      case ProductCategory.tools:
        return 'Skincare Tools';
      case ProductCategory.bundles:
        return 'Recovery Kits';
    }
  }

  IconData get icon {
    switch (this) {
      case ProductCategory.peptides:
        return Icons.science_outlined;
      case ProductCategory.serums:
        return Icons.water_drop_outlined;
      case ProductCategory.hydration:
        return Icons.opacity;
      case ProductCategory.spf:
        return Icons.wb_sunny_outlined;
      case ProductCategory.recovery:
        return Icons.healing_outlined;
      case ProductCategory.supplements:
        return Icons.medication_outlined;
      case ProductCategory.tools:
        return Icons.spa_outlined;
      case ProductCategory.bundles:
        return Icons.card_giftcard_outlined;
    }
  }
}

/// Trust badges surfaced on cards and the detail screen.
enum ProductBadge {
  clinicallyInspired,
  dermatologistRecommended,
  bestSeller,
  newArrival,
  editorsPick,
  bundleSavings,
}

extension ProductBadgeX on ProductBadge {
  String get label {
    switch (this) {
      case ProductBadge.clinicallyInspired:
        return 'Expertly Curated';
      case ProductBadge.dermatologistRecommended:
        return 'Derm Recommended';
      case ProductBadge.bestSeller:
        return 'Best Seller';
      case ProductBadge.newArrival:
        return 'New';
      case ProductBadge.editorsPick:
        return "Editor's Pick";
      case ProductBadge.bundleSavings:
        return 'Save 15%';
    }
  }
}

class Product {
  final String id;
  final String name;
  final ProductCategory category;
  final double price;
  final double? originalPrice; // for bundles or promos — shown struck-through
  final String? imageUrl;
  final String shortDescription;
  final String whyRecommend;

  /// Deeper clinical rationale shown on the detail screen.
  final String clinicalNotes;

  /// Practical "how to use" guidance shown on the detail screen.
  final String usage;

  final String? affiliateLink;

  /// Free-form tags used by the recommendation engine, e.g.
  /// 'post-laser', 'redness', 'hairTransplant', 'peptide'.
  final List<String> tags;

  /// Trust badges to render on cards and the detail screen.
  final List<ProductBadge> badges;

  /// IDs of products that complement this one (Frequently Bought Together).
  final List<String> complementsIds;

  /// Product IDs included in this bundle. Empty for non-bundle products.
  final List<String> bundledItemIds;

  /// 0..5 average rating used for star display.
  final double rating;

  /// Total ratings count shown next to the stars.
  final int ratingCount;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.originalPrice,
    this.imageUrl,
    required this.shortDescription,
    required this.whyRecommend,
    this.clinicalNotes = '',
    this.usage = '',
    this.affiliateLink,
    this.tags = const [],
    this.badges = const [],
    this.complementsIds = const [],
    this.bundledItemIds = const [],
    this.rating = 4.7,
    this.ratingCount = 124,
  });

  bool get isBundle => category == ProductCategory.bundles;

  double? get savingsPercent {
    if (originalPrice == null || originalPrice! <= price) return null;
    return ((originalPrice! - price) / originalPrice!) * 100.0;
  }
}

class ProductCatalog {
  ProductCatalog._();

  /// Curated catalog of recovery-focused products + signature bundles.
  ///
  /// `imageUrl` values use free Unsplash photo URLs (no API key required).
  /// `affiliateLink` is a partner search URL — replace with your real
  /// affiliate link IDs in production.
  static const List<Product> all = [
    // ───────── Peptides ─────────
    Product(
      id: 'matrixyl-3000',
      name: 'Matrixyl 3000 Peptide Serum',
      category: ProductCategory.peptides,
      price: 28.00,
      imageUrl:
          'https://images.unsplash.com/photo-1765053534710-2409e33e65b4?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=matrixyl+3000+peptide+serum&tag=aestheticskin-20',
      shortDescription:
          'Palmitoyl peptide complex that targets collagen synthesis and visible firmness.',
      whyRecommend:
          'Matrixyl 3000 signals fibroblasts to rebuild collagen scaffolding — ideal after micro-injury treatments such as microneedling, laser resurfacing, or for daily anti-aging maintenance.',
      clinicalNotes:
          'Published vehicle-controlled studies report ~45% reduction in deep wrinkle depth after 2 months of twice-daily use. Synergistic with retinoids and vitamin C when layered correctly.',
      usage:
          'Apply 3–4 drops to clean, slightly damp skin AM & PM. Follow with moisturizer and SPF in the morning. Safe to layer with retinoids on alternating nights.',
      tags: [
        'peptide',
        'collagen',
        'anti-aging',
        'post-laser',
        'microneedling',
      ],
      badges: [ProductBadge.clinicallyInspired, ProductBadge.bestSeller],
      complementsIds: ['ha-multi-mw', 'mineral-spf-50', 'vitamin-c-15'],
      rating: 4.8,
      ratingCount: 1284,
    ),
    Product(
      id: 'copper-peptide-ghk',
      name: 'GHK-Cu Copper Peptide Solution',
      category: ProductCategory.peptides,
      price: 42.00,
      imageUrl:
          'https://images.unsplash.com/photo-1773700596401-61bc77e0b436?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=ghk-cu+copper+peptide+serum&tag=aestheticskin-20',
      shortDescription:
          'Tripeptide-1 (GHK) bound to copper for wound healing and skin remodeling.',
      whyRecommend:
          'GHK-Cu is widely studied for accelerating tissue repair, reducing inflammation, and improving elasticity — a strong choice for post-surgical recovery and scar refinement.',
      clinicalNotes:
          'Stimulates dermal fibroblasts, downregulates TGF-β1, and modulates matrix metalloproteinases — a triple-action profile that supports both repair and remodeling.',
      usage:
          'Apply morning and evening to clean skin. Avoid layering directly with strong acids or vitamin C; alternate days or separate by at least 30 minutes.',
      tags: ['peptide', 'copper', 'wound-healing', 'scar', 'post-surgical'],
      badges: [ProductBadge.dermatologistRecommended, ProductBadge.editorsPick],
      complementsIds: [
        'centella-cica-cream',
        'ha-multi-mw',
        'arnica-bromelain',
      ],
      rating: 4.9,
      ratingCount: 642,
    ),
    Product(
      id: 'argireline-serum',
      name: 'Argireline 10% Expression-Line Serum',
      category: ProductCategory.peptides,
      price: 22.00,
      imageUrl:
          'https://images.unsplash.com/photo-1768235146507-20d280903e13?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=argireline+serum&tag=aestheticskin-20',
      shortDescription:
          'Acetyl hexapeptide-8 serum that softens dynamic expression lines.',
      whyRecommend:
          'Bridges the gap between neuromodulator visits by reducing fine forehead and crow\'s-foot lines, especially useful while waiting for injectable results to settle.',
      clinicalNotes:
          'Mimics the N-terminal end of SNAP-25, modestly inhibiting neurotransmitter release at the neuromuscular junction — a non-invasive companion to neuromodulator treatments.',
      usage:
          'Pat 2–3 drops onto expression areas (forehead, crow\'s-feet, between brows) AM & PM. Follow with moisturizer.',
      tags: ['peptide', 'injectables', 'wrinkle', 'fine-lines'],
      badges: [ProductBadge.clinicallyInspired],
      complementsIds: ['matrixyl-3000', 'ha-multi-mw'],
      rating: 4.6,
      ratingCount: 318,
    ),

    // ───────── Hydration ─────────
    Product(
      id: 'ha-multi-mw',
      name: 'Multi-Weight Hyaluronic Acid Serum',
      category: ProductCategory.hydration,
      price: 18.00,
      imageUrl:
          'https://images.unsplash.com/photo-1768235146440-1dc7e02132a3?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=hyaluronic+acid+serum&tag=aestheticskin-20',
      shortDescription:
          'Layered HA molecular weights for deep and surface-level hydration.',
      whyRecommend:
          'Restores the moisture barrier disrupted by lasers, peels, and tretinoin. Plumps tissue around injectable sites for a smoother integration.',
      clinicalNotes:
          'Combines high, medium, and low molecular weight HA — surface plumping, mid-dermis hydration, and deeper barrier support in a single application.',
      usage:
          'Apply to damp skin AM & PM, then seal with moisturizer. Excellent under makeup.',
      tags: ['hydration', 'post-laser', 'post-peel', 'barrier'],
      badges: [ProductBadge.bestSeller, ProductBadge.editorsPick],
      complementsIds: [
        'centella-cica-cream',
        'niacinamide-10',
        'mineral-spf-50',
      ],
      rating: 4.8,
      ratingCount: 2104,
    ),

    // ───────── Serums ─────────
    Product(
      id: 'niacinamide-10',
      name: 'Niacinamide 10% + Zinc Serum',
      category: ProductCategory.serums,
      price: 14.00,
      imageUrl:
          'https://images.unsplash.com/photo-1768254636839-9a2d2619c861?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=niacinamide+10+zinc+serum&tag=aestheticskin-20',
      shortDescription:
          'Calms redness, balances sebum, and refines visible pore appearance.',
      whyRecommend:
          'Niacinamide reinforces ceramide synthesis and reduces post-inflammatory redness — perfect for daily use after procedures or during peptide-induced purging.',
      clinicalNotes:
          'Vitamin B3 derivative supported by extensive literature for pore appearance, sebum regulation, and PIH reduction. Pairs well with HA and ceramides.',
      usage:
          'Apply morning and night to clean skin before heavier serums or creams. Limit pairing with high-strength vitamin C to alternate routines.',
      tags: ['redness', 'pores', 'barrier', 'daily'],
      badges: [ProductBadge.dermatologistRecommended, ProductBadge.bestSeller],
      complementsIds: ['ha-multi-mw', 'mineral-spf-50'],
      rating: 4.7,
      ratingCount: 3201,
    ),
    Product(
      id: 'vitamin-c-15',
      name: 'L-Ascorbic 15% Brightening Serum',
      category: ProductCategory.serums,
      price: 36.00,
      imageUrl:
          'https://images.unsplash.com/photo-1620916566398-39f1143ab7be?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=vitamin+c+serum+l+ascorbic&tag=aestheticskin-20',
      shortDescription:
          'Stabilized 15% L-ascorbic acid for tone, brightness, and antioxidant defense.',
      whyRecommend:
          'Neutralizes free radicals from sun and procedure stress while improving pigment evenness — pairs well with SPF for visible glow in 6–8 weeks.',
      clinicalNotes:
          'L-ascorbic at low pH provides the most validated topical antioxidant signal — synergistic with vitamin E and ferulic acid when stacked.',
      usage:
          'Use in the morning on clean dry skin, followed by moisturizer and SPF. Store away from heat & light to preserve potency.',
      tags: ['brightening', 'pigment', 'antioxidant', 'tone'],
      badges: [ProductBadge.clinicallyInspired, ProductBadge.editorsPick],
      complementsIds: ['mineral-spf-50', 'ha-multi-mw'],
      rating: 4.7,
      ratingCount: 1422,
    ),

    // ───────── Sunscreen ─────────
    Product(
      id: 'mineral-spf-50',
      name: 'Mineral SPF 50 Recovery Sunscreen',
      category: ProductCategory.spf,
      price: 32.00,
      imageUrl:
          'https://images.unsplash.com/photo-1709551264885-06719a695b4c?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=mineral+sunscreen+spf+50+zinc&tag=aestheticskin-20',
      shortDescription:
          'Tinted zinc oxide SPF 50 with squalane — safe for compromised skin.',
      whyRecommend:
          'Non-irritating mineral filter that protects fresh treatment areas without chemical sting. Essential for the first 6 weeks post-laser or peel to prevent hyperpigmentation.',
      clinicalNotes:
          '20%+ zinc oxide offers broad UVA/UVB coverage without photo-degradation. Critical for pigment-prone and post-procedure skin.',
      usage:
          'Apply 2 finger-lengths every morning as the final step. Reapply every 2 hours of sun exposure.',
      tags: ['spf', 'post-laser', 'post-peel', 'pigment', 'essential'],
      badges: [ProductBadge.dermatologistRecommended, ProductBadge.bestSeller],
      complementsIds: ['vitamin-c-15', 'centella-cica-cream'],
      rating: 4.9,
      ratingCount: 4082,
    ),

    // ───────── Supplements ─────────
    Product(
      id: 'collagen-peptide-powder',
      name: 'Marine Collagen Peptide Powder',
      category: ProductCategory.supplements,
      price: 45.00,
      imageUrl:
          'https://images.unsplash.com/photo-1688614586206-70a039559217?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=marine+collagen+peptide+powder&tag=aestheticskin-20',
      shortDescription:
          'Hydrolyzed type I & III marine collagen with vitamin C cofactor.',
      whyRecommend:
          'Oral collagen supports systemic recovery — clinically associated with improved skin elasticity, joint comfort, and hair regrowth after transplant procedures.',
      clinicalNotes:
          'Hydrolyzed peptides (2–5 kDa) absorb efficiently and stimulate fibroblast activity. Best taken with vitamin C to drive endogenous collagen synthesis.',
      usage:
          'Mix one scoop (10 g) into coffee, smoothie, or water daily. Best taken on an empty stomach in the morning.',
      tags: ['supplement', 'collagen', 'hair', 'hairTransplant', 'elasticity'],
      badges: [ProductBadge.bestSeller],
      complementsIds: ['arnica-bromelain', 'vitamin-c-15'],
      rating: 4.6,
      ratingCount: 952,
    ),

    // ───────── Recovery ─────────
    Product(
      id: 'arnica-bromelain',
      name: 'Arnica + Bromelain Recovery Capsules',
      category: ProductCategory.recovery,
      price: 24.00,
      imageUrl:
          'https://images.unsplash.com/photo-1768235146463-328c98e7234d?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=arnica+bromelain+supplement&tag=aestheticskin-20',
      shortDescription:
          'Botanical anti-inflammatory blend traditionally used to reduce bruising and swelling.',
      whyRecommend:
          'Often recommended by aesthetic providers before and after injectables, fillers, and surgical procedures to minimize bruising and edema.',
      clinicalNotes:
          'Bromelain (pineapple-derived proteolytic enzyme) and arnica are widely prescribed pre/post procedure to support recovery. Discontinue before any new procedure if your provider directs.',
      usage:
          'Take 2 capsules twice daily starting 3 days before and continuing 5 days after procedure. Always confirm with your provider.',
      tags: ['recovery', 'injectables', 'surgical', 'swelling', 'bruising'],
      badges: [ProductBadge.clinicallyInspired],
      complementsIds: ['centella-cica-cream', 'collagen-peptide-powder'],
      rating: 4.5,
      ratingCount: 287,
    ),
    Product(
      id: 'centella-cica-cream',
      name: 'Centella Asiatica Cica Repair Cream',
      category: ProductCategory.recovery,
      price: 26.00,
      imageUrl:
          'https://images.unsplash.com/photo-1556228720-195a672e8a03?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=centella+cica+cream&tag=aestheticskin-20',
      shortDescription:
          'Madecassoside-rich barrier cream for redness, irritation, and post-procedure care.',
      whyRecommend:
          'Centella triterpenes accelerate barrier recovery and soothe reactive skin — a gentle finishing layer after ablative or fractional laser sessions.',
      clinicalNotes:
          'Madecassoside upregulates type I collagen and downregulates inflammatory cytokines — a leading post-laser barrier choice in dermatology clinics.',
      usage:
          'Apply a thick layer post-procedure or whenever skin feels reactive. Safe AM & PM.',
      tags: ['cica', 'redness', 'post-laser', 'barrier', 'recovery'],
      badges: [ProductBadge.dermatologistRecommended, ProductBadge.editorsPick],
      complementsIds: ['ha-multi-mw', 'mineral-spf-50', 'copper-peptide-ghk'],
      rating: 4.8,
      ratingCount: 1675,
    ),

    // ───────── Skincare Tools ─────────
    Product(
      id: 'led-mask-red',
      name: 'Pro Red-Light LED Therapy Mask',
      category: ProductCategory.tools,
      price: 199.00,
      originalPrice: 249.00,
      affiliateLink:
          'https://www.amazon.com/s?k=red+light+led+face+mask&tag=aestheticskin-20',
      shortDescription:
          '630/660/830 nm tri-wavelength LED mask for collagen support and post-procedure calming.',
      whyRecommend:
          'Red and near-infrared light boost mitochondrial activity in skin cells — supporting collagen, calming inflammation, and accelerating recovery after laser, microneedling, or surgery.',
      clinicalNotes:
          'Red light (630–660 nm) targets the dermis for collagen support; near-infrared (830 nm) penetrates deeper for repair. 10–20 minute sessions, 3–5x weekly.',
      usage:
          'Cleanse skin, wear for 10–20 minutes, 3–5 times per week. Pair with peptide serums applied before the session.',
      tags: ['tools', 'led', 'collagen', 'post-laser', 'post-surgical'],
      badges: [ProductBadge.newArrival, ProductBadge.editorsPick],
      complementsIds: [
        'copper-peptide-ghk',
        'matrixyl-3000',
        'centella-cica-cream',
      ],
      rating: 4.7,
      ratingCount: 412,
    ),
    Product(
      id: 'gua-sha-stone',
      name: 'Lymphatic Gua Sha Stone',
      category: ProductCategory.tools,
      price: 28.00,
      imageUrl:
          'https://images.unsplash.com/photo-1556228578-8c89e6adf883?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=gua+sha+stone+facial&tag=aestheticskin-20',
      shortDescription:
          'Hand-finished bian stone for daily lymphatic drainage and lift.',
      whyRecommend:
          'Supports lymphatic flow to reduce puffiness, fluid retention, and post-procedure swelling — a daily ritual that compounds visible results.',
      clinicalNotes:
          'Manual lymphatic drainage is a recognized adjunct after fillers, lipo, and surgery. Use light pressure only; never on bruised or open skin.',
      usage:
          'Apply facial oil first. Glide upward and outward in slow strokes for 5 minutes nightly.',
      tags: ['tools', 'lymphatic', 'swelling', 'daily', 'post-surgical'],
      badges: [ProductBadge.bestSeller],
      complementsIds: ['arnica-bromelain', 'ha-multi-mw'],
      rating: 4.6,
      ratingCount: 891,
    ),

    // ───────── Bundles ─────────
    Product(
      id: 'bundle-laser-recovery',
      name: 'Halo Laser Recovery Kit',
      category: ProductCategory.bundles,
      price: 79.00,
      originalPrice: 94.00,
      imageUrl:
          'https://images.unsplash.com/photo-1571781926291-c477ebfd024b?auto=format&fit=crop&w=800&q=80',
      affiliateLink:
          'https://www.amazon.com/s?k=post+laser+recovery+kit&tag=aestheticskin-20',
      shortDescription:
          'Everything you need for the first 6 weeks post-laser: barrier repair, hydration, and broad-spectrum SPF.',
      whyRecommend:
          'A complete, dermatologist-aligned routine designed for ablative or fractional laser recovery. Calms reactivity, restores barrier, and protects against pigment rebound.',
      clinicalNotes:
          'Includes Centella Cica Repair Cream, Multi-Weight HA Serum, and Mineral SPF 50 — selected to cover the three critical needs of laser recovery: soothing, hydrating, and shielding.',
      usage:
          'Apply HA serum to damp skin AM & PM, layer Cica cream, then SPF in the morning. Use exclusively for the first 2 weeks; resume actives only when cleared by your provider.',
      tags: [
        'bundle',
        'post-laser',
        'post-peel',
        'barrier',
        'pigment',
        'essential',
      ],
      badges: [ProductBadge.bundleSavings, ProductBadge.editorsPick],
      bundledItemIds: ['centella-cica-cream', 'ha-multi-mw', 'mineral-spf-50'],
      rating: 4.9,
      ratingCount: 248,
    ),
    Product(
      id: 'bundle-post-lipo',
      name: 'Post-Lipo Essentials Bundle',
      category: ProductCategory.bundles,
      price: 85.00,
      originalPrice: 100.00,
      affiliateLink:
          'https://www.amazon.com/s?k=post+surgical+recovery+kit&tag=aestheticskin-20',
      shortDescription:
          'Lymphatic, anti-inflammatory, and barrier support tailored for post-surgical body recovery.',
      whyRecommend:
          'Combines Arnica + Bromelain capsules with a Gua Sha lymphatic stone and Centella Cica cream — covering swelling, drainage, and incision-area barrier care.',
      clinicalNotes:
          'Always confirm supplement timing with your surgeon. Gua sha is for face/neck only; avoid directly over compressed surgical sites until cleared.',
      usage:
          'Arnica + Bromelain twice daily, gua sha nightly on face/neck only, Cica on cleared scar lines AM & PM.',
      tags: ['bundle', 'post-surgical', 'lipo', 'lymphatic', 'recovery'],
      badges: [ProductBadge.bundleSavings, ProductBadge.clinicallyInspired],
      bundledItemIds: [
        'arnica-bromelain',
        'gua-sha-stone',
        'centella-cica-cream',
      ],
      rating: 4.8,
      ratingCount: 132,
    ),
    Product(
      id: 'bundle-glow-injectables',
      name: 'Injectable Glow-Up Bundle',
      category: ProductCategory.bundles,
      price: 64.00,
      originalPrice: 74.00,
      affiliateLink:
          'https://www.amazon.com/s?k=injectable+skincare+routine&tag=aestheticskin-20',
      shortDescription:
          'Stretch your filler and tox results between visits with this peptide + brightening trio.',
      whyRecommend:
          'Pairs Argireline expression-line serum, Matrixyl 3000 for collagen support, and L-Ascorbic 15% for tone — designed to extend the visible benefits of injectables.',
      clinicalNotes:
          'Topicals do not replace injectables but can support smoother integration and longer-lasting visual benefit when used consistently between appointments.',
      usage:
          'Argireline AM & PM on expression areas, Matrixyl 3000 evenings, Vitamin C mornings followed by SPF.',
      tags: ['bundle', 'injectables', 'wrinkle', 'brightening', 'tone'],
      badges: [ProductBadge.bundleSavings],
      bundledItemIds: ['argireline-serum', 'matrixyl-3000', 'vitamin-c-15'],
      rating: 4.7,
      ratingCount: 96,
    ),
  ];

  static Product? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  static List<Product> byIds(Iterable<String> ids) {
    final result = <Product>[];
    for (final id in ids) {
      final p = byId(id);
      if (p != null) result.add(p);
    }
    return result;
  }
}
