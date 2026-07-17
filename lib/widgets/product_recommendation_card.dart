import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../utils/ai_product_recommendation_engine.dart';

/// Displays a single clinician-recommended product with image, reason, usage, and affiliate link.
class ProductRecommendationCard extends StatelessWidget {
  final AIProductRecommendation recommendation;
  final VoidCallback? onTapLink;

  const ProductRecommendationCard({
    super.key,
    required this.recommendation,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyApp.goldShimmer.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image + name/brand
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image placeholder
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: MyApp.champagne,
                  border: Border.all(
                    color: MyApp.goldShimmer.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: recommendation.imageUrl.startsWith('http')
                      ? Image.network(
                          recommendation.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: MyApp.goldShimmer.withValues(alpha: 0.4),
                              size: 32,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.shopping_bag_outlined,
                            color: MyApp.goldShimmer,
                            size: 40,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Product name, brand, category badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    Text(
                      recommendation.productName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    // Brand
                    Text(
                      recommendation.brand,
                      style: TextStyle(
                        fontSize: 12,
                        color: MyApp.textBrown.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Category badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _categoryColor(
                          recommendation.category,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        recommendation.category,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _categoryColor(recommendation.category),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Clinical reason
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MyApp.champagne.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.15),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Why This Recommendation',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.champagneGold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  recommendation.clinicalReason,
                  style: TextStyle(
                    fontSize: 13,
                    color: MyApp.textBrown.withValues(alpha: 0.82),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Usage guidance
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Usage Guidance',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MyApp.textBrown.withValues(alpha: 0.7),
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                recommendation.usageGuidance,
                style: TextStyle(
                  fontSize: 12.5,
                  color: MyApp.textBrown.withValues(alpha: 0.75),
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Evidence level + Link row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Evidence badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _evidenceColor(
                    recommendation.evidenceLevel,
                  ).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _evidenceColor(
                      recommendation.evidenceLevel,
                    ).withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  recommendation.evidenceLevel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _evidenceColor(recommendation.evidenceLevel),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              // View on Amazon button
              GestureDetector(
                onTap: () {
                  onTapLink?.call();
                  _launchAffiliateLink(recommendation.affiliateLink);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.champagneGold, AppColors.goldHover],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.champagneGold.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'View',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Recovery Support':
        return AppColors.champagneGold;
      case 'Maintenance':
        return MyApp.goldShimmer;
      case 'Prevention':
        return AppColors.mutedSage;
      default:
        return MyApp.textBrown;
    }
  }

  Color _evidenceColor(String evidence) {
    switch (evidence) {
      case 'Proven efficacy':
        return AppColors.mutedSage;
      case 'Evidence-backed':
        return AppColors.refinedSlate;
      case 'Clinical consensus':
        return AppColors.softTerracotta;
      default:
        return AppColors.refinedSlate.withValues(alpha: 0.62);
    }
  }

  Future<void> _launchAffiliateLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Silently handle launch errors
      debugPrint('Error launching URL: $e');
    }
  }
}

/// Full-width section displaying clinician-recommended products with disclosure.
class ClinicalProductRecommendationsSection extends StatelessWidget {
  final List<AIProductRecommendation> recommendations;
  final String? sectionTitle;
  final String? sectionSubtitle;

  const ClinicalProductRecommendationsSection({
    super.key,
    required this.recommendations,
    this.sectionTitle,
    this.sectionSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    if (recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    final textColor = MyApp.textBrown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(Icons.spa_outlined, color: MyApp.clinicalTeal, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sectionTitle ?? 'Suggested Products',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: MyApp.clinicalNavy,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (sectionSubtitle?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      sectionSubtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: textColor.withValues(alpha: 0.65),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Product cards
        ...recommendations.asMap().entries.map((entry) {
          final index = entry.key;
          final recommendation = entry.value;
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < recommendations.length - 1 ? 14 : 0,
            ),
            child: ProductRecommendationCard(recommendation: recommendation),
          );
        }),
        const SizedBox(height: 16),
        // Amazon Associate disclosure
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.champagneGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.champagneGold.withValues(alpha: 0.22),
              width: 0.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.champagneGold,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'As an Amazon Associate I earn from qualifying purchases. These recommendations are based on clinical efficacy and your skin metrics.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.refinedSlate.withValues(alpha: 0.78),
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
