// lib/widgets/scan_based_recommendations_card.dart
//
// Tabbed recommendation card surfaced on the home screen, powered by
// ScanBasedRecommendationEngine. Three sections: Peptides | Procedures | Products.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/scan_history.dart';
import '../utils/ai_product_recommendation_engine.dart';
import '../utils/scan_based_recommendation_engine.dart';

class ScanBasedRecommendationsCard extends StatefulWidget {
  final SkinMetrics latest;
  final SkinMetrics? baseline;
  final String? procedureType;
  final Map<String, double>? latestBody;
  final Map<String, double>? baselineBody;

  const ScanBasedRecommendationsCard({
    super.key,
    required this.latest,
    this.baseline,
    this.procedureType,
    this.latestBody,
    this.baselineBody,
  });

  @override
  State<ScanBasedRecommendationsCard> createState() =>
      _ScanBasedRecommendationsCardState();
}

class _ScanBasedRecommendationsCardState
    extends State<ScanBasedRecommendationsCard> {
  int _selected = 0; // 0 = peptides, 1 = procedures, 2 = products

  static const _rose = AppColors.champagneGold;
  static const _gold = AppColors.mutedSage;
  static const _textBrown = AppColors.refinedSlate;
  static const _muted = AppColors.refinedSlate;
  static const _surface = AppColors.cardBackground;

  @override
  Widget build(BuildContext context) {
    final rec = ScanBasedRecommendationEngine.generate(
      latest: widget.latest,
      baseline: widget.baseline,
      procedureType: widget.procedureType,
      latestBody: widget.latestBody,
      baselineBody: widget.baselineBody,
    );

    final hasAnything =
        rec.peptides.isNotEmpty ||
        rec.procedures.isNotEmpty ||
        rec.products.isNotEmpty;
    if (!hasAnything) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _rose.withValues(alpha: 0.08),
            _gold.withValues(alpha: 0.05),
            AppColors.cardBackground.withValues(alpha: 0.96),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borders, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _rose.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(rec),
          _summary(rec),
          if (rec.bodyDeltas.isNotEmpty) _bodyDeltasStrip(rec),
          _segmented(rec),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            child: _body(rec),
          ),
        ],
      ),
    );
  }

  Widget _header(ScanRecommendations rec) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: _rose.withValues(alpha: 0.10),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_rose, _gold],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Recommendations from Your Scan',
                  style: TextStyle(
                    color: _textBrown,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  rec.headline,
                  style: TextStyle(
                    color: _textBrown.withValues(alpha: 0.70),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(ScanRecommendations rec) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        rec.summary,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: _textBrown,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // Compact body composition delta strip — shown above the segmented tabs
  // when the user has body metrics tracked.
  Widget _bodyDeltasStrip(ScanRecommendations rec) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.softTerracotta.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.softTerracotta.withValues(alpha: 0.22),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.fitness_center_rounded,
                  size: 14,
                  color: AppColors.softTerracotta,
                ),
                SizedBox(width: 6),
                Text(
                  'Body Composition',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.softTerracotta,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: rec.bodyDeltas.map((d) => _bodyDeltaTile(d)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyDeltaTile(MetricDelta d) {
    final improved = d.improved;
    final color = improved ? AppColors.mutedSage : AppColors.softTerracotta;
    final bg = improved
        ? AppColors.mutedSage.withValues(alpha: 0.12)
        : AppColors.softTerracotta.withValues(alpha: 0.12);
    final border = improved
        ? AppColors.mutedSage.withValues(alpha: 0.28)
        : AppColors.softTerracotta.withValues(alpha: 0.28);
    final arrow = d.delta < 0 ? '\u2193' : '\u2191';
    final deltaAbs = d.delta.abs().toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            d.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${d.baseline.toStringAsFixed(1)}\u2192${d.latest.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$arrow$deltaAbs',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmented(ScanRecommendations rec) {
    final tabs = [
      ('Peptides', rec.peptides.length, Icons.science_outlined),
      ('Procedures', rec.procedures.length, Icons.medical_services_outlined),
      ('Products', rec.products.length, Icons.shopping_bag_outlined),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _rose.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final active = i == _selected;
            final (label, count, icon) = tabs[i];
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selected = i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? _rose : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 14,
                        color: active ? Colors.white : _muted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '$label · $count',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: active ? Colors.white : _textBrown,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _body(ScanRecommendations rec) {
    switch (_selected) {
      case 0:
        return _peptidesBody(rec);
      case 1:
        return _proceduresBody(rec);
      default:
        return _productsBody(rec);
    }
  }

  Widget _peptidesBody(ScanRecommendations rec) {
    if (rec.peptides.isEmpty) {
      return _emptyState(
        'No peptide recommendations right now — your scan is in healthy range across the board.',
      );
    }
    return Column(
      children: rec.peptides
          .map(
            (p) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _peptideCard(p),
            ),
          )
          .toList(),
    );
  }

  Widget _peptideCard(PeptideRecommendation p) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _rose.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: _rose.withValues(alpha: 0.06),
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
              Expanded(
                child: Text(
                  p.entry.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _textBrown,
                  ),
                ),
              ),
              _tierBadge(p.entry.evidenceLevel),
            ],
          ),
          if (p.entry.inci.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                p.entry.inci,
                style: const TextStyle(
                  fontSize: 11,
                  color: _muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            p.reason,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: _textBrown,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _gold.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt, color: _gold, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.expectedBenefit,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: _textBrown,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (p.matchedMetrics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: p.matchedMetrics
                  .map((m) => _chip(m, Icons.center_focus_strong_outlined))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _proceduresBody(ScanRecommendations rec) {
    if (rec.procedures.isEmpty) {
      return _emptyState(
        'No procedure recommendations — your metrics are well-controlled through home care.',
      );
    }
    return Column(
      children: rec.procedures
          .map(
            (p) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _procedureCard(p),
            ),
          )
          .toList(),
    );
  }

  Widget _procedureCard(ProcedureRecommendation p) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: _gold.withValues(alpha: 0.07),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  p.category,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF8A5D17),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _tierBadge(p.evidenceTier),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            p.name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _textBrown,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            p.mechanism,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: _muted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            p.reason,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: _textBrown,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (p.matchedMetrics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: p.matchedMetrics
                  .map((m) => _chip(m, Icons.center_focus_strong_outlined))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _productsBody(ScanRecommendations rec) {
    if (rec.products.isEmpty) {
      return _emptyState(
        'No product recommendations available for this scan profile.',
      );
    }
    return Column(
      children: rec.products
          .map(
            (p) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _productCard(p),
            ),
          )
          .toList(),
    );
  }

  Widget _productCard(AIProductRecommendation p) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _rose.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: _rose.withValues(alpha: 0.05),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.productName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: _textBrown,
                      ),
                    ),
                    if (p.brand.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          p.brand,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _evidenceBadge(p.evidenceLevel),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            p.clinicalReason,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: _textBrown,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (p.usageGuidance.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.tips_and_updates_outlined,
                  size: 14,
                  color: _muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    p.usageGuidance,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: _muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _tierBadge(String tier) {
    Color bg;
    Color fg;
    switch (tier) {
      case 'Tier 1':
        bg = AppColors.mutedSage.withValues(alpha: 0.12);
        fg = AppColors.mutedSage;
        break;
      case 'Tier 2':
        bg = AppColors.champagneGold.withValues(alpha: 0.14);
        fg = AppColors.champagneGold;
        break;
      default:
        bg = const Color(0xFFF3EAE3);
        fg = _muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        tier,
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _evidenceBadge(String level) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _rose.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        level,
        style: const TextStyle(
          fontSize: 9.5,
          color: _rose,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _chip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _rose.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: _muted),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 10.5,
              color: _textBrown,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _rose.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 18, color: _muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: _textBrown,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
