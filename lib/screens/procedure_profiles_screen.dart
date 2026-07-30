import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';
import '../widgets/before_after_split_slider.dart';
import '../models/journal_entry.dart';
import '../models/premium_recovery_models.dart';
import '../models/procedure.dart';
import '../models/procedure_log.dart';
import '../models/scan_history.dart';
import '../providers/procedure_logs_provider.dart';
import '../utils/ai_product_recommendation_engine.dart';
import '../utils/ai_recovery_plan.dart';
import '../utils/app_logger.dart';
import '../utils/app_prefs.dart';
import '../utils/procedure_intelligence.dart';
import '../utils/ai_intelligence_engine.dart';
import '../utils/ocr_service.dart';
import '../utils/peptide_display.dart';
import '../utils/premium_recovery_service.dart';
import '../utils/report_service.dart';
import '../utils/web_upload_image_utils.dart';
import '../widgets/journal_entry_composer.dart';
import '../widgets/local_image_preview.dart';
import '../widgets/procedure_recovery_curve.dart';
import '../widgets/product_recommendation_card.dart';
import '../widgets/recovery_timeline_card.dart';
import '../widgets/report_disclaimer_notice.dart';
import '../widgets/report_share_helper.dart' as report_share;
import '../widgets/smart_narrative_container.dart';
import '../widgets/skin_heatmap_overlay.dart';
import '../utils/report_purchase.dart';
import '../widgets/luxe_report_layout.dart';
import '../widgets/report_paywall_sheet.dart';
import 'ai_recovery_coach_screen.dart';
import 'camera_screen.dart';
import 'create_procedure_screen.dart';
import 'procedure_camera_guide_screen.dart';
import 'recovery_metric_detail_screen.dart';

enum HeatmapDebugRegion { face, abdomen, flanks, thighs, arms, breasts }

class ProcedureProfilesScreen extends StatefulWidget {
  const ProcedureProfilesScreen({super.key});

  @override
  State<ProcedureProfilesScreen> createState() =>
      _ProcedureProfilesScreenState();
}

class _ProcedureProfilesScreenState extends State<ProcedureProfilesScreen> {
  bool _loading = true;
  List<Procedure> _procedures = const [];
  Map<String, PeptideDisplay> _peptideDisplays = {};
  int _selectedFilter = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final raw = await AppPrefs.getProcedureEntries();
      final list = raw
          .map((e) => Procedure.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.startDate.compareTo(a.startDate));
      final displays = await resolvePeptideDisplaysFor(list);
      if (!mounted) return;
      setState(() {
        _procedures = list;
        _peptideDisplays = displays;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<Procedure> get _visible {
    switch (_selectedFilter) {
      case 1:
        return _procedures.where((p) => !p.isCompleted).toList();
      case 2:
        return _procedures.where((p) => p.isCompleted).toList();
      default:
        return _procedures;
    }
  }

  String get _activeName {
    final active = _procedures.where((p) => !p.isCompleted);
    if (active.isEmpty) return 'None';
    final first = active.first;
    return (_peptideDisplays[first.id]?.title ?? first.type).trim();
  }

  String get _latestDate {
    if (_procedures.isEmpty) return '—';
    return _fmt(_procedures.first.startDate);
  }

  String _fmt(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final yy = (date.year % 100).toString().padLeft(2, '0');
    return '$mm/$dd/$yy';
  }

  Widget _thumb(Procedure procedure) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: MyApp.roseGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.24)),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.medical_services_outlined,
        size: 22,
        color: MyApp.roseGold,
      ),
    );
  }

  Future<void> _openDetail(Procedure procedure) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProcedureDetailScreen(procedure: procedure),
      ),
    );
    await _load();
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateProcedureScreen()),
    );
    await _load();
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: MyApp.champagne,
        appBar: _appBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final visible = _visible;

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: _appBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── header + stats + filters ────────────────────────────────────
          _buildHeader(),
          // ── list ────────────────────────────────────────────────────────
          Expanded(
            child: visible.isEmpty ? _emptyState() : _buildList(visible),
          ),
          // ── bottom CTA ──────────────────────────────────────────────────
          _buildCreateButton(),
        ],
      ),
    );
  }

  AppBar _appBar() => AppBar(
    title: const ClinicalAppBarTitle(
      title: 'Procedure Profiles',
      eyebrow: 'Treatment plans',
    ),
    centerTitle: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    foregroundColor: MyApp.textBrown,
  );

  // ── header widget ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: MyApp.champagne,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ClinicalSectionHeader(
            icon: Icons.medical_services_outlined,
            title: 'Your Aesthetic Procedures',
            eyebrow: 'Clinical overview',
          ),
          const SizedBox(height: 8),
          // subtitle
          Text(
            'Track treatments, monitor recovery, and review progress across every procedure on your plan.',
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.72),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          // stats row
          Row(
            children: [
              Expanded(
                child: _statCard('Saved plans', '${_procedures.length}'),
              ),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Active procedure', _activeName)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Latest start date', _latestDate)),
            ],
          ),
          const SizedBox(height: 12),
          // filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('Clinical Planning', 0),
                const SizedBox(width: 8),
                _chip('Recovery Timelines', 1),
                const SizedBox(width: 8),
                _chip('Progress Intelligence', 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.58),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MyApp.textBrown,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int index) {
    final selected = _selectedFilter == index;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _selectedFilter = index),
      backgroundColor: Colors.white,
      selectedColor: MyApp.roseGold.withValues(alpha: 0.15),
      side: BorderSide(
        color: selected
            ? MyApp.roseGold
            : MyApp.roseGold.withValues(alpha: 0.25),
      ),
      labelStyle: TextStyle(
        color: selected ? MyApp.roseGold : MyApp.textBrown,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  // ── list widget ────────────────────────────────────────────────────────────

  Widget _buildList(List<Procedure> items) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _procedureCard(items[i]),
      ),
    );
  }

  Widget _procedureCard(Procedure p) {
    final isActive = !p.isCompleted;
    final pep = _peptideDisplays[p.id];
    final Color accent = pep?.categoryColor ?? MyApp.roseGold;
    final String title = pep?.title ?? p.type;
    // Procedure list subtitle:
    //  • peptide  → mechanism / "with X, Y +N more"
    //  • else     → original provider (replaces raw "Self" with friendlier label)
    final String subtitle =
        pep?.subtitle ??
        (p.provider.trim().toLowerCase() == 'self'
            ? 'Self-managed'
            : p.provider);
    return Card(
      color: Colors.white,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(p),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // thumbnail or peptide icon
              if (pep != null)
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.30)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(pep.icon, size: 22, color: accent),
                )
              else
                _thumb(p),
              const SizedBox(width: 12),
              // text block
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // procedure / peptide name
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: MyApp.textBrown,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pep != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.40),
                              ),
                            ),
                            child: Text(
                              pep.categoryLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    // subtitle: peptide mechanism, or provider (Self-managed)
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.70),
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // start date + sessions
                    Text(
                      'Started ${_fmt(p.startDate)}  •  '
                      '${p.numSessions} session${p.numSessions == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Active / Completed badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.green.withValues(alpha: 0.11)
                      : MyApp.roseGold.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isActive ? 'Active' : 'Completed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.green.shade700 : MyApp.roseGold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: MyApp.textBrown.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── empty state ────────────────────────────────────────────────────────────

  Widget _emptyState() {
    final isFiltered = _selectedFilter != 0 && _procedures.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.medical_services_outlined,
              size: 48,
              color: MyApp.roseGold.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              isFiltered
                  ? 'No procedures match this filter yet.'
                  : 'No procedure plans yet.\nTap "+ Create New Procedure Plan" to add your first one.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.68),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── bottom create button ───────────────────────────────────────────────────

  Widget _buildCreateButton() {
    return Container(
      color: MyApp.champagne,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _openCreate,
          icon: const Icon(Icons.add),
          label: const Text('+ Create New Procedure Plan'),
          style: MyApp.primaryGoldButton,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Safe first-scan dashboard (shown when a procedure has no scans yet — kept
// for internal use from ProcedureDetailScreen if needed)
// ─────────────────────────────────────────────────────────────────────────────

class ProcedureSafeDashboardScreen extends StatelessWidget {
  const ProcedureSafeDashboardScreen({super.key, required this.procedure});

  final Procedure procedure;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: 'Recovery Dashboard',
          eyebrow: 'Procedure overview',
          color: MyApp.textBrown,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.textBrown,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(procedure.type, style: MyApp.sectionTitleStyle()),
            const SizedBox(height: 8),
            Text('Provider: ${procedure.provider}'),
            const SizedBox(height: 12),
            Text(
              'Start with your first progress scan to unlock full details and trend analytics.',
              style: TextStyle(color: MyApp.textBrown.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () async {
                await AppPrefs.setSelectedProcedureId(procedure.id);
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => kIsWeb
                        ? CameraScreen(procedure: procedure)
                        : ProcedureCameraGuideScreen(procedure: procedure),
                  ),
                );
                if (!context.mounted) return;
                Navigator.of(context).pop(true);
              },
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Add First Progress Scan'),
              style: MyApp.primaryGoldButton,
            ),
          ],
        ),
      ),
    );
  }
}

class ProcedureDetailScreen extends StatefulWidget {
  const ProcedureDetailScreen({super.key, required this.procedure});

  final Procedure procedure;

  @override
  State<ProcedureDetailScreen> createState() => _ProcedureDetailScreenState();
}

class _ProcedureDetailScreenState extends State<ProcedureDetailScreen> {
  // Helper: Returns clinical-grade AI insights for the latest scan, using procedure-aware logic
  List<MetricInsight> get _latestMetricInsights {
    final latest = _latestMetrics;
    final baseline = _baselineMetrics;
    if (latest == null) return [];
    final report = AiIntelligenceEngine.interpretScanMetrics(
      latest,
      baseline: baseline,
      procedureType: _procedure.type,
      customDescription: _procedure.customDescription,
      focusArea: _procedure.focusArea,
      daysSinceProcedure:
          DateTime.now().difference(_procedure.startDate).inDays + 1,
    );
    return report.metricInsights;
  }

