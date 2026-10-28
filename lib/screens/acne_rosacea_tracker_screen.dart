// lib/screens/acne_rosacea_tracker_screen.dart
//
// The dedicated Acne & Rosacea Healing Companion. Combines per-symptom
// severity tracking, photo timeline + before/after comparison, and a
// deterministic AI insight + healing-plan engine driven by the user's logs,
// active product stack, and profile concerns.
//
// Architecture:
//   AppBar (gradient hero summary)
//   Sticky TabBar: Track · Photos · Insights · Plan
//   TabBarView with four lazy-loaded scrollable bodies
//   Floating Action Button: "Quick Log" — opens a unified bottom sheet
//     that captures metric + severity + photo + note in one pass.
//
// All AI is deterministic / on-device via AcneRosaceaIntelligence — no
// network calls, no opaque inference. See lib/utils/acne_rosacea_intelligence.dart.

import 'dart:convert' show base64Encode;
import 'dart:io' show Directory, File;
import 'dart:typed_data' show Uint8List;

import 'package:before_after/before_after.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';
import '../models/acne_rosacea_log.dart';
import '../models/product_tracker.dart';
import '../models/scan_history.dart';
import '../utils/acne_rosacea_intelligence.dart';
import '../utils/acne_rosacea_photo_analysis.dart';
import '../utils/ai/skin_analysis_model.dart';
import '../utils/ai/skin_analysis_runner.dart';
import '../utils/ai/skin_detections.dart';
import '../utils/app_prefs.dart';
import '../utils/skin_metric_labels.dart';
import '../widgets/clinical_metric_label.dart';
import '../widgets/clinical_section_header.dart';
import '../widgets/image_crop_dialog.dart';

class AcneRosaceaTrackerScreen extends StatefulWidget {
  /// Optional initial metric key to pre-expand on open (e.g. when
  /// launched from the Recovery Metric Detail screen).
  final String? initialMetricKey;

  /// If true, the AI Photo Analysis capture sheet opens automatically
  /// after the tracker finishes loading. Used by Home Quick Actions and
  /// Active Skincare Details to deep-link into the analysis flow.
  final bool autoOpenPhotoAnalysis;

  const AcneRosaceaTrackerScreen({
    super.key,
    this.initialMetricKey,
    this.autoOpenPhotoAnalysis = false,
  });

  @override
  State<AcneRosaceaTrackerScreen> createState() =>
      _AcneRosaceaTrackerScreenState();
}

