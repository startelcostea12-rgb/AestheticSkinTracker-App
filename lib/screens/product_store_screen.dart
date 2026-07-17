// lib/screens/product_store_screen.dart
//
// Premium AestheticSkinTracker Product Store.
//
// Features:
//   • AI-personalized hero with smart headline (procedure-aware)
//   • Signature Recovery Kit (bundle) carousel
//   • Trust strip with affiliate disclosure
//   • Category chip filter
//   • Responsive grid (2/3/4 cols) of premium product cards with badges,
//     star rating, "Why we recommend" snippet, and quick-add button
//   • Live cart badge on the AppBar

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/product.dart';
import '../utils/app_prefs.dart';
import '../utils/cart_service.dart';
import '../widgets/category_artwork.dart';
import '../widgets/clinical_section_header.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';

// ─── Brand palette (rose-gold, soft navy, champagne) ────────────────────
const Color _kSoftNavy = Color(0xFF1F3A5F);
const Color _kAccentGold = Color(0xFFB8924C);

class ProductStoreScreen extends StatefulWidget {
  const ProductStoreScreen({super.key});

  @override
  State<ProductStoreScreen> createState() => _ProductStoreScreenState();
}

class _ProductStoreScreenState extends State<ProductStoreScreen> {
  ProductCategory? _filter; // null = All
  bool _loading = true;
  String? _activeProcedureType;
  List<Product> _recommended = const [];
  List<Product> _bundles = const [];

  @override
  void initState() {
    super.initState();
    _load();
    CartService.instance.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    CartService.instance.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await CartService.instance.ensureLoaded();
    final selectedId = await AppPrefs.getSelectedProcedureIdOrNull();
    String? procedureType;
    if (selectedId != null && selectedId.trim().isNotEmpty) {
      final procs = await AppPrefs.getProcedureEntries();
      for (final raw in procs) {
        final id = (raw['id'] ?? raw['procedureId'] ?? '').toString().trim();
        if (id == selectedId.trim()) {
          procedureType = (raw['type'] ?? raw['name'] ?? '').toString().trim();
          break;
        }
      }
    }

    final recs = _recommendFor(procedureType);
    final bundles = ProductCatalog.all
        .where((p) => p.category == ProductCategory.bundles)
        .toList();

    if (!mounted) return;
    setState(() {
      _activeProcedureType = procedureType;
      _recommended = recs;
      _bundles = bundles;
      _loading = false;
    });
  }

