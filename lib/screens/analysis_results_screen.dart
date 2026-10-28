import 'package:flutter/material.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import '../app_theme.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart'; // adjust path if needed
import 'package:aesthetic_skin_tracker/models/product_tracker.dart'; // for TrackedProduct
import '../utils/ai_intelligence_engine.dart';
import '../utils/ai_product_recommendation_engine.dart';
import '../utils/app_logger.dart';
import '../utils/procedure_intelligence.dart';
import '../widgets/product_recommendation_card.dart';
import '../widgets/clinical_section_header.dart';
import '../widgets/smart_narrative_container.dart';

class AnalysisResultsScreen extends StatelessWidget {
  final String? imagePath;
  final SkinMetrics? metrics;
  final bool? isPremium;
  final String? selectedProcedureLabel;
  const AnalysisResultsScreen({
    super.key,
    this.imagePath,
    this.metrics,
    this.isPremium,
    this.selectedProcedureLabel,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = MyApp.textBrown;
    final accentColor = MyApp.goldShimmer;

    // If metrics is provided, show AI-interpreted view (for previous results navigation)
    if (metrics != null) {
      final aiReport = AiIntelligenceEngine.interpretScanMetrics(
        metrics!,
        procedureType: selectedProcedureLabel,
      );
      return Scaffold(
        backgroundColor: MyApp.champagne,
        appBar: AppBar(
          title: Text(
            selectedProcedureLabel?.isNotEmpty == true
                ? 'Procedure Analysis � $selectedProcedureLabel'
                : 'Procedure Analysis',
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: textColor,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Premium report header
            _buildReportHeader(
              selectedProcedureLabel?.isNotEmpty == true
                  ? '$selectedProcedureLabel Scan Analysis'
                  : 'Previous Scan Analysis',
              null,
              textColor,
            ),
            const SizedBox(height: 16),
            _buildSectionLabel(
              'Assessment Summary',
              textColor,
              icon: Icons.assessment_outlined,
              eyebrow: 'Clinical interpretation',
            ),
            _buildAiNarrativeCard(
              aiReport,
              textColor,
              procedureType: selectedProcedureLabel,
            ),
            const SizedBox(height: 16),
            _buildSectionLabel(
              'Metric-by-Metric Analysis',
              textColor,
              icon: Icons.analytics_outlined,
              eyebrow: 'Quantified changes',
            ),
            _buildMetricsProgressHeader(textColor),
            // AI Metric Cards
            ...aiReport.metricInsights.map(
              (insight) => _buildAiMetricCard(insight),
            ),
            const SizedBox(height: 16),
            _buildSectionLabel(
              'Clinical Recommendation',
              textColor,
              icon: Icons.medical_services_outlined,
              eyebrow: 'Next steps',
            ),
            _buildRecommendationCard(aiReport.primaryRecommendation, textColor),
            const SizedBox(height: 16),
            _buildSectionLabel(
              'Clinician-Recommended Products',
              textColor,
              icon: Icons.shopping_bag_outlined,
              eyebrow: 'Curated protocol',
            ),
            _buildProductRecommendations(
              metrics!,
              textColor,
              procedureType: selectedProcedureLabel,
            ),
            const SizedBox(height: 16),
            _buildReportFooter(textColor),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/home'),
              icon: const Icon(Icons.home, color: Colors.white),
              label: const Text(
                'Home',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.roseGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back_ios),
              label: const Text('Return to Procedure Profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.roseGold,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            // Legacy invisible fields kept for compatibility
            Opacity(
              opacity: 0.0,
              child: Column(
                children: [
                  Text('Redness: ${metrics!.redness.toStringAsFixed(1)}'),
                  Text('Texture: ${metrics!.texture.toStringAsFixed(1)}'),
                  Text('Wrinkle: ${metrics!.wrinkle.toStringAsFixed(1)}'),
                  Text('Pore: ${metrics!.pore.toStringAsFixed(1)}'),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/home');
                    },
                    icon: const Icon(Icons.home, color: Colors.white),
                    label: const Text(
                      'Home',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 8,
                      shadowColor: Colors.amber[600]!.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_back_ios),
                    label: const Text('Return to Procedure Profile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.roseGold,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Default: show scan history with AI interpretation
    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        title: const ClinicalAppBarTitle(
          title: 'Procedure Analysis',
          eyebrow: 'AI insights',
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: FutureBuilder<(List<ScanHistoryEntry>, List<Map<String, dynamic>>, String?, String?)>(
        future:
            Future.wait([
              AppPrefs.getScanHistory(),
              AppPrefs.getProcedureEntries(),
              AppPrefs.getSelectedProcedureIdOrNull(),
              AppPrefs.getProcedureType(),
            ]).then(
              (r) => (
                r[0] as List<ScanHistoryEntry>,
                r[1] as List<Map<String, dynamic>>,
                r[2] as String?,
                r[3] as String?,
              ),
            ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading results: ${snapshot.error}'),
            );
          }

          final (
            rawEntries,
            proceduresJson,
            selectedProcId,
            storedProcedureType,
          ) = snapshot.data!;
          // Filter to the active/selected procedure's scans so analysis is
          // always scoped to the currently tracked procedure.
          final filteredRaw = (selectedProcId?.isNotEmpty == true)
              ? rawEntries
                    .where((e) => e.procedureId == selectedProcId)
                    .toList()
              : rawEntries;
          final scans = filteredRaw.map((e) => e.toSkinMetrics()).toList();
          if (scans.isEmpty) {
            return Center(
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(26),
                decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.08),
                child: Text(
                  'Welcome! Take your first photo to start tracking your skin progress',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (scans.length == 1) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "Ready for your next scan?",
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Capture your progress",
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // --- Logged Skincare Products Section ---
                  FutureBuilder<List<TrackedProduct>>(
                    future: AppPrefs.getTrackedProducts(),
                    builder: (context, productSnapshot) {
                      if (productSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final products = productSnapshot.data ?? [];
                      if (products.isEmpty) {
                        return const SizedBox.shrink(); // or: Text('No active product', style: TextStyle(fontSize: 12, color: Colors.grey))
                      }
                      final activeProduct = products.last;
                      String insight;
                      final name = activeProduct.name.toLowerCase();
                      final ingredients = activeProduct.keyIngredients
                          .toLowerCase();
                      if (name.contains('niacinamide') ||
                          ingredients.contains('niacinamide')) {
                        insight =
                            "Niacinamide is helping with oil control and pores � keep going!";
                      } else if (name.contains('retinol') ||
                          ingredients.contains('retinol')) {
                        insight =
                            "Retinol is boosting cell turnover and smoothing wrinkles � visible results in 8-12 weeks.";
                      } else if (name.contains('hyaluronic acid') ||
                          ingredients.contains('hyaluronic acid')) {
                        insight =
                            "Hyaluronic acid is improving hydration � skin looks plumper.";
                      } else {
                        insight =
                            "This product is supporting your skin journey � continue scanning!";
                      }
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Product: ${activeProduct.name} (${activeProduct.brand.isNotEmpty ? activeProduct.brand : 'No brand'})',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber[900],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              insight,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.amber[800],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  TextButton(
                    onPressed: () {},
                    child: Text(
                      'Or view your previous results',
                      style: TextStyle(color: Colors.amber[700], fontSize: 14),
                    ),
                  ),
                ],
              ),
            );
          }

          // 2+ scans: full results with product adaptation
          final sortedRaw = List<ScanHistoryEntry>.from(filteredRaw)
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          final sorted = scans
            ..sort((a, b) {
              final aDate = a.date ?? DateTime(1970);
              final bDate = b.date ?? DateTime(1970);
              return aDate.compareTo(bDate);
            });
          final baseline = sorted.first;
          final latest = sorted.last;
          final latestEntry = sortedRaw.last;

          final scanNumber = sorted.length;
          final latestDate = latest.date;
          final dateLabel = latestDate != null
              ? '${latestDate.day} ${_monthName(latestDate.month)} ${latestDate.year}'
              : null;

          // Resolve procedureType: prefer the active selected procedure and saved app setting,
          // then fall back to scan metadata only if nothing else is available.
          String? resolvedProcedureType;
          // 1. Look up the active selected procedure directly from proceduresJson
          if (selectedProcId?.isNotEmpty == true) {
            try {
              final match = proceduresJson.firstWhere(
                (p) => (p['id']?.toString() ?? '') == selectedProcId,
              );
              final t = (match['type']?.toString() ?? '').trim();
              if (t.isNotEmpty) resolvedProcedureType = t;
            } catch (_) {}
          }
          // 2. Fall back to the saved app-level procedure type
          resolvedProcedureType ??=
              storedProcedureType?.trim().isNotEmpty == true
              ? storedProcedureType!.trim()
              : selectedProcedureLabel?.trim().isNotEmpty == true
              ? selectedProcedureLabel!.trim()
              : null;
          // 3. Fall back to procedureId lookup on the scan entry
          if (resolvedProcedureType == null &&
              (latestEntry.procedureId?.isNotEmpty == true)) {
            final procId = latestEntry.procedureId!;
            try {
              final match = proceduresJson.firstWhere(
                (p) => (p['id']?.toString() ?? '') == procId,
              );
              final t = (match['type']?.toString() ?? '').trim();
              if (t.isNotEmpty) resolvedProcedureType = t;
            } catch (_) {}
          }

          // 4. Fall back to explicit procedure label stored on the scan entry.
          if (resolvedProcedureType == null) {
            final scanType = (latestEntry.procedure ?? '').trim();
            if (scanType.isNotEmpty && scanType.toLowerCase() != 'unknown') {
              resolvedProcedureType = scanType;
            }
          }

          // 5. Final safe fallback to avoid unresolved procedure context.
          resolvedProcedureType ??= 'General Skincare';

          AppLogger.verbose(
            '[AnalysisResultsScreen] resolvedProcedureType=$resolvedProcedureType',
          );

          // Build a descriptive scan type label using the resolved procedure type
            final String scanTypeLabel = resolvedProcedureType.isNotEmpty
              ? '$resolvedProcedureType Scan Analysis'
              : _scanTypeLabel(latestEntry);

          // AI interpretation (procedure-aware). Pass raw `ScanHistoryEntry.metrics`
          // maps so body-composition metrics (weight, body fat %, waist,
          // muscle mass, appetite control, body-composition score) can be
          // sourced beyond the 6 facial-skin fields that [SkinMetrics] holds.
          final ScanHistoryEntry baselineEntry = sortedRaw.first;
          final trendPayload = latestEntry.rawPayload;
          Map<String, dynamic> asMap(dynamic value) {
            if (value is Map<String, dynamic>) return value;
            if (value is Map) return Map<String, dynamic>.from(value);
            return const <String, dynamic>{};
          }
          final nestedLuxe = asMap(asMap(trendPayload)['luxePayload']);
          final trendStatusSource = asMap(nestedLuxe['trend_status']).isNotEmpty
              ? asMap(nestedLuxe['trend_status'])
              : asMap(asMap(trendPayload)['trend_status']);
          final trendLockReasonSource =
              asMap(nestedLuxe['trend_lock_reasons']).isNotEmpty
              ? asMap(nestedLuxe['trend_lock_reasons'])
              : asMap(asMap(trendPayload)['trend_lock_reasons']);
          final aiReport = AiIntelligenceEngine.interpretScanMetrics(
            latest,
            baseline: baseline,
            procedureType: resolvedProcedureType,
            customDescription: latestEntry.customDescription,
            focusArea: latestEntry.focusArea,
            rawMetrics: latestEntry.metrics,
            baselineRawMetrics: baselineEntry.metrics,
            trendStatus: trendStatusSource.map(
              (key, value) => MapEntry(key, value.toString()),
            ),
            trendLockReason: trendLockReasonSource.map(
              (key, value) => MapEntry(key, value.toString()),
            ),
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Premium report header
              _buildReportHeader(
                scanTypeLabel,
                dateLabel != null
                    ? 'Scan #$scanNumber � $dateLabel � vs. baseline'
                    : 'Scan #$scanNumber',
                textColor,
              ),
              const SizedBox(height: 16),

              // Section: Assessment Summary
              _buildSectionLabel(
                'Assessment Summary',
                textColor,
                icon: Icons.assessment_outlined,
                eyebrow: 'Clinical interpretation',
              ),
              _buildAiNarrativeCard(
                aiReport,
                textColor,
                procedureType: resolvedProcedureType,
              ),
              const SizedBox(height: 16),

              // Return to Procedure Profile button
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Return to Procedure Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyApp.roseGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(height: 8),

              // Section: Metric Analysis
              _buildSectionLabel(
                'Metric-by-Metric Analysis',
                textColor,
                icon: Icons.analytics_outlined,
                eyebrow: 'Quantified changes',
              ),
              _buildMetricsProgressHeader(textColor),
              ...aiReport.metricInsights.map(
                (insight) => _buildAiMetricCard(insight),
              ),
              const SizedBox(height: 16),

              // Section: Clinical Recommendation
              _buildSectionLabel(
                'Clinical Recommendation',
                textColor,
                icon: Icons.medical_services_outlined,
                eyebrow: 'Next steps',
              ),
              _buildRecommendationCard(
                aiReport.primaryRecommendation,
                textColor,
              ),
              const SizedBox(height: 16),

              // Section: Procedure-Aware Product Recommendations
              _buildProductRecommendations(
                latest,
                textColor,
                procedureType: resolvedProcedureType,
              ),
              const SizedBox(height: 12),

              // Nested FutureBuilder for product adaptation
              FutureBuilder<List<TrackedProduct>>(
                future: AppPrefs.getTrackedProducts(),
                builder: (context, productSnapshot) {
                  if (productSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final products = productSnapshot.data ?? [];
                  final activeProduct = products.isNotEmpty
                      ? products.last
                      : null;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (activeProduct != null) ...[
                        _buildProductInsightCard(
                          activeProduct,
                          report: aiReport,
                        ),
                        const SizedBox(height: 20),
                      ],
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(context, '/scan');
                        },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Take Another Progress Photo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(context, '/home');
                        },
                        icon: const Icon(Icons.home),
                        label: const Text('Home'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildReportFooter(textColor),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// Helper for product-specific insight � clinically phrased, cross-referenced with AI report
String _getProductInsight(TrackedProduct product, {ScanAiReport? report}) {
  final lowerName = product.name.toLowerCase();
  final lowerIngredients = product.keyIngredients.toLowerCase();

  // Identify top concern from AI report for personalised context
  final concernList =
      report?.metricInsights
          .where((i) => i.isConcerning || i.isPositiveTrend == false)
          .toList() ??
      [];
  concernList.sort(
    (a, b) => _unifiedMetricScore100(a).compareTo(_unifiedMetricScore100(b)),
  );
  final topMetric = concernList.isNotEmpty ? concernList.first : null;

  if (lowerName.contains('niacinamide') ||
      lowerIngredients.contains('niacinamide')) {
    final metricNote = topMetric?.label == 'Redness'
        ? ' With redness at ${topMetric!.value.toStringAsFixed(1)}, niacinamide is a well-placed choice � it modulates vascular reactivity and supports transepidermal water loss reduction.'
        : topMetric?.label == 'Pores'
        ? ' With pore visibility at ${topMetric!.value.toStringAsFixed(1)}, niacinamide is a clinically supported option � consistent use over 8�12 weeks typically yields measurable pore reduction.'
        : '';
    return 'Niacinamide supports sebum regulation, pore minimization, and skin tone evenness.$metricNote Expect measurable improvement within 4�8 weeks of consistent twice-daily use.';
  } else if (lowerName.contains('retinol') ||
      lowerIngredients.contains('retinol') ||
      lowerIngredients.contains('tretinoin')) {
    final metricNote = topMetric?.label == 'Texture'
        ? ' Your texture score of ${topMetric!.value.toStringAsFixed(1)} places you in the range where retinol typically yields the most visible surface refinement.'
        : topMetric?.label == 'Wrinkles'
        ? ' At a wrinkle score of ${topMetric!.value.toStringAsFixed(1)}, retinol is the most evidence-based topical intervention � expect a meaningful response at 8�12 weeks.'
        : '';
    return 'Retinol accelerates cellular turnover, stimulates collagen I and III synthesis, and refines surface texture.$metricNote Initial adjustment (mild dryness or flaking) is expected � persist for 12 weeks before evaluating the full response.';
  } else if (lowerIngredients.contains('hyaluronic acid')) {
    return 'Hyaluronic acid draws moisture into the epidermis, improving hydration depth and plumpness. It also supports barrier integrity � an important foundation for tolerating active ingredient protocols. Visible improvement in skin suppleness is typically apparent within 2�4 weeks.';
  } else if (lowerIngredients.contains('vitamin c') ||
      lowerIngredients.contains('ascorbic')) {
    final metricNote = topMetric?.label == 'Dark Spots'
        ? ' With dark spots at ${topMetric!.value.toStringAsFixed(1)}, vitamin C is a well-aligned morning active � it inhibits tyrosinase-driven melanin synthesis and neutralises UV-induced free radicals.'
        : '';
    return 'Vitamin C (L-ascorbic acid) provides multi-benefit antioxidant protection, inhibits melanin overproduction, and supports collagen synthesis.$metricNote Apply before SPF in the morning for maximum photoprotective benefit.';
  } else if (lowerIngredients.contains('azelaic')) {
    return 'Azelaic acid offers dual-action benefit: it modulates vascular reactivity (reducing redness) and inhibits melanin overproduction (fading pigmentation). Notably well-tolerated on sensitive and post-procedure skin. Clinical benefit typically appears at 4�8 weeks.';
  } else {
    final metricNote = topMetric != null
        ? ' Given your current ${topMetric.label.toLowerCase()} reading of ${topMetric.value.toStringAsFixed(1)}, regular scanning will help quantify this product\'s contribution to your progress.'
        : '';
    return 'This product is an active part of your tracked routine.$metricNote Consistent use and regular scanning will reveal its impact on your key metrics over the coming weeks.';
  }
}

// --- AI Widget Helpers --------------------------------------------------------

// -- Premium report header -----------------------------------------------------
Widget _buildReportHeader(String title, String? subtitle, Color textColor) {
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8D5D5), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE8A8B5), Color(0xFFC97B8B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.document_scanner_outlined,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: textColor,
                  letterSpacing: 0.1,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: textColor.withValues(alpha: 0.50),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF6A1B9A).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF6A1B9A).withValues(alpha: 0.22),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 12,
                color: Color(0xFF6A1B9A),
              ),
              SizedBox(width: 3),
              Text(
                'AI',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF6A1B9A),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// -- Metrics progress header ---------------------------------------------------
Widget _buildMetricsProgressHeader(Color textColor) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFDF8F5),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFEAE0D6)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 16, color: Color(0xFF7A6458)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Metrics Progress � For most skin metrics (Erythema, Skin Texture Quality, Rhytids, Pore Visibility, Hyperpigmentation, Inflammatory Response), lower numbers are better. Teal ? means improvement from baseline; rose ? means regression. Higher-is-better metrics: Skin Laxity, Skin Tone Uniformity, Skin Hydration Level, and Global Skin Quality Score.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: textColor.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    ),
  );
}

// -- Section label --------------------------------------------------------------
Widget _buildSectionLabel(
  String label,
  Color textColor, {
  IconData icon = Icons.bookmark_outline,
  String? eyebrow,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
    child: ClinicalSectionHeader(
      icon: icon,
      title: label,
      eyebrow: eyebrow,
      textColor: textColor,
    ),
  );
}

// -- Clinical disclaimer footer -------------------------------------------------
Widget _buildReportFooter(Color textColor) {
  return Container(
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(top: 4),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, size: 13, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Text(
              'Clinical Disclaimer',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'This report is generated by AestheticSkinTracker\'s AI analysis (scan photos are analyzed on our server) for informational and tracking purposes only. It does not constitute medical advice, diagnosis, or treatment. AI-generated assessments are based on image pattern analysis and deterministic clinical models. Individual results vary. Always consult a qualified dermatologist or healthcare provider before modifying your skincare regimen or if you have any concerns about your skin health.',
          style: TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.50),
        ),
      ],
    ),
  );
}

Widget _buildAiNarrativeCard(
  ScanAiReport report,
  Color textColor, {
  String? procedureType,
}) {
  final hasPositive = report.positiveFindings.isNotEmpty;
  final headerColor = report.topPriority != null
      ? const Color(0xFF6A1B9A)
      : const Color(0xFF2E7D32);
  final isProc = procedureType?.isNotEmpty == true;
  final assessmentTitle = isProc
      ? 'AI ${procedureType!} Recovery Assessment'
      : 'AI Skin Assessment';

  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          headerColor.withValues(alpha: 0.08),
          headerColor.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0.95),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: headerColor.withValues(alpha: 0.20),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: headerColor.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: headerColor.withValues(alpha: 0.10),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
          ),
          child: Row(
            children: [
              Icon(Icons.psychology_outlined, color: headerColor, size: 20),
              const SizedBox(width: 8),
              Text(
                assessmentTitle,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: headerColor,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SmartNarrativeContainer(narrativeText: report.overallNarrative),
              if (hasPositive) ...[
                const SizedBox(height: 12),
                const Text(
                  'Performing well:',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: Color(0xFF2E7D32),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: report.positiveFindings
                      .map((f) => _aiChip(f, const Color(0xFF2E7D32)))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildAiMetricCard(MetricInsight insight) {
  final score100 = _unifiedMetricScore100(insight);
  final statusLabel = _statusFromInsight(insight);
  final chipColor = _statusColor(statusLabel);

  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: insight.color.withValues(alpha: 0.18),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: insight.color.withValues(alpha: 0.06),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Icon + label + value + level chip
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: insight.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(insight.icon, color: insight.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      insight.clinicalLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: insight.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    score100.toStringAsFixed(0),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: chipColor,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: chipColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: chipColor.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: chipColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '/100',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Context note
          Text(
            insight.contextNote,
            style: TextStyle(
              fontSize: 13,
              color: Colors.black87.withValues(alpha: 0.78),
              height: 1.5,
            ),
          ),
          // Trend note
          if (insight.trendNote != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  insight.trendNote!.contains('Improved') ||
                          insight.trendNote!.contains('reduced') ||
                          insight.trendNote!.contains('faded') ||
                          insight.trendNote!.contains('Smoother') ||
                          insight.trendNote!.contains('progressing')
                      ? Icons.trending_down
                      : Icons.trending_up,
                  size: 15,
                  color:
                      insight.trendNote!.contains('Improved') ||
                          insight.trendNote!.contains('reduced') ||
                          insight.trendNote!.contains('faded') ||
                          insight.trendNote!.contains('Smoother') ||
                          insight.trendNote!.contains('progressing')
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFE65100),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    insight.trendNote!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color:
                          insight.trendNote!.contains('Improved') ||
                              insight.trendNote!.contains('reduced') ||
                              insight.trendNote!.contains('faded') ||
                              insight.trendNote!.contains('Smoother') ||
                              insight.trendNote!.contains('progressing')
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFE65100),
                    ),
                  ),
                ),
              ],
            ),
          ],
          // Suggestion
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: insight.color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 14, color: insight.color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    insight.suggestion,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.black87.withValues(alpha: 0.80),
                      height: 1.48,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildRecommendationCard(String recommendation, Color textColor) {
  const accentColor = Color(0xFF6A1B9A);
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          accentColor.withValues(alpha: 0.08),
          accentColor.withValues(alpha: 0.03),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accentColor.withValues(alpha: 0.20)),
      boxShadow: [
        BoxShadow(
          color: accentColor.withValues(alpha: 0.06),
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
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.recommend_outlined,
                color: accentColor,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Priority Clinical Recommendation',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          recommendation,
          style: TextStyle(
            fontSize: 13.5,
            color: textColor.withValues(alpha: 0.88),
            height: 1.60,
          ),
        ),
      ],
    ),
  );
}

