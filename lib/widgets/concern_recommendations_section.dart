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
  static const String noneElevatedText =
      'Redness, pigment, texture and pores are all 25 or below (out of 100) '
      'on your latest comparable scan.';
  static const String disclaimer =
      'General product ideas based on your latest comparable scan, not '
      'medical advice. Talk with a licensed provider before starting '
      'anything new.';

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
    final muted = ink.withValues(alpha: 0.75);
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
            style: TextStyle(
              color: ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (groups == null)
            Text(
              ConcernRecommendationsSection.noComparableText,
              key: const ValueKey('concern_recs_no_comparable'),
              style: TextStyle(color: muted, height: 1.35),
            )
          else if (groups.isEmpty)
            Text(
              ConcernRecommendationsSection.noneElevatedText,
              key: const ValueKey('concern_recs_none_elevated'),
              style: TextStyle(color: muted, height: 1.35),
            )
          else ...[
            for (final group in groups) ...[
              const SizedBox(height: 6),
              Text(
                group.concern.heading,
                key: ValueKey('concern_group_${group.concern.engineKey}'),
                style: const TextStyle(color: ink, fontWeight: FontWeight.w800),
              ),
              for (final product
                  in _premium ? group.products : group.products.take(1))
                ListTile(
                  key: ValueKey(
                    'concern_product_${group.concern.engineKey}_'
                    '${product.productName}',
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(product.productName),
                  subtitle: Text(product.brand),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _open(product),
                ),
            ],
            if (hiddenCount > 0)
              TextButton(
                key: const ValueKey('concern_recs_upgrade'),
                onPressed: _upgrade,
                child: Text(
                  'See $hiddenCount more pick${hiddenCount == 1 ? '' : 's'} '
                  'with Premium',
                ),
              ),
            const SizedBox(height: 6),
            Text(
              ConcernRecommendationsSection.disclaimer,
              style: TextStyle(color: muted, fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}