  /// Surface up to 4 recommended products based on the active procedure type.
  ///
  /// Photo-aware logic:
  ///   1. Score each product by procedure-relevance (tag matches).
  ///   2. Add a small bonus for products whose photo is unique in the catalog
  ///      (so the row never feels like a wall of identical bottles).
  ///   3. Sort by relevance → photo-uniqueness → rating × log(ratingCount).
  ///   4. Walk the sorted list and keep at most one product per imageUrl,
  ///      so two recommendations never share the exact same photo.
  ///   5. If fewer than 4 photo-unique picks survive, top up from the
  ///      remaining sorted pool — still skipping any imageUrl already used.
  List<Product> _recommendFor(String? procedureType) {
    final type = (procedureType ?? '').toLowerCase();
    final keywords = <String>{
      if (type.contains('laser') ||
          type.contains('halo') ||
          type.contains('peel')) ...[
        'post-laser',
        'post-peel',
        'pigment',
        'cica',
        'spf',
        'barrier',
      ],
      if (type.contains('inject') ||
          type.contains('filler') ||
          type.contains('botox') ||
          type.contains('tox')) ...[
        'injectables',
        'wrinkle',
        'fine-lines',
        'bruising',
      ],
      if (type.contains('hair') || type.contains('transplant')) ...[
        'hairTransplant',
        'hair',
        'peptide',
        'collagen',
      ],
      if (type.contains('microneedl')) ...[
        'microneedling',
        'collagen',
        'barrier',
      ],
      if (type.contains('surg') ||
          type.contains('lift') ||
          type.contains('lipo')) ...[
        'post-surgical',
        'wound-healing',
        'recovery',
        'scar',
        'lymphatic',
      ],
      if (type.contains('body') || type.contains('contour')) ...[
        'elasticity',
        'collagen',
        'lymphatic',
      ],
    };

    final pool = ProductCatalog.all
        .where((p) => p.category != ProductCategory.bundles)
        .toList();

    // Photo-frequency map across the *entire* non-bundle catalog. Lower
    // frequency = more unique image = stronger candidate for the AI row.
    final photoCounts = <String, int>{};
    for (final p in pool) {
      final key = (p.imageUrl ?? '').trim();
      if (key.isEmpty) continue;
      photoCounts[key] = (photoCounts[key] ?? 0) + 1;
    }
    bool isPhotoUnique(Product p) =>
        (p.imageUrl ?? '').trim().isNotEmpty &&
        (photoCounts[p.imageUrl ?? ''] ?? 0) == 1;
    bool hasUsablePhoto(Product p) => (p.imageUrl ?? '').trim().isNotEmpty;

    // Composite score: relevance dominates, photo-uniqueness is a tiebreaker,
    // then social proof (rating × ratingCount, dampened).
    double scoreOf(Product p) {
      final relevance = p.tags.where(keywords.contains).length.toDouble();
      final photoBonus = isPhotoUnique(p)
          ? 0.6
          : (hasUsablePhoto(p) ? 0.0 : -0.4);
      final social =
          p.rating *
          (p.ratingCount > 0
              ? (1.0 + (p.ratingCount.toDouble().clamp(0, 5000)) / 5000)
              : 0.0);
      // Relevance is integer-valued, so weight it heavily to keep dominance.
      return relevance * 10.0 + photoBonus + social * 0.05;
    }

    // No procedure context → curated default list, but still photo-deduped.
    if (keywords.isEmpty) {
      final defaults = <String>[
        'mineral-spf-50',
        'ha-multi-mw',
        'vitamin-c-15',
        'matrixyl-3000',
        'niacinamide-10',
        'centella-cica-cream',
        'argireline-serum',
        'copper-peptide-ghk',
      ].map(ProductCatalog.byId).whereType<Product>().toList();
      return _dedupeByPhoto(defaults, 4);
    }

    final ranked =
        pool
            .map((p) => MapEntry(p, scoreOf(p)))
            .where(
              (e) =>
                  // Must have at least one relevance match OR a unique photo to
                  // be eligible — keeps the row tightly relevant.
                  e.key.tags.where(keywords.contains).isNotEmpty,
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final primary = _dedupeByPhoto(ranked.map((e) => e.key).toList(), 4);

    if (primary.length >= 4) return primary;

    // Top up: walk the rest of the catalog by composite score, still
    // skipping any imageUrl we've already used.
    final used = primary.map((p) => p.imageUrl ?? '').toSet();
    final usedIds = primary.map((p) => p.id).toSet();
    final fillers =
        pool
            .where((p) => !usedIds.contains(p.id))
            .map((p) => MapEntry(p, scoreOf(p)))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in fillers) {
      if (primary.length >= 4) break;
      final p = entry.key;
      final url = (p.imageUrl ?? '').trim();
      // Avoid duplicate photos in the AI row whenever possible.
      if (url.isNotEmpty && used.contains(url)) continue;
      primary.add(p);
      used.add(url);
    }

    // Last-resort: if we still couldn't reach 4 (catalog too small / too
    // much photo overlap), allow one duplicated photo rather than show an
    // empty slot — but only after every unique option is exhausted.
    if (primary.length < 4) {
      for (final entry in fillers) {
        if (primary.length >= 4) break;
        final p = entry.key;
        if (primary.contains(p)) continue;
        primary.add(p);
      }
    }

    return primary;
  }