  Widget _metricGridCard(Map<String, dynamic> metric) {
    final Color statusColor = metric['statusColor'] as Color;
    final Map<String, dynamic> trendMeta =
        metric['trendMeta'] as Map<String, dynamic>;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            (metric['softColor'] as Color).withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.24),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric['name'] as String,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.4,
              color: MyApp.clinicalNavy,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                metric['valueText'] as String,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                  height: 1,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      metric['statusText'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            metric['explanation'] as String,
            style: TextStyle(
              fontSize: 11,
              color: MyApp.textBrown.withValues(alpha: 0.72),
              height: 1.35,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                trendMeta['icon'] as IconData,
                size: 13,
                color: trendMeta['color'] as Color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  trendMeta['label'] as String,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: trendMeta['color'] as Color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buildProcedureMetricCards(
    List<MetricInsight> insights,
  ) {
    final isHalo = _procedure.type.toLowerCase().contains('halo');

    MetricInsight? pick(List<String> keys) {
      for (final insight in insights) {
        final label = insight.label.toLowerCase();
        if (keys.any(label.contains)) return insight;
      }
      return null;
    }

    Map<String, dynamic> buildMetric({
      required String name,
      required List<String> keys,
      required String explanation,
      required bool lowerIsBetter,
      required double fallbackValue,
      required String fallbackStatus,
      required String fallbackTrend,
      required String unit,
    }) {
      final insight = pick(keys);
      final value = (insight?.value ?? fallbackValue).clamp(0.0, 10.0);
      final statusText = insight?.clinicalLabel ?? fallbackStatus;
      final statusColor = insight?.color ?? _statusColorFromLabel(statusText);
      final trend = _trendKind(insight, fallbackTrend);
      final trendMeta = _trendMeta(trend);
      final normalizedScore = lowerIsBetter
          ? ((10 - value) / 10) * 100
          : (value / 10) * 100;

      String valueText;
      if (unit == 'mm') {
        valueText = '${_poreSizeMmFromScore(value).toStringAsFixed(2)} mm';
      } else {
        valueText =
            '${value.toStringAsFixed(1)}/10${unit.isEmpty ? '' : ' $unit'}';
      }

      return {
        'name': name,
        'valueText': valueText,
        'statusText': statusText,
        'statusColor': statusColor,
        'softColor': statusColor,
        'explanation': explanation,
        'trendMeta': trendMeta,
        'score': normalizedScore.clamp(0.0, 100.0),
      };
    }

    final redness = buildMetric(
      name: 'Redness / Erythema',
      keys: ['redness', 'erythema', 'inflammation'],
      explanation:
          'Measures post-laser inflammation and vascular reactivity in treated skin.',
      lowerIsBetter: true,
      fallbackValue: isHalo ? 4.2 : 5.0,
      fallbackStatus: 'Mild erythema',
      fallbackTrend: 'improving',
      unit: '',
    );

    final texture = buildMetric(
      name: 'Texture & Smoothness',
      keys: ['texture', 'smoothness'],
      explanation:
          'Tracks skin surface refinement as epidermal turnover and resurfacing improve.',
      lowerIsBetter: true,
      fallbackValue: isHalo ? 3.8 : 4.9,
      fallbackStatus: 'Mild roughness',
      fallbackTrend: 'improving',
      unit: '',
    );

    final pigmentation = buildMetric(
      name: 'Dark Spots / Pigmentation',
      keys: ['dark', 'pigment', 'hyperpigmentation'],
      explanation:
          'Reflects post-inflammatory pigmentation activity and uneven tone risk.',
      lowerIsBetter: true,
      fallbackValue: isHalo ? 4.7 : 5.3,
      fallbackStatus: 'Moderate pigmentation',
      fallbackTrend: 'stable',
      unit: '',
    );

    final pores = buildMetric(
      name: 'Pore Size',
      keys: ['pore'],
      explanation:
          'Represents pore visibility and local congestion after treatment recovery.',
      lowerIsBetter: true,
      fallbackValue: isHalo ? 3.9 : 4.8,
      fallbackStatus: 'Mild visibility',
      fallbackTrend: 'improving',
      unit: 'mm',
    );

    final elasticity = buildMetric(
      name: 'Elasticity / Firmness',
      keys: ['elasticity', 'firmness', 'laxity'],
      explanation:
          'Captures dermal support and rebound as collagen remodeling progresses.',
      lowerIsBetter: false,
      fallbackValue: isHalo ? 6.7 : 5.8,
      fallbackStatus: 'Moderate firmness',
      fallbackTrend: 'improving',
      unit: '',
    );

    final barrierInsight = pick(['barrier', 'inflammation', 'hydration']);
    final barrierBase = barrierInsight != null
        ? (10 - barrierInsight.value).clamp(0.0, 10.0)
        : ((10 - ((redness['score'] as double) / 10)) +
                  (10 - ((texture['score'] as double) / 10))) /
              2;
    final barrierStatus = barrierBase >= 7.8
        ? 'Strong'
        : barrierBase >= 6.2
        ? 'Moderate'
        : 'Compromised';
    final barrierTrend = barrierInsight?.isPositiveTrend == null
        ? 'improving'
        : (barrierInsight!.isPositiveTrend! ? 'improving' : 'regressing');

    final barrierRecovery = {
      'name': 'Barrier Recovery',
      'valueText': '${(barrierBase * 10).round()}%',
      'statusText': barrierStatus,
      'statusColor': _statusColorFromLabel(barrierStatus),
      'softColor': _statusColorFromLabel(barrierStatus),
      'explanation':
          'Estimates barrier resilience, hydration integrity, and irritant tolerance.',
      'trendMeta': _trendMeta(barrierTrend),
      'score': (barrierBase * 10).clamp(0.0, 100.0),
    };

    final metrics = <Map<String, dynamic>>[
      redness,
      texture,
      pigmentation,
      pores,
      elasticity,
      barrierRecovery,
    ];

    final overall = _computeOverallRecoveryScore(metrics);
    final overallStatus = overall >= 82
        ? 'Excellent'
        : overall >= 68
        ? 'On-Track'
        : overall >= 52
        ? 'Moderate'
        : 'Needs Support';
    metrics.add({
      'name': 'Overall Recovery Score',
      'valueText': '${overall.toStringAsFixed(0)} / 100',
      'statusText': overallStatus,
      'statusColor': _statusColorFromLabel(overallStatus),
      'softColor': _statusColorFromLabel(overallStatus),
      'explanation':
          'Composite indicator blending inflammation, texture, tone, pores, firmness, and barrier resilience.',
      'trendMeta': _trendMeta('improving'),
      'score': overall,
    });

    return metrics;
  }

  Widget _buildMetricExplanationStrip() {
    final items = <Map<String, String>>[
      {
        'name': 'Redness / Erythema',
        'text':
            'Measures visible inflammation and vascular reactivity. Lower is better.',
      },
      {
        'name': 'Texture & Smoothness',
        'text':
            'Measures skin surface evenness and resurfacing progress. Lower is better.',
      },
      {
        'name': 'Dark Spots / Pigmentation',
        'text':
            'Measures uneven tone and post-inflammatory pigment activity. Lower is better.',
      },
      {
        'name': 'Pore Size',
        'text': 'Measures visible pore openings. Lower is better.',
      },
      {
        'name': 'Elasticity / Firmness',
        'text': 'Measures rebound and collagen support. Higher is better.',
      },
      {
        'name': 'Barrier Recovery',
        'text':
            'Measures resilience, hydration integrity, and irritation tolerance. Higher is better.',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.16),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: MyApp.roseGold),
              const SizedBox(width: 6),
              Text(
                'How to read these metrics',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: MyApp.clinicalNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 840
                  ? 2
                  : constraints.maxWidth >= 520
                  ? 1
                  : 1;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items.map((item) {
                  return Container(
                    width: columns == 2
                        ? (constraints.maxWidth - 8) / 2
                        : constraints.maxWidth,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: MyApp.goldShimmer.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name']!,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: MyApp.clinicalNavy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item['text']!,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: MyApp.textBrown.withValues(alpha: 0.76),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  double _poreSizeMmFromScore(double score) {
    return (0.12 + (score * 0.028)).clamp(0.12, 0.42);
  }

  double _computeOverallRecoveryScore(List<Map<String, dynamic>> cards) {
    if (cards.isEmpty) return 0;
    final values = cards
        .map((m) => (m['score'] as double?) ?? 0)
        .where((v) => v >= 0)
        .toList();
    if (values.isEmpty) return 0;
    final sum = values.fold<double>(0, (a, b) => a + b);
    return (sum / values.length).clamp(0.0, 100.0);
  }

  String _trendKind(MetricInsight? insight, String fallback) {
    if (insight?.isPositiveTrend == null) return fallback;
    return insight!.isPositiveTrend! ? 'improving' : 'regressing';
  }

  Map<String, dynamic> _trendMeta(String trend) {
    switch (trend) {
      case 'improving':
        return {
          'label': 'Improving trend',
          'icon': Icons.trending_up,
          'color': const Color(0xFF1E8C5F),
        };
      case 'regressing':
        return {
          'label': 'Regression trend',
          'icon': Icons.trending_down,
          'color': const Color(0xFFB13C52),
        };
      default:
        return {
          'label': 'Stable trend',
          'icon': Icons.trending_flat,
          'color': const Color(0xFFAD7C2B),
        };
    }
  }

  Color _statusColorFromLabel(String label) {
    final s = label.toLowerCase();
    if (s.contains('excellent') ||
        s.contains('optimal') ||
        s.contains('strong') ||
        s.contains('minimal')) {
      return const Color(0xFF1E8C5F);
    }
    if (s.contains('mild') || s.contains('on-track') || s.contains('stable')) {
      return MyApp.clinicalTeal;
    }
    if (s.contains('moderate')) {
      return const Color(0xFFAD7C2B);
    }
    return const Color(0xFFB13C52);
  }

  late Procedure _procedure;
  List<ScanHistoryEntry> _scans = const [];
  ProcedureLog? _procedureLog;
  String? _baselineScanId;
  String? _baselineImagePath;
  String? _latestScanId;
  String? _latestImagePath;
  Uint8List? _baselineHydratedBytes;
  Uint8List? _latestHydratedBytes;
  List<ProgressPhotoInsight> _progressInsights = const [];
  List<CustomRecoveryPlan> _customPlans = const [];
  bool _loadingPremiumData = false;
  bool _busy = false;
  Map<String, dynamic>? _localProcedureDeltaPayload;

  // BBL-specific manual recovery assessment metrics
  Map<String, double>? _bblAssessment;
  Map<String, double>? _bblAssessmentPrevious;
  List<Map<String, dynamic>> _bblHistory = const [];

  // Peptide-specific display block (peptide name, mechanism, category badge).
  // Null when this procedure isn't peptide-related.
  PeptideDisplay? _peptideDisplay;
  String _selectedRecoveryCurveMetric = 'redness';
  bool _showHeatmapDebugRow = kDebugMode;
  HeatmapDebugRegion? _debugHeatmapRegionOverride;

  @override
  void initState() {
    super.initState();
    _procedure = widget.procedure;
    AppLogger.verbose(
      '[ProcedureProfilesScreen] resolvedProcedureType=${canonicalProcedureType(widget.procedure.type)}',
    );
    _refresh();
  }

  Future<void> _refresh() async {
    final entries = await AppPrefs.getProcedureEntries();
    final index = entries.indexWhere((e) => (e['id'] ?? '') == _procedure.id);
    if (index != -1) {
      _procedure = Procedure.fromJson(
        Map<String, dynamic>.from(entries[index]),
      );
    }

    final availableCurveMetrics = _availableRecoveryCurveMetricsForProcedure(
      _procedure.type,
    );
    final savedRecoveryCurveMetric = await _loadSavedRecoveryCurveMetric(
      _procedure.id,
    );
    final resolvedRecoveryCurveMetric =
        availableCurveMetrics.contains(savedRecoveryCurveMetric)
        ? savedRecoveryCurveMetric!
        : (availableCurveMetrics.isNotEmpty
              ? availableCurveMetrics.first
              : 'redness');
    final heatmapDebugRaw = await AppPrefs.getString(
      'debug_heatmap_overlay_enabled',
    );
    final showHeatmapDebugRow =
        kDebugMode ||
        (heatmapDebugRaw?.trim().toLowerCase() == 'true') ||
        (heatmapDebugRaw?.trim() == '1');

    final all = await AppPrefs.getScanEntries();
    final scoped =
        all.where((s) => (s.procedureId ?? '') == _procedure.id).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final comparison = await AppPrefs.getProcedurePhotoComparison(
      _procedure.id,
    );
    debugPrint(
      '[BASELINE_READ] source=procedure_photo_comparison procedureId=${_procedure.id} '
      'baselineScanId=${comparison['baselineScanId'] ?? 'none'} '
      'latestScanId=${comparison['latestScanId'] ?? 'none'} reason=procedure_profiles_refresh',
    );

    // At-Home procedures store their photos on a ProcedureLog (Hive), not in
    // scan history. Load the log that shares this procedure's id so the
    // Before/After section can surface those photos too.
    final procedureLog = _findProcedureLogById(_procedure.id);
    debugPrint(
      'Loaded ProcedureLog for procedure ${_procedure.id}: '
      '${procedureLog == null ? 'none' : '${procedureLog.photoPaths.length} photos: ${procedureLog.photoPaths}'}',
    );
    AppLogger.verbose(
      '[_refresh] proc=${_procedure.id} | resolvedProcedureType=${canonicalProcedureType(_procedure.type)}'
      ' | scans=${scoped.length}'
      ' | baselineId=${comparison['baselineScanId']}'
      ' | latestId=${comparison['latestScanId']}'
      ' | samePhoto=${comparison['baselineScanId'] == comparison['latestScanId']}',
    );

    if (!mounted) return;
    final pepDisplay = await resolvePeptideDisplay(_procedure);
    if (!mounted) return;
    setState(() {
      _scans = scoped;
      _procedureLog = procedureLog;
      _baselineScanId = comparison['baselineScanId'];
      _baselineImagePath = comparison['baselineImagePath'];
      _latestScanId = comparison['latestScanId'];
      _latestImagePath = comparison['latestImagePath'];
      _peptideDisplay = pepDisplay;
      _selectedRecoveryCurveMetric = resolvedRecoveryCurveMetric;
      _showHeatmapDebugRow = showHeatmapDebugRow;
    });

    await _hydrateLocalProcedureDeltaPayload(procedureLog);

    // Load BBL-specific assessment and history for body contouring procedures
    if (ProcedureIntelligence.categoryFor(_procedure.type) ==
        ProcedureCategory.bodyContouring) {
      final bbl = await AppPrefs.getBBLAssessment(_procedure.id);
      final hist = await AppPrefs.getBBLAssessmentHistory(_procedure.id);
      if (mounted) {
        setState(() {
          _bblAssessment = bbl;
          _bblHistory = hist;
        });
      }
    }

    await _loadPremiumData();
  }

  Future<void> _hydrateLocalProcedureDeltaPayload(
    ProcedureLog? procedureLog,
  ) async {
    final photos = procedureLog?.labeledPhotos
            .where((photo) => photo.path.trim().isNotEmpty)
            .toList() ??
        const [];

    if (photos.length < 2) {
      if (!mounted) return;
      setState(() {
        _localProcedureDeltaPayload = null;
        _baselineHydratedBytes = null;
        _latestHydratedBytes = null;
      });
      return;
    }

    final baselinePath =
        procedureLog?.photoForLabel('Before') ?? photos.first.path;
    final latestPath = procedureLog?.photoForLabel('After') ?? photos.last.path;

    if (baselinePath.trim().isEmpty ||
        latestPath.trim().isEmpty ||
        baselinePath.trim() == latestPath.trim()) {
      if (!mounted) return;
      setState(() {
        _localProcedureDeltaPayload = null;
        _baselineHydratedBytes = null;
        _latestHydratedBytes = null;
      });
      return;
    }

    try {
      print(
        "DEBUG [Delta Engine]: Starting compute for baseline: '$baselinePath' and progress: '$latestPath'",
      );

      final baselineBytes = await _readStoredImageBytes(baselinePath.trim());
      final latestBytes = await _readStoredImageBytes(latestPath.trim());

      final payload = await computeLocalProcedureDeltas(
        baselinePath.trim(),
        latestPath.trim(),
      );

      print(
        'DEBUG [Delta Engine]: Success! Payload keys found: ${payload.keys}',
      );
      print(
        "DEBUG [Delta Engine]: metric_matrix: ${payload['metric_matrix']}",
      );

      if (!mounted) {
        print(
          'DEBUG [Delta Engine]: Widget unmounted, dropping state update.',
        );
        return;
      }

      print(
        'DEBUG [Delta Engine]: Dispatching setState to trigger premium layout rebuild.',
      );
      setState(() {
        _localProcedureDeltaPayload = payload;
        _baselineHydratedBytes = baselineBytes;
        _latestHydratedBytes = latestBytes;
      });
      setState(() {});
    } catch (e, stackTrace) {
      print('DEBUG [Delta Engine]: CRITICAL FAILURE processing photo deltas: $e');
      print('DEBUG [Delta Engine]: StackTrace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _localProcedureDeltaPayload = null;
        _baselineHydratedBytes = null;
        _latestHydratedBytes = null;
      });
    }
  }

  Future<void> _loadPremiumData() async {
    if (!mounted) return;
    setState(() => _loadingPremiumData = true);
    try {
      // Lazy-generate an insight on-the-fly when this procedure has at
      // least two scans but none of the persisted insights covers its
      // latest scan yet. This makes the AI Progress Insights section
      // light up reliably as soon as a second scan exists — even if the
      // camera-side trigger was skipped (e.g. non-premium account at
      // capture time, scans imported from another path, etc.).
      if (_scans.length >= 2) {
        final existing = await PremiumRecoveryService.loadProgressInsights();
        final latestId = _scans.first.id;
        final hasInsightForLatest = existing
            .whereType<ProgressPhotoInsight>()
            .any((i) => i.latestScanId == latestId);
        if (!hasInsightForLatest) {
          try {
            await PremiumRecoveryService.autoAnalyzeLatestProgressFromHistory(
              _scans,
            );
          } catch (e) {
            debugPrint('[_loadPremiumData] lazy insight gen failed: $e');
          }
        }
      }

      final insightsRaw = await PremiumRecoveryService.loadProgressInsights();
      final plansRaw = await PremiumRecoveryService.loadCustomPlans();

      // Match insights to this procedure by scan id first (most reliable),
      // falling back to the procedureType string. Insights without any
      // procedureType are kept (legacy data).
      final scopedScanIds = _scans.map((s) => s.id).toSet();
      final filteredInsights =
          insightsRaw.whereType<ProgressPhotoInsight>().where((i) {
            if (scopedScanIds.contains(i.latestScanId)) return true;
            if ((i.procedureType ?? '').trim().isNotEmpty) {
              return i.procedureType!.toLowerCase() ==
                  _procedure.type.toLowerCase();
            }
            return true;
          }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final filteredPlans =
          plansRaw
              .whereType<CustomRecoveryPlan>()
              .where(
                (p) =>
                    p.procedureType.toLowerCase() ==
                    _procedure.type.toLowerCase(),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _progressInsights = filteredInsights;
        _customPlans = filteredPlans;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingPremiumData = false);
      }
    }
  }

  /// True only if the active procedure is a Brazilian Butt Lift.
  /// Lipo, Tummy Tuck, etc. are body contouring but NOT BBL.
  bool get _isBBL {
    final canonical = canonicalProcedureType(_procedure.type).toLowerCase();
    return canonical == 'bbl' ||
        canonical.contains('bbl') ||
        canonical.contains('brazilian butt');
  }

  /// Returns the metric defs relevant to the current procedure.
  /// Fat retention only applies to BBL (fat grafting). Other body contouring
  /// procedures track contour evenness, fibrosis, and satisfaction.
  List<Map<String, dynamic>> get _activeMetricDefs {
    if (_isBBL) return _bblMetricDefs;
    return _bblMetricDefs.where((d) => d['key'] != 'fatRetentionPct').toList();
  }

  int get _currentStreak {
    final entries = _procedure.journalEntries;
    if (entries.isEmpty) {
      final start = DateTime(
        _procedure.startDate.year,
        _procedure.startDate.month,
        _procedure.startDate.day,
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return start.isAfter(today) ? 0 : 1;
    }

    final uniqueDays =
        entries
            .map((e) => DateTime(e.date.year, e.date.month, e.date.day))
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var expected = today;

    if (uniqueDays.first != today) {
      final yesterday = today.subtract(const Duration(days: 1));
      if (uniqueDays.first != yesterday) return 0;
      expected = yesterday;
    }

    var streak = 0;
    var i = 0;
    while (i < uniqueDays.length && uniqueDays[i] == expected) {
      streak++;
      expected = expected.subtract(const Duration(days: 1));
      i++;
    }
    return streak;
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  /// Short, glanceable current-phase label for the At-a-Glance stats row.
  /// Generic across procedure types — clinical timeline anchors are reflected
  /// in the dedicated Recovery Timeline section below.
  String _currentPhaseShort() {
    final d = DateTime.now().difference(_procedure.startDate).inDays + 1;
    if (d <= 0) return 'Pre-op';
    if (d <= 7) return 'Day $d';
    if (d <= 42) return 'Wk ${((d) / 7).ceil()}';
    if (d <= 365) return 'Mo ${((d) / 30).ceil()}';
    return 'Yr ${((d) / 365).floor()}+';
  }

  Future<void> _openScanCapture() async {
    await AppPrefs.setSelectedProcedureId(_procedure.id);
    if (!mounted) return;
    final acceptedDisclaimer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Before you capture a progress photo'),
          content: const Text(
            'These photos are for wellness tracking only. They do not provide medical advice or diagnosis. Use consistent lighting and framing, and consult your licensed provider for clinical guidance.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('I Understand'),
            ),
          ],
        );
      },
    );
    if (acceptedDisclaimer != true || !mounted) return;
    final baselineRecord = _procedureLog?.latestTrackProcedureBaselineRecord();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => kIsWeb
            ? CameraScreen(
                procedure: _procedure,
                initialTrackProcedureBaselineRecord: baselineRecord,
              )
            : ProcedureCameraGuideScreen(
                procedure: _procedure,
                initialTrackProcedureBaselineRecord: baselineRecord,
              ),
      ),
    );
    await _refresh();
  }

  ScanHistoryEntry? _findScanById(String? scanId) {
    if (scanId == null || scanId.isEmpty) return null;
    for (final scan in _scans) {
      if (scan.id == scanId) {
        return scan;
      }
    }
    return null;
  }

  Uint8List? _decodeStoredImagePath(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return null;
    if (imagePath.startsWith('data:image')) {
      try {
        final parts = imagePath.split(',');
        if (parts.length > 1) {
          return base64Decode(parts[1]);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<Uint8List?> _readStoredImageBytes(String? imagePath) async {
    final decoded = _decodeStoredImagePath(imagePath);
    if (decoded != null && decoded.isNotEmpty) {
      return decoded;
    }

    final clean = imagePath?.trim();
    if (clean == null || clean.isEmpty) return null;

    try {
      return await XFile(clean).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  SkinMetrics? get _latestMetrics {
    final latestEntry = _findScanById(_latestScanId);
    if (latestEntry != null) {
      debugPrint(
        '[BASELINE_READ] source=procedure_photo_comparison procedureId=${_procedure.id} '
        'baselineScanId=${_baselineScanId ?? 'none'} latestScanId=${_latestScanId ?? 'none'} reason=latest_id_hit',
      );
      return latestEntry.toSkinMetrics();
    }
    if (_scans.isNotEmpty) {
      debugPrint(
        '[BASELINE_READ] source=previous_scan_in_list procedureId=${_procedure.id} '
        'baselineScanId=${_baselineScanId ?? 'none'} latestScanId=${_latestScanId ?? 'none'} reason=latest_id_miss_fallback_first_scan',
      );
    }
    return _scans.isNotEmpty ? _scans.first.toSkinMetrics() : null;
  }

  /// Returns the baseline metrics (first photo taken for this procedure).
  /// The baseline is ALWAYS the oldest scan (first uploaded photo).
  /// The isBaseline flag should mark it, but as fallback we use timestamp order.
  SkinMetrics? get _baselineMetrics {
    if (_scans.isEmpty) return null;

    final savedBaseline = _findScanById(_baselineScanId);
    if (savedBaseline != null) {
      debugPrint(
        '[BASELINE_READ] source=procedure_photo_comparison procedureId=${_procedure.id} '
        'baselineScanId=${_baselineScanId ?? 'none'} latestScanId=${_latestScanId ?? 'none'} reason=baseline_id_hit',
      );
      return savedBaseline.toSkinMetrics();
    }

    // TODO(baseline-cleanup): fallback path kept for compatibility while proving live map-based flow.
    // Primary: Find scan marked as baseline
    ScanHistoryEntry? baselineEntry;
    try {
      baselineEntry = _scans.firstWhere((s) => s.isBaseline);
      debugPrint(
        '[BASELINE_READ] source=previous_scan_in_list procedureId=${_procedure.id} '
        'baselineScanId=${_baselineScanId ?? 'none'} latestScanId=${_latestScanId ?? 'none'} reason=baseline_id_miss_use_isBaseline_flag',
      );
    } catch (_) {
      // Fallback: Use the OLDEST scan (last in sorted list, since newest is first)
      baselineEntry = _scans.last;
      debugPrint(
        '[BASELINE_READ] source=previous_scan_in_list procedureId=${_procedure.id} '
        'baselineScanId=${_baselineScanId ?? 'none'} latestScanId=${_latestScanId ?? 'none'} reason=baseline_id_miss_use_oldest_scan',
      );
    }

    return baselineEntry.toSkinMetrics();
  }

  /// Returns the baseline photo (first image taken) as bytes, or null if not available
  Uint8List? get _baselinePhotoBytes {
    if (_baselineHydratedBytes != null && _baselineHydratedBytes!.isNotEmpty) {
      return _baselineHydratedBytes;
    }
    final savedBaselineBytes = _decodeStoredImagePath(_baselineImagePath);
    if (savedBaselineBytes != null && savedBaselineBytes.isNotEmpty) {
      return savedBaselineBytes;
    }

    if (_scans.isEmpty) return null;

    // Primary: Find scan marked as baseline
    ScanHistoryEntry? baselineEntry;
    try {
      baselineEntry = _scans.firstWhere((s) => s.isBaseline);
    } catch (_) {
      // Fallback: Use the OLDEST scan (last in list, since sorted newest-first)
      baselineEntry = _scans.last;
    }

    return _decodeStoredImagePath(baselineEntry.imagePath);
  }

  /// Returns the latest progress photo (most recent image) as bytes, or null if not available
  Uint8List? get _latestPhotoBytes {
    if (_latestHydratedBytes != null && _latestHydratedBytes!.isNotEmpty) {
      return _latestHydratedBytes;
    }
    final savedLatestBytes = _decodeStoredImagePath(_latestImagePath);
    if (savedLatestBytes != null && savedLatestBytes.isNotEmpty) {
      return savedLatestBytes;
    }

    if (_scans.isEmpty) return null;

    final latestEntry = _findScanById(_latestScanId) ?? _scans.first;
    return _decodeStoredImagePath(latestEntry.imagePath);
  }

  bool get _hasDistinctComparisonPair {
    if ((_baselineImagePath ?? '').isEmpty ||
        (_latestImagePath ?? '').isEmpty) {
      return _scans.length > 1;
    }
    return _baselineImagePath != _latestImagePath;
  }

  Future<Map<String, dynamic>> computeLocalProcedureDeltas(
    String baselinePath,
    String afterPath,
  ) async {
    Future<Uint8List?> readStoredBytes(String path) async {
      final trimmed = path.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('data:image')) {
        try {
          final comma = trimmed.indexOf(',');
          if (comma == -1) return null;
          return base64Decode(trimmed.substring(comma + 1));
        } catch (_) {
          return null;
        }
      }
      try {
        return await XFile(trimmed).readAsBytes();
      } catch (_) {
        return null;
      }
    }

    img.Image? decodeGrayscale(Uint8List? bytes) {
      if (bytes == null || bytes.isEmpty) return null;
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      return img.grayscale(decoded);
    }

    final baselineImage = decodeGrayscale(await readStoredBytes(baselinePath));
    final afterImage = decodeGrayscale(await readStoredBytes(afterPath));

    if (baselineImage == null || afterImage == null) {
      return const {
        'metric_matrix': <String, dynamic>{},
        'trend_deltas': <String, dynamic>{},
      };
    }

    img.Image normalize(img.Image source) {
      return img.copyResize(
        source,
        width: 160,
        height: 160,
        interpolation: img.Interpolation.average,
      );
    }

    Map<String, double> summarize(img.Image source) {
      final sample = normalize(source);
      final width = sample.width;
      final height = sample.height;
      final totalPixels = width * height;
      if (totalPixels == 0) {
        return const <String, double>{};
      }

      double sum = 0;
      double sumSquares = 0;
      double edgeMagnitudeSum = 0;
      int edgeHits = 0;
      int adaptiveDarkHits = 0;
      int adaptivePoreHits = 0;
      int centralPixels = 0;

      final startX = (width * 0.22).round();
      final endX = (width * 0.78).round();
      final startY = (height * 0.20).round();
      final endY = (height * 0.80).round();

      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final pixel = sample.getPixel(x, y);
          final lum = pixel.r.toDouble();
          sum += lum;
          sumSquares += lum * lum;

          if (x < startX || x > endX || y < startY || y > endY) {
            continue;
          }

          centralPixels++;
          final radius = 3;
          double localSum = 0;
          int localCount = 0;
          for (var yy = (y - radius).clamp(0, height - 1);
              yy <= (y + radius).clamp(0, height - 1);
              yy++) {
            for (var xx = (x - radius).clamp(0, width - 1);
                xx <= (x + radius).clamp(0, width - 1);
                xx++) {
              localSum += sample.getPixel(xx, yy).r.toDouble();
              localCount++;
            }
          }

          final localMean = localCount == 0 ? lum : localSum / localCount;
          if (lum < localMean - 8.0) {
            adaptiveDarkHits++;
          }
          if (lum < localMean - 12.0) {
            adaptivePoreHits++;
          }
        }
      }

      for (var y = 1; y < height - 1; y++) {
        for (var x = 1; x < width - 1; x++) {
          final center = sample.getPixel(x, y).r.toDouble();
          final gx =
              -sample.getPixel(x - 1, y - 1).r.toDouble() +
              sample.getPixel(x + 1, y - 1).r.toDouble() * 1 +
              -2 * sample.getPixel(x - 1, y).r.toDouble() +
              2 * sample.getPixel(x + 1, y).r.toDouble() +
              -sample.getPixel(x - 1, y + 1).r.toDouble() +
              sample.getPixel(x + 1, y + 1).r.toDouble() * 1;
          final gy =
              -sample.getPixel(x - 1, y - 1).r.toDouble() -
              2 * sample.getPixel(x, y - 1).r.toDouble() -
              sample.getPixel(x + 1, y - 1).r.toDouble() +
              sample.getPixel(x - 1, y + 1).r.toDouble() +
              2 * sample.getPixel(x, y + 1).r.toDouble() +
              sample.getPixel(x + 1, y + 1).r.toDouble();
          final magnitude = math.sqrt(gx * gx + gy * gy) / 255.0;
          edgeMagnitudeSum += magnitude;
          if (magnitude > 0.22) {
            edgeHits++;
          }
          if (center < 160) {
            edgeMagnitudeSum += 0;
          }
        }
      }

      final mean = sum / totalPixels;
      final variance = (sumSquares / totalPixels) - (mean * mean);
      final stdDev = variance.isNegative ? 0.0 : math.sqrt(variance);
      final brightness = (mean / 255.0).clamp(0.0, 1.0);
      final contrast = (stdDev / 128.0).clamp(0.0, 1.0);
      final poreVisibility = centralPixels == 0
          ? 0.0
          : (adaptivePoreHits / centralPixels).clamp(0.0, 1.0);
      final adaptiveDarkRatio = centralPixels == 0
          ? 0.0
          : (adaptiveDarkHits / centralPixels).clamp(0.0, 1.0);
      final edgeDensity = ((edgeHits / ((width - 2) * (height - 2)))
              .clamp(0.0, 1.0))
          .toDouble();
      final edgeEnergy = (edgeMagnitudeSum / ((width - 2) * (height - 2)))
          .clamp(0.0, 1.0)
          .toDouble();

      return {
        'localized_redness': ((1.0 - brightness) * 100).clamp(0.0, 100.0),
        'texture_smoothness':
            ((1.0 - edgeDensity) * 100).clamp(0.0, 100.0),
        'pore_visibility': (poreVisibility * 100).clamp(0.0, 100.0),
        'glabellar_wrinkle_depth': (edgeEnergy * 100).clamp(0.0, 100.0),
        'structural_firmness_elasticity':
            ((1.0 - contrast) * 100).clamp(0.0, 100.0),
        'adaptive_dark_ratio': (adaptiveDarkRatio * 100).clamp(0.0, 100.0),
      };
    }

    final baselineMetrics = summarize(baselineImage);
    final currentMetrics = summarize(afterImage);

    double trendDelta(
      String key, {
      required bool lowerIsBetter,
    }) {
      final baseline = baselineMetrics[key] ?? 0;
      final current = currentMetrics[key] ?? 0;
      if (baseline <= 0) return 0.0;
      final raw = ((current - baseline) / baseline) * 100.0;
      return lowerIsBetter ? -raw : raw;
    }

    final metricMatrix = <String, dynamic>{
      ...currentMetrics,
      'metric_source': 'local-vision',
    };

    final trendDeltas = <String, dynamic>{
      'localized_redness': trendDelta(
        'localized_redness',
        lowerIsBetter: true,
      ),
      'texture_smoothness': trendDelta(
        'texture_smoothness',
        lowerIsBetter: false,
      ),
      'pore_visibility': trendDelta(
        'pore_visibility',
        lowerIsBetter: true,
      ),
      'glabellar_wrinkle_depth': trendDelta(
        'glabellar_wrinkle_depth',
        lowerIsBetter: true,
      ),
      'structural_firmness_elasticity': trendDelta(
        'structural_firmness_elasticity',
        lowerIsBetter: false,
      ),
    };

    return {
      'metric_matrix': metricMatrix,
      'trend_deltas': trendDeltas,
    };
  }

  Future<void> _generateCustomPlanFromNotes() async {
    final notes = _procedure.notes.trim();
    if (notes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add surgeon notes first to generate a custom AI plan.',
          ),
        ),
      );
      return;
    }

    final plan = await PremiumRecoveryService.buildCustomPlanFromNotes(
      notes: notes,
      procedureType: _procedure.type,
      startDate: _procedure.startDate,
    );

    final existingRaw = await PremiumRecoveryService.loadCustomPlans();
    final existing = existingRaw.whereType<CustomRecoveryPlan>().toList();
    final updated = [plan, ...existing];
    await PremiumRecoveryService.saveCustomPlans(
      updated.map((e) => e.toJson()).toList(),
    );
    await _loadPremiumData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Custom recovery plan generated.')),
    );
  }

