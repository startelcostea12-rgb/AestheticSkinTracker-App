import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../utils/ai_scan_mode.dart';
import '../utils/app_prefs.dart';
import '../utils/app_logger.dart';
import '../app_theme.dart';
import '../models/procedure.dart';
import '../models/product_tracker.dart';
import '../models/scan_history.dart';
import 'active_skincare_details_screen.dart';
import 'package:aesthetic_skin_tracker/features/procedures/presentation/procedure_profiles_screen.dart';
import '../widgets/clinical_section_header.dart';
import '../widgets/luxe_report_layout.dart';
import '../utils/skin_scan_coach_copy.dart';
import '../utils/ai_product_recommendation_engine.dart';
import '../utils/report_flow.dart';
import '../widgets/product_recommendation_card.dart';
import '../utils/trend_label_resolver.dart';

Map<String, dynamic> _asDynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

/// The one authorized way this screen learns a metric's trend direction —
/// always sourced from the backend's trend_status/trend_lock_reason/
/// trend_deltas on [latest]'s raw payload, never recomputed locally from
/// two raw metric numbers. Returns null when the backend supplied no
/// verdict for this metric on this scan.
///
/// [metricKey] may be one of this screen's short display-key aliases
/// (e.g. "redness", "wrinkle") rather than the backend's canonical name
/// ("localized_redness", "wrinkle_load") — [shortMetricKeyToCanonical]
/// resolves that before looking up trend_status.
ResolvedTrendLabel? _resolveScanMetricTrend(
  ScanHistoryEntry latest,
  String metricKey,
) {
  final payload = _asDynamicMap(latest.rawPayload);
  final nestedLuxe = _asDynamicMap(payload['luxePayload']);

  Map<String, dynamic> preferNested(String key) {
    final nested = _asDynamicMap(nestedLuxe[key]);
    return nested.isNotEmpty ? nested : _asDynamicMap(payload[key]);
  }

  final trendStatusMap = preferNested('trend_status');
  final trendLockReasonsMap = preferNested('trend_lock_reasons');
  final trendDeltasMap = preferNested('trend_deltas');

  final canonicalKey = shortMetricKeyToCanonical[metricKey];
  final lookupKey = trendStatusMap.containsKey(metricKey)
      ? metricKey
      : (canonicalKey != null && trendStatusMap.containsKey(canonicalKey)
            ? canonicalKey
            : metricKey);

  final deltaRaw = trendDeltasMap[lookupKey];
  return resolveTrendLabel(
    trendStatus: trendStatusMap[lookupKey]?.toString(),
    trendLockReason: trendLockReasonsMap[lookupKey]?.toString(),
    trendDeltaPct: deltaRaw is num ? deltaRaw.toDouble() : null,
  );
}

String formatProgressReportTrendPercent({
  required String trendLabel,
  required double percentDelta,
  required bool isWorsened,
}) {
  final prefix = !isWorsened && percentDelta > 0 ? '+' : '';
  return '$trendLabel $prefix${percentDelta.abs().toStringAsFixed(1)}%';
}

enum ProgressReportViewMode { reports, scans }

class _ProcedureScanGroup {
  _ProcedureScanGroup({
    required this.key,
    required List<ScanHistoryEntry> scans,
    required this.baselineEntry,
    required this.latestEntry,
  }) : scans = List<ScanHistoryEntry>.from(scans)
         ..sort(_compareScansByTimestampAscThenId);

  final String key;
  final List<ScanHistoryEntry> scans;
  final ScanHistoryEntry baselineEntry;
  final ScanHistoryEntry latestEntry;

  static int _compareScansByTimestampAscThenId(
    ScanHistoryEntry a,
    ScanHistoryEntry b,
  ) {
    final ts = a.timestamp.compareTo(b.timestamp);
    if (ts != 0) return ts;
    return a.id.compareTo(b.id);
  }

  ScanHistoryEntry get baseline => baselineEntry;
  ScanHistoryEntry get latest => latestEntry;
  int get count => scans.length;

  String get title {
    final procedure = latest.procedure?.trim();
    if (procedure != null && procedure.isNotEmpty) return procedure;
    final baselineProcedure = baseline.procedure?.trim();
    if (baselineProcedure != null && baselineProcedure.isNotEmpty) {
      return baselineProcedure;
    }
    return 'Procedure Scan';
  }

  String get focus {
    final latestFocus = (latest.focusArea ?? latest.customDescription ?? '')
        .trim();
    if (latestFocus.isNotEmpty) return latestFocus;
    return (baseline.focusArea ?? baseline.customDescription ?? '').trim();
  }
}

class _MetricDelta {
  const _MetricDelta({
    required this.key,
    required this.label,
    required this.baselineValue,
    required this.latestValue,
    required this.hasValidComparison,
    this.isInitialBaseline = false,
    this.resolvedTrend,
  });

  final String key;
  final String label;
  final double baselineValue;
  final double latestValue;
  final bool hasValidComparison;
  final bool isInitialBaseline;

  /// Backend-authorized trend verdict for this metric; null means the
  /// backend supplied no trend_status for it, in which case no
  /// Improved/Worsened claim may be shown.
  final ResolvedTrendLabel? resolvedTrend;

  bool get improved => resolvedTrend?.isImproved ?? false;
  bool get worsened => resolvedTrend?.isWorsened ?? false;

  double get delta => latestValue - baselineValue;
  double get magnitude => delta.abs();
}

class ProgressReportScreen extends StatefulWidget {
  final bool showSkincareFirst; // New: control which tab opens first
  final int initialTabIndex;
  final ProgressReportViewMode viewMode;

  const ProgressReportScreen({
    super.key,
    this.showSkincareFirst = false,
    this.initialTabIndex = 0,
    this.viewMode = ProgressReportViewMode.reports,
  });

  @override
  State<ProgressReportScreen> createState() => _ProgressReportScreenState();
}

