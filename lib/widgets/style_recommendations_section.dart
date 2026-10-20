// "Recommended for your style": curated products from the user's selected
// skincare styles (skincare_style_catalog.dart). Premium only -- free users
// see a locked state with an upgrade action. Separate from, and leaves
// unchanged, the metric-based recommendations.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/premium_access.dart';
import '../utils/skincare_style_catalog.dart';
import 'paywall_screen.dart';

class StyleRecommendationsSection extends StatefulWidget {
  const StyleRecommendationsSection({
    super.key,
    this.loadStyles = loadSkincareStyles,
    this.isPremium = PremiumAccess.isPremiumUser,
    this.limit = 8,
  });

  final Future<Set<SkincareStyle>> Function() loadStyles;
  final Future<bool> Function() isPremium;
  final int limit;

  static const String title = 'Recommended for your style';
  static const String disclaimer =
      'General product ideas for the styles you chose, not personalized '
      'medical advice. Talk with a licensed provider before starting '
      'anything new.';

  @override
  State<StyleRecommendationsSection> createState() =>
      _StyleRecommendationsSectionState();
}

class _StyleRecommendationsSectionState
    extends State<StyleRecommendationsSection> {
  Set<SkincareStyle>? _styles;
  bool _premium = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final styles = await widget.loadStyles();
    final premium = await widget.isPremium();
    if (!mounted) return;
    setState(() {
      _styles = styles;
      _premium = premium;
    });
  }

  Future<void> _upgrade() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PaywallScreen()));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final styles = _styles;
    if (styles == null) return const SizedBox.shrink();
    const ink = AppColors.textStructure;
    final selectedLabels = [
      for (final style in SkincareStyle.values)
        if (styles.contains(style)) style.label,
    ].join(', ');

    Widget body;
    if (styles.isEmpty) {
      body = Text(
        'Choose your skincare style in Settings to see picks.',
        key: const ValueKey('style_recs_no_style'),
        style: TextStyle(color: ink.withValues(alpha: 0.75)),
      );
    } else if (!_premium) {
      body = Column(
        key: const ValueKey('style_recs_locked'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 18, color: ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Premium: curated $selectedLabels picks',
                  style: const TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('style_recs_upgrade'),
            onPressed: _upgrade,
            child: const Text('Upgrade to see picks'),
          ),
        ],
      );
    } else {
      final picks = styleRecommendations(styles, limit: widget.limit);
      body = Column(
        key: const ValueKey('style_recs_list'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final product in picks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${product.description} · ${product.style.label}',
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.75),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            StyleRecommendationsSection.disclaimer,
            style: TextStyle(
              color: ink.withValues(alpha: 0.65),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    return Container(
      key: const ValueKey('style_recommendations_section'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            StyleRecommendationsSection.title,
            style: TextStyle(
              color: ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }
}