Widget _buildProductRecommendations(
  SkinMetrics metrics,
  Color textColor, {
  String? procedureType,
}) {
  final resolvedProcedureType = (() {
    final normalized = (procedureType ?? '').trim();
    if (normalized.isEmpty || normalized.toLowerCase() == 'unknown') {
      return 'General Skincare';
    }
    return normalized;
  })();
  AppLogger.verbose(
    '[AnalysisResultsScreen._buildProductRecommendations] resolvedProcedureType=$resolvedProcedureType',
  );
  final isBodyContouring =
      resolvedProcedureType.isNotEmpty &&
      ProcedureIntelligence.categoryFor(resolvedProcedureType) ==
          ProcedureCategory.bodyContouring;
  final recommendations = AIProductRecommendationEngine.generateRecommendations(
    metrics,
    procedureType: resolvedProcedureType,
    maxRecommendations: isBodyContouring ? 6 : 3,
    userSkinConcerns: [
      if (metrics.redness > 6.0) 'redness',
      if (metrics.texture > 6.0) 'texture',
      if (metrics.wrinkle > 6.0) 'aging',
      if (metrics.pore > 6.0) 'pores',
      if (metrics.darkSpots > 6.0) 'pigmentation',
      if (metrics.elasticity < 4.8) 'firmness',
      if (metrics.elasticity < 4.8 || metrics.texture > 6.0) 'dryness',
      if (metrics.redness > 6.0) 'sensitive',
    ],
    recentProcedureTypes:
      resolvedProcedureType.isNotEmpty ? [resolvedProcedureType] : null,
  );

  if (recommendations.isEmpty) {
    return const SizedBox.shrink();
  }

  final isProc =
      resolvedProcedureType.isNotEmpty &&
      resolvedProcedureType.toLowerCase() != 'general skincare';
  return ClinicalProductRecommendationsSection(
    recommendations: recommendations,
    sectionTitle: isProc
        ? '$resolvedProcedureType Product Recommendations'
        : 'Clinician-Recommended Products',
    sectionSubtitle: isProc
        ? 'Matched to your $resolvedProcedureType recovery'
        : 'Based on your scan metrics',
  );
}

