// Skin History Repository
// ------------------------
// A thin, focused persistence layer for AI skin-analysis scans. It wraps
// the app's existing SharedPreferences-backed scan store (`AppPrefs` +
// `ScanHistoryEntry`) so callers can save and read the full 6-metric
// result produced by [SkinAnalysisService] without touching storage
// internals.
//
// Storage model:
//   This app persists scans as JSON `ScanHistoryEntry` records whose
//   per-scan readings live in a free-form `metrics` map (string → double).
//   There is no SQL table, so the "columns" for `acne_severity` and
//   `rosacea_intensity` are simply two additional well-known keys stored
//   alongside the existing four (`pigment`, `redness`, `texture`,
//   `wrinkle`). The keys below are the single source of truth for those
//   metric names.

import '../models/scan_history.dart';
import '../utils/app_prefs.dart';
import 'package:flutter/foundation.dart';

/// Repository for reading and writing AI skin-analysis scans, including
/// the two specialist metrics (`acne_severity`, `rosacea_intensity`).
class SkinHistoryRepository {
  SkinHistoryRepository._();

  /// Shared, app-wide instance.
  static final SkinHistoryRepository instance = SkinHistoryRepository._();

  // ── Metric keys ("columns") ───────────────────────────────────────
  static const String kPigment = 'pigment';
  static const String kRedness = 'redness';
  static const String kTexture = 'texture';
  static const String kWrinkle = 'wrinkle';
  static const String kAcneSeverity = 'acne_severity';
  static const String kRosaceaIntensity = 'rosacea_intensity';

  /// All six metric keys, in canonical order.
  static const List<String> allMetricKeys = [
    kPigment,
    kRedness,
    kTexture,
    kWrinkle,
    kAcneSeverity,
    kRosaceaIntensity,
  ];

  static const Set<String> _clinicalMetricKeys = {
    'localized_redness',
    'texture_smoothness',
    'pore_visibility',
    'wrinkle_load',
    'pigment_load',
    'breakout_activity',
    'diffuse_flushing_erythema',
    'sebum_excess_oil_gloss',
    'skin_tone_radiance_evenness',
    'glabellar_wrinkle_depth',
    'under_eye_texture_density',
    'under_eye_dark_circle_density',
    'rosacea_severity',
    'structural_firmness_elasticity',
    'pore_contraction_index',
  };

  // ── Writes ────────────────────────────────────────────────────────

