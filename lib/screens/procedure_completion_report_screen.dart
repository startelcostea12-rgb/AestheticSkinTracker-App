import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/scan_history.dart';
import '../utils/ai_product_recommendation_engine.dart';
import '../utils/app_logger.dart';
import '../widgets/product_recommendation_card.dart';
import '../widgets/clinical_section_header.dart';

// ─── Data Model ──────────────────────────────────────────────────────────────

/// All data needed to render a Procedure Completion Report.
/// Assembled by _ProcedureDetailScreenState so we can keep _ScanEntry private.
class ProcedureCompletionData {
  final String procedureType;
  final String provider;
  final DateTime startDate;

  /// Before photo: Uint8List (web/bytes) or file-path String, or null.
  final dynamic beforePhoto;

  /// After photo: Uint8List (web/bytes) or file-path String, or null.
  final dynamic afterPhoto;

  /// Metric map from the first (baseline) scan.
  final Map<String, double> beforeMetrics;

  /// Metric map from the most recent (after) scan.
  final Map<String, double> afterMetrics;

  final int userChronologicalAge;
  final int scanCount;

  const ProcedureCompletionData({
    required this.procedureType,
    required this.provider,
    required this.startDate,
    this.beforePhoto,
    this.afterPhoto,
    required this.beforeMetrics,
    required this.afterMetrics,
    required this.userChronologicalAge,
    required this.scanCount,
  });
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class ProcedureCompletionReportScreen extends StatelessWidget {
  final ProcedureCompletionData data;

  const ProcedureCompletionReportScreen({super.key, required this.data});

  // ── Helpers ────────────────────────────────────────────────────────────────

  SkinMetrics _toSkinMetrics(Map<String, double> m) => SkinMetrics(
    redness: m['redness'] ?? 5.0,
    texture: m['texture'] ?? 5.0,
    wrinkle: m['wrinkles'] ?? m['wrinkle'] ?? 5.0,
    pore: m['pores'] ?? m['pore'] ?? 5.0,
    darkSpots: m['darkSpots'] ?? 5.0,
    elasticity: m['elasticity'] ?? 6.0,
  );

  /// Improvement %: positive = improved.
  /// For lower-is-better metrics: (before − after) / before × 100.
  /// For elasticity (higher-is-better): (after − before) / before × 100.
  double _pct(double before, double after, {bool higherIsBetter = false}) {
    if (before == 0) return 0;
    return higherIsBetter
        ? ((after - before) / before * 100)
        : ((before - after) / before * 100);
  }

  String _metricOutcomeText(
    String key,
    double percent,
    bool improved,
    bool stable,
  ) {
    final rounded = percent.abs().toStringAsFixed(0);
    if (stable) {
      switch (key) {
        case 'pores':
          return 'Pore appearance remained stable';
        case 'darkSpots':
          return 'Dark spot pigmentation remained stable';
        case 'redness':
          return 'Redness remained clinically stable';
        case 'texture':
          return 'Texture and smoothness remained stable';
        case 'wrinkles':
          return 'Fine lines and wrinkles remained stable';
        case 'elasticity':
          return 'Elasticity remained stable';
        default:
          return 'Metric remained stable';
      }
    }

    switch (key) {
      case 'pores':
        return improved
            ? 'Pores decreased by $rounded%'
            : 'Pores increased by $rounded%';
      case 'darkSpots':
        return improved
            ? 'Dark spots reduced by $rounded%'
            : 'Dark spots increased by $rounded%';
      case 'redness':
        return improved
            ? 'Redness improved by $rounded%'
            : 'Redness increased by $rounded%';
      case 'texture':
        return improved
            ? 'Texture / Smoothness improved by $rounded%'
            : 'Texture / Smoothness worsened by $rounded%';
      case 'wrinkles':
        return improved
            ? 'Wrinkles softened by $rounded%'
            : 'Wrinkles increased by $rounded%';
      case 'elasticity':
        return improved
            ? 'Elasticity increased by $rounded%'
            : 'Elasticity decreased by $rounded%';
      default:
        return improved ? 'Improved by $rounded%' : 'Changed by $rounded%';
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Copy helpers ───────────────────────────────────────────────────────────

  String _overallSummary() {
    final beforeAge = estimateVisualSkinAge(
      _toSkinMetrics(data.beforeMetrics),
    ).round();
    final afterAge = estimateVisualSkinAge(
      _toSkinMetrics(data.afterMetrics),
    ).round();
    final diff = beforeAge - afterAge;
    final ageNote = diff > 0
        ? ', taking an estimated $diff year${diff == 1 ? '' : 's'} off your apparent skin age'
        : '';
    final scanNote = data.scanCount > 1
        ? 'Measurable changes were captured across ${data.scanCount} tracked sessions.'
        : 'Your baseline has been established and is ready for ongoing comparison.';
    return 'Your skin showed significant improvement after your ${data.procedureType} procedure$ageNote. $scanNote';
  }

  String _recoveryInsights() {
    switch (data.procedureType) {
      case 'Microneedling':
      case 'RF Microneedling':
        return 'Collagen induction from microneedling typically continues to mature for 3–6 months post-treatment. '
            'The improvements in texture, pore appearance, and elasticity captured here reflect early collagen remodeling. '
            'Maintaining consistent SPF use and a hydrating routine will support continued refinement of your results.';
      case 'Halo Laser':
      case 'Fractional Laser':
      case 'CO2 Laser Resurfacing':
        return 'Laser resurfacing outcomes evolve considerably over 3–6 months as deeper collagen regeneration occurs beneath the surface. '
            'The texture, tone, and pigmentation improvements recorded reflect successful epidermal renewal. '
            'Diligent sun protection and a retinoid-containing regimen will help consolidate and prolong your results.';
      case 'Chemical Peel':
        return 'Chemical peels improve skin clarity and texture through controlled accelerated cell turnover. '
            'The pigmentation and surface-smoothness gains in your data reflect healthy cellular renewal. '
            'Follow-up peels at appropriate intervals and consistent broad-spectrum SPF will preserve these improvements.';
      case 'IPL':
        return 'IPL photofacial outcomes for pigmentation and vascular concerns are typically cumulative across a series. '
            'Your data captures meaningful improvements in redness and dark spot distribution. '
            'Ongoing sun avoidance and SPF 50+ daily are essential to maintaining these results long term.';
      case 'Morpheus8':
        return 'Morpheus8 radiofrequency results continue to improve for up to 6 months as deep tissue remodeling progresses. '
            'The early textural and elasticity gains captured here are strong indicators of ongoing collagen production. '
            'Sun protection and consistent hydration are key to optimizing your outcome.';
      case 'Botox / Dysport / Xeomin':
      case 'Dermal Fillers':
        return 'Neuromodulator and filler outcomes are best evaluated over 2–4 weeks as the product fully settles. '
            'Consistency with your treatment schedule and a strong skincare foundation will support natural-looking, lasting results.';
      default:
        return 'The improvements captured in your scan data reflect successful tissue healing and a positive recovery response. '
            'Continue your provider\'s post-care guidance and maintain consistent sun protection to preserve and extend your results. '
            'Follow-up assessments are recommended to evaluate long-term outcomes.';
    }
  }

  String _closingNote() {
    switch (data.procedureType) {
      case 'Microneedling':
      case 'RF Microneedling':
      case 'Morpheus8':
        return 'Your collagen renewal journey is well underway. The metrics captured represent real, measurable change in your skin biology. '
            'Stay the course with your home-care routine, protect your results with SPF, and return to your provider at the recommended '
            'interval to build further on this excellent foundation.';
      case 'Halo Laser':
      case 'Fractional Laser':
      case 'CO2 Laser Resurfacing':
        return 'Laser resurfacing results are among the most dramatic and durable outcomes in aesthetic medicine — and your data supports that. '
            'The skin age improvement you\'ve achieved reflects genuine structural change. Prioritize sun avoidance, and continue '
            'tracking to watch your results deepen over the coming months.';
      case 'Chemical Peel':
        return 'A well-executed peel and a committed recovery are a powerful combination. Your consistency with scanning has captured '
            'something many patients never see: objective, quantified proof of improvement. Keep your regimen strong and revisit '
            'in 6–8 weeks to assess further gains.';
      case 'Botox / Dysport / Xeomin':
      case 'Dermal Fillers':
        return 'Injectables work best as part of an ongoing, thoughtful aesthetic plan. Your tracking data creates a valuable baseline '
            'for assessing treatment longevity and scheduling your next session at the right time. Well done for taking a data-driven approach to your care.';
      default:
        return 'Your commitment to tracking this procedure from start to finish is exactly the kind of disciplined, data-driven approach '
            'that leads to better outcomes. Share this report with your provider at your next visit — it tells a clear, objective story '
            'of your recovery. You have done exceptionally well.';
    }
  }

  // ── Photo widget ───────────────────────────────────────────────────────────

  Widget _photo(dynamic src, String label, double height) {
    Widget imageWidget;
    if (src is Uint8List && src.isNotEmpty) {
      imageWidget = Image.memory(
        src,
        fit: BoxFit.cover,
        height: height,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _photoPlaceholder(label, height),
      );
    } else if (src is String && src.isNotEmpty) {
      if (kIsWeb || src.startsWith('http') || src.startsWith('data:image')) {
        imageWidget = Image.network(
          src,
          fit: BoxFit.cover,
          height: height,
          width: double.infinity,
          errorBuilder: (_, __, ___) => _photoPlaceholder(label, height),
        );
      } else {
        imageWidget = Image.file(
          io.File(src),
          fit: BoxFit.cover,
          height: height,
          width: double.infinity,
          errorBuilder: (_, __, ___) => _photoPlaceholder(label, height),
        );
      }
    } else {
      imageWidget = _photoPlaceholder(label, height);
    }
    return SizedBox(height: height, width: double.infinity, child: imageWidget);
  }

  Widget _photoPlaceholder(String label, double height) => Container(
    height: height,
    width: double.infinity,
    color: Colors.grey[200],
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 38, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        ],
      ),
    ),
  );

