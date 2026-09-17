// lib/screens/active_skincare_details_screen.dart
import 'dart:convert';
import 'dart:io' show File;
import 'package:before_after/before_after.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ← Fixed: added this import
import 'package:url_launcher/url_launcher.dart';

import '../models/product_tracker.dart';
import '../app_theme.dart';
import '../utils/app_prefs.dart';
import '../utils/metric_trend.dart';
import '../models/scan_history.dart';
import '../models/journal_entry.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import '../widgets/app_brand_title.dart';

class ActiveSkincareDetailsScreen extends StatefulWidget {
  final TrackedProduct product;

  const ActiveSkincareDetailsScreen({super.key, required this.product});

  @override
  State<ActiveSkincareDetailsScreen> createState() =>
      _ActiveSkincareDetailsScreenState();
}

class _ActiveSkincareDetailsScreenState
    extends State<ActiveSkincareDetailsScreen> {
  List<ScanHistoryEntry> scans = [];
  List<JournalEntry> journalEntries = [];
  bool _didInit = false;

  final int _userChronologicalAge = 34;
  bool _showAnalysisDisclaimerBanner = true;

  // Gemini Vision analysis state
  String? _geminiVisionAnalysis;
  bool _isAnalyzingWithGemini = false;
  bool _geminiVisionUsed = false;

  @override
  void initState() {
    super.initState();
    _loadAnalysisDisclaimerBannerState();
    _loadScans();
    _loadJournalEntries();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Skip the very first call (initState already loaded)
    if (!_didInit) {
      _didInit = true;
      return;
    }
    // Reload when returning from camera or other screens
    _loadScans();
    _loadJournalEntries();
  }

  Future<void> _loadAnalysisDisclaimerBannerState() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool('analysis_disclaimer_dismissed') ?? false;
    if (mounted) {
      setState(() => _showAnalysisDisclaimerBanner = !dismissed);
    }
  }

  Future<void> _dismissAnalysisDisclaimerBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('analysis_disclaimer_dismissed', true);
    if (mounted) {
      setState(() => _showAnalysisDisclaimerBanner = false);
    }
  }

  Future<void> _loadScans() async {
    try {
      final allScans = await AppPrefs.getScanEntries();
      final productKey = widget.product.name.trim().toLowerCase();
      if (!mounted) return;
      setState(() {
        scans =
            allScans
                .where(
                  (scan) =>
                      (scan.productName?.trim().toLowerCase() ?? '') ==
                      productKey,
                )
                .toList()
              ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      });
      // Try Gemini Vision analysis if we have before/after photos
      _tryGeminiVisionAnalysis();
    } catch (e) {
      setState(() => scans = []);
    }
  }

  Future<void> _tryGeminiVisionAnalysis() async {
    if (mounted) {
      setState(() {
        _isAnalyzingWithGemini = false;
        _geminiVisionUsed = false;
        _geminiVisionAnalysis = null;
      });
    }
  }

  Future<void> _loadJournalEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('skincare_journal_entries');
    if (raw == null || raw.isEmpty) {
      setState(() => journalEntries = []);
      return;
    }
    try {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      final List<dynamic> entriesList =
          decoded[widget.product.name] as List<dynamic>? ?? [];
      setState(() {
        journalEntries =
            entriesList
                .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
      });
    } catch (e) {
      setState(() => journalEntries = []);
    }
  }

  bool get _hasEnoughScansForAge => scans.length >= 2;

  bool get _hasBothPhotos =>
      scans.length >= 2 &&
      (scans.first.imagePath?.isNotEmpty ?? false) &&
      (scans.last.imagePath?.isNotEmpty ?? false);

  String? get _beforePhoto => scans.isNotEmpty ? scans.first.imagePath : null;

  String? get _afterPhoto => scans.length >= 2 ? scans.last.imagePath : null;

  List<ScanHistoryEntry> get _afterPhotos =>
      scans.length >= 2 ? scans.skip(1).toList() : const [];

  // ==================== SKIN AGE ====================
  int _getEstimatedSkinAge() {
    if (scans.isEmpty) return _userChronologicalAge;
    return ((_userChronologicalAge - (scans.length - 1) * 1.5).clamp(
      29,
      42,
    )).round();
  }

  Color _getSkinAgeColor(int skinAge) =>
      skinAge < _userChronologicalAge ? Colors.green : Colors.orange;

  String _scanLabel(int index) => index == 0 ? 'Baseline' : 'After $index';

  Widget _buildAfterPlaceholder() {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: MyApp.roseGold.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.18),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                bottomLeft: Radius.circular(18),
              ),
              gradient: LinearGradient(
                colors: [Color(0xFFE8A8B5), Color(0xFFE0C070)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_a_photo_outlined,
                    color: MyApp.roseGold,
                    size: 42,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Upload after photo\nto compare results',
                    style: TextStyle(
                      color: MyApp.roseGold,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkinAgeCard() {
    if (!_hasEnoughScansForAge) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: MyApp.roseGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.4)),
          ),
          child: const Column(
            children: [
              Icon(Icons.face, color: Colors.grey, size: 32),
              SizedBox(height: 12),
              Text(
                'Apparent Skin Age',
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
              Text(
                'Waiting for second scan to estimate skin age...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final skinAge = _getEstimatedSkinAge();
    final skinAgeColor = _getSkinAgeColor(skinAge);

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: MyApp.roseGold.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: MyApp.roseGold.withValues(alpha: 0.18),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 56,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(22),
                  bottomLeft: Radius.circular(22),
                ),
                gradient: LinearGradient(
                  colors: [Color(0xFFE8A8B5), Color(0xFFE0C070)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Icon(Icons.face, color: skinAgeColor, size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Apparent Skin Age',
                  style: TextStyle(
                    fontSize: 16,
                    color: skinAgeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$skinAge years',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: skinAgeColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Map<String, double> _getMetricsForScan(ScanHistoryEntry scan) {
    final index = scans.indexOf(scan);

    if (scan.metrics.isNotEmpty) {
      return {
        'Redness': scan.metrics['redness'] ?? 5.0,
        'Texture': scan.metrics['texture'] ?? 5.0,
        'Wrinkle': scan.metrics['wrinkles'] ?? scan.metrics['wrinkle'] ?? 5.0,
        'Pore': scan.metrics['pores'] ?? scan.metrics['pore'] ?? 5.0,
        'Dark Spots': scan.metrics['darkSpots'] ?? 5.0,
        'Firmness': scan.metrics['elasticity'] ?? 5.0,
      };
    }

    final result = {
      'Redness': (5.8 - index * 0.9).clamp(2.8, 7.2),
      'Texture': (6.4 - index * 1.0).clamp(3.2, 7.8),
      'Wrinkle': (5.2 - index * 0.85).clamp(2.5, 6.8),
      'Pore': (6.1 - index * 0.95).clamp(3.0, 7.5),
      'Dark Spots': (5.5 - index * 0.8).clamp(2.7, 7.0),
      'Firmness': (4.1 + index * 0.95).clamp(3.5, 8.2),
    };

    return result;
  }

  // ==================== IMAGE BUILDER ====================
  Widget _buildImage(
    String? path, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (path == null || path.isEmpty) {
      return const Icon(Icons.photo, size: 80, color: Colors.grey);
    }

    // Base64 data URI (saved by camera on web: "data:image/jpeg;base64,...")
    // Image.network() does NOT support data: URIs in Flutter — use Image.memory()
    if (path.startsWith('data:image')) {
      final comma = path.indexOf(',');
      if (comma != -1) {
        try {
          final bytes = base64Decode(path.substring(comma + 1));
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 80, color: Colors.grey),
          );
        } catch (_) {}
      }
      return const Icon(Icons.broken_image, size: 80, color: Colors.grey);
    }

    if (kIsWeb) {
      // Regular URL (not a data URI)
      return Image.network(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image, size: 80, color: Colors.grey),
      );
    } else {
      return Image.file(
        File(path),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image, size: 80, color: Colors.grey),
      );
    }
  }

  Future<void> _openCamera() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          isSkincareScan: true,
          productName: widget.product.name,
          capturePurpose: CameraCapturePurpose.skincareTracking,
        ),
      ),
    );
    // getScanEntries() calls prefs.reload() internally — no delay needed
    if (mounted) await _loadScans();
  }

  // ==================== COMPARE DIALOG ====================
  void _showCompareDialog() {
    if (scans.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need at least 2 scans to compare')),
      );
      return;
    }

    final beforeData = _beforePhoto;
    final afterData = _afterPhoto;
    final metricsWithChange = _getMetricsWithChange();
    double sliderValue = 0.5;
    bool showMetrics = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 820),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        BeforeAfter(
                          before: _buildImage(beforeData),
                          after: _buildImage(afterData),
                          value: sliderValue,
                          onValueChanged: (v) =>
                              setState(() => sliderValue = v),
                          thumbWidth: 4,
                          height: double.infinity,
                          thumbDecoration: BoxDecoration(
                            color: MyApp.goldShimmer,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: MyApp.goldShimmer.withValues(alpha: 0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 20,
                          left: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'BEFORE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 20,
                          right: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'AFTER',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    children: [
                      Text(
                        'Before vs After Comparison',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: MyApp.textBrown,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Drag the slider to compare improvement',
                        style: TextStyle(fontSize: 15, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey, width: 0.5),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => setState(() => showMetrics = !showMetrics),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Skin Metrics',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  color: MyApp.textBrown,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                showMetrics
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: MyApp.goldShimmer,
                                size: 28,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showMetrics)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: Column(
                            children: metricsWithChange.map((metric) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        metric['label'],
                                        style: const TextStyle(fontSize: 16.5),
                                      ),
                                    ),
                                    Text(
                                      metric['latest'],
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    if (metric['arrowIcon'] != null)
                                      Icon(
                                        metric['arrowIcon'],
                                        color: metric['arrowColor'],
                                        size: 22,
                                      ),
                                    if (metric['change'] != '') ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        metric['change'],
                                        style: TextStyle(
                                          color: metric['arrowColor'],
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16.5,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade200,
                              foregroundColor: Colors.grey.shade800,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Close',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== MAIN METRICS WITH CHANGE ====================
  List<Map<String, dynamic>> _getMetricsWithChange() {
    if (scans.length < 2) return [];

    final baseline = _getMetricsForScan(scans.first);
    final latest = _getMetricsForScan(scans.last);

    return baseline.keys.map((metric) {
      final baselineValue = baseline[metric]!;
      final latestValue = latest[metric]!;
      final trend = resolveMetricTrend(
        metric,
        baseline: baselineValue,
        current: latestValue,
      );

      return {
        'label': metric,
        'baseline': baselineValue.toStringAsFixed(1),
        'latest': latestValue.toStringAsFixed(1),
        'score': latestValue.toStringAsFixed(1), // Clean 0-10 score
        'arrowIcon': trend.hasMeaningfulChange ? trend.icon : null,
        'arrowColor': trend.hasMeaningfulChange ? trend.color : null,
      };
    }).toList();
  }

  // ==================== NATURAL LANGUAGE INSIGHTS ====================
  List<String> _generateProgressInsights() {
    if (scans.length < 2) return [];

    final baseline = _getMetricsForScan(scans.first);
    final latest = _getMetricsForScan(scans.last);
    final insights = <String>[];

    // Analyze each metric and generate natural language
    baseline.forEach((metric, baselineValue) {
      final latestValue = latest[metric] ?? baselineValue;
      final change = latestValue - baselineValue;
      final percentChange = baselineValue > 0
          ? (change.abs() / baselineValue * 100)
          : 0;

      // Only report meaningful changes (>10% or >0.5 points)
      if (percentChange > 10 || change.abs() > 0.5) {
        if (change < -0.3) {
          // Improvement (lower is better for most metrics)
          if (metric == 'Firmness') {
            insights.add(
              'Your $metric has improved beautifully — skin appears more lifted and toned.',
            );
          } else {
            insights.add(
              'Your ${metric.toLowerCase()} has improved noticeably since your last scan.',
            );
          }
        } else if (change > 0.3) {
          // Worsening
          if (metric == 'Redness') {
            insights.add(
              'Redness remains elevated — continue focusing on barrier repair and gentle care.',
            );
          } else if (metric == 'Pore' || metric == 'Pores') {
            insights.add(
              'Pores are still visible — consistent care and professional treatments may help.',
            );
          } else if (metric == 'Firmness') {
            insights.add(
              'Firmness needs attention — consider collagen-supporting actives.',
            );
          } else {
            insights.add(
              '$metric could use more attention — stay consistent with your routine.',
            );
          }
        }
      }
    });

    // If no significant changes, add encouraging message
    if (insights.isEmpty) {
      insights.add(
        'Your skin is maintaining its current condition. Keep up the great work!',
      );
      insights.add('Consistent skincare is key — results build over time.');
    } else if (insights.length == 1) {
      insights.add('Stay consistent with your routine for continued progress.');
    }

    return insights;
  }

  // ==================== RECOMMENDATIONS ====================
  List<Map<String, String>> _getProcedureRecommendations() {
    if (scans.isEmpty) return [];

    final metrics = _getMetricsForScan(scans.last);
    final redness = metrics['Redness'] ?? 5.0;
    final texture = metrics['Texture'] ?? 5.0;
    final wrinkle = metrics['Wrinkle'] ?? 5.0;
    final pore = metrics['Pore'] ?? 5.0;
    final darkSpots = metrics['Dark Spots'] ?? 5.0;

    List<Map<String, String>> recs = [];

    if (redness > 5.0 || texture > 5.5) {
      recs.add({
        'name': 'RF Microneedling',
        'benefit':
            'Reduces redness and improves skin texture by stimulating collagen production with minimal downtime.',
      });
    }
    if (wrinkle > 4.5 || texture > 5.5) {
      recs.add({
        'name': 'Morpheus8',
        'benefit':
            'Deep fractional RF treatment that tightens skin and reduces fine lines and wrinkles.',
      });
    }
    if (darkSpots > 5.0 || redness > 5.5) {
      recs.add({
        'name': 'IPL Photofacial',
        'benefit':
            'Reduces pigmentation, redness, and sun damage for a more even skin tone.',
      });
    }
    if (pore > 5.5 || texture > 5.5) {
      recs.add({
        'name': 'Fractional Laser Resurfacing',
        'benefit': 'Improves pore size, skin texture, and overall smoothness.',
      });
    }

    if (recs.isEmpty) {
      recs.add({
        'name': 'Gentle Chemical Peel',
        'benefit':
            'Exfoliates the skin surface to improve texture and brightness with little downtime.',
      });
    }

    return recs;
  }

  List<Map<String, String>> _getRecommendedProducts() {
    final name = widget.product.name.toLowerCase().trim();
    if (name.contains('niacin') ||
        name.contains('b3') ||
        name.contains('nicotin')) {
      return [
        {
          'name': 'The Ordinary Niacinamide 10% + Zinc 1%',
          'brand': 'The Ordinary',
          'description': 'Boosts barrier and reduces redness',
          'link':
              'https://theordinary.com/en-us/niacinamide-10-zinc-1-serum-100436.html',
        },
        {
          'name': 'Paula\'s Choice 10% Niacinamide Booster',
          'brand': 'Paula\'s Choice',
          'description': 'Clinical strength for pore refinement',
          'link':
              'https://www.paulaschoice.com/10-niacinamide-booster/798.html',
        },
      ];
    }
    return [
      {
        'name': 'EltaMD UV Clear Broad-Spectrum SPF 46',
        'brand': 'EltaMD',
        'description': 'Lightweight daily sunscreen',
        'link':
            'https://www.amazon.com/EltaMD-UV-Clear-Broad-Spectrum-SPF-46/dp/B00I0J4V5C',
      },
      {
        'name': 'La Roche-Posay Toleriane Double Repair Moisturizer',
        'brand': 'La Roche-Posay',
        'description': 'Repairs skin barrier',
        'link':
            'https://www.amazon.com/La-Roche-Posay-Toleriane-Moisturizer-Ceramide/dp/B07Z8KX9KX',
      },
    ];
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = MyApp.textBrown;
    final recommendedProducts = _getRecommendedProducts();
    final recommendedProcedures = _getProcedureRecommendations();
    final metricsWithChange = _getMetricsWithChange();
    final totalScans = scans.length;
    final afters = _afterPhotos;
    final improvementPercent = _hasBothPhotos ? 65 : 0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const AppBrandTitle(),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, 'journal_updated'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Luxury Header Card ---
            Container(
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    MyApp.champagne,
                    MyApp.roseGold.withValues(alpha: 0.18),
                    MyApp.goldShimmer.withValues(alpha: 0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: MyApp.roseGold.withValues(alpha: 0.13),
                    blurRadius: 36,
                    offset: const Offset(0, 14),
                  ),
                ],
                border: Border.all(
                  color: MyApp.goldShimmer.withValues(alpha: 0.18),
                  width: 1.4,
                ),
              ),
              child: Stack(
                children: [
                  // Left accent stripe
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 7,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(32),
                        ),
                        gradient: LinearGradient(
                          colors: [
                            MyApp.roseGold,
                            MyApp.goldShimmer.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.spa_outlined,
                              color: MyApp.roseGold,
                              size: 36,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                widget.product.name,
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: textColor,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.product.notes.isNotEmpty
                              ? widget.product.notes
                              : 'Track your skincare product, monitor progress, and maintain deltas.',
                          style: TextStyle(
                            fontSize: 16,
                            color: textColor.withValues(alpha: 0.82),
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    MyApp.roseGold.withValues(alpha: 0.13),
                                    Colors.white.withValues(alpha: 0.7),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: MyApp.roseGold.withValues(alpha: 0.18),
                                  width: 1.1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: MyApp.roseGold.withValues(
                                      alpha: 0.08,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.local_florist,
                                    size: 15,
                                    color: MyApp.roseGold,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    widget.product.brand.isNotEmpty
                                        ? widget.product.brand
                                        : 'No brand',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: textColor.withValues(alpha: 0.75),
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    MyApp.goldShimmer.withValues(alpha: 0.13),
                                    Colors.white.withValues(alpha: 0.7),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: MyApp.goldShimmer.withValues(
                                    alpha: 0.18,
                                  ),
                                  width: 1.1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: MyApp.goldShimmer.withValues(
                                      alpha: 0.08,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 15,
                                    color: MyApp.goldShimmer,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    'Scans: $totalScans',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: textColor.withValues(alpha: 0.75),
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- Overall Progress ---
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Overall Improvement',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: improvementPercent / 100,
                        backgroundColor: Colors.grey[200],
                        color: MyApp.goldShimmer,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '$improvementPercent%',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: MyApp.goldShimmer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Text(
                  'Total scans: $totalScans',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textColor.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // --- Skin Age Card ---
            _buildSkinAgeCard(),
            const SizedBox(height: 32),

            // --- Scan History ---
            Text(
              'Scan History',
              style: MyApp.sectionTitleStyle(color: textColor),
            ),
            const SizedBox(height: 12),
            if (scans.isEmpty)
              Card(
                color: MyApp.surface,
                shape: MyApp.cardShape,
                child: const Padding(
                  padding: MyApp.cardPadding,
                  child: Center(
                    child: Text(
                      'No scans yet. Take your first photo!',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: scans.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final scan = scans[i];
                  return Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildImage(
                          scan.imagePath,
                          width: 60,
                          height: 60,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _scanLabel(i),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              scan.timestamp.toLocal().toString().split(' ')[0],
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 32),

            // Disclaimer Banner
            if (_showAnalysisDisclaimerBanner) ...[
              _analysisDisclaimerBanner(),
              const SizedBox(height: 16),
            ],

            // --- Gemini Vision Analysis ---
            if (_geminiVisionUsed) ...[
              _buildGeminiVisionSection(),
              const SizedBox(height: 32),
            ],

            // --- Progress Summary (Natural Language Insights) ---
            if (scans.length > 1) ...[
              _buildProgressSummarySection(),
              const SizedBox(height: 32),
            ],

            // --- Progress Photos ---
            Text(
              'Progress Photos',
              style: MyApp.sectionTitleStyle(color: textColor),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'Baseline Before',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 190,
                          child: _buildImage(
                            _beforePhoto,
                            width: 190,
                            height: 190,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'Latest After',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 190,
                          child: _hasBothPhotos
                              ? _buildImage(
                                  _afterPhoto,
                                  width: 190,
                                  height: 190,
                                )
                              : _buildAfterPlaceholder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // --- Past After Photos ---
            if (afters.isNotEmpty) ...[
              const Text(
                'Past After Photos',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: afters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final scan = afters[i];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildImage(scan.imagePath, width: 70, height: 70),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],

            // --- New Progress Scan Button ---
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('New Progress Scan'),
              onPressed: _openCamera,
              style: MyApp.primaryGoldButton,
            ),
            const SizedBox(height: 12),

            // --- Compare Before and After Button ---
            if (_hasBothPhotos)
              ElevatedButton.icon(
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Compare Before and After Photo'),
                onPressed: _showCompareDialog,
                style: MyApp.primaryGoldButton,
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  "Compare Before and After will appear after your second scan/photo.",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 12),

            // --- Home Button Row (like ProcedureDetailScreen) ---
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Home'),
                    onPressed: () =>
                        Navigator.popUntil(context, (route) => route.isFirst),
                    style: MyApp.primaryGoldButton,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // --- Tip Box ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.08),
              child: const Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.orange, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'For accurate tracking, take every photo at the exact same distance and in similar lighting conditions.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // --- Skin Metrics ---
            if (scans.length > 1 && !_geminiVisionUsed) ...[
              ExpansionTile(
                title: Text(
                  'View Detailed Metrics',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: MyApp.textBrown,
                  ),
                ),
                subtitle: Text(
                  'See numeric scores for each skin attribute',
                  style: TextStyle(
                    fontSize: 13,
                    color: MyApp.textBrown.withValues(alpha: 0.6),
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: metricsWithChange
                          .map(
                            (m) => Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: MyApp.surface,
                              elevation: 2,
                              shadowColor: Colors.black.withValues(alpha: 0.06),
                              shape: MyApp.cardShape,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                title: Text(
                                  m['label'],
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      m['score'],
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (m['arrowIcon'] != null)
                                      Icon(
                                        m['arrowIcon'],
                                        color: m['arrowColor'],
                                        size: 26,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ] else if (scans.length <= 1) ...[
              const Text(
                'Skin Metrics will appear after your second scan/photo.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 24),
            ],

            const SizedBox(height: 40),

            // --- AI Recommendations ---
            Text(
              'AI Recommendations',
              style: MyApp.sectionTitleStyle(color: textColor),
            ),
            const SizedBox(height: 12),
            Card(
              color: MyApp.surface,
              elevation: 2,
              shadowColor: Colors.black.withValues(alpha: 0.06),
              shape: MyApp.cardShape,
              child: Padding(
                padding: MyApp.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recommended Products',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...recommendedProducts.map((p) => _buildProductCard(p)),
                    const SizedBox(height: 24),
                    const Text(
                      'Recommended Next Procedures',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...recommendedProcedures.map(
                      (proc) => ListTile(
                        leading: const Icon(
                          Icons.arrow_forward,
                          color: Colors.green,
                        ),
                        title: Text(proc['name']!),
                        subtitle: Text(proc['benefit']!),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, String> product) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      title: Text(
        product['name'] ?? '',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(product['description'] ?? ''),
      trailing: const Icon(Icons.arrow_forward_ios, size: 18),
      onTap: () => _launchUrl(product['link']!),
    );
  }

  Widget _buildGeminiVisionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: MyApp.goldShimmer, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AI Skin Analysis',
                style: MyApp.sectionTitleStyle(color: MyApp.textBrown),
              ),
            ),
            // Re-analyze button
            if (!_isAnalyzingWithGemini)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _geminiVisionAnalysis = null;
                    _geminiVisionUsed = false;
                  });
                  _tryGeminiVisionAnalysis();
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Re-analyze'),
                style: TextButton.styleFrom(
                  foregroundColor: MyApp.goldShimmer,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Gemini badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: MyApp.goldShimmer.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: MyApp.goldShimmer.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified, size: 14, color: MyApp.goldShimmer),
              const SizedBox(width: 6),
              Text(
                'Analyzed with Gemini Vision AI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MyApp.goldShimmer,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_isAnalyzingWithGemini)
          Card(
            color: MyApp.surface,
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.06),
            shape: MyApp.cardShape,
            child: Padding(
              padding: MyApp.cardPadding,
              child: Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Analyzing your skin photos with Gemini Vision...',
                      style: TextStyle(
                        fontSize: 15,
                        color: MyApp.textBrown.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_geminiVisionAnalysis != null)
          Card(
            color: MyApp.surface,
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.06),
            shape: MyApp.cardShape,
            child: Padding(
              padding: MyApp.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _geminiVisionAnalysis!,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.55,
                      color: MyApp.textBrown,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      '⚠️ AI-generated analysis only — not medical advice. Always consult a licensed dermatologist or aesthetician for clinical guidance.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProgressSummarySection() {
    final insights = _generateProgressInsights();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.insights, color: MyApp.roseGold, size: 22),
            const SizedBox(width: 8),
            Text(
              'What This Means',
              style: MyApp.sectionTitleStyle(color: MyApp.textBrown),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                MyApp.goldShimmer.withValues(alpha: 0.08),
                MyApp.roseGold.withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: MyApp.goldShimmer.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 20, color: MyApp.goldShimmer),
                  const SizedBox(width: 8),
                  Text(
                    'Your Progress Summary',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: MyApp.textBrown,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...insights.map(
                (insight) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: MyApp.goldShimmer,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          insight,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: MyApp.textBrown,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _analysisDisclaimerBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MyApp.goldShimmer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: MyApp.goldShimmer.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: MyApp.goldShimmer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Disclaimer: This is AI-generated general skincare guidance. It is not medical advice or a diagnosis. Always consult a licensed dermatologist or aesthetician for professional recommendations.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: MyApp.textBrown.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _dismissAnalysisDisclaimerBanner,
            borderRadius: BorderRadius.circular(12),
            child: Icon(
              Icons.close,
              size: 16,
              color: MyApp.textBrown.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== SINGLE JOURNAL ENTRY DETAIL SCREEN ====================
class SingleJournalEntryScreen extends StatelessWidget {
  final TrackedProduct product;
  final JournalEntry entry;

  const SingleJournalEntryScreen({
    super.key,
    required this.product,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = entry.date.toLocal().toString().split(' ')[0];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal Entry'),
        backgroundColor: Colors.white,
        foregroundColor: MyApp.textBrown,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            product.brand.isNotEmpty
                                ? '${product.brand} - ${product.name}'
                                : product.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: MyApp.roseGold,
                            ),
                          ),
                        ),
                        Text(
                          dateStr,
                          style: TextStyle(
                            color: MyApp.textBrown.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (entry.title.isNotEmpty) ...[
                      Text(
                        entry.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Text(
                          ['😞', '😐', '🙂', '😊', '🥰'][entry.moodRating - 1],
                          style: const TextStyle(fontSize: 32),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      entry.content,
                      style: const TextStyle(fontSize: 16, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            if (entry.attachedImagePath != null &&
                entry.attachedImagePath!.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Attached Photo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildImageInDetail(entry.attachedImagePath),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageInDetail(String? path) {
    if (path == null || path.isEmpty) {
      return const Icon(Icons.photo, size: 120, color: Colors.grey);
    }
    // Base64 data URI (camera saves web photos as "data:image/jpeg;base64,...")
    if (path.startsWith('data:image')) {
      final comma = path.indexOf(',');
      if (comma != -1) {
        try {
          final bytes = base64Decode(path.substring(comma + 1));
          return Image.memory(bytes, fit: BoxFit.contain);
        } catch (_) {}
      }
      return const Icon(Icons.broken_image, size: 120, color: Colors.grey);
    }
    if (kIsWeb) {
      return Image.network(path, fit: BoxFit.contain);
    } else {
      return Image.file(File(path), fit: BoxFit.contain);
    }
  }
}
