// "Recommended for your style": 4-6 curated products from the user's
// selected skincare styles (skincare_style_catalog.dart), filtered to the
// latest scan's top concerns when any match (style_concern_recommendations
// .dart), otherwise the general picks for those styles. Premium only --
// free users see a locked note with a "See your style picks with Premium"
// link (the same link style as the concerns section's "See N more
// picks"). Separate from, and leaves unchanged, the metric-based
// recommendations.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'home_section_style.dart';
import 'premium_more_picks_link.dart';
import '../utils/premium_access.dart';
import '../models/scan_history.dart';
import '../utils/skincare_style_catalog.dart';
import '../utils/style_concern_recommendations.dart';
import 'paywall_screen.dart';

class StyleRecommendationsSection extends StatefulWidget {
  const StyleRecommendationsSection({
    super.key,
    this.loadStyles = loadSkincareStyles,
    this.isPremium = PremiumAccess.isPremiumUser,
    this.scans = const <ScanHistoryEntry>[],
  });

  final Future<Set<SkincareStyle>> Function() loadStyles;
  final Future<bool> Function() isPremium;

  /// Scan history; the latest AI scan's concerns filter the picks.
  final List<ScanHistoryEntry> scans;

  static const String generalPicksText = 'Top picks for your style.';
  static String matchedText(List<String> concerns) {
    final names = concerns.join(concerns.length == 2 ? ' and ' : ', ');
    return 'Matched to your $names from your latest scan.';
  }

  static const String title = 'Recommended for your style';
  static const String lockedLinkLabel = 'See your style picks with Premium';
  static String lockedText(String styleLabels) =>
      'Curated picks for $styleLabels are part of Premium.';
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
        style: homeSectionMessageStyle(),
      );
    } else if (!_premium) {
      body = Column(
        key: const ValueKey('style_recs_locked'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            StyleRecommendationsSection.lockedText(selectedLabels),
            style: homeSectionMessageStyle(),
          ),
          const SizedBox(height: 4),
          PremiumUpsellLink(
            key: const ValueKey('style_recs_upgrade'),
            label: StyleRecommendationsSection.lockedLinkLabel,
            onPressed: _upgrade,
          ),
        ],
      );
    } else {
      final result = stylePicksFor(
        styles,
        currentStyleConcernTags(widget.scans),
      );
      body = Column(
        key: const ValueKey('style_recs_list'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.isFallback
                ? StyleRecommendationsSection.generalPicksText
                : StyleRecommendationsSection.matchedText(
                    result.matchedConcerns,
                  ),
            key: ValueKey(
              result.isFallback ? 'style_recs_general' : 'style_recs_matched',
            ),
            style: homeSectionMessageStyle(),
          ),
          const SizedBox(height: 8),
          for (final product in result.products)
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
                    '${product.brand} · ${product.category.label}',
                    style: homeSectionSubtleStyle(),
                  ),
                  Text(
                    '${product.description} · ${product.style.label}',
                    style: homeSectionSubtleStyle(),
                  ),
                ],
              ),
            ),
          Text(
            StyleRecommendationsSection.disclaimer,
            style: homeSectionDisclaimerStyle(),
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
            style: homeSectionTitleStyle,
          ),
          const SizedBox(height: homeSectionTitleGap),
          body,
        ],
      ),
    );
  }
}