class _ProgressReportScreenState extends State<ProgressReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Procedure> _procedures = [];
  List<TrackedProduct> _trackedProducts = [];
  List<ScanHistoryEntry> _scanEntries = [];
  Map<String, Map<String, String?>> _procedurePhotoComparisonById = const {};
  bool _isLoading = true;
  int? _latestSkinAge;

  List<ScanHistoryEntry> _sanitizeScanEntries(List<ScanHistoryEntry> allScans) {
    bool hasPositiveValueInMap(Map<String, dynamic> source) {
      for (final value in source.values) {
        if (value is num && value.toDouble() > 0.0) return true;
      }
      return false;
    }

    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    bool hasDeepPositiveMetric(ScanHistoryEntry scan) {
      final raw = asMap(scan.rawPayload);
      if (raw.isEmpty) return false;
      if (hasPositiveValueInMap(raw)) return true;
      final matrix = asMap(raw['metric_matrix']);
      if (hasPositiveValueInMap(matrix)) return true;
      final opencv = asMap(raw['opencv_metrics']);
      if (hasPositiveValueInMap(opencv)) return true;
      final metrics = asMap(raw['metrics']);
      if (hasPositiveValueInMap(metrics)) return true;
      final nestedMatrix = asMap(metrics['metric_matrix']);
      if (hasPositiveValueInMap(nestedMatrix)) return true;
      final nestedOpencv = asMap(metrics['opencv_metrics']);
      if (hasPositiveValueInMap(nestedOpencv)) return true;
      return false;
    }

    final validScans = allScans.where((scan) {
      final metrics = scan.metrics;
      final hasFlattenedMetrics =
          metrics.isNotEmpty && metrics.values.any((val) => val > 0.0);
      return hasFlattenedMetrics || hasDeepPositiveMetric(scan);
    }).toList();
    validScans.sort(_ProcedureScanGroup._compareScansByTimestampAscThenId);
    return validScans;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.showSkincareFirst
          ? 2
          : widget.initialTabIndex.clamp(0, 3),
    );
    _loadScanHistory();
    _loadProcedures();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadScanHistory();
  }

  Future<void> _loadScanHistory() async {
    try {
      final allScans = await AppPrefs.getScanEntries();
      final validScans = _sanitizeScanEntries(allScans);
      for (final scan in validScans) {
        print('DEBUG SCAN ENTRY METRICS: ${scan.metrics}');
      }
      if (!mounted) return;
      setState(() {
        _scanEntries = validScans;
      });
    } catch (_) {
      // Ignore refresh errors here; full load path handles surface state.
    }
  }

  Future<void> _loadProcedures() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        AppPrefs.getProcedureEntries(),
        AppPrefs.getScanEntries(),
        AppPrefs.getTrackedProducts(),
      ]);
      final procedures =
          (results[0] as List<dynamic>)
              .map((json) => Procedure.fromJson(json as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.startDate.compareTo(a.startDate));

      final scans = _sanitizeScanEntries(results[1] as List<ScanHistoryEntry>);
      final products = (results[2] as List<TrackedProduct>)
        ..sort((a, b) => b.startDate.compareTo(a.startDate));
      final comparisonMapByProcedure = <String, Map<String, String?>>{};
      final procedureIds = scans
          .map((scan) => (scan.procedureId ?? '').trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final procedureId in procedureIds) {
        final comparison = await AppPrefs.getProcedurePhotoComparison(
          procedureId,
        );
        comparisonMapByProcedure[procedureId] = comparison;
      }
      int? skinAge;
      if (scans.isNotEmpty) {
        final latest = scans.reduce(
          (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
        );
        final estimated = latest.hasTrustworthyEstimatedSkinAge
            ? latest.estimatedSkinAge
            : null;
        skinAge = estimated?.round();
      }

      setState(() {
        _procedures = procedures;
        _trackedProducts = products;
        _scanEntries = scans;
        _procedurePhotoComparisonById = comparisonMapByProcedure;
        _latestSkinAge = skinAge;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<ScanHistoryEntry> _filteredScans(String? scanType) {
    if (scanType == null) return _scanEntries;
    return _scanEntries
        .where((scan) => scan.resolvedScanType == scanType)
        .toList();
  }

  List<_ProcedureScanGroup> _procedureScanGroups(List<ScanHistoryEntry> scans) {
    final grouped = <String, List<ScanHistoryEntry>>{};
    for (final scan in scans.where((scan) => scan.isProcedureScan)) {
      final keyParts = [
        (scan.procedureId ?? '').trim(),
        (scan.procedure ?? '').trim().toLowerCase(),
        (scan.focusArea ?? scan.customDescription ?? '').trim().toLowerCase(),
      ].where((part) => part.isNotEmpty).toList();
      final key = keyParts.isEmpty ? 'procedure' : keyParts.join('|');
      grouped.putIfAbsent(key, () => <ScanHistoryEntry>[]).add(scan);
    }

    final groups =
        grouped.entries.map((entry) {
          final ordered = List<ScanHistoryEntry>.from(entry.value)
            ..sort(_ProcedureScanGroup._compareScansByTimestampAscThenId);
          final procedureId = ordered
              .map((scan) => (scan.procedureId ?? '').trim())
              .firstWhere((id) => id.isNotEmpty, orElse: () => '');
          final comparison = procedureId.isNotEmpty
              ? _procedurePhotoComparisonById[procedureId]
              : null;

          final baselineScanId = comparison?['baselineScanId']?.trim();
          final latestScanId = comparison?['latestScanId']?.trim();

          ScanHistoryEntry? baseline;
          if (baselineScanId != null && baselineScanId.isNotEmpty) {
            for (final scan in ordered) {
              if (scan.id == baselineScanId) {
                baseline = scan;
                break;
              }
            }
          }
          baseline ??= ordered.first;

          ScanHistoryEntry? latest;
          if (latestScanId != null && latestScanId.isNotEmpty) {
            for (final scan in ordered.reversed) {
              if (scan.id == latestScanId) {
                latest = scan;
                break;
              }
            }
          }
          latest ??= ordered.last;

          return _ProcedureScanGroup(
            key: entry.key,
            scans: ordered,
            baselineEntry: baseline,
            latestEntry: latest,
          );
        }).toList()..sort((a, b) {
          final ts = b.latest.timestamp.compareTo(a.latest.timestamp);
          if (ts != 0) return ts;
          return a.latest.id.compareTo(b.latest.id);
        });
    return groups;
  }

  DateTime _repositoryItemTimestamp(Object item) {
    if (item is _ProcedureScanGroup) return item.latest.timestamp;
    return (item as ScanHistoryEntry).timestamp;
  }

  List<_MetricDelta> _metricDeltas(
    ScanHistoryEntry baseline,
    ScanHistoryEntry latest,
  ) {
    print('DEBUG SCAN ENTRY METRICS: ${baseline.metrics}');
    print('DEBUG SCAN ENTRY METRICS: ${latest.metrics}');
    final rows = <_MetricDelta>[];
    final baselineRows = ScanDetailScreen.displayMetricsFor(baseline);
    final latestRows = ScanDetailScreen.displayMetricsFor(latest);
    final isSingleScan = baseline.id == latest.id;

    if (isSingleScan) {
      for (final latestRow in latestRows) {
        final currentValue = ScanDetailScreen.normalizeMetricValueTo100(
          latestRow.key,
          ScanDetailScreen.extractBackendMetricValue(latest, latestRow.key),
        );
        if (!currentValue.isFinite || currentValue <= 0.0) {
          continue;
        }
        rows.add(
          _MetricDelta(
            key: latestRow.key,
            label: latestRow.label,
            baselineValue: currentValue,
            latestValue: currentValue,
            hasValidComparison: true,
            isInitialBaseline: true,
          ),
        );
      }
      rows.sort((a, b) => b.latestValue.compareTo(a.latestValue));
      return rows;
    }

    for (final latestRow in latestRows) {
      final baselineMatches = baselineRows.where(
        (row) => row.key == latestRow.key || row.label == latestRow.label,
      );
      if (baselineMatches.isEmpty) continue;
      final extractedBaseline = ScanDetailScreen.extractBackendMetricValue(
        baseline,
        latestRow.key,
      );
      final extractedCurrent = ScanDetailScreen.extractBackendMetricValue(
        latest,
        latestRow.key,
      );
      final normalizedBaselineValue =
          ScanDetailScreen.normalizeMetricValueTo100(
            latestRow.key,
            extractedBaseline,
          );
      final latestValue = ScanDetailScreen.normalizeMetricValueTo100(
        latestRow.key,
        extractedCurrent,
      );
      final baselineValue = ScanDetailScreen.normalizeLegacyBaselineForDelta(
        latestRow.key,
        normalizedBaselineValue,
        latestValue,
      );
      final hasValidComparison =
          baselineValue.isFinite &&
          latestValue.isFinite &&
          baselineValue > 0.0 &&
          latestValue > 0.0 &&
          ScanHistoryEntry.scanEnginesComparable(
            baseline.scanEngine,
            latest.scanEngine,
          );
      final delta = latestValue - baselineValue;

      if (hasValidComparison && delta.abs() < 0.05) continue;

      rows.add(
        _MetricDelta(
          key: latestRow.key,
          label: latestRow.label,
          baselineValue: baselineValue,
          latestValue: latestValue,
          hasValidComparison: hasValidComparison,
          resolvedTrend: _resolveScanMetricTrend(latest, latestRow.key),
        ),
      );
    }
    rows.sort((a, b) => b.magnitude.compareTo(a.magnitude));
    return rows;
  }

  ({IconData icon, String label, Color color}) _scanTypeMeta(
    ScanHistoryEntry scan,
  ) {
    switch (scan.resolvedScanType) {
      case ScanHistoryEntry.scanTypeAiAnalysis:
        return (
          icon: Icons.auto_awesome_rounded,
          label: 'AI Analysis',
          color: AppColors.champagneGold,
        );
      case ScanHistoryEntry.scanTypeSkincare:
        return (
          icon: Icons.spa_rounded,
          label: 'Skincare',
          // Scan-category label, not a metric status — must not borrow the
          // reserved improved/worsened green.
          color: AppColors.champagneGold,
        );
      default:
        return (
          icon: Icons.medical_services_outlined,
          label: 'Procedure',
          color: AppColors.refinedSlate,
        );
    }
  }

  Widget _buildScanRepositorySection(String? scanType) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final scans = _filteredScans(scanType);
    final List<Object> repositoryItems;
    if (scanType == ScanHistoryEntry.scanTypeProcedure) {
      repositoryItems = _procedureScanGroups(scans);
    } else if (scanType == null) {
      repositoryItems =
          <Object>[
            ..._procedureScanGroups(
              _filteredScans(ScanHistoryEntry.scanTypeProcedure),
            ),
            ..._scanEntries.where((scan) => !scan.isProcedureScan),
          ]..sort(
            (a, b) => _repositoryItemTimestamp(
              b,
            ).compareTo(_repositoryItemTimestamp(a)),
          );
    } else {
      repositoryItems = scans;
    }
    const title = 'No Scans Recorded Yet - Take Your First Scan';
    const subtitle =
        'Once you complete your first scan, your progress metrics will appear here.';

    if (scans.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borders),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.champagneGold,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MyApp.textBrown,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.66),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemCount: repositoryItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = repositoryItems[index];
        if (item is _ProcedureScanGroup) {
          return _buildProcedureScanGroupCard(item);
        }
        return _buildScanRepositoryCard(item as ScanHistoryEntry);
      },
    );
  }

  Widget _buildProcedureScanGroupCard(_ProcedureScanGroup group) {
    const meta = (
      icon: Icons.medical_services_outlined,
      label: 'Procedure Progress',
      color: AppColors.refinedSlate,
    );
    final deltas = _metricDeltas(group.baseline, group.latest);
    final displayableDeltas = deltas
        .where((delta) => !metricsWithHiddenTrendVerdicts.contains(delta.key))
        .toList();
    final hasInitialBaseline = displayableDeltas.any(
      (delta) => delta.isInitialBaseline,
    );
    final comparable = displayableDeltas.where(
      (delta) => delta.hasValidComparison,
    );
    final improvedCount = hasInitialBaseline
        ? 0
        : comparable.where((delta) => delta.improved).length;
    final worsenedCount = hasInitialBaseline
        ? 0
        : comparable.where((delta) => delta.worsened).length;
    final pendingCount = hasInitialBaseline
        ? 0
        : displayableDeltas.length - improvedCount - worsenedCount;
    final dateRange = group.count > 1
        ? '${_shortDate(group.baseline.timestamp)} -> ${_shortDate(group.latest.timestamp)}'
        : _shortDate(group.latest.timestamp);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  _ProcedureScanComparisonDetailScreen(group: group),
            ),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: meta.color.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: meta.color.withValues(alpha: 0.07),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 94,
                  height: 74,
                  child: Row(
                    children: [
                      Expanded(
                        child: _comparisonThumb(
                          group.baseline.imagePath,
                          'Base',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _comparisonThumb(group.latest.imagePath, 'Now'),
                      ),
                    ],
                  ),
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
                              group.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: MyApp.textBrown,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _scanTypeBadge(meta.icon, meta.label, meta.color),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$dateRange • ${group.count} upload${group.count == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.62),
                          fontSize: 11.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (group.focus.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          group.focus,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.refinedSlate.withValues(
                              alpha: 0.76,
                            ),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: displayableDeltas.isEmpty
                            ? [
                                _summaryChip(
                                  'Baseline saved',
                                  AppColors.champagneGold,
                                  Icons.flag_rounded,
                                ),
                              ]
                            : [
                                if (improvedCount > 0)
                                  _summaryChip(
                                    '$improvedCount improved',
                                    AppColors.mutedSage,
                                    Icons.trending_up_rounded,
                                  ),
                                if (worsenedCount > 0)
                                  _summaryChip(
                                    '$worsenedCount worsened',
                                    AppColors.softTerracotta,
                                    Icons.trending_down_rounded,
                                  ),
                                if (pendingCount > 0)
                                  _summaryChip(
                                    '$pendingCount pending baseline',
                                    AppColors.refinedSlate,
                                    Icons.schedule_rounded,
                                  ),
                                if (!hasInitialBaseline)
                                  ...displayableDeltas
                                      .take(2)
                                      .map(_deltaPreviewChip),
                              ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: meta.color.withValues(alpha: 0.74),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _comparisonThumb(String? imagePath, String label) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _scanImage(imagePath),
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.refinedSlate.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.4,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deltaPreviewChip(_MetricDelta delta) {
    final color = delta.improved
        ? AppColors.mutedSage
        : (delta.worsened ? AppColors.softTerracotta : AppColors.refinedSlate);
    final arrow = delta.improved
        ? Icons.arrow_upward_rounded
        : (delta.worsened
              ? Icons.warning_rounded
              : Icons.trending_flat_rounded);
    return _summaryChip(delta.label, color, arrow);
  }

  String _shortDate(DateTime timestamp) {
    final date = timestamp.toLocal();
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _buildScanRepositoryCard(ScanHistoryEntry scan) {
    final meta = _scanTypeMeta(scan);
    final focus = (scan.focusArea ?? scan.customDescription ?? '').trim();
    final title = scan.isAiAnalysisScan
        ? (isQuickAiScan(scan) ? 'AI Quick Scan' : 'AI Deep Analysis')
        : scan.isSkincareScan
        ? (scan.productName?.trim().isNotEmpty == true
              ? scan.productName!.trim()
              : 'Skincare Log')
        : ((scan.procedure ?? '').trim().isNotEmpty
              ? scan.procedure!.trim()
              : 'Procedure Scan');
    final metricPreview = ScanDetailScreen.displayMetricsFor(
      scan,
    ).take(3).toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ScanDetailScreen(scan: scan)),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: meta.color.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: meta.color.withValues(alpha: 0.07),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: SizedBox(
                    width: 74,
                    height: 74,
                    child: _scanImage(scan.imagePath),
                  ),
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
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: MyApp.textBrown,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _scanTypeBadge(meta.icon, meta.label, meta.color),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        scan.timestamp.toLocal().toString().split(' ').first,
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.62),
                          fontSize: 11.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (focus.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          focus,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.refinedSlate.withValues(
                              alpha: 0.76,
                            ),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (metricPreview.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: metricPreview
                              .map(
                                (entry) => _metricChip(
                                  entry.label,
                                  entry.value,
                                  meta.color,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: meta.color.withValues(alpha: 0.74),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportsLanding() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_scanEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borders),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.champagneGold,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  'No Scans Recorded Yet - Take Your First Scan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MyApp.textBrown,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Complete your first scan to unlock progress metrics and trend tracking.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.66),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final procedureScans = _filteredScans(ScanHistoryEntry.scanTypeProcedure);
    final skincareScans = _filteredScans(ScanHistoryEntry.scanTypeSkincare);
    final aiScans = _filteredScans(ScanHistoryEntry.scanTypeAiAnalysis);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.champagneGold.withValues(alpha: 0.24),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.refinedSlate.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                Icons.analytics_rounded,
                'Progress Journal',
                eyebrow: 'Reports & exports',
              ),
              const SizedBox(height: 12),
              Text(
                'Create provider-ready summaries from your procedure history, skincare logs, and scan archive.',
                style: TextStyle(
                  color: AppColors.refinedSlate.withValues(alpha: 0.72),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _reportStatTile(
                      'Scans',
                      _scanEntries.length.toString(),
                      Icons.photo_library_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _reportStatTile(
                      'Procedures',
                      _procedures.length.toString(),
                      Icons.medical_services_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _reportStatTile(
                      'AI',
                      aiScans.length.toString(),
                      Icons.auto_awesome_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _reportActionCard(
          icon: Icons.ios_share_rounded,
          title: 'Export Provider Report',
          subtitle:
              'Generate a polished PDF from the active procedure profile.',
          buttonLabel: 'Create Export',
          onPressed: () => runGatedReportFlow(context),
        ),
        const SizedBox(height: 12),
        _reportActionCard(
          icon: Icons.folder_special_rounded,
          title: 'Saved Exported Reports',
          subtitle: 'Review or download reports you already generated.',
          buttonLabel: 'Open Saved Reports',
          onPressed: () => Navigator.of(context).pushNamed('/report'),
        ),
        const SizedBox(height: 18),
        _sectionHeader(
          Icons.summarize_outlined,
          'Summary Sources',
          eyebrow: 'Progress data',
        ),
        const SizedBox(height: 12),
        _sourceSummaryCard(
          'Procedure Scans',
          '${procedureScans.length} captured',
          Icons.medical_services_outlined,
          AppColors.refinedSlate,
          () => _openScansTab(1),
        ),
        const SizedBox(height: 10),
        _sourceSummaryCard(
          'Skincare Logs',
          '${skincareScans.length} captured',
          Icons.spa_rounded,
          AppColors.champagneGold,
          () => _openScansTab(2),
        ),
        const SizedBox(height: 10),
        _sourceSummaryCard(
          'AI Deep Analysis',
          '${aiScans.length} captured',
          Icons.auto_awesome_rounded,
          AppColors.champagneGold,
          () => _openScansTab(3),
        ),
      ],
    );
  }

  Widget _reportStatTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warmAlabaster,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.champagneGold, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: MyApp.textBrown,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.62),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.2),
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.champagneGold, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: MyApp.textBrown,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.64),
                        fontSize: 12.3,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
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
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(buttonLabel),
              style: MyApp.primaryGoldButton,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceSummaryCard(
    String title,
    String subtitle,
    IconData icon,
    Color accent,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: MyApp.textBrown,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.62),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  void _openScansTab(int index) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ProgressReportScreen(
          viewMode: ProgressReportViewMode.scans,
          initialTabIndex: index,
        ),
      ),
    );
  }

  Widget _scanTypeBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(String key, double value, Color color) {
    final normalizedValue = ScanDetailScreen.normalizeMetricValueTo100(
      key,
      value,
    );
    final label = key.replaceAll('_', ' ').replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) {
        return '${match.group(1)} ${match.group(2)}';
      },
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warmAlabaster,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        '${label.toUpperCase()} ${normalizedValue.toStringAsFixed(1)}',
        style: TextStyle(
          color: MyApp.textBrown.withValues(alpha: 0.72),
          fontSize: 9.8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildProcedureList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_procedures.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MyApp.roseGold.withValues(alpha: 0.13),
                  MyApp.champagne.withValues(alpha: 0.92),
                  MyApp.goldShimmer.withValues(alpha: 0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: MyApp.roseGold.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: MyApp.goldShimmer.withValues(alpha: 0.18),
                width: 1.2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.insights,
                  size: 44,
                  color: MyApp.roseGold.withValues(alpha: 0.55),
                ),
                const SizedBox(height: 18),
                Text(
                  "No procedure progress reports yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    color: MyApp.textBrown.withValues(alpha: 0.8),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Your future progress reports will appear here, beautifully formatted and ready to share with your provider.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.2,
                    color: MyApp.textBrown.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w600,
                    height: 1.44,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _procedures.length,
      separatorBuilder: (_, __) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        final proc = _procedures[index];
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.97),
                MyApp.champagne.withValues(alpha: 0.93),
                MyApp.roseGold.withValues(alpha: 0.07),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: MyApp.roseGold.withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: MyApp.goldShimmer.withValues(alpha: 0.13),
              width: 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(18),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: proc.beforePhotoBytes != null
                  ? Image.memory(
                      proc.beforePhotoBytes!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    )
                  : Icon(
                      Icons.image,
                      size: 60,
                      color: MyApp.roseGold.withValues(alpha: 0.32),
                    ),
            ),
            title: Text(
              proc.type,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: MyApp.textBrown,
                fontSize: 19,
                letterSpacing: 0.12,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${proc.provider} � ${proc.numSessions} sessions',
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  "Started: ${proc.startDate.toString().split(' ')[0]}",
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.62),
                    fontSize: 13.2,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    // "Completed" is a genuine positive milestone (status
                    // green is appropriate); "Active" is a neutral lifecycle
                    // state, not a worsened signal, so it uses the brand
                    // accent rather than borrowing status-worsened.
                    color: proc.isCompleted
                        ? AppColors.kMetricImprovedColor.withValues(alpha: 0.12)
                        : AppColors.brandAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: proc.isCompleted
                          ? AppColors.kMetricImprovedColor.withValues(
                              alpha: 0.35,
                            )
                          : AppColors.brandAccent.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Text(
                    proc.isCompleted ? 'Completed' : 'Active',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: proc.isCompleted
                          ? AppColors.kMetricImprovedColor
                          : AppColors.brandAccent,
                    ),
                  ),
                ),
              ],
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: MyApp.goldShimmer,
              size: 28,
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProcedureDetailScreen(procedure: proc),
              ),
            ),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildSkincareSection() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTrackedSkincareList(),
          if (_trackedProducts.isNotEmpty) const SizedBox(height: 28),
          _sectionHeader(
            Icons.cake_outlined,
            'Estimated Skin Age',
            eyebrow: 'Biological indicator',
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MyApp.champagne.withValues(alpha: 0.97),
                  MyApp.goldShimmer.withValues(alpha: 0.13),
                  MyApp.roseGold.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: MyApp.roseGold.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: MyApp.goldShimmer.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              child: Column(
                children: [
                  ShaderMask(
                    shaderCallback: (b) => LinearGradient(
                      colors: [MyApp.goldShimmer, MyApp.roseGold],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(b),
                    child: Text(
                      _latestSkinAge != null ? '$_latestSkinAge' : '--',
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.0,
                        letterSpacing: -2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'years',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: MyApp.textBrown.withValues(alpha: 0.6),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _latestSkinAge != null
                        ? 'Based on your latest AI skin metrics'
                        : 'No Scans Recorded Yet - Take Your First Scan',
                    style: TextStyle(
                      color: MyApp.textBrown.withValues(alpha: 0.65),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Product Recommendations based on latest skin metrics
          FutureBuilder<List<ScanHistoryEntry>>(
            future: AppPrefs.getScanEntries(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }
              final scans = snapshot.data!;
              final latest = scans.reduce(
                (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
              );
              final latestMetrics = latest.toSkinMetrics();
              final recentProcedureTypes = scans
                  .map((s) => s.procedure?.trim())
                  .whereType<String>()
                  .where((p) => p.isNotEmpty && p.toLowerCase() != 'unknown')
                  .toSet()
                  .toList();
              final resolvedProcedureType = (() {
                final latestProcedure = (latest.procedure ?? '').trim();
                if (latestProcedure.isNotEmpty &&
                    latestProcedure.toLowerCase() != 'unknown') {
                  return latestProcedure;
                }
                if (recentProcedureTypes.isNotEmpty) {
                  return recentProcedureTypes.first;
                }
                return 'General Skincare';
              })();
              AppLogger.verbose(
                '[ProgressReportScreen] resolvedProcedureType=$resolvedProcedureType (recent=${recentProcedureTypes.join('|')})',
              );
              final recommendations =
                  AIProductRecommendationEngine.generateRecommendations(
                    latestMetrics,
                    procedureType: resolvedProcedureType,
                    maxRecommendations: 3,
                    userSkinConcerns: [
                      if (latestMetrics.redness > 6.0) 'redness',
                      if (latestMetrics.texture > 6.0) 'texture',
                      if (latestMetrics.wrinkle > 6.0) 'aging',
                      if (latestMetrics.pore > 6.0) 'pores',
                      if (latestMetrics.darkSpots > 6.0) 'pigmentation',
                      if (latestMetrics.elasticity < 4.8) 'firmness',
                      if (latestMetrics.redness > 6.0) 'sensitive',
                    ],
                    recentProcedureTypes:
                        resolvedProcedureType.toLowerCase() !=
                            'general skincare'
                        ? recentProcedureTypes
                        : null,
                  );
              return ClinicalProductRecommendationsSection(
                recommendations: recommendations,
                sectionSubtitle:
                    'Tailored to improve your current skin metrics',
              );
            },
          ),

          const SizedBox(height: 28),

          _sectionHeader(
            Icons.local_fire_department_outlined,
            'Scan Streaks',
            eyebrow: 'Consistency',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.97),
                  MyApp.champagne.withValues(alpha: 0.93),
                  MyApp.roseGold.withValues(alpha: 0.07),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: MyApp.roseGold.withValues(alpha: 0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: MyApp.goldShimmer.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFB36B), Color(0xFFFF7B5A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF7B5A).withValues(alpha: 0.30),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.whatshot_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Streak: 7 days',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: MyApp.textBrown,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Great consistency � keep it going!',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: MyApp.textBrown.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          _sectionHeader(
            Icons.compare_outlined,
            'Before & After',
            eyebrow: 'Visual evidence',
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<ScanHistoryEntry>>(
            future: AppPrefs.getScanEntries(),
            builder: (context, snapshot) {
              final skincareScans =
                  (snapshot.data ?? const <ScanHistoryEntry>[])
                      .where((s) {
                        // Include scans linked to a tracked skincare product OR
                        // general (non-procedure) progress scans. Exclude scans
                        // that belong to a tracked procedure.
                        final hasProcedure = (s.procedureId ?? '')
                            .trim()
                            .isNotEmpty;
                        final hasProduct = (s.productName ?? '')
                            .trim()
                            .isNotEmpty;
                        return hasProduct || !hasProcedure;
                      })
                      .where((s) => (s.imagePath ?? '').isNotEmpty)
                      .toList()
                    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
              final before = skincareScans.isNotEmpty
                  ? skincareScans.first
                  : null;
              final after = skincareScans.length > 1
                  ? skincareScans.last
                  : null;
              return Row(
                children: [
                  Expanded(child: _buildBeforeAfterCard('Before', before)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildBeforeAfterCard('After', after)),
                ],
              );
            },
          ),

          const SizedBox(height: 28),

          _sectionHeader(
            Icons.tips_and_updates_outlined,
            'Quick Tips',
            eyebrow: 'Expert guidance',
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.97),
                  MyApp.champagne.withValues(alpha: 0.93),
                  MyApp.roseGold.withValues(alpha: 0.07),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: MyApp.roseGold.withValues(alpha: 0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: MyApp.goldShimmer.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tipRow(
                    Icons.wb_sunny_outlined,
                    'Apply SPF every 2 hours outdoors',
                  ),
                  _tipRow(Icons.water_drop_outlined, 'Drink 2.5L water daily'),
                  _tipRow(Icons.bedtime_outlined, 'Gentle cleansing at night'),
                  _tipRow(
                    Icons.wb_iridescent_outlined,
                    'Consistent lighting for scans',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/camera'),
              icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
              label: const Text(
                'New Face Scan',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.roseGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackedSkincareList() {
    if (_trackedProducts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              MyApp.roseGold.withValues(alpha: 0.12),
              MyApp.champagne.withValues(alpha: 0.92),
              MyApp.goldShimmer.withValues(alpha: 0.10),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.spa_outlined,
              size: 40,
              color: MyApp.roseGold.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 14),
            Text(
              'No tracked skincare products yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: MyApp.textBrown.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Log a skincare product from Home to see its progress photos here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: MyApp.textBrown.withValues(alpha: 0.62),
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tracked Skincare Products',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: MyApp.textBrown,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_trackedProducts.length, (index) {
          final product = _trackedProducts[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.97),
                    MyApp.champagne.withValues(alpha: 0.93),
                    MyApp.roseGold.withValues(alpha: 0.07),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: MyApp.goldShimmer.withValues(alpha: 0.13),
                ),
                boxShadow: [
                  BoxShadow(
                    color: MyApp.roseGold.withValues(alpha: 0.07),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: _scanImage(product.photoPath),
                  ),
                ),
                title: Text(
                  product.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: MyApp.textBrown,
                    fontSize: 17,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.brand.isNotEmpty)
                      Text(
                        product.brand,
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      'Started: ${product.startDate.toString().split(' ')[0]}',
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.62),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: MyApp.goldShimmer,
                  size: 28,
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ActiveSkincareDetailsScreen(product: product),
                    ),
                  );
                  await _loadProcedures();
                },
              ),
            ),
          );
        }),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildImageCard(String label) {
    return _buildBeforeAfterCard(label, null);
  }

  Widget _buildBeforeAfterCard(String label, ScanHistoryEntry? scan) {
    final hasScan = scan != null;
    final dateLabel = hasScan
        ? scan.timestamp.toLocal().toString().split(' ')[0]
        : null;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: MyApp.roseGold.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Stack(
            children: [
              SizedBox(
                height: 170,
                width: double.infinity,
                child: _scanImage(scan?.imagePath),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              dateLabel ?? 'Awaiting scan',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: MyApp.textBrown.withValues(alpha: hasScan ? 0.85 : 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title, {String? eyebrow}) {
    return ClinicalSectionHeader(
      icon: icon,
      title: title,
      eyebrow: eyebrow,
      textColor: MyApp.textBrown,
    );
  }

  Widget _tipRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: MyApp.roseGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: MyApp.roseGold, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: MyApp.textBrown.withValues(alpha: 0.85),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanImage(String? path) {
    if (path == null || path.isEmpty) {
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Icon(Icons.image, size: 60, color: Colors.grey),
        ),
      );
    }
    if (kIsWeb ||
        path.startsWith('http') ||
        path.startsWith('blob:') ||
        path.startsWith('data:')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey[300],
          child: const Center(
            child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
          ),
        ),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey[300],
        child: const Center(
          child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showingScans = widget.viewMode == ProgressReportViewMode.scans;
    return Scaffold(
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: showingScans ? 'Scans' : 'Progress Reports',
          eyebrow: showingScans ? 'Scan archive' : 'Progress journal',
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.textBrown,
        bottom: showingScans
            ? PreferredSize(
                preferredSize: const Size.fromHeight(64),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: MyApp.goldShimmer.withValues(alpha: 0.25),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      indicator: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [MyApp.goldShimmer, AppColors.champagneGold],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: MyApp.roseGold.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: MyApp.textBrown.withValues(
                        alpha: 0.72,
                      ),
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: const [
                        Tab(text: 'All'),
                        Tab(text: 'Procedure Scans'),
                        Tab(text: 'Skincare Logs'),
                        Tab(text: 'AI Deep Analysis'),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
      backgroundColor: AppColors.canvas,
      body: showingScans
          ? TabBarView(
              controller: _tabController,
              children: [
                _buildScanRepositorySection(null),
                _buildScanRepositorySection(ScanHistoryEntry.scanTypeProcedure),
                _buildScanRepositorySection(ScanHistoryEntry.scanTypeSkincare),
                _buildScanRepositorySection(
                  ScanHistoryEntry.scanTypeAiAnalysis,
                ),
              ],
            )
          : _buildReportsLanding(),
      floatingActionButton: showingScans
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                final random = [
                  "You are radiant and beautiful.",
                  "Your skin glows with health.",
                  "You are worthy of self-care.",
                ].first;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(random)));
              },
              backgroundColor: MyApp.goldShimmer,
              label: const Text("Affirmation"),
              icon: const Icon(Icons.favorite),
            ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

class _ProcedureScanComparisonDetailScreen extends StatelessWidget {
  final _ProcedureScanGroup group;

  const _ProcedureScanComparisonDetailScreen({required this.group});

  @override
  Widget build(BuildContext context) {
    final baseline = group.baseline;
    final latest = group.latest;
    final focus = group.focus;
    final deltas = _metricDeltas(baseline, latest);
    final visibleDeltas = deltas
        .where(
          (delta) =>
              !delta.isInitialBaseline,
        )
        .toList();
    final displayableDeltas = deltas
        .where((delta) => !metricsWithHiddenTrendVerdicts.contains(delta.key))
        .toList();
    final hasInitialBaseline = displayableDeltas.any(
      (delta) => delta.isInitialBaseline,
    );
    final comparable = displayableDeltas.where(
      (delta) => delta.hasValidComparison,
    );
    final improvedCount = hasInitialBaseline
        ? 0
        : comparable.where((delta) => delta.improved).length;
    final worsenedCount = hasInitialBaseline
        ? 0
        : comparable.where((delta) => delta.worsened).length;
    final pendingCount = hasInitialBaseline
        ? 0
        : displayableDeltas.length - improvedCount - worsenedCount;

    return Scaffold(
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: group.title,
          eyebrow: 'Procedure comparison',
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.refinedSlate,
      ),
      backgroundColor: AppColors.canvas,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _photoPanel(
                  'Baseline',
                  baseline.imagePath,
                  baseline.timestamp,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _photoPanel(
                  'Most Recent',
                  latest.imagePath,
                  latest.timestamp,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _detailDecoration(AppColors.refinedSlate),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _badge(
                      Icons.medical_services_outlined,
                      'Procedure Progress',
                      AppColors.refinedSlate,
                    ),
                    const Spacer(),
                    Text(
                      '${group.count} upload${group.count == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: AppColors.refinedSlate.withValues(alpha: 0.62),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  group.title,
                  style: const TextStyle(
                    color: AppColors.refinedSlate,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (focus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    focus,
                    style: TextStyle(
                      color: AppColors.refinedSlate.withValues(alpha: 0.72),
                      fontSize: 13.4,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _infoPill(
                      Icons.flag_rounded,
                      'Baseline ${_shortDate(baseline.timestamp)}',
                      AppColors.champagneGold,
                    ),
                    _infoPill(
                      Icons.photo_camera_rounded,
                      'Latest ${_shortDate(latest.timestamp)}',
                      AppColors.refinedSlate,
                    ),
                    if (improvedCount > 0)
                      _infoPill(
                        Icons.trending_up_rounded,
                        '$improvedCount improved',
                        AppColors.mutedSage,
                      ),
                    if (worsenedCount > 0)
                      _infoPill(
                        Icons.trending_down_rounded,
                        '$worsenedCount worsened',
                        AppColors.softTerracotta,
                      ),
                    if (pendingCount > 0)
                      _infoPill(
                        Icons.schedule_rounded,
                        '$pendingCount pending baseline',
                        AppColors.refinedSlate,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const ClinicalSectionHeader(
            icon: Icons.insights_rounded,
            title: 'Metric Changes',
            textColor: AppColors.refinedSlate,
          ),
          const SizedBox(height: 10),
          if (visibleDeltas.isEmpty)
            _emptyMetricsCard()
          else
            ...visibleDeltas.map(_metricDeltaRow),
        ],
      ),
    );
  }

  Widget _photoPanel(String label, String? imagePath, DateTime timestamp) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 0.82,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _scanImage(imagePath),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.refinedSlate.withValues(alpha: 0.76),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _shortDate(timestamp),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricDeltaRow(_MetricDelta delta) {
    final baselineValue = delta.baselineValue;
    final currentValue = delta.latestValue;
    print(
      'REPORT CARD [${delta.label}]: Baseline=$baselineValue -> Current=$currentValue',
    );
    final adjustedBaselineForDelta =
        ScanDetailScreen.normalizeLegacyBaselineForDelta(
          delta.key,
          baselineValue,
          currentValue,
        );
    final hasNonPositiveBaselineOrCurrent =
        baselineValue <= 0.0 || currentValue <= 0.0;
    final baselinePresent =
        adjustedBaselineForDelta.isFinite && adjustedBaselineForDelta > 0.0;
    final currentPresent = currentValue.isFinite && currentValue > 0.0;
    final canShowPercentageBadge =
        !hasNonPositiveBaselineOrCurrent && baselinePresent && currentPresent;
    // Trend wording/coloring requires BOTH a numerically valid comparison
    // AND a real backend trend_status verdict — never derived from the raw
    // sign of currentValue - baselineValue on its own.
    final resolvedTrend = delta.resolvedTrend;
    final isHiddenTrendMetric = metricsWithHiddenTrendVerdicts.contains(
      delta.key,
    );
    final canShowTrendBadge =
        !isHiddenTrendMetric && canShowPercentageBadge && resolvedTrend != null;
    final color = canShowTrendBadge
        ? (resolvedTrend.isImproved
              ? AppColors.mutedSage
              : resolvedTrend.isWorsened
              ? AppColors.softTerracotta
              : AppColors.refinedSlate)
        : AppColors.refinedSlate;
    final directionIcon = delta.delta > 0
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;
    final percentDelta = canShowPercentageBadge
        ? ((currentValue - adjustedBaselineForDelta) /
                  adjustedBaselineForDelta) *
              100.0
        : 0.0;
    double? badgePercent = canShowTrendBadge ? percentDelta : null;
    final trendLabel = canShowTrendBadge
        ? (resolvedTrend.lockHeadline ?? resolvedTrend.label)
        : null;
    String subtext;
    if (isHiddenTrendMetric) {
      badgePercent = null;
      final lockReason = resolvedTrend?.lockReason;
      subtext = lockReason == null
          ? 'Recorded'
          : 'Not comparable: ${resolvedTrend?.lockShortLabel ?? lockReason}';
    } else if (!canShowTrendBadge) {
      badgePercent = null;
      subtext = 'Tracks visible appearance in key zones';
    } else {
      subtext = formatProgressReportTrendPercent(
        trendLabel: trendLabel ?? '',
        percentDelta: percentDelta,
        isWorsened: resolvedTrend?.isWorsened ?? false,
      );
    }
    final deltaTextColor = canShowTrendBadge
        ? color
        : AppColors.refinedSlate.withValues(alpha: 0.72);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    delta.label,
                    style: const TextStyle(
                      color: AppColors.refinedSlate,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (badgePercent != null &&
                    currentValue > 0.0 &&
                    baselineValue > 0.0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(directionIcon, color: color, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          formatProgressReportTrendPercent(
                            trendLabel: trendLabel ?? '',
                            percentDelta: badgePercent,
                            isWorsened: resolvedTrend?.isWorsened ?? false,
                          ),
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtext,
              style: TextStyle(
                color: deltaTextColor,
                fontSize: 11.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _valueColumn('Baseline', baselineValue)),
                const SizedBox(width: 10),
                Expanded(child: _valueColumn('Latest', currentValue)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: ScanDetailScreen._metricProgressValue(currentValue),
                backgroundColor: AppColors.borders.withValues(alpha: 0.65),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _valueColumn(String label, double value) {
    final normalized = ScanDetailScreen.normalizeMetricValueTo100(label, value);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warmAlabaster,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            normalized.toStringAsFixed(1),
            style: const TextStyle(
              color: AppColors.refinedSlate,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: AppColors.refinedSlate.withValues(alpha: 0.62),
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.refinedSlate,
              fontSize: 11.8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyMetricsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borders),
      ),
      child: Text(
        'No shared metric changes were saved between the baseline and latest upload yet.',
        style: TextStyle(
          color: AppColors.refinedSlate.withValues(alpha: 0.66),
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }

  BoxDecoration _detailDecoration(Color accent) {
    return BoxDecoration(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: accent.withValues(alpha: 0.24)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  Widget _scanImage(String? path) {
    final cleanPath = path?.trim() ?? '';
    if (cleanPath.isEmpty) return _emptyImage(Icons.image);
    if (cleanPath.startsWith('data:image')) {
      final comma = cleanPath.indexOf(',');
      if (comma == -1) return _emptyImage(Icons.broken_image);
      try {
        return Image.memory(
          base64Decode(cleanPath.substring(comma + 1)),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _emptyImage(Icons.broken_image),
        );
      } catch (_) {
        return _emptyImage(Icons.broken_image);
      }
    }
    if (cleanPath.startsWith('http') || cleanPath.startsWith('blob:')) {
      return Image.network(
        cleanPath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _emptyImage(Icons.broken_image),
      );
    }
    if (kIsWeb) return _emptyImage(Icons.broken_image);
    return Image.file(
      File(cleanPath),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _emptyImage(Icons.broken_image),
    );
  }

  Widget _emptyImage(IconData icon) {
    return Container(
      color: AppColors.borders,
      child: Center(
        child: Icon(
          icon,
          size: 52,
          color: AppColors.refinedSlate.withValues(alpha: 0.36),
        ),
      ),
    );
  }

  static List<_MetricDelta> _metricDeltas(
    ScanHistoryEntry baseline,
    ScanHistoryEntry latest,
  ) {
    print('DEBUG SCAN ENTRY METRICS: ${baseline.metrics}');
    print('DEBUG SCAN ENTRY METRICS: ${latest.metrics}');
    final rows = <_MetricDelta>[];
    final baselineRows = ScanDetailScreen.displayMetricsFor(baseline);
    final latestRows = ScanDetailScreen.displayMetricsFor(latest);
    final isSingleScan = baseline.id == latest.id;

    if (isSingleScan) {
      for (final latestRow in latestRows) {
        final currentValue = ScanDetailScreen.normalizeMetricValueTo100(
          latestRow.key,
          ScanDetailScreen.extractBackendMetricValue(latest, latestRow.key),
        );
        if (!currentValue.isFinite || currentValue <= 0.0) continue;
        rows.add(
          _MetricDelta(
            key: latestRow.key,
            label: latestRow.label,
            baselineValue: currentValue,
            latestValue: currentValue,
            hasValidComparison: true,
            isInitialBaseline: true,
          ),
        );
      }
      rows.sort((a, b) => b.latestValue.compareTo(a.latestValue));
      return rows;
    }

    for (final latestRow in latestRows) {
      final baselineMatches = baselineRows.where(
        (row) => row.key == latestRow.key || row.label == latestRow.label,
      );
      if (baselineMatches.isEmpty) continue;
      final extractedBaseline = ScanDetailScreen.extractBackendMetricValue(
        baseline,
        latestRow.key,
      );
      final extractedCurrent = ScanDetailScreen.extractBackendMetricValue(
        latest,
        latestRow.key,
      );
      final normalizedBaselineValue =
          ScanDetailScreen.normalizeMetricValueTo100(
            latestRow.key,
            extractedBaseline,
          );
      final latestValue = ScanDetailScreen.normalizeMetricValueTo100(
        latestRow.key,
        extractedCurrent,
      );
      final baselineValue = ScanDetailScreen.normalizeLegacyBaselineForDelta(
        latestRow.key,
        normalizedBaselineValue,
        latestValue,
      );
      final hasValidComparison =
          baselineValue.isFinite &&
          latestValue.isFinite &&
          baselineValue > 0.0 &&
          latestValue > 0.0 &&
          ScanHistoryEntry.scanEnginesComparable(
            baseline.scanEngine,
            latest.scanEngine,
          );
      final delta = latestValue - baselineValue;

      if (hasValidComparison && delta.abs() < 0.05) continue;

      rows.add(
        _MetricDelta(
          key: latestRow.key,
          label: latestRow.label,
          baselineValue: baselineValue,
          latestValue: latestValue,
          hasValidComparison: hasValidComparison,
          resolvedTrend: _resolveScanMetricTrend(latest, latestRow.key),
        ),
      );
    }
    rows.sort((a, b) => b.magnitude.compareTo(a.magnitude));
    return rows;
  }

  static String _shortDate(DateTime timestamp) {
    final date = timestamp.toLocal();
    return '${date.month}/${date.day}/${date.year}';
  }
}

class ScanDetailScreen extends StatelessWidget {
  final ScanHistoryEntry scan;

  const ScanDetailScreen({super.key, required this.scan});

  ({IconData icon, String label, Color color}) get _meta {
    switch (scan.resolvedScanType) {
      case ScanHistoryEntry.scanTypeAiAnalysis:
        return (
          icon: Icons.auto_awesome_rounded,
          label: isQuickAiScan(scan) ? 'AI Quick Scan' : 'AI Deep Analysis',
          color: AppColors.champagneGold,
        );
      case ScanHistoryEntry.scanTypeSkincare:
        return (
          icon: Icons.spa_rounded,
          label: 'Skincare Log',
          color: AppColors.champagneGold,
        );
      default:
        return (
          icon: Icons.medical_services_outlined,
          label: 'Procedure Scan',
          color: AppColors.refinedSlate,
        );
    }
  }

  String get _title {
    if (scan.isAiAnalysisScan) {
      return isQuickAiScan(scan) ? 'AI Quick Scan' : 'AI Deep Analysis';
    }
    if (scan.isSkincareScan) {
      return scan.productName?.trim().isNotEmpty == true
          ? scan.productName!.trim()
          : 'Skincare Log';
    }
    return scan.procedure?.trim().isNotEmpty == true
        ? scan.procedure!.trim()
        : 'Procedure Scan';
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    final focus = (scan.focusArea ?? scan.customDescription ?? '').trim();
    final metrics = _displayMetrics;
    final insightRows = _insightRows(metrics);
    final qualityRows = <({String label, String value})>[
      if (scan.hasTrustworthyEstimatedSkinAge)
        (
          label: 'Estimated Skin Age',
          value: scan.estimatedSkinAge.toStringAsFixed(0),
        )
      else if (scan.estimatedSkinAge > 0)
        (label: 'Estimated Skin Age', value: 'Estimate unavailable'),
      if (scan.lightingConfidence != null)
        (
          label: 'Lighting Confidence',
          value: _percent(scan.lightingConfidence!),
        ),
      if (scan.distanceEstimate != null)
        (label: 'Framing Quality', value: _percent(scan.distanceEstimate!)),
      if (scan.expressionConfidence != null)
        (
          label: 'Expression Confidence',
          value: _percent(scan.expressionConfidence!),
        ),
      if (scan.headTiltAngle != null)
        (
          label: 'Head Tilt',
          value: '${scan.headTiltAngle!.toStringAsFixed(1)} deg',
        ),
    ];
    final archivedAiPayload = scan.isAiAnalysisScan
        ? _buildLuxePayloadForAiScan()
        : const <String, dynamic>{};
    final archivedAiHistoryCount = scan.isAiAnalysisScan
        ? _archivePayloadHistoryCount(archivedAiPayload)
        : 0;
    final archivedAiHasComparison = scan.isAiAnalysisScan
        ? _archiveHasResolvedComparison(archivedAiPayload)
        : false;

    return Scaffold(
      appBar: AppBar(
        title: ClinicalAppBarTitle(title: _title, eyebrow: meta.label),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.refinedSlate,
      ),
      backgroundColor: AppColors.canvas,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: meta.color.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.refinedSlate.withValues(alpha: 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: AspectRatio(
                aspectRatio: 1,
                child: _scanImage(scan.imagePath),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _detailDecoration(meta.color),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wrap, not Row: on narrow phones the timestamp drops below
                // the badge instead of overflowing.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _badge(meta.icon, meta.label, meta.color),
                    Text(
                      scan.timestamp.toLocal().toString().split('.').first,
                      style: TextStyle(
                        color: AppColors.refinedSlate.withValues(alpha: 0.62),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _title,
                  style: const TextStyle(
                    color: AppColors.refinedSlate,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (focus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    focus,
                    style: TextStyle(
                      color: AppColors.refinedSlate.withValues(alpha: 0.72),
                      fontSize: 13.4,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (scan.isBaseline)
                      _noticeChip(
                        Icons.flag_rounded,
                        'Baseline reference',
                        AppColors.champagneGold,
                      ),
                    if (scan.preferredReference)
                      _noticeChip(
                        Icons.star_rounded,
                        'Preferred reference',
                        AppColors.champagneGold,
                      ),
                    if (scan.makeupPresent)
                      _noticeChip(
                        Icons.info_outline_rounded,
                        'Makeup/product noted',
                        AppColors.softTerracotta,
                      ),
                    if (_engineChip(scan.scanEngine) != null)
                      _engineChip(scan.scanEngine)!,
                  ],
                ),
              ],
            ),
          ),
          if (insightRows.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionTitle(Icons.auto_awesome_rounded, 'AI Insights & Notes'),
            const SizedBox(height: 10),
            _insightsCard(insightRows, meta.color),
          ],
          if (qualityRows.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionTitle(Icons.tune_rounded, 'Capture Quality'),
            const SizedBox(height: 10),
            _qualityGrid(qualityRows),
          ],
          const SizedBox(height: 18),
          if (scan.isAiAnalysisScan) ...[
            _sectionTitle(
              Icons.insights_rounded,
              isQuickAiScan(scan) ? 'AI Quick Scan' : 'AI Deep Analysis',
            ),
            const SizedBox(height: 10),
            LuxeReportLayout(
              rawPayload: archivedAiPayload,
              localHistoryCount: archivedAiHistoryCount,
              isFollowUp: archivedAiHasComparison,
              gateReason: archivedAiHasComparison
                  ? 'archived follow-up rendered from resolved baseline data'
                  : 'archived baseline rendered in read-only mode',
            ),
            const SizedBox(height: 18),
            _sectionTitle(Icons.psychology_rounded, 'AI Coach Insight'),
            const SizedBox(height: 10),
            _coachInsightCard(archivedAiPayload: archivedAiPayload),
            const SizedBox(height: 14),
            _coachRoutineCard(archivedAiPayload: archivedAiPayload),
          ] else ...[
            _sectionTitle(Icons.insights_rounded, 'Metrics'),
            const SizedBox(height: 10),
            ..._buildMetricRows(meta.color),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic> _buildLuxePayloadForAiScan() {
    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    double? readMetricMatrixValue(Map<String, dynamic> data, String key) {
      final metricMatrix = asMap(data['metric_matrix']);
      final raw = metricMatrix[key];
      if (raw is num && raw.isFinite) return raw.toDouble();

      final nestedMetrics = asMap(data['metrics']);
      final nestedMetricMatrix = asMap(nestedMetrics['metric_matrix']);
      final nestedRaw = nestedMetricMatrix[key];
      if (nestedRaw is num && nestedRaw.isFinite) return nestedRaw.toDouble();

      return null;
    }

    final rawPayloadMap = asMap(scan.rawPayload);
    final mergedPayload = <String, dynamic>{...rawPayloadMap};

    final liveLuxePayload = asMap(rawPayloadMap['luxePayload']);
    if (liveLuxePayload.isNotEmpty) {
      mergedPayload.addAll(liveLuxePayload);
      mergedPayload['metrics'] = {
        ...asMap(mergedPayload['metrics']),
        ...asMap(liveLuxePayload['metrics']),
      };
      mergedPayload['metric_matrix'] = {
        ...asMap(mergedPayload['metric_matrix']),
        ...asMap(liveLuxePayload['metric_matrix']),
      };
      mergedPayload['trend_deltas'] = {
        ...asMap(mergedPayload['trend_deltas']),
        ...asMap(liveLuxePayload['trend_deltas']),
      };
      mergedPayload['trend_status'] = {
        ...asMap(mergedPayload['trend_status']),
        ...asMap(liveLuxePayload['trend_status']),
      };
      // The addAll above just overwrote metric_extraction_paths /
      // baseline_metric_extraction_paths with liveLuxePayload's copies
      // (nested under rawPayload['luxePayload'], written once at save
      // time and never updated again). rawPayloadMap's top-level copies
      // are the ones kept in sync by _mergePayloadForPersistence, so they
      // must win here the same way the four fields above are reconciled
      // -- otherwise every metric's extraction path silently reads from a
      // stale nested duplicate instead of the maintained top-level field.
      mergedPayload['metric_extraction_paths'] = {
        ...asMap(liveLuxePayload['metric_extraction_paths']),
        ...asMap(rawPayloadMap['metric_extraction_paths']),
      };
      mergedPayload['baseline_metric_extraction_paths'] = {
        ...asMap(liveLuxePayload['baseline_metric_extraction_paths']),
        ...asMap(rawPayloadMap['baseline_metric_extraction_paths']),
      };
    }

    if (scan.metrics.isNotEmpty) {
      final metricsMap = Map<String, dynamic>.from(scan.metrics);
      final nestedMetrics = asMap(mergedPayload['metrics']);
      mergedPayload['metrics'] = {...metricsMap, ...nestedMetrics};
    }

    DateTime? parseTimestamp(dynamic input) {
      if (input is DateTime) return input;
      final raw = input?.toString();
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    final scansNode = mergedPayload['_scans'];
    final payloadScans = <Map<String, dynamic>>[];
    if (scansNode is List) {
      for (final item in scansNode) {
        final map = asMap(item);
        if (map.isNotEmpty) payloadScans.add(map);
      }
      payloadScans.sort((a, b) {
        final aTime = parseTimestamp(a['timestamp']);
        final bTime = parseTimestamp(b['timestamp']);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return -1;
        if (bTime == null) return 1;
        return aTime.compareTo(bTime);
      });
    }

    final Map<String, dynamic> baselineMap;
    if (payloadScans.length >= 2) {
      baselineMap = payloadScans.first;
    } else if (payloadScans.length == 1) {
      baselineMap = payloadScans.first;
    } else {
      baselineMap = asMap(mergedPayload['baseline']);
    }

    final source = ScanDetailScreen.backendMetricSource(scan.metrics);
    final matrix = <String, dynamic>{};
    for (final entry in source.entries) {
      final normalized = entry.value.clamp(0.0, 100.0).toDouble();
      if (!normalized.isFinite || normalized <= 0.0) continue;
      matrix[entry.key] = normalized;
    }

    final baselineMatrix = <String, dynamic>{};
    final currentMatrix = <String, dynamic>{};
    for (final entry in matrix.entries) {
      final key = entry.key;
      final currentValue = (entry.value as num).toDouble();
      if (!currentValue.isFinite || currentValue <= 0.0) continue;

      currentMatrix[key] = currentValue;

      final baselineFromScan = readMetricMatrixValue(baselineMap, key);
      final baselineFromMerged = readMetricMatrixValue(mergedPayload, key);
      final baselineValue = baselineFromScan ?? baselineFromMerged;
      if (baselineValue == null ||
          !baselineValue.isFinite ||
          baselineValue <= 0.0) {
        continue;
      }
      baselineMatrix[key] = baselineValue.clamp(0.0, 100.0).toDouble();
    }

    final initialBaseline = payloadScans.length == 1;

    final topLevelTrendDeltas = asMap(mergedPayload['trend_deltas']);
    final topLevelTrendStatus = asMap(mergedPayload['trend_status']);
    final trendDeltas = <String, dynamic>{};
    final trendStatus = <String, dynamic>{};
    for (final key in currentMatrix.keys) {
      final rawDelta = topLevelTrendDeltas[key];
      final parsedDelta = rawDelta is num
          ? rawDelta.toDouble()
          : double.tryParse(rawDelta?.toString() ?? '');
      final rawStatus = topLevelTrendStatus[key]?.toString().trim();
      final hasBackendTrendDelta = parsedDelta != null && parsedDelta.isFinite;
      final hasBackendTrendStatus = rawStatus != null && rawStatus.isNotEmpty;

      if (hasBackendTrendDelta && hasBackendTrendStatus) {
        trendDeltas[key] = parsedDelta;
        trendStatus[key] = rawStatus;
      } else if (!initialBaseline) {
        debugPrint(
          'ARCHIVE TREND FALLBACK [$key]: missing payload.trend_deltas/trend_status entry; Luxe parser will recompute for legacy payload.',
        );
      }
    }

    final rawMetricExtractionPaths = asMap(
      rawPayloadMap['metric_extraction_paths'],
    );
    final mergedMetricExtractionPaths = asMap(
      mergedPayload['metric_extraction_paths'],
    );
    final metricExtractionPaths = rawMetricExtractionPaths.isNotEmpty
        ? rawMetricExtractionPaths
        : mergedMetricExtractionPaths;
    final rawBaselineExtractionPaths = asMap(
      rawPayloadMap['baseline_metric_extraction_paths'],
    );
    final mergedBaselineExtractionPaths = asMap(
      mergedPayload['baseline_metric_extraction_paths'],
    );
    final baselineMetricExtractionPaths = rawBaselineExtractionPaths.isNotEmpty
        ? rawBaselineExtractionPaths
        : mergedBaselineExtractionPaths;

    return {
      'metric_matrix': matrix,
      'trend_deltas': trendDeltas,
      'trend_status': trendStatus,
      'metric_extraction_paths': metricExtractionPaths,
      'baseline_metric_extraction_paths': baselineMetricExtractionPaths,
      'baseline': {'metric_matrix': baselineMatrix},
      'current': {'metric_matrix': currentMatrix},
      'initial_baseline': initialBaseline,
      '_scans': payloadScans,
      'metrics': {
        'metric_matrix': matrix,
        'trend_deltas': trendDeltas,
        'trend_status': trendStatus,
      },
    };
  }

  int _archivePayloadHistoryCount(Map<String, dynamic> payload) {
    final scansNode = payload['_scans'];
    if (scansNode is List) {
      return scansNode.length;
    }
    return 1;
  }

  bool _archiveHasResolvedComparison(Map<String, dynamic> payload) {
    final baselineNode = _asMap(payload['baseline']);
    final baselineMatrix = _asMap(baselineNode['metric_matrix']);
    return baselineMatrix.isNotEmpty;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  Map<String, double> _archivedCoachScores() {
    final backend = ScanDetailScreen.backendMetricSource(scan.metrics);
    double? read(String key) {
      final value = backend[key];
      if (value == null || !value.isFinite) return null;
      return (value / 10.0).clamp(0.0, 10.0).toDouble();
    }

    final scores = <String, double>{};
    final redness = read('localized_redness');
    if (redness != null) scores['redness'] = redness;

    final textureSmoothness = backend['texture_smoothness'];
    if (textureSmoothness != null && textureSmoothness.isFinite) {
      scores['texture'] = ((100.0 - textureSmoothness) / 10.0)
          .clamp(0.0, 10.0)
          .toDouble();
    }

    final pore = read('pore_visibility');
    if (pore != null) scores['pore'] = pore;

    final breakout = read('breakout_activity');
    if (breakout != null) scores['acne_severity'] = breakout;

    final pigment = read('pigment_load');
    if (pigment != null) scores['pigment'] = pigment;

    final wrinkle = read('wrinkle_load');
    if (wrinkle != null) scores['wrinkle'] = wrinkle;

    final rosacea = read('rosacea_severity');
    if (rosacea != null) scores['rosacea_intensity'] = rosacea;

    return scores;
  }

  Map<String, double> _archivedTrendDeltas() {
    final raw = scan.rawPayload ?? const <String, dynamic>{};
    final trendNode = <String, dynamic>{
      ..._asMap(raw['trend_deltas']),
      ..._asMap(raw['metrics']),
    };
    final out = <String, double>{};
    for (final entry in trendNode.entries) {
      final value = entry.value;
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse(value.toString());
      if (parsed == null || !parsed.isFinite) continue;
      out[entry.key.toString()] = parsed;
    }
    return out;
  }

  Widget _coachInsightCard({Map<String, dynamic>? archivedAiPayload}) {
    final scores = _archivedCoachScores();
    final payload = archivedAiPayload ?? _buildLuxePayloadForAiScan();
    final trendDeltas = _archivedTrendDeltas();
    final sensitivitySignal = <double>[
      scores['redness'] ?? 0,
      scores['rosacea_intensity'] ?? 0,
      scores['texture'] ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final barrierStressed = sensitivitySignal >= 4.0;
    final insight = SkinScanCoachCopy.buildInsight(
      scores: scores,
      metricMatrix: _asMap(payload['metric_matrix']),
      trendDeltas: trendDeltas,
      isFollowUp: _archiveHasResolvedComparison(payload),
      sensitivitySignal: sensitivitySignal,
    );
    final routineHeader = SkinScanCoachCopy.buildRoutineHeader(
      scores: scores,
      isFollowUp: _archiveHasResolvedComparison(payload),
      barrierStressed: barrierStressed,
      sensitivitySignal: sensitivitySignal,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            insight,
            style: const TextStyle(
              fontSize: 13.6,
              height: 1.48,
              fontWeight: FontWeight.w600,
              color: AppColors.refinedSlate,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            routineHeader,
            style: TextStyle(
              fontSize: 12.8,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: AppColors.refinedSlate.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coachRoutineCard({Map<String, dynamic>? archivedAiPayload}) {
    final scores = _archivedCoachScores();
    final payload = archivedAiPayload ?? _buildLuxePayloadForAiScan();
    final sensitivitySignal = <double>[
      scores['redness'] ?? 0,
      scores['rosacea_intensity'] ?? 0,
      scores['texture'] ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final barrierStressed = sensitivitySignal >= 4.0;
    final routine = SkinScanCoachCopy.buildRoutine(
      scores: scores,
      isFollowUp: _archiveHasResolvedComparison(payload),
      sensitivitySignal: sensitivitySignal,
      barrierStressed: barrierStressed,
    );

    return ExpansionTile(
      initiallyExpanded: _archiveHasResolvedComparison(payload),
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      iconColor: AppColors.champagneGold,
      collapsedIconColor: AppColors.champagneGold,
      title: const Text(
        'Suggested routine',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.refinedSlate,
        ),
      ),
      children: [
        // AM/PM is a schedule label, not a metric status — PM previously
        // (mis)used the worsened/status brick color; both now use the
        // brand accent, distinguished by opacity instead of hue.
        _routineColumn('AM', routine.amSteps, AppColors.brandAccent),
        const SizedBox(height: 8),
        _routineColumn(
          'PM',
          routine.pmSteps,
          AppColors.brandAccent.withValues(alpha: 0.68),
        ),
      ],
    );
  }

  Widget _routineColumn(String label, List<String> steps, Color accent) {
    if (steps.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ROUTINE',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: accent,
            ),
          ),
          const SizedBox(height: 10),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '• $step',
                style: const TextStyle(
                  fontSize: 12.8,
                  height: 1.38,
                  fontWeight: FontWeight.w600,
                  color: AppColors.refinedSlate,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildMetricRows(Color accent) {
    final metrics = _displayMetrics;
    if (metrics.isEmpty) return [_emptyMetricsCard()];
    return metrics
        .map((entry) => _metricRow(entry.label, entry.value, accent))
        .toList();
  }

  List<({String key, String label, double value})> get _displayMetrics =>
      displayMetricsFor(scan);

  static List<({String key, String label, double value})> displayMetricsFor(
    ScanHistoryEntry scan,
  ) {
    final source = backendMetricSource(scan.metrics);
    if (source.isEmpty) return const [];

    if (scan.isAiAnalysisScan) {
      final rows = <({String key, String label, double value})>[];
      final entries = source.entries.toList()
        ..sort((a, b) => _metricLabel(a.key).compareTo(_metricLabel(b.key)));
      for (final entry in entries) {
        if (entry.key.toLowerCase().endsWith('_detected')) continue;
        final normalized = normalizeMetricValueTo100(entry.key, entry.value);
        if (!normalized.isFinite || normalized <= 0.0) continue;
        rows.add((
          key: entry.key,
          label: _metricLabel(entry.key),
          value: normalized,
        ));
      }
      return rows;
    }

    double? firstValue(List<String> keys) {
      final lookupKeys = scan.isAiAnalysisScan ? <String>[keys.first] : keys;
      for (final key in lookupKeys) {
        final value = source[key];
        if (value != null && value.isFinite) return value;
      }
      return null;
    }

    final isBodyProcedure = _isBodyProcedureScan(scan);
    final preferred = isBodyProcedure
        ? <({String key, String label, List<String> keys})>[
            (
              key: 'fatRetention',
              label: 'Fat Retention',
              keys: [
                'fatRetention',
                'fat_retention',
                'fatRetentionPct',
                'fatRetentionPercent',
              ],
            ),
            (
              key: 'swelling',
              label: 'Swelling',
              keys: [
                'swelling',
                'edema',
                'postOpSwelling',
                'swellingLevel',
                'swellingIndex',
                'redness',
                'erythema',
              ],
            ),
            (
              key: 'firmness',
              label: 'Firmness',
              keys: [
                'firmness',
                'bodyFirmness',
                'skinFirmness',
                'fibrosisFirmness',
                'pores',
                'pore',
              ],
            ),
            (
              key: 'skinLaxityFirmness',
              label: 'Skin Laxity / Firmness',
              keys: ['skinLaxityFirmness', 'elasticity'],
            ),
            (
              key: 'skinLaxity',
              label: 'Skin Laxity',
              keys: ['skinLaxity', 'laxity'],
            ),
            (
              key: 'contourSmoothness',
              label: 'Contour Smoothness',
              keys: [
                'contourSmoothness',
                'contourEvenness',
                'bodySmoothness',
                'textureSmoothness',
                'smoothness',
                'texture',
                'roughness',
              ],
            ),
            (
              key: 'skinRetraction',
              label: 'Skin Retraction',
              keys: [
                'skinRetraction',
                'skin_retraction',
                'retraction',
                'wrinkles',
                'wrinkle',
                'rhytids',
              ],
            ),
            (
              key: 'bruising',
              label: 'Bruising',
              keys: ['bruising', 'bruise', 'ecchymosis', 'darkSpots'],
            ),
            (
              key: 'fibrosisLevel',
              label: 'Fibrosis Level',
              keys: ['fibrosisLevel', 'fibrosis', 'fibrosisScore'],
            ),
            (
              key: 'scarringBruising',
              label: 'Scarring / Bruising',
              keys: ['scarringBruising', 'scarring_bruising', 'scarring'],
            ),
            (
              key: 'hyperpigmentation',
              label: 'Hyperpigmentation',
              keys: ['hyperpigmentation', 'pigment', 'pigmentation'],
            ),
            (
              key: 'volumeSatisfaction',
              label: 'Volume Satisfaction',
              keys: ['volumeSatisfaction', 'volume_satisfaction'],
            ),
            (
              key: 'overallHealingScore',
              label: 'Overall Healing',
              keys: [
                'overallHealingScore',
                'overall_healing_score',
                'bodyHealingScore',
              ],
            ),
          ]
        : <({String key, String label, List<String> keys})>[
            (key: 'redness', label: 'Redness', keys: ['redness', 'erythema']),
            (key: 'texture', label: 'Texture', keys: ['texture', 'roughness']),
            (
              key: 'wrinkle',
              label: 'Wrinkles',
              keys: ['wrinkles', 'wrinkle', 'rhytids'],
            ),
            (key: 'pores', label: 'Pores', keys: ['pores', 'pore']),
            (
              key: 'darkSpots',
              label: 'Dark Spots',
              keys: ['darkSpots', 'pigment', 'pigmentation'],
            ),
            (key: 'elasticity', label: 'Face Shape Stability', keys: ['elasticity']),
            (
              key: 'fatRetention',
              label: 'Fat Retention',
              keys: ['fatRetention', 'fat_retention'],
            ),
            (key: 'swelling', label: 'Swelling', keys: ['swelling', 'edema']),
            (
              key: 'firmness',
              label: 'Firmness',
              keys: ['firmness', 'bodyFirmness', 'skinLaxityFirmness'],
            ),
            (
              key: 'overallHealingScore',
              label: 'Overall Healing',
              keys: [
                'overallHealingScore',
                'overall_healing_score',
                'bodyHealingScore',
              ],
            ),
          ];

    final rows = <({String key, String label, double value})>[];
    final consumedKeys = <String>{};
    final consumedLabels = <String>{};
    for (final spec in preferred) {
      final value = firstValue(spec.keys);
      if (value == null) continue;
      final normalized = normalizeMetricValueTo100(spec.key, value);
      if (!normalized.isFinite || normalized <= 0.0) continue;
      rows.add((key: spec.key, label: spec.label, value: normalized));
      consumedKeys.addAll(spec.keys.where((key) => source.containsKey(key)));
      consumedLabels.add(spec.label.toLowerCase());
    }

    final extras =
        source.entries.where((entry) {
          final key = entry.key;
          if (!entry.value.isFinite || consumedKeys.contains(key)) return false;
          if (_isDerivedTrendOrPercentKey(key)) return false;
          if (key.startsWith('source') || key.startsWith('capture_')) {
            return false;
          }
          if (_isMetricAlias(key)) return false;
          final label = _metricLabel(key).toLowerCase();
          return !consumedLabels.contains(label);
        }).toList()..sort(
          (a, b) => _metricLabel(a.key).compareTo(_metricLabel(b.key)),
        );

    for (final entry in extras) {
      final normalized = normalizeMetricValueTo100(entry.key, entry.value);
      if (!normalized.isFinite || normalized <= 0.0) continue;
      rows.add((
        key: entry.key,
        label: _metricLabel(entry.key),
        value: normalized,
      ));
    }

    return rows;
  }

  List<String> _insightRows(
    List<({String key, String label, double value})> metrics,
  ) {
    final notes = <String>[];
    final customNote = scan.customDescription?.trim();
    if (customNote != null && customNote.isNotEmpty) notes.add(customNote);
    if (scan.isAiAnalysisScan && metrics.isNotEmpty) {
      final concernMetrics =
          metrics.where((metric) => !_higherIsBetterMetric(metric.key)).toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      final top = concernMetrics.isNotEmpty
          ? concernMetrics.first
          : metrics.first;
      notes.add(
        '${top.label} is the most elevated saved AI signal for this analysis.',
      );
      notes.add(
        'Use this scan as a cosmetic tracking reference alongside consistent lighting and angle.',
      );
    }
    return notes;
  }

  Widget _insightsCard(List<String> rows, Color accent) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _detailDecoration(accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows
            .map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: accent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row,
                        style: TextStyle(
                          color: AppColors.refinedSlate.withValues(alpha: 0.82),
                          fontSize: 12.6,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  BoxDecoration _detailDecoration(Color accent) {
    return BoxDecoration(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: accent.withValues(alpha: 0.24)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return ClinicalSectionHeader(
      icon: icon,
      title: title,
      textColor: AppColors.refinedSlate,
    );
  }

  Widget _qualityGrid(List<({String label, String value})> rows) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: rows
          .map(
            (row) => Container(
              width: 150,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borders),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.value,
                    style: const TextStyle(
                      color: AppColors.refinedSlate,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.label,
                    style: TextStyle(
                      color: AppColors.refinedSlate.withValues(alpha: 0.62),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _metricRow(String label, double value, Color accent) {
    final normalizedValue = normalizeMetricValueTo100(label, value);
    final normalized = _metricProgressValue(normalizedValue);
    final displayValue = normalizedValue.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: AppColors.refinedSlate.withValues(alpha: 0.035),
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
                    label,
                    style: const TextStyle(
                      color: AppColors.refinedSlate,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  displayValue,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: normalized,
                backgroundColor: AppColors.borders.withValues(alpha: 0.65),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyMetricsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borders),
      ),
      child: Text(
        'No numeric metrics were saved for this scan.',
        style: TextStyle(
          color: AppColors.refinedSlate.withValues(alpha: 0.66),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.refinedSlate,
                fontSize: 11.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Badge distinguishing which analysis engine produced this scan's
  /// metrics, so users understand why some scans don't chart trends
  /// against each other (see ScanHistoryEntry.scanEnginesComparable).
  Widget? _engineChip(String scanEngine) {
    switch (scanEngine) {
      case ScanHistoryEntry.engineLocalTflite:
        return _noticeChip(
          Icons.bolt_rounded,
          'Quick on-device scan',
          AppColors.champagneGold,
        );
      case ScanHistoryEntry.engineBackendOpencv:
        return _noticeChip(
          Icons.cloud_done_rounded,
          'Full AI analysis',
          AppColors.champagneGold,
        );
      default:
        return null;
    }
  }

  Widget _scanImage(String? path) {
    final cleanPath = path?.trim() ?? '';
    if (cleanPath.isEmpty) return _emptyImage(Icons.image);
    if (cleanPath.startsWith('data:image')) {
      final comma = cleanPath.indexOf(',');
      if (comma == -1) return _emptyImage(Icons.broken_image);
      try {
        return Image.memory(
          base64Decode(cleanPath.substring(comma + 1)),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _emptyImage(Icons.broken_image),
        );
      } catch (_) {
        return _emptyImage(Icons.broken_image);
      }
    }
    if (cleanPath.startsWith('http') || cleanPath.startsWith('blob:')) {
      return Image.network(
        cleanPath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _emptyImage(Icons.broken_image),
      );
    }
    if (kIsWeb) return _emptyImage(Icons.broken_image);
    return Image.file(
      File(cleanPath),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _emptyImage(Icons.broken_image),
    );
  }

  Widget _emptyImage(IconData icon) {
    return Container(
      color: AppColors.borders,
      child: Center(
        child: Icon(
          icon,
          size: 52,
          color: AppColors.refinedSlate.withValues(alpha: 0.36),
        ),
      ),
    );
  }

  static String _percent(double value) {
    return '${(value.clamp(0, 1) * 100).round()}%';
  }

  static String _metricLabel(String key) {
    if (key == 'structural_firmness_elasticity') {
      return 'Face Shape Stability';
    }
    final spaced = key
        .replaceAll('_', ' ')
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        );
    return spaced
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static double _metricProgressValue(double value) {
    return (value.clamp(0.0, 100.0) / 100.0).toDouble();
  }

  static double normalizeMetricValueTo100(String key, double value) {
    if (!value.isFinite) return 0.0;

    var normalized = value;
    final normalizedKey = key.toLowerCase().replaceAll('_', '');
    const tenPointScaleKeys = {
      'redness',
      'texture',
      'wrinkle',
      'wrinkles',
      'pores',
      'pore',
      'darkspots',
      'elasticity',
      'acneseverity',
      'swelling',
      'firmness',
      'fatretention',
      'overallhealingscore',
      'rhytids',
      'roughness',
      'pigmentation',
      'bodyfirmness',
      'skinlaxityfirmness',
      'bodysmoothness',
      'bodyhealingscore',
      'contoursmoothness',
      'skinretraction',
      'volumesatisfaction',
      'hyperpigmentation',
      'fibrosislevel',
    };

    if (tenPointScaleKeys.contains(normalizedKey) &&
        normalized >= 0.0 &&
        normalized <= 10.0) {
      normalized *= 10.0;
    }

    return (normalized.clamp(0.0, 100.0) as num).toDouble();
  }

  static double extractBackendMetricValue(
    dynamic scan,
    String metricKeyOrTitle,
  ) {
    if (scan == null) return 0.0;

    const canonicalKeys = <String>{
      'localized_redness',
      'texture_smoothness',
      'pigment_load',
      'wrinkle_load',
      'pore_visibility',
      'breakout_activity',
      'sebum_excess_oil_gloss',
      'diffuse_flushing_erythema',
      'skin_tone_radiance_evenness',
      'glabellar_wrinkle_depth',
      'under_eye_texture_density',
      'under_eye_dark_circle_density',
      'rosacea_severity',
      'structural_firmness_elasticity',
      'pore_contraction_index',
    };
    if (!canonicalKeys.contains(metricKeyOrTitle)) return 0.0;

    double? parseNumber(dynamic value) {
      if (value is num) return value.toDouble();
      if (value == null) return null;
      return double.tryParse(value.toString());
    }

    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    double? searchCanonicalKeyInMap(Map<String, dynamic> source, String key) {
      if (source.isEmpty) return null;
      final matrix = asMap(source['metric_matrix']);
      final opencv = asMap(source['opencv_metrics']);

      final direct = parseNumber(source[key]);
      if (direct != null && direct.isFinite) return direct;

      final matrixValue = parseNumber(matrix[key]);
      if (matrixValue != null && matrixValue.isFinite) return matrixValue;

      final opencvValue = parseNumber(opencv[key]);
      if (opencvValue != null && opencvValue.isFinite) return opencvValue;

      final flat1 = parseNumber(source['metric_matrix.$key']);
      if (flat1 != null && flat1.isFinite) return flat1;

      final flat2 = parseNumber(source['metric_matrix_$key']);
      if (flat2 != null && flat2.isFinite) return flat2;

      final flat3 = parseNumber(source['opencv_metrics.$key']);
      if (flat3 != null && flat3.isFinite) return flat3;

      final flat4 = parseNumber(source['opencv_metrics_$key']);
      if (flat4 != null && flat4.isFinite) return flat4;

      return null;
    }

    dynamic rawPayload;
    dynamic extraMetrics;
    dynamic metrics;
    dynamic serializedScan;
    dynamic mappedScan;

    if (scan is ScanHistoryEntry) {
      rawPayload = scan.rawPayload;
      metrics = scan.metrics;
      serializedScan = scan.toJson();
      mappedScan = scan.toJson();
    } else if (scan is Map) {
      rawPayload = scan['rawPayload'];
      extraMetrics = scan['extraMetrics'];
      metrics = scan['metrics'] ?? scan;
      serializedScan = scan;
      mappedScan = scan;
    } else {
      try {
        rawPayload = scan.rawPayload;
      } catch (_) {}
      try {
        extraMetrics = scan.extraMetrics;
      } catch (_) {}
      try {
        metrics = scan.metrics;
      } catch (_) {}
      try {
        serializedScan = scan.toJson();
      } catch (_) {}
      try {
        mappedScan = scan.toMap();
      } catch (_) {}
    }

    final metricsMap = asMap(metrics);
    final rawPayloadMap = asMap(rawPayload);
    final toMap = asMap(mappedScan).isNotEmpty
        ? asMap(mappedScan)
        : asMap(serializedScan);

    final extraMetricsMap = asMap(extraMetrics);
    final val =
        searchCanonicalKeyInMap(metricsMap, metricKeyOrTitle) ??
        searchCanonicalKeyInMap(rawPayloadMap, metricKeyOrTitle) ??
        searchCanonicalKeyInMap(toMap, metricKeyOrTitle) ??
        searchCanonicalKeyInMap(extraMetricsMap, metricKeyOrTitle);

    if (val == null || !val.isFinite) {
      final metricsKeys = metricsMap.keys.toList();
      print(
        'EXTRACTOR FAIL for [$metricKeyOrTitle] -> Available keys in metrics: $metricsKeys',
      );
      return 0.0;
    }
    return val;
  }

  static Map<String, double> backendMetricSource(Map<String, double> metrics) {
    const backendKeys = {
      'texture_smoothness',
      'localized_redness',
      'pore_visibility',
      'breakout_activity',
      'pigment_load',
      'wrinkle_load',
      'sebum_excess_oil_gloss',
      'diffuse_flushing_erythema',
      'skin_tone_radiance_evenness',
      'glabellar_wrinkle_depth',
      'pore_contraction_index',
      'structural_firmness_elasticity',
      'under_eye_texture_density',
      'under_eye_dark_circle_density',
      'rosacea_severity',
    };

    double? readBackendValue(String key) {
      final prefixedCandidates = <String>[
        'metric_matrix.$key',
        'metric_matrix_$key',
      ];
      for (final candidate in prefixedCandidates) {
        final value = metrics[candidate];
        if (value != null && value.isFinite) return value;
      }
      final direct = metrics[key];
      if (direct != null && direct.isFinite) return direct;
      return null;
    }

    final out = <String, double>{};
    for (final key in backendKeys) {
      final value = readBackendValue(key);
      if (value == null) continue;
      final normalized = normalizeMetricValueTo100(key, value);
      if (!normalized.isFinite || normalized <= 0.0) continue;
      out[key] = normalized;
    }
    return out;
  }

  static double normalizeLegacyBaselineForDelta(
    String key,
    double baselineValue,
    double currentValue,
  ) {
    final normalizedBaseline = normalizeMetricValueTo100(key, baselineValue);
    final normalizedCurrent = normalizeMetricValueTo100(key, currentValue);

    if (normalizedBaseline <= 10.0 && normalizedCurrent > 10.0) {
      return (normalizedBaseline * 10.0).clamp(0.0, 100.0).toDouble();
    }
    return normalizedBaseline;
  }

  static bool _isDerivedTrendOrPercentKey(String key) {
    final normalized = key.toLowerCase();
    if (normalized.startsWith('trend_delta_')) return true;
    if (normalized.startsWith('delta_')) return true;
    if (normalized.startsWith('percent_')) return true;
    if (normalized.contains('trend_delta')) return true;
    if (normalized.contains('percent_change')) return true;
    if (normalized.contains('change_pct')) return true;
    return normalized == 'percent' ||
        normalized == 'percentage' ||
        normalized == 'trend_percent' ||
        normalized == 'trend_percentage';
  }

  static bool _higherIsBetterMetric(String key) {
    return const {
      'elasticity',
      'firmness',
      'bodyFirmness',
      'skinFirmness',
      'skinLaxityFirmness',
      'fibrosisFirmness',
      'fatRetention',
      'fat_retention',
      'fatRetentionPct',
      'fatRetentionPercent',
      'overallHealingScore',
      'overall_healing_score',
      'bodyHealingScore',
      'textureSmoothness',
      'bodySmoothness',
      'smoothness',
      'contourSmoothness',
      'contourEvenness',
      'volumeSatisfaction',
      'volume_satisfaction',
      'skinRetraction',
      'skin_retraction',
      'retraction',
    }.contains(key);
  }

  static bool _isBodyProcedureScan(ScanHistoryEntry scan) {
    final metricKeys = scan.metrics.keys
        .map((key) => key.toLowerCase().replaceAll('_', ''))
        .toSet();
    const bodyMetricSignals = {
      'fatretention',
      'fatretentionpct',
      'fatretentionpercent',
      'postopswelling',
      'swellingindex',
      'swellinglevel',
      'bodyfirmness',
      'skinfirmness',
      'skinlaxityfirmness',
      'fibrosisfirmness',
      'skinlaxity',
      'fibrosislevel',
      'fibrosisscore',
      'contoursmoothness',
      'contourevenness',
      'bodysmoothness',
      'skinretraction',
      'volumesatisfaction',
      'bodyhealingscore',
      'scarringbruising',
    };
    if (metricKeys.any(bodyMetricSignals.contains)) return true;

    final combined = [
      scan.procedure,
      scan.customDescription,
      scan.focusArea,
    ].whereType<String>().join(' ').toLowerCase();
    const bodyTextSignals = [
      'bbl',
      'brazilian butt',
      'tummy tuck',
      'abdominoplasty',
      'mini tummy',
      'liposuction',
      'lipo',
      'body contour',
      'body sculpt',
      'abdomen',
      'abdominal',
      'waist',
      'flank',
      'buttock',
      'thigh',
      'arm contour',
      'brachioplasty',
    ];
    if (bodyTextSignals.any(combined.contains)) return true;

    if (!scan.isProcedureScan) return false;
    return usesBodyContouringContext(
      procedureType: scan.procedure,
      customDescription: scan.customDescription,
      focusArea: scan.focusArea,
    );
  }

  static bool _isMetricAlias(String key) {
    return const {
      'pigmentation',
      'erythema',
      'roughness',
      'rhytids',
      'acneSeverity',
      'rosaceaSeverity',
      'edema',
      'bodyFirmness',
      'skinLaxityFirmness',
      'bodySmoothness',
      'overall_healing_score',
      'bodyHealingScore',
    }.contains(key);
  }
}