  /// Returns up to [limit] products from [sorted] (already ranked best-first),
  /// keeping at most one product per `imageUrl`.
  List<Product> _dedupeByPhoto(List<Product> sorted, int limit) {
    final out = <Product>[];
    final usedUrls = <String>{};
    for (final p in sorted) {
      if (out.length >= limit) break;
      final url = (p.imageUrl ?? '').trim();
      if (url.isNotEmpty && usedUrls.contains(url)) continue;
      out.add(p);
      if (url.isNotEmpty) usedUrls.add(url);
    }
    return out;
  }

  /// Personalized headline e.g. "Best for your Halo Laser recovery".
  String get _heroHeadline {
    final type = (_activeProcedureType ?? '').trim();
    if (type.isEmpty) return 'Curated by AI for your skin journey';
    final lc = type.toLowerCase();
    if (lc.contains('halo')) return 'Best for your Halo Laser recovery';
    if (lc.contains('laser')) return 'Best for your laser recovery';
    if (lc.contains('peel')) return 'Best for your chemical-peel recovery';
    if (lc.contains('microneedl')) {
      return 'Best for your microneedling recovery';
    }
    if (lc.contains('hair') || lc.contains('transplant')) {
      return 'Best for your hair-transplant recovery';
    }
    if (lc.contains('botox') || lc.contains('tox')) {
      return 'Curated to extend your Botox results';
    }
    if (lc.contains('filler') || lc.contains('inject')) {
      return 'Curated to support your injectable journey';
    }
    if (lc.contains('lipo')) return 'Best for your post-lipo recovery';
    if (lc.contains('lift') || lc.contains('surg')) {
      return 'Best for your post-surgical recovery';
    }
    return 'Personalized for your $type plan';
  }

  String get _heroSubhead {
    final type = (_activeProcedureType ?? '').trim();
    if (type.isEmpty) {
      return 'Sign in to your active procedure for fully tailored picks.';
    }
    return 'Hand-picked by our recovery AI based on your active plan and scan signals.';
  }

  List<Product> get _visible {
    if (_filter == null) {
      return ProductCatalog.all
          .where((p) => p.category != ProductCategory.bundles)
          .toList();
    }
    return ProductCatalog.all.where((p) => p.category == _filter).toList();
  }

  void _openCart() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  void _openDetail(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
  }

