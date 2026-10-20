// "For your concerns": the existing metric-based product recommendations
// grouped by concern (redness, pigment, texture, pores) from the latest
// comparable AI scan. Free users see every concern heading with its top
// pick; Premium shows each concern's full list. Tapping a product opens
// the product lookup detail (Add to routine / Save for later).

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/scan_history.dart';
import '../screens/product_lookup_detail_screen.dart';
import '../utils/ai_product_recommendation_engine.dart';
import '../utils/concern_recommendations.dart';
import '../utils/premium_access.dart';
import '../utils/product_lookup.dart';
import 'home_section_style.dart';
import 'premium_more_picks_link.dart';
import 'paywall_screen.dart';

class ConcernRecommendationsSection extends StatefulWidget {
  const ConcernRecommendationsSection({
    super.key,
    required this.scans,
    this.isPremium = PremiumAccess.isPremiumUser,
    this.productsFor = AIProductRecommendationEngine.productsForConcern,
  });

  final List<ScanHistoryEntry> scans;
  final Future<bool> Function() isPremium;
  final ConcernProductSource productsFor;

  static const String title = 'For your concerns';
  static const String noComparableText =
      'Picks for your concerns appear after a follow-up scan that is '
      'comparable with your baseline.';
  // Non-breaking spaces keep "25 or below (out of 100)" on one line on
  // narrow phones instead of splitting the number from its scale.
  static const String noneElevatedText =
      'Redness, pigment, texture and pores are all '
      '25\u00A0or\u00A0below (out\u00A0of\u00A0100) on your latest comparable '
      'scan.';
  static const String disclaimer =
      'General product ideas from your latest comparable scan, not medical '
      'advice. Talk with a licensed provider before starting anything new.';

  @override
  State<ConcernRecommendationsSection> createState() =>
      _ConcernRecommendationsSectionState();
}

class _ConcernRecommendationsSectionState
    extends State<ConcernRecommendationsSection> {
  bool _premium = false;

  @override
  void initState() {
    super.initState();
    _loadPremium();
  }

  Future<void> _loadPremium() async {
    final premium = await widget.isPremium();
    if (mounted) setState(() => _premium = premium);
  }

  Future<void> _upgrade() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PaywallScreen()));
    await _loadPremium();
  }

  void _open(AIProductRecommendation product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductLookupDetailScreen(
          product: LookupProduct(
            name: product.productName,
            brand: product.brand,
            description: product.clinicalReason,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.textStructure;
    final groups = concernGroupsForScans(
      widget.scans,
      productsFor: widget.productsFor,
    );
    final hiddenCount = _premium || groups == null
        ? 0
        : groups.fold<int>(0, (sum, g) => sum + g.products.length - 1);

    return Container(
      key: const ValueKey('concern_recs_section'),
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
            ConcernRecommendationsSection.title,
            style: homeSectionTitleStyle,
          ),
          const SizedBox(height: homeSectionTitleGap),
          if (groups == null)
            Text(
              ConcernRecommendationsSection.noComparableText,
              key: const ValueKey('concern_recs_no_comparable'),
              style: homeSectionMessageStyle(),
            )
          else if (groups.isEmpty)
            Text(
              ConcernRecommendationsSection.noneElevatedText,
              key: const ValueKey('concern_recs_none_elevated'),
              style: homeSectionMessageStyle(),
            )
          else ...[
            for (final group in groups) ...[
              Text(
                group.concern.heading,
                key: ValueKey('concern_group_${group.concern.engineKey}'),
                style: TextStyle(
                  color: ink.withValues(alpha: 0.7),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              for (final product
                  in _premium ? group.products : group.products.take(1))
                _productRow(group, product),
            ],
            if (hiddenCount > 0)
              PremiumMorePicksLink(
                key: const ValueKey('concern_recs_upgrade'),
                hiddenCount: hiddenCount,
                onPressed: _upgrade,
              ),
            const SizedBox(height: 4),
            Text(
              ConcernRecommendationsSection.disclaimer,
              style: homeSectionDisclaimerStyle(),
            ),
          ],
        ],
      ),
    );
  }

  /// Same look as a "Recommended for your style" row (name, then a muted
  /// line), plus a chevron because it opens the product.
  Widget _productRow(ConcernGroup group, AIProductRecommendation product) {
    return InkWell(
      key: ValueKey(
        'concern_product_${group.concern.engineKey}_${product.productName}',
      ),
      onTap: () => _open(product),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    style: const TextStyle(
                      color: AppColors.textStructure,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(product.brand, style: homeSectionSubtleStyle()),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textStructure,
            ),
          ],
        ),
      ),
    );
  }
}