  Future<void> _setCompleted(bool completed) async {
    setState(() => _busy = true);
    final updated = _procedure.copyWith(
      isCompleted: completed,
      completedAt: completed ? DateTime.now() : null,
    );
    await AppPrefs.updateProcedureInHistory(updated.id, updated.toJson());
    if (!mounted) return;
    setState(() {
      _procedure = updated;
      _busy = false;
    });
  }

  Future<void> _addProcedureJournalEntry() async {
    final isCosmetic = (_procedure.category).toLowerCase().contains('cosmetic');
    final entry = await showJournalEntryComposer(
      context: context,
      contextTitle: _procedure.type,
      contextSubtitle: _procedure.provider.isNotEmpty
          ? '${_procedure.provider} • Recovery check-in'
          : 'Recovery check-in',
      showSwelling: isCosmetic,
    );
    if (entry == null || !mounted) return;
    final updated = _procedure.copyWith(
      journalEntries: [..._procedure.journalEntries, entry],
    );
    await AppPrefs.updateProcedureInHistory(updated.id, updated.toJson());
    if (!mounted) return;
    setState(() => _procedure = updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Journal entry saved')));
  }

  Future<void> _deleteProcedure() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Procedure?'),
        content: const Text(
          'This removes this procedure profile and its saved notes from history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await AppPrefs.removeProcedureFromHistory(_procedure.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _exportProcedureReportPdf() async {
    // ── Hybrid monetization gate ───────────────────────────────────────────────
    // Premium subscribers → generate immediately.
    // Free users          → require either an unlocked one-time purchase
    //                       for this specific procedure, or a Premium upgrade.
    final canGenerate = await ReportPurchase.canGenerateReport(_procedure.id);
    if (!canGenerate) {
      if (!mounted) return;
      final unlocked = await showReportPaywallSheet(
        context,
        procedureId: _procedure.id,
        procedureName: _procedure.type,
      );
      if (!mounted || !unlocked) return;
    }

    if (!mounted) return;
    final acceptedDisclaimer = await confirmReportShareDisclaimer(context);
    if (!mounted || !acceptedDisclaimer) return;

    // Gather premium insights and milestones
    final insightsRaw = await PremiumRecoveryService.loadProgressInsights();
    final insights =
        insightsRaw
            .whereType<ProgressPhotoInsight>()
            .where(
              (i) =>
                  (i.procedureType ?? '').toLowerCase() ==
                  _procedure.type.toLowerCase(),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final milestones = _customPlans
        .expand((p) => p.timelineMilestones)
        .take(8)
        .toList();

    final patientName = await AppPrefs.getUserName();

    // ── Debug: verify image bytes before PDF generation ──────────────────────
    final dbgBasePath = _baselineImagePath;
    final dbgLatPath = _latestImagePath;
    debugPrint(
      '[PDF Export] _baselineImagePath: ${dbgBasePath != null ? "${dbgBasePath.substring(0, dbgBasePath.length.clamp(0, 60))}..." : "NULL"}',
    );
    debugPrint(
      '[PDF Export] _latestImagePath:   ${dbgLatPath != null ? "${dbgLatPath.substring(0, dbgLatPath.length.clamp(0, 60))}..." : "NULL"}',
    );
    debugPrint('[PDF Export] _scans.length: ${_scans.length}');
    if (_scans.isNotEmpty) {
      final fp = _scans.first.imagePath ?? '';
      final lp = _scans.last.imagePath ?? '';
      debugPrint(
        '[PDF Export] scans.first.imagePath: ${fp.isEmpty ? "EMPTY" : "${fp.substring(0, fp.length.clamp(0, 60))}..."}',
      );
      debugPrint(
        '[PDF Export] scans.last.imagePath:  ${lp.isEmpty ? "EMPTY" : "${lp.substring(0, lp.length.clamp(0, 60))}..."}',
      );
    }

    // Always source PDF photos from scan history first, then fall back to
    // comparison-map paths if needed.
    ScanHistoryEntry? baselineEntry;
    try {
      baselineEntry = _scans.firstWhere(
        (s) => s.isBaseline && (s.imagePath ?? '').trim().isNotEmpty,
      );
    } catch (_) {
      baselineEntry = _scans.isNotEmpty ? _scans.last : null;
    }
    final latestEntry =
        _findScanById(_latestScanId) ??
        (_scans.isNotEmpty ? _scans.first : null);

    final baselineFromHistory = _decodeStoredImagePath(
      baselineEntry?.imagePath,
    );
    final latestFromHistory = _decodeStoredImagePath(latestEntry?.imagePath);
    final baselineFromComparison = _decodeStoredImagePath(_baselineImagePath);
    final latestFromComparison = _decodeStoredImagePath(_latestImagePath);

    final dbgBaselineBytes = baselineFromHistory ?? baselineFromComparison;
    final dbgLatestBytes = latestFromHistory ?? latestFromComparison;

    debugPrint(
      '[PDF Export] baseline source: ${baselineFromHistory != null ? "scan-history" : "comparison-map"}',
    );
    debugPrint(
      '[PDF Export] latest source:   ${latestFromHistory != null ? "scan-history" : "comparison-map"}',
    );
    debugPrint(
      '[PDF Export] _baselinePhotoBytes: ${dbgBaselineBytes?.length ?? "NULL"}',
    );
    debugPrint(
      '[PDF Export] _latestPhotoBytes:   ${dbgLatestBytes?.length ?? "NULL"}',
    );

    final input = ReportInput(
      procedure: _procedure,
      scans: _scans,
      beforePhotoBytes: dbgBaselineBytes,
      afterPhotoBytes: dbgLatestBytes,
      insights: insights,
      surgeonNotes: _procedure.notes.trim().isEmpty
          ? null
          : _procedure.notes.trim(),
      patientName: patientName,
      customPlanMilestones: milestones,
    );

    ReportResult result;
    try {
      result = await ReportService.generateAndSave(input);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to generate report: $e')));
      return;
    }

    await report_share.shareProfessionalReportPdf(
      result.pdfBytes,
      fileName: result.record.pdfFileName ?? 'recovery_report.pdf',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(kIsWeb ? 'Report downloaded.' : 'Report ready to share.'),
      ),
    );
  }

  // ignore: unused_element
  Widget _primaryPreview() {
    if (_procedure.afterPhotoBytes != null &&
        _procedure.afterPhotoBytes!.isNotEmpty) {
      return Image.memory(_procedure.afterPhotoBytes!, fit: BoxFit.cover);
    }
    if (_procedure.beforePhotoBytes != null &&
        _procedure.beforePhotoBytes!.isNotEmpty) {
      return Image.memory(_procedure.beforePhotoBytes!, fit: BoxFit.cover);
    }
    if (_procedure.taggedPhotos.isNotEmpty) {
      final ref = _procedure.taggedPhotos.last;
      if (ref.startsWith('http') || ref.startsWith('data:image')) {
        return Image.network(ref, fit: BoxFit.cover);
      }
      return buildLocalImagePreview(
        ref,
        width: double.infinity,
        height: 190,
        borderRadius: 14,
      );
    }
    return Center(
      child: Text(
        'No scan preview yet',
        style: TextStyle(
          color: MyApp.textBrown.withValues(alpha: 0.65),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMetricsProgressHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows, size: 14, color: MyApp.clinicalTeal),
              const SizedBox(width: 6),
              Text(
                'HOW TO READ THESE METRICS',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: MyApp.clinicalTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: MyApp.textBrown.withValues(alpha: 0.82),
              ),
              children: [
                const TextSpan(
                  text: 'Lower-is-better: ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(
                  text:
                      'Erythema, Skin Texture Quality, Rhytids, Pore Visibility, Hyperpigmentation, Inflammatory Response. ',
                ),
                TextSpan(
                  text: '↑ teal',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: MyApp.clinicalTeal,
                  ),
                ),
                const TextSpan(text: ' = improvement, '),
                TextSpan(
                  text: '↓ rose',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: MyApp.roseGold,
                  ),
                ),
                const TextSpan(
                  text:
                      ' = regression. Higher-is-better: Skin Laxity, Tone Uniformity, Hydration Level, Global Skin Quality.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    String? eyebrow,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: MyApp.roseGold.withValues(alpha: 0.14),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClinicalSectionHeader(icon: icon, title: title, eyebrow: eyebrow),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  // ── Surgeon plan helpers ───────────────────────────────────────────────────

  /// Persists surgeon notes (and optional plan photo), then refreshes the
  /// screen and shows a SnackBar.
  ///
  /// Pass [photoBytes] to attach/replace the surgeon plan photo.
  /// Pass [clearPhoto] = true to remove an existing plan photo.
  Future<void> _saveSurgeonNotes(
    String text, {
    Uint8List? photoBytes,
    bool clearPhoto = false,
  }) async {
    // Clamp to 4 000 chars — protects SharedPreferences from giant blobs
    final clamped = text.length > 4000 ? text.substring(0, 4000) : text;
    try {
      final updated = _procedure.copyWith(
        notes: clamped,
        surgeonPlanPhotoBytes: photoBytes,
        clearSurgeonPlanPhoto: clearPhoto,
      );
      await AppPrefs.updateProcedureInHistory(_procedure.id, updated.toJson());
      if (!mounted) return;
      setState(() => _procedure = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('Surgeon instructions saved successfully.')),
            ],
          ),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  /// Extracts readable text from a picked file based on its extension.
  /// Binary formats (PDF, JPEG, PNG, DOC) return a clean placeholder instead
  /// of decoded binary garbage.
  static String _extractFileText(String name, Uint8List bytes) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'txt':
      case 'rtf':
      case 'csv':
        // Genuine text — decode UTF-8 and cap to 4 000 chars
        try {
          final decoded = utf8.decode(bytes, allowMalformed: true);
          return decoded.length > 4000 ? decoded.substring(0, 4000) : decoded;
        } catch (_) {
          return '--- Attached: $name ---\n(Could not read file text.)';
        }
      case 'pdf':
      case 'doc':
      case 'docx':
        return '📄 Document attached: $name\n\n'
            'Full text extraction is not available on this device. '
            'Please type or paste the key instructions from your surgeon\'s document below.';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'heic':
        return '📷 Image attached: $name\n\n'
            'Text recognition from images is not available here. '
            'Please type or paste the instructions visible in your photo below.';
      default:
        return '--- Attached: $name ---\n(Unsupported file type — please type your notes below.)';
    }
  }

  Future<Uint8List?> _readPickedImageBytes(XFile picked) async {
    final fileName = picked.name;
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.isNotEmpty) {
        final prepared = await prepareWebUploadImage(bytes, fileName: fileName);
        if (prepared.isSuccess) return prepared.image!.bytes;
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(prepared.errorMessage!)));
        }
        return null;
      }
    } catch (_) {
      // Fall through to web path decoding fallback.
    }

    if (kIsWeb) {
      final path = picked.path;
      if (path.startsWith('data:image')) {
        try {
          final parts = path.split(',');
          if (parts.length > 1) {
            final decoded = base64Decode(parts[1]);
            final prepared = await prepareWebUploadImage(
              decoded,
              fileName: fileName,
            );
            if (prepared.isSuccess) return prepared.image!.bytes;
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(prepared.errorMessage!)));
            }
          }
        } catch (_) {}
      }
    }
    return null;
  }

  String _webPhotoErrorMessage() {
    return 'We could not process the selected image. '
        'Please choose a valid photo file and try again.';
  }

  Future<void> _showSurgeonPlanEditor() async {
    final ctrl = TextEditingController(text: _procedure.notes);
    String? importedFileName;
    bool saving = false;
    bool processingOcr = false;
    bool ocrError = false;

    // Photo state — seeded with any previously saved surgeon plan photo so it
    // remains visible (and editable) when the user re-opens the modal.
    Uint8List? photoBytes = _procedure.surgeonPlanPhotoBytes;
    final picker = ImagePicker();

    Future<void> capturePhoto(StateSetter setInner, ImageSource source) async {
      try {
        final picked = await picker.pickImage(
          source: source,
          imageQuality: 88,
          maxWidth: 2400,
        );
        if (picked == null) return;
        final bytes = await _readPickedImageBytes(picked);
        if (bytes == null || bytes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(_webPhotoErrorMessage())));
          }
          return;
        }
        setInner(() {
          photoBytes = bytes;
          importedFileName = picked.name;
          ocrError = false;
        });
        // Best-effort OCR — if it succeeds and the text field is empty, prefill it.
        setInner(() => processingOcr = true);
        try {
          final text = await OcrService.performOcr(bytes, picked.name);
          if (text != null && text.trim().isNotEmpty) {
            if (ctrl.text.trim().isEmpty) {
              ctrl.text = text;
            }
            setInner(() {
              processingOcr = false;
              ocrError = false;
            });
          } else {
            setInner(() {
              processingOcr = false;
              ocrError = ctrl.text.trim().isEmpty;
            });
          }
        } catch (_) {
          setInner(() {
            processingOcr = false;
            ocrError = ctrl.text.trim().isEmpty;
          });
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_webPhotoErrorMessage())));
        }
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final busy = saving || processingOcr;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: MyApp.champagne,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: MyApp.textBrown.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header row
                    Row(
                      children: [
                        Icon(
                          Icons.assignment_outlined,
                          color: MyApp.roseGold,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Surgeon's Recovery Plan",
                            style: MyApp.cardTitleStyle(),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    Text(
                      'Take a photo of your printed instructions, browse a file, '
                      'or paste/type the key points below.',
                      style: TextStyle(
                        fontSize: 12,
                        color: MyApp.textBrown.withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Primary capture actions ─────────────────────────
                    // Take Photo is the prominent primary action; Browse File
                    // and Choose from Library sit beside it as secondary.
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: ElevatedButton.icon(
                            onPressed: busy || kIsWeb
                                ? null
                                : () => capturePhoto(
                                    setInner,
                                    ImageSource.camera,
                                  ),
                            icon: const Icon(
                              Icons.photo_camera_outlined,
                              size: 17,
                            ),
                            label: Text(
                              photoBytes == null
                                  ? 'Take Photo'
                                  : 'Retake Photo',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: MyApp.roseGold,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => capturePhoto(
                                    setInner,
                                    ImageSource.gallery,
                                  ),
                            icon: const Icon(
                              Icons.photo_library_outlined,
                              size: 15,
                            ),
                            label: const Text('Library'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: MyApp.roseGold,
                              side: BorderSide(
                                color: MyApp.roseGold.withValues(alpha: 0.6),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              textStyle: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                try {
                                  final result = await FilePicker.platform
                                      .pickFiles(
                                        type: FileType.custom,
                                        allowedExtensions: [
                                          'txt',
                                          'pdf',
                                          'doc',
                                          'docx',
                                          'rtf',
                                          'jpg',
                                          'jpeg',
                                          'png',
                                        ],
                                        withData: true,
                                      );
                                  if (result != null &&
                                      result.files.isNotEmpty) {
                                    final file = result.files.first;
                                    if (file.bytes != null) {
                                      if (OcrService.isImageFile(file.name)) {
                                        final prepared =
                                            await prepareWebUploadImage(
                                              file.bytes!,
                                              fileName: file.name,
                                            );
                                        if (!prepared.isSuccess) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  prepared.errorMessage!,
                                                ),
                                              ),
                                            );
                                          }
                                          return;
                                        }
                                        final normalizedBytes =
                                            prepared.image!.bytes;
                                        setInner(() {
                                          processingOcr = true;
                                          ocrError = false;
                                          importedFileName = file.name;
                                          photoBytes = normalizedBytes;
                                        });
                                        final text =
                                            await OcrService.performOcr(
                                              normalizedBytes,
                                              file.name,
                                            );
                                        if (text != null && text.isNotEmpty) {
                                          ctrl.text = text;
                                          setInner(() => processingOcr = false);
                                        } else {
                                          setInner(() {
                                            processingOcr = false;
                                            ocrError = true;
                                          });
                                        }
                                      } else {
                                        ctrl.text = _extractFileText(
                                          file.name,
                                          file.bytes!,
                                        );
                                        setInner(() {
                                          importedFileName = file.name;
                                          ocrError = false;
                                        });
                                      }
                                    } else if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _webPhotoErrorMessage(),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                } catch (_) {}
                              },
                        icon: const Icon(Icons.upload_file_outlined, size: 15),
                        label: const Text(
                          'Browse File (TXT, PDF, DOC, JPG, PNG)',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MyApp.roseGold,
                          side: BorderSide(
                            color: MyApp.roseGold.withValues(alpha: 0.45),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          textStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    // ── Photo preview ───────────────────────────────────
                    if (photoBytes != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: MyApp.roseGold.withValues(alpha: 0.28),
                            width: 0.9,
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                photoBytes!,
                                width: 84,
                                height: 84,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 14,
                                        color: Colors.green[700],
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Photo attached',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Saved with your instructions and viewable any time.',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: MyApp.textBrown.withValues(
                                        alpha: 0.65,
                                      ),
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      TextButton.icon(
                                        onPressed: busy || kIsWeb
                                            ? null
                                            : () => capturePhoto(
                                                setInner,
                                                ImageSource.camera,
                                              ),
                                        icon: const Icon(
                                          Icons.refresh,
                                          size: 14,
                                        ),
                                        label: const Text('Retake'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: MyApp.roseGold,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          minimumSize: const Size(0, 32),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      TextButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => setInner(() {
                                                photoBytes = null;
                                                importedFileName = null;
                                              }),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 14,
                                        ),
                                        label: const Text('Remove'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.red[700],
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          minimumSize: const Size(0, 32),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
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
                    ],

                    // Status row — OCR spinner / error / import success
                    if (processingOcr) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: MyApp.roseGold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Reading text from image…',
                            style: TextStyle(
                              fontSize: 12,
                              color: MyApp.textBrown.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ] else if (ocrError) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_outlined,
                            size: 14,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Text recognition failed. The photo is saved — '
                              'type any key details below.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else if (importedFileName != null &&
                        photoBytes == null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 14,
                            color: Colors.green[700],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Imported: $importedFileName',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Text field
                    TextField(
                      controller: ctrl,
                      maxLines: 7,
                      enabled: !processingOcr,
                      style: TextStyle(color: MyApp.textBrown, height: 1.4),
                      decoration: InputDecoration(
                        hintText:
                            'E.g. "Avoid sun exposure for 2 weeks. Prescribed ointment twice '
                            'daily. Follow-up in 4 weeks..."',
                        hintStyle: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.40),
                          fontSize: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: MyApp.roseGold.withValues(alpha: 0.35),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: MyApp.roseGold),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: MyApp.roseGold.withValues(alpha: 0.30),
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.55),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Improve Text button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () {
                                final cleaned = OcrService.cleanText(ctrl.text);
                                ctrl.text = cleaned;
                                setInner(() {});
                              },
                        icon: const Icon(
                          Icons.auto_fix_high_outlined,
                          size: 16,
                        ),
                        label: const Text('Clean Up Text'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MyApp.roseGold,
                          side: BorderSide(
                            color: MyApp.roseGold.withValues(alpha: 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Save button — shows spinner while saving, disabled during OCR
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final text = ctrl.text.trim();
                                final hadPhoto =
                                    _procedure.surgeonPlanPhotoBytes != null;
                                final clearPhoto =
                                    hadPhoto && photoBytes == null;
                                setInner(() => saving = true);
                                await _saveSurgeonNotes(
                                  text,
                                  photoBytes: photoBytes,
                                  clearPhoto: clearPhoto,
                                );
                                if (ctx.mounted) Navigator.of(ctx).pop();
                              },
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: Text(saving ? 'Saving…' : 'Save Instructions'),
                        style: MyApp.primaryGoldButton,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BBL Recovery Metrics — first-class recovery intelligence for BBL/Lipo
  // ─────────────────────────────────────────────────────────────────────────
  static const Color _bblAccent = Color(0xFFAD1457); // deep rose — BBL brand

  static const List<Map<String, dynamic>> _bblMetricDefs = [
    {
      'key': 'fatRetentionPct',
      'label': 'Fat Retention %',
      'icon': Icons.water_drop_outlined,
      'unit': '%',
      'min': 0.0,
      'max': 100.0,
      'lowerBetter': false,
      'hint': 'Estimated % of transferred fat volume that survived',
      'fullHint':
          'Surgeons intentionally over-transfer fat (by 30–50%) anticipating 20–40% natural reabsorption. '
          'A healthy final result of 60–80% retention is the clinical gold standard. '
          'Track this over time — your trend matters more than any single reading.',
    },
    {
      'key': 'volumeSatisfaction',
      'label': 'Volume Satisfaction',
      'icon': Icons.thumb_up_alt_outlined,
      'unit': '/10',
      'min': 0.0,
      'max': 10.0,
      'lowerBetter': false,
      'hint': 'How satisfied are you with your current volume result',
      'fullHint':
          'Weeks 1–8 feature significant swelling that can make shape look different from the final outcome. '
          'The true result emerges at months 4–6 as all edema resolves. '
          'Rate your honest feeling today — the upward trend over time tells the real story.',
    },
    {
      'key': 'contourEvenness',
      'label': 'Contour Evenness',
      'icon': Icons.waves_outlined,
      'unit': '/10',
      'min': 0.0,
      'max': 10.0,
      'lowerBetter': false,
      'hint':
          '10 = perfectly smooth, 0 = significant irregularities or lumpiness',
      'fullHint':
          'Fibrosis (lumpiness under the skin) is normal in weeks 2–8 and is very treatable. '
          'Manual lymphatic drainage (MLD) sessions dramatically improve contour evenness. '
          'Track this weekly — you should see steady improvement with consistent MLD.',
    },
    {
      'key': 'fibrosisLevel',
      'label': 'Fibrosis / Firmness',
      'icon': Icons.medical_services_outlined,
      'unit': '/10',
      'min': 0.0,
      'max': 10.0,
      'lowerBetter': true,
      'hint': 'Hardness or lumpiness in treated areas — lower is better',
      'fullHint':
          'Fibrosis is your body\'s normal healing response after fat removal. It peaks weeks 3–6 and '
          'then gradually softens. MLD massage (by a certified therapist) is the gold-standard treatment. '
          'This score should decrease steadily through months 2–4.',
    },
  ];

  String _bblInterpretation(String key, double value) {
    switch (key) {
      case 'fatRetentionPct':
        if (value >= 80) {
          return 'Outstanding — you\'re in the top tier of outcomes. '
              'Your positioning discipline and nutrition are making a real difference. '
              'Keep the no-pressure protocol through Week 8 to lock in these results.';
        }
        if (value >= 65) {
          return 'Excellent — right in the ideal 60–80% clinical range. '
              'Your BBL pillow compliance and compression garment are working. '
              'Maintain this protocol through Month 2 for best final contour.';
        }
        if (value >= 50) {
          return 'Below the clinical target. Review: are you using your BBL pillow '
              'for every seated moment? Any buttock pressure reduces fat survival. '
              'Focus on protein intake (1.4g/kg/day) and strict positioning.';
        }
        return 'Worth a conversation with your surgeon. Lower retention can result from '
            'early sitting pressure, insufficient nutrition, or natural healing variation. '
            'Do not sit directly on your buttocks without your BBL foam cushion.';
      case 'volumeSatisfaction':
        if (value >= 8) {
          return 'Wonderful! Remember this continues to improve — '
              'swelling resolves through Month 6 and your final result will be even better.';
        }
        if (value >= 6) {
          return 'Good satisfaction — and remember that weeks 1–8 swelling '
              'can significantly distort shape perception. Volume and symmetry '
              'improve continuously through Months 4–6.';
        }
        if (value >= 4) {
          return 'Neutral satisfaction is completely normal right now. '
              'Trust the process: final results aren\'t visible until Month 4–6 '
              'as all surgical swelling fully resolves.';
        }
        return 'Recovery can feel discouraging. This phase is one of the hardest — '
            'please discuss any concerns with your surgeon before drawing conclusions. '
            'The "ugly duckling" phase (weeks 2–8) is real and temporary.';
      case 'contourEvenness':
        if (value >= 8) {
          return 'Excellent smooth contour! Your lymphatic drainage routine is clearly working. '
              'Keep your scheduled MLD sessions to maintain this.';
        }
        if (value >= 6) {
          return 'Good contour with minor irregularities — these typically resolve with '
              'consistent lymphatic drainage by Weeks 6–8.';
        }
        if (value >= 4) {
          return 'Moderate irregularity (fibrosis is developing) — increase MLD to '
              '2–3 sessions per week. This is very normal and highly treatable.';
        }
        return 'Significant lumpiness — book a professional lymphatic drainage session this week '
            'and inform your surgeon. Do not attempt aggressive self-massage.';
      case 'fibrosisLevel':
        if (value <= 2) {
          return 'Minimal fibrosis — your tissue is healing beautifully. '
              'Continue preventive lymphatic massage as scheduled to stay on track.';
        }
        if (value <= 4) {
          return 'Mild fibrosis — completely expected at this stage. '
              'Regular MLD and oral Arnica pellets will steadily resolve this over the coming weeks.';
        }
        if (value <= 6) {
          return 'Moderate firmness — increase MLD to 3 sessions per week. '
              'Wear your compression garment as prescribed and avoid aggressive self-massage.';
        }
        return 'Significant hardening — book an urgent lymphatic drainage session. '
            'Avoid self-massaging hard areas and notify your surgeon at your next visit.';
      default:
        return '';
    }
  }

  String _bblPhaseLabel(int daysSince) {
    if (daysSince <= 5) return 'Peak Swelling Phase';
    if (daysSince <= 14) return 'Early Recovery';
    if (daysSince <= 42) return 'Active Healing Phase';
    if (daysSince <= 75) return 'Contour Refinement';
    if (daysSince <= 150) return 'Final Shaping Phase';
    return 'Results Stabilizing';
  }

  String _bblPhaseActionTip(int daysSince) {
    // For BBL: include fat-graft-specific advice (pillow protocol, faja, fat survival)
    if (_isBBL) {
      if (daysSince <= 5) {
        return 'No sitting on buttocks — foam pillow under thighs at ALL times when seated. '
            'Sleep prone or on your side only. Stage 1 faja 22+ hrs/day.';
      }
      if (daysSince <= 14) {
        return 'Continue BBL pillow protocol. Light walking reduces DVT risk. '
            'Fat graft blood supply establishing — positioning compliance is critical right now.';
      }
      if (daysSince <= 42) {
        return 'Fibrosis is actively forming — book MLD sessions 2–3x per week starting now. '
            'Transition to Stage 2 faja around Week 3. Protein intake: 1.4g/kg/day minimum.';
      }
      if (daysSince <= 75) {
        return 'Positioning restrictions ease after Week 8. Continue Stage 2 faja and '
            'weekly MLD through Month 3. Final contour is becoming clearer.';
      }
      if (daysSince <= 150) {
        return 'Most swelling has resolved. SPF 50 on all incision sites mandatory. '
            'Schedule a provider assessment — touch-up options can be discussed if needed.';
      }
      return 'Results are approaching their final state. Discuss any remaining asymmetry '
          'or volume concerns with your surgeon. Secondary procedures are typically assessed at 6+ months.';
    }

    // Generic body contouring (Liposuction, Tummy Tuck, Arm/Thigh contouring, etc.)
    if (daysSince <= 5) {
      return 'Wear your compression garment continuously (22+ hrs/day). '
          'Elevate the treated area when resting to reduce swelling. '
          'Avoid strenuous activity and follow your surgeon\'s movement guidelines.';
    }
    if (daysSince <= 14) {
      return 'Continue compression garment wear. Light walking is encouraged. '
          'Follow up with your surgeon as scheduled and watch incision sites for signs of infection.';
    }
    if (daysSince <= 42) {
      return 'Fibrosis may be developing — book manual lymphatic drainage (MLD) sessions 2–3x per week. '
          'Continue compression wear and stay well hydrated. Protein intake: 1.4g/kg/day minimum.';
    }
    if (daysSince <= 75) {
      return 'Most acute swelling has resolved. Continue monthly MLD. '
          'Contour is becoming more defined — final results emerge at months 4–6.';
    }
    if (daysSince <= 150) {
      return 'Swelling is largely resolved. Protect incision sites with SPF 50. '
          'Discuss any remaining firmness or contour concerns at your follow-up appointment.';
    }
    return 'Results are approaching their final state. '
        'Discuss any residual irregularity with your surgeon — refinement options can be assessed at 6+ months.';
  }

  Color _bblMetricColor(String key, double value) {
    final bool lowerBetter = key == 'fibrosisLevel';
    if (lowerBetter) {
      if (value <= 3) return const Color(0xFF2E7D32);
      if (value <= 6) return const Color(0xFFF57F17);
      return const Color(0xFFC62828);
    } else {
      final max = key == 'fatRetentionPct' ? 100.0 : 10.0;
      final ratio = value / max;
      if (ratio >= 0.70) return const Color(0xFF2E7D32);
      if (ratio >= 0.45) return const Color(0xFFF57F17);
      return const Color(0xFFC62828);
    }
  }

  String _bblTrendLabel(DateTime procedureStart, DateTime assessmentTime) {
    final days = assessmentTime.difference(procedureStart).inDays + 1;
    if (days <= 7) return 'Wk 1';
    if (days <= 14) return 'Wk 2';
    if (days <= 21) return 'Wk 3';
    if (days <= 28) return 'Wk 4';
    if (days <= 42) return 'Wk 6';
    if (days <= 56) return 'Wk 8';
    final months = (days / 30).floor();
    return 'M$months';
  }

  Future<void> _showBBLMetricsEditor() async {
    final defaults = {
      'fatRetentionPct': 65.0,
      'volumeSatisfaction': 6.0,
      'contourEvenness': 6.0,
      'fibrosisLevel': 3.0,
    };
    final working = Map<String, double>.from(_bblAssessment ?? defaults);
    final previous = _bblAssessmentPrevious;
    final daysSince =
        DateTime.now().difference(_procedure.startDate).inDays + 1;
    final phaseLabel = _bblPhaseLabel(daysSince);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) {
            return StatefulBuilder(
              builder: (ctx, setInner) {
                Future<void> openDetail(Map<String, dynamic> def) async {
                  final key = def['key'] as String;
                  final result = await Navigator.of(ctx).push<double>(
                    MaterialPageRoute(
                      builder: (_) => RecoveryMetricDetailScreen(
                        procedureId: _procedure.id,
                        procedureStartDate: _procedure.startDate,
                        isBBL: _isBBL,
                        metricDef: def,
                        currentValue:
                            working[key] ??
                            ((def['min'] as double) + (def['max'] as double)) /
                                2,
                        previousValue: previous?[key],
                      ),
                    ),
                  );
                  if (result == null) return;
                  final prevSnapshot = _bblAssessment != null
                      ? Map<String, double>.from(_bblAssessment!)
                      : null;
                  working[key] = result;
                  await AppPrefs.saveBBLAssessment(_procedure.id, working);
                  final hist = await AppPrefs.getBBLAssessmentHistory(
                    _procedure.id,
                  );
                  if (mounted) {
                    setState(() {
                      _bblAssessment = Map<String, double>.from(working);
                      _bblAssessmentPrevious = prevSnapshot;
                      _bblHistory = hist;
                    });
                  }
                  setInner(() {});
                }

                return Container(
                  decoration: BoxDecoration(
                    color: MyApp.champagne,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      // ── Drag handle ─────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: MyApp.clinicalSlate.withValues(alpha: 0.32),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          children: [
                            // ── Header ───────────────────────────────
                            ClinicalSectionHeader(
                              icon: Icons.monitor_heart_outlined,
                              title: 'Recovery Assessment',
                              eyebrow: 'Day $daysSince · $phaseLabel',
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 44,
                                right: 4,
                                bottom: 6,
                              ),
                              child: Text(
                                'Tap a metric to see week-by-week guidance, '
                                'practical tips, and add your own notes.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: MyApp.clinicalSlate,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // ── Metric cards ────────────────────────
                            for (final def in _activeMetricDefs) ...[
                              _metricListCard(
                                def: def,
                                value:
                                    working[def['key'] as String] ??
                                    (((def['min'] as double) +
                                            (def['max'] as double)) /
                                        2),
                                previousValue: previous?[def['key'] as String],
                                onTap: () => openDetail(def),
                              ),
                              const SizedBox(height: 12),
                            ],
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: MyApp.clinicalNavy,
                                  side: BorderSide(
                                    color: MyApp.clinicalSlate.withValues(
                                      alpha: 0.28,
                                    ),
                                    width: 0.9,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: const Text('Done'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Scannable metric card used in the main assessment list ─────────────
  Widget _metricListCard({
    required Map<String, dynamic> def,
    required double value,
    required double? previousValue,
    required VoidCallback onTap,
  }) {
    final key = def['key'] as String;
    final label = def['label'] as String;
    final icon = def['icon'] as IconData;
    final lowerBetter = def['lowerBetter'] as bool;
    final color = _bblMetricColor(key, value);
    final display = key == 'fatRetentionPct'
        ? '${value.round()}%'
        : value.toStringAsFixed(1);
    final hint = (def['hint'] as String?) ?? '';

    final hasChange =
        previousValue != null && (value - previousValue).abs() >= 0.5;
    final improving = hasChange
        ? (lowerBetter ? value < previousValue : value > previousValue)
        : false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.05),
          child: Row(
            children: [
              // Icon tile
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: color.withValues(alpha: 0.28),
                    width: 0.7,
                  ),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              // Label + summary
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
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: MyApp.clinicalNavy,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                        // Trend arrow
                        if (hasChange) ...[
                          Icon(
                            improving
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            size: 16,
                            color: improving
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                          ),
                          const SizedBox(width: 4),
                        ],
                        // Score pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: color.withValues(alpha: 0.32),
                              width: 0.6,
                            ),
                          ),
                          child: Text(
                            display,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: color,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: MyApp.clinicalSlate,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: MyApp.clinicalSlate.withValues(alpha: 0.55),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── BBL secondary metric tile (compact card for grid layout) ─────────────
  Widget _bblSecondaryMetricTile(String key, Map<String, double> assessment) {
    final def = _bblMetricDefs.firstWhere(
      (d) => d['key'] == key,
      orElse: () => <String, dynamic>{},
    );
    if (def.isEmpty) return const SizedBox.shrink();
    final label = def['label'] as String;
    final icon = def['icon'] as IconData;
    final min = def['min'] as double;
    final max = def['max'] as double;
    final val = assessment[key] ?? ((min + max) / 2);
    final color = _bblMetricColor(key, val);
    final ratio = (val - min) / (max - min);
    final display = key == 'fatRetentionPct'
        ? '${val.round()}%'
        : val.toStringAsFixed(1);
    final isLowerBetter = def['lowerBetter'] as bool;
    final prev = _bblAssessmentPrevious?[key];
    final hasChange = prev != null && (val - prev).abs() >= 0.5;
    final improved = hasChange
        ? (isLowerBetter ? val < prev : val > prev)
        : false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: MyApp.textBrown,
                  ),
                ),
              ),
              if (hasChange)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    improved ? Icons.trending_up : Icons.trending_down,
                    size: 13,
                    color: improved
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: color.withValues(alpha: 0.13),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                display,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _bblInterpretation(key, val),
            style: TextStyle(
              fontSize: 10.5,
              color: MyApp.textBrown.withValues(alpha: 0.68),
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Volume Retention Trend mini chart ─────────────────────────────────────
  Widget _buildVolumeRetentionTrend() {
    final entries = _bblHistory.where((e) {
      final m = e['metrics'];
      return m is Map && m.containsKey('fatRetentionPct');
    }).toList();
    if (entries.length < 2) return const SizedBox.shrink();

    // Subsample to max 6 evenly-spaced entries (always include first and last)
    final List<Map<String, dynamic>> displayed;
    if (entries.length <= 6) {
      displayed = entries;
    } else {
      displayed = [
        entries.first,
        for (int i = 1; i <= 4; i++)
          entries[((entries.length - 1) * i / 5).round().clamp(
            1,
            entries.length - 2,
          )],
        entries.last,
      ];
    }

    double maxPct = 0;
    for (final e in displayed) {
      final m = e['metrics'] as Map?;
      final pct = ((m?['fatRetentionPct'] ?? 0.0) as num).toDouble();
      if (pct > maxPct) maxPct = pct;
    }
    final maxPctDisplay = maxPct > 0 ? maxPct : 100.0;
    const maxBarHeight = 52.0;

    final firstPct =
        ((((displayed.first['metrics'] as Map?))?['fatRetentionPct'] ?? 0.0)
                as num)
            .toDouble();
    final lastPct =
        ((((displayed.last['metrics'] as Map?))?['fatRetentionPct'] ?? 0.0)
                as num)
            .toDouble();
    final trendUp = lastPct > firstPct + 0.5;
    final trendFlat = (lastPct - firstPct).abs() <= 0.5;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, size: 16, color: _bblAccent),
              const SizedBox(width: 6),
              Text(
                'Fat Retention Trend',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: MyApp.textBrown,
                ),
              ),
              const Spacer(),
              Icon(
                trendFlat
                    ? Icons.trending_flat
                    : (trendUp ? Icons.trending_up : Icons.trending_down),
                size: 15,
                color: trendFlat
                    ? const Color(0xFFF57F17)
                    : (trendUp
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFC62828)),
              ),
              const SizedBox(width: 4),
              Text(
                trendFlat
                    ? 'Stabilizing'
                    : (trendUp
                          ? '+${(lastPct - firstPct).round()}% improvement'
                          : '${(firstPct - lastPct).round()}% decrease'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: trendFlat
                      ? const Color(0xFFF57F17)
                      : (trendUp
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFC62828)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: displayed.map((entry) {
              final m = entry['metrics'] as Map?;
              final pct = ((m?['fatRetentionPct'] ?? 0.0) as num).toDouble();
              final barH = (pct / maxPctDisplay) * maxBarHeight;
              final barColor = _bblMetricColor('fatRetentionPct', pct);
              final ts = entry['timestamp'] as String?;
              String lbl = '—';
              if (ts != null) {
                try {
                  lbl = _bblTrendLabel(
                    _procedure.startDate,
                    DateTime.parse(ts),
                  );
                } catch (_) {}
              }
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${pct.round()}%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: barColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    height: barH.clamp(4.0, maxBarHeight),
                    width: 30,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lbl,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: MyApp.textBrown.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'Clinical target: 60–80% retention',
                style: TextStyle(
                  fontSize: 10,
                  color: MyApp.textBrown.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBBLRecoveryMetricsCard() {
    final assessment = _bblAssessment;
    final daysSince =
        DateTime.now().difference(_procedure.startDate).inDays + 1;
    final phase = _bblPhaseLabel(daysSince);
    final phaseTip = _bblPhaseActionTip(daysSince);
    final fatPct = assessment?['fatRetentionPct'] ?? 0.0;
    final fatColor = assessment != null
        ? _bblMetricColor('fatRetentionPct', fatPct)
        : Colors.grey.shade400;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _bblAccent.withValues(alpha: 0.28), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card header ────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _bblAccent.withValues(alpha: 0.18),
                        _bblAccent.withValues(alpha: 0.07),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_outlined,
                    color: _bblAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_procedure.type} Recovery Tracking',
                        style: MyApp.cardTitleStyle(),
                      ),
                      Text(
                        'Body Contouring · Specialized Intelligence',
                        style: TextStyle(
                          fontSize: 11,
                          color: MyApp.textBrown.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _bblAccent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Day $daysSince',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _bblAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      phase,
                      style: TextStyle(
                        fontSize: 10,
                        color: MyApp.textBrown.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── FAT RETENTION HERO GAUGE (BBL only) ─────────────────────────
            if (_isBBL) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      fatColor.withValues(alpha: 0.07),
                      fatColor.withValues(alpha: 0.02),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: fatColor.withValues(
                      alpha: assessment != null ? 0.22 : 0.10,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Fat Retention',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.5,
                        color: MyApp.textBrown.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Circular gauge ring
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: CircularProgressIndicator(
                            value: assessment != null ? (fatPct / 100.0) : 0,
                            backgroundColor: Colors.grey.withValues(
                              alpha: 0.12,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(fatColor),
                            strokeWidth: 16,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              assessment != null ? '${fatPct.round()}%' : '—',
                              style: TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                color: assessment != null
                                    ? fatColor
                                    : Colors.grey.shade400,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'FAT RETAINED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: MyApp.textBrown.withValues(alpha: 0.48),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Clinical range note
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 13,
                          color: const Color(
                            0xFF2E7D32,
                          ).withValues(alpha: 0.80),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Clinical target range: 60–80% retention',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MyApp.textBrown.withValues(alpha: 0.60),
                          ),
                        ),
                      ],
                    ),
                    if (assessment != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: fatColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _bblInterpretation('fatRetentionPct', fatPct),
                          style: TextStyle(
                            fontSize: 12,
                            color: MyApp.textBrown.withValues(alpha: 0.82),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ), // closes Container
            ], // end if (_isBBL) — fat retention section
            const SizedBox(height: 14),

            // ── VOLUME RETENTION TREND (BBL only, requires >1 history entry) ─
            if (_isBBL && _bblHistory.length > 1) ...[
              _buildVolumeRetentionTrend(),
              const SizedBox(height: 14),
            ],

            // ── SECONDARY METRICS GRID ──────────────────────────────────────
            if (assessment != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _bblSecondaryMetricTile(
                      'contourEvenness',
                      assessment,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _bblSecondaryMetricTile('fibrosisLevel', assessment),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _bblSecondaryMetricTile('volumeSatisfaction', assessment),
              const SizedBox(height: 14),
            ],

            // ── RECOVERY PHASE TIP ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _bblAccent.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _bblAccent.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.tips_and_updates_outlined,
                    size: 16,
                    color: _bblAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phase,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: _bblAccent,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          phaseTip,
                          style: TextStyle(
                            fontSize: 12,
                            color: MyApp.textBrown.withValues(alpha: 0.80),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── EMPTY STATE ─────────────────────────────────────────────────
            if (assessment == null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _bblAccent.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _bblAccent.withValues(alpha: 0.14)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start tracking your ${_procedure.type} recovery metrics',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: MyApp.textBrown,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isBBL
                          ? 'Log Fat Retention %, Contour Evenness, Fibrosis level, and Volume Satisfaction — '
                                'the metrics that define a truly successful BBL outcome. '
                                'These go beyond what any camera scan captures, and tracking them weekly '
                                'shows you the trend toward your final result.'
                          : 'Log Contour Evenness, Fibrosis level, and Volume Satisfaction — '
                                'the metrics that define a successful ${_procedure.type} outcome. '
                                'These go beyond what any camera scan captures, and tracking them weekly '
                                'shows you the trend toward your final result.',
                      style: TextStyle(
                        fontSize: 12,
                        color: MyApp.textBrown.withValues(alpha: 0.70),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              const SizedBox(height: 12),
            ],

            // ── ACTION BUTTON ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showBBLMetricsEditor,
                icon: Icon(
                  assessment == null ? Icons.add_chart : Icons.edit_outlined,
                  size: 18,
                ),
                label: Text(
                  assessment == null
                      ? 'Log First Assessment'
                      : 'Update Today\'s Assessment',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _bblAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSurgeonPlanSection() {
    final hasNotes = _procedure.notes.trim().isNotEmpty;
    final milestones = _procedure.timelineMilestones;
    final hasReminders = _procedure.customReminders.isNotEmpty;
    final hasMilestones = milestones.isNotEmpty;
    final planPhoto = _procedure.surgeonPlanPhotoBytes;
    final hasPhoto = planPhoto != null;
    final hasSomething = hasNotes || hasReminders || hasMilestones || hasPhoto;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: hasSomething
              ? MyApp.roseGold.withValues(alpha: 0.18)
              : MyApp.roseGold.withValues(alpha: 0.36),
          width: hasSomething ? 0.8 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ───────────────────────────────────────────────
            Row(
              children: [
                const Expanded(
                  child: ClinicalSectionHeader(
                    icon: Icons.assignment_outlined,
                    title: "Surgeon's Recovery Plan",
                    eyebrow: 'Post-op instructions & milestones',
                  ),
                ),
                if (hasSomething)
                  IconButton(
                    onPressed: _showSurgeonPlanEditor,
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: MyApp.roseGold,
                    ),
                    tooltip: 'Edit instructions',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Filled state ─────────────────────────────────────────────
            if (hasSomething) ...[
              if (hasPhoto) ...[
                _buildSurgeonPlanPhotoTile(planPhoto),
                if (hasNotes || hasReminders || hasMilestones)
                  const SizedBox(height: 12),
              ],
              if (hasNotes)
                Text(
                  _procedure.notes.trim(),
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.82),
                    height: 1.4,
                  ),
                ),
              if (hasReminders) ...[
                if (hasNotes) const SizedBox(height: 10),
                ..._procedure.customReminders.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: MyApp.roseGold,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(r)),
                      ],
                    ),
                  ),
                ),
              ],
              if (hasMilestones) ...[
                if (hasNotes || hasReminders) const SizedBox(height: 8),
                Text(
                  'Next milestone: ${milestones.first.label}'
                  ' (${_formatDate(milestones.first.expectedDate)})',
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ]
            // ── Empty state ──────────────────────────────────────────────
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: MyApp.roseGold.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.upload_file_outlined,
                      color: MyApp.roseGold,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No instructions added yet',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: MyApp.textBrown,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Add your surgeon\'s post-op care notes, '
                          'restrictions, medications, and follow-up dates.',
                          style: TextStyle(
                            fontSize: 12,
                            color: MyApp.textBrown.withValues(alpha: 0.58),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showSurgeonPlanEditor,
                  icon: const Icon(Icons.photo_camera_outlined, size: 17),
                  label: const Text('Take Photo of Plan'),
                  style: MyApp.primaryGoldButton,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showSurgeonPlanEditor,
                      icon: const Icon(Icons.upload_file_outlined, size: 16),
                      label: const Text('Browse File'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyApp.roseGold,
                        side: BorderSide(color: MyApp.roseGold),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showSurgeonPlanEditor,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Type Notes'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyApp.roseGold,
                        side: BorderSide(color: MyApp.roseGold),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact, tappable tile that previews the surgeon plan photo and opens
  /// a full-screen viewer when tapped. Sits at the top of the filled-state
  /// surgeon plan section.
  Widget _buildSurgeonPlanPhotoTile(Uint8List bytes) {
    return InkWell(
      onTap: () => _openSurgeonPlanPhotoViewer(bytes),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: MyApp.roseGold.withValues(alpha: 0.26),
            width: 0.9,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                bytes,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan Photo Attached',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: MyApp.textBrown,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to view your surgeon\'s instructions',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: MyApp.textBrown.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.zoom_in_rounded, size: 18, color: MyApp.roseGold),
          ],
        ),
      ),
    );
  }

  /// Full-screen viewer for the saved surgeon plan photo.
  void _openSurgeonPlanPhotoViewer(Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 22),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiPlanSection() {
    final latest = _latestMetrics;
    final baseline = _baselineMetrics;
    final resolvedProcedureType = (() {
      final normalized = _procedure.type.trim();
      if (normalized.isEmpty || normalized.toLowerCase() == 'unknown') {
        return 'General Skincare';
      }
      return normalized;
    })();
    AppLogger.verbose(
      '[ProcedureProfilesScreen._buildAiPlanSection] resolvedProcedureType=$resolvedProcedureType',
    );
    final recommendations = latest == null
        ? <AIProductRecommendation>[]
        : AIProductRecommendationEngine.generateRecommendations(
            latest,
            baselineMetrics: baseline,
            procedureType: resolvedProcedureType,
            maxRecommendations:
                ProcedureIntelligence.categoryFor(resolvedProcedureType) ==
                    ProcedureCategory.bodyContouring
                ? 6
                : 3,
            userSkinConcerns: [
              if (latest.redness > 6.0) 'redness',
              if (latest.texture > 6.0) 'texture',
              if (latest.wrinkle > 6.0) 'aging',
              if (latest.pore > 6.0) 'pores',
              if (latest.darkSpots > 6.0) 'pigmentation',
              if (latest.elasticity < 4.8) 'firmness',
              if (latest.redness > 6.0) 'sensitive',
            ],
            recentProcedureTypes:
                resolvedProcedureType.toLowerCase() != 'general skincare'
                ? [resolvedProcedureType]
                : null,
          );

    final plan = AiRecoveryPlanEngine.generate(
      procedureType: _procedure.type,
      startDate: _procedure.startDate,
      latestMetrics: latest,
      baselineMetrics: baseline,
      scanCount: _scans.length,
    );

    final dayN = (DateTime.now().difference(_procedure.startDate).inDays + 1)
        .clamp(1, 999);

    return _buildSectionCard(
      title: 'AI Recovery Plan',
      icon: Icons.psychology_alt_outlined,
      eyebrow: 'Procedure-aware guidance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Phase headline banner ──────────────────────────────────────
          _aiPlanPhaseBanner(plan),
          const SizedBox(height: 12),
          // ── Personalized summary ──────────────────────────────────────
          Text(
            plan.summary,
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.82),
              height: 1.45,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          // ── Context chips ─────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Recovery day $dayN'),
              _chip(
                '${_scans.length} progress scan${_scans.length == 1 ? '' : 's'}',
              ),
              _chip(
                'Streak $_currentStreak day${_currentStreak == 1 ? '' : 's'}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Daily Focus ───────────────────────────────────────────────
          _aiPlanSubsection(
            icon: Icons.wb_sunny_outlined,
            title: 'Daily Focus',
            eyebrow: 'TODAY · NON-NEGOTIABLES',
            accent: MyApp.clinicalTeal,
            items: plan.dailyFocus,
          ),
          const SizedBox(height: 14),
          // ── Weekly Focus ──────────────────────────────────────────────
          _aiPlanSubsection(
            icon: Icons.calendar_view_week_outlined,
            title: 'This Week',
            eyebrow: 'NEXT 7 DAYS · PROTOCOL HABITS',
            accent: MyApp.roseGold,
            items: plan.weeklyFocus,
          ),
          const SizedBox(height: 14),
          // ── What to Avoid ─────────────────────────────────────────────
          _aiPlanSubsection(
            icon: Icons.do_not_disturb_alt_outlined,
            title: 'What to Avoid',
            eyebrow: 'PROTECT YOUR RESULT',
            accent: const Color(0xFFB7895A), // warm amber-bronze
            items: plan.avoid,
          ),
          const SizedBox(height: 14),
          // ── Red Flags ─────────────────────────────────────────────────
          _aiPlanSubsection(
            icon: Icons.health_and_safety_outlined,
            title: 'Contact Your Provider If…',
            eyebrow: 'CLINICAL ESCALATION SIGNALS',
            accent: const Color(0xFFC0566A), // clinical rose-red
            items: plan.redFlags,
            isWarning: true,
          ),
          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 18),
            Divider(
              height: 1,
              color: MyApp.goldShimmer.withValues(alpha: 0.16),
            ),
            const SizedBox(height: 14),
            ClinicalProductRecommendationsSection(
              recommendations: recommendations,
              sectionSubtitle: 'Matched to your latest metrics',
            ),
          ],
          const SizedBox(height: 14),
          // ── Disclaimer ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MyApp.clinicalTeal.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: MyApp.clinicalTeal.withValues(alpha: 0.22),
                width: 0.8,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: MyApp.clinicalTeal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI guidance — supportive only. Always follow your provider\u2019s personalized instructions.',
                    style: TextStyle(
                      color: MyApp.clinicalNavy.withValues(alpha: 0.85),
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
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

  /// Phase banner: gradient pill with phase label + 2-line description.
  Widget _aiPlanPhaseBanner(AiRecoveryPlan plan) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MyApp.clinicalNavy.withValues(alpha: 0.06),
            MyApp.roseGold.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.28),
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
              gradient: LinearGradient(
                colors: [
                  MyApp.goldShimmer.withValues(alpha: 0.35),
                  MyApp.roseGold.withValues(alpha: 0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.phaseLabel.toUpperCase(),
                  style: TextStyle(
                    color: MyApp.roseGold,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  plan.phaseDescription,
                  style: TextStyle(
                    color: MyApp.clinicalNavy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bulleted subsection (Daily Focus / Avoid / Red Flags).
  Widget _aiPlanSubsection({
    required IconData icon,
    required String title,
    required Color accent,
    required List<RecoveryPlanItem> items,
    String? eyebrow,
    bool isWarning = false,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isWarning
              ? [accent.withValues(alpha: 0.08), accent.withValues(alpha: 0.03)]
              : [accent.withValues(alpha: 0.05), MyApp.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: isWarning ? 0.34 : 0.22),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.06),
            blurRadius: 10,
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
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.10),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.25),
                    width: 0.6,
                  ),
                ),
                child: Icon(icon, size: 14, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (eyebrow != null) ...[
                      Text(
                        eyebrow,
                        style: TextStyle(
                          color: accent.withValues(alpha: 0.90),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      title,
                      style: TextStyle(
                        color: MyApp.clinicalNavy,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Item-count pill for visual weight + scannability ─────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.32),
                    width: 0.7,
                  ),
                ),
                child: Text(
                  '${items.length} item${items.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(items.length, (i) {
            final item = items[i];
            final isLast = i == items.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.35),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: MyApp.clinicalNavy.withValues(alpha: 0.92),
                          fontSize: 12.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          TextSpan(text: item.text),
                          if (item.reason != null && item.reason!.isNotEmpty)
                            TextSpan(
                              text: ' — ${item.reason}',
                              style: TextStyle(
                                color: MyApp.textBrown.withValues(alpha: 0.72),
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }


  Widget _buildProgressInsightSummaryCard(
    SkinMetrics? latest,
    SkinMetrics? baseline,
    _ComparisonConfidence confidence,
  ) {
    if (latest == null || baseline == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MyApp.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.16)),
        ),
        child: Text(
          'Add at least two progress scans to unlock detailed improvement and regression tracking.',
          style: TextStyle(
            color: MyApp.textBrown.withValues(alpha: 0.78),
            height: 1.45,
          ),
        ),
      );
    }

    final cards = _buildDetailedProgressInsightCards(latest, baseline);
    final comparable = cards
      .where((c) => (c['hasComparison'] as bool?) ?? true)
      .toList();
    final improved = comparable.where((c) => c['trend'] == 'improving').length;
    final worsened = comparable.where((c) => c['trend'] == 'regressing').length;
    final stable = comparable.where((c) => c['trend'] == 'stable').length;
    final pendingBaseline = cards.length - comparable.length;
    final overall = _computeOverallRecoveryScore(
      _buildProcedureMetricCards(_latestMetricInsights),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            MyApp.champagne.withValues(alpha: 0.7),
            MyApp.roseGold.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: MyApp.roseGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.insights_outlined,
                  color: MyApp.roseGold,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  comparable.isEmpty
                      ? 'Recovery trend pending baseline reference data'
                      : 'Recovery trend is ${improved >= worsened ? 'moving in the right direction' : 'mixed and needs attention'}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: MyApp.clinicalNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Overall recovery score: ${overall.toStringAsFixed(0)} / 100',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: MyApp.roseGold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            comparable.isEmpty
                ? 'All tracked metrics are currently awaiting a valid baseline comparison. Capture a baseline and follow-up scan to unlock trend badges.'
                : 'Compared with your baseline scan, $improved metric${improved == 1 ? '' : 's'} improved, $stable remained stable, and $worsened showed mild regression.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: MyApp.textBrown.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _buildOverallInsightSentence(latest, baseline, cards),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: MyApp.textBrown.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _trendPill('Improved $improved', const Color(0xFF1E8C5F)),
              if (comparable.isNotEmpty) ...[
                const SizedBox(width: 8),
                _trendPill('Stable $stable', const Color(0xFFAD7C2B)),
                const SizedBox(width: 8),
                _trendPill('Needs attention $worsened', const Color(0xFFB13C52)),
              ],
              if (pendingBaseline > 0) ...[
                const SizedBox(width: 8),
                _trendPill('Pending baseline $pendingBaseline', const Color(0xFF5A6270)),
              ],
            ],
          ),
          if (confidence.label.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              confidence.label,
              style: TextStyle(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: MyApp.clinicalSlate.withValues(alpha: 0.88),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressInsightGrid(List<Map<String, dynamic>> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960
            ? 3
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns == 1 ? 1.55 : 1.05,
          ),
          itemBuilder: (_, index) => _progressInsightCard(cards[index]),
        );
      },
    );
  }

  Widget _progressInsightCard(Map<String, dynamic> item) {
    final Color color = item['color'] as Color;
    final showStatusBadge = (item['showStatusBadge'] as bool?) ?? true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, color.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item['icon'] as IconData, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item['title'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.8,
                    color: MyApp.clinicalNavy,
                  ),
                ),
              ),
              if (showStatusBadge)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item['status'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item['detail'] as String,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.42,
              color: MyApp.textBrown.withValues(alpha: 0.78),
            ),
          ),
          const Spacer(),
          const SizedBox(height: 8),
          Text(
            item['advice'] as String,
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressInsightActionCard(
    SkinMetrics? latest,
    SkinMetrics? baseline,
  ) {
    if (latest == null || baseline == null) {
      return const SizedBox.shrink();
    }
    final cards = _buildDetailedProgressInsightCards(latest, baseline);
    final attention = cards.where((c) => c['trend'] == 'regressing').toList();
    final improving = cards.where((c) => c['trend'] == 'improving').toList();

    final actionText = attention.isNotEmpty
        ? 'Focus on barrier support, consistent SPF, and gentle hydration while avoiding aggressive actives on the areas that regressed.'
        : 'Keep the current plan: gentle cleanser, hydrating moisturizer, diligent SPF, and avoid over-exfoliation until the skin stabilizes.';

    final focusLabel = attention.isNotEmpty
        ? 'Primary attention areas'
        : 'What to keep doing';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            focusLabel,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: MyApp.clinicalNavy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            actionText,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: MyApp.textBrown.withValues(alpha: 0.78),
            ),
          ),
          if (attention.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: attention
                  .map(
                    (item) => _trendPill(
                      '${item['title']}: ${item['deltaText']}',
                      item['color'] as Color,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (improving.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: improving
                  .map(
                    (item) => _trendPill(
                      '${item['title']}: ${item['deltaText']}',
                      item['color'] as Color,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressConfidenceNote(_ComparisonConfidence confidence) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: confidence.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: confidence.color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, size: 16, color: confidence.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              confidence.note,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: MyApp.clinicalNavy.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportingInsightNote(ProgressPhotoInsight insight) {
    final highlights = insight.highlights.take(2).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MyApp.champagne.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SmartNarrativeContainer(narrativeText: insight.summary),
          if (highlights.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...highlights.map(
              (h) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 5, color: MyApp.roseGold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        h,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: MyApp.clinicalNavy.withValues(alpha: 0.82),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<ProcedureRecoveryPoint> _recoveryCurvePointsForMetric(String metricKey) {
    if (_scans.isEmpty) return const <ProcedureRecoveryPoint>[];

    final chronological = List<ScanHistoryEntry>.from(_scans)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final baselineDate = chronological.first.timestamp;
    final byDay = <int, double>{};

    for (final scan in chronological) {
      final day = scan.timestamp.difference(baselineDate).inDays + 1;
      if (day < 1 || day > 30) continue;

      final value = _metricCurveValue(scan.toSkinMetrics(), metricKey);
      if (value == null) continue;

      // Keep the latest reading within a day if multiple scans exist.
      byDay[day] = value;
    }

    final sortedDays = byDay.keys.toList()..sort();
    return sortedDays
        .map(
          (day) =>
              ProcedureRecoveryPoint(day: day.toDouble(), value: byDay[day]!),
        )
        .toList();
  }

  double? _metricCurveValue(SkinMetrics metrics, String metricKey) {
    switch (metricKey) {
      case 'redness':
        return (metrics.redness * 10).clamp(0, 100).toDouble();
      case 'texture':
        return (metrics.texture * 10).clamp(0, 100).toDouble();
      case 'wrinkle':
        return (metrics.wrinkle * 10).clamp(0, 100).toDouble();
      case 'pore':
        return (metrics.pore * 10).clamp(0, 100).toDouble();
      case 'darkSpots':
        return (metrics.darkSpots * 10).clamp(0, 100).toDouble();
      case 'elasticity':
        return (metrics.elasticity * 10).clamp(0, 100).toDouble();
      default:
        return null;
    }
  }

  List<String> _availableRecoveryCurveMetrics() {
    return _availableRecoveryCurveMetricsForProcedure(_procedure.type);
  }

  List<String> _availableRecoveryCurveMetricsForProcedure(
    String procedureType,
  ) {
    const keys = <String>[
      'redness',
      'texture',
      'darkSpots',
      'pore',
      'wrinkle',
      'elasticity',
    ];
    return keys
        .where(
          (key) => ProcedureIntelligence.isMetricRelevant(key, procedureType),
        )
        .toList();
  }

  String _recoveryCurveMetricPrefKey(String procedureId) {
    return 'procedure_recovery_curve_metric_$procedureId';
  }

  Future<String?> _loadSavedRecoveryCurveMetric(String procedureId) async {
    final id = procedureId.trim();
    if (id.isEmpty) return null;
    final raw = await AppPrefs.getString(_recoveryCurveMetricPrefKey(id));
    final normalized = _normalizeRecoveryCurveMetricKey(raw);
    if (normalized == null) return null;

    // Migrate legacy aliases to canonical keys at read time.
    if ((raw?.trim() ?? '') != normalized) {
      await AppPrefs.setString(_recoveryCurveMetricPrefKey(id), normalized);
    }
    return normalized;
  }

  Future<void> _saveRecoveryCurveMetricSelection(String metricKey) async {
    final id = _procedure.id.trim();
    if (id.isEmpty) return;
    final normalized = _normalizeRecoveryCurveMetricKey(metricKey);
    if (normalized == null) return;
    await AppPrefs.setString(_recoveryCurveMetricPrefKey(id), normalized);
  }

  String? _normalizeRecoveryCurveMetricKey(String? raw) {
    final key = raw?.trim();
    if (key == null || key.isEmpty) return null;

    switch (key.toLowerCase()) {
      case 'redness':
        return 'redness';
      case 'texture':
        return 'texture';
      case 'dark spots':
      case 'darkspots':
      case 'dark_spots':
      case 'dark-spots':
      case 'darkspot':
      case 'dark_spot':
      case 'dark-spot':
        return 'darkSpots';
      case 'pore':
      case 'pores':
        return 'pore';
      case 'wrinkle':
      case 'wrinkles':
        return 'wrinkle';
      case 'elasticity':
        return 'elasticity';
      default:
        return key;
    }
  }

  Map<String, double> _clinicalZoneForCurveMetric(String metricKey) {
    switch (metricKey) {
      case 'redness':
        return {'min': 30, 'max': 60};
      case 'texture':
        return {'min': 25, 'max': 55};
      case 'darkSpots':
        return {'min': 20, 'max': 50};
      case 'pore':
        return {'min': 20, 'max': 55};
      case 'wrinkle':
        return {'min': 25, 'max': 55};
      case 'elasticity':
        return {'min': 45, 'max': 75};
      default:
        return {'min': 30, 'max': 60};
    }
  }

  Widget _buildRecoveryCurveMetricSelector(List<String> keys, String selected) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: keys.map((key) {
        final isSelected = key == selected;
        return ChoiceChip(
          label: Text(ProcedureIntelligence.metricLabel(key, _procedure.type)),
          selected: isSelected,
          onSelected: (_) {
            if (isSelected) return;
            setState(() => _selectedRecoveryCurveMetric = key);
            _saveRecoveryCurveMetricSelection(key);
          },
          selectedColor: MyApp.roseGold.withValues(alpha: 0.18),
          backgroundColor: MyApp.surface,
          side: BorderSide(
            color: isSelected
                ? MyApp.roseGold.withValues(alpha: 0.44)
                : MyApp.roseGold.withValues(alpha: 0.22),
            width: 0.8,
          ),
          labelStyle: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? MyApp.clinicalNavy : MyApp.textBrown,
          ),
        );
      }).toList(),
    );
  }

  List<Map<String, dynamic>> _buildDetailedProgressInsightCards(
    SkinMetrics latest,
    SkinMetrics baseline,
  ) {
    final cards = <Map<String, dynamic>>[];

    void addMetric({
      required String title,
      required double latestValue,
      required double baselineValue,
      required bool lowerIsBetter,
      required String unit,
      required String improvementAdvice,
      required String worseningAdvice,
      required String function,
    }) {
        final hasComparison =
          !(latestValue == 0.0 && baselineValue == 0.0);
      final delta = latestValue - baselineValue;
      final improved = lowerIsBetter ? delta < 0 : delta > 0;
      final changed = delta.abs();
        final trend = !hasComparison
          ? 'pending'
          : changed < 0.2
          ? 'stable'
          : improved
          ? 'improving'
          : 'regressing';
        final Color color = trend == 'pending'
          ? const Color(0xFF5A6270)
          : trend == 'improving'
          ? const Color(0xFF1E8C5F)
          : trend == 'stable'
          ? const Color(0xFFAD7C2B)
          : const Color(0xFFB13C52);
        final status = trend == 'pending'
          ? 'Pending Baseline'
          : trend == 'improving'
          ? 'Improving'
          : trend == 'stable'
          ? 'Stable'
          : 'Needs attention';
      final changeText = unit == 'mm'
          ? '${delta.abs().toStringAsFixed(2)} mm'
          : '${changed.toStringAsFixed(1)} points';
        final detail = trend == 'pending'
          ? '$function is awaiting baseline capture before trend classification can be shown.'
          : trend == 'stable'
          ? '$function stayed relatively steady. Changes are small enough to read as direction, not a firm conclusion.'
          : improved
          ? '$function improved by $changeText compared with baseline.'
          : '$function worsened by $changeText compared with baseline.';
      final advice = trend == 'regressing'
          ? worseningAdvice
          : improvementAdvice;

      cards.add({
        'title': title,
        'trend': trend,
        'status': status,
        'hasComparison': hasComparison,
        'showStatusBadge': hasComparison,
        'detail': detail,
        'advice': advice,
        'color': color,
        'icon': trend == 'pending'
          ? Icons.schedule_rounded
          : trend == 'improving'
            ? Icons.trending_up
            : trend == 'stable'
            ? Icons.trending_flat
            : Icons.trending_down,
        'deltaText': !hasComparison
          ? 'Pending Baseline'
          : unit == 'mm'
            ? '${improved ? '-' : '+'}${delta.abs().toStringAsFixed(2)} mm'
            : '${improved ? '-' : '+'}${changed.toStringAsFixed(1)}',
      });
    }

    addMetric(
      title: 'Redness / Erythema',
      latestValue: latest.redness,
      baselineValue: baseline.redness,
      lowerIsBetter: true,
      unit: '',
      function: 'Surface inflammation',
      improvementAdvice:
          'Continue gentle cleansing, SPF, and barrier-supporting moisturizer. Avoid strong actives while redness is still settling.',
      worseningAdvice:
          'Pause exfoliating products for now and focus on soothing hydration. If redness keeps rising, keep heat and sun exposure to a minimum.',
    );

    addMetric(
      title: 'Texture & Smoothness',
      latestValue: latest.texture,
      baselineValue: baseline.texture,
      lowerIsBetter: true,
      unit: '',
      function: 'Surface refinement',
      improvementAdvice:
          'Keep hydration consistent and avoid over-exfoliation. Texture usually improves best with steady barrier care.',
      worseningAdvice:
          'Shift to a simpler routine for several days and avoid scrubs, acids, and friction until the surface settles.',
    );

    addMetric(
      title: 'Dark Spots / Pigmentation',
      latestValue: latest.darkSpots,
      baselineValue: baseline.darkSpots,
      lowerIsBetter: true,
      unit: '',
      function: 'Tone evenness',
      improvementAdvice:
          'Keep mineral SPF daily and avoid picking or heat exposure. Pigment tends to respond slowly, so consistency matters more than intensity.',
      worseningAdvice:
          'Protect the area from UV, heat, and friction. Consider gentle pigment-supporting care only once the skin is less reactive.',
    );

    addMetric(
      title: 'Pore Size',
      latestValue: _poreSizeMmFromScore(latest.pore),
      baselineValue: _poreSizeMmFromScore(baseline.pore),
      lowerIsBetter: true,
      unit: 'mm',
      function: 'Visible pore openings',
      improvementAdvice:
          'Keep the skin clean, hydrated, and protected from congestion. Small pore changes are best read over several scans.',
      worseningAdvice:
          'Use gentler cleansing and avoid heavy occlusive layers if congestion seems to be increasing.',
    );

    addMetric(
      title: 'Elasticity / Firmness',
      latestValue: latest.elasticity,
      baselineValue: baseline.elasticity,
      lowerIsBetter: false,
      unit: '',
      function: 'Collagen support',
      improvementAdvice:
          'Keep support routines steady: hydration, protein-rich nutrition, and the procedure-specific plan you were given.',
      worseningAdvice:
          'Avoid overloading the skin with actives. Consistent recovery habits are more useful than aggressive resurfacing at this stage.',
    );

    final barrierLatest = ((10 - latest.redness) + (10 - latest.texture)) / 2;
    final barrierBaseline =
        ((10 - baseline.redness) + (10 - baseline.texture)) / 2;
    addMetric(
      title: 'Barrier Recovery',
      latestValue: barrierLatest,
      baselineValue: barrierBaseline,
      lowerIsBetter: false,
      unit: '',
      function: 'Barrier resilience',
      improvementAdvice:
          'Barrier recovery looks stronger. Keep moisturizers and SPF in place and avoid unnecessary irritation.',
      worseningAdvice:
          'Prioritize barrier repair: fragrance-free moisturizer, reduced actives, and less friction until reactivity settles.',
    );

    return cards;
  }

  String _buildOverallInsightSentence(
    SkinMetrics latest,
    SkinMetrics baseline,
    List<Map<String, dynamic>> cards,
  ) {
    final improved = cards.where((c) => c['trend'] == 'improving').toList();
    final regressed = cards.where((c) => c['trend'] == 'regressing').toList();

    String maxGainLabel = '';
    double maxGain = 0;
    for (final card in improved) {
      final text = card['deltaText'] as String;
      final numeric =
          double.tryParse(text.replaceAll(RegExp(r'[^0-9\.]'), '')) ?? 0;
      if (numeric > maxGain) {
        maxGain = numeric;
        maxGainLabel = card['title'] as String;
      }
    }

    if (regressed.isEmpty) {
      return maxGainLabel.isNotEmpty
          ? '$maxGainLabel showed the clearest improvement, while the rest of the scan is either steady or moving in the right direction.'
          : 'The scan is broadly steady with no meaningful regressions. Small changes should still be interpreted conservatively.';
    }

    final worst = regressed.first;
    return maxGainLabel.isNotEmpty
        ? '$maxGainLabel improved the most overall, while ${worst['title']} deserves the most attention right now.'
        : '${worst['title']} is the main area to watch right now.';
  }

  _ComparisonConfidence _comparisonConfidence(
    ScanHistoryEntry? latest,
    ScanHistoryEntry? baseline,
  ) {
    final values = <double>[];
    for (final scan in [latest, baseline]) {
      if (scan == null) continue;
      if (scan.lightingConfidence != null) {
        values.add(scan.lightingConfidence!);
      }
      if (scan.expressionConfidence != null) {
        values.add(scan.expressionConfidence!);
      }
    }
    if (values.isEmpty) {
      return _ComparisonConfidence(
        label:
            'Confidence note: comparison is useful, but read small changes as directional until you have several scans under similar lighting and pose.',
        note:
            'Photo-comparison confidence: directional only. Keep future scans under similar lighting and head position to confirm the trend.',
        color: const Color(0xFFAD7C2B),
      );
    }

    final mean = values.fold<double>(0, (a, b) => a + b) / values.length;
    if (mean >= 0.8) {
      return _ComparisonConfidence(
        label:
            'Comparison confidence is strong. The lighting and expression signals support the trend.',
        note:
            'Photo-comparison confidence: strong. The scan trend is likely reliable, but still treat sub-0.2 point changes as small.',
        color: const Color(0xFF1E8C5F),
      );
    }
    if (mean >= 0.65) {
      return _ComparisonConfidence(
        label:
            'Comparison confidence is moderate. The trend is credible, but minor changes should be treated conservatively.',
        note:
            'Photo-comparison confidence: moderate. Lighting and pose were acceptable, but small changes should be read as directional rather than definitive.',
        color: const Color(0xFFAD7C2B),
      );
    }
    return _ComparisonConfidence(
      label:
          'Comparison confidence is limited. Use this scan to guide trends, not to over-interpret small shifts.',
      note:
          'Photo-comparison confidence: limited. Capture the next scan with more consistent lighting, distance, and expression to improve reliability.',
      color: const Color(0xFFB13C52),
    );
  }

  Widget _trendPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildCustomPlanSection() {
    final hasPlans = _customPlans.isNotEmpty;
    return _buildSectionCard(
      title: 'Custom AI Plan Timeline',
      icon: Icons.auto_awesome_motion_outlined,
      eyebrow: 'Auto-generated from surgeon notes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasPlans
                ? 'Personalized milestones distilled from your surgeon\u2019s written instructions.'
                : 'Paste your post-op instructions into the surgeon plan, then generate a structured recovery timeline tailored to your procedure.',
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.78),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _generateCustomPlanFromNotes,
              icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
              label: Text(
                hasPlans
                    ? 'Regenerate from Surgeon Notes'
                    : 'Generate from Surgeon Notes',
              ),
              style: MyApp.secondaryOutlineButton(accent: MyApp.roseGold),
            ),
          ),
          if (hasPlans) ...[
            const SizedBox(height: 16),
            Divider(
              height: 1,
              color: MyApp.goldShimmer.withValues(alpha: 0.16),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _customPlans.take(2).length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MyApp.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: MyApp.roseGold.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                MyApp.goldShimmer.withValues(alpha: 0.35),
                                MyApp.roseGold.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _customPlans[i].title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _customPlans[i].surgeonNotes,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: MyApp.textBrown.withValues(alpha: 0.82),
                      ),
                    ),
                    if (_customPlans[i].timelineMilestones.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.timeline,
                            size: 14,
                            color: MyApp.clinicalTeal,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_customPlans[i].timelineMilestones.length} milestone${_customPlans[i].timelineMilestones.length == 1 ? '' : 's'} mapped',
                            style: TextStyle(
                              color: MyApp.clinicalNavy,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: MyApp.roseGold.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.28),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: MyApp.clinicalNavy,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Before/After Comparison Slider - Draggable divider overlay
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _beforeAfterComparisonSlider({
    required Uint8List baselinePhoto,
    required Uint8List latestPhoto,
    SkinMetrics? baselineMetrics,
    SkinMetrics? latestMetrics,
    List<BeforeAfterMetricTag> metricTags = const <BeforeAfterMetricTag>[],
  }) {
    final category = ProcedureIntelligence.categoryFor(_procedure.type);
    final isLaserCategory = category == ProcedureCategory.laserPeel;
    final isBodyContouringCategory =
        category == ProcedureCategory.bodyContouring;
    final isFaceOverride =
        _debugHeatmapRegionOverride == HeatmapDebugRegion.face;
    final bodyOverride = _bodyHeatmapRegionFromDebugOverride(
      _debugHeatmapRegionOverride,
    );
    final useLaserOverlay =
        isFaceOverride || (isLaserCategory && bodyOverride == null);
    final useBodyOverlay =
        bodyOverride != null || (!isFaceOverride && isBodyContouringCategory);
    final bodyRegion =
        bodyOverride ?? _bodyHeatmapRegionForProcedure(_procedure.type);
    final baselineProvider = MemoryImage(baselinePhoto);
    final latestProvider = MemoryImage(latestPhoto);

    return InteractiveBeforeAfterSlider(
      beforeImage: baselineProvider,
      afterImage: latestProvider,
      beforeLayerBuilder: baselineMetrics != null
          ? (context, image) {
              if (useLaserOverlay) {
                return SkinHeatmapOverlay.laser(
                  photo: image,
                  redness: baselineMetrics.redness,
                  wrinkles: baselineMetrics.wrinkle,
                  improvement: 0.08,
                );
              }
              if (useBodyOverlay) {
                return SkinHeatmapOverlay.bodyContouring(
                  photo: image,
                  region: bodyRegion,
                  inflammation: baselineMetrics.redness,
                  textureIrregularity: baselineMetrics.texture,
                  improvement: 0.08,
                );
              }
              return Image(image: image, fit: BoxFit.cover);
            }
          : null,
      afterLayerBuilder: latestMetrics != null
          ? (context, image) {
              if (useLaserOverlay) {
                return SkinHeatmapOverlay.laser(
                  photo: image,
                  redness: latestMetrics.redness,
                  wrinkles: latestMetrics.wrinkle,
                  improvement: _laserImprovementIntensity(
                    baseline: baselineMetrics,
                    latest: latestMetrics,
                  ),
                );
              }
              if (useBodyOverlay) {
                return SkinHeatmapOverlay.bodyContouring(
                  photo: image,
                  region: bodyRegion,
                  inflammation: latestMetrics.redness,
                  textureIrregularity: latestMetrics.texture,
                  improvement: _bodyImprovementIntensity(
                    baseline: baselineMetrics,
                    latest: latestMetrics,
                  ),
                );
              }
              return Image(image: image, fit: BoxFit.cover);
            }
          : null,
      beforeLabel: 'Before',
      afterLabel: 'After',
      metricTags: metricTags,
    );
  }

  SkinHeatmapBodyRegion _bodyHeatmapRegionForProcedure(String procedureType) {
    switch (ProcedureIntelligence.bodyContouringSubtype(procedureType)) {
      case ProcedureBodyContouringSubtype.bbl:
        return SkinHeatmapBodyRegion.flanks;
      case ProcedureBodyContouringSubtype.liposuction:
        return SkinHeatmapBodyRegion.abdomen;
      case ProcedureBodyContouringSubtype.other:
        final canonical = canonicalProcedureType(procedureType).toLowerCase();
        if (canonical.contains('breast')) return SkinHeatmapBodyRegion.breasts;
        if (canonical.contains('thigh')) return SkinHeatmapBodyRegion.thighs;
        if (canonical.contains('arm')) return SkinHeatmapBodyRegion.arms;
        if (canonical.contains('tummy') || canonical.contains('abdomen')) {
          return SkinHeatmapBodyRegion.abdomen;
        }
        return SkinHeatmapBodyRegion.generic;
    }
  }

  SkinHeatmapBodyRegion? _bodyHeatmapRegionFromDebugOverride(
    HeatmapDebugRegion? override,
  ) {
    switch (override) {
      case HeatmapDebugRegion.abdomen:
        return SkinHeatmapBodyRegion.abdomen;
      case HeatmapDebugRegion.flanks:
        return SkinHeatmapBodyRegion.flanks;
      case HeatmapDebugRegion.thighs:
        return SkinHeatmapBodyRegion.thighs;
      case HeatmapDebugRegion.arms:
        return SkinHeatmapBodyRegion.arms;
      case HeatmapDebugRegion.breasts:
        return SkinHeatmapBodyRegion.breasts;
      case HeatmapDebugRegion.face:
      case null:
        return null;
    }
  }

  String _heatmapDebugRegionLabel(HeatmapDebugRegion region) {
    switch (region) {
      case HeatmapDebugRegion.face:
        return 'Face';
      case HeatmapDebugRegion.abdomen:
        return 'Abdomen';
      case HeatmapDebugRegion.flanks:
        return 'Flanks';
      case HeatmapDebugRegion.thighs:
        return 'Thighs';
      case HeatmapDebugRegion.arms:
        return 'Arms';
      case HeatmapDebugRegion.breasts:
        return 'Breasts';
    }
  }

  Widget _buildHeatmapDebugChipRow() {
    const regions = <HeatmapDebugRegion>[
      HeatmapDebugRegion.face,
      HeatmapDebugRegion.abdomen,
      HeatmapDebugRegion.flanks,
      HeatmapDebugRegion.thighs,
      HeatmapDebugRegion.arms,
      HeatmapDebugRegion.breasts,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: regions.map((region) {
        final isSelected = _debugHeatmapRegionOverride == region;
        return ChoiceChip(
          label: Text(_heatmapDebugRegionLabel(region)),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              _debugHeatmapRegionOverride = selected ? region : null;
            });
          },
          selectedColor: MyApp.roseGold.withValues(alpha: 0.18),
          backgroundColor: MyApp.surface,
          side: BorderSide(
            color: isSelected
                ? MyApp.roseGold.withValues(alpha: 0.44)
                : MyApp.roseGold.withValues(alpha: 0.22),
            width: 0.8,
          ),
          labelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? MyApp.clinicalNavy : MyApp.textBrown,
          ),
        );
      }).toList(),
    );
  }

  double _laserImprovementIntensity({
    required SkinMetrics? baseline,
    required SkinMetrics? latest,
  }) {
    if (baseline == null || latest == null) return 0;

    final rednessGain = (baseline.redness - latest.redness).clamp(0, 10);
    final wrinkleGain = (baseline.wrinkle - latest.wrinkle).clamp(0, 10);
    final textureGain = (baseline.texture - latest.texture).clamp(0, 10);
    final elasticityGain = (latest.elasticity - baseline.elasticity).clamp(
      0,
      10,
    );
    final blended =
        (rednessGain + wrinkleGain + textureGain + elasticityGain) / 40;
    return blended.clamp(0, 1).toDouble();
  }

  double _bodyImprovementIntensity({
    required SkinMetrics? baseline,
    required SkinMetrics? latest,
  }) {
    if (baseline == null || latest == null) return 0;

    final rednessGain = (baseline.redness - latest.redness).clamp(0, 10);
    final textureGain = (baseline.texture - latest.texture).clamp(0, 10);
    final poreGain = (baseline.pore - latest.pore).clamp(0, 10);
    final elasticityGain = (latest.elasticity - baseline.elasticity).clamp(
      0,
      10,
    );
    final blended =
        (rednessGain + textureGain + poreGain + elasticityGain) / 40;
    return blended.clamp(0, 1).toDouble();
  }

  List<BeforeAfterMetricTag> _comparisonMetricTagsFromPayload(
    Map<String, dynamic> payload,
  ) {
    final metrics = LuxeMetricParser.parseTimelinePayload(payload);
    if (metrics.isEmpty) return const <BeforeAfterMetricTag>[];

    final procedureType = _procedure.type;
    final relevant = metrics
        .where(
          (metric) => ProcedureIntelligence.isMetricRelevant(
            metric.key,
            procedureType,
          ),
        )
        .toList()
      ..sort((a, b) => LuxeMetricParser.displayDeltaMagnitude(
            baseline: b.baselineScore,
            current: b.currentScore,
            deltaPct: b.improvementPercent,
          ).compareTo(
            LuxeMetricParser.displayDeltaMagnitude(
              baseline: a.baselineScore,
              current: a.currentScore,
              deltaPct: a.improvementPercent,
            ),
          ));

    return relevant.take(4).map((metric) {
      return BeforeAfterMetricTag(
        label: metric.name,
        value: LuxeMetricParser.formatDisplayDelta(
          baseline: metric.baselineScore,
          current: metric.currentScore,
          deltaPct: metric.improvementPercent,
          includeSign: true,
        ),
        side: metric.improvementPercent <= 0
            ? BeforeAfterTagSide.left
            : BeforeAfterTagSide.right,
      );
    }).toList();
  }

  Widget _metricsComparisonWidgetFromPayload(
    Map<String, dynamic> payload,
  ) {
    final metrics = LuxeMetricParser.parseTimelinePayload(payload);
    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: const Color(0xFFE8E2D8), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LOCAL PHOTO DELTA',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: MyApp.clinicalNavy.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Metrics Progress',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.1,
                color: MyApp.clinicalNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Computed directly from metric_matrix and trend_deltas.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: MyApp.textBrown.withValues(alpha: 0.66),
              ),
            ),
            const SizedBox(height: 14),
            ...metrics.asMap().entries.expand(
              (entry) => [
                if (entry.key > 0) const SizedBox(height: 10),
                _localMetricCard(metric: entry.value),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _localMetricCard({
    required LuxeMetric metric,
  }) {
    const double threshold = 0.0001;
    final isUnchanged = metric.improvementPercent.abs() < threshold;
    final isImproved = isUnchanged
        ? false
        : (metric.lowerIsBetter
            ? metric.currentScore < metric.baselineScore
            : metric.currentScore > metric.baselineScore);
    final accent = isUnchanged
        ? const Color(0xFF6B7280)
        : (isImproved ? const Color(0xFF166534) : const Color(0xFF991B1B));
    final deltaText = LuxeMetricParser.formatDisplayDelta(
      baseline: metric.baselineScore,
      current: metric.currentScore,
      deltaPct: metric.improvementPercent,
      includeSign: true,
    );
    final currentScoreText = metric.currentScore.toStringAsFixed(1);
    final baselineScoreText = metric.baselineScore.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEAE4DA), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: MyApp.clinicalNavy,
                    fontSize: 13.5,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  baselineScoreText,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: MyApp.textBrown.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'baseline',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: MyApp.textBrown.withValues(alpha: 0.48),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currentScoreText,
                style: TextStyle(
                  fontSize: 34,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  color: MyApp.clinicalNavy,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  deltaText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: accent,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Finds the ProcedureLog whose id matches [procedureId]. At-Home logs share
  /// their id with the Procedure created from them (see _procedureFromLog), so
  /// this reliably links a Procedure record back to its source log.
  ProcedureLog? _findProcedureLogById(String procedureId) {
    if (!Hive.isBoxOpen(procedureLogsBoxName)) return null;
    final box = Hive.box<ProcedureLog>(procedureLogsBoxName);
    return box.get(procedureId);
  }

  /// The linked log's photos, paired with their label, with duplicate paths
  /// removed so a single upload never renders more than once.
  List<({String label, String path})> get _dedupedLogPhotos {
    final log = _procedureLog;
    if (log == null) return const [];
    final seen = <String>{};
    final result = <({String label, String path})>[];
    for (final photo in log.labeledPhotos) {
      final path = photo.path.trim();
      if (path.isEmpty) continue;
      if (!seen.add(path)) continue; // skip duplicate paths
      result.add(photo);
    }
    return result;
  }

  Widget _buildProcedureLogPhotosSection(
    List<({String label, String path})> photos,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.10),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: MyApp.roseGold.withValues(alpha: 0.16),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClinicalSectionHeader(
              icon: Icons.compare_outlined,
              title: 'Before & After',
              eyebrow:
                  '${photos.length} photo${photos.length == 1 ? '' : 's'} logged',
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: buildLocalImagePreview(
                          photo.path,
                          width: 140,
                          height: 140,
                          borderRadius: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        photo.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: MyApp.clinicalNavy,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBeforeAfterSection() {
    final baselinePhoto = _baselinePhotoBytes;
    final latestPhoto = _latestPhotoBytes;
    final hasBaseline = baselinePhoto != null && baselinePhoto.isNotEmpty;
    final hasLatest =
        latestPhoto != null &&
        latestPhoto.isNotEmpty &&
        _hasDistinctComparisonPair;

    // At-Home procedures keep their photos on the linked ProcedureLog rather
    // than in scan history. When scan-history has no usable photo bytes but
    // the log has photos, render those (deduplicated) so the record isn't empty.
    if (!hasBaseline) {
      final logPhotos = _dedupedLogPhotos;
      if (logPhotos.isNotEmpty) {
        return _buildProcedureLogPhotosSection(logPhotos);
      }
    }

    // ── Hero: full slider + metrics ──────────────────────────────────────────
    if (hasBaseline && hasLatest) {
      final baseline = _baselineMetrics;
      final latest = _latestMetrics;
      final localPayload = _localProcedureDeltaPayload;
      final baselineProvider = MemoryImage(baselinePhoto);
      final latestProvider = MemoryImage(latestPhoto);
      return Card(
        margin: EdgeInsets.zero,
        elevation: 2,
        shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: MyApp.roseGold.withValues(alpha: 0.16),
            width: 0.8,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: ClinicalSectionHeader(
                      icon: Icons.compare_outlined,
                      title: 'Before & After',
                      eyebrow: 'Side-by-side progression',
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: MyApp.roseGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: MyApp.roseGold.withValues(alpha: 0.22),
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      'Drag to compare',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: MyApp.roseGold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_showHeatmapDebugRow) ...[
                _buildHeatmapDebugChipRow(),
                const SizedBox(height: 12),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _beforeAfterComparisonSlider(
                  baselinePhoto: baselinePhoto,
                  latestPhoto: latestPhoto,
                  baselineMetrics: baseline,
                  latestMetrics: latest,
                  metricTags: localPayload != null
                      ? _comparisonMetricTagsFromPayload(localPayload!)
                      : const <BeforeAfterMetricTag>[],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Single baseline photo — waiting for progress scan ────────────────────
    if (hasBaseline) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 2,
        shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: MyApp.roseGold.withValues(alpha: 0.14),
            width: 0.8,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ClinicalSectionHeader(
                icon: Icons.compare_outlined,
                title: 'Before & After',
                eyebrow: 'Baseline captured',
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(baselinePhoto, fit: BoxFit.cover),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Baseline',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: MyApp.textBrown.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Baseline locked. Add a progress photo to unlock the Before/After comparison.',
                      style: TextStyle(
                        fontSize: 12,
                        color: MyApp.textBrown.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _openScanCapture,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add Progress Photo'),
                style: MyApp.primaryGoldButton,
              ),
            ],
          ),
        ),
      );
    }

    // ── No photos at all ─────────────────────────────────────────────────────
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: MyApp.roseGold.withValues(alpha: 0.14),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          children: [
            Icon(
              Icons.compare_outlined,
              size: 40,
              color: MyApp.roseGold.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 10),
            Text('Before & After Comparison', style: MyApp.cardTitleStyle()),
            const SizedBox(height: 6),
            Text(
              'Upload your first photo to set the permanent baseline, then add progress photos to see your transformation.',
              style: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.65),
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openScanCapture,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add Baseline Photo'),
              style: MyApp.primaryGoldButton,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: _procedure.type,
          eyebrow: 'Procedure record',
          color: MyApp.textBrown,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.textBrown,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'complete') {
                await _setCompleted(!_procedure.isCompleted);
              } else if (value == 'delete') {
                await _deleteProcedure();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'complete',
                child: Text(
                  _procedure.isCompleted ? 'Mark Active' : 'Mark Completed',
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete Procedure'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Procedure header ──────────────────────────────────────────
            Card(
              margin: EdgeInsets.zero,
              elevation: 2,
              shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: MyApp.roseGold.withValues(alpha: 0.14),
                  width: 0.8,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_peptideDisplay != null) ...[
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _peptideDisplay!.categoryColor.withValues(
                                    alpha: 0.18,
                                  ),
                                  _peptideDisplay!.categoryColor.withValues(
                                    alpha: 0.08,
                                  ),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _peptideDisplay!.categoryColor
                                    .withValues(alpha: 0.38),
                                width: 0.8,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              _peptideDisplay!.icon,
                              size: 22,
                              color: _peptideDisplay!.categoryColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PROCEDURE RECORD',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: MyApp.roseGold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _peptideDisplay?.title ?? _procedure.type,
                                style: TextStyle(
                                  color: MyApp.clinicalNavy,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  letterSpacing: 0.1,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _peptideDisplay?.subtitle ??
                                    (_procedure.provider.trim().toLowerCase() ==
                                            'self'
                                        ? 'Self-managed'
                                        : _procedure.provider),
                                style: TextStyle(
                                  color: MyApp.textBrown.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _procedure.isCompleted
                                ? Colors.green.withValues(alpha: 0.10)
                                : MyApp.clinicalTeal.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _procedure.isCompleted
                                  ? Colors.green.withValues(alpha: 0.32)
                                  : MyApp.clinicalTeal.withValues(alpha: 0.32),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _procedure.isCompleted
                                      ? Colors.green.shade600
                                      : MyApp.clinicalTeal,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _procedure.isCompleted ? 'Completed' : 'Active',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                  color: _procedure.isCompleted
                                      ? Colors.green.shade700
                                      : MyApp.clinicalTeal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (_peptideDisplay != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _peptideDisplay!.categoryColor.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _peptideDisplay!.categoryColor
                                    .withValues(alpha: 0.40),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              _peptideDisplay!.categoryLabel,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: _peptideDisplay!.categoryColor,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: MyApp.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: MyApp.roseGold.withValues(alpha: 0.26),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_outlined,
                                size: 12,
                                color: MyApp.roseGold,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Started ${_formatDate(_procedure.startDate)}',
                                style: TextStyle(
                                  color: MyApp.clinicalNavy,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: MyApp.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: MyApp.roseGold.withValues(alpha: 0.26),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.repeat_rounded,
                                size: 12,
                                color: MyApp.roseGold,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${_procedure.numSessions} session${_procedure.numSessions == 1 ? '' : 's'}',
                                style: TextStyle(
                                  color: MyApp.clinicalNavy,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
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
            ),
            const SizedBox(height: 12),
            // ── Stats row ─────────────────────────────────────────────────
            Card(
              margin: EdgeInsets.zero,
              elevation: 2,
              shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: MyApp.roseGold.withValues(alpha: 0.14),
                  width: 0.8,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                child: Row(
                  children: [
                    Expanded(child: _statTile('Scans', '${_scans.length}')),
                    Expanded(
                      child: _statTile(
                        'Streak',
                        '$_currentStreak day${_currentStreak == 1 ? '' : 's'}',
                      ),
                    ),
                    Expanded(
                      child: _statTile('Current Phase', _currentPhaseShort()),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // ── HERO: Before/After slider ──────────────────────────────────
            _buildBeforeAfterSection(),
            const SizedBox(height: 14),
            if (_localProcedureDeltaPayload != null) ...[
              LuxeReportLayout(
                rawPayload: _localProcedureDeltaPayload!,
                baselineImageProvider: _baselinePhotoBytes != null
                    ? MemoryImage(_baselinePhotoBytes!)
                    : null,
                currentImageProvider: _latestPhotoBytes != null
                    ? MemoryImage(_latestPhotoBytes!)
                    : null,
                baselineLabel: 'Before',
                currentLabel: 'After',
              ),
              const SizedBox(height: 14),
              _metricsComparisonWidgetFromPayload(_localProcedureDeltaPayload!),
              const SizedBox(height: 14),
            ],
            // ── BBL-specific recovery metrics (body contouring only) ───────
            if (ProcedureIntelligence.categoryFor(_procedure.type) ==
                ProcedureCategory.bodyContouring) ...[
              _buildBBLRecoveryMetricsCard(),
              const SizedBox(height: 14),
            ],
            // ── Recovery Timeline — the central recovery roadmap ──────────
            RecoveryTimelineCard(
              procedureType: _procedure.type,
              startDate: _procedure.startDate,
              timelineMilestones: _procedure.timelineMilestones,
            ),
            const SizedBox(height: 14),
            // ── Surgeon's Recovery Plan ────────────────────────────────────
            _buildSurgeonPlanSection(),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Quick Actions',
              icon: Icons.bolt_outlined,
              eyebrow: 'Procedure tools & exports',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _openScanCapture,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Add Progress Scan'),
                    style: MyApp.primaryGoldButton,
                  ),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _showSurgeonPlanEditor,
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text("Surgeon's Recovery Plan"),
                    style: MyApp.secondaryOutlineButton(accent: MyApp.roseGold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AIRecoveryCoachScreen(
                                  procedure: _procedure,
                                ),
                              ),
                            );
                          },
                    icon: const Icon(Icons.psychology_alt_outlined),
                    label: const Text('AI Recovery Coach'),
                    style: MyApp.secondaryOutlineButton(accent: MyApp.roseGold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _exportProcedureReportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Export Report'),
                    style: MyApp.secondaryOutlineButton(accent: MyApp.roseGold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CustomRecoveryPlanScreen(
                                  procedure: _procedure,
                                ),
                              ),
                            );
                            await _refresh();
                          },
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('View Custom Recovery Plan'),
                    style: MyApp.secondaryOutlineButton(accent: MyApp.roseGold),
                  ),
                ],
              ),
            ),
            if (_procedure.customReminders.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Custom Reminders', style: MyApp.cardTitleStyle()),
              const SizedBox(height: 8),
              ..._procedure.customReminders.map(
                (r) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.notifications_none_outlined),
                    title: Text(r),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text('Journal Entries', style: MyApp.cardTitleStyle()),
                ),
                TextButton.icon(
                  onPressed: _addProcedureJournalEntry,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add entry'),
                  style: TextButton.styleFrom(foregroundColor: MyApp.roseGold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_procedure.journalEntries.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MyApp.roseGold.withValues(alpha: 0.10),
                        border: Border.all(
                          color: MyApp.roseGold.withValues(alpha: 0.30),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.menu_book_outlined,
                        color: MyApp.roseGold,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No journal entries yet',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: MyApp.clinicalNavy,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Capture how recovery feels day by day — even brief notes help reveal your healing pattern.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: MyApp.clinicalSlate,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._procedure.journalEntries.reversed.map(
                (entry) => Card(
                  child: ListTile(
                    title: Text(
                      entry.title.isEmpty ? 'Journal Entry' : entry.title,
                    ),
                    subtitle: Text(
                      entry.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _formatDate(entry.date),
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProcedureJournalEntryScreen(
                          procedure: _procedure,
                          entry: entry,
                          showSwelling: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: MyApp.roseGold,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: MyApp.textBrown.withValues(alpha: 0.65),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

class _ComparisonConfidence {
  _ComparisonConfidence({
    required this.label,
    required this.note,
    required this.color,
  });

  final String label;
  final String note;
  final Color color;
}

class ProcedureJournalEntryScreen extends StatelessWidget {
  const ProcedureJournalEntryScreen({
    super.key,
    required this.procedure,
    required this.entry,
    required this.showSwelling,
  });

  final Procedure procedure;
  final JournalEntry entry;
  final bool showSwelling;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: 'Journal Entry',
          eyebrow: 'Recovery log',
          color: MyApp.textBrown,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.textBrown,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(procedure.type, style: MyApp.sectionTitleStyle()),
          const SizedBox(height: 8),
          if (entry.title.isNotEmpty)
            Text(entry.title, style: MyApp.cardTitleStyle()),
          const SizedBox(height: 8),
          Text(
            entry.content,
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
          if (showSwelling && entry.swellingLevel != null) ...[
            const SizedBox(height: 12),
            Chip(
              label: Text(
                'Swelling ${entry.swellingLevel}/10 · ${entry.swellingLabel}',
              ),
            ),
          ],
          if ((entry.attachedImagePath ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child:
                  (entry.attachedImagePath!.startsWith('http') ||
                      entry.attachedImagePath!.startsWith('data:image'))
                  ? Image.network(entry.attachedImagePath!, fit: BoxFit.cover)
                  : buildLocalImagePreview(
                      entry.attachedImagePath!,
                      width: double.infinity,
                      height: 260,
                      borderRadius: 12,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Recovery Plan Screen
// Dedicated screen with Surgeon's Recovery Plan + AI-generated plan sections.
// ─────────────────────────────────────────────────────────────────────────────

class CustomRecoveryPlanScreen extends StatefulWidget {
  const CustomRecoveryPlanScreen({super.key, required this.procedure});
  final Procedure procedure;

  @override
  State<CustomRecoveryPlanScreen> createState() =>
      _CustomRecoveryPlanScreenState();
}

class _CustomRecoveryPlanScreenState extends State<CustomRecoveryPlanScreen> {
  late Procedure _procedure;
  List<CustomRecoveryPlan> _customPlans = const [];
  final bool _loading = false;
  bool _generating = false;
  bool _aiExpanded = true;

  @override
  void initState() {
    super.initState();
    _procedure = widget.procedure;
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    // Refresh procedure from storage to pick up latest notes
    final entries = await AppPrefs.getProcedureEntries();
    final idx = entries.indexWhere((e) => (e['id'] ?? '') == _procedure.id);
    if (idx != -1) {
      _procedure = Procedure.fromJson(Map<String, dynamic>.from(entries[idx]));
    }
    final raw = await PremiumRecoveryService.loadCustomPlans();
    final plans =
        raw
            .whereType<CustomRecoveryPlan>()
            .where(
              (p) =>
                  p.procedureType.toLowerCase() ==
                  _procedure.type.toLowerCase(),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (mounted) setState(() => _customPlans = plans);
  }

  Future<void> _saveSurgeonNotes(String text) async {
    final clamped = text.length > 4000 ? text.substring(0, 4000) : text;
    final updated = _procedure.copyWith(notes: clamped);
    await AppPrefs.updateProcedureInHistory(_procedure.id, updated.toJson());
    if (!mounted) return;
    setState(() => _procedure = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Surgeon instructions saved.')),
          ],
        ),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _generatePlan() async {
    final notes = _procedure.notes.trim();
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add your surgeon\'s instructions first, then generate a plan.',
          ),
        ),
      );
      return;
    }
    setState(() => _generating = true);
    try {
      final plan = await PremiumRecoveryService.buildCustomPlanFromNotes(
        notes: notes,
        procedureType: _procedure.type,
        startDate: _procedure.startDate,
      );
      final raw = await PremiumRecoveryService.loadCustomPlans();
      final existing = raw.whereType<CustomRecoveryPlan>().toList();
      await PremiumRecoveryService.saveCustomPlans(
        [plan, ...existing].map((e) => e.toJson()).toList(),
      );
      await _loadPlans();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI recovery plan generated.')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _openSurgeonEditor() async {
    final ctrl = TextEditingController(text: _procedure.notes);
    String? importedFileName;
    bool saving = false;
    bool processingOcr = false;
    bool ocrError = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final busy = saving || processingOcr;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: MyApp.champagne,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: MyApp.textBrown.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        color: MyApp.roseGold,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Surgeon's Recovery Plan",
                          style: MyApp.cardTitleStyle(),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                try {
                                  final result = await FilePicker.platform
                                      .pickFiles(
                                        type: FileType.custom,
                                        allowedExtensions: [
                                          'txt',
                                          'pdf',
                                          'doc',
                                          'docx',
                                          'rtf',
                                          'jpg',
                                          'jpeg',
                                          'png',
                                        ],
                                        withData: true,
                                      );
                                  if (result != null &&
                                      result.files.isNotEmpty) {
                                    final file = result.files.first;
                                    if (file.bytes != null) {
                                      if (OcrService.isImageFile(file.name)) {
                                        final prepared =
                                            await prepareWebUploadImage(
                                              file.bytes!,
                                              fileName: file.name,
                                            );
                                        if (!prepared.isSuccess) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  prepared.errorMessage!,
                                                ),
                                              ),
                                            );
                                          }
                                          return;
                                        }
                                        final normalizedBytes =
                                            prepared.image!.bytes;
                                        setInner(() {
                                          processingOcr = true;
                                          ocrError = false;
                                          importedFileName = file.name;
                                        });
                                        final text =
                                            await OcrService.performOcr(
                                              normalizedBytes,
                                              file.name,
                                            );
                                        if (text != null && text.isNotEmpty) {
                                          ctrl.text = text;
                                          setInner(() => processingOcr = false);
                                        } else {
                                          ctrl.clear();
                                          setInner(() {
                                            processingOcr = false;
                                            ocrError = true;
                                          });
                                        }
                                      } else {
                                        ctrl.text =
                                            _ProcedureDetailScreenState._extractFileText(
                                              file.name,
                                              file.bytes!,
                                            );
                                        setInner(() {
                                          importedFileName = file.name;
                                          ocrError = false;
                                        });
                                      }
                                    }
                                  }
                                } catch (_) {}
                              },
                        icon: const Icon(Icons.upload_file_outlined, size: 15),
                        label: const Text('Browse File'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MyApp.roseGold,
                          side: BorderSide(color: MyApp.roseGold),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Status row
                  if (processingOcr) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: MyApp.roseGold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Reading text from image…',
                          style: TextStyle(
                            fontSize: 12,
                            color: MyApp.textBrown.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ] else if (ocrError) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 14,
                          color: Colors.orange[700],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Text recognition failed. You can type the instructions manually.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (importedFileName != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: Colors.green[700],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Imported: $importedFileName',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Paste, type, or browse a file with your post-op instructions.',
                    style: TextStyle(
                      fontSize: 12,
                      color: MyApp.textBrown.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    maxLines: 8,
                    enabled: !processingOcr,
                    style: TextStyle(color: MyApp.textBrown, height: 1.4),
                    decoration: InputDecoration(
                      hintText:
                          'E.g. "Avoid sun for 2 weeks. Apply ointment twice daily..."',
                      hintStyle: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.40),
                        fontSize: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: MyApp.roseGold),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: MyApp.roseGold.withValues(alpha: 0.30),
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.55),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () {
                              final cleaned = OcrService.cleanText(ctrl.text);
                              ctrl.text = cleaned;
                              setInner(() {});
                            },
                      icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                      label: const Text('Clean Up Text'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyApp.roseGold,
                        side: BorderSide(
                          color: MyApp.roseGold.withValues(alpha: 0.55),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final text = ctrl.text.trim();
                              setInner(() => saving = true);
                              await _saveSurgeonNotes(text);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(saving ? 'Saving…' : 'Save Instructions'),
                      style: MyApp.primaryGoldButton,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final hasNotes = _procedure.notes.trim().isNotEmpty;
    final milestones = _procedure.timelineMilestones;
    final daysSince =
        DateTime.now().difference(_procedure.startDate).inDays + 1;

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: 'Custom Recovery Plan',
          eyebrow: 'Personalized protocol',
          color: MyApp.textBrown,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.textBrown,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                // ── Procedure header ──────────────────────────────────────
                _buildProcedureHeader(daysSince),
                const SizedBox(height: 22),

                // ── Section 1: Surgeon's Instructions ─────────────────────
                _buildSectionLabel(
                  step: '1',
                  icon: Icons.assignment_outlined,
                  title: "Surgeon's Instructions",
                  subtitle: 'Your official post-op care notes',
                ),
                const SizedBox(height: 10),
                _buildSurgeonCard(hasNotes, milestones),
                const SizedBox(height: 20),

                // ── Flow connector ────────────────────────────────────────
                _buildFlowConnector(hasNotes),
                const SizedBox(height: 20),

                // ── Section 2: AI Recovery Plan ───────────────────────────
                _buildAiSectionHeader(),
                if (_aiExpanded) ...[
                  const SizedBox(height: 10),
                  _buildAiPlanCard(hasNotes),
                ],
                const SizedBox(height: 8),
              ],
            ),
    );
  }

  // ── Procedure header ──────────────────────────────────────────────────────
  Widget _buildProcedureHeader(int daysSince) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MyApp.roseGold.withValues(alpha: 0.11),
            MyApp.goldShimmer.withValues(alpha: 0.07),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [MyApp.roseGold, MyApp.goldShimmer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.medical_services_outlined,
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
                  _procedure.type,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Started ${_formatDate(_procedure.startDate)} · Day $daysSince',
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.58),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label with numbered step circle ───────────────────────────────
  Widget _buildSectionLabel({
    required String step,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [MyApp.roseGold, MyApp.goldShimmer],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: MyApp.roseGold.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(
              step,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
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
                  Icon(icon, size: 14, color: MyApp.roseGold),
                  const SizedBox(width: 5),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: MyApp.textBrown,
                    ),
                  ),
                ],
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: MyApp.textBrown.withValues(alpha: 0.52),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Surgeon card ─────────────────────────────────────────────────────────
  Widget _buildSurgeonCard(bool hasNotes, List<dynamic> milestones) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasNotes
              ? MyApp.roseGold.withValues(alpha: 0.22)
              : MyApp.roseGold.withValues(alpha: 0.55),
          width: hasNotes ? 1.0 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.roseGold.withValues(alpha: 0.09),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: MyApp.roseGold.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: hasNotes ? _buildSurgeonFilled(milestones) : _buildSurgeonEmpty(),
    );
  }

  Widget _buildSurgeonFilled(List<dynamic> milestones) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status chip + Edit button row
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.green.withValues(alpha: 0.28)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 13,
                    color: Colors.green[700],
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Instructions on file',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _openSurgeonEditor,
              icon: Icon(Icons.edit_rounded, size: 14, color: MyApp.roseGold),
              label: Text(
                'Edit',
                style: TextStyle(
                  fontSize: 13,
                  color: MyApp.roseGold,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyApp.roseGold,
                side: BorderSide(color: MyApp.roseGold.withValues(alpha: 0.55)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Notes with rose-gold left accent bar
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [MyApp.roseGold, MyApp.goldShimmer],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MyApp.champagne.withValues(alpha: 0.42),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                      topLeft: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                  child: Text(
                    _procedure.notes.trim(),
                    style: TextStyle(
                      color: MyApp.textBrown.withValues(alpha: 0.83),
                      height: 1.55,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (milestones.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MyApp.roseGold.withValues(alpha: 0.08),
                  MyApp.goldShimmer.withValues(alpha: 0.04),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MyApp.roseGold.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: MyApp.roseGold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEXT MILESTONE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: MyApp.roseGold,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${milestones.first.label}  ·  ${_formatDate(milestones.first.expectedDate)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: MyApp.textBrown.withValues(alpha: 0.80),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSurgeonEmpty() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero icon + description centred
        Center(
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [
                      MyApp.roseGold.withValues(alpha: 0.16),
                      MyApp.goldShimmer.withValues(alpha: 0.09),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: MyApp.roseGold.withValues(alpha: 0.32),
                  ),
                ),
                child: Icon(
                  Icons.upload_file_outlined,
                  color: MyApp.roseGold,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Add Surgeon\'s Instructions',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: MyApp.textBrown,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Upload a document or type your post-op care notes,\nmedications, restrictions, and follow-up dates.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: MyApp.textBrown.withValues(alpha: 0.54),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        // Primary CTA — Browse File
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _openSurgeonEditor,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text(
              'Browse File',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: MyApp.primaryGoldButton,
          ),
        ),
        const SizedBox(height: 10),
        // OR divider
        Row(
          children: [
            Expanded(
              child: Divider(color: MyApp.roseGold.withValues(alpha: 0.22)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'or',
                style: TextStyle(
                  fontSize: 12,
                  color: MyApp.textBrown.withValues(alpha: 0.38),
                ),
              ),
            ),
            Expanded(
              child: Divider(color: MyApp.roseGold.withValues(alpha: 0.22)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Secondary CTA — Type Notes
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _openSurgeonEditor,
            icon: Icon(Icons.edit_rounded, size: 18, color: MyApp.roseGold),
            label: Text(
              'Type Notes',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: MyApp.roseGold,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyApp.roseGold,
              side: BorderSide(color: MyApp.roseGold, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Flow connector between sections ──────────────────────────────────────
  Widget _buildFlowConnector(bool hasNotes) {
    final Color lineColor = MyApp.roseGold.withValues(alpha: 0.25);
    return Center(
      child: Column(
        children: [
          // top fade-in line
          Container(
            width: 2,
            height: 18,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [lineColor.withValues(alpha: 0), lineColor],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // sparkle circle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasNotes
                  ? MyApp.goldShimmer.withValues(alpha: 0.16)
                  : MyApp.roseGold.withValues(alpha: 0.08),
              border: Border.all(
                color: hasNotes
                    ? MyApp.goldShimmer.withValues(alpha: 0.42)
                    : MyApp.roseGold.withValues(alpha: 0.22),
                width: 1.5,
              ),
              boxShadow: hasNotes
                  ? [
                      BoxShadow(
                        color: MyApp.goldShimmer.withValues(alpha: 0.22),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 18,
              color: hasNotes
                  ? MyApp.goldShimmer
                  : MyApp.roseGold.withValues(alpha: 0.42),
            ),
          ),
          // bottom fade-out line
          Container(
            width: 2,
            height: 18,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [lineColor, lineColor.withValues(alpha: 0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              hasNotes
                  ? 'AI analyses your surgeon\'s instructions to build a personalised recovery timeline'
                  : 'Add surgeon\'s instructions above to unlock AI plan generation',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: MyApp.textBrown.withValues(
                  alpha: hasNotes ? 0.60 : 0.36,
                ),
                fontStyle: hasNotes ? FontStyle.normal : FontStyle.italic,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── AI section collapsible header ─────────────────────────────────────────
  Widget _buildAiSectionHeader() {
    final planCount = _customPlans.length;
    return GestureDetector(
      onTap: () => setState(() => _aiExpanded = !_aiExpanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              MyApp.roseGold.withValues(alpha: 0.09),
              MyApp.goldShimmer.withValues(alpha: 0.05),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [MyApp.roseGold, MyApp.goldShimmer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Text(
                  '2',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI-Powered Recovery Plan',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: MyApp.textBrown,
                    ),
                  ),
                  Text(
                    planCount > 0
                        ? '$planCount plan${planCount == 1 ? "" : "s"} generated'
                        : 'Personalised from your surgeon\'s notes',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: MyApp.textBrown.withValues(alpha: 0.52),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              _aiExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              color: MyApp.roseGold,
            ),
          ],
        ),
      ),
    );
  }

  // ── AI plan content card ──────────────────────────────────────────────────
  Widget _buildAiPlanCard(bool hasNotes) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: MyApp.goldShimmer.withValues(alpha: 0.09),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: MyApp.goldShimmer.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasNotes) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 15, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add surgeon\'s instructions above first, then generate your AI plan.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generating ? null : _generatePlan,
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_fix_high_outlined, size: 18),
              label: Text(
                _generating ? 'Generating…' : 'Generate AI Recovery Plan',
              ),
              style: MyApp.primaryGoldButton,
            ),
          ),
          if (_customPlans.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Generated Plans',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: MyApp.textBrown,
              ),
            ),
            const SizedBox(height: 10),
            ..._customPlans.map((plan) => _buildPlanTile(plan)),
          ] else ...[
            const SizedBox(height: 14),
            Text(
              'No plans generated yet. Add surgeon instructions above and tap Generate.',
              style: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.58),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Individual AI plan tile ───────────────────────────────────────────────
  Widget _buildPlanTile(CustomRecoveryPlan plan) {
    final tileBackground = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : MyApp.champagne.withValues(alpha: 0.46);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tileBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: MyApp.roseGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 11,
                        color: MyApp.roseGold,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'AI Plan',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: MyApp.roseGold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(plan.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: MyApp.textBrown.withValues(alpha: 0.42),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              plan.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          if (plan.surgeonNotes.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text(
                plan.surgeonNotes.trim(),
                style: TextStyle(
                  color: MyApp.textBrown.withValues(alpha: 0.75),
                  height: 1.45,
                  fontSize: 13,
                ),
              ),
            )
          else
            const SizedBox(height: 12),
          if (plan.timelineMilestones.isNotEmpty) ...[
            Divider(height: 1, color: MyApp.roseGold.withValues(alpha: 0.12)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recovery Milestones',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: MyApp.textBrown,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...plan.timelineMilestones.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: MyApp.roseGold.withValues(alpha: 0.10),
                            ),
                            child: Icon(
                              Icons.check_outlined,
                              size: 11,
                              color: MyApp.roseGold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                if (m.description.isNotEmpty)
                                  Text(
                                    m.description,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: MyApp.textBrown.withValues(
                                        alpha: 0.60,
                                      ),
                                      height: 1.35,
                                    ),
                                  ),
                                Text(
                                  _formatDate(m.expectedDate),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: MyApp.textBrown.withValues(
                                      alpha: 0.42,
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
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