class _AcneRosaceaTrackerScreenState extends State<AcneRosaceaTrackerScreen>
    with SingleTickerProviderStateMixin {
  Map<String, List<AcneRosaceaLog>> _logs = const {};
  AcneRosaceaInsightReport? _report;
  bool _loading = true;

  // Per-metric ephemeral form state.
  final Map<String, int> _draftValues = {};
  final Map<String, TextEditingController> _noteCtrls = {};
  final Set<String> _saving = {};
  String? _expandedKey;

  // Before/After photo selection.
  int? _baselinePhotoIndex;
  int? _comparePhotoIndex;
  double _beforeAfterValue = 0.5;

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    for (final spec in SkinMetricRegistry.acneAndRosacea) {
      _noteCtrls[spec.key] = TextEditingController();
    }
    _expandedKey = widget.initialMetricKey;
    _loadAll();
  }

  @override
  void dispose() {
    for (final c in _noteCtrls.values) {
      c.dispose();
    }
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final results = await Future.wait([
      AppPrefs.getAcneRosaceaLogs(),
      AppPrefs.getTrackedProducts(),
      AppPrefs.getUserSkinConcerns(),
    ]);
    if (!mounted) return;
    final logs = results[0] as Map<String, List<AcneRosaceaLog>>;
    final products = results[1] as List<TrackedProduct>;
    final concerns = results[2] as List<String>;
    final report = AcneRosaceaIntelligence.analyze(
      logs: logs,
      products: products,
      profileConcerns: concerns,
    );
    setState(() {
      _logs = logs;
      _report = report;
      for (final spec in SkinMetricRegistry.acneAndRosacea) {
        final last = (logs[spec.key] ?? const []).isNotEmpty
            ? logs[spec.key]!.first.value
            : (spec.lowerIsBetter ? 3 : 5);
        _draftValues[spec.key] = last;
      }
      // Baseline is permanent — always the oldest photo on record.
      // Compare defaults to the newest photo.
      final photos = _allPhotos();
      if (photos.length >= 2) {
        _baselinePhotoIndex = photos.length - 1; // oldest (locked)
        _comparePhotoIndex = 0; // newest
      } else if (photos.length == 1) {
        _baselinePhotoIndex = 0; // first ever — lock as baseline
        _comparePhotoIndex = 0;
      } else {
        _baselinePhotoIndex = null;
        _comparePhotoIndex = null;
      }
      _loading = false;
    });

    // Deep-link: auto-open the AI Photo Analysis sheet once after the
    // first successful load if the screen was launched in that mode.
    if (widget.autoOpenPhotoAnalysis && !_autoOpenedAnalysis) {
      _autoOpenedAnalysis = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPhotoAnalysis();
      });
    }
  }

  bool _autoOpenedAnalysis = false;

  List<AcneRosaceaLog> _allLogsSortedDesc() {
    final out = <AcneRosaceaLog>[];
    for (final list in _logs.values) {
      out.addAll(list);
    }
    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out;
  }

  List<AcneRosaceaLog> _allPhotos() =>
      _allLogsSortedDesc().where((e) => e.hasPhoto).toList();

  Future<void> _saveQuickLog({
    required String metricKey,
    required int value,
    required String note,
    required String imagePath,
  }) async {
    setState(() => _saving.add(metricKey));
    await AppPrefs.addAcneRosaceaLog(
      metricKey,
      value,
      note: note,
      imagePath: imagePath,
    );
    await _loadAll();
    if (!mounted) return;
    setState(() => _saving.remove(metricKey));
    final spec = SkinMetricRegistry.byKey(metricKey);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Logged ${spec?.shortName ?? metricKey} · level $value'
          '${imagePath.isNotEmpty ? ' · photo attached' : ''}',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.refinedSlate,
      ),
    );
  }

  Future<void> _saveLog(SkinMetricSpec spec) async {
    final value = _draftValues[spec.key] ?? 0;
    final note = _noteCtrls[spec.key]?.text ?? '';
    await _saveQuickLog(
      metricKey: spec.key,
      value: value,
      note: note,
      imagePath: '',
    );
    _noteCtrls[spec.key]?.clear();
  }

  Future<void> _deleteLog(String metricKey, DateTime timestamp) async {
    await AppPrefs.removeAcneRosaceaLog(metricKey, timestamp);
    await _loadAll();
  }

  Future<void> _openQuickLogSheet({String? presetMetricKey}) async {
    final result = await showModalBottomSheet<_QuickLogResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => _QuickLogSheet(
        presetMetricKey: presetMetricKey ?? _expandedKey,
        recentMetricKeys: _logs.entries
            .where((e) => e.value.isNotEmpty)
            .map((e) => e.key)
            .toList(),
        latestLogs: {
          for (final e in _logs.entries)
            if (e.value.isNotEmpty) e.key: e.value.first,
        },
      ),
    );
    if (result == null || !mounted) return;
    await _saveQuickLog(
      metricKey: result.metricKey,
      value: result.value,
      note: result.note,
      imagePath: result.imagePath,
    );
  }

  /// Opens the AI Photo Analysis flow. The user captures a photo + picks
  /// optional region/context flags; the engine auto-detects all 7 tracker
  /// metrics from pixel features, then the editable result screen lets
  /// the user adjust any value before persisting in a single batch.
  /// Runs the AI photo analyzer against the user's most recent scan in
  /// the global Scan History — no capture sheet required. Falls back to
  /// the standard capture flow if no scan photo is available. Used by
  /// the "Tap to analyze" empty state on metric tiles so users can have
  /// the AI determine their metrics straight from existing scans.
  Future<void> _analyzeFromLatestScan() async {
    List<ScanHistoryEntry> scans;
    try {
      scans = await AppPrefs.getScanEntries();
    } catch (_) {
      scans = const [];
    }
    final scanWithPhoto =
        scans.where((s) => (s.imagePath ?? '').trim().isNotEmpty).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (scanWithPhoto.isEmpty) {
      // No usable scan — fall back to the standard capture flow.
      await _openPhotoAnalysis();
      return;
    }

    final latest = scanWithPhoto.first;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.mutedSage,
        duration: Duration(seconds: 2),
        content: Text(
          'Analyzing your latest scan…',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );

    PhotoFeatures features;
    Uint8List? imageBytes;
    try {
      imageBytes = await XFile(latest.imagePath!).readAsBytes();
      features = PhotoFeatureExtractor.extract(imageBytes);
    } catch (_) {
      features = PhotoFeatures.neutral();
    }
    if (!mounted) return;

    final baseInput = PhotoAnalysisInput.fromFeatures(
      imagePath: latest.imagePath!,
      capturedAt: latest.timestamp,
      region: FacialRegion.fullFace,
      features: features,
      cycleRelatedFlare: false,
      adultOnset: false,
    );
    final aug = await SkinAnalysisRunner.augment(
      baseInput: baseInput,
      imageBytes: imageBytes,
    );
    final input = aug.input;

    // Baseline: oldest photo-bearing log strictly before this scan.
    AcneRosaceaLog? baseline;
    final allWithPhotos =
        _logs.values
            .expand((x) => x)
            .where(
              (e) =>
                  e.hasPhoto &&
                  e.timestamp.isBefore(
                    input.capturedAt.subtract(const Duration(hours: 1)),
                  ),
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (allWithPhotos.isNotEmpty) baseline = allWithPhotos.first;

    final report = AcneRosaceaPhotoAnalyzer.analyze(
      input: input,
      baselineSnapshot: baseline,
      history: _logs,
      confidence: SkinAnalysisRunner.resolveConfidence(
        featureConfidence: features.confidence,
        modelConfidence: aug.modelConfidence,
      ),
      features: features,
    );

    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PhotoAnalysisResultScreen(
          result: report,
          modelInfo: aug.modelInfo,
          modelConfidence: aug.modelConfidence,
          modelOwnedMetrics: aug.modelOwnedMetrics,
          meshUsed: aug.meshUsed,
          symmetryScore: aug.symmetryScore,
          faceCoverage: aug.faceCoverage,
          yoloUsed: aug.yoloUsed,
          detections: aug.detections,
          efficientNetUsed: aug.efficientNetUsed,
          qualityScores: aug.qualityScores,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _loadAll();
    }
  }

  Future<void> _openPhotoAnalysis() async {
    final capture = await showModalBottomSheet<_AnalysisCapture>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => const _PhotoAnalysisInputSheet(),
    );
    if (capture == null || !mounted) return;

    // Read photo bytes (cross-platform via XFile) and extract features.
    // Prefer the cropped bytes captured in the input sheet so the analyzer
    // never sees the uncropped original.
    PhotoFeatures features;
    Uint8List? imageBytes = capture.imageBytes;
    try {
      imageBytes ??= await XFile(capture.imagePath).readAsBytes();
      features = PhotoFeatureExtractor.extract(imageBytes);
    } catch (_) {
      features = PhotoFeatures.neutral();
    }
    if (!mounted) return;

    final baseInput = PhotoAnalysisInput.fromFeatures(
      imagePath: capture.imagePath,
      capturedAt: DateTime.now(),
      region: capture.region,
      features: features,
      cycleRelatedFlare: capture.cycleRelated,
      adultOnset: capture.adultOnset,
    );
    final aug = await SkinAnalysisRunner.augment(
      baseInput: baseInput,
      imageBytes: imageBytes,
    );
    final input = aug.input;

    // Baseline: oldest photo-bearing log strictly before this capture.
    AcneRosaceaLog? baseline;
    final allWithPhotos =
        _logs.values
            .expand((x) => x)
            .where(
              (e) =>
                  e.hasPhoto &&
                  e.timestamp.isBefore(
                    input.capturedAt.subtract(const Duration(hours: 1)),
                  ),
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (allWithPhotos.isNotEmpty) baseline = allWithPhotos.first;

    final report = AcneRosaceaPhotoAnalyzer.analyze(
      input: input,
      baselineSnapshot: baseline,
      history: _logs,
      confidence: SkinAnalysisRunner.resolveConfidence(
        featureConfidence: features.confidence,
        modelConfidence: aug.modelConfidence,
      ),
      features: features,
    );

    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PhotoAnalysisResultScreen(
          result: report,
          modelInfo: aug.modelInfo,
          modelConfidence: aug.modelConfidence,
          modelOwnedMetrics: aug.modelOwnedMetrics,
          meshUsed: aug.meshUsed,
          symmetryScore: aug.symmetryScore,
          faceCoverage: aug.faceCoverage,
          yoloUsed: aug.yoloUsed,
          detections: aug.detections,
          efficientNetUsed: aug.efficientNetUsed,
          qualityScores: aug.qualityScores,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    const textColor = AppColors.refinedSlate;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.champagneGold,
              foregroundColor: AppColors.refinedSlate,
              onPressed: () => _openQuickLogSheet(),
              icon: const Icon(Icons.add_chart_rounded),
              label: const Text(
                'Quick Log',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (ctx, inner) => [
                SliverAppBar(
                  backgroundColor: AppColors.cardBackground,
                  foregroundColor: textColor,
                  elevation: 0,
                  scrolledUnderElevation: 0.5,
                  pinned: true,
                  expandedHeight: 198,
                  title: const Text(
                    'Acne & Rosacea Healing',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: _buildHeroSummary(textColor),
                    collapseMode: CollapseMode.parallax,
                  ),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(46),
                    child: Container(
                      color: AppColors.cardBackground,
                      child: TabBar(
                        controller: _tabCtrl,
                        indicatorColor: AppColors.champagneGold,
                        indicatorWeight: 2.5,
                        labelColor: AppColors.champagneGold,
                        unselectedLabelColor: textColor.withValues(alpha: 0.52),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          letterSpacing: 0.4,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          letterSpacing: 0.4,
                        ),
                        tabs: const [
                          Tab(text: 'Track'),
                          Tab(text: 'Photos'),
                          Tab(text: 'Insights'),
                          Tab(text: 'Plan'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildTrackTab(textColor),
                  _buildPhotosTab(textColor),
                  _buildInsightsTab(textColor),
                  _buildPlanTab(textColor),
                ],
              ),
            ),
    );
  }

  // ── Hero summary ──────────────────────────────────────────────────────
  Widget _buildHeroSummary(Color textColor) {
    final report = _report;
    final overall = report?.overallSeverityIndex ?? 0;
    final band = report?.overallBand ?? SeverityBand.clear;
    final color = _severityColorFromBand(band);
    final headline = report?.headline ?? 'Symptom journal';
    final sub = report?.subheadline ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.28)),
                ),
                child: Text(
                  overall.toStringAsFixed(1),
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _bandLabel(band),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: textColor.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 1: Track ──────────────────────────────────────────────────────
  Widget _buildTrackTab(Color textColor) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _buildPhotoAnalysisCta(textColor),
        const SizedBox(height: 16),
        _buildNextStepBanner(textColor),
        const SizedBox(height: 18),
        ClinicalSectionHeader(
          icon: Icons.monitor_heart_outlined,
          title: 'Skin Metrics',
          eyebrow: 'Latest reading · 7-day trend · severity bar',
          textColor: textColor,
        ),
        const SizedBox(height: 8),
        _buildLastAnalyzedIndicator(textColor),
        _buildClinicalMetricsPanel(textColor),
        const SizedBox(height: 22),
        _buildRecentEntriesSection(textColor),
        const SizedBox(height: 22),
        ClinicalSectionHeader(
          icon: Icons.timeline_outlined,
          title: 'Log Severity',
          eyebrow: 'Tap a metric to log severity',
          textColor: textColor,
        ),
        const SizedBox(height: 12),
        for (final spec in SkinMetricRegistry.acneAndRosacea) ...[
          _buildMetricCard(spec, textColor),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        _buildDisclaimer(textColor),
      ],
    );
  }

  // ── Tab 2: Photos ─────────────────────────────────────────────────────
  Widget _buildPhotosTab(Color textColor) {
    final photos = _allPhotos();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (photos.isNotEmpty) ...[
          ClinicalSectionHeader(
            icon: Icons.push_pin_outlined,
            title: 'Permanent Baseline',
            eyebrow: 'Your first reference photo — locked',
            textColor: textColor,
          ),
          const SizedBox(height: 12),
          _buildBaselinePinnedCard(photos.last, textColor),
          const SizedBox(height: 24),
        ],
        ClinicalSectionHeader(
          icon: Icons.compare_outlined,
          title: 'Before & After',
          eyebrow: photos.length < 2
              ? 'Capture 2+ photos to unlock'
              : 'Drag slider to compare against baseline',
          textColor: textColor,
        ),
        const SizedBox(height: 12),
        _buildBeforeAfterCard(photos, textColor),
        const SizedBox(height: 24),
        ClinicalSectionHeader(
          icon: Icons.photo_library_outlined,
          title: 'Photo Timeline',
          eyebrow: photos.isEmpty
              ? 'No photos yet'
              : '${photos.length} ${photos.length == 1 ? 'photo' : 'photos'}',
          textColor: textColor,
        ),
        const SizedBox(height: 12),
        _buildPhotoTimeline(photos, textColor),
        const SizedBox(height: 18),
        _buildPhotoTips(textColor),
      ],
    );
  }

  // ── Tab 3: Insights ───────────────────────────────────────────────────
  Widget _buildInsightsTab(Color textColor) {
    final report = _report;
    if (report == null || !report.hasEnoughData) {
      return _buildEmptyInsights(textColor);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _buildInsightHeadlineCard(report, textColor),
        const SizedBox(height: 22),
        ClinicalSectionHeader(
          icon: Icons.trending_down_rounded,
          title: 'Progress Trends',
          eyebrow: '7-day & 30-day deltas',
          textColor: textColor,
        ),
        const SizedBox(height: 12),
        if (report.trends.isEmpty)
          _emptyMiniCard(
            'Log a few entries to unlock trend analysis.',
            textColor,
          )
        else
          for (final t in report.trends) ...[
            _buildTrendCard(t, textColor),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 16),
        ClinicalSectionHeader(
          icon: Icons.psychology_outlined,
          title: 'Trigger Hypotheses',
          eyebrow: 'Pattern detection from logs',
          textColor: textColor,
        ),
        const SizedBox(height: 12),
        if (report.triggers.isEmpty)
          _emptyMiniCard(
            'No clear trigger pattern yet — keep logging notes during flares.',
            textColor,
          )
        else
          for (final t in report.triggers) ...[
            _buildTriggerCard(t, textColor),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 16),
        if (report.warnings.isNotEmpty) ...[
          ClinicalSectionHeader(
            icon: Icons.warning_amber_rounded,
            title: 'Compatibility Warnings',
            eyebrow: 'Your product stack vs active symptoms',
            textColor: textColor,
          ),
          const SizedBox(height: 12),
          for (final w in report.warnings) ...[
            _buildWarningCard(w, textColor),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
        ],
        ClinicalSectionHeader(
          icon: Icons.science_outlined,
          title: 'Personalized Recommendations',
          eyebrow: 'Targeted to your dominant subtype',
          textColor: textColor,
        ),
        const SizedBox(height: 12),
        if (report.recommendations.isEmpty)
          _emptyMiniCard(
            'Log a few more entries to unlock product recommendations.',
            textColor,
          )
        else
          for (final r in report.recommendations) ...[
            _buildRecommendationCard(r, textColor),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 18),
        _buildDisclaimer(textColor),
      ],
    );
  }

  // ── Tab 4: Plan ───────────────────────────────────────────────────────
  Widget _buildPlanTab(Color textColor) {
    final report = _report;
    if (report == null || !report.hasEnoughData) {
      return _buildEmptyPlan(textColor);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _buildHealingSummaryCard(report, textColor),
        const SizedBox(height: 18),
        if (report.dailyActions.isNotEmpty) ...[
          ClinicalSectionHeader(
            icon: Icons.wb_sunny_outlined,
            title: 'Daily Protocol',
            eyebrow: 'What to do today',
            textColor: textColor,
          ),
          const SizedBox(height: 12),
          _buildActionList(
            actions: report.dailyActions,
            accent: AppColors.champagneGold,
            textColor: textColor,
          ),
          const SizedBox(height: 22),
        ],
        if (report.weeklyActions.isNotEmpty) ...[
          ClinicalSectionHeader(
            icon: Icons.event_repeat_outlined,
            title: 'This Week',
            eyebrow: 'Action checklist',
            textColor: textColor,
          ),
          const SizedBox(height: 12),
          _buildActionList(
            actions: report.weeklyActions,
            accent: AppColors.mutedSage,
            textColor: textColor,
          ),
          const SizedBox(height: 22),
        ],
        for (final plan in report.subtypePlans) ...[
          ClinicalSectionHeader(
            icon: _subtypeIcon(plan.subtype),
            title: plan.subtypeLabel,
            eyebrow: 'Week-by-week protocol',
            textColor: textColor,
          ),
          const SizedBox(height: 12),
          _buildSubtypePlanCard(plan, textColor),
          if (plan.naturalAlternatives.isNotEmpty) ...[
            const SizedBox(height: 16),
            ClinicalSectionHeader(
              icon: Icons.eco_outlined,
              title: 'Natural Alternatives',
              eyebrow: 'Evidence-based clean swaps',
              textColor: textColor,
            ),
            const SizedBox(height: 10),
            for (final r in plan.naturalAlternatives) ...[
              _buildRecommendationCard(r, textColor),
              const SizedBox(height: 10),
            ],
            _buildNaturalDisclaimer(textColor),
          ],
          const SizedBox(height: 22),
        ],
        ClinicalSectionHeader(
          icon: Icons.menu_book_outlined,
          title: 'Tailored Skin Guidance',
          eyebrow: 'Reference protocols',
          textColor: textColor,
        ),
        const SizedBox(height: 12),
        _buildGuidanceCard(textColor),
        const SizedBox(height: 18),
        _buildDisclaimer(textColor),
      ],
    );
  }

  // ── Recent entries (cross-metric) ─────────────────────────────────────
  Widget _buildRecentEntriesSection(Color textColor) {
    final recent = <AcneRosaceaLog>[];
    for (final list in _logs.values) {
      recent.addAll(list);
    }
    recent.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final shown = recent.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClinicalSectionHeader(
          icon: Icons.history_rounded,
          title: 'Recent Journal',
          eyebrow: shown.isEmpty
              ? 'No entries yet'
              : '${recent.length} ${recent.length == 1 ? 'entry' : 'entries'}',
          textColor: textColor,
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          _buildEmptyJournalCard(textColor)
        else
          Card(
            margin: EdgeInsets.zero,
            elevation: 1.5,
            shadowColor: AppColors.refinedSlate.withValues(alpha: 0.06),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: AppColors.champagneGold.withValues(alpha: 0.14),
                width: 0.8,
              ),
            ),
            color: AppColors.cardBackground,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    _buildRecentRow(shown[i], textColor),
                    if (i < shown.length - 1)
                      Divider(
                        height: 1,
                        indent: 56,
                        endIndent: 16,
                        color: AppColors.champagneGold.withValues(alpha: 0.10),
                      ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyJournalCard(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.14),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            color: AppColors.champagneGold.withValues(alpha: 0.62),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No entries yet. Log a flare or improvement below to start your '
              'symptom timeline.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: textColor.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRow(AcneRosaceaLog log, Color textColor) {
    final spec = SkinMetricRegistry.byKey(log.metricKey);
    final label = spec?.shortName ?? log.metricKey;
    final icon = spec?.icon ?? Icons.circle_outlined;
    final color = _severityColor(log.value);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: color.withValues(alpha: 0.30),
                width: 0.8,
              ),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Level ${log.value}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: color,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(log.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.58),
                  ),
                ),
                if (log.note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    log.note,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: textColor.withValues(alpha: 0.80),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: textColor.withValues(alpha: 0.40),
            ),
            tooltip: 'Delete entry',
            onPressed: () => _deleteLog(log.metricKey, log.timestamp),
          ),
        ],
      ),
    );
  }

  // ── Clinical metrics panel (Track tab top) ────────────────────────────
  Widget _buildClinicalMetricsPanel(Color textColor) {
    final report = _report;
    final trendsByKey = <String, MetricTrend>{
      if (report != null)
        for (final t in report.trends) t.metricKey: t,
    };
    const specs = SkinMetricRegistry.acneAndRosacea;
    final loggedCount = specs
        .where((s) => (_logs[s.key] ?? const []).isNotEmpty)
        .length;
    final totalEntries = specs.fold<int>(
      0,
      (a, s) => a + (_logs[s.key]?.length ?? 0),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.cardBackground,
            AppColors.champagneGold.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.22),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header strip — tracked count + total entries
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.mutedSage.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.mutedSage.withValues(alpha: 0.32),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.health_and_safety_outlined,
                        size: 12,
                        color: AppColors.mutedSage,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$loggedCount / ${specs.length} tracked',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.mutedSage,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  totalEntries == 0
                      ? 'No entries yet'
                      : '$totalEntries '
                            '${totalEntries == 1 ? 'entry' : 'entries'}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: textColor.withValues(alpha: 0.55),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < specs.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.6,
                color: AppColors.champagneGold.withValues(alpha: 0.12),
              ),
            _buildClinicalMetricRow(
              specs[i],
              trendsByKey[specs[i].key],
              textColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClinicalMetricRow(
    SkinMetricSpec spec,
    MetricTrend? trend,
    Color textColor,
  ) {
    final list = _logs[spec.key] ?? const [];
    final hasEntries = list.isNotEmpty;
    final latest = hasEntries ? list.first.value : null;
    final color = _severityColor(latest ?? -1);
    final severityLabel = latest == null ? null : _severityLabel(latest);
    final pct = (latest ?? 0) / 10.0;
    final trendIcon = trend == null
        ? Icons.remove_rounded
        : trend.direction7d == TrendDirection.improving
        ? Icons.trending_down_rounded
        : trend.direction7d == TrendDirection.worsening
        ? Icons.trending_up_rounded
        : Icons.trending_flat_rounded;
    final trendColor = trend == null
        ? AppColors.refinedSlate.withValues(alpha: 0.55)
        : trend.direction7d == TrendDirection.improving
        ? AppColors.mutedSage
        : trend.direction7d == TrendDirection.worsening
        ? AppColors.softTerracotta
        : AppColors.refinedSlate;
    final deltaText = (trend == null || latest == null)
        ? '—'
        : trend.deltaPct7d.abs() < 0.5
        ? 'steady'
        : '${trend.deltaPct7d > 0 ? '+' : ''}'
              '${trend.deltaPct7d.toStringAsFixed(0)}%';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // No prior entry → run AI on the user's latest scan so the
        // metric gets determined automatically. Existing entries still
        // open Quick Log for edits / fresh manual logs.
        onTap: () => hasEntries
            ? _openQuickLogSheet(presetMetricKey: spec.key)
            : _analyzeFromLatestScan(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.champagneGold.withValues(alpha: 0.20),
                          AppColors.champagneGold.withValues(alpha: 0.12),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: AppColors.champagneGold.withValues(alpha: 0.28),
                        width: 0.7,
                      ),
                    ),
                    child: Icon(
                      spec.icon,
                      size: 16,
                      color: AppColors.champagneGold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClinicalMetricLabel(
                      label: spec.clinicalName,
                      compact: false,
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: latest == null
                          ? AppColors.refinedSlate.withValues(alpha: 0.10)
                          : color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: latest == null
                            ? AppColors.refinedSlate.withValues(alpha: 0.22)
                            : color.withValues(alpha: 0.32),
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      latest == null ? '—' : '$latest / 10',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: latest == null
                            ? textColor.withValues(alpha: 0.45)
                            : color,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (latest != null) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        severityLabel!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: color,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    if (list.first.note.startsWith('AI photo analysis')) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.champagneGold.withValues(alpha: 0.18),
                              AppColors.champagneGold.withValues(alpha: 0.18),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.42,
                            ),
                            width: 0.5,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 8,
                              color: AppColors.champagneGold,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'AI · PHOTO',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                color: AppColors.champagneGold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Icon(trendIcon, size: 13, color: trendColor),
                    const SizedBox(width: 3),
                    Text(
                      '7d $deltaText',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: trendColor,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDate(list.first.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: textColor.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: AppColors.refinedSlate.withValues(
                      alpha: 0.10,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                if (latest <= 1) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 12,
                        color: AppColors.mutedSage,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _absencePhrase(spec.key),
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                            color: textColor.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ] else ...[
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 14,
                      color: AppColors.mutedSage,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _absencePhrase(spec.key),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: textColor.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                    const Text(
                      'Tap to analyze →',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.champagneGold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.refinedSlate.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Permanent baseline pinned card (Photos tab top) ───────────────────
  Widget _buildBaselinePinnedCard(AcneRosaceaLog baseline, Color textColor) {
    final spec = SkinMetricRegistry.byKey(baseline.metricKey);
    final color = _severityColor(baseline.value);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.mutedSage.withValues(alpha: 0.10),
            AppColors.champagneGold.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.mutedSage.withValues(alpha: 0.32),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 96,
              height: 96,
              child: _localPhotoImage(baseline.imagePath),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 13,
                      color: AppColors.mutedSage,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'BASELINE',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: AppColors.mutedSage,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(baseline.timestamp),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${spec?.shortName ?? baseline.metricKey} · ${_severityLabel(baseline.value)} (${baseline.value}/10)',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your first reference photo is permanently locked. Every future photo compares against this image.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: textColor.withValues(alpha: 0.70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Per-metric card ───────────────────────────────────────────────────
  Widget _buildMetricCard(SkinMetricSpec spec, Color textColor) {
    final list = _logs[spec.key] ?? const [];
    final hasEntries = list.isNotEmpty;
    final latestValue = hasEntries ? list.first.value : null;
    final latestColor = _severityColor(latestValue ?? -1);
    final isSaving = _saving.contains(spec.key);
    final expanded = _expandedKey == spec.key;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1.5,
      shadowColor: AppColors.refinedSlate.withValues(alpha: 0.06),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: expanded
              ? AppColors.champagneGold.withValues(alpha: 0.45)
              : AppColors.champagneGold.withValues(alpha: 0.14),
          width: 0.8,
        ),
      ),
      color: AppColors.cardBackground,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expandedKey = expanded ? null : spec.key),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.champagneGold.withValues(alpha: 0.20),
                          AppColors.champagneGold.withValues(alpha: 0.14),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.champagneGold.withValues(alpha: 0.28),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      spec.icon,
                      color: AppColors.champagneGold,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClinicalMetricLabel(
                      label: spec.clinicalName,
                      compact: false,
                    ),
                  ),
                  if (latestValue != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: latestColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$latestValue / 10',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: latestColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: textColor.withValues(alpha: 0.50),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 48, top: 6),
                child: Text(
                  hasEntries
                      ? 'Last logged ${_formatDate(list.first.timestamp)}'
                      : '${_absencePhrase(spec.key)} — AI will populate this from your latest scan',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: textColor.withValues(alpha: 0.56),
                    fontStyle: hasEntries ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ),
              if (expanded) ...[
                const SizedBox(height: 14),
                _buildSliderRow(spec, textColor),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteCtrls[spec.key],
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: 13, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Optional note — triggers, products, location…',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: textColor.withValues(alpha: 0.40),
                    ),
                    filled: true,
                    fillColor: AppColors.canvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.champagneGold.withValues(alpha: 0.18),
                        width: 0.8,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.champagneGold.withValues(alpha: 0.18),
                        width: 0.8,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.champagneGold.withValues(alpha: 0.55),
                        width: 1.0,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isSaving ? null : () => _saveLog(spec),
                    icon: isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_chart_rounded, size: 18),
                    label: Text(isSaving ? 'Saving…' : 'Save level'),
                    style: MyApp.primaryGoldButton,
                  ),
                ),
                if (list.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'RECENT FOR THIS METRIC',
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: AppColors.champagneGold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final entry in list.take(3))
                    _buildInlineEntry(entry, textColor),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow(SkinMetricSpec spec, Color textColor) {
    final value = _draftValues[spec.key] ?? 0;
    final color = _severityColor(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Severity level',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: textColor.withValues(alpha: 0.72),
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$value · ${_severityLabel(value)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: color.withValues(alpha: 0.18),
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.18),
            valueIndicatorColor: color,
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            label: '$value',
            onChanged: (v) =>
                setState(() => _draftValues[spec.key] = v.round()),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineEntry(AcneRosaceaLog entry, Color textColor) {
    final color = _severityColor(entry.value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withValues(alpha: 0.28),
                width: 0.8,
              ),
            ),
            child: Text(
              '${entry.value}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(entry.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: textColor.withValues(alpha: 0.68),
                  ),
                ),
                if (entry.note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.note,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: textColor.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(
              Icons.close_rounded,
              size: 14,
              color: textColor.withValues(alpha: 0.36),
            ),
            tooltip: 'Delete',
            onPressed: () => _deleteLog(entry.metricKey, entry.timestamp),
          ),
        ],
      ),
    );
  }

  // ── Subtype guidance ──────────────────────────────────────────────────
  Widget _buildGuidanceCard(Color textColor) {
    final tiles = <_GuidanceTile>[
      const _GuidanceTile(
        icon: Icons.bubble_chart_outlined,
        title: 'Cystic Acne',
        eyebrow: 'Deep nodulocystic lesions',
        bullets: [
          'Never pop or extract — risks permanent scarring and post-inflammatory hyperpigmentation.',
          'Topicals alone rarely resolve cysts. A board-certified dermatologist may prescribe oral antibiotics, hormonal therapy, or isotretinoin.',
          'Cold compress 10 minutes 2–3× / day to reduce inflammation.',
          'Photograph active cysts so your dermatologist can track resolution.',
        ],
      ),
      const _GuidanceTile(
        icon: Icons.calendar_month_outlined,
        title: 'Hormonal Acne',
        eyebrow: 'Jawline & chin pattern',
        bullets: [
          'Log breakouts against your cycle — flares 7–10 days pre-menses are a hormonal signature.',
          'Spironolactone, combined oral contraceptives, or low-dose isotretinoin are evidence-based options.',
          'Topical: gentle BHA, azelaic acid, and tretinoin work over 8–12 weeks.',
          'Reduce dairy and high-glycemic foods if you notice a pattern in your journal.',
        ],
      ),
      const _GuidanceTile(
        icon: Icons.local_florist_outlined,
        title: 'Rosacea',
        eyebrow: 'Central-face redness',
        bullets: [
          'Barrier-first: gentle cleanser, ceramide moisturizer, mineral SPF 30+ daily.',
          'Prescription topicals: azelaic acid 15%, ivermectin 1%, metronidazole 0.75%.',
          'Keep a trigger log — heat, alcohol, spicy food, stress, and UV are common.',
          'Avoid scrubs, alcohol-based toners, fragrance, and aggressive actives.',
        ],
      ),
      const _GuidanceTile(
        icon: Icons.thermostat_outlined,
        title: 'Flushing Episodes',
        eyebrow: 'Transient erythema',
        bullets: [
          'Topical alpha-agonists (brimonidine, oxymetazoline) provide hours of relief.',
          'Beta-blockers (under physician supervision) reduce frequency for some patients.',
          'Cool environment, slow breathing, and SPF reduce trigger load.',
        ],
      ),
      const _GuidanceTile(
        icon: Icons.account_tree_outlined,
        title: 'Visible Blood Vessels',
        eyebrow: 'Telangiectasia',
        bullets: [
          'Vascular laser (KTP, Nd:YAG) or IPL is the gold-standard treatment.',
          'Wait until inflammation is controlled before treating — laser is most effective on quiescent skin.',
          'Daily SPF prevents new vessel formation.',
        ],
      ),
      const _GuidanceTile(
        icon: Icons.flash_on_outlined,
        title: 'Skin Sensitivity',
        eyebrow: 'Reactivity & stinging',
        bullets: [
          'Pull all actives for 2 weeks. Reintroduce one at a time at low frequency.',
          'Anchor on ceramides, panthenol, centella asiatica, and niacinamide.',
          'Avoid hot water, mechanical exfoliation, and fragranced products.',
          'Patch-test new products on the inner forearm for 3 nights first.',
        ],
      ),
    ];
    return Column(
      children: [for (final t in tiles) _buildGuidanceTile(t, textColor)],
    );
  }

  Widget _buildGuidanceTile(_GuidanceTile tile, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.14),
          width: 0.8,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          iconColor: AppColors.champagneGold,
          collapsedIconColor: AppColors.champagneGold.withValues(alpha: 0.50),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.champagneGold.withValues(alpha: 0.20),
                  AppColors.champagneGold.withValues(alpha: 0.14),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.28),
                width: 0.8,
              ),
            ),
            child: Icon(tile.icon, color: AppColors.champagneGold, size: 18),
          ),
          title: Text(
            tile.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              tile.eyebrow,
              style: TextStyle(
                fontSize: 11.5,
                color: textColor.withValues(alpha: 0.60),
              ),
            ),
          ),
          children: [
            for (final b in tile.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppColors.champagneGold,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        b,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: textColor.withValues(alpha: 0.82),
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

  Widget _buildDisclaimer(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.refinedSlate.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: textColor.withValues(alpha: 0.62),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This tracker is an AI-assisted symptom journal — not medical '
              'advice. For persistent breakouts, cystic lesions, or active '
              'rosacea, consult a board-certified dermatologist.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: textColor.withValues(alpha: 0.70),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact disclaimer attached to each "Natural Alternatives" subsection
  /// reminding users these are *supporting* options, not replacements for
  /// dermatologist-prescribed care.
  Widget _buildNaturalDisclaimer(Color textColor) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.mutedSage.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.mutedSage.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.eco_outlined, size: 14, color: AppColors.mutedSage),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Natural actives are supportive options — they pair best with '
              'evidence-based core care above, not in place of it. Patch-test '
              'new ingredients for 48 hours.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: textColor.withValues(alpha: 0.72),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── "Last analyzed from photo on …" indicator ───────────────────────
  /// Small contextual pill rendered above the Clinical Metrics panel
  /// when at least one metric was last saved via the AI photo flow.
  /// Mirrors the source of truth on the Track tab so users know which
  /// readings came from AI vs. manual logging.
  Widget _buildLastAnalyzedIndicator(Color textColor) {
    DateTime? mostRecent;
    for (final list in _logs.values) {
      for (final log in list) {
        if (!log.note.startsWith('AI photo analysis')) continue;
        if (mostRecent == null || log.timestamp.isAfter(mostRecent)) {
          mostRecent = log.timestamp;
        }
      }
    }
    if (mostRecent == null) {
      return const SizedBox(height: 4);
    }
    final rel = _relativeFromNow(mostRecent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.champagneGold.withValues(alpha: 0.10),
              AppColors.champagneGold.withValues(alpha: 0.10),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.champagneGold.withValues(alpha: 0.35),
            width: 0.6,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 13,
              color: AppColors.champagneGold,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Last analyzed from photo $rel',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: textColor.withValues(alpha: 0.78),
                ),
              ),
            ),
            TextButton(
              onPressed: _openPhotoAnalysis,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.champagneGold,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Re-analyze',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact "5m ago / 3h ago / 2d ago" formatter used by the indicator.
  String _relativeFromNow(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).round()}w ago';
    return 'on ${t.month}/${t.day}/${t.year}';
  }

  // ── AI Photo Analysis CTA ───────────────────────────────────────────
  /// Hero CTA shown at the top of the Track tab. Opens the photo capture
  /// + symptom input sheet, runs the deterministic analyzer, and pushes
  /// the dermatologist-style result screen.
  Widget _buildPhotoAnalysisCta(Color textColor) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: _openPhotoAnalysis,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.refinedSlate.withValues(alpha: 0.92),
              AppColors.mutedSage.withValues(alpha: 0.92),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.refinedSlate.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.champagneGold.withValues(alpha: 0.95),
                    AppColors.champagneGold.withValues(alpha: 0.95),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.champagneGold.withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                            width: 0.6,
                          ),
                        ),
                        child: const Text(
                          'NEW · AI',
                          style: TextStyle(
                            fontSize: 8.5,
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'AI ANALYSIS',
                        style: TextStyle(
                          fontSize: 8.5,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Take an analysis photo',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Detect acne type, rosacea pattern, procedure fit, and '
                    'compare against your baseline.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.84),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }

  // ── Next-step banner ─────────────────────────────────────────────────
  Widget _buildNextStepBanner(Color textColor) {
    final next =
        _report?.nextStep ??
        'Tap "Quick Log" to record today\'s severity and (optionally) a photo.';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.14),
            AppColors.champagneGold.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.30),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.champagneGold,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NEXT BEST STEP',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: AppColors.champagneGold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  next,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: textColor.withValues(alpha: 0.85),
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

  // ── Photos: Before/After + Timeline ───────────────────────────────────
  Widget _buildBeforeAfterCard(List<AcneRosaceaLog> photos, Color textColor) {
    if (photos.length < 2) {
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.champagneGold.withValues(alpha: 0.14),
            width: 0.8,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.compare_outlined,
              size: 36,
              color: AppColors.champagneGold.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 10),
            Text(
              photos.isEmpty
                  ? 'No photos yet. Take your first photo via Quick Log to start your healing timeline.'
                  : 'Add one more photo to unlock the before/after slider.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: textColor.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      );
    }
    final baseline = photos[_baselinePhotoIndex ?? photos.length - 1];
    final compare = photos[_comparePhotoIndex ?? 0];
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1.5,
      shadowColor: AppColors.refinedSlate.withValues(alpha: 0.06),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.champagneGold.withValues(alpha: 0.16),
          width: 0.8,
        ),
      ),
      color: AppColors.cardBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                // before_after package: `before` is on the RIGHT, `after`
                // on the LEFT. We swap to put older photo on the LEFT.
                child: BeforeAfter(
                  value: _beforeAfterValue,
                  onValueChanged: (v) => setState(() => _beforeAfterValue = v),
                  before: _localPhotoImage(compare.imagePath),
                  after: _localPhotoImage(baseline.imagePath),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _baCaption(
                    label: 'BEFORE',
                    date: baseline.timestamp,
                    severity: baseline.value,
                    metricKey: baseline.metricKey,
                    textColor: textColor,
                    align: CrossAxisAlignment.start,
                  ),
                ),
                Expanded(
                  child: _baCaption(
                    label: 'NOW',
                    date: compare.timestamp,
                    severity: compare.value,
                    metricKey: compare.metricKey,
                    textColor: textColor,
                    align: CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tap a thumbnail below to set "Now". The baseline (oldest photo) is permanently locked as your reference.',
              style: TextStyle(
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                color: textColor.withValues(alpha: 0.52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _localPhotoImage(String path) {
    if (path.isEmpty) {
      return Container(color: AppColors.refinedSlate.withValues(alpha: 0.15));
    }
    if (kIsWeb) {
      return Image.network(path, fit: BoxFit.cover);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }

  Widget _baCaption({
    required String label,
    required DateTime date,
    required int severity,
    required String metricKey,
    required Color textColor,
    required CrossAxisAlignment align,
  }) {
    final spec = SkinMetricRegistry.byKey(metricKey);
    final color = _severityColor(severity);
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w800,
            color: AppColors.champagneGold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _formatDate(date),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${spec?.shortName ?? metricKey} · ${_severityLabel(severity)} ($severity)',
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }

  Widget _buildPhotoTimeline(List<AcneRosaceaLog> photos, Color textColor) {
    if (photos.isEmpty) {
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.champagneGold.withValues(alpha: 0.14),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.add_a_photo_outlined,
              color: AppColors.champagneGold.withValues(alpha: 0.55),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No photos yet. Use Quick Log to capture your first reference photo.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: textColor.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 138,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final p = photos[i];
          final isCompare = i == _comparePhotoIndex;
          final isBaseline = i == _baselinePhotoIndex;
          return GestureDetector(
            onTap: () => setState(() => _comparePhotoIndex = i),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCompare
                          ? AppColors.champagneGold
                          : (isBaseline
                                ? AppColors.mutedSage
                                : AppColors.champagneGold.withValues(
                                    alpha: 0.18,
                                  )),
                      width: (isCompare || isBaseline) ? 2.0 : 0.8,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: _localPhotoImage(p.imagePath),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(p.timestamp),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: textColor.withValues(alpha: 0.72),
                  ),
                ),
                Text(
                  isCompare ? 'NOW' : (isBaseline ? 'BEFORE' : ''),
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: isCompare
                        ? AppColors.champagneGold
                        : AppColors.mutedSage,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhotoTips(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.mutedSage.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.mutedSage.withValues(alpha: 0.18),
          width: 0.6,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.tips_and_updates_outlined,
            size: 16,
            color: AppColors.mutedSage,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Best results: same lighting, same angle, no makeup. Morning natural light gives the most consistent baseline.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: textColor.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Insights builders ─────────────────────────────────────────────────
  Widget _buildInsightHeadlineCard(
    AcneRosaceaInsightReport report,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.20),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'AI HEALING SUMMARY',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: AppColors.champagneGold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${report.totalEntries} entries · ${report.photoCount} photos',
                style: TextStyle(
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            report.headline,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: textColor,
              height: 1.3,
            ),
          ),
          if (report.subheadline.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              report.subheadline,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: textColor.withValues(alpha: 0.78),
              ),
            ),
          ],
          if (report.dominantSubtypes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in report.dominantSubtypes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.mutedSage.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.mutedSage.withValues(alpha: 0.28),
                        width: 0.6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _subtypeIcon(s),
                          size: 12,
                          color: AppColors.mutedSage,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _subtypeLabel(s),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.mutedSage,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendCard(MetricTrend t, Color textColor) {
    final IconData icon;
    final Color color;
    switch (t.direction7d) {
      case TrendDirection.improving:
        icon = Icons.trending_down_rounded;
        color = AppColors.mutedSage;
        break;
      case TrendDirection.worsening:
        icon = Icons.trending_up_rounded;
        color = AppColors.softTerracotta;
        break;
      case TrendDirection.steady:
        icon = Icons.trending_flat_rounded;
        color = AppColors.refinedSlate;
        break;
      case TrendDirection.insufficient:
        icon = Icons.help_outline_rounded;
        color = AppColors.refinedSlate;
        break;
    }
    final delta7Pct = t.deltaPct7d.abs().round();
    final hasDelta7 =
        t.direction7d != TrendDirection.insufficient &&
        t.direction7d != TrendDirection.steady;
    final delta7Sign = t.direction7d == TrendDirection.improving ? '↓' : '↑';
    // 30d delta sign / direction derived from the report engine.
    final Color color30 = t.direction30d == TrendDirection.improving
        ? AppColors.mutedSage
        : t.direction30d == TrendDirection.worsening
        ? AppColors.softTerracotta
        : AppColors.refinedSlate;
    final String label30 = t.direction30d == TrendDirection.improving
        ? '30d improving'
        : t.direction30d == TrendDirection.worsening
        ? '30d worsening'
        : t.direction30d == TrendDirection.steady
        ? '30d steady'
        : '30d —';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.24), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.metricLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'now ${t.avgLast7d.toStringAsFixed(1)}/10 · ${t.sampleCount} entries',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: textColor.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Twin delta badges: 7d + 30d.
          Row(
            children: [
              Expanded(
                child: _trendDeltaChip(
                  label: hasDelta7 ? '7d $delta7Sign$delta7Pct%' : '7d steady',
                  color: color,
                  filled: hasDelta7,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _trendDeltaChip(
                  label: label30,
                  color: color30,
                  filled:
                      t.direction30d == TrendDirection.improving ||
                      t.direction30d == TrendDirection.worsening,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t.summary,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: textColor.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendDeltaChip({
    required String label,
    required Color color,
    required bool filled,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled
            ? color.withValues(alpha: 0.14)
            : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: filled ? 0.34 : 0.18),
          width: 0.7,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildTriggerCard(TriggerHypothesis t, Color textColor) {
    final IconData icon;
    switch (t.iconCue) {
      case IconCue.calendar:
        icon = Icons.calendar_month_rounded;
        break;
      case IconCue.product:
        icon = Icons.inventory_2_outlined;
        break;
      case IconCue.stress:
        icon = Icons.psychology_outlined;
        break;
      case IconCue.diet:
        icon = Icons.restaurant_outlined;
        break;
      case IconCue.weather:
        icon = Icons.wb_sunny_outlined;
        break;
      case IconCue.pattern:
        icon = Icons.insights_outlined;
        break;
    }
    final confPct = (t.confidence * 100).clamp(0, 100).round();
    final Color confColor = confPct >= 70
        ? AppColors.mutedSage
        : confPct >= 40
        ? AppColors.champagneGold
        : AppColors.refinedSlate;
    final String confLabel = confPct >= 70
        ? 'HIGH'
        : confPct >= 40
        ? 'MEDIUM'
        : 'LOW';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.champagneGold.withValues(alpha: 0.22),
                      AppColors.champagneGold.withValues(alpha: 0.14),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.champagneGold, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: confColor.withValues(alpha: 0.30),
                    width: 0.6,
                  ),
                ),
                child: Text(
                  '$confLabel · $confPct%',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: confColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Confidence progress rail.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: confPct / 100.0,
              minHeight: 5,
              backgroundColor: confColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(confColor),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t.description,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: textColor.withValues(alpha: 0.80),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard(CompatibilityWarning w, Color textColor) {
    final color = w.severity == WarningSeverity.avoid
        ? AppColors.softTerracotta
        : const Color(0xFFD9A441);
    final label = w.severity == WarningSeverity.avoid ? 'AVOID' : 'CAUTION';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  w.product,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            w.reasoning,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: textColor.withValues(alpha: 0.80),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(ProductRecommendation r, Color textColor) {
    final Color badgeColor;
    final String badgeLabel;
    switch (r.priority) {
      case RecommendationPriority.foundational:
        badgeColor = AppColors.champagneGold;
        badgeLabel = 'FOUNDATIONAL';
        break;
      case RecommendationPriority.supporting:
        badgeColor = AppColors.mutedSage;
        badgeLabel = 'SUPPORTING';
        break;
      case RecommendationPriority.optional:
        badgeColor = AppColors.refinedSlate;
        badgeLabel = 'OPTIONAL';
        break;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.24),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.name,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: badgeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            r.activeIngredient,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: badgeColor,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            r.rationale,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: textColor.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }

  // ── Plan builders ─────────────────────────────────────────────────────
  Widget _buildEmptyPlan(Color textColor) => _buildUnlockCard(
    textColor: textColor,
    icon: Icons.medical_services_outlined,
    eyebrow: 'AI HEALING PLAN',
    title: 'Your personalized treatment plan',
    body:
        'Log severity for any metric — the engine identifies your '
        'dominant subtype, builds a week-by-week protocol, and surfaces '
        'evidence-based products tailored to your skin.',
    unlocks: const [
      'Daily + weekly care protocols',
      'Week-by-week healing stages with "You are here"',
      'Personalized actives + natural alternatives',
    ],
  );

  Widget _buildEmptyInsights(Color textColor) => _buildUnlockCard(
    textColor: textColor,
    icon: Icons.insights_outlined,
    eyebrow: 'AI INSIGHTS',
    title: 'Pattern detection unlocks at 2 entries',
    body:
        'A few quality logs power 7-day & 30-day trend deltas, trigger '
        'hypotheses, and product compatibility analysis against your '
        'active routine.',
    unlocks: const [
      '7-day & 30-day progress trends per metric',
      'Trigger hypotheses with confidence levels',
      'Compatibility warnings for your product stack',
    ],
  );

  /// Premium unlock card used by the Plan + Insights empty states.
  /// Combines a hero icon, eyebrow + headline + body, a progress meter
  /// toward the 2-entry threshold, a bullet of what unlocks, and a CTA.
  Widget _buildUnlockCard({
    required Color textColor,
    required IconData icon,
    required String eyebrow,
    required String title,
    required String body,
    required List<String> unlocks,
  }) {
    final entries = _report?.totalEntries ?? 0;
    const target = 2;
    final progress = (entries / target).clamp(0.0, 1.0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.champagneGold.withValues(alpha: 0.10),
                AppColors.mutedSage.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.champagneGold.withValues(alpha: 0.22),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.refinedSlate.withValues(alpha: 0.04),
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
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.champagneGold.withValues(alpha: 0.18),
                          AppColors.champagneGold.withValues(alpha: 0.14),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.champagneGold.withValues(alpha: 0.28),
                        width: 0.7,
                      ),
                    ),
                    child: Icon(icon, color: AppColors.champagneGold, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow,
                          style: const TextStyle(
                            fontSize: 9.5,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w800,
                            color: AppColors.champagneGold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: textColor,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                body,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: textColor.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 16),
              // Progress meter toward unlock threshold.
              Row(
                children: [
                  const Text(
                    'PROGRESS TO UNLOCK',
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: AppColors.mutedSage,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$entries / $target entries',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: textColor.withValues(alpha: 0.80),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppColors.refinedSlate.withValues(
                    alpha: 0.12,
                  ),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.mutedSage,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (final u in unlocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 14,
                        color: AppColors.mutedSage,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          u,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: textColor.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openQuickLogSheet(),
                  icon: const Icon(Icons.add_chart_rounded, size: 18),
                  label: Text(
                    entries == 0
                        ? 'Log first entry'
                        : 'Log ${target - entries} more to unlock',
                  ),
                  style: MyApp.primaryGoldButton,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHealingSummaryCard(
    AcneRosaceaInsightReport report,
    Color textColor,
  ) {
    final daysTracked = _daysTracked();
    final foundationalCount = report.recommendations
        .where((r) => r.priority == RecommendationPriority.foundational)
        .length;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.12),
            AppColors.mutedSage.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.26),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.champagneGold.withValues(alpha: 0.85),
                      AppColors.champagneGold.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.champagneGold.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI HEALING PLAN',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: AppColors.champagneGold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your personalized protocol',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            report.healingPlanSummary,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: textColor.withValues(alpha: 0.86),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (report.dominantSubtypes.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'FOCUS AREAS',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: AppColors.refinedSlate,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in report.dominantSubtypes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.mutedSage.withValues(alpha: 0.30),
                        width: 0.7,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _subtypeIcon(s),
                          size: 13,
                          color: AppColors.mutedSage,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _subtypeLabel(s),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.mutedSage,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          // Three-stat strip: tracked days · foundational actives · warnings.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.cardBackground.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.14),
                width: 0.7,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _planStat(
                    label: 'Days tracked',
                    value: '$daysTracked',
                    icon: Icons.calendar_today_outlined,
                    color: AppColors.mutedSage,
                    textColor: textColor,
                  ),
                ),
                Container(
                  width: 1,
                  height: 26,
                  color: AppColors.champagneGold.withValues(alpha: 0.18),
                ),
                Expanded(
                  child: _planStat(
                    label: 'Core actives',
                    value: '$foundationalCount',
                    icon: Icons.science_outlined,
                    color: AppColors.champagneGold,
                    textColor: textColor,
                  ),
                ),
                Container(
                  width: 1,
                  height: 26,
                  color: AppColors.champagneGold.withValues(alpha: 0.18),
                ),
                Expanded(
                  child: _planStat(
                    label: 'Warnings',
                    value: '${report.warnings.length}',
                    icon: Icons.warning_amber_rounded,
                    color: report.warnings.isEmpty
                        ? AppColors.refinedSlate
                        : const Color(0xFFD37B4F),
                    textColor: textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Single column in the AI Healing Plan stat strip.
  Widget _planStat({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color textColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 8.5,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: textColor.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  /// Distinct calendar days that contain at least one log entry — used
  /// to give the AI Healing Plan a "days tracked" stat.
  int _daysTracked() {
    final days = <String>{};
    for (final list in _logs.values) {
      for (final e in list) {
        days.add('${e.timestamp.year}-${e.timestamp.month}-${e.timestamp.day}');
      }
    }
    return days.length;
  }

  Widget _buildActionList({
    required List<String> actions,
    required Color accent,
    required Color textColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.18), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < actions.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.32),
                      width: 0.8,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    actions[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: textColor.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
            if (i < actions.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildSubtypePlanCard(SubtypePlan plan, Color textColor) {
    const subtypeColor = AppColors.mutedSage;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.22),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // In-card subtype header (icon chip + label + protocol eyebrow).
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      subtypeColor.withValues(alpha: 0.18),
                      subtypeColor.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: subtypeColor.withValues(alpha: 0.32),
                    width: 0.7,
                  ),
                ),
                child: Icon(
                  _subtypeIcon(plan.subtype),
                  size: 18,
                  color: subtypeColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CARE PROTOCOL',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: subtypeColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.subtypeLabel,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            plan.overview,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: textColor.withValues(alpha: 0.80),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(
                Icons.calendar_view_week_rounded,
                size: 13,
                color: AppColors.champagneGold,
              ),
              SizedBox(width: 5),
              Text(
                'WEEK-BY-WEEK PROTOCOL',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: AppColors.champagneGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < plan.stages.length; i++) ...[
            _buildHealingStageRow(plan.stages[i], i + 1, textColor),
            const SizedBox(height: 10),
          ],
          if (plan.recommendations.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(
                  Icons.science_outlined,
                  size: 13,
                  color: AppColors.champagneGold,
                ),
                SizedBox(width: 5),
                Text(
                  'KEY ACTIVES',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: AppColors.champagneGold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final r in plan.recommendations) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppColors.mutedSage,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: textColor.withValues(alpha: 0.82),
                          ),
                          children: [
                            TextSpan(
                              text: '${r.name} — ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(text: r.rationale),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHealingStageRow(
    HealingStage s,
    int stepNumber,
    Color textColor,
  ) {
    final isCurrent = s.isCurrent;
    final accent = isCurrent
        ? AppColors.champagneGold
        : AppColors.refinedSlate.withValues(alpha: 0.55);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left accent rail — thicker / gold for the current stage.
          Container(
            width: isCurrent ? 4 : 2,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppColors.champagneGold
                  : AppColors.refinedSlate.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppColors.champagneGold.withValues(alpha: 0.07)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCurrent
                      ? AppColors.champagneGold.withValues(alpha: 0.32)
                      : AppColors.refinedSlate.withValues(alpha: 0.18),
                  width: 0.8,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step number badge.
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withValues(alpha: 0.34),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '$stepNumber',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                s.weekRange,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: accent,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                s.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.champagneGold,
                                      AppColors.champagneGold,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.champagneGold.withValues(
                                        alpha: 0.30,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.my_location_rounded,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'YOU ARE HERE',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.description,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: textColor.withValues(alpha: 0.74),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyMiniCard(String message, Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.14),
          width: 0.8,
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: textColor.withValues(alpha: 0.65),
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────
  Color _severityColor(int value) {
    if (value < 0) return AppColors.refinedSlate;
    if (value <= 2) return AppColors.mutedSage; // calm green
    if (value <= 5) return const Color(0xFFD9A441); // amber
    if (value <= 7) return const Color(0xFFD37B4F); // orange
    return AppColors.softTerracotta; // muted red
  }

  String _severityLabel(int value) {
    if (value <= 1) return 'Clear';
    if (value <= 3) return 'Mild';
    if (value <= 5) return 'Moderate';
    if (value <= 7) return 'Marked';
    return 'Severe';
  }

  /// Per-metric clinical "absence" phrasing used in the Clinical Metrics
  /// panel when a tile has either no log yet or a latest value of 0–1
  /// (i.e. the AI did not detect meaningful activity). Keeps the empty
  /// state informative + clinical rather than blank "Not logged yet".
  String _absencePhrase(String metricKey) {
    switch (metricKey) {
      case 'acneSeverity':
        return 'No active acne detected';
      case 'cysticAcneSeverity':
        return 'No cystic lesions detected';
      case 'hormonalAcneSeverity':
        return 'No hormonal acne pattern detected';
      case 'rosaceaSeverity':
        return 'No rosacea signs detected';
      case 'rosaceaFlushing':
        return 'No flushing episodes detected';
      case 'visibleBloodVessels':
        return 'No visible telangiectasias detected';
      case 'skinSensitivity':
        return 'No sensitivity signs detected';
      default:
        return 'No findings detected';
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Color _severityColorFromBand(SeverityBand band) {
    switch (band) {
      case SeverityBand.clear:
        return AppColors.mutedSage;
      case SeverityBand.mild:
        return const Color(0xFFD9A441);
      case SeverityBand.moderate:
        return const Color(0xFFD37B4F);
      case SeverityBand.marked:
        return AppColors.softTerracotta;
      case SeverityBand.severe:
        return const Color(0xFFA63A40);
    }
  }

  String _bandLabel(SeverityBand band) {
    switch (band) {
      case SeverityBand.clear:
        return 'CLEAR · STABLE';
      case SeverityBand.mild:
        return 'MILD · MONITOR';
      case SeverityBand.moderate:
        return 'MODERATE · ACTIVE TREATMENT';
      case SeverityBand.marked:
        return 'MARKED · ACTION NEEDED';
      case SeverityBand.severe:
        return 'SEVERE · CONSULT DERM';
    }
  }

  IconData _subtypeIcon(AcneRosaceaSubtype s) {
    switch (s) {
      case AcneRosaceaSubtype.acne:
        return Icons.face_retouching_natural_outlined;
      case AcneRosaceaSubtype.cystic:
        return Icons.bubble_chart_outlined;
      case AcneRosaceaSubtype.hormonal:
        return Icons.calendar_month_outlined;
      case AcneRosaceaSubtype.rosacea:
        return Icons.local_florist_outlined;
      case AcneRosaceaSubtype.flushing:
        return Icons.thermostat_outlined;
      case AcneRosaceaSubtype.visibleVessels:
        return Icons.account_tree_outlined;
      case AcneRosaceaSubtype.sensitivity:
        return Icons.flash_on_outlined;
    }
  }

  String _subtypeLabel(AcneRosaceaSubtype s) {
    switch (s) {
      case AcneRosaceaSubtype.acne:
        return 'Acne';
      case AcneRosaceaSubtype.cystic:
        return 'Cystic';
      case AcneRosaceaSubtype.hormonal:
        return 'Hormonal';
      case AcneRosaceaSubtype.rosacea:
        return 'Rosacea';
      case AcneRosaceaSubtype.flushing:
        return 'Flushing';
      case AcneRosaceaSubtype.visibleVessels:
        return 'Vessels';
      case AcneRosaceaSubtype.sensitivity:
        return 'Sensitivity';
    }
  }
}

class _GuidanceTile {
  final IconData icon;
  final String title;
  final String eyebrow;
  final List<String> bullets;

  const _GuidanceTile({
    required this.icon,
    required this.title,
    required this.eyebrow,
    required this.bullets,
  });
}

// ─── Quick Log bottom sheet ───────────────────────────────────────────────

class _QuickLogResult {
  final String metricKey;
  final int value;
  final String note;
  final String imagePath;

  const _QuickLogResult({
    required this.metricKey,
    required this.value,
    required this.note,
    required this.imagePath,
  });
}

class _QuickLogSheet extends StatefulWidget {
  final String? presetMetricKey;
  final List<String> recentMetricKeys;

  /// Most-recent log per metric key. Used to pre-fill the slider with
  /// the latest reading (which may be an AI-detected value) and to show
  /// an "AI SUGGESTED" badge when that latest log came from the photo
  /// analyzer.
  final Map<String, AcneRosaceaLog> latestLogs;

  const _QuickLogSheet({
    this.presetMetricKey,
    required this.recentMetricKeys,
    this.latestLogs = const {},
  });

  @override
  State<_QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<_QuickLogSheet> {
  late String _metricKey;
  int _value = 4;
  String _imagePath = '';
  final TextEditingController _noteCtrl = TextEditingController();
  bool _saving = false;

  /// True while the analyzer is running against the user's latest scan
  /// to re-determine severity for an AI-sourced metric.
  bool _reanalyzing = false;

  /// True when the most recent log for the current metric was written
  /// by the AI photo analyzer (note starts with `'AI photo analysis'`).
  /// AI-sourced metrics surface as a read-only card with a Re-analyze
  /// button; manual metrics keep the slider.
  bool get _isAiSuggested {
    final seed = widget.latestLogs[_metricKey];
    return seed != null && seed.note.startsWith('AI photo analysis');
  }

  @override
  void initState() {
    super.initState();
    _metricKey =
        widget.presetMetricKey ??
        (widget.recentMetricKeys.isNotEmpty
            ? widget.recentMetricKeys.first
            : SkinMetricRegistry.acneAndRosacea.first.key);
    // Seed slider from the most recent log of the chosen metric so the
    // AI-detected value (or last manual value) becomes the default.
    final seed = widget.latestLogs[_metricKey];
    if (seed != null) _value = seed.value;
  }

  /// Pulls the user's most recent scan photo, runs the on-device photo
  /// analyzer, and updates [_value] with the AI-determined severity for
  /// the currently selected metric. Severity is always AI-driven \u2014
  /// the user does not drag a slider.
  Future<void> _reanalyzeWithAi() async {
    if (_reanalyzing) return;
    setState(() => _reanalyzing = true);
    try {
      final scans = await AppPrefs.getScanEntries();
      final withPhoto =
          scans.where((s) => (s.imagePath ?? '').trim().isNotEmpty).toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (withPhoto.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No scan photo available. Capture a scan to let AI '
              'determine severity.',
            ),
          ),
        );
        return;
      }
      final latest = withPhoto.first;
      PhotoFeatures features;
      Uint8List? imageBytes;
      try {
        imageBytes = await XFile(latest.imagePath!).readAsBytes();
        features = PhotoFeatureExtractor.extract(imageBytes);
      } catch (_) {
        features = PhotoFeatures.neutral();
      }
      final baseInput = PhotoAnalysisInput.fromFeatures(
        imagePath: latest.imagePath!,
        capturedAt: latest.timestamp,
        region: FacialRegion.fullFace,
        features: features,
        cycleRelatedFlare: false,
        adultOnset: false,
      );
      final aug = await SkinAnalysisRunner.augment(
        baseInput: baseInput,
        imageBytes: imageBytes,
      );
      final report = AcneRosaceaPhotoAnalyzer.analyze(
        input: aug.input,
        baselineSnapshot: null,
        history: const {},
        confidence: SkinAnalysisRunner.resolveConfidence(
          featureConfidence: features.confidence,
          modelConfidence: aug.modelConfidence,
        ),
        features: features,
      );
      final detected = report.detected[_metricKey];
      if (!mounted) return;
      setState(() => _value = detected);
      final stack = <String>[
        if (aug.meshUsed) 'ML Kit',
        if (aug.yoloUsed) 'YOLOv8',
        if (aug.efficientNetUsed) 'EffNet-B0',
        if (aug.aiInferenceUsed && !aug.yoloUsed && !aug.efficientNetUsed)
          'TFLite',
      ];
      final engineLabel = stack.isEmpty
          ? 'Calibrated analysis'
          : '${stack.join(" + ")} AI';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.mutedSage,
          duration: const Duration(seconds: 2),
          content: Text(
            '$engineLabel → $detected · ${_severityLabel(detected)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reanalyzing = false);
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: source, imageQuality: 85);
      if (image == null || !mounted) return;

      // Mandatory crop: progress photos must be cropped before they are
      // stored or shown, identical to the AI Analysis flow.
      final rawBytes = await image.readAsBytes();
      if (!mounted) return;
      final cropped = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ImageCropDialog(imageBytes: rawBytes),
      );
      if (!mounted) return;
      if (cropped == null) {
        // User cancelled the cropper — keep any prior selection cleared.
        setState(() => _imagePath = '');
        return;
      }

      final stored = await _persistCroppedImage(cropped);
      if (!mounted) return;
      setState(() => _imagePath = stored);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not access camera/gallery.')),
      );
    }
  }

  /// Persists cropped bytes to a displayable reference: a data URI on web
  /// (consumed by `Image.network`) or a temp file path on native (consumed
  /// by `Image.file`).
  Future<String> _persistCroppedImage(Uint8List bytes) async {
    if (kIsWeb) {
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }
    final dir = Directory.systemTemp;
    final file = File(
      '${dir.path}/quicklog_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _showPhotoSourceSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.refinedSlate.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.champagneGold,
                          AppColors.champagneGold,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ATTACH PROGRESS PHOTO',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w900,
                            color: AppColors.champagneGold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Track visible healing over time',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.refinedSlate,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Capture guidelines (consistent with AI Analysis sheet)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.mutedSage.withValues(alpha: 0.07),
                      AppColors.champagneGold.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.mutedSage.withValues(alpha: 0.22),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: AppColors.mutedSage,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'CAPTURE GUIDELINES',
                          style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w900,
                            color: AppColors.mutedSage,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _quickTip(
                      Icons.wb_sunny_outlined,
                      'Bright, even, indirect daylight.',
                    ),
                    const SizedBox(height: 5),
                    _quickTip(
                      Icons.face_retouching_natural_outlined,
                      'Clean skin, no makeup, neutral expression.',
                    ),
                    const SizedBox(height: 5),
                    _quickTip(
                      Icons.straighten_outlined,
                      'Match angle + distance to your baseline photo.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickPhoto(ImageSource.camera);
                  },
                  icon: const Icon(Icons.photo_camera_rounded, size: 19),
                  label: const Text(
                    'Take photo with camera',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                  style: MyApp.primaryGoldButton,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _pickPhoto(ImageSource.gallery);
                  },
                  icon: const Icon(
                    Icons.photo_library_outlined,
                    size: 18,
                    color: AppColors.mutedSage,
                  ),
                  label: const Text(
                    'Choose from gallery',
                    style: TextStyle(
                      color: AppColors.mutedSage,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.mutedSage.withValues(alpha: 0.50),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (_imagePath.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _imagePath = '');
                    },
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 17,
                      color: AppColors.softTerracotta,
                    ),
                    label: const Text(
                      'Remove photo',
                      style: TextStyle(
                        color: AppColors.softTerracotta,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickTip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.mutedSage),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.refinedSlate.withValues(alpha: 0.80),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Color _severityColor(int v) {
    if (v <= 2) return AppColors.mutedSage;
    if (v <= 5) return const Color(0xFFD9A441);
    if (v <= 7) return const Color(0xFFD37B4F);
    return AppColors.softTerracotta;
  }

  String _severityLabel(int v) {
    if (v <= 1) return 'Clear';
    if (v <= 3) return 'Mild';
    if (v <= 5) return 'Moderate';
    if (v <= 7) return 'Marked';
    return 'Severe';
  }

  /// Read-only severity card shown in place of the slider when the
  /// metric's most recent log came from the AI photo analyzer. Surfaces
  /// the AI value front-and-center with an explicit "Edit" button that
  /// reveals the manual slider, so the AI flow is never forced through
  /// a manual drag.
  Widget _readOnlySeverityCard(Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.08),
            AppColors.champagneGold.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.32),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$_value',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI value: ${_severityLabel(_value)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.refinedSlate,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Severity is determined by AI from your latest scan. '
                  'Tap re-analyze to refresh.',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    color: AppColors.refinedSlate.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: _reanalyzing ? null : _reanalyzeWithAi,
            icon: _reanalyzing
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 14),
            label: Text(_reanalyzing ? 'Analyzing…' : 'Re-analyze'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.champagneGold,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const textColor = AppColors.refinedSlate;
    final color = _severityColor(_value);
    final spec = SkinMetricRegistry.byKey(_metricKey);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.refinedSlate.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Quick Log',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Capture symptom severity, photo, and notes in one pass.',
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.60),
                  ),
                ),
                const SizedBox(height: 16),
                // Metric picker
                const Text(
                  'METRIC',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: AppColors.champagneGold,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _metricKey,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.canvas,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.champagneGold.withValues(alpha: 0.20),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.champagneGold.withValues(alpha: 0.20),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.champagneGold.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  items: [
                    for (final s in SkinMetricRegistry.acneAndRosacea)
                      DropdownMenuItem(
                        value: s.key,
                        child: Row(
                          children: [
                            Icon(
                              s.icon,
                              size: 16,
                              color: AppColors.champagneGold,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.shortName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _metricKey = v;
                      // Re-seed from the latest log of the newly chosen
                      // metric (AI-detected or otherwise).
                      final seed = widget.latestLogs[v];
                      if (seed != null) _value = seed.value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Severity slider
                Row(
                  children: [
                    const Text(
                      'SEVERITY',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: AppColors.champagneGold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_isAiSuggested)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.champagneGold.withValues(alpha: 0.18),
                              AppColors.champagneGold.withValues(alpha: 0.18),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.42,
                            ),
                            width: 0.6,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 9,
                              color: AppColors.champagneGold,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'AI DETERMINED',
                              style: TextStyle(
                                fontSize: 8.5,
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.w900,
                                color: AppColors.champagneGold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_value · ${_severityLabel(_value)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: color,
                    inactiveTrackColor: color.withValues(alpha: 0.18),
                    thumbColor: color,
                    overlayColor: color.withValues(alpha: 0.18),
                  ),
                  child: _isAiSuggested
                      ? _readOnlySeverityCard(color)
                      : Slider(
                          value: _value.toDouble(),
                          min: 0,
                          max: 10,
                          divisions: 10,
                          label: '$_value',
                          onChanged: (v) => setState(() => _value = v.round()),
                        ),
                ),
                const SizedBox(height: 8),
                // Photo capture
                GestureDetector(
                  onTap: _showPhotoSourceSheet,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.champagneGold.withValues(alpha: 0.22),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _imagePath.isEmpty
                              ? const Icon(
                                  Icons.add_a_photo_outlined,
                                  color: AppColors.champagneGold,
                                  size: 20,
                                )
                              : (kIsWeb
                                    ? Image.network(
                                        _imagePath,
                                        fit: BoxFit.cover,
                                      )
                                    : Image.file(
                                        File(_imagePath),
                                        fit: BoxFit.cover,
                                      )),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _imagePath.isEmpty
                                    ? 'Attach photo (optional)'
                                    : 'Photo attached',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _imagePath.isEmpty
                                    ? 'Track visible healing over time'
                                    : 'Tap to change or remove',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textColor.withValues(alpha: 0.60),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: textColor.withValues(alpha: 0.40),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Note
                const Text(
                  'NOTE',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: AppColors.champagneGold,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 13, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Trigger? Product? Time of day?',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: textColor.withValues(alpha: 0.40),
                    ),
                    filled: true,
                    fillColor: AppColors.canvas,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.champagneGold.withValues(alpha: 0.20),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.champagneGold.withValues(alpha: 0.20),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.champagneGold.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() => _saving = true);
                            Navigator.pop(
                              context,
                              _QuickLogResult(
                                metricKey: _metricKey,
                                value: _value,
                                note: _noteCtrl.text.trim(),
                                imagePath: _imagePath,
                              ),
                            );
                          },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      spec == null
                          ? 'Save entry'
                          : 'Save ${spec.shortName} · level $_value',
                    ),
                    style: MyApp.primaryGoldButton,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'AI guidance — not medical advice.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: textColor.withValues(alpha: 0.50),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  AI Photo Analysis — Input Sheet + Result Screen
// ════════════════════════════════════════════════════════════════════

/// Bottom sheet that captures the analysis photo and a small set of
/// user-verified severity sliders, returning a [PhotoAnalysisInput].
/// Result of the capture sheet: the picked photo path + light meta the
/// user picks in one tap each (focus region, cycle-related, adult-onset).
/// Severity values are auto-derived later from the photo via
/// [PhotoFeatureExtractor], so the user never has to touch a slider.
class _AnalysisCapture {
  final String imagePath;
  final Uint8List? imageBytes;
  final FacialRegion region;
  final bool cycleRelated;
  final bool adultOnset;
  const _AnalysisCapture({
    required this.imagePath,
    this.imageBytes,
    required this.region,
    required this.cycleRelated,
    required this.adultOnset,
  });
}

class _PhotoAnalysisInputSheet extends StatefulWidget {
  const _PhotoAnalysisInputSheet();

  @override
  State<_PhotoAnalysisInputSheet> createState() =>
      _PhotoAnalysisInputSheetState();
}

class _PhotoAnalysisInputSheetState extends State<_PhotoAnalysisInputSheet> {
  String _imagePath = '';

  /// Cropped JPEG bytes from the mandatory crop step. The "Run AI Analysis"
  /// button stays disabled until this is non-null, and these exact bytes are
  /// what the analyzer receives — never the uncropped original.
  Uint8List? _croppedBytes;
  // Region is REQUIRED. We keep a default value for downstream wiring,
  // but track `_regionPicked` separately so the user has to explicitly
  // confirm a focus area before "Run AI analysis" unlocks.
  FacialRegion _region = FacialRegion.fullFace;
  bool _regionPicked = false;
  bool _cycleRelated = false;
  bool _adultOnset = false;
  bool _analyzing = false;

  Future<void> _pickPhoto(ImageSource src) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: src, imageQuality: 88);
      if (picked == null || !mounted) return;

      // Mandatory crop: the analyzer must only ever see the cropped patch.
      final rawBytes = await picked.readAsBytes();
      if (!mounted) return;
      final cropped = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ImageCropDialog(imageBytes: rawBytes),
      );
      if (!mounted) return;
      if (cropped == null) {
        // User cancelled the cropper — clear any prior selection so the
        // "Run AI Analysis" button stays disabled.
        setState(() {
          _imagePath = '';
          _croppedBytes = null;
        });
        return;
      }

      final storedReference = await _persistCroppedImage(cropped);
      if (!mounted) return;
      setState(() {
        _croppedBytes = cropped;
        _imagePath = storedReference;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not access camera/gallery.')),
      );
    }
  }

  /// Persists the cropped bytes to a displayable reference: a data URI on the
  /// web (consumed by `Image.network`) or a temp file path on native (consumed
  /// by `Image.file`). The analyzer uses the in-memory bytes directly.
  Future<String> _persistCroppedImage(Uint8List bytes) async {
    if (kIsWeb) {
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }
    final dir = Directory.systemTemp;
    final file = File(
      '${dir.path}/acne_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    const textColor = AppColors.refinedSlate;
    final hasPhoto = _imagePath.isNotEmpty && _croppedBytes != null;
    final canRun = hasPhoto && _regionPicked && !_analyzing;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.refinedSlate.withValues(alpha: 0.30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ── Clinical header ──
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.champagneGold,
                          AppColors.champagneGold,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.25,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI SKIN ANALYSIS',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w900,
                            color: AppColors.champagneGold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Capture · Region · Review',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: textColor,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // ── 2-step progress indicator ──
              _stepProgress(hasPhoto, _regionPicked, textColor),
              const SizedBox(height: 16),

              // ── STEP 1: Capture guidelines (always visible) ──
              _captureGuidelinesCard(),
              const SizedBox(height: 12),

              // ── Photo preview / capture buttons ──
              _photoPanel(textColor, hasPhoto),
              const SizedBox(height: 18),

              // ── STEP 2: PRIMARY REGION (REQUIRED) ──
              _sectionEyebrowRequired(
                'PRIMARY REGION',
                satisfied: _regionPicked,
              ),
              const SizedBox(height: 4),
              Text(
                _regionPicked
                    ? 'AI will focus its analysis on this area.'
                    : 'Pick the area you\'re tracking — this guides the AI.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: textColor.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 10),
              _regionGrid(textColor),
              const SizedBox(height: 16),

              // ── Context toggles (optional) ──
              _sectionEyebrow('CONTEXT  ·  OPTIONAL'),
              const SizedBox(height: 2),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: AppColors.champagneGold,
                value: _cycleRelated,
                onChanged: (v) => setState(() => _cycleRelated = v),
                title: const Text(
                  'Flares with menstrual cycle',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: AppColors.champagneGold,
                value: _adultOnset,
                onChanged: (v) => setState(() => _adultOnset = v),
                title: const Text(
                  'Adult-onset / persists past mid-20s',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Run AI CTA ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: !canRun
                      ? null
                      : () {
                          setState(() => _analyzing = true);
                          Navigator.pop(
                            context,
                            _AnalysisCapture(
                              imagePath: _imagePath,
                              imageBytes: _croppedBytes,
                              region: _region,
                              cycleRelated: _cycleRelated,
                              adultOnset: _adultOnset,
                            ),
                          );
                        },
                  icon: _analyzing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 19),
                  label: Text(
                    _analyzing ? 'Analyzing…' : 'Run AI Analysis',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                  style: MyApp.primaryGoldButton,
                ),
              ),
              if (!canRun && !_analyzing) ...[
                const SizedBox(height: 8),
                Text(
                  !hasPhoto
                      ? 'Add a photo above to continue.'
                      : 'Select the primary region you want analyzed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.refinedSlate.withValues(alpha: 0.85),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'AI-assisted analysis — not a substitute for professional '
                'medical advice. All AI-detected values are editable '
                'before saving.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: textColor.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step progress indicator (1: Photo · 2: Region · Review) ──
  Widget _stepProgress(bool photoDone, bool regionDone, Color textColor) {
    Widget step(int index, String label, bool done, bool active) {
      final accent = done
          ? AppColors.mutedSage
          : (active ? AppColors.champagneGold : AppColors.refinedSlate);
      return Expanded(
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: done ? 0.20 : 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: accent.withValues(alpha: done ? 0.65 : 0.35),
                  width: 1,
                ),
              ),
              child: done
                  ? Icon(Icons.check_rounded, size: 13, color: accent)
                  : Text(
                      '$index',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        step(1, 'PHOTO', photoDone, !photoDone),
        Container(
          width: 14,
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: AppColors.refinedSlate.withValues(alpha: 0.30),
        ),
        step(2, 'REGION', regionDone, photoDone && !regionDone),
        Container(
          width: 14,
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: AppColors.refinedSlate.withValues(alpha: 0.30),
        ),
        step(3, 'RUN AI', false, photoDone && regionDone),
      ],
    );
  }

  // ── Always-visible capture guidelines ──
  Widget _captureGuidelinesCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.mutedSage.withValues(alpha: 0.07),
            AppColors.champagneGold.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.mutedSage.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: AppColors.mutedSage,
              ),
              SizedBox(width: 6),
              Text(
                'CAPTURE GUIDELINES',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w900,
                  color: AppColors.mutedSage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _captureTip(
            Icons.wb_sunny_outlined,
            'Bright, even, indirect daylight — no harsh shadows.',
          ),
          const SizedBox(height: 5),
          _captureTip(
            Icons.face_retouching_natural_outlined,
            'Clean skin, no makeup, neutral expression.',
          ),
          const SizedBox(height: 5),
          _captureTip(
            Icons.straighten_outlined,
            'Match angle + distance to your baseline photo.',
          ),
          const SizedBox(height: 5),
          _captureTip(
            Icons.center_focus_strong_outlined,
            'Hold steady · focus on the region you\'ll select below.',
          ),
        ],
      ),
    );
  }

  // ── Required-section eyebrow (rose accent + REQUIRED badge) ──
  Widget _sectionEyebrowRequired(String text, {required bool satisfied}) {
    final accent = satisfied ? AppColors.mutedSage : AppColors.champagneGold;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accent.withValues(alpha: 0.40),
                width: 0.6,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  satisfied
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 10,
                  color: accent,
                ),
                const SizedBox(width: 3),
                Text(
                  satisfied ? 'SELECTED' : 'REQUIRED',
                  style: TextStyle(
                    fontSize: 8.5,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Prominent region grid (2-column tappable tiles) ──
  Widget _regionGrid(Color textColor) {
    const regions = FacialRegion.values;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        const spacing = 8.0;
        final tileW = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final r in regions)
              SizedBox(width: tileW, child: _regionTile(r, textColor)),
          ],
        );
      },
    );
  }

  Widget _regionTile(FacialRegion r, Color textColor) {
    final selected = _regionPicked && _region == r;
    final accent = selected ? AppColors.champagneGold : AppColors.refinedSlate;
    return InkWell(
      onTap: () => setState(() {
        _region = r;
        _regionPicked = true;
      }),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    AppColors.champagneGold.withValues(alpha: 0.14),
                    AppColors.champagneGold.withValues(alpha: 0.10),
                  ],
                )
              : null,
          color: selected ? null : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent.withValues(alpha: selected ? 0.55 : 0.22),
            width: selected ? 1.2 : 0.8,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.champagneGold.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                PhotoAnalysisUi.regionIcon(r),
                size: 17,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                PhotoAnalysisUi.regionLabel(r),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: selected ? AppColors.champagneGold : textColor,
                  height: 1.2,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: AppColors.champagneGold,
              ),
          ],
        ),
      ),
    );
  }

  Widget _photoPanel(Color textColor, bool hasPhoto) {
    if (!hasPhoto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _pickPhoto(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_rounded, size: 19),
              label: const Text(
                'Take photo with camera',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
              style: MyApp.primaryGoldButton,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(
                Icons.photo_library_outlined,
                size: 18,
                color: AppColors.mutedSage,
              ),
              label: const Text(
                'Choose from gallery',
                style: TextStyle(
                  color: AppColors.mutedSage,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: AppColors.mutedSage.withValues(alpha: 0.50),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }
    // Photo captured — show preview.
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.30),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 72,
              child: _localPhotoImagePreview(_imagePath),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AppColors.mutedSage,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Photo ready for analysis',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppColors.mutedSage,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'AI will auto-detect acne type, rosacea pattern, '
                  'and all 7 severity metrics from this image.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: textColor.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Retake',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.mutedSage),
            onPressed: () => setState(() {
              _imagePath = '';
              _croppedBytes = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _captureTip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.mutedSage),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.refinedSlate.withValues(alpha: 0.80),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionEyebrow(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9.5,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w800,
          color: AppColors.mutedSage,
        ),
      ),
    );
  }

  Widget _localPhotoImagePreview(String path) {
    if (path.isEmpty) {
      return Container(color: AppColors.refinedSlate.withValues(alpha: 0.15));
    }
    if (kIsWeb) return Image.network(path, fit: BoxFit.cover);
    return Image.file(File(path), fit: BoxFit.cover);
  }
}

/// Full-screen result view rendered after the analyser runs. Shows the
/// captured photo, detected acne/rosacea pattern, severity index, focus
/// region, personalised insights, ranked procedure recommendations with
/// pros/cons/timeline, product cues, and (when present) a baseline
/// comparison block.
class _PhotoAnalysisResultScreen extends StatefulWidget {
  final PhotoAnalysisResult result;
  final ModelInfo modelInfo;
  final double? modelConfidence;
  final Set<String> modelOwnedMetrics;
  final bool meshUsed;
  final double? symmetryScore;
  final double? faceCoverage;
  final bool yoloUsed;
  final List<Detection> detections;
  final bool efficientNetUsed;
  final SkinQualityScores? qualityScores;
  const _PhotoAnalysisResultScreen({
    required this.result,
    this.modelInfo = ModelInfo.fallback,
    this.modelConfidence,
    this.modelOwnedMetrics = const {},
    this.meshUsed = false,
    this.symmetryScore,
    this.faceCoverage,
    this.yoloUsed = false,
    this.detections = const [],
    this.efficientNetUsed = false,
    this.qualityScores,
  });

  @override
  State<_PhotoAnalysisResultScreen> createState() =>
      _PhotoAnalysisResultScreenState();
}

class _PhotoAnalysisResultScreenState
    extends State<_PhotoAnalysisResultScreen> {
  // Editable per-metric values; initialised from the AI-detected map.
  late Map<String, int> _values;
  // Tracks which metric tiles the user has manually adjusted.
  final Set<String> _edited = {};
  bool _saving = false;

  PhotoAnalysisResult get result => widget.result;

  @override
  void initState() {
    super.initState();
    // Seed every canonical key (zero-default) before overlaying the
    // engine's detected values so the editable panel + Save loop
    // always have all 7 metrics present.
    _values = {
      for (final s in SkinMetricRegistry.acneAndRosacea) s.key: 0,
      ...result.detected.values,
    };
  }

  Color get _severityColor {
    final s = result.severityIndex;
    if (s < 3.0) return AppColors.mutedSage;
    if (s < 5.0) return const Color(0xFFD9A441);
    if (s < 7.0) return const Color(0xFFD37B4F);
    return AppColors.softTerracotta;
  }

  Color _valueColor(int v) {
    if (v <= 2) return AppColors.mutedSage;
    if (v <= 5) return const Color(0xFFD9A441);
    if (v <= 7) return const Color(0xFFD37B4F);
    return AppColors.softTerracotta;
  }

  String _dominantMetricKey() {
    var bestKey = 'acneSeverity';
    var bestVal = -1;
    _values.forEach((k, v) {
      if (v > bestVal) {
        bestVal = v;
        bestKey = k;
      }
    });
    return bestKey;
  }

  Future<void> _saveToTracker() async {
    if (_saving) return;
    setState(() => _saving = true);
    final dominant = _dominantMetricKey();
    final regionLabel = PhotoAnalysisUi.regionLabel(result.input.region);
    try {
      // Persist ALL 7 canonical metrics in a single batch so the Track
      // tab reflects the full AI read. We iterate
      // `SkinMetricRegistry.acneAndRosacea` (not `_values.entries`) to
      // defensively guarantee every key gets a log even if the engine
      // map is ever missing one. The photo + region tag attach to the
      // dominant key; non-dominant keys log without a photo.
      final allZero = _values.values.every((v) => v <= 0);
      for (final spec in SkinMetricRegistry.acneAndRosacea) {
        final key = spec.key;
        final value = _values[key] ?? 0;
        final isDominant = key == dominant;
        final isEdited = _edited.contains(key);
        final base = (allZero && isDominant)
            ? 'AI photo analysis · no signs detected'
            : (isEdited ? 'AI photo analysis (adjusted)' : 'AI photo analysis');
        await AppPrefs.addAcneRosaceaLog(
          key,
          value,
          note: isDominant ? '$base · $regionLabel' : base,
          imagePath: isDominant ? result.input.imagePath : '',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.mutedSage,
          content: Text(
            allZero
                ? 'Clear result saved across all 7 metrics.'
                : 'All 7 AI-detected metrics saved to tracker.',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not save metrics.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    const textColor = AppColors.refinedSlate;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        foregroundColor: textColor,
        elevation: 0,
        title: const Text(
          'AI Analysis Result',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _saveToTracker,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_circle_rounded, size: 18),
            label: Text(
              _saving
                  ? 'Saving…'
                  : (result.isClear
                        ? 'Save clear result to tracker'
                        : 'Save AI-detected metrics to tracker'),
            ),
            style: MyApp.primaryGoldButton,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _engineBadge(textColor),
          const SizedBox(height: 10),
          _heroCard(textColor),
          const SizedBox(height: 16),
          _detectionGrid(textColor),
          const SizedBox(height: 18),
          // ── AI-detected metrics (editable) ──
          _sectionHeader(
            Icons.auto_awesome_rounded,
            'AI-Detected Severity Metrics',
          ),
          const SizedBox(height: 4),
          Text(
            result.isClear
                ? 'AI found minimal activity — most metrics start at 0. '
                      'Adjust any tile if you notice signs the AI missed.'
                : 'Auto-detected from your photo. Tap and drag any slider to '
                      'override before saving — your edits take priority.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: textColor.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 10),
          _metricsPanel(textColor),
          const SizedBox(height: 18),
          if (result.comparison != null) ...[
            _comparisonCard(result.comparison!, textColor),
            const SizedBox(height: 16),
          ],
          _sectionHeader(
            Icons.psychology_alt_rounded,
            'Personalized Skin Insights',
          ),
          const SizedBox(height: 10),
          for (final ins in result.insights) ...[
            _insightCard(ins, textColor),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          _sectionHeader(
            Icons.medical_services_outlined,
            'Procedure Recommendations',
          ),
          const SizedBox(height: 4),
          Text(
            'Ranked by suitability for your detected pattern. Each card '
            'lists honest pros, cons, expected sessions, and timeline so '
            'you can have an informed conversation with a provider.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: textColor.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 10),
          for (final p in result.procedures) ...[
            _procedureCard(p, textColor),
            const SizedBox(height: 10),
          ],
          if (result.productCues.isNotEmpty) ...[
            const SizedBox(height: 6),
            _sectionHeader(Icons.science_outlined, 'Suggested Routine Cues'),
            const SizedBox(height: 10),
            _productCuesCard(textColor),
          ],
          const SizedBox(height: 18),
          _disclaimer(textColor),
        ],
      ),
    );
  }

  // ── Editable metrics panel ──────────────────────────────────────
  Widget _metricsPanel(Color textColor) {
    // Build display order matching SkinMetricRegistry.acneAndRosacea so
    // the result mirrors the Track tab layout exactly.
    final specs = SkinMetricRegistry.acneAndRosacea
        .where((s) => result.detected.values.containsKey(s.key))
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          for (final spec in specs) _metricTile(spec, textColor),
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.refinedSlate.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 12,
                  color: textColor.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'AI suggestions can be adjusted. Tap "Save" below to '
                    'write all values to the Track tab in one batch.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                      color: textColor.withValues(alpha: 0.62),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(SkinMetricSpec spec, Color textColor) {
    final value = _values[spec.key] ?? 0;
    final suggested = result.detected[spec.key];
    final edited = _edited.contains(spec.key);
    final color = _valueColor(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  spec.clinicalName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
              if (!edited)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.champagneGold.withValues(alpha: 0.18),
                        AppColors.champagneGold.withValues(alpha: 0.18),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.champagneGold.withValues(alpha: 0.42),
                      width: 0.6,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 9,
                        color: AppColors.champagneGold,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'AI SUGGESTED',
                        style: TextStyle(
                          fontSize: 8.5,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w900,
                          color: AppColors.champagneGold,
                        ),
                      ),
                    ],
                  ),
                )
              else
                InkWell(
                  onTap: () => setState(() {
                    _values[spec.key] = suggested;
                    _edited.remove(spec.key);
                  }),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.refinedSlate.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.undo_rounded,
                          size: 11,
                          color: AppColors.refinedSlate,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'EDITED · AI WAS $suggested',
                          style: const TextStyle(
                            fontSize: 8.5,
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w900,
                            color: AppColors.refinedSlate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Container(
                width: 30,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.15),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.18),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 10,
              divisions: 10,
              onChanged: (v) {
                setState(() {
                  final next = v.round();
                  _values[spec.key] = next;
                  if (next != suggested) {
                    _edited.add(spec.key);
                  } else {
                    _edited.remove(spec.key);
                  }
                });
              },
            ),
          ),
          if (result.derivations[spec.key] != null) ...[
            const SizedBox(height: 4),
            _derivationNote(result.derivations[spec.key]!, textColor),
          ],
        ],
      ),
    );
  }

  /// One-line methodology pill + plain-English clinical explanation
  /// shown beneath each metric slider. Surfaces *how* the AI arrived at
  /// the score so the value isn't an opaque "AI number."
  Widget _derivationNote(MetricDerivation d, Color textColor) {
    final confPct = (d.confidence * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
      decoration: BoxDecoration(
        color: AppColors.refinedSlate.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.refinedSlate.withValues(alpha: 0.10),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.science_outlined,
                size: 11,
                color: AppColors.refinedSlate,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  d.methodLabel,
                  style: const TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w900,
                    color: AppColors.refinedSlate,
                  ),
                ),
              ),
              Text(
                '$confPct% conf.',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: AppColors.refinedSlate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            d.methodDetail,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              fontStyle: FontStyle.italic,
              color: textColor.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }

  // ── "None detected" / low-confidence hero variant ───────────────
  /// Friendly, supportive hero shown when the engine sees no meaningful
  /// acne or rosacea signs (or when confidence is too low to draw firm
  /// conclusions). Replaces the severity-ring hero so users get a clear,
  /// encouraging read instead of an empty severity bar.
  Widget _clearHeroCard(Color textColor) {
    final lowConfidence = result.isLowConfidence && !result.isClear;
    final accent = lowConfidence ? AppColors.refinedSlate : AppColors.mutedSage;
    final eyebrow = lowConfidence
        ? 'LOW CONFIDENCE'
        : 'NO ACTIVE SIGNS DETECTED';
    final headline = lowConfidence
        ? 'We couldn\'t read this photo confidently'
        : 'Skin appears clear in this area';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.10),
            AppColors.champagneGold.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.32), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withValues(alpha: 0.45),
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              lowConfidence
                  ? Icons.help_outline_rounded
                  : Icons.check_circle_rounded,
              color: accent,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  result.detectionSummary,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: textColor.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _clearChip(
                      'Confidence',
                      '${(result.confidence * 100).round()}%',
                      accent,
                    ),
                    _clearChip(
                      'Severity',
                      result.severityIndex.toStringAsFixed(1),
                      accent,
                    ),
                    _clearChip('Band', result.severityBandLabel, accent),
                  ],
                ),
                if (!lowConfidence) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.tips_and_updates_outlined,
                        size: 13,
                        color: textColor.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'You can still adjust the metrics below if you '
                          'notice something the AI missed.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                            color: textColor.withValues(alpha: 0.62),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _clearChip(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.30), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label · ',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: accent.withValues(alpha: 0.85),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero card with photo + severity ring + headline ─────────────
  Widget _engineBadge(Color textColor) {
    final info = widget.modelInfo;
    final aiUsed = !info.isFallback;
    final meshUsed = widget.meshUsed;
    final yoloUsed = widget.yoloUsed;
    final effUsed = widget.efficientNetUsed;
    final stack = <String>[
      if (meshUsed) 'ML Kit Face Mesh',
      if (yoloUsed) 'YOLOv8 Lesion Detector',
      if (effUsed) 'EfficientNet-B0',
      if (aiUsed && !yoloUsed && !effUsed) 'TensorFlow Lite',
    ];
    final bg = (aiUsed || meshUsed)
        ? AppColors.mutedSage.withValues(alpha: 0.12)
        : const Color(0xFFF1ECE7);
    final fg = (aiUsed || meshUsed)
        ? AppColors.mutedSage
        : textColor.withValues(alpha: 0.75);
    final headline = stack.isEmpty
      ? 'Analysis available'
        : 'Powered by ${stack.join(" + ")}';
    final conf = widget.modelConfidence;
    final detCount = widget.detections.length;
    final sub = <String>[
      if (aiUsed) info.name,
      if (aiUsed && conf != null) '${(conf * 100).round()}% conf',
      if (yoloUsed) '$detCount lesions detected',
      // Bounding-box-area / full-image-area -- a different denominator
      // than the live capture guide's percentage (which divides by a
      // fixed 68%x84% guide box), so label explicitly to avoid reading
      // as directly comparable to that number.
      if (meshUsed && widget.faceCoverage != null)
        'full-frame face coverage ${(widget.faceCoverage! * 100).round()}%',
      if (meshUsed && widget.symmetryScore != null)
        'symmetry ${(widget.symmetryScore! * 100).round()}%',
      if (!aiUsed && !meshUsed)
        'Using the current analysis profile for this scan',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            (aiUsed || meshUsed)
                ? Icons.psychology_alt_rounded
                : Icons.science_rounded,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: fg,
                    height: 1.25,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: fg.withValues(alpha: 0.85),
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(Color textColor) {
    if (result.isClear || result.isLowConfidence) {
      return _clearHeroCard(textColor);
    }
    final sevPct = (result.severityIndex / 10.0).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.refinedSlate.withValues(alpha: 0.06),
            AppColors.champagneGold.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: _photo(result.input.imagePath),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.champagneGold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'AI ANALYSIS · ${result.severityBandLabel.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w900,
                          color: AppColors.champagneGold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      result.headline,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.subheadline,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: textColor.withValues(alpha: 0.74),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'SEVERITY INDEX',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: AppColors.refinedSlate,
                ),
              ),
              const Spacer(),
              Text(
                '${result.severityIndex.toStringAsFixed(1)} / 10',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: _severityColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: sevPct,
              minHeight: 8,
              backgroundColor: AppColors.refinedSlate.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(_severityColor),
            ),
          ),
        ],
      ),
    );
  }

  // ── Detection grid (acne type · rosacea · region) ───────────────
  Widget _detectionGrid(Color textColor) {
    return Row(
      children: [
        Expanded(
          child: _detectionTile(
            icon: Icons.coronavirus_outlined,
            label: 'ACNE TYPE',
            value: PhotoAnalysisUi.acneTypeLabel(result.acneType),
            color: AppColors.champagneGold,
            textColor: textColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _detectionTile(
            icon: Icons.local_florist_outlined,
            label: 'REDNESS',
            value: PhotoAnalysisUi.rosaceaPatternLabel(result.rosaceaPattern),
            color: AppColors.mutedSage,
            textColor: textColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _detectionTile(
            icon: PhotoAnalysisUi.regionIcon(result.input.region),
            label: 'FOCUS',
            value: PhotoAnalysisUi.regionLabel(result.input.region),
            color: AppColors.champagneGold,
            textColor: textColor,
          ),
        ),
      ],
    );
  }

  Widget _detectionTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: textColor,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Baseline comparison block ───────────────────────────────────
  Widget _comparisonCard(BaselineComparison c, Color textColor) {
    final improved = c.improved;
    final color = improved
        ? AppColors.mutedSage
        : c.worsened
        ? AppColors.softTerracotta
        : AppColors.refinedSlate;
    final deltaLabel = c.overallDeltaPct >= 0
        ? '+${c.overallDeltaPct.toStringAsFixed(0)}%'
        : '${c.overallDeltaPct.toStringAsFixed(0)}%';
    final df =
        '${c.baselineDate.month}/${c.baselineDate.day}/${c.baselineDate.year}';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.08), AppColors.cardBackground],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows_rounded, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                'BASELINE COMPARISON',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  deltaLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: _photo(c.baselineImagePath),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      improved
                          ? 'Visible improvement vs. baseline'
                          : c.worsened
                          ? 'Trending up vs. baseline'
                          : 'Holding steady vs. baseline',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Baseline · $df  ·  ${c.weeksSinceBaseline} weeks ago',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: textColor.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (c.metricDeltas.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final d in c.metricDeltas)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.metricLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textColor.withValues(alpha: 0.82),
                        ),
                      ),
                    ),
                    Text(
                      '${d.baselineValue} → ${d.currentValue}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: textColor.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (d.improved
                                    ? AppColors.mutedSage
                                    : d.worsened
                                    ? AppColors.softTerracotta
                                    : AppColors.refinedSlate)
                                .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        d.improved
                            ? '↓ ${d.deltaPct.abs().toStringAsFixed(0)}%'
                            : d.worsened
                            ? '↑ ${d.deltaPct.toStringAsFixed(0)}%'
                            : '—',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: d.improved
                              ? AppColors.mutedSage
                              : d.worsened
                              ? AppColors.softTerracotta
                              : AppColors.refinedSlate,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── Insight card ────────────────────────────────────────────────
  Widget _insightCard(ClinicalInsight ins, Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ins.accent.withValues(alpha: 0.28),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ins.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(ins.icon, color: ins.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ins.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ins.detail,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: textColor.withValues(alpha: 0.80),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Procedure card ──────────────────────────────────────────────
  Widget _procedureCard(ProcedureRecommendation p, Color textColor) {
    final intensityColor = PhotoAnalysisUi.intensityColor(p.intensity);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.22),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: intensityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  PhotoAnalysisUi.procedureCategoryIcon(p.category),
                  color: intensityColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          PhotoAnalysisUi.procedureCategoryLabel(p.category),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: textColor.withValues(alpha: 0.60),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: intensityColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            PhotoAnalysisUi.intensityLabel(
                              p.intensity,
                            ).toUpperCase(),
                            style: TextStyle(
                              fontSize: 8.5,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w900,
                              color: intensityColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.mutedSage.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${p.suitabilityPct}% fit',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.mutedSage,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            p.indication,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: textColor.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniMeta(
                  icon: Icons.event_repeat_outlined,
                  label: 'Sessions',
                  value: p.expectedSessions,
                  color: AppColors.refinedSlate,
                  textColor: textColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniMeta(
                  icon: Icons.schedule_outlined,
                  label: 'Timeline',
                  value: p.timelineWeeks,
                  color: AppColors.refinedSlate,
                  textColor: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _prosConsList(
            icon: Icons.add_circle_outline_rounded,
            color: AppColors.mutedSage,
            label: 'PROS',
            items: p.pros,
            textColor: textColor,
          ),
          const SizedBox(height: 6),
          _prosConsList(
            icon: Icons.remove_circle_outline_rounded,
            color: AppColors.softTerracotta,
            label: 'TRADE-OFFS',
            items: p.cons,
            textColor: textColor,
          ),
        ],
      ),
    );
  }

  Widget _miniMeta({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.16), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 8.5,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: textColor,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _prosConsList({
    required IconData icon,
    required Color color,
    required String label,
    required List<String> items,
    required Color textColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final s in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 3, left: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 6),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    s,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: textColor.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Product cues card ───────────────────────────────────────────
  Widget _productCuesCard(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.mutedSage.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in result.productCues)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.mutedSage,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: textColor.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Common helpers ──────────────────────────────────────────────
  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.champagneGold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.champagneGold, size: 16),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: AppColors.refinedSlate,
          ),
        ),
      ],
    );
  }

  Widget _disclaimer(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.refinedSlate.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: textColor.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI-assisted analysis — not a substitute for professional '
              'medical advice. Procedures listed are evidence-based '
              'options to discuss with a board-certified dermatologist.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                fontStyle: FontStyle.italic,
                color: textColor.withValues(alpha: 0.62),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo(String path) {
    if (path.isEmpty) {
      return Container(color: AppColors.refinedSlate.withValues(alpha: 0.15));
    }
    final base = kIsWeb
        ? Image.network(path, fit: BoxFit.cover)
        : Image.file(File(path), fit: BoxFit.cover);
    if (widget.detections.isEmpty) return base;
    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        Positioned.fill(
          child: CustomPaint(
            painter: _TrackerDetectionOverlayPainter(widget.detections),
          ),
        ),
      ],
    );
  }
}

/// Paints YOLO bounding boxes (normalised [0,1] coords) over a small
/// thumbnail. Skips per-box labels — they'd be unreadable at 96 px.
class _TrackerDetectionOverlayPainter extends CustomPainter {
  final List<Detection> detections;
  const _TrackerDetectionOverlayPainter(this.detections);

  static const Map<String, Color> _palette = {
    'papule': Color(0xFFE65C5C),
    'pustule': Color(0xFFE6A05C),
    'cyst': Color(0xFFB23A48),
    'blackhead': Color(0xFF3D3D3D),
    'whitehead': Color(0xFFE8E0D0),
    'dark_spot': Color(0xFF6B4A2B),
  };

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final r = Rect.fromLTRB(
        d.box.left * size.width,
        d.box.top * size.height,
        d.box.right * size.width,
        d.box.bottom * size.height,
      );
      final c = _palette[d.label] ?? const Color(0xFF4F7EAE);
      final stroke = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrackerDetectionOverlayPainter old) =>
      old.detections != detections;
}