  // ── Section builders ───────────────────────────────────────────────────────

  Widget _heroHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF5D28A), Color(0xFFE8A8B5), Color(0xFFF5E6A0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE0C070).withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        children: [
          const Text('✦', style: TextStyle(fontSize: 36, color: Colors.white)),
          const SizedBox(height: 10),
          Text(
            'PROCEDURE COMPLETE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 3.0,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            data.procedureType,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.2,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.provider,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Started ${_fmt(data.startDate)}  ·  ${data.scanCount} scan${data.scanCount == 1 ? '' : 's'} tracked',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overallSummaryCard(Color textColor) {
    return Container(
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: MyApp.goldShimmer, size: 22),
              const SizedBox(width: 10),
              Text(
                'Overall Improvement',
                style: MyApp.cardTitleStyle(color: textColor),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _overallSummary(),
            style: TextStyle(
              fontSize: 15,
              color: textColor.withValues(alpha: 0.83),
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }

  Widget _beforeAfterCard(Color textColor) {
    const photoH = 220.0;
    return Container(
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: MyApp.goldShimmer.withValues(alpha: 0.30),
          width: 1.2,
        ),
        boxShadow: MyApp.cardShadow,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_rounded, color: MyApp.roseGold, size: 22),
              const SizedBox(width: 10),
              Text(
                'Before & After',
                style: MyApp.cardTitleStyle(color: textColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _photo(data.beforePhoto, 'Before', photoH),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'BEFORE',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.8,
                        color: textColor.withValues(alpha: 0.55),
                      ),
                    ),
                    Text(
                      _fmt(data.startDate),
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.40),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _photo(data.afterPhoto, 'After', photoH),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'AFTER',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.8,
                        color: AppColors.mutedSage,
                      ),
                    ),
                    Text(
                      _fmt(DateTime.now()),
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.40),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _skinAgeCard(Color textColor) {
    if (data.beforeMetrics.isEmpty && data.afterMetrics.isEmpty) {
      return const SizedBox.shrink();
    }
    final beforeAge = estimateVisualSkinAge(
      _toSkinMetrics(data.beforeMetrics),
    ).round();
    final afterAge = estimateVisualSkinAge(
      _toSkinMetrics(data.afterMetrics),
    ).round();
    final diff = beforeAge - afterAge;
    final improved = diff > 0;
    final accentColor = improved ? AppColors.mutedSage : MyApp.roseGold;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MyApp.champagne,
            MyApp.goldShimmer.withValues(alpha: 0.16),
            MyApp.roseGold.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: MyApp.goldShimmer.withValues(alpha: 0.34),
          width: 1.2,
        ),
        boxShadow: MyApp.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.face_retouching_natural_rounded,
                color: MyApp.roseGold,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Apparent Skin Age Journey',
                style: MyApp.cardTitleStyle(color: textColor),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Before age
              Column(
                children: [
                  Text(
                    '$beforeAge',
                    style: TextStyle(
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                      color: textColor.withValues(alpha: 0.38),
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'years before',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textColor.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: accentColor,
                  size: 32,
                ),
              ),
              // After age
              Column(
                children: [
                  Text(
                    '$afterAge',
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      color: accentColor,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'years after',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              improved
                  ? 'Apparent skin age improved from $beforeAge to $afterAge years'
                  : diff == 0
                  ? 'Apparent skin age remained stable at $afterAge years'
                  : 'Apparent skin age changed from $beforeAge to $afterAge years',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricWinsCard(Color textColor) {
    if (data.beforeMetrics.isEmpty || data.afterMetrics.isEmpty) {
      return const SizedBox.shrink();
    }

    // Each record: metric key, display label, icon, whether higher is better
    final defs = [
      (
        key: 'redness',
        label: 'Redness',
        icon: Icons.water_drop_outlined,
        higherBetter: false,
      ),
      (
        key: 'texture',
        label: 'Texture & Smoothness',
        icon: Icons.grain,
        higherBetter: false,
      ),
      (
        key: 'wrinkles',
        label: 'Fine Lines & Wrinkles',
        icon: Icons.face,
        higherBetter: false,
      ),
      (
        key: 'pores',
        label: 'Pore Appearance',
        icon: Icons.lens_blur,
        higherBetter: false,
      ),
      (
        key: 'darkSpots',
        label: 'Dark Spot Pigmentation',
        icon: Icons.brightness_3,
        higherBetter: false,
      ),
      (
        key: 'elasticity',
        label: 'Elasticity & Firmness',
        icon: Icons.compress,
        higherBetter: true,
      ),
    ];

    Widget row(String key, String label, IconData icon, bool higherBetter) {
      final altKey = key == 'wrinkles'
          ? 'wrinkle'
          : (key == 'pores' ? 'pore' : null);
      final before =
          data.beforeMetrics[key] ??
          (altKey != null ? data.beforeMetrics[altKey] : null) ??
          5.0;
      final after =
          data.afterMetrics[key] ??
          (altKey != null ? data.afterMetrics[altKey] : null) ??
          5.0;
      final pct = _pct(before, after, higherIsBetter: higherBetter);
      final improved = pct > 0.5;
      final stable = pct.abs() <= 0.5;
      final accentColor = improved
          ? Colors.green.shade600
          : (stable ? Colors.grey : MyApp.roseGold);
      final outcomeText = _metricOutcomeText(key, pct, improved, stable);
      final pctDisplay = stable ? 'Stable' : '${pct.abs().toStringAsFixed(0)}%';

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 20, color: accentColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    outcomeText,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (pct.abs() / 60.0).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: Colors.grey.shade200,
                      color: improved
                          ? Colors.green.shade400
                          : (stable ? Colors.grey.shade300 : MyApp.roseGold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                pctDisplay,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: MyApp.goldShimmer, size: 22),
              const SizedBox(width: 10),
              Text(
                'Your Metric Wins',
                style: MyApp.cardTitleStyle(color: textColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final d in defs) row(d.key, d.label, d.icon, d.higherBetter),
        ],
      ),
    );
  }

  Widget _recoveryInsightsCard(Color textColor) {
    return Container(
      decoration: BoxDecoration(
        color: MyApp.blush.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_hospital_outlined,
                color: MyApp.roseGold,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Recovery Insights',
                style: MyApp.cardTitleStyle(color: textColor),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _recoveryInsights(),
            style: TextStyle(
              fontSize: 14.5,
              color: textColor.withValues(alpha: 0.82),
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }

  Widget _productRecommendationsCard(Color textColor) {
    if (data.afterMetrics.isEmpty) {
      return const SizedBox.shrink();
    }
    final afterMetrics = _toSkinMetrics(data.afterMetrics);
    final resolvedProcedureType = (() {
      final normalized = data.procedureType.trim();
      if (normalized.isEmpty || normalized.toLowerCase() == 'unknown') {
        return 'General Skincare';
      }
      return normalized;
    })();
    AppLogger.verbose(
      '[ProcedureCompletionReportScreen] resolvedProcedureType=$resolvedProcedureType',
    );
    final recommendations =
        AIProductRecommendationEngine.generateRecommendations(
          afterMetrics,
          maxRecommendations: 2,
          procedureType: resolvedProcedureType,
          userSkinConcerns: [
            if (afterMetrics.redness > 6.0) 'redness',
            if (afterMetrics.texture > 6.0) 'texture',
            if (afterMetrics.wrinkle > 6.0) 'aging',
            if (afterMetrics.pore > 6.0) 'pores',
            if (afterMetrics.darkSpots > 6.0) 'pigmentation',
            if (afterMetrics.elasticity < 4.8) 'firmness',
            if (afterMetrics.redness > 6.0) 'sensitive',
          ],
          recentProcedureTypes:
              resolvedProcedureType.toLowerCase() != 'general skincare'
              ? [resolvedProcedureType]
              : null,
        );

    if (recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClinicalProductRecommendationsSection(
      recommendations: recommendations,
      sectionSubtitle: 'To continue supporting your recovery and results',
    );
  }

  Widget _closingNoteCard(Color textColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MyApp.goldShimmer.withValues(alpha: 0.12),
            MyApp.roseGold.withValues(alpha: 0.08),
            MyApp.champagne,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: MyApp.goldShimmer.withValues(alpha: 0.30),
          width: 1.2,
        ),
        boxShadow: MyApp.cardShadow,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.medical_services_outlined,
                color: MyApp.goldShimmer,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A Note From Your Clinician',
                  style: MyApp.cardTitleStyle(color: textColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _closingNote(),
            style: TextStyle(
              fontSize: 15,
              color: textColor.withValues(alpha: 0.84),
              height: 1.72,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '— Your Aesthetic Care Team',
              style: TextStyle(
                fontSize: 13,
                color: MyApp.goldShimmer,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final textColor = MyApp.textBrown;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: 'Completion Report',
          eyebrow: 'Procedure recovery',
          color: textColor,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 52),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heroHeader(),
            const SizedBox(height: 24),
            const ClinicalSectionHeader(
              icon: Icons.summarize_outlined,
              title: 'Overall Summary',
              eyebrow: 'Patient overview',
            ),
            const SizedBox(height: 12),
            _overallSummaryCard(textColor),
            const SizedBox(height: 24),
            const ClinicalSectionHeader(
              icon: Icons.compare_outlined,
              title: 'Before & After',
              eyebrow: 'Visual evidence',
            ),
            const SizedBox(height: 12),
            _beforeAfterCard(textColor),
            const SizedBox(height: 24),
            const ClinicalSectionHeader(
              icon: Icons.cake_outlined,
              title: 'Skin Age',
              eyebrow: 'Biological indicator',
            ),
            const SizedBox(height: 12),
            _skinAgeCard(textColor),
            const SizedBox(height: 24),
            const ClinicalSectionHeader(
              icon: Icons.insights_outlined,
              title: 'Metric Wins',
              eyebrow: 'Key improvements',
            ),
            const SizedBox(height: 12),
            _metricWinsCard(textColor),
            const SizedBox(height: 24),
            const ClinicalSectionHeader(
              icon: Icons.healing_outlined,
              title: 'Recovery Insights',
              eyebrow: 'Professional interpretation',
            ),
            const SizedBox(height: 12),
            _recoveryInsightsCard(textColor),
            const SizedBox(height: 24),
            const ClinicalSectionHeader(
              icon: Icons.spa_outlined,
              title: 'Recommended Products',
              eyebrow: 'Aftercare protocol',
            ),
            const SizedBox(height: 12),
            _productRecommendationsCard(textColor),
            const SizedBox(height: 24),
            const ClinicalSectionHeader(
              icon: Icons.medical_services_outlined,
              title: "Clinician's Note",
              eyebrow: 'Care team message',
            ),
            const SizedBox(height: 12),
            _closingNoteCard(textColor),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: MyApp.primaryGoldButton,
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
