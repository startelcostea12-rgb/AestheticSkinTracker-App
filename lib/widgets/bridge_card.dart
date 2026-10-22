import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/peptide_model.dart';
import '../models/procedure.dart' as models;
import '../models/scan_history.dart';
import '../utils/trend_label_resolver.dart';

class BridgeCard extends StatelessWidget {
  const BridgeCard({
    super.key,
    required this.scans,
    this.activeProcedure,
    this.activePeptides = const [],
    this.title = 'Recovery Bridge',
    this.ctaLabel = 'Unlock deeper guidance',
    this.onTap,
  });

  final List<ScanHistoryEntry> scans;
  final models.Procedure? activeProcedure;
  final List<dynamic> activePeptides;
  final String title;
  final String ctaLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final resolvedProcedure = activeProcedure ?? _inferProcedureFromScans(scans);
    final latest = scans.isEmpty ? null : _latestScan(scans);
    final trendText = _buildTrendLine(latest);
    final hasRealProcedure = activeProcedure != null && (activeProcedure?.type ?? '').trim().isNotEmpty;
    final procedureName = (resolvedProcedure?.type ?? '').trim();
    final dayCount = _dayCountFromProcedure(resolvedProcedure);
    final peptideName = _peptideSummary();
    final peptideInsight = latest == null
        ? null
        : computePeptideTrendInsight(
            scans: scans,
            latest: latest,
            activePeptides: activePeptides,
          );
    final captureColor = latest != null && latest.captureQuality != null
        ? _captureBadgeColor(latest.captureQuality!)
        : AppColors.brandAccent;
    final ageDisplay = latest != null && latest.estimatedSkinAge > 0 && !latest.hasTrustworthyEstimatedSkinAge
        ? 'Estimate unavailable'
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.cardBackground,
            AppColors.warmAlabaster,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.brandAccent.withValues(alpha: 0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brandAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandAccent,
                    letterSpacing: 0.12,
                  ),
                ),
              ),
              const Spacer(),
              if (latest != null && latest.captureQuality != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: captureColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: captureColor.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    latest.captureQuality!.toLowerCase(),
                    style: TextStyle(
                      color: captureColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasRealProcedure && resolvedProcedure != null && procedureName.isNotEmpty)
            Text(
              'Day $dayCount post-$procedureName',
              style: const TextStyle(
                color: AppColors.refinedSlate,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            )
          else
            const Text(
              'Recovery check-in',
              style: TextStyle(
                color: AppColors.refinedSlate,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
          if (peptideName.isNotEmpty && hasRealProcedure) ...[
            const SizedBox(height: 4),
            Text(
              'on $peptideName',
              style: TextStyle(
                color: AppColors.refinedSlate.withValues(alpha: 0.76),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (peptideName.isNotEmpty && !hasRealProcedure) ...[
            const SizedBox(height: 4),
            Text(
              'on $peptideName',
              style: TextStyle(
                color: AppColors.refinedSlate.withValues(alpha: 0.76),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (ageDisplay != null) ...[
            Text(
              ageDisplay,
              style: const TextStyle(
                color: AppColors.refinedSlate,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            trendText,
            style: TextStyle(
              color: _trendColorForText(trendText),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (peptideInsight != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.kMetricImprovedColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.kMetricImprovedColor.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
              child: Text(
                peptideInsight,
                style: const TextStyle(
                  color: AppColors.kMetricImprovedColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.refinedSlate,
                  side: BorderSide(
                    color: AppColors.brandAccent.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  ctaLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? computePeptideTrendInsight({
    required List<ScanHistoryEntry> scans,
    required ScanHistoryEntry latest,
    required List<dynamic> activePeptides,
  }) {
    if (activePeptides.isEmpty) return null;

    // For multiple active peptides, use the most recently started one. This keeps
    // the insight simple and ensures the comparison remains honest by checking the
    // baseline date before any correlation text is shown.
    final candidatePeptide = _selectMostRelevantPeptide(activePeptides);
    if (candidatePeptide == null) return null;

    final baseline = _baselineEntryForComparison(scans, latest);
    if (baseline == null || candidatePeptide.startDate.isAfter(baseline.timestamp)) {
      return null;
    }

    final trendStatusMap = <String, dynamic>{
      ..._asMap((latest.rawPayload ?? const <String, dynamic>{})['trend_status']),
      ..._asMap((latest.rawPayload ?? const <String, dynamic>{})['luxePayload'] is Map
          ? ((latest.rawPayload ?? const <String, dynamic>{})['luxePayload'] as Map)['trend_status']
          : null),
    };

    final metricKey = _preferredMetricKey(latest);
    final metricStatus = trendStatusMap[metricKey]?.toString().trim().toLowerCase();
    if (metricStatus != 'improved') return null;

    final metricLabel = _metricLabel(metricKey);
    final peptideName = candidatePeptide.name.trim();
    if (peptideName.isEmpty) return null;
    return 'Since starting $peptideName, your $metricLabel has trended down.';
  }

  static PeptideEntry? _selectMostRelevantPeptide(List<dynamic> activePeptides) {
    final resolved = activePeptides
        .map((peptide) {
          if (peptide is PeptideEntry) return peptide;
          if (peptide is Map) {
            final name = peptide['name']?.toString() ?? '';
            final rawStart = peptide['startDate']?.toString() ?? '';
            final startDate = DateTime.tryParse(rawStart) ?? DateTime.now();
            final category = peptide['category']?.toString() ?? 'other';
            return PeptideEntry(
              id: peptide['id']?.toString() ?? name,
              name: name,
              frequency: peptide['frequency']?.toString() ?? 'Once daily',
              startDate: startDate,
              category: category,
            );
          }
          return null;
        })
        .whereType<PeptideEntry>()
        .toList();

    if (resolved.isEmpty) return null;
    resolved.sort((a, b) => b.startDate.compareTo(a.startDate));
    return resolved.first;
  }

  static String _preferredMetricKey(ScanHistoryEntry scan) {
    // 2026-09-08: pigment_load was rebaselined; wait for real trend history.
    final metricKeys = [
      'localized_redness',
      'rosacea_severity',
      'wrinkle_load',
      'glabellar_wrinkle_depth',
      'texture_smoothness',
    ];
    for (final key in metricKeys) {
      if (scan.metrics.containsKey(key)) return key;
    }
    return 'localized_redness';
  }

  static String _metricLabel(String metricKey) {
    switch (metricKey) {
      case 'rosacea_severity':
        return 'rosacea';
      case 'glabellar_wrinkle_depth':
        return 'glabellar wrinkles';
      case 'texture_smoothness':
        return 'texture';
      case 'pigment_load':
        return 'pigment';
      case 'wrinkle_load':
        return 'wrinkles';
      case 'localized_redness':
      default:
        return 'redness';
    }
  }

  static ScanHistoryEntry? _baselineEntryForComparison(
    List<ScanHistoryEntry> scans,
    ScanHistoryEntry latest,
  ) {
    final sameProcedure = scans
        .where((scan) => scan.procedureId == latest.procedureId)
        .where((scan) => scan.timestamp.isBefore(latest.timestamp))
        .toList();
    if (sameProcedure.isNotEmpty) {
      sameProcedure.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return sameProcedure.first;
    }

    final earlier = scans
        .where((scan) => scan.timestamp.isBefore(latest.timestamp))
        .toList();
    if (earlier.isEmpty) return null;
    earlier.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return earlier.first;
  }

  String _peptideSummary() {
    if (activePeptides.isEmpty) return '';
    final names = activePeptides
        .map((peptide) => peptide is Map ? peptide['name']?.toString() : peptide.name?.toString())
        .whereType<String>()
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) return '';
    return names.take(2).join(' + ');
  }

  String _buildTrendLine(ScanHistoryEntry? latest) {
    if (latest == null) return 'baseline set';
    if ((latest.rawPayload == null || latest.rawPayload!.isEmpty) && latest.metrics.isEmpty) {
      return 'baseline set';
    }

    final resolvedProcedure = activeProcedure ?? _inferProcedureFromScans(scans);
    final isBodyProcedure = resolvedProcedure?.bodyRegion == models.ProcedureBodyRegion.body;

    final payload = _asMap(latest.rawPayload);
    final nestedLuxe = _asMap(payload['luxePayload']);
    final trendSource = _asMap(nestedLuxe['trend_status']).isNotEmpty
        ? _asMap(nestedLuxe['trend_status'])
        : _asMap(payload['trend_status']);
    final lockReasonSource = _asMap(nestedLuxe['trend_lock_reasons']).isNotEmpty
        ? _asMap(nestedLuxe['trend_lock_reasons'])
        : _asMap(payload['trend_lock_reasons']);
    final metricKey = _preferredMetricKey(latest);
    final resolvedTrend = resolveTrendLabel(
      trendStatus: trendSource[metricKey]?.toString(),
      trendLockReason: lockReasonSource[metricKey]?.toString(),
    );

    final baselineComparable = _hasBaselineInfo(payload, nestedLuxe);
    if (!baselineComparable || resolvedTrend == null) {
      return isBodyProcedure
          ? 'Body tracking is still building your baseline — trends will appear as more scans accumulate. Check back after a few more sessions.'
          : 'baseline set';
    }

    if (resolvedTrend.isInsufficientSignal) {
      return isBodyProcedure
          ? 'Body tracking is still building your baseline — trends will appear as more scans accumulate. Check back after a few more sessions.'
          : 'steady since baseline';
    }

    if (resolvedTrend.isImproved) {
      return '${_metricLabel(metricKey)} trending down since baseline';
    }

    if (resolvedTrend.isWorsened) {
      return '${_metricLabel(metricKey)} trending up since baseline';
    }

    if (isBodyProcedure) {
      return 'Body tracking is still building your baseline — trends will appear as more scans accumulate. Check back after a few more sessions.';
    }
    // A "stable" trend_status can mean two different things: a genuine small
    // delta (real, honest stability) or a forced lock because this scan's
    // capture conditions weren't comparable to the baseline. Only the latter
    // gets a distinct label — a genuine stable keeps "steady since baseline".
    final lockLabel = resolvedTrend.lockShortLabel;
    return lockLabel ?? 'steady since baseline';
  }

  bool _hasBaselineInfo(Map<String, dynamic> payload, Map<String, dynamic> nestedLuxe) {
    final hasTrendStatus = _asMap(payload['trend_status']).isNotEmpty ||
        _asMap(nestedLuxe['trend_status']).isNotEmpty;
    final hasBaselineMatrix = _asMap(payload['baseline_metric_matrix']).isNotEmpty ||
        _asMap(payload['baseline']).isNotEmpty ||
        _asMap(nestedLuxe['baseline_metric_matrix']).isNotEmpty;
    return hasTrendStatus || hasBaselineMatrix || payload.containsKey('initial_baseline');
  }

  models.Procedure? _inferProcedureFromScans(List<ScanHistoryEntry> scans) {
    final sorted = List<ScanHistoryEntry>.from(scans)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (sorted.isEmpty) return null;
    final latest = sorted.last;
    final procedureName = (latest.procedure ?? '').trim();
    final procedureId = (latest.procedureId ?? '').trim();
    if (procedureName.isEmpty && procedureId.isEmpty) return null;
    return models.Procedure(
      id: procedureId.isNotEmpty ? procedureId : 'scan_${latest.id}',
      type: procedureName.isNotEmpty ? procedureName : 'Recovery',
      provider: 'Self-tracked',
      startDate: latest.timestamp.subtract(const Duration(days: 11)),
      numSessions: 1,
    );
  }

  int _dayCountFromProcedure(models.Procedure? procedure) {
    if (procedure == null) return 1;
    final today = DateTime.now();
    final days = today.difference(procedure.startDate).inDays;
    return days < 1 ? 1 : days + 1;
  }

  ScanHistoryEntry _latestScan(List<ScanHistoryEntry> list) {
    final sorted = List<ScanHistoryEntry>.from(list)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.first;
  }

  Color _trendColorForText(String trendText) {
    if (trendText.contains('down')) {
      return AppColors.kMetricImprovedColor;
    }
    if (trendText.contains('up')) {
      return AppColors.kMetricWorsenedColor;
    }
    return AppColors.refinedSlate.withValues(alpha: 0.75);
  }

  Color _captureBadgeColor(String captureQuality) {
    switch (captureQuality.toLowerCase()) {
      case 'normal':
        return AppColors.kMetricImprovedColor;
      case 'low_light':
      case 'blurry':
      case 'poor_angle':
      case 'face_offcenter':
      case 'partial_body_framing':
      case 'uneven_lighting':
        return AppColors.kMetricWorsenedColor;
      default:
        return AppColors.brandAccent;
    }
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }
}
