// lib/screens/product_detail_screen.dart
//
// Premium product detail with badges, ratings, "Why we recommend",
// Clinical Notes, How to Use, "Included in this kit" (for bundles),
// Frequently Bought Together cross-sells, and Buy-Now / Add-to-Cart.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/product.dart';
import '../utils/cart_service.dart';
import '../widgets/category_artwork.dart';
import '../widgets/clinical_section_header.dart';
import 'cart_screen.dart';

const Color _kSoftNavy = Color(0xFF1F3A5F);
const Color _kAccentGold = Color(0xFFB8924C);

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});
  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _quantity = 1;
  bool _adding = false;
  bool _buying = false;

  Product get _p => widget.product;

  Future<void> _addToCart() async {
    setState(() => _adding = true);
    await CartService.instance.add(_p.id, quantity: _quantity);
    if (!mounted) return;
    setState(() => _adding = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('${_p.name} added (×$_quantity)'),
        action: SnackBarAction(
          label: 'Cart',
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CartScreen())),
        ),
      ),
    );
  }

  Future<void> _buyNow() async {
    setState(() => _buying = true);
    final link = _p.affiliateLink;
    final uri = (link == null || link.isEmpty) ? null : Uri.tryParse(link);
    bool ok = false;
    if (uri != null) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        ok = false;
      }
    }
    if (!mounted) return;
    setState(() => _buying = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not open the affiliate link.'),
        ),
      );
    }
  }

  void _openDetail(Product p) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
    );
  }

  Future<void> _quickAdd(Product p) async {
    await CartService.instance.add(p.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('${p.name} added to cart'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final bundled = p.isBundle
        ? ProductCatalog.byIds(p.bundledItemIds)
        : <Product>[];
    final fbt = ProductCatalog.byIds(p.complementsIds);

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: MyApp.clinicalNavy),
        foregroundColor: MyApp.clinicalNavy,
        title: const ClinicalAppBarTitle(
          title: 'Product Details',
          eyebrow: 'Curated formulation',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                children: [
                  _buildHeroImage(p),
                  const SizedBox(height: 10),
                  _buildCategoryAndBadges(p),
                  const SizedBox(height: 6),
                  Text(
                    p.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: MyApp.textBrown,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.shortDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    strutStyle: const StrutStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      forceStrutHeight: true,
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      color: MyApp.textBrown.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  _buildPriceRow(p),
                  const SizedBox(height: 14),
                  _buildWhyRecommend(p),
                  if (p.clinicalNotes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildClinicalNotes(p),
                  ],
                  if (p.usage.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildUsage(p),
                  ],
                  if (bundled.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sectionHeader(
                      'Included in this kit',
                      Icons.card_giftcard_outlined,
                      'Bundle contents',
                    ),
                    const SizedBox(height: 8),
                    _miniCarousel(bundled, isFbt: false),
                  ],
                  if (fbt.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sectionHeader(
                      'Frequently bought together',
                      Icons.auto_awesome_motion_outlined,
                      'Patient pairings',
                    ),
                    const SizedBox(height: 8),
                    _miniCarousel(fbt, isFbt: true),
                  ],
                  if (p.tags.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildTagsWrap(p),
                  ],
                  const SizedBox(height: 12),
                  _buildAffiliateDisclosure(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroImage(Product p) {
    return AspectRatio(
      aspectRatio: 2.2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _kSoftNavy.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned.fill(
                child: CategoryArtwork(
                  product: p,
                  glyphSize: 56,
                  monogramSize: 24,
                  showPhoto: false,
                ),
              ),
              if (p.savingsPercent != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: MyApp.roseGold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'SAVE ${p.savingsPercent!.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryAndBadges(Product p) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: MyApp.roseGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(p.category.icon, size: 13, color: MyApp.roseGold),
              const SizedBox(width: 5),
              Text(
                p.category.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: MyApp.roseGold,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
        for (final b in p.badges) _BadgePill(badge: b),
      ],
    );
  }

  Widget _buildRatingLine(Product p) {
    return Row(
      children: [
        for (int i = 0; i < 5; i++)
          Icon(
            i < p.rating.round()
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            size: 16,
            color: _kAccentGold,
          ),
        const SizedBox(width: 6),
        Text(
          '${p.rating.toStringAsFixed(1)} · ${p.ratingCount} reviews',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: MyApp.textBrown.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(Product p) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '\$${p.price.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: MyApp.textBrown,
              height: 1.0,
            ),
          ),
          if (p.originalPrice != null) ...[
            const SizedBox(width: 6),
            Text(
              '\$${p.originalPrice!.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 13,
                decoration: TextDecoration.lineThrough,
                color: MyApp.textBrown.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          _buildRatingLine(p),
        ],
      ),
    );
  }

  Widget _buildWhyRecommend(Product p) {
    final snippet = _compactSnippet(p.whyRecommend);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            MyApp.roseGold.withValues(alpha: 0.15),
            _kAccentGold.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: MyApp.roseGold.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: MyApp.roseGold),
              const SizedBox(width: 6),
              Text(
                'Why we recommend it',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: MyApp.roseGold,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            snippet,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.42,
              color: MyApp.textBrown,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicalNotes(Product p) {
    return _infoCard(
      icon: Icons.medical_services_outlined,
      title: 'Expert Notes',
      body: p.clinicalNotes,
      tint: _kSoftNavy,
    );
  }

  Widget _buildUsage(Product p) {
    return _infoCard(
      icon: Icons.schedule_outlined,
      title: 'How to Use',
      body: p.usage,
      tint: _kAccentGold,
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String body,
    required Color tint,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: _kSoftNavy.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: tint,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.42,
              color: MyApp.textBrown,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, [String? eyebrow]) {
    return ClinicalSectionHeader(icon: icon, title: title, eyebrow: eyebrow);
  }

  Widget _miniCarousel(List<Product> items, {required bool isFbt}) {
    return SizedBox(
      height: 255,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4, top: 2),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => SizedBox(
          width: 175,
          child: _MiniProductCard(
            product: items[i],
            onTap: () => _openDetail(items[i]),
            onAdd: isFbt ? () => _quickAdd(items[i]) : null,
          ),
        ),
      ),
    );
  }

  Widget _buildTagsWrap(Product p) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in p.tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.3)),
            ),
            child: Text(
              t,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: MyApp.textBrown.withValues(alpha: 0.75),
                letterSpacing: 0.3,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAffiliateDisclosure() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyApp.textBrown.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.handshake_outlined,
            size: 18,
            color: MyApp.textBrown.withValues(alpha: 0.65),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Buy via our affiliate partner. We may earn a small commission at no extra cost to you.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: MyApp.textBrown.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: _kSoftNavy.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _QtyStepper(
                quantity: _quantity,
                onChange: (q) => setState(() => _quantity = q),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.roseGold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _buying ? null : _buyNow,
                    icon: _buying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.open_in_new, size: 16),
                    label: const Text(
                      'Buy Now',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: MyApp.textBrown,
                side: BorderSide(
                  color: MyApp.roseGold.withValues(alpha: 0.6),
                  width: 1.4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _adding ? null : _addToCart,
              icon: _adding
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.shopping_bag_outlined, size: 16),
              label: Text(
                'Add to Cart',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: MyApp.textBrown,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Buy securely via our affiliate partner.',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: MyApp.textBrown.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.badge});
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        badge.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.quantity, required this.onChange});
  final int quantity;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            color: MyApp.textBrown,
            onPressed: quantity > 1 ? () => onChange(quantity - 1) : null,
          ),
          SizedBox(
            width: 22,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: MyApp.textBrown,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            color: MyApp.textBrown,
            onPressed: quantity < 10 ? () => onChange(quantity + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _MiniProductCard extends StatelessWidget {
  const _MiniProductCard({
    required this.product,
    required this.onTap,
    this.onAdd,
  });
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
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
            border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: _kSoftNavy.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: MyApp.roseGold.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 118,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CategoryArtwork(
                          product: product,
                          glyphSize: 40,
                          monogramSize: 20,
                          compact: true,
                          showPhoto: false,
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.16),
                                  Colors.white.withValues(alpha: 0.0),
                                  Colors.black.withValues(alpha: 0.04),
                                ],
                                stops: const [0.0, 0.55, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 8, 11, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.category.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.2,
                          fontWeight: FontWeight.w800,
                          color: MyApp.roseGold,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: MyApp.textBrown,
                          height: 1.18,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '\$${product.price.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: MyApp.textBrown,
                              ),
                            ),
                          ),
                          if (onAdd != null)
                            Material(
                              color: MyApp.roseGold,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: onAdd,
                                child: const SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: Icon(
                                    Icons.add,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
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

String _compactSnippet(String raw) {
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.length <= 115) return text;
  final firstSentence = text.split('.').first.trim();
  if (firstSentence.isNotEmpty && firstSentence.length <= 115) {
    return '$firstSentence.';
  }
  return '${text.substring(0, 112).trim()}...';
}