  /// Persists a single scan with all six metrics and returns the stored
  /// [ScanHistoryEntry].
  ///
  /// Pass the full map returned by
  /// `SkinAnalysisService.instance.runFullAnalysis(...)`. Missing metrics
  /// default to `0.0` so the record always carries the complete column
  /// set. Any extra keys present in [metrics] are preserved untouched.
  Future<ScanHistoryEntry> saveScan({
    required Map<String, double> metrics,
    String? imagePath,
    DateTime? timestamp,
    String? procedureId,
    String? procedure,
    String? scanType,
    String? poseTemplate,
    String? guideType,
    String? captureQuality,
    String? focusArea,
    String? customDescription,
    int? sourceImageWidth,
    int? sourceImageHeight,
    double estimatedSkinAge = 0,
    Map<String, dynamic>? rawPayload,
  }) async {
    final ts = timestamp ?? DateTime.now();

    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    bool isFiniteMeasuredValue(dynamic value) =>
      value is num && value.isFinite && value >= 0;

    void absorbClinicalMetrics(
      Map<String, double> target,
      Map<String, dynamic> source,
    ) {
      for (final entry in source.entries) {
        final key = entry.key;
        final value = entry.value;
        if (!_clinicalMetricKeys.contains(key) ||
          !isFiniteMeasuredValue(value)) {
          continue;
        }
        target[key] = (value as num).toDouble();
      }
    }

    double? extractBackendMetricMatrixPore(Map<String, dynamic> data) {
      final metricMatrix = asMap(data['metric_matrix']);
      final direct = metricMatrix['pore_visibility'];
      if (direct is num && direct.isFinite && direct >= 0) {
        return direct.toDouble();
      }

      final metricsNode = asMap(data['metrics']);
      final nestedMatrix = asMap(metricsNode['metric_matrix']);
      final nested = nestedMatrix['pore_visibility'];
      if (nested is num && nested.isFinite && nested >= 0) {
        return nested.toDouble();
      }

      return null;
    }

    final payloadMap = asMap(rawPayload);

    final stored = <String, double>{...metrics};

    // Merge canonical clinical metrics from backend payload nodes so the
    // persisted ScanHistoryEntry.metrics map always carries the same keys
    // used by baseline candidate selection and Luxe rendering.
    final payloadMetricMatrix = asMap(payloadMap['metric_matrix']);
    absorbClinicalMetrics(stored, payloadMetricMatrix);

    final payloadMetrics = asMap(payloadMap['metrics']);
    absorbClinicalMetrics(stored, payloadMetrics);

    final nestedMetricMatrix = asMap(payloadMetrics['metric_matrix']);
    absorbClinicalMetrics(stored, nestedMetricMatrix);

    final backendMatrixPore = extractBackendMetricMatrixPore(payloadMap);
    if (backendMatrixPore != null) {
      stored['pore_visibility'] = backendMatrixPore;
    } else {
      stored.remove('pore_visibility');
    }
    final computedSkinAge = estimateVisualSkinAgeFromAiMetrics(stored);

    // The only caller of saveScan is the remote-backend AI Analysis flow
    // (_SkinAiAnalysisScreenState._runAnalysis), which posts to
    // /api/skin/analyze-single. That endpoint doesn't currently emit a
    // `modelUsed` tag (unlike its sibling /api/analyze-skin), so fall back
    // to the known engine for this call path rather than "unknown".
    final resolvedScanEngine = ScanHistoryEntry.resolveScanEngine(
      payloadMap,
      fallback: ScanHistoryEntry.engineBackendOpencv,
    );

    final entry = ScanHistoryEntry(
      id: ScanHistoryEntry.generateId(ts, imagePath),
      timestamp: ts,
      imagePath: imagePath,
      procedureId: procedureId,
      scanType: scanType ?? ScanHistoryEntry.scanTypeAiAnalysis,
      procedure: procedure,
      poseTemplate: poseTemplate?.trim().isNotEmpty == true
          ? poseTemplate!.trim()
          : null,
      guideType: guideType?.trim().isNotEmpty == true
          ? guideType!.trim()
          : null,
      captureQuality: captureQuality?.trim().isNotEmpty == true
          ? captureQuality!.trim()
          : null,
      focusArea: focusArea?.trim().isNotEmpty == true
          ? focusArea!.trim()
          : null,
      customDescription: customDescription?.trim().isNotEmpty == true
          ? customDescription!.trim()
          : null,
      estimatedSkinAge: estimatedSkinAge > 0
          ? estimatedSkinAge
          : computedSkinAge ?? 0,
      metrics: stored,
      rawPayload: rawPayload,
      sourceImageWidth: sourceImageWidth,
      sourceImageHeight: sourceImageHeight,
      scanEngine: resolvedScanEngine,
    );

    final hasProcedureId =
        (entry.procedureId?.trim().isNotEmpty ?? false);
    debugPrint(
      '[BASELINE_WRITE] saveScan entryId=${entry.id} procedureId=${entry.procedureId ?? 'null'} '
      'willSyncProcedureComparison=$hasProcedureId',
    );

    final history = await AppPrefs.addScanEntry(entry);
    debugPrint(
      '[BASELINE_WRITE] addScanEntry complete entryId=${entry.id} historyCount=${history.length}',
    );
    await AppPrefs.syncProcedurePhotoComparisonForEntry(
      entry,
      history: history,
    );
    debugPrint(
      '[BASELINE_WRITE] syncProcedurePhotoComparisonForEntry complete entryId=${entry.id}',
    );
    return entry;
  }

  // ── Reads ─────────────────────────────────────────────────────────

  /// Returns every stored scan, newest first. Each entry's `metrics` map
  /// includes the six analysis columns (defaulting to `0.0` for legacy
  /// scans that pre-date a given metric).
  Future<List<ScanHistoryEntry>> getAllScans() async {
    final scans = await AppPrefs.getScanEntries();
    scans.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return scans;
  }

  /// Reads the six analysis metrics from a [ScanHistoryEntry], filling
  /// absent columns with `0.0`. Convenience for chart/report consumers.
  Map<String, double> metricsOf(ScanHistoryEntry entry) {
    return {for (final key in allMetricKeys) key: entry.metrics[key] ?? 0.0};
  }
}