  Future<void> _quickAdd(Product product) async {
    await CartService.instance.add(product.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('${product.name} added to cart'),
        action: SnackBarAction(label: 'View Cart', onPressed: _openCart),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxis = width >= 1100
        ? 4
        : width >= 760
        ? 3
        : 2;

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const ClinicalAppBarTitle(
          title: 'Aesthetic Store',
          eyebrow: 'Curated marketplace',
        ),
        centerTitle: true,
        actions: [_CartAppBarButton(onTap: _openCart)],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHero()),
                  if (_bundles.isNotEmpty)
                    SliverToBoxAdapter(child: _buildBundlesSection()),
                  SliverToBoxAdapter(child: _buildTrustStrip()),
                  SliverToBoxAdapter(child: _buildCategoryChips()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                      child: ClinicalSectionHeader(
                        icon: Icons.storefront_outlined,
                        title: _filter == null ? 'Shop All' : _filter!.label,
                        eyebrow: 'Curated catalogue',
                        trailing: Text(
                          '${_visible.length} items',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: MyApp.textBrown.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxis,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.62,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _PremiumProductCard(
                          product: _visible[i],
                          onTap: () => _openDetail(_visible[i]),
                          onAdd: () => _quickAdd(_visible[i]),
                        ),
                        childCount: _visible.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildFooterDisclosure()),
                ],
              ),
      ),
    );
  }

  // ─── Hero (AI Recommended) ────────────────────────────────────────────

  Widget _buildHero() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kSoftNavy.withValues(alpha: 0.97),
            _kSoftNavy.withValues(alpha: 0.85),
            MyApp.roseGold.withValues(alpha: 0.85),
          ],
          stops: const [0.0, 0.55, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _kSoftNavy.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.32),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 12, color: _kAccentGold),
                    SizedBox(width: 5),
                    Text(
                      'AI RECOMMENDED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: _kAccentGold,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Curated for you',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _heroHeadline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _heroSubhead,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: _recommended.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(
                width: 168,
                child: _RecommendedCard(
                  product: _recommended[i],
                  onTap: () => _openDetail(_recommended[i]),
                  onAdd: () => _quickAdd(_recommended[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bundles ──────────────────────────────────────────────────────────

  Widget _buildBundlesSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClinicalSectionHeader(
            icon: Icons.card_giftcard_outlined,
            title: 'Signature Recovery Kits',
            eyebrow: 'Bundled protocols',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: _kAccentGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Save up to 15%',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: _kAccentGold,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Procedure-specific routines, ready in one click.',
            style: TextStyle(
              fontSize: 12.5,
              color: MyApp.textBrown.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: _bundles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(
                width: 210,
                child: _BundleCard(
                  bundle: _bundles[i],
                  onTap: () => _openDetail(_bundles[i]),
                  onAdd: () => _quickAdd(_bundles[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Trust strip ──────────────────────────────────────────────────────

  Widget _buildTrustStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _trustItem(Icons.verified_outlined, 'Expertly Curated'),
          ),
          _trustDivider(),
          Expanded(
            child: _trustItem(
              Icons.local_shipping_outlined,
              'Affiliate Fulfilled',
            ),
          ),
          _trustDivider(),
          Expanded(child: _trustItem(Icons.shield_outlined, 'No Extra Cost')),
        ],
      ),
    );
  }

  Widget _trustItem(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: MyApp.roseGold),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: MyApp.textBrown,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _trustDivider() => Container(
    width: 1,
    height: 30,
    color: MyApp.roseGold.withValues(alpha: 0.18),
  );

  // ─── Category chips ───────────────────────────────────────────────────

  Widget _buildCategoryChips() {
    final chips = <(ProductCategory?, String)>[
      (null, 'All'),
      ...ProductCategory.values
          .where((c) => c != ProductCategory.bundles)
          .map((c) => (c, c.label)),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = chips[i].$1;
          final label = chips[i].$2;
          final selected = _filter == cat;
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => setState(() => _filter = cat),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : MyApp.textBrown,
            ),
            selectedColor: MyApp.roseGold,
            backgroundColor: Colors.white,
            side: BorderSide(
              color: MyApp.roseGold.withValues(alpha: selected ? 0.0 : 0.35),
            ),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  // ─── Footer disclosure ────────────────────────────────────────────────

  Widget _buildFooterDisclosure() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        children: [
          Icon(
            Icons.handshake_outlined,
            size: 16,
            color: MyApp.textBrown.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 6),
          Text(
            'Some links are affiliate links. We may earn a small commission at no extra cost to you. '
            'Curation is independent and evidence informed.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: MyApp.textBrown.withValues(alpha: 0.55),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Reusable widgets
// ═══════════════════════════════════════════════════════════════════════

class _CartAppBarButton extends StatelessWidget {
  const _CartAppBarButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CartService.instance,
      builder: (context, _) {
        final count = CartService.instance.count;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Cart',
                onPressed: onTap,
                icon: Icon(Icons.shopping_bag_outlined, color: MyApp.textBrown),
              ),
              if (count > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: MyApp.roseGold,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PremiumProductCard extends StatelessWidget {
  const _PremiumProductCard({
    required this.product,
    required this.onTap,
    required this.onAdd,
  });
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final primaryBadge = product.badges.isNotEmpty
        ? product.badges.first
        : null;
    final hasDiscount =
        product.originalPrice != null && product.originalPrice! > product.price;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: MyApp.roseGold.withValues(alpha: 0.22),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _kSoftNavy.withValues(alpha: 0.09),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: MyApp.roseGold.withValues(alpha: 0.07),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Framed artwork with subtle inner glow
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: AspectRatio(
                  aspectRatio: 1.05,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Positioned.fill(child: _ProductImage(product: product)),
                        // diagonal highlight for premium sheen
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.22),
                                    Colors.white.withValues(alpha: 0.0),
                                    Colors.black.withValues(alpha: 0.04),
                                  ],
                                  stops: const [0.0, 0.55, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (primaryBadge != null)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: _Badge(badge: primaryBadge),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 8, 13, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category label
                      Text(
                        product.category.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: MyApp.roseGold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Name
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: MyApp.textBrown,
                          height: 1.2,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Short description
                      Text(
                        product.shortDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: MyApp.textBrown.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Rating
                      _RatingRow(
                        rating: product.rating,
                        count: product.ratingCount,
                      ),
                      const SizedBox(height: 6),
                      // Subtle gradient divider
                      Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              MyApp.roseGold.withValues(alpha: 0.28),
                              MyApp.roseGold.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Price + Add
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    '\$${product.price.toStringAsFixed(2)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: MyApp.textBrown,
                                      height: 1.0,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                if (hasDiscount) ...[
                                  const SizedBox(width: 6),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      '\$${product.originalPrice!.toStringAsFixed(2)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        decoration: TextDecoration.lineThrough,
                                        color: MyApp.textBrown.withValues(
                                          alpha: 0.42,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _AddIconButton(onTap: onAdd, compact: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({
    required this.product,
    required this.onTap,
    required this.onAdd,
  });
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final primaryBadge = product.badges.isNotEmpty
        ? product.badges.first
        : null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 124,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ProductImage(product: product),
                      if (primaryBadge != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _Badge(badge: primaryBadge),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.category.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: MyApp.roseGold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: MyApp.textBrown,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _RatingRow(
                        rating: product.rating,
                        count: product.ratingCount,
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '\$${product.price.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: MyApp.textBrown,
                                  ),
                                ),
                                if (product.originalPrice != null)
                                  Text(
                                    '\$${product.originalPrice!.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      decoration: TextDecoration.lineThrough,
                                      color: MyApp.textBrown.withValues(
                                        alpha: 0.45,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _AddIconButton(onTap: onAdd, compact: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BundleCard extends StatelessWidget {
  const _BundleCard({
    required this.bundle,
    required this.onTap,
    required this.onAdd,
  });
  final Product bundle;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final savings = bundle.savingsPercent;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kAccentGold.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: _kSoftNavy.withValues(alpha: 0.07),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 108,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  child: _ProductImage(product: bundle),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: _kAccentGold.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'BUNDLE',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: _kAccentGold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          if (savings != null) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: MyApp.roseGold,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'SAVE ${savings.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.9,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bundle.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: MyApp.textBrown,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${bundle.bundledItemIds.length} products · all-in-one routine',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: MyApp.textBrown.withValues(alpha: 0.60),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '\$${bundle.price.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: MyApp.textBrown,
                                ),
                              ),
                              if (bundle.originalPrice != null)
                                Text(
                                  '\$${bundle.originalPrice!.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    decoration: TextDecoration.lineThrough,
                                    color: MyApp.textBrown.withValues(
                                      alpha: 0.45,
                                    ),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          _AddIconButton(onTap: onAdd, compact: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.badge});
  final ProductBadge badge;

  @override
  Widget build(BuildContext context) {
    final color = switch (badge) {
      ProductBadge.bestSeller => MyApp.roseGold,
      ProductBadge.newArrival => _kSoftNavy,
      ProductBadge.editorsPick => _kAccentGold,
      ProductBadge.bundleSavings => MyApp.roseGold,
      ProductBadge.clinicallyInspired => _kSoftNavy,
      ProductBadge.dermatologistRecommended => _kSoftNavy,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        badge.label.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.rating, required this.count});
  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 14, color: _kAccentGold),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: MyApp.textBrown,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '($count)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: MyApp.textBrown.withValues(alpha: 0.55),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddIconButton extends StatelessWidget {
  const _AddIconButton({required this.onTap, this.compact = false});
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 34.0;
    return Material(
      color: MyApp.roseGold,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: const Icon(Icons.add, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return CategoryArtwork(product: product, showPhoto: false);
  }
}