Widget _buildProductInsightCard(
  TrackedProduct product, {
  ScanAiReport? report,
}) {
  const accentColor = Color(0xFFBF8A30);
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFFF8E7), Color(0xFFFCF3E8)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: accentColor.withValues(alpha: 0.28)),
      boxShadow: [
        BoxShadow(
          color: accentColor.withValues(alpha: 0.08),
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
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.spa_outlined,
                color: accentColor,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Product',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: accentColor.withValues(alpha: 0.65),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '${product.brand.isNotEmpty ? '${product.brand} � ' : ''}${product.name}',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _getProductInsight(product, report: report),
          style: const TextStyle(
            fontSize: 13.5,
            color: Color(0xFF5C3D00),
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

Widget _aiChip(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

double _unifiedMetricScore100(MetricInsight insight) {
  final raw10 = insight.value.clamp(0.0, 10.0).toDouble();
  final raw100 = raw10 * 10.0;
  final normalizedLabel = insight.label.toLowerCase().trim();
  final higherIsBetter = {
    'elasticity',
    'firmness',
    'skin laxity',
    'skin tone uniformity',
    'skin hydration level',
    'global skin quality score',
  }.contains(normalizedLabel);
  final score = higherIsBetter ? raw100 : (100.0 - raw100);
  return score.clamp(0.0, 100.0).toDouble();
}

/// The ONLY authorized source for this screen's Improved/Worsened/Stable
/// chip: derived from [MetricInsight.trendNote]/[isPositiveTrend], which
/// are themselves already gated by the backend's trend_status (see
/// ai_intelligence_engine.dart's _buildInsightFromDef). Never derived from
/// the metric's absolute current value alone — a metric can be severe right
/// now and still show no trend claim if the backend supplied no verdict.
String _statusFromInsight(MetricInsight insight) {
  if (insight.trendNote == null) return 'Tracking';
  if (insight.isPositiveTrend == true) return 'Improved';
  if (insight.isPositiveTrend == false) return 'Worsened';
  return 'Stable';
}

Color _statusColor(String status) {
  switch (status) {
    case 'Improved':
      return const Color(0xFF2E7D32);
    case 'Worsened':
      return const Color(0xFFE65100);
    default:
      return const Color(0xFF8C6D3A);
  }
}

String _monthName(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[(month - 1).clamp(0, 11)];
}

String _scanTypeLabel(ScanHistoryEntry entry) {
  // Prioritise procedure type name, then product name, else generic fallbacks
  final procedure = entry.procedure?.trim();
  if (procedure != null && procedure.isNotEmpty) {
    return '$procedure Scan Results';
  }
  final product = entry.productName?.trim();
  if (product != null && product.isNotEmpty) {
    return '$product Scan Results';
  }
  if (entry.procedureId != null && entry.procedureId!.isNotEmpty) {
    return 'Procedure Scan Results';
  }
  return 'Cosmetic Scan Results';
}

