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
    String? focusArea,
    String? customDescription,
    double estimatedSkinAge = 0,
  }) async {
    final ts = timestamp ?? DateTime.now();

    // Normalise the six known columns, preserving any extra keys.
    final stored = <String, double>{
      ...metrics,
      kPigment: metrics[kPigment] ?? 0.0,
      kRedness: metrics[kRedness] ?? 0.0,
      kTexture: metrics[kTexture] ?? 0.0,
      kWrinkle: metrics[kWrinkle] ?? 0.0,
      kAcneSeverity: metrics[kAcneSeverity] ?? 0.0,
      kRosaceaIntensity: metrics[kRosaceaIntensity] ?? 0.0,
    };
    final computedSkinAge = estimateVisualSkinAgeFromAiMetrics(stored);

    final entry = ScanHistoryEntry(
      id: ScanHistoryEntry.generateId(ts, imagePath),
      timestamp: ts,
      imagePath: imagePath,
      procedureId: procedureId,
      scanType: scanType ?? ScanHistoryEntry.scanTypeAiAnalysis,
      procedure: procedure,
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
    );

    await AppPrefs.addScanEntry(entry);
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
