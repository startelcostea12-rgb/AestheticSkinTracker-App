// lib/widgets/category_artwork.dart
//
// Premium per-product image surface.
//
// Renders an elegant gradient + soft accents as the BASE layer (always
// visible), then overlays the product's high-resolution network photo on
// top with a smooth fade-in. If the network image fails or is empty, the
// gradient artwork remains as a graceful fallback — every product card
// always looks polished.

import 'package:flutter/material.dart';

import '../models/product.dart';

const Color _kSoftNavy = Color(0xFF1F3A5F);
const Color _kAccentGold = Color(0xFFB8924C);

class CategoryArtwork extends StatelessWidget {
  const CategoryArtwork({
    super.key,
    required this.product,
    this.glyphSize = 44,
    this.monogramSize = 24,
    this.compact = false,
    this.showPhoto = true,
  });

  final Product product;
  final double glyphSize;
  final double monogramSize;
  final bool compact;

  /// When true (default) the product's network photo is overlaid on top
  /// of the gradient. Set false to render the artwork only.
  final bool showPhoto;

  static const _palettes = <ProductCategory, List<Color>>{
    ProductCategory.peptides: [Color(0xFFF5D9D0), Color(0xFFDEAE9E)],
    ProductCategory.serums: [Color(0xFFEDD9C8), Color(0xFFD0A882)],
    ProductCategory.hydration: [Color(0xFFD8E8F4), Color(0xFFB0CEEA)],
    ProductCategory.spf: [Color(0xFFF8E6B0), Color(0xFFE8C050)],
    ProductCategory.recovery: [Color(0xFFDEEDD5), Color(0xFFB4CFA2)],
    ProductCategory.supplements: [Color(0xFFEDD8F2), Color(0xFFC8A6D8)],
    ProductCategory.tools: [Color(0xFFDDD6F0), Color(0xFFBAAED8)],
    ProductCategory.bundles: [Color(0xFFF8DCC4), Color(0xFFDEA868)],
  };

  String get _monogram {
    final words = product.name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '';
    if (words.length == 1) {
      return words.first
          .substring(0, words.first.length.clamp(0, 2))
          .toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        _palettes[product.category] ??
        const [Color(0xFFF6ECE3), Color(0xFFE5CDB9)];

    final artwork = _ArtworkBackdrop(
      colors: colors,
      icon: product.category.icon,
      monogram: _monogram,
      categoryLabel: product.category.label,
      glyphSize: glyphSize,
      monogramSize: monogramSize,
      compact: compact,
    );

    if (!showPhoto || (product.imageUrl?.isEmpty ?? true)) {
      return artwork;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        artwork,
        // Real product photo overlay — fades in when loaded.
        Image.network(
          product.imageUrl!,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSyncLoaded) {
            if (wasSyncLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ArtworkBackdrop extends StatelessWidget {
  const _ArtworkBackdrop({
    required this.colors,
    required this.icon,
    required this.monogram,
    required this.categoryLabel,
    required this.glyphSize,
    required this.monogramSize,
    required this.compact,
  });

  final List<Color> colors;
  final IconData icon;
  final String monogram;
  final String categoryLabel;
  final double glyphSize;
  final double monogramSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ),
          Positioned(
            left: -30,
            bottom: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: glyphSize,
                  color: _kSoftNavy.withValues(alpha: 0.65),
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Text(
                    monogram,
                    style: TextStyle(
                      fontSize: monogramSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                      color: _kSoftNavy.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 26,
                    height: 2,
                    decoration: BoxDecoration(
                      color: _kAccentGold.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!compact)
            Positioned(
              left: 10,
              bottom: 8,
              child: Text(
                categoryLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: _kSoftNavy.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
