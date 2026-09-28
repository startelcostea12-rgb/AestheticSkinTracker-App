// lib/screens/skin_ai_analysis_screen.dart
//
// Dedicated "Skin AI Analysis" experience — a clean, full-page flow
// launched directly from the home shortcut row. Intentionally NOT
// nested inside the Acne & Rosacea Tracker so that users get a fast,
// focused capture → analyze → results experience without the tabbed
// tracker context.
//
// Stages:
//   1. capture   — photo source picker (camera, gallery, latest scan),
//                  minimal region/context selector, "Run AI Analysis"
//                  button.
//   2. analyzing — loader with progress copy.
//   3. results   — clinical results view rendering analyzer output.
//
// The analysis engine itself is the shared `AcneRosaceaPhotoAnalyzer`,
// so derivations and scoring stay consistent with the tracker.

import 'dart:convert' show base64Decode, base64Encode, utf8;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:aesthetic_skin_tracker/app_theme.dart';
import 'package:aesthetic_skin_tracker/models/acne_rosacea_log.dart';
import 'package:aesthetic_skin_tracker/models/ai_scan_frame_exposure.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/services/skin_history_repository.dart';
import 'package:aesthetic_skin_tracker/utils/acne_rosacea_photo_analysis.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/ai/skin_analysis_model.dart';
import 'package:aesthetic_skin_tracker/utils/ai/skin_analysis_runner.dart';
import 'package:aesthetic_skin_tracker/utils/ai/skin_detections.dart';
import 'package:aesthetic_skin_tracker/utils/app_logger.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/backend_config.dart';
import 'package:aesthetic_skin_tracker/utils/skin_analysis_service.dart' as remote_analysis;
import 'package:aesthetic_skin_tracker/utils/procedure_intelligence.dart' as procedure_intel;
import 'package:aesthetic_skin_tracker/utils/procedure_metric_set.dart';
import 'package:aesthetic_skin_tracker/utils/trend_label_resolver.dart';
import 'package:aesthetic_skin_tracker/utils/ai_product_recommendation_engine.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:aesthetic_skin_tracker/widgets/clinical_section_header.dart';
import 'package:aesthetic_skin_tracker/widgets/image_crop_dialog.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:aesthetic_skin_tracker/widgets/skin_heatmap_overlay.dart';
import 'package:aesthetic_skin_tracker/widgets/smart_narrative_container.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/screens/ai_recovery_coach_screen.dart';

class SkinAiAnalysisScreen extends StatefulWidget {
  const SkinAiAnalysisScreen({super.key});

  @override
  State<SkinAiAnalysisScreen> createState() => _SkinAiAnalysisScreenState();
}

enum _Stage { capture, analyzing, results }

enum _DebugExportAction { burstLog, scanData }

class MultiFrameAnalysisAggregate {
  const MultiFrameAnalysisAggregate({
    required this.response,
    required this.metricContributorCounts,
    required this.successfulFrames,
    required this.requestedFrames,
  });

  final Map<String, dynamic> response;
  final Map<String, int> metricContributorCounts;
  final int successfulFrames;
  final int requestedFrames;
}

Map<String, dynamic> _dynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

Set<String> _stringSetFromDynamic(dynamic value) {
  if (value is! List) return const <String>{};
  return value.map((e) => e.toString()).toSet();
}

/// Canonical clinical metric keys used across AI Skin Analysis provenance
/// checks (extraction paths, formula versions) -- a saved scan's own
/// provenance maps never contain a key outside this set.
const Set<String> aiSkinAnalysisCanonicalMetricKeys = <String>{
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
  'pore_contraction_index',
  'structural_firmness_elasticity',
  'rosacea_severity',
  'skin_hydration',
};

Map<String, dynamic>? _asPlainMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? preservedAiExtractionPath(dynamic value) {
  final path = value?.toString().trim();
  return path == null || path.isEmpty ? null : path;
}

/// The per-metric analysis-extraction-path provenance a saved AI Skin
/// Analysis scan recorded, checking every nested location the persisted
/// payload may have put it (top-level, under "metrics", and under
/// "luxePayload"/its own nested "metrics" -- mirrors
/// _mergePayloadForPersistence's own nesting). Every non-empty backend path
/// is preserved verbatim. Empty when the scan's rawPayload carries no path
/// provenance at all -- an "unknown analysis method" scan, per
/// [scanPassesSingleScanBaselineGates].
Map<String, String> aiScanExtractionPaths(ScanHistoryEntry scan) {
  final out = <String, String>{};
  final rawPayload = scan.rawPayload;
  if (rawPayload == null || rawPayload.isEmpty) return out;

  void mergePathSource(dynamic source) {
    final map = _asPlainMap(source);
    if (map == null || map.isEmpty) return;
    for (final entry in map.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      if (!aiSkinAnalysisCanonicalMetricKeys.contains(key)) continue;
      final path = preservedAiExtractionPath(entry.value);
      if (path != null) out[key] = path;
    }
  }

  mergePathSource(rawPayload['metric_extraction_paths']);
  final nestedMetrics = _asPlainMap(rawPayload['metrics']);
  mergePathSource(nestedMetrics?['metric_extraction_paths']);
  final nestedLuxe = _asPlainMap(rawPayload['luxePayload']);
  mergePathSource(nestedLuxe?['metric_extraction_paths']);
  final nestedLuxeMetrics = _asPlainMap(nestedLuxe?['metrics']);
  mergePathSource(nestedLuxeMetrics?['metric_extraction_paths']);

  return out;
}

/// Per-metric scoring-formula-version provenance a saved scan recorded
/// (see main.py's METRIC_FORMULA_VERSION / _metric_formula_version, echoed
/// back in the response as metric_formula_versions). Empty when the scan
/// predates this field or carries no usable entries -- a "no known
/// formula version" scan, per [scanPassesSingleScanBaselineGates].
Map<String, int> aiScanFormulaVersions(ScanHistoryEntry scan) {
  final out = <String, int>{};
  final rawPayload = scan.rawPayload;
  if (rawPayload == null || rawPayload.isEmpty) return out;

  void mergeVersionSource(dynamic source) {
    final map = _asPlainMap(source);
    if (map == null || map.isEmpty) return;
    for (final entry in map.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      if (!aiSkinAnalysisCanonicalMetricKeys.contains(key)) continue;
      final value = entry.value;
      final parsed = value is num
          ? value.toInt()
          : int.tryParse(value?.toString() ?? '');
      if (parsed != null) out[key] = parsed;
    }
  }

  mergeVersionSource(rawPayload['metric_formula_versions']);
  final nestedMetrics = _asPlainMap(rawPayload['metrics']);
  mergeVersionSource(nestedMetrics?['metric_formula_versions']);
  final nestedLuxe = _asPlainMap(rawPayload['luxePayload']);
  mergeVersionSource(nestedLuxe?['metric_formula_versions']);
  final nestedLuxeMetrics = _asPlainMap(nestedLuxe?['metrics']);
  mergeVersionSource(nestedLuxeMetrics?['metric_formula_versions']);

  return out;
}

/// The single-scan honesty gates a scan must pass before it can EVER be
/// selected as an AI Skin Analysis baseline for any key -- checked once,
/// independent of any specific comparison partner:
///  - a known, non-null poseTemplate AND guideType (a scan missing either
///    can never match a real capture's AiBaselineKey anyway -- this states
///    the same rule directly, for callers checking eligibility up front);
///  - capture quality recorded as "normal" (any other, or unknown, quality
///    means this scan's own conditions were degraded);
///  - a known analysis method (at least one recognized extraction path
///    recorded);
///  - a recorded scoring-formula version (at least one metric).
/// A scan failing any of these is NEVER stored as a baseline, no matter
/// how it was reached (auto-registration or an explicit pin) -- it's
/// simply not yet "a real, comparable scan". Pairwise gates (resolution
/// match, extraction-path MATCH, quality MATCH against a specific other
/// scan) are separate and enforced by the backend's own trend gates at
/// comparison time, not here -- see _trend_delta_and_status in main.py.
bool scanPassesSingleScanBaselineGates(ScanHistoryEntry scan) =>
    aiBaselineRejectionReason(scan) == null;

/// Names the FIRST check [scanPassesSingleScanBaselineGates] fails for
/// [scan], in the same order that function checks them, or null if it
/// passes every gate. Single source of truth for both functions, so the
/// pass/fail verdict and its user-facing explanation can never disagree.
/// Purely a rejection MESSAGE -- never changes which scans are eligible.
String? aiBaselineRejectionReason(ScanHistoryEntry scan) {
  if (scan.poseTemplate == null) {
    return "Not saved as baseline: this photo's angle was not recorded.";
  }
  if (scan.guideType == null) {
    return "Not saved as baseline: this photo's region was not recorded.";
  }
  final quality = (scan.captureQuality ?? '').trim().toLowerCase();
  if (quality.isEmpty) {
    return 'Not saved as baseline: capture quality was not recorded.';
  }
  if (quality != 'normal') {
    return "Not saved as baseline: capture quality was '$quality'.";
  }
  if (aiScanExtractionPaths(scan).isEmpty) {
    return 'Not saved as baseline: no recognized analysis method was '
        'recorded for this scan.';
  }
  if (aiScanFormulaVersions(scan).isEmpty) {
    return 'Not saved as baseline: no scoring formula version was '
        'recorded for this scan.';
  }
  return null;
}

Map<String, String> buildAiSkinAnalysisBackendFields({
  String? procedureType,
  String? customDescription,
  required String focusArea,
  String? currentCaptureQuality,
  String? baselineCaptureQuality,
  String? poseTemplate,
  String? baselinePoseTemplate,
  String? guideType,
  String? baselineGuideType,
}) {
  return {
    if ((procedureType ?? '').trim().isNotEmpty)
      'procedure_type': procedureType!.trim(),
    if ((customDescription ?? '').trim().isNotEmpty)
      'skin_profile_note': customDescription!.trim(),
    if (focusArea.trim().isNotEmpty)
      'selected_skin_profile_note': focusArea.trim(),
    if ((currentCaptureQuality ?? '').trim().isNotEmpty)
      'capture_quality': currentCaptureQuality!.trim(),
    if ((baselineCaptureQuality ?? '').trim().isNotEmpty)
      'baseline_capture_quality': baselineCaptureQuality!.trim(),
    if ((poseTemplate ?? '').trim().isNotEmpty)
      'pose_template': poseTemplate!.trim(),
    if ((baselinePoseTemplate ?? '').trim().isNotEmpty)
      'baseline_pose_template': baselinePoseTemplate!.trim(),
    if ((guideType ?? '').trim().isNotEmpty) 'guide_type': guideType!.trim(),
    if ((baselineGuideType ?? '').trim().isNotEmpty)
      'baseline_guide_type': baselineGuideType!.trim(),
  };
}

/// Reads a per-frame `trend_deltas` / `trend_status` / `trend_lock_reasons`
/// map from a single frame's raw backend response, preferring a top-level
/// key and falling back to the same key nested under `metrics` -- mirrors
/// _parseBackendAnalysisPayload's own dual lookup so a per-frame response is
/// read the exact same way it would be if it were the only frame.
Map<String, dynamic> _perFrameTrendNode(
  Map<String, dynamic> response,
  Map<String, dynamic> metricsNode,
  String key,
) {
  final topLevel = _dynamicMap(response[key]);
  if (topLevel.isNotEmpty) return topLevel;
  return _dynamicMap(metricsNode[key]);
}

MultiFrameAnalysisAggregate averageBackendAnalysisFrames(
  List<Map<String, dynamic>> responses, {
  required int requestedFrames,
}) {
  final samples = <String, List<double>>{};
  // Parallel to `samples`: which successfulResponses index each sample came
  // from, so a metric's trend verdict can later be taken from whichever
  // frame's own value is closest to that metric's average -- the same value
  // this aggregate actually reports -- instead of always frame 1's.
  final sampleFrameIndices = <String, List<int>>{};
  final confidenceSamples = <String, List<Object>>{};
  final successfulResponses = <Map<String, dynamic>>[];

  Object? confidenceForMetric(
    Map<String, dynamic> response,
    Map<String, dynamic> metricsNode,
    String metricKey,
  ) {
    for (final source in [
      _dynamicMap(response['metric_confidence']),
      _dynamicMap(metricsNode['metric_confidence']),
    ]) {
      final value = source[metricKey];
      if (value is num && value.toDouble().isFinite) return value.toDouble();
      final text = value?.toString().trim().toLowerCase();
      if (text == 'high' || text == 'medium' || text == 'low') return text;
    }
    return null;
  }

  for (final response in responses) {
    final metricsNode = _dynamicMap(response['metrics']);
    final matrix = _dynamicMap(response['metric_matrix']).isNotEmpty
        ? _dynamicMap(response['metric_matrix'])
        : _dynamicMap(metricsNode['metric_matrix']);
    if (matrix.isEmpty) continue;
    final frameMetrics = <String, double>{};
    for (final entry in matrix.entries) {
      final value = entry.value;
      final numeric = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (numeric == null || !numeric.isFinite) continue;
      frameMetrics[entry.key] = numeric;
    }
    if (frameMetrics.isEmpty) continue;
    successfulResponses.add(response);
    final frameIndex = successfulResponses.length - 1;
    for (final entry in frameMetrics.entries) {
      samples.putIfAbsent(entry.key, () => <double>[]).add(entry.value);
      sampleFrameIndices
          .putIfAbsent(entry.key, () => <int>[])
          .add(frameIndex);
      final confidence = confidenceForMetric(response, metricsNode, entry.key);
      if (confidence != null) {
        confidenceSamples.putIfAbsent(entry.key, () => <Object>[]).add(
          confidence,
        );
      }
    }
  }

  if (successfulResponses.isEmpty || samples.isEmpty) {
    throw StateError('No captured frame produced usable backend metrics.');
  }

  final averagedMatrix = <String, double>{};
  final contributorCounts = <String, int>{};
  final metricRanges = <String, Map<String, num>>{};
  for (final entry in samples.entries) {
    averagedMatrix[entry.key] =
        entry.value.reduce((a, b) => a + b) / entry.value.length;
    contributorCounts[entry.key] = entry.value.length;
    metricRanges[entry.key] = <String, num>{
      'min': entry.value.reduce((a, b) => a < b ? a : b),
      'max': entry.value.reduce((a, b) => a > b ? a : b),
      'count': entry.value.length,
    };
  }

  final correctedConfidence = <String, Object>{};
  for (final entry in confidenceSamples.entries) {
    if (entry.value.isEmpty) continue;
    correctedConfidence[entry.key] = entry.value.first;
  }

  // For each metric, the trend verdict (status/delta/lock reason) must come
  // from the same frame whose raw value the averaged, displayed value is
  // closest to -- never unconditionally frame 1, which previously left the
  // shown verdict describing a different number than the one on screen.
  final resolvedTrendStatus = <String, dynamic>{};
  final resolvedTrendDeltas = <String, dynamic>{};
  final resolvedTrendLockReasons = <String, dynamic>{};
  final resolvedExtractionPaths = <String, dynamic>{};
  final resolvedBaselineExtractionPaths = <String, dynamic>{};
  for (final key in averagedMatrix.keys) {
    final values = samples[key];
    final indices = sampleFrameIndices[key];
    if (values == null || indices == null || values.isEmpty) continue;
    final target = averagedMatrix[key]!;
    var nearestIndex = indices.first;
    var nearestDistance = (values.first - target).abs();
    for (var i = 1; i < values.length; i++) {
      final distance = (values[i] - target).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = indices[i];
      }
    }
    final nearestResponse = successfulResponses[nearestIndex];
    final nearestMetricsNode = _dynamicMap(nearestResponse['metrics']);
    final status =
        _perFrameTrendNode(nearestResponse, nearestMetricsNode, 'trend_status')[key];
    if (status != null) resolvedTrendStatus[key] = status;
    final delta =
        _perFrameTrendNode(nearestResponse, nearestMetricsNode, 'trend_deltas')[key];
    if (delta != null) resolvedTrendDeltas[key] = delta;
    final lockReason = _perFrameTrendNode(
      nearestResponse,
      nearestMetricsNode,
      'trend_lock_reasons',
    )[key];
    if (lockReason != null) resolvedTrendLockReasons[key] = lockReason;
    final extractionPath = _perFrameTrendNode(
      nearestResponse,
      nearestMetricsNode,
      'metric_extraction_paths',
    )[key];
    if (extractionPath != null) resolvedExtractionPaths[key] = extractionPath;
    final baselineExtractionPath = _perFrameTrendNode(
      nearestResponse,
      nearestMetricsNode,
      'baseline_metric_extraction_paths',
    )[key];
    if (baselineExtractionPath != null) {
      resolvedBaselineExtractionPaths[key] = baselineExtractionPath;
    }
  }

  final first = successfulResponses.first;
  final response = Map<String, dynamic>.from(first);
  final metricsNode = Map<String, dynamic>.from(_dynamicMap(first['metrics']));
  response['metric_matrix'] = averagedMatrix;
  response['metric_confidence'] = correctedConfidence;
  response['trend_status'] = resolvedTrendStatus;
  response['trend_deltas'] = resolvedTrendDeltas;
  response['trend_lock_reasons'] = resolvedTrendLockReasons;
  response['metric_extraction_paths'] = resolvedExtractionPaths;
  response['baseline_metric_extraction_paths'] =
      resolvedBaselineExtractionPaths;
  response.addAll(averagedMatrix);
  metricsNode
    ..addAll(averagedMatrix)
    ..['metric_matrix'] = averagedMatrix
    ..['metric_confidence'] = correctedConfidence
    ..['trend_status'] = resolvedTrendStatus
    ..['trend_deltas'] = resolvedTrendDeltas
    ..['trend_lock_reasons'] = resolvedTrendLockReasons
    ..['metric_extraction_paths'] = resolvedExtractionPaths
    ..['baseline_metric_extraction_paths'] = resolvedBaselineExtractionPaths;
  response['metrics'] = metricsNode;
  response['multi_frame_analysis'] = <String, dynamic>{
    'requested_frames': requestedFrames,
    'successful_frames': successfulResponses.length,
    'metric_contributor_counts': contributorCounts,
    'metric_frame_values': <String, List<double>>{
      for (final entry in samples.entries)
        entry.key: List<double>.unmodifiable(entry.value),
    },
    'metric_ranges': metricRanges,
  };

  return MultiFrameAnalysisAggregate(
    response: response,
    metricContributorCounts: contributorCounts,
    successfulFrames: successfulResponses.length,
    requestedFrames: requestedFrames,
  );
}

double? _parseFiniteDouble(dynamic value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

({double min, double max})? _parseMetricRange(dynamic rawRange) {
  final map = _dynamicMap(rawRange);
  final min = _parseFiniteDouble(map['min']);
  final max = _parseFiniteDouble(map['max']);
  if (min == null || max == null) return null;
  return (min: min, max: max);
}

/// Client-side honesty gate that runs on top of the backend's own
/// trend_status: an "improved"/"worsened" verdict is downgraded to
/// "stable" (with lock reason "frame_range_overlap") whenever the current
/// scan's and the baseline scan's own multi-frame value ranges for that
/// metric substantially overlap -- meaning frame-to-frame capture noise
/// alone could explain the gap between their averages, regardless of how
/// large that gap looks as a percentage. This is exactly the case that let
/// texture_smoothness 19.4 -> 39.4 ("+100%") through as "Improved" while
/// the two scans' own frame ranges (11.2-30.3 baseline, 28.7-50.2 current)
/// overlapped from 28.7-30.3.
///
/// Downgrade-only: a "stable" or "insufficient_signal" verdict is never
/// touched, and a downgraded verdict is never flipped to the opposite
/// direction or upgraded to a stronger one -- this layer can only pull an
/// improved/worsened claim back to stable, never invent one. [trendDeltas]
/// is zeroed alongside any downgraded key, matching the backend's own
/// invariant that a "stable" status always carries a 0 delta.
///
/// A metric missing a usable range on either side -- an older scan
/// persisted before per-frame ranges existed, or a single-frame capture
/// with no spread to report -- is left exactly as the backend verdict
/// reported it. Missing range data is never treated as evidence of overlap.
({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, String> trendLockReasons,
})
downgradeTrendForOverlappingFrameRanges({
  required Map<String, String> trendStatus,
  required Map<String, double> trendDeltas,
  required Map<String, String> trendLockReasons,
  required Map<String, dynamic> currentMetricRanges,
  required Map<String, dynamic> baselineMetricRanges,
}) {
  final updatedStatus = Map<String, String>.from(trendStatus);
  final updatedDeltas = Map<String, double>.from(trendDeltas);
  final updatedLockReasons = Map<String, String>.from(trendLockReasons);

  for (final entry in trendStatus.entries) {
    final key = entry.key;
    final status = entry.value.trim().toLowerCase();
    if (status != 'improved' && status != 'worsened') continue;

    final currentRange = _parseMetricRange(currentMetricRanges[key]);
    final baselineRange = _parseMetricRange(baselineMetricRanges[key]);
    if (currentRange == null || baselineRange == null) continue;

    final overlapLength =
        math.min(currentRange.max, baselineRange.max) -
        math.max(currentRange.min, baselineRange.min);
    // Conservative: any real overlap counts, not just a large fraction of
    // either range's width. A 1e-9 floor only excludes the two ranges
    // merely touching at a shared boundary value, not a genuine overlap.
    if (overlapLength > 1e-9) {
      updatedStatus[key] = 'stable';
      updatedDeltas[key] = 0.0;
      updatedLockReasons[key] = 'frame_range_overlap';
    }
  }

  return (
    trendStatus: updatedStatus,
    trendDeltas: updatedDeltas,
    trendLockReasons: updatedLockReasons,
  );
}

/// Client-side honesty gate that re-applies the backend's OWN measured
/// noise-floor policy (main.py's METRIC_NOISE_FLOOR_2SD /
/// TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE /
/// TREND_NOISE_FLOOR_EXCLUDED_MULTIPLIER, echoed back in the response as
/// metric_noise_floor_2sd / trend_noise_floor_exceeds_useful_range /
/// trend_noise_floor_excluded_multiplier) against the value actually shown
/// on screen.
///
/// Why this exists: _trend_delta_and_status runs once per backend call, and
/// the app calls the backend once PER CAPTURED FRAME, then averages the
/// frames' values client-side into the number that's displayed. The
/// backend's noise-floor gate (and every other gate in
/// _trend_delta_and_status) is therefore checked against a single frame's
/// raw value, never the averaged value the user sees -- even after nearest-
/// frame trend selection (see averageBackendAnalysisFrames), which only
/// narrows this gap, it doesn't close it. A frame can sit close to the
/// average yet still independently clear the floor on its own, while the
/// average itself does not: e.g. frames [20.0, 33.0, 37.6] average to 30.2
/// (a 3.2 delta against a 27.0 baseline, below texture_smoothness's 5.4
/// floor), but the nearest-to-average frame (33.0) has its own delta of
/// 6.0, clearing both the floor and the relative honesty band on its own
/// and reporting "Improved" -- a verdict about a number that isn't the one
/// on screen.
///
/// The thresholds themselves are read from the backend response rather
/// than duplicated as Dart constants, specifically so this can never drift
/// from main.py's calibration table -- see downgradeTrendForOverlappingFrameRanges's
/// doc comment for the same downgrade-only design this mirrors.
///
/// Downgrade-only, same as the overlap gate: only "improved"/"worsened" is
/// ever rewritten, only ever to "stable" (or, for a metric in
/// trendNoiseFloorExceedsUsefulRange, to "insufficient_signal" -- "stable"
/// is itself an overconfident claim once that metric's floor swallows most
/// of the range real users show, per main.py's own reasoning for that set).
/// A currently-"stable" excluded-metric verdict below its 3x threshold is
/// also corrected to "insufficient_signal" for the same reason. This layer
/// never invents a direction or upgrades a hedge into a stronger claim --
/// it has no way to independently verify a real "improved"/"worsened" would
/// be correct, only whether an existing directional claim should be
/// withdrawn.
///
/// Per (1): if the backend response is missing the threshold fields
/// entirely (an older backend build, or a metric absent from the table),
/// this falls back to existing behavior for the affected metric(s) --
/// leaving trendStatus/trendDeltas/trendLockReasons exactly as computed
/// upstream -- rather than skipping evaluation for every metric or forcing
/// a result. Same precedent as a missing frame range above.
({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, String> trendLockReasons,
})
downgradeTrendBelowMeasuredNoiseFloor({
  required Map<String, String> trendStatus,
  required Map<String, double> trendDeltas,
  required Map<String, String> trendLockReasons,
  required Map<String, dynamic> averagedMetricMatrix,
  required Map<String, dynamic> baselineMetricMatrix,
  required Map<String, dynamic> metricNoiseFloor2sd,
  required Set<String> trendNoiseFloorExceedsUsefulRange,
  required double? trendNoiseFloorExcludedMultiplier,
}) {
  final updatedStatus = Map<String, String>.from(trendStatus);
  final updatedDeltas = Map<String, double>.from(trendDeltas);
  final updatedLockReasons = Map<String, String>.from(trendLockReasons);

  for (final entry in trendStatus.entries) {
    final key = entry.key;
    final status = entry.value.trim().toLowerCase();
    if (status != 'improved' && status != 'worsened' && status != 'stable') {
      continue;
    }

    final floor = _parseFiniteDouble(metricNoiseFloor2sd[key]);
    final current = _parseFiniteDouble(averagedMetricMatrix[key]);
    final baseline = _parseFiniteDouble(baselineMetricMatrix[key]);
    if (floor == null || current == null || baseline == null) continue;

    final absoluteDelta = (current - baseline).abs();
    final isExcluded = trendNoiseFloorExceedsUsefulRange.contains(key);

    if (isExcluded) {
      if (trendNoiseFloorExcludedMultiplier == null) continue;
      final required = floor * trendNoiseFloorExcludedMultiplier;
      if (absoluteDelta < required && status != 'insufficient_signal') {
        updatedStatus[key] = 'insufficient_signal';
        updatedDeltas[key] = 0.0;
        updatedLockReasons.remove(key);
      }
    } else if (absoluteDelta < floor &&
        (status == 'improved' || status == 'worsened')) {
      updatedStatus[key] = 'stable';
      updatedDeltas[key] = 0.0;
      updatedLockReasons[key] = 'below_noise_floor';
    }
  }

  return (
    trendStatus: updatedStatus,
    trendDeltas: updatedDeltas,
    trendLockReasons: updatedLockReasons,
  );
}

/// Debug-only, per-frame diagnostic string for a failed or unusable backend
/// upload. [uploadFrame]'s only surface to analyzeBackendFrames is the
/// exception it throws (or a successful decoded response) -- there's no
/// direct access to the raw `http.Response` here -- so an HTTP failure is
/// recovered by parsing the "HTTP <code>: <body>" suffix that
/// SkinAnalysisService.uploadSingleImageFile's own exception message
/// always contains for a non-2xx response, rather than duplicating that
/// request/response handling in this file. Every frame in this flow
/// uploads to the same fixed endpoint (BackendConfig.analyzeSingleSkinUri),
/// so that constant is reported as "the request URL" without needing the
/// callback to expose it. Anything that doesn't match an HTTP failure
/// (timeout, socket error, etc. -- the request never completed) falls back
/// to the exception's own type and message.
String _describeUploadFailure(Object error) {
  final message = error.toString();
  final httpMatch = RegExp(r'HTTP (\d+):\s*([\s\S]*)$').firstMatch(message);
  if (httpMatch != null) {
    final status = httpMatch.group(1);
    final body = httpMatch.group(2) ?? '';
    final bodyPreview = body.length > 300 ? body.substring(0, 300) : body;
    return 'url=${BackendConfig.analyzeSingleSkinUri} status=$status '
        'body="$bodyPreview"';
  }
  return 'url=${BackendConfig.analyzeSingleSkinUri} '
      'exception=${error.runtimeType}: $message';
}

const String aiScanPerFrameDiagnosticsKey = 'per_frame_diagnostics';
const String rednessTrendLockReasonsKey = 'redness_trend_lock_reasons';
const String cheekSideConventionSubjectAnatomical = 'subject_anatomical';

List<Map<String, dynamic>> buildAiScanPerFrameDiagnostics({
  required List<Map<String, dynamic>?> frameResponses,
  required List<AiScanFrameExposure> frameExposureMetadata,
  required int frameCount,
}) {
  return List<Map<String, dynamic>>.generate(frameCount, (index) {
    final response = index < frameResponses.length
        ? frameResponses[index]
        : null;
    final metricsNode = _dynamicMap(response?['metrics']);
    final imageQuality = _dynamicMap(response?['image_quality']).isNotEmpty
        ? _dynamicMap(response?['image_quality'])
        : _dynamicMap(metricsNode['image_quality']);
    final metricMatrix = _dynamicMap(response?['metric_matrix']).isNotEmpty
        ? _dynamicMap(response?['metric_matrix'])
        : _dynamicMap(metricsNode['metric_matrix']);
    final exposure = index < frameExposureMetadata.length
        ? frameExposureMetadata[index]
        : const AiScanFrameExposure();
    return <String, dynamic>{
      'frame_number': index + 1,
      'cheek_side': imageQuality['redness_cheek_side'],
      'cheek_side_convention': imageQuality['cheek_side_convention'],
      'mask_pixel_count': imageQuality['redness_cheek_roi_pixels'],
      'cheek_p95_a_after_wb': imageQuality['redness_cheek_p95_a_after_wb'],
      'cheek_p10_a_after_wb': imageQuality['redness_cheek_p10_a_after_wb'],
      'cheek_p10_a_before_wb': imageQuality['redness_cheek_p10_a_before_wb'],
      'localized_redness': metricMatrix['localized_redness'],
        'face_skin_pixels': imageQuality['face_skin_pixels'],
        'pore_roi_pixels': imageQuality['pore_roi_pixels'],
        'u_zone_pixels': imageQuality['u_zone_pixels'],
        'localized_redness_mask_kind':
          imageQuality['localized_redness_mask_kind'],
        'localized_redness_mask_pixels':
          imageQuality['localized_redness_mask_pixels'],
        'texture_smoothness_mask_kind':
          imageQuality['texture_smoothness_mask_kind'],
        'texture_smoothness_mask_pixels':
          imageQuality['texture_smoothness_mask_pixels'],
        'pigment_load_mask_kind': imageQuality['pigment_load_mask_kind'],
        'pigment_load_mask_pixels': imageQuality['pigment_load_mask_pixels'],
        'pore_visibility_mask_kind': imageQuality['pore_visibility_mask_kind'],
        'pore_visibility_mask_pixels':
          imageQuality['pore_visibility_mask_pixels'],
        'diffuse_flushing_erythema_mask_kind':
          imageQuality['diffuse_flushing_erythema_mask_kind'],
        'diffuse_flushing_erythema_mask_pixels':
          imageQuality['diffuse_flushing_erythema_mask_pixels'],
      ...exposure.toJson(),
    };
  }, growable: false);
}

({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, String> trendLockReasons,
  Set<String> rednessLockReasons,
})
downgradeRednessTrendForCaptureMismatch({
  required Map<String, String> trendStatus,
  required Map<String, double> trendDeltas,
  required Map<String, String> trendLockReasons,
  required Map<String, dynamic> currentPayload,
  required Map<String, dynamic> baselinePayload,
}) {
  final existingRednessLockReason = trendLockReasons['localized_redness'];
  if (!trendStatus.containsKey('localized_redness') &&
      existingRednessLockReason != 'path_mismatch') {
    return (
      trendStatus: Map<String, String>.from(trendStatus),
      trendDeltas: Map<String, double>.from(trendDeltas),
      trendLockReasons: Map<String, String>.from(trendLockReasons),
      rednessLockReasons: const <String>{},
    );
  }

  Map<String, dynamic> imageQuality(Map<String, dynamic> payload) {
    final direct = _dynamicMap(payload['image_quality']);
    if (direct.isNotEmpty) return direct;
    return _dynamicMap(_dynamicMap(payload['metrics'])['image_quality']);
  }

  List<double> frameP95Values(Map<String, dynamic> payload) {
    final raw = payload[aiScanPerFrameDiagnosticsKey];
    if (raw is! List) return const <double>[];
    return raw
        .map((frame) => _parseFiniteDouble(_dynamicMap(frame)['cheek_p95_a_after_wb']))
        .whereType<double>()
        .toList(growable: false);
  }

  final currentQuality = imageQuality(currentPayload);
  final baselineQuality = imageQuality(baselinePayload);
  final currentSide = currentQuality['redness_cheek_side']?.toString().trim();
    final storedBaselineSide = baselineQuality['redness_cheek_side']
      ?.toString()
      .trim();
    final baselineConvention = baselineQuality['cheek_side_convention']
      ?.toString()
      .trim();
    final baselineSide = baselineConvention == cheekSideConventionSubjectAnatomical
      ? storedBaselineSide
      : switch (storedBaselineSide) {
        'left' => 'right',
        'right' => 'left',
        _ => storedBaselineSide,
      };
  final reasons = <String>{};
  if (existingRednessLockReason == 'path_mismatch') {
    reasons.add('path_mismatch');
  }
  if (currentSide != null &&
      currentSide.isNotEmpty &&
      baselineSide != null &&
      baselineSide.isNotEmpty &&
      currentSide != baselineSide) {
    reasons.add('cheek_mismatch');
  }

  final currentFrameP95 = frameP95Values(currentPayload);
  final baselineFrameP95 = frameP95Values(baselinePayload);
  if (currentFrameP95.length < 2 || baselineFrameP95.length < 2) {
    reasons.add('cast_mismatch');
  } else {
    double range(List<double> values) =>
        values.reduce(math.max) - values.reduce(math.min);
    final allowedDelta = math.max(
      range(currentFrameP95),
      range(baselineFrameP95),
    );
    final currentP10 = _parseFiniteDouble(
      currentQuality['redness_cheek_p10_a_after_wb'],
    );
    final baselineP10 = _parseFiniteDouble(
      baselineQuality['redness_cheek_p10_a_after_wb'],
    );
    final currentP95 = _parseFiniteDouble(
      currentQuality['redness_cheek_p95_a_after_wb'],
    );
    final baselineP95 = _parseFiniteDouble(
      baselineQuality['redness_cheek_p95_a_after_wb'],
    );
    if ((currentP10 != null &&
            baselineP10 != null &&
            (currentP10 - baselineP10).abs() > allowedDelta) ||
        (currentP95 != null &&
            baselineP95 != null &&
            (currentP95 - baselineP95).abs() > allowedDelta)) {
      reasons.add('cast_mismatch');
    }
  }

  final updatedStatus = Map<String, String>.from(trendStatus);
  final updatedDeltas = Map<String, double>.from(trendDeltas);
  final updatedLockReasons = Map<String, String>.from(trendLockReasons);
  if (reasons.isNotEmpty) {
    updatedStatus.remove('localized_redness');
    updatedDeltas.remove('localized_redness');
    updatedLockReasons['localized_redness'] = reasons.contains('cheek_mismatch')
        ? 'cheek_mismatch'
        : reasons.contains('cast_mismatch')
        ? 'cast_mismatch'
        : 'path_mismatch';
  }

  return (
    trendStatus: updatedStatus,
    trendDeltas: updatedDeltas,
    trendLockReasons: updatedLockReasons,
    rednessLockReasons: Set<String>.unmodifiable(reasons),
  );
}

Future<MultiFrameAnalysisAggregate> analyzeBackendFrames(
  List<Uint8List> frames, {
  required Future<Map<String, dynamic>> Function(
    Uint8List frame,
    int frameNumber,
  ) uploadFrame,
  List<AiScanFrameExposure> frameExposureMetadata =
      const <AiScanFrameExposure>[],
}) async {
  final responses = <Map<String, dynamic>>[];
  final responsesByFrame = List<Map<String, dynamic>?>.filled(
    frames.length,
    null,
  );
  // Debug-only: one human-readable reason per frame that didn't contribute
  // a usable metric, appended to averageBackendAnalysisFrames' StateError
  // below so the on-screen red error banner shows why, instead of only a
  // debugPrint the user can't see on a physical device. Never collected
  // (and so never shown) in release builds -- release keeps today's plain
  // message.
  final failureReasons = <String>[];
  for (var index = 0; index < frames.length; index++) {
    final frameNumber = index + 1;
    try {
      final response = await uploadFrame(frames[index], frameNumber);
      responses.add(response);
      responsesByFrame[index] = response;
      if (kDebugMode) {
        final metricsNode = _dynamicMap(response['metrics']);
        final matrix = _dynamicMap(response['metric_matrix']).isNotEmpty
            ? _dynamicMap(response['metric_matrix'])
            : _dynamicMap(metricsNode['metric_matrix']);
        if (matrix.isEmpty) {
          failureReasons.add(
            'Frame $frameNumber: request succeeded (HTTP 200) but the '
            'response had no usable metric_matrix',
          );
        }
      }
    } catch (error) {
      debugPrint(
        '[MultiFrameAnalysis] Frame $frameNumber/${frames.length} failed: $error',
      );
      if (kDebugMode) {
        failureReasons.add(
          'Frame $frameNumber: ${_describeUploadFailure(error)}',
        );
      }
    }
  }
  try {
    final aggregate = averageBackendAnalysisFrames(
      responses,
      requestedFrames: frames.length,
    );
    aggregate.response[aiScanPerFrameDiagnosticsKey] =
        buildAiScanPerFrameDiagnostics(
          frameResponses: responsesByFrame,
          frameExposureMetadata: frameExposureMetadata,
          frameCount: frames.length,
        );
    return aggregate;
  } on StateError catch (e) {
    if (kDebugMode && failureReasons.isNotEmpty) {
      throw StateError('${e.message}\n${failureReasons.join('\n')}');
    }
    rethrow;
  }
}

Map<String, dynamic> luxePrecisionMetadataFromBackend(
  Map<String, dynamic>? backendResponse,
) =>
    <String, dynamic>{
      'metric_confidence': _dynamicMap(
        backendResponse?['metric_confidence'],
      ),
      'multi_frame_analysis': _dynamicMap(
        backendResponse?['multi_frame_analysis'],
      ),
    };

/// Friendly capture-quality tag for the results hero badge — replaces the
/// old "N% confidence" figure, which was never a confidence in the
/// clinical claim shown next to it, only in whether the on-device model
/// successfully located a face. [rawCaptureQualityTag] is the same raw
/// tag sent to the backend (see buildAiSkinAnalysisBackendFields above /
/// main.py's `_normalize_capture_quality`), so this is honest, real
/// pipeline metadata rather than a fabricated number. A top-level pure
/// function (no screen state) so it's directly unit-testable.
String captureQualityBadgeLabel(String? rawCaptureQualityTag) {
  switch ((rawCaptureQualityTag ?? '').trim().toLowerCase()) {
    case 'normal':
      return 'Good capture quality';
    case 'low_light':
      return 'Low light';
    case 'poor_angle':
      return 'Off angle';
    case 'uneven_lighting':
      return 'Uneven lighting';
    case 'blurry':
      return 'Blurry';
    case 'face_offcenter':
      return 'Off-center';
    default:
      return 'Capture quality unknown';
  }
}

String _joinWithCommasAndAndPure(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  if (items.length == 2) return '${items.first} and ${items.last}';
  return '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}';
}

/// Backend-only, non-diagnostic hero headline + subheadline for the AI
/// Skin Analysis results screen. Built EXCLUSIVELY from [metricMatrix]
/// (the same cleaned backend metric_matrix LuxeReportLayout renders —
/// see _buildLuxeResultsPayload): never reads AcneRosaceaPhotoAnalyzer's
/// local pixel-heuristic report, the on-device TFLite model, or any
/// other local signal. Deliberately never names a condition (acne /
/// rosacea / telangiectasia) — only the plain-language visual concern
/// area a metric maps to, matching the vocabulary already used in
/// _coachTopConcerns. Keys absent from [metricMatrix] are treated as "no
/// data" (not "no concern") and skipped entirely, since the backend only
/// populates a key when its honesty gates trust it for this scan. A
/// top-level pure function (no screen state) so it's directly
/// unit-testable — see test/skin_ai_results_hero_backend_only_test.dart.
({String headline, String subheadline}) buildBackendHeroCopy(
  Map<String, dynamic> metricMatrix,
) {
  double? metricValue(String key) {
    if (!metricMatrix.containsKey(key)) return null;
    final raw = metricMatrix[key];
    final parsed = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
    return parsed.clamp(0.0, 100.0).toDouble();
  }

  final concerns = <String, double>{};
  final rednessValues = [
    metricValue('localized_redness'),
    metricValue('rosacea_severity'),
  ].whereType<double>().toList();
  if (rednessValues.isNotEmpty) {
    concerns['redness'] = rednessValues.reduce(math.max);
  }
  final textureSmoothness = metricValue('texture_smoothness');
  if (textureSmoothness != null) {
    // Inverted: texture_smoothness is "higher = smoother = better", but
    // the hero speaks in "how much this stood out" terms.
    concerns['texture'] = (100.0 - textureSmoothness).clamp(0.0, 100.0);
  }
  final pigment = metricValue('pigment_load');
  if (pigment != null) concerns['tone evenness'] = pigment;
  final wrinkle = metricValue('wrinkle_load');
  if (wrinkle != null) concerns['fine lines'] = wrinkle;
  final breakout = metricValue('breakout_activity');
  if (breakout != null) concerns['visible breakouts'] = breakout;

  if (concerns.isEmpty) {
    return (
      headline: 'Scan captured',
      subheadline:
          "Backend metrics aren't available yet for this scan — check back after processing finishes.",
    );
  }

  final ranked = concerns.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = ranked.first;

  String band(double value) {
    if (value < 25) return 'Minimal';
    if (value < 50) return 'Mild';
    if (value < 70) return 'Noticeable';
    return 'Significant';
  }

  final headline = top.value < 25
      ? 'Calm, low-concern scan'
      : '${band(top.value)} ${top.key} pattern in this scan';

  final flagged = ranked
      .where((entry) => entry.value >= 40)
      .take(3)
      .map((entry) => entry.key)
      .toList();
  final subheadline = flagged.isEmpty
      ? 'No individual metric stood out beyond the typical range in this scan.'
      : 'Most notable: ${_joinWithCommasAndAndPure(flagged)}.';

  return (headline: headline, subheadline: subheadline);
}

/// Backend-only timeline metrics for persistence (Skin Tracker / Recovery
/// Timeline history, and the visual skin-age estimate derived from them —
/// see estimateVisualSkinAgeFromAiMetrics). Each of the six base values
/// (pigment, redness, texture, wrinkle, acne_severity, rosacea_intensity)
/// is read ONLY from [unifiedMetrics] — this scan's freshly-parsed
/// backend metric_matrix (see _parseBackendAnalysisPayload) — never from
/// AcneRosaceaPhotoAnalyzer's local pixel-heuristic report, the on-device
/// EfficientNet quality scores, or a stale previous scan's cached
/// `_fullMetrics` reading. All three of those were previously used as
/// silent substitutes whenever the backend didn't have a value, which is
/// exactly the "looks precise, isn't backed by anything" problem this
/// function existed to avoid.
///
/// When the backend has no usable value for a metric, that metric — and
/// every aggregate metric derived from it (swelling, firmness,
/// overallHealingScore, etc.) — is OMITTED from the result entirely
/// rather than computed from a fabricated or partial substitute. Callers
/// (and anything reading persisted scan history later) must treat a
/// missing key as "no data", not "zero". A top-level pure function (no
/// screen state) so it's directly unit-testable — see
/// test/skin_ai_timeline_metrics_backend_only_test.dart.
Map<String, double> timelineMetricsFromBackend(
  Map<String, double>? unifiedMetrics,
) {
  double? backendValue(String key) {
    final v = unifiedMetrics?[key];
    if (v == null || v.isNaN || v.isInfinite) return null;
    return (v * 10).clamp(0.0, 10.0).toDouble();
  }

  final pigmentFinal = backendValue('pigment');
  final rednessFinal = backendValue('redness');
  final textureFinal = backendValue('texture');
  final wrinkleFinal = backendValue('wrinkle');
  final acne = backendValue('acne_severity');
  final rosacea = backendValue('rosacea_intensity');

  final out = <String, double>{};
  void put(String key, double? value) {
    if (value != null) out[key] = value;
  }

  // Primary four requested timeline metrics.
  put('pigment', pigmentFinal);
  put('redness', rednessFinal);
  put('texture', textureFinal);
  put('wrinkle', wrinkleFinal);
  // Aliases consumed by existing recovery timeline insight helpers.
  put('pigmentation', pigmentFinal);
  put('darkSpots', pigmentFinal);
  put('erythema', rednessFinal);
  put('roughness', textureFinal);
  put('wrinkles', wrinkleFinal);
  put('rhytids', wrinkleFinal);
  put('hyperpigmentation', pigmentFinal);
  // Inflammatory conditions.
  put('acne_severity', acne);
  put('acneSeverity', acne);
  put('rosacea_intensity', rosacea);
  put('rosaceaSeverity', rosacea);

  // Aggregate/derived metrics — only computable when every input they
  // depend on is itself backend-derived; omitted (not substituted)
  // otherwise, and cascading: an aggregate whose inputs are missing
  // can't honestly be computed even partially.
  double? swelling;
  if (rednessFinal != null && textureFinal != null && pigmentFinal != null) {
    swelling = (rednessFinal * 0.50 + textureFinal * 0.30 + pigmentFinal * 0.20)
        .clamp(0, 10)
        .toDouble();
  }
  put('swelling', swelling);
  put('edema', swelling);

  double? firmness;
  if (textureFinal != null && wrinkleFinal != null && swelling != null) {
    firmness = (10 - (textureFinal * 0.45 + wrinkleFinal * 0.20 + swelling * 0.15))
        .clamp(0, 10)
        .toDouble();
  }
  put('firmness', firmness);
  put('bodyFirmness', firmness);
  put('skinLaxityFirmness', firmness);

  double? smoothness;
  if (textureFinal != null) {
    smoothness = (10 - textureFinal).clamp(0, 10).toDouble();
  }
  put('smoothness', smoothness);
  put('bodySmoothness', smoothness);
  put('textureSmoothness', smoothness);

  double? scarringBruising;
  if (pigmentFinal != null && rednessFinal != null && textureFinal != null) {
    scarringBruising =
        (pigmentFinal * 0.45 + rednessFinal * 0.35 + textureFinal * 0.20)
            .clamp(0, 10)
            .toDouble();
  }
  put('scarringBruising', scarringBruising);
  put('scarring_bruising', scarringBruising);
  put('bruising', scarringBruising);

  double? fatRetention;
  if (swelling != null && scarringBruising != null && textureFinal != null) {
    fatRetention =
        (10 - (swelling * 0.30 + scarringBruising * 0.20 + textureFinal * 0.15))
            .clamp(0, 10)
            .toDouble();
  }
  put('fatRetention', fatRetention);
  put('fat_retention', fatRetention);

  double? overallHealing;
  if (swelling != null &&
      firmness != null &&
      smoothness != null &&
      scarringBruising != null &&
      pigmentFinal != null &&
      fatRetention != null) {
    overallHealing = ((10 - swelling) * 0.22 +
            firmness * 0.18 +
            smoothness * 0.16 +
            (10 - scarringBruising) * 0.18 +
            (10 - pigmentFinal) * 0.12 +
            fatRetention * 0.14)
        .clamp(0, 10)
        .toDouble();
  }
  put('overallHealingScore', overallHealing);
  put('overall_healing_score', overallHealing);
  put('bodyHealingScore', overallHealing);

  if (out.isNotEmpty) out['sourceSkinAiAnalysis'] = 1;

  return out;
}

/// Everything _getPreviousMetrics resolves about the current capture's
/// baseline, per the per-(procedureId, focusArea, poseTemplate, guideType)
/// baseline rule -- kept as one bundle so every consumer (backend fields,
/// the local Luxe metric matrix, "first scan"/"pin ignored" messaging)
/// reads a single, consistent resolution instead of recomputing it.
class AiBaselineResolution {
  const AiBaselineResolution({
    this.key,
    this.baselineScan,
    this.eligibleScansForKey = const <ScanHistoryEntry>[],
    this.isFirstForKey = false,
    this.ignoredPinReason,
    this.baselineUnavailable = false,
    this.shouldPinResolvedBaseline = false,
  });

  /// The current capture's own key. Null until the first resolution runs.
  final AiBaselineKey? key;

  /// The resolved baseline entry for this key, or null if none exists yet
  /// -- this capture will become the baseline once saved, if it itself
  /// passes [scanPassesSingleScanBaselineGates].
  final ScanHistoryEntry? baselineScan;

  /// The one fixed baseline scan available to per-metric readers, or empty
  /// while no baseline is available. Never contains alternative scans.
  final List<ScanHistoryEntry> eligibleScansForKey;

  /// True when there is no valid baseline (no pin, no eligible earliest
  /// scan) for this key yet.
  final bool isFirstForKey;

  /// Non-null when a fixed pin is unavailable, key-mismatched, or no longer
  /// eligible. No alternative history scan is substituted in that case.
  final String? ignoredPinReason;

  final bool baselineUnavailable;

  final bool shouldPinResolvedBaseline;
}

/// Pure resolution of the AI Skin Analysis baseline for [key], given every
/// scan matching that key (in any order) and whatever scan id (if any) is
/// currently pinned for it. Implements the baseline product rule's
/// precedence exactly: a valid fixed pin wins; a reset marker permits only
/// post-reset scans; a broken pin blocks comparison; earliest-history fallback
/// is reserved for legacy keys with no registry entry at all.
AiBaselineResolution resolveAiBaseline({
  required AiBaselineKey key,
  required List<ScanHistoryEntry> keyMatches,
  required List<ScanHistoryEntry> allScans,
  String? pinnedScanId,
  bool registryEntryExists = false,
  DateTime? resetAt,
}) {
  final sorted = List<ScanHistoryEntry>.from(keyMatches)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final eligible = sorted.where((scan) {
    if (!scanPassesSingleScanBaselineGates(scan)) return false;
    return resetAt == null || !scan.timestamp.toUtc().isBefore(resetAt.toUtc());
  }).toList();

  ScanHistoryEntry? pinnedValid;
  String? ignoredPinReason;
  final cleanPinnedId = pinnedScanId?.trim();
  if (cleanPinnedId != null && cleanPinnedId.isNotEmpty) {
    ScanHistoryEntry? pinnedScan;
    for (final scan in allScans) {
      if (scan.id == cleanPinnedId) {
        pinnedScan = scan;
        break;
      }
    }
    if (pinnedScan == null) {
      ignoredPinReason =
          'Your baseline scan is unavailable. Reset or update the baseline '
          'before comparing new scans.';
    } else if (pinnedScan.aiBaselineKey != key) {
      ignoredPinReason =
          'Your baseline no longer matches this angle or region. Reset or '
          'update the baseline before comparing new scans.';
    } else if (!scanPassesSingleScanBaselineGates(pinnedScan)) {
      ignoredPinReason =
          'Your baseline scan no longer meets the quality checks required '
          'for comparison. Reset or update the baseline.';
    } else {
      pinnedValid = pinnedScan;
    }
  }

  if (cleanPinnedId != null && cleanPinnedId.isNotEmpty) {
    return AiBaselineResolution(
      key: key,
      baselineScan: pinnedValid,
      eligibleScansForKey: pinnedValid == null ? const [] : [pinnedValid],
      isFirstForKey: false,
      ignoredPinReason: pinnedValid == null ? ignoredPinReason : null,
      baselineUnavailable: pinnedValid == null,
    );
  }

  if (resetAt != null) {
    final resetBaseline = eligible.isNotEmpty ? eligible.first : null;
    return AiBaselineResolution(
      key: key,
      baselineScan: resetBaseline,
      eligibleScansForKey: resetBaseline == null ? const [] : [resetBaseline],
      isFirstForKey: resetBaseline == null,
      shouldPinResolvedBaseline: resetBaseline != null,
    );
  }

  if (registryEntryExists) {
    return AiBaselineResolution(
      key: key,
      isFirstForKey: false,
      ignoredPinReason:
          'Your baseline registry entry is unavailable. Reset or update the '
          'baseline before comparing new scans.',
      baselineUnavailable: true,
    );
  }

  final resolvedBaseline = eligible.isNotEmpty ? eligible.first : null;

  return AiBaselineResolution(
    key: key,
    baselineScan: resolvedBaseline,
    eligibleScansForKey: resolvedBaseline == null ? const [] : [resolvedBaseline],
    isFirstForKey: resolvedBaseline == null,
  );
}

class _SkinAiAnalysisScreenState extends State<SkinAiAnalysisScreen> {
  /// Debug-only: shares camera_screen.dart's burst_luminance.log via the
  /// native share sheet, for pulling burst-luminance logging data off a
  /// physical device without Xcode's Devices and Simulators window.
  Future<void> _exportBurstLuminanceLog(BuildContext buttonContext) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final logFile = File(
        '${docsDir.path}${Platform.pathSeparator}burst_luminance.log',
      );
      if (!await logFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No burst_luminance.log found yet.')),
          );
        }
        return;
      }
      final renderObject = buttonContext.findRenderObject();
      final box = renderObject is RenderBox ? renderObject : null;
      final origin =
          (box != null &&
              box.hasSize &&
              box.size.width > 0 &&
              box.size.height > 0)
          ? (box.localToGlobal(Offset.zero) & box.size)
          : const Rect.fromLTWH(0, 0, 1, 1);
      await Share.shareXFiles(
        [XFile(logFile.path)],
        text: 'Burst luminance log',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to export burst log: $e')));
      }
    }
  }

  Future<void> _exportScanData(BuildContext buttonContext) async {
    final messenger = ScaffoldMessenger.of(context);
    final renderObject = buttonContext.findRenderObject();
    final box = renderObject is RenderBox ? renderObject : null;
    final origin =
        (box != null &&
            box.hasSize &&
            box.size.width > 0 &&
            box.size.height > 0)
        ? (box.localToGlobal(Offset.zero) & box.size)
        : const Rect.fromLTWH(0, 0, 1, 1);
    try {
      final scans = AiScanDataCsvExporter.exportableScans(
        await AppPrefs.getScanEntriesWithoutNormalization(),
      );
      if (scans.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No saved AI scan data to export.')),
          );
        }
        return;
      }

      final fileName =
          'ai_skin_analysis_scans_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';
      final csv = AiScanDataCsvExporter.format(
        scans,
        registryBaselineScanIds: await AppPrefs.getAllAiBaselineScanIds(),
      );
      final file = kIsWeb
          ? XFile.fromData(
              Uint8List.fromList(utf8.encode(csv)),
              mimeType: 'text/csv',
              name: fileName,
            )
          : await _writeScanDataCsv(fileName, csv);
      await Share.shareXFiles(
        [file],
        text: 'AI Skin Analysis scan data',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to export scan data: $e')),
        );
      }
    }
  }

  Future<XFile> _writeScanDataCsv(String fileName, String csv) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(csv, flush: true);
    return XFile(file.path, mimeType: 'text/csv', name: fileName);
  }

  _Stage _stage = _Stage.capture;

  String? _imagePath;

  /// Cropped JPEG bytes from the mandatory crop step (camera/gallery). When
  /// non-null these exact bytes are what the analyzer receives — never the
  /// uncropped original. A "latest scan" selection leaves this null and is
  /// read from its stored path instead.
  Uint8List? _croppedBytes;
  List<Uint8List> _analysisFrameBytes = const [];
  List<AiScanFrameExposure> _analysisFrameExposureMetadata = const [];

  /// The user must explicitly accept the pre-analysis disclaimer before the
  /// "Run AI Analysis" button unlocks. This is a hard gate, not a checkbox
  /// that can be skipped.
  bool _consentAccepted = false;
  FacialRegion? _region = FacialRegion.fullFace;
  bool _cycleRelated = false;
  bool _adultOnset = false;

  /// Validation message shown beneath the focus-area chips when the user
  /// attempts to run analysis without first selecting a focus area.
  String? _focusAreaError;

  PhotoAnalysisResult? _result;
  ModelInfo _modelInfo = ModelInfo.fallback;
  double? _modelConfidence;
  Set<String> _modelOwnedMetrics = const {};
  bool _meshUsed = false;
  double? _symmetryScore;
  double? _faceCoverage;
  bool _yoloUsed = false;
  List<Detection> _detections = const [];
  bool _efficientNetUsed = false;
  SkinQualityScores? _qualityScores;
  String? _analysisError;
  ScanHistoryEntry? _latestScan;
  ScanHistoryEntry? _ghostReferenceScan;
  bool _loadingLatest = true;
  bool _ghostOverlayEnabled = true;
  String? _selectedProcedureId;
  String? _selectedProcedureType;
  String? _selectedProcedureFocusArea;
  String? _selectedProcedureCustomDescription;
  static const double _ghostOverlayOpacity = 0.20;

  /// Canonical metric map used by timeline/result rendering. In the
  /// server-first flow this is populated from backend metric-matrix
  /// values and normalized to 0-1 for shared timeline math.
  Map<String, double> _fullMetrics = const {};

  /// The 6 metrics from the most recent PREVIOUS scan, captured before
  /// the current scan is persisted. Used to draw improvement/worsening
  /// trend indicators in the results card. Empty when there is no prior
  /// scan to compare against (first-ever analysis).
  Map<String, double> _previousMetrics = const {};
  ScanHistoryEntry? _previousFocusAreaScan;
  ScanHistoryEntry? _baselineFocusAreaScan;
  String? _currentCaptureQuality;

  /// The view angle and camera guide type from the CameraScreen capture
  /// that produced [_imagePath] (see AiSkinAnalysisCaptureResult). Null
  /// when the photo came from the gallery instead of the live camera --
  /// the angle/region are then genuinely unknown for that scan, and are
  /// saved as null rather than guessed.
  String? _capturedPoseTemplate;
  String? _capturedGuideType;

  /// Set by [_getPreviousMetrics] when prior scans exist for this
  /// procedure/focus area but none share this capture's angle AND guide
  /// type -- so the results UI can say plainly that no matching baseline
  /// exists, instead of silently falling back to "first scan" copy or
  /// comparing across angles. Null whenever a real baseline was found, or
  /// when there were no candidate scans at all for another reason.
  String? _noComparableBaselineMessage;
  List<ScanHistoryEntry> _priorFocusAreaScans = const [];
  bool _hasPriorFocusAreaScan = false;
  int _localHistoryCountForFocusArea = 1;
  bool _explicitLocalFollowUpFlag = false;
  bool _explicitBaselineSelection = false;
  Map<String, double> _serverTrendDeltas = const {};
  Map<String, String> _serverTrendStatus = const {};
  Map<String, String> _serverTrendLockReasons = const {};
  Map<String, dynamic>? _latestBackendAnalysisPayload;
  Map<String, int> _metricContributorCounts = const {};
  int _successfulAnalysisFrameCount = 0;
  int _requestedAnalysisFrameCount = 0;
  /// The resolved AI Skin Analysis baseline for the current capture's
  /// (procedureId, focusArea, poseTemplate, guideType) key -- see
  /// AiBaselineResolution. Replaces the old device-global
  /// _manualBaselineMetricMatrix cache, which carried no such scoping.
  AiBaselineResolution _aiBaselineResolution = const AiBaselineResolution();

  /// The per-key AI baseline registry's id for the current capture's key,
  /// as read during baseline resolution (null when none was registered).
  String? _aiBaselineRegistryScanId;

  /// Set once, right after this scan is saved, when it just became the
  /// first-ever registered baseline for its key.
  bool _currentScanBecameNewBaseline = false;

  /// Non-null when this scan was eligible to become the first baseline for
  /// its key (no earlier one existed) but was NOT saved as one because it
  /// failed a single-scan honesty gate (see aiBaselineRejectionReason).
  /// The results screen must show this instead of "Baseline scan
  /// captured" -- it was never saved as a baseline.
  String? _baselineNotSavedReason;

  /// Non-null when a pinned baseline existed for this key but was ignored
  /// (missing pose/guide, or failed a single-scan honesty gate) -- shown in
  /// the results so the user knows why their pin didn't take effect.
  String? _ignoredBaselinePinMessage;

  /// Plain confirmation text once this scan has actually been registered as
  /// the first baseline for its key (see _registerAiBaselineIfNeeded) --
  /// null until that registration has actually happened, so this never
  /// claims "it's now your baseline" for a scan that failed its own
  /// single-scan honesty gates.
  String? get _firstBaselineConfirmationMessage {
    if (!_currentScanBecameNewBaseline) return null;
    final focusLabel = _resolvedFocusArea().trim().isEmpty
        ? 'this area'
        : _resolvedFocusArea().trim();
    final pose = _capturedPoseTemplate;
    return pose == null
        ? 'This scan is now your baseline for future comparisons.'
        : 'This is your first $pose scan of $focusLabel; it\'s now your '
            'baseline.';
  }

  /// Debug-only: the deployed backend's git commit (see GET /health and
  /// main.py's health_check), shown on the results screen so a developer
  /// can confirm which server build actually served this analysis. Null
  /// while loading, unreachable, or in a release build (never fetched).
  String? _debugBackendCommit;

  @override
  void initState() {
    super.initState();
    _loadLatestScan();
    _loadProcedureContext();
    _refreshFocusAreaPhaseHint();
    if (kDebugMode) {
      remote_analysis.SkinAnalysisService.fetchBackendCommit().then((commit) {
        if (!mounted) return;
        setState(() => _debugBackendCommit = commit);
      });
    }
  }

  Future<void> _refreshFocusAreaPhaseHint() async {
    try {
      final focus = _normalizeFocus(_resolvedFocusArea());
      final scans = await SkinHistoryRepository.instance.getAllScans();
      final hasAny = scans.any((scan) {
        final scanFocus = _normalizeFocus(scan.focusArea);
        if (focus.isNotEmpty && scanFocus != focus) return false;
        if (scan.isAiAnalysisScan && (scan.imagePath ?? '').trim().isNotEmpty) {
          return true;
        }
        final raw = scan.metrics;
        return SkinHistoryRepository.allMetricKeys.any(raw.containsKey) ||
            const [
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
            ].any(raw.containsKey) ||
            const [
              'fatRetention',
              'swelling',
              'firmness',
              'smoothness',
              'scarringBruising',
              'hyperpigmentation',
              'overallHealingScore',
            ].any(raw.containsKey);
      });
      if (!mounted) return;
      setState(() {
        _hasPriorFocusAreaScan = hasAny;
      });
    } catch (_) {
      // Keep existing phase hint if history lookup fails.
    }
  }

  double? _safeToDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  AiBaselineKey _currentAiBaselineKey() {
    final selectedProcedureId = (_selectedProcedureId ?? '').trim();
    return ScanHistoryEntry.resolveAiBaselineKey(
      procedureId: selectedProcedureId.isEmpty ? null : selectedProcedureId,
      focusArea: _resolvedFocusArea(),
      poseTemplate: _capturedPoseTemplate,
      guideType: _capturedGuideType,
    );
  }

  /// Clears the registered baseline for the CURRENT capture's key only
  /// (see AppPrefs.clearAiBaselineScanId) -- every other angle/region/
  /// procedure keeps its own baseline untouched.
  Future<void> _handleBaselineReset() async {
    final key = _currentAiBaselineKey();
    await AppPrefs.clearAiBaselineScanId(key);
    if (!mounted) return;
    setState(() {
      _aiBaselineResolution = const AiBaselineResolution();
      _currentScanBecameNewBaseline = false;
      _baselineNotSavedReason = null;
      _ignoredBaselinePinMessage = null;
      _serverTrendDeltas = const {};
      _serverTrendStatus = const {};
      _serverTrendLockReasons = const {};
    });
  }

  Future<void> _showResetConfirmationDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset Skin Baseline?'),
          content: const Text(
            'This will set your next scan as your new permanent benchmark. '
            'Future scans will measure progress from this point forward.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(foregroundColor: MyApp.clinicalSlate),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _handleBaselineReset();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.softTerracotta,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reset Baseline'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadProcedureContext() async {
    try {
      final selectedId = (await AppPrefs.getSelectedProcedureIdOrNull())
          ?.trim();
      final entries = await AppPrefs.getProcedureEntries();
      String? procedureType;
      if (selectedId?.isNotEmpty == true) {
        for (final entry in entries) {
          final id = (entry['id'] ?? entry['procedureId'] ?? '')
              .toString()
              .trim();
          if (id != selectedId) continue;
          final type = (entry['type'] ?? entry['procedure'] ?? '')
              .toString()
              .trim();
          if (type.isNotEmpty) {
            procedureType = type;
          }
          final focusArea = (entry['focusArea'] ?? '').toString().trim();
          final customDescription = (entry['customDescription'] ?? '')
              .toString()
              .trim();
          if (!mounted) return;
          setState(() {
            _selectedProcedureId = selectedId;
            _selectedProcedureType = procedureType;
            _selectedProcedureFocusArea = focusArea.isNotEmpty
                ? focusArea
                : null;
            _selectedProcedureCustomDescription = customDescription.isNotEmpty
                ? customDescription
                : null;
          });
          _refreshFocusAreaPhaseHint();
          return;
        }
      }
      final storedProcedureType = (await AppPrefs.getProcedureType()).trim();
      procedureType ??= storedProcedureType.isNotEmpty
          ? storedProcedureType
          : null;
      if (!mounted) return;
      setState(() {
        _selectedProcedureId = selectedId?.isNotEmpty == true
            ? selectedId
            : null;
        _selectedProcedureType = procedureType;
      });
      _refreshFocusAreaPhaseHint();
    } catch (_) {
      // Procedure context is optional; facial Skin AI remains the fallback.
    }
  }

  bool get _isBodyProcedure =>
      procedure_intel.ProcedureIntelligence.categoryFor(
        _selectedProcedureType,
      ) ==
      procedure_intel.ProcedureCategory.bodyContouring;

  bool get _isFullFaceFocusSelected {
    if (_region == FacialRegion.fullFace) return true;
    final focus = _normalizeFocus(_resolvedFocusArea());
    return focus == 'full face';
  }

  bool get _showCoreFaceMetricSetOnly =>
      !_isBodyProcedure && _isFullFaceFocusSelected;

  Future<void> _loadLatestScan() async {
    try {
      final scans = await AppPrefs.getScanEntries();
      final withPhoto =
          scans.where((s) => (s.imagePath ?? '').isNotEmpty).toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (!mounted) return;
      setState(() {
        _latestScan = withPhoto.isNotEmpty ? withPhoto.first : null;
        _ghostReferenceScan = withPhoto.isNotEmpty ? withPhoto.first : null;
        _loadingLatest = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLatest = false);
    }
  }

  // ── Photo source actions ──────────────────────────────────────────

  Future<void> _pickFromCamera() async {
    try {
      final captured = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => const CameraScreen(
            isSkincareScan: true,
            aiMultiFrameCapture: true,
            capturePurpose: CameraCapturePurpose.aiSkinAnalysis,
          ),
        ),
      );

      final capturedImagePath = switch (captured) {
        AiSkinAnalysisCaptureResult result => result.primaryImagePath,
        String path => path,
        _ => null,
      };

      if (!mounted || capturedImagePath == null || capturedImagePath.isEmpty) {
        return;
      }

      setState(() {
        _imagePath = capturedImagePath;
        if (captured is AiSkinAnalysisCaptureResult) {
          _analysisFrameBytes = captured.croppedFrames;
          _analysisFrameExposureMetadata = captured.frameExposureMetadata;
          _croppedBytes = captured.croppedFrames.first;
          _currentCaptureQuality = captured.captureQuality;
          _capturedPoseTemplate = captured.poseTemplate;
          _capturedGuideType = captured.guideType;
        } else {
          _analysisFrameBytes = const [];
          _analysisFrameExposureMetadata = const [];
          _croppedBytes = null;
          _currentCaptureQuality = null;
          _capturedPoseTemplate = null;
          _capturedGuideType = null;
        }
        _explicitBaselineSelection = false;
      });

      if (_region == null) {
        setState(() {
          _focusAreaError =
              'Please select a focus area before generating your progress report.';
        });
        return;
      }

      setState(() => _focusAreaError = null);
      await _runAnalysis();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera unavailable: $e')),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    await _pickAndCrop(ImageSource.gallery, 'Could not open photo');
  }

  /// Picks an image then forces the shared [ImageCropDialog]. The analyzer
  /// only ever sees the cropped patch: on success [_croppedBytes] and a
  /// displayable [_imagePath] are set together; on cancel both are cleared
  /// so the "Run AI Analysis" button stays disabled.
  Future<void> _pickAndCrop(ImageSource source, String errorLabel) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2400,
      );
      if (picked == null || !mounted) return;

      final rawBytes = await picked.readAsBytes();
      if (!mounted) return;
      final cropped = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ImageCropDialog(imageBytes: rawBytes),
      );
      if (!mounted) return;
      if (cropped == null) {
        // User cancelled the cropper — keep everything cleared.
        setState(() {
          _imagePath = null;
          _croppedBytes = null;
          _analysisFrameBytes = const [];
          _analysisFrameExposureMetadata = const [];
          _capturedPoseTemplate = null;
          _capturedGuideType = null;
        });
        return;
      }

      final stored = await _persistCroppedImage(cropped);
      if (!mounted) return;
      setState(() {
        _croppedBytes = cropped;
        _analysisFrameBytes = <Uint8List>[cropped];
        _analysisFrameExposureMetadata = const [];
        _imagePath = stored;
        _explicitBaselineSelection = false;
        // A gallery photo has no known capture angle or camera guide type
        // -- must not be guessed from the focus-area/procedure selection.
        _capturedPoseTemplate = null;
        _capturedGuideType = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$errorLabel: $e')));
    }
  }

  /// Persists cropped bytes to a displayable reference: a data URI on web
  /// (consumed by `Image.network`) or a durable file path on native
  /// (consumed by `Image.file`).
  Future<String> _persistCroppedImage(Uint8List bytes) async {
    if (kIsWeb) {
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(
        '${docsDir.path}${Platform.pathSeparator}scans',
      );
      if (!await scansDir.exists()) {
        await scansDir.create(recursive: true);
      }

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final entropy = math.Random().nextInt(1 << 32);
      final filename = 'scan_${timestamp}_${entropy.toRadixString(16)}.jpg';
      final file = File('${scansDir.path}${Platform.pathSeparator}$filename');

      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on FileSystemException catch (e) {
      throw Exception(
        'Could not save scan photo to local storage. '
        'Please check app permissions and available disk space. '
        'Details: ${e.message}',
      );
    } catch (e) {
      throw Exception('Could not save scan photo: $e');
    }
  }

  void _useLatestAsBaseline() {
    final s = _latestScan;
    if (s == null || (s.imagePath ?? '').isEmpty) return;
    setState(() {
      _ghostReferenceScan = s;
      _explicitBaselineSelection = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Baseline reference updated from latest saved scan.'),
      ),
    );
  }

  ImageProvider<Object>? _ghostReferenceImageProvider() {
    if (!_ghostOverlayEnabled) return null;
    final referencePath = (_ghostReferenceScan?.imagePath ?? '').trim();
    final selectedPath = (_imagePath ?? '').trim();
    if (referencePath.isEmpty || referencePath == selectedPath) {
      return null;
    }
    return _imageProviderForPath(referencePath);
  }

  Widget _ghostSilhouetteLayer(ImageProvider<Object> provider) {
    return Opacity(
      opacity: _ghostOverlayOpacity,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: Image(image: provider, fit: BoxFit.cover),
      ),
    );
  }

  // ── Run analysis ──────────────────────────────────────────────────

  /// Validates required inputs (focus area) before kicking off analysis.
  /// Surfaces an inline error instead of silently doing nothing so the
  /// user understands why the button did not proceed.
  void _onRunPressed() {
    if (_region == null) {
      setState(() {
        _focusAreaError =
            'Please select a focus area before generating your progress report.';
      });
      return;
    }
    setState(() => _focusAreaError = null);
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    final path = _imagePath;
    if (path == null || path.isEmpty) return;
    setState(() {
      _stage = _Stage.analyzing;
      _analysisError = null;
    });

    try {
      PhotoFeatures features;
      Uint8List? imageBytes;
      try {
        // Prefer the in-memory cropped bytes; fall back to reading the path
        // (used by the "latest scan" source, which is already a capture).
        imageBytes = _croppedBytes ?? await XFile(path).readAsBytes();
        features = PhotoFeatureExtractor.extract(imageBytes);
      } catch (_) {
        features = PhotoFeatures.neutral();
      }

      var input = PhotoAnalysisInput.fromFeatures(
        imagePath: path,
        capturedAt: DateTime.now(),
        region: _region ?? FacialRegion.fullFace,
        features: features,
        cycleRelatedFlare: _cycleRelated,
        adultOnset: _adultOnset,
      );

      // ── Real AI inference (ML Kit Face Mesh + TFLite / TF.js) ──
      // FaceMesh crops to the face (Android/iOS only — passthrough on
      // web/desktop). TFLite then runs the ACNE04 classifier on the
      // cropped bytes. On any failure the rule engine still owns every
      // metric and the badge reflects which engines actually fired.
      final aug = await SkinAnalysisRunner.augment(
        baseInput: input,
        imageBytes: imageBytes,
      );
      input = aug.input;
      final ModelInfo modelInfo = aug.modelInfo;
      final double? modelConf = aug.modelConfidence;
      final Set<String> modelOwned = aug.modelOwnedMetrics;

      // Optional baseline from existing photo logs (for comparison block).
      AcneRosaceaLog? baseline;
      final Map<String, List<AcneRosaceaLog>> history =
          await AppPrefs.getAcneRosaceaLogs();
      final allWithPhotos =
          history.values
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
        history: history,
        confidence: SkinAnalysisRunner.resolveConfidence(
          featureConfidence: features.confidence,
          modelConfidence: modelConf,
        ),
        features: features,
      );

        final Map<String, double> previousMetrics = await _getPreviousMetrics();

      // Server-first execution: route this scan through the backend multipart
      // endpoint and parse canonical metrics + trend deltas from the payload.
      final backendBytes = imageBytes ?? await XFile(path).readAsBytes();
      final backendFields = buildAiSkinAnalysisBackendFields(
        procedureType: _selectedProcedureType,
        customDescription: _selectedProcedureCustomDescription,
        focusArea: _resolvedFocusArea(),
        currentCaptureQuality: _currentCaptureQuality,
        baselineCaptureQuality: _previousFocusAreaScan?.captureQuality,
        poseTemplate: _capturedPoseTemplate,
        baselinePoseTemplate: _previousFocusAreaScan?.poseTemplate,
        guideType: _capturedGuideType,
        baselineGuideType: _previousFocusAreaScan?.guideType,
      );

      final frames = _analysisFrameBytes.isNotEmpty
          ? _analysisFrameBytes
          : <Uint8List>[backendBytes];
      // Both the metric matrix AND its extraction-path provenance now come
      // from the SAME resolved baseline entry (_previousFocusAreaScan) --
      // no more device-global manual-matrix branch that could describe a
      // different scan than the one whose provenance fields were sent.
      final resolvedBaselineMatrix = _buildLuxeBaselineMetricMatrix();
      final baselineMetricMatrixForTrend =
          resolvedBaselineMatrix.isEmpty ? null : resolvedBaselineMatrix;
        final storedBaselineFormulaVersions = _previousFocusAreaScan == null
          ? const <String, int>{}
          : aiScanFormulaVersions(_previousFocusAreaScan!);
      final aggregate = await analyzeBackendFrames(
        frames,
        frameExposureMetadata: _analysisFrameExposureMetadata,
        uploadFrame: (frame, frameNumber) =>
            remote_analysis.SkinAnalysisService.uploadSingleImageFile(
              image: XFile.fromData(
                frame,
                name: 'skin_ai_analysis_frame_$frameNumber.jpg',
                mimeType: 'image/jpeg',
              ),
              fields: backendFields,
              baselineMetricMatrix: baselineMetricMatrixForTrend,
              baselineExtractionPaths: _buildLuxeBaselineExtractionPaths(),
                baselineFormulaVersions: storedBaselineFormulaVersions.isEmpty
                  ? null
                  : storedBaselineFormulaVersions,
              allowBackend: true,
            ),
      );
      final backendResponse = aggregate.response;
      debugPrint(
        '[MultiFrameAnalysis] ${aggregate.successfulFrames}/${aggregate.requestedFrames} '
        'frames succeeded; contributors=${aggregate.metricContributorCounts}',
      );
      final parsedBackend = _parseBackendAnalysisPayload(backendResponse);
      final Map<String, double> fullMetrics = parsedBackend.fullMetrics;
      // Client-side-only honesty gate: downgrades improved/worsened to
      // stable when this scan's and the baseline scan's own multi-frame
      // value ranges substantially overlap (see
      // downgradeTrendForOverlappingFrameRanges). Backend-reported
      // capture-quality/path/resolution/confidence gates are untouched --
      // this only ever pulls a claim back toward stable, never invents one.
      final currentMetricRanges = _dynamicMap(
        _dynamicMap(backendResponse['multi_frame_analysis'])['metric_ranges'],
      );
      final baselineMetricRanges = _dynamicMap(
        _dynamicMap(
          _previousFocusAreaScan?.rawPayload?['multi_frame_analysis'],
        )['metric_ranges'],
      );
      final overlapAdjustedTrend = downgradeTrendForOverlappingFrameRanges(
        trendStatus: parsedBackend.serverTrendStatus,
        trendDeltas: parsedBackend.serverTrendDeltas,
        trendLockReasons: parsedBackend.serverTrendLockReasons,
        currentMetricRanges: currentMetricRanges,
        baselineMetricRanges: baselineMetricRanges,
      );
      // Second client-side-only honesty gate, chained after the overlap
      // gate above: re-applies the backend's OWN measured noise-floor
      // policy (echoed back in the response, never duplicated as Dart
      // constants -- see downgradeTrendBelowMeasuredNoiseFloor's doc
      // comment) against the averaged metric_matrix value actually shown
      // on screen, since the backend's own noise-floor check ran per-frame
      // against a value that isn't the one displayed.
      final noiseFloorAdjustedTrend = downgradeTrendBelowMeasuredNoiseFloor(
        trendStatus: overlapAdjustedTrend.trendStatus,
        trendDeltas: overlapAdjustedTrend.trendDeltas,
        trendLockReasons: overlapAdjustedTrend.trendLockReasons,
        averagedMetricMatrix: _dynamicMap(backendResponse['metric_matrix']),
        baselineMetricMatrix: baselineMetricMatrixForTrend ?? const {},
        metricNoiseFloor2sd: _dynamicMap(
          backendResponse['metric_noise_floor_2sd'],
        ),
        trendNoiseFloorExceedsUsefulRange: _stringSetFromDynamic(
          backendResponse['trend_noise_floor_exceeds_useful_range'],
        ),
        trendNoiseFloorExcludedMultiplier: _parseFiniteDouble(
          backendResponse['trend_noise_floor_excluded_multiplier'],
        ),
      );
        final rednessAdjustedTrend = downgradeRednessTrendForCaptureMismatch(
        trendStatus: noiseFloorAdjustedTrend.trendStatus,
        trendDeltas: noiseFloorAdjustedTrend.trendDeltas,
        trendLockReasons: noiseFloorAdjustedTrend.trendLockReasons,
        currentPayload: backendResponse,
        baselinePayload:
          _previousFocusAreaScan?.rawPayload ?? const <String, dynamic>{},
        );
        final Map<String, double> serverTrendDeltas =
          rednessAdjustedTrend.trendDeltas;
        final Map<String, String> serverTrendStatus =
          rednessAdjustedTrend.trendStatus;
        final Map<String, String> serverTrendLockReasons =
          rednessAdjustedTrend.trendLockReasons;
      // Write the (possibly downgraded) trend fields back into
      // backendResponse -- both locations _mergePayloadForPersistence reads
      // from -- so what gets persisted to ScanHistoryEntry.rawPayload
      // matches what is displayed now, rather than the pre-downgrade
      // backend verdict.
      backendResponse['trend_status'] = serverTrendStatus;
      backendResponse['trend_deltas'] = serverTrendDeltas;
      backendResponse['trend_lock_reasons'] = serverTrendLockReasons;
        backendResponse[rednessTrendLockReasonsKey] =
          rednessAdjustedTrend.rednessLockReasons.toList(growable: false);
      final backendResponseMetricsNode = _asDynamicMap(
        backendResponse['metrics'],
      );
      if (backendResponseMetricsNode != null) {
        backendResponseMetricsNode['trend_status'] = serverTrendStatus;
        backendResponseMetricsNode['trend_deltas'] = serverTrendDeltas;
        backendResponseMetricsNode['trend_lock_reasons'] =
            serverTrendLockReasons;
        backendResponse['metrics'] = backendResponseMetricsNode;
      }
      final luxePayload = _buildLuxeResultsPayload(
        report,
        backendResponse: backendResponse,
      );
      final persistencePayload = _mergePayloadForPersistence(
        backendResponse: backendResponse,
        luxePayload: luxePayload,
      );
      // The baseline whose metrics/paths were actually sent with this
      // scan's frames -- none when no baseline matrix was sent.
      recordAiComparisonBaseline(
        persistencePayload,
        baselineScanId: baselineMetricMatrixForTrend == null
            ? null
            : _previousFocusAreaScan?.id,
        registryScanId: _aiBaselineRegistryScanId,
      );
      final Map<String, double> rawMetricScores =
          _rawMetricScoresForStorage(persistencePayload);
      final persistedMetricsNode =
          _asDynamicMap(persistencePayload['metrics']) ?? <String, dynamic>{};
      persistencePayload['metrics'] = {
        ...persistedMetricsNode,
      };

      // Capture the most recent PREVIOUS scan's metrics BEFORE we
      // persist the current one, so the results card can show trend
      // arrows (improved / worsened) against the prior analysis.
      final timelineMetrics = _withTrendDeltaMetrics(
        timelineMetricsFromBackend(fullMetrics),
        serverTrendDeltas: serverTrendDeltas,
      );

      // Persist the full analysis to the Skin Tracker (and, via the
      // shared scan store, the Recovery Timeline). Falls back to the
      // rule-engine detections when the TFLite models produced nothing.
      bool savedToHistory = false;
      ScanHistoryEntry? savedEntry;
      try {
        final resolvedProcedureId =
            (_selectedProcedureId?.trim().isNotEmpty == true)
            ? _selectedProcedureId!.trim()
            : (await AppPrefs.getSelectedProcedureIdOrNull())?.trim();
        savedEntry = await SkinHistoryRepository.instance.saveScan(
          metrics: rawMetricScores,
          imagePath: path,
          timestamp: input.capturedAt,
          procedureId: resolvedProcedureId,
          procedure: _selectedProcedureType ?? 'AI Skin Analysis',
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          poseTemplate: _capturedPoseTemplate,
          guideType: _capturedGuideType,
          captureQuality: _currentCaptureQuality,
          focusArea: _resolvedFocusArea(),
          customDescription: _selectedProcedureCustomDescription,
          estimatedSkinAge:
              estimateVisualSkinAgeFromAiMetrics(timelineMetrics) ?? 0,
          rawPayload: persistencePayload,
        );
        savedToHistory = true;
      } catch (e) {
        // Fallback: persist at least one AI scan entry with the image path,
        // even if metric_matrix is empty or repository sync fails.
        try {
          final fallbackEntry = ScanHistoryEntry(
            id: ScanHistoryEntry.generateId(input.capturedAt, path),
            timestamp: input.capturedAt,
            imagePath: path,
            procedureId: (_selectedProcedureId?.trim().isNotEmpty == true)
                ? _selectedProcedureId!.trim()
                : (await AppPrefs.getSelectedProcedureIdOrNull())?.trim(),
            scanType: ScanHistoryEntry.scanTypeAiAnalysis,
            procedure: _selectedProcedureType ?? 'AI Skin Analysis',
            poseTemplate: _capturedPoseTemplate,
            guideType: _capturedGuideType,
            captureQuality: _currentCaptureQuality,
            focusArea: _resolvedFocusArea(),
            customDescription: _selectedProcedureCustomDescription,
            estimatedSkinAge:
                estimateVisualSkinAgeFromAiMetrics(timelineMetrics) ?? 0,
            metrics: rawMetricScores,
            rawPayload: persistencePayload,
            scanEngine: ScanHistoryEntry.resolveScanEngine(
              persistencePayload,
              fallback: ScanHistoryEntry.engineBackendOpencv,
            ),
          );
          final existing = await AppPrefs.getScanEntries();
          final alreadyExists = existing.any((s) => s.id == fallbackEntry.id);
          if (!alreadyExists) {
            final history = await AppPrefs.addScanEntry(fallbackEntry);
            await AppPrefs.syncProcedurePhotoComparisonForEntry(
              fallbackEntry,
              history: history,
            );
          }
          savedToHistory = true;
          savedEntry = fallbackEntry;
        } catch (_) {
          // Non-fatal — the analysis still surfaces to the user.
        }
      }

      // Per the baseline product rule: when no valid baseline existed for
      // this key, the scan that was JUST saved becomes it -- but only if
      // it itself passes the single-scan honesty gates (a blurry/degraded
      // first scan does not become a permanent baseline). No-op if a
      // baseline already existed for this key.
      if (savedEntry != null) {
        await _registerAiBaselineIfNeeded(savedEntry);
      }

      if (!mounted) return;
      setState(() {
        _fullMetrics = fullMetrics;
        _previousMetrics = previousMetrics;
        _serverTrendDeltas = serverTrendDeltas;
        _serverTrendStatus = serverTrendStatus;
        _serverTrendLockReasons = serverTrendLockReasons;
        _latestBackendAnalysisPayload = backendResponse;
        _metricContributorCounts = aggregate.metricContributorCounts;
        _successfulAnalysisFrameCount = aggregate.successfulFrames;
        _requestedAnalysisFrameCount = aggregate.requestedFrames;
        _result = report;
        _modelInfo = modelInfo;
        _modelConfidence = modelConf;
        _modelOwnedMetrics = modelOwned;
        _meshUsed = aug.meshUsed;
        _symmetryScore = aug.symmetryScore;
        _faceCoverage = aug.faceCoverage;
        _yoloUsed = aug.yoloUsed;
        _detections = aug.detections;
        _efficientNetUsed = aug.efficientNetUsed;
        _qualityScores = aug.qualityScores;
        _stage = _Stage.results;
      });

      if (savedToHistory) {
        // Baseline registration (see _registerAiBaselineIfNeeded, called
        // right after saving above) already handles "first real scan
        // becomes the baseline" per the product rule's precedence -- no
        // separate auto-pin step needed here.
        final storageWarning = await AppPrefs.consumeScanStorageWarning();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: storageWarning == null
                ? MyApp.clinicalTeal
                : const Color(0xFFBF8A30),
            content: Text(
              storageWarning ?? 'Saved to Skin Tracker & Recovery Timeline',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.capture;
        _analysisError = 'Analysis failed: $e';
        _latestBackendAnalysisPayload = null;
      });
    }
  }

  /// Applies the backend's OWN trend_delta_*_pct values onto [current]'s
  /// metrics for storage. Displayed/persisted trend deltas come ONLY from
  /// the backend's trend_deltas -- this never recomputes a percentage from
  /// raw current/previous values client-side, so a client-computed number
  /// can never disagree with (or silently stand in for) what the backend
  /// actually verified against the honesty gates.
  Map<String, double> _withTrendDeltaMetrics(
    Map<String, double> current, {
    Map<String, double> serverTrendDeltas = const <String, double>{},
  }) {
    final enriched = <String, double>{...current};
    if (serverTrendDeltas.isEmpty) return enriched;

    const keyMap = <String, String>{
      'localized_redness': 'trend_delta_localized_redness_pct',
      'texture_smoothness': 'trend_delta_texture_smoothness_pct',
      'pore_visibility': 'trend_delta_pore_visibility_pct',
      'breakout_activity': 'trend_delta_breakout_activity_pct',
      'pigment_load': 'trend_delta_pigment_load_pct',
      'wrinkle_load': 'trend_delta_wrinkle_load_pct',
      'overall_healing': 'trend_delta_overall_healing_pct',
      'swelling': 'trend_delta_swelling_pct',
      'smoothness': 'trend_delta_smoothness_pct',
      'scarring_bruising': 'trend_delta_scarring_bruising_pct',
    };
    for (final entry in keyMap.entries) {
      final value = serverTrendDeltas[entry.key];
      if (value == null) continue;
      enriched[entry.value] = value;
    }

    return enriched;
  }

  Map<String, dynamic>? _asDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  bool _hasExplicitNullPoreInPayload(Map<String, dynamic> payload) {
    bool hasNullPore(Map<String, dynamic>? source) {
      if (source == null) return false;
      if (!source.containsKey('pore_visibility')) return false;
      return source['pore_visibility'] == null;
    }

    final metricsNode = _asDynamicMap(payload['metrics']);
    final matrixNode = _asDynamicMap(payload['metric_matrix']);
    final nestedMatrix = _asDynamicMap(metricsNode?['metric_matrix']);
    final luxeNode = _asDynamicMap(payload['luxePayload']);
    final luxeMetricsNode = _asDynamicMap(luxeNode?['metrics']);
    final luxeMatrixNode = _asDynamicMap(luxeNode?['metric_matrix']);

    return hasNullPore(payload) ||
        hasNullPore(metricsNode) ||
        hasNullPore(matrixNode) ||
        hasNullPore(nestedMatrix) ||
        hasNullPore(luxeNode) ||
        hasNullPore(luxeMetricsNode) ||
        hasNullPore(luxeMatrixNode);
  }

  bool _hasNumericPoreInPayload(Map<String, dynamic> payload) {
    bool hasNumericPore(Map<String, dynamic>? source) {
      if (source == null) return false;
      if (!source.containsKey('pore_visibility')) return false;
      final raw = source['pore_visibility'];
      final parsed = _safeToDouble(raw);
      return parsed != null && parsed.isFinite;
    }

    final metricsNode = _asDynamicMap(payload['metrics']);
    final matrixNode = _asDynamicMap(payload['metric_matrix']);
    final nestedMatrix = _asDynamicMap(metricsNode?['metric_matrix']);
    final luxeNode = _asDynamicMap(payload['luxePayload']);
    final luxeMetricsNode = _asDynamicMap(luxeNode?['metrics']);
    final luxeMatrixNode = _asDynamicMap(luxeNode?['metric_matrix']);

    return hasNumericPore(payload) ||
        hasNumericPore(metricsNode) ||
        hasNumericPore(matrixNode) ||
        hasNumericPore(nestedMatrix) ||
        hasNumericPore(luxeNode) ||
        hasNumericPore(luxeMetricsNode) ||
        hasNumericPore(luxeMatrixNode);
  }

  bool _shouldPersistPoreMetric(Map<String, dynamic> payload) {
    if (_hasExplicitNullPoreInPayload(payload)) return false;
    return _hasNumericPoreInPayload(payload);
  }

  Map<String, double> _rawMetricScoresForStorage(
    Map<String, dynamic> responseMap,
  ) {
    final rawScores = <String, double>{};
    final shouldPersistPore = _shouldPersistPoreMetric(responseMap);

    void collectNumerics(Map<String, dynamic> source) {
      source.forEach((k, v) {
        final key = k.toString();
        final lower = key.toLowerCase();
        if (lower.endsWith('_detected')) return;
        final parsed = _safeToDouble(v);
        if (parsed == null || parsed.isNaN || parsed.isInfinite) return;
        final clamped = parsed.clamp(0.0, 100.0).toDouble();
        if (clamped <= 0.0) return;
        rawScores[key] = clamped;
      });
    }

    final metricsNode = _asDynamicMap(responseMap['metrics']) ?? const {};
    final metricMatrixNode = _asDynamicMap(responseMap['metric_matrix']) ?? const {};
    final nestedMetricMatrixNode = _asDynamicMap(metricsNode['metric_matrix']) ?? const {};
    final luxeNode = _asDynamicMap(responseMap['luxePayload']) ?? const {};
    final luxeMetricMatrixNode = _asDynamicMap(luxeNode['metric_matrix']) ?? const {};

    collectNumerics(metricsNode);
    collectNumerics(metricMatrixNode);
    collectNumerics(nestedMetricMatrixNode);
    collectNumerics(luxeMetricMatrixNode);

    if (!shouldPersistPore) {
      rawScores.remove('pore_visibility');
    }

    return rawScores;
  }

  Map<String, dynamic> _mergePayloadForPersistence({
    required Map<String, dynamic> backendResponse,
    required Map<String, dynamic> luxePayload,
  }) {
    final shouldPersistPore = _shouldPersistPoreMetric(backendResponse);

    Map<String, dynamic> sanitizeUiMetricMap(Map<String, dynamic> source) {
      final out = <String, dynamic>{};
      for (final entry in source.entries) {
        final key = entry.key.toString();
        final lower = key.toLowerCase();
        if (lower.endsWith('_detected')) continue;

        final parsed = _safeToDouble(entry.value);
        if (parsed == null || parsed.isNaN || parsed.isInfinite) continue;
        final clamped = parsed.clamp(0.0, 100.0).toDouble();
        if (clamped <= 0.0) continue;
        out[key] = clamped;
      }
      return out;
    }

    final merged = <String, dynamic>{
      ...backendResponse,
      'luxePayload': luxePayload,
    };

    final backendMetrics = _asDynamicMap(backendResponse['metrics']) ?? const {};
    final luxeMetrics = _asDynamicMap(luxePayload['metrics']) ?? const {};
    const backendFirstCoreKeys = <String>{
      'localized_redness',
      'texture_smoothness',
      'pigment_load',
      'pore_visibility',
      'wrinkle_load',
      'breakout_activity',
    };

    final mergedMetrics = <String, dynamic>{
      ...backendMetrics,
      ...luxeMetrics,
    };
    for (final key in backendFirstCoreKeys) {
      if (backendMetrics.containsKey(key)) {
        // Preserve backend canonical value, including explicit nulls.
        mergedMetrics[key] = backendMetrics[key];
      }
    }
    merged['metrics'] = sanitizeUiMetricMap(mergedMetrics);

    final backendMatrix =
        _asDynamicMap(backendResponse['metric_matrix']) ?? const {};
    final luxeMatrix = _asDynamicMap(luxePayload['metric_matrix']) ?? const {};
    final mergedMatrix = <String, dynamic>{
      ...backendMatrix,
      ...luxeMatrix,
    };
    for (final key in backendFirstCoreKeys) {
      if (backendMatrix.containsKey(key)) {
        // Preserve backend canonical value, including explicit nulls.
        mergedMatrix[key] = backendMatrix[key];
      }
    }
    merged['metric_matrix'] = sanitizeUiMetricMap(mergedMatrix);

    final backendTrend =
        _asDynamicMap(backendResponse['trend_deltas']) ?? const {};
    final luxeTrend = _asDynamicMap(luxePayload['trend_deltas']) ?? const {};
    merged['trend_deltas'] = {
      ...backendTrend,
      ...luxeTrend,
    };

    Map<String, dynamic> normalizePathMap(dynamic source) {
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
        'skin_hydration',
      };
      final map = _asDynamicMap(source) ?? const <String, dynamic>{};
      final out = <String, dynamic>{
        for (final key in canonicalKeys) key: 'unknown',
      };
      for (final entry in map.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        if (!canonicalKeys.contains(key)) continue;
        out[key] = preservedAiExtractionPath(entry.value) ?? 'unknown';
      }
      return out;
    }

    final backendExtractionPaths = normalizePathMap(
      backendResponse['metric_extraction_paths'],
    );
    final luxeExtractionPaths = normalizePathMap(
      luxePayload['metric_extraction_paths'],
    );
    merged['metric_extraction_paths'] = {
      ...backendExtractionPaths,
      ...luxeExtractionPaths,
    };

    final backendBaselinePaths = normalizePathMap(
      backendResponse['baseline_metric_extraction_paths'],
    );
    final luxeBaselinePaths = normalizePathMap(
      luxePayload['baseline_metric_extraction_paths'],
    );
    merged['baseline_metric_extraction_paths'] = {
      ...backendBaselinePaths,
      ...luxeBaselinePaths,
    };

    if (!shouldPersistPore) {
      final mergedMetrics =
          _asDynamicMap(merged['metrics']) ?? <String, dynamic>{};
      mergedMetrics.remove('pore_visibility');
      merged['metrics'] = mergedMetrics;

      final mergedMatrix =
          _asDynamicMap(merged['metric_matrix']) ?? <String, dynamic>{};
      mergedMatrix.remove('pore_visibility');
      merged['metric_matrix'] = mergedMatrix;

      merged.remove('pore_visibility');
    }

    return merged;
  }

  ({
    Map<String, double> fullMetrics,
    Map<String, double> serverTrendDeltas,
    Map<String, String> serverTrendStatus,
    Map<String, String> serverTrendLockReasons,
  })
  _parseBackendAnalysisPayload(Map<String, dynamic> payload) {
    final metricsNode = _asDynamicMap(payload['metrics']) ?? payload;
    final metricMatrix =
        _asDynamicMap(payload['metric_matrix']) ??
        _asDynamicMap(metricsNode['metric_matrix']) ??
        const <String, dynamic>{};
    final trendNode =
        _asDynamicMap(payload['trend_deltas']) ??
        _asDynamicMap(metricsNode['trend_deltas']) ??
        const <String, dynamic>{};
    final trendStatusNode =
        _asDynamicMap(payload['trend_status']) ??
        _asDynamicMap(metricsNode['trend_status']) ??
        const <String, dynamic>{};
    final trendLockReasonsNode =
        _asDynamicMap(payload['trend_lock_reasons']) ??
        _asDynamicMap(metricsNode['trend_lock_reasons']) ??
        const <String, dynamic>{};

    double? number(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    final fullMetrics = <String, double>{};

    final rednessConcern = (() {
      final fromMatrix = number(metricMatrix['localized_redness']);
      if (fromMatrix != null) return (fromMatrix / 100).clamp(0.0, 1.0);
      return null;
    })();
    if (rednessConcern != null) {
      fullMetrics['redness'] = rednessConcern;
    }

    final textureConcern = (() {
      final smoothness = number(metricMatrix['texture_smoothness']);
      if (smoothness != null) {
        return ((100.0 - smoothness) / 100.0).clamp(0.0, 1.0);
      }
      return null;
    })();
    if (textureConcern != null) {
      fullMetrics['texture'] = textureConcern;
    }

    final poreConcern = number(metricMatrix['pore_visibility']);
    if (poreConcern != null) {
      fullMetrics['pore'] = (poreConcern / 100).clamp(0.0, 1.0);
    }

    final breakoutConcern = number(metricMatrix['breakout_activity']);
    if (breakoutConcern != null) {
      fullMetrics['acne_severity'] = (breakoutConcern / 100).clamp(0.0, 1.0);
    }

    final pigmentConcern = number(metricMatrix['pigment_load']);
    if (pigmentConcern != null) {
      fullMetrics['pigment'] = (pigmentConcern / 100).clamp(0.0, 1.0);
    }

    final wrinkleConcern = number(metricMatrix['wrinkle_load']);
    if (wrinkleConcern != null) {
      fullMetrics['wrinkle'] = (wrinkleConcern / 100).clamp(0.0, 1.0);
    }

    final mappedTrend = <String, double>{};
    for (final entry in trendNode.entries) {
      final parsed = number(entry.value);
      if (parsed == null) continue;
      mappedTrend[entry.key] = parsed;
    }

    final mappedTrendStatus = <String, String>{};
    for (final entry in trendStatusNode.entries) {
      final value = entry.value?.toString().trim();
      if (value == null || value.isEmpty) continue;
      mappedTrendStatus[entry.key] = value;
    }

    final mappedTrendLockReasons = <String, String>{};
    for (final entry in trendLockReasonsNode.entries) {
      final value = entry.value?.toString().trim();
      if (value == null || value.isEmpty) continue;
      mappedTrendLockReasons[entry.key] = value;
    }

    return (
      fullMetrics: fullMetrics,
      serverTrendDeltas: mappedTrend,
      serverTrendStatus: mappedTrendStatus,
      serverTrendLockReasons: mappedTrendLockReasons,
    );
  }

  Map<String, double> _bodyRecoveryScoresFor(Map<String, double> scores) {
    final pigment = (scores['pigment'] ?? 0).clamp(0, 10).toDouble();
    final redness = (scores['redness'] ?? 0).clamp(0, 10).toDouble();
    final texture = (scores['texture'] ?? 0).clamp(0, 10).toDouble();
    final wrinkle = (scores['wrinkle'] ?? 0).clamp(0, 10).toDouble();

    final swelling = (redness * 0.50 + texture * 0.30 + pigment * 0.20)
        .clamp(0, 10)
        .toDouble();
    final firmness = (10 - (texture * 0.45 + wrinkle * 0.20 + swelling * 0.15))
        .clamp(0, 10)
        .toDouble();
    final smoothness = (10 - texture).clamp(0, 10).toDouble();
    final scarringBruising = (pigment * 0.45 + redness * 0.35 + texture * 0.20)
        .clamp(0, 10)
        .toDouble();
    final fatRetention =
        (10 - (swelling * 0.30 + scarringBruising * 0.20 + texture * 0.15))
            .clamp(0, 10)
            .toDouble();
    final overallHealing =
        ((10 - swelling) * 0.22 +
                firmness * 0.18 +
                smoothness * 0.16 +
                (10 - scarringBruising) * 0.18 +
                (10 - pigment) * 0.12 +
                fatRetention * 0.14)
            .clamp(0, 10)
            .toDouble();

    return {
      'fatRetention': fatRetention,
      'fat_retention': fatRetention,
      'swelling': swelling,
      'edema': swelling,
      'firmness': firmness,
      'bodyFirmness': firmness,
      'skinLaxityFirmness': firmness,
      'smoothness': smoothness,
      'bodySmoothness': smoothness,
      'textureSmoothness': smoothness,
      'scarringBruising': scarringBruising,
      'scarring_bruising': scarringBruising,
      'bruising': scarringBruising,
      'hyperpigmentation': pigment,
      'overallHealingScore': overallHealing,
      'overall_healing_score': overallHealing,
      'bodyHealingScore': overallHealing,
    };
  }

  String _bodyMetricStorageKey(String label) {
    switch (label) {
      case 'Fat Retention':
        return 'fatRetention';
      case 'Swelling':
        return 'swelling';
      case 'Skin Laxity / Firmness':
        return 'firmness';
      case 'Texture / Smoothness':
        return 'smoothness';
      case 'Scarring / Bruising':
        return 'scarringBruising';
      case 'Hyperpigmentation':
        return 'hyperpigmentation';
      case 'Overall Healing Score':
        return 'overallHealingScore';
      default:
        return label;
    }
  }

  void _startOver() {
    setState(() {
      _stage = _Stage.capture;
      _imagePath = null;
      _croppedBytes = null;
      _analysisFrameBytes = const [];
      _analysisFrameExposureMetadata = const [];
      _result = null;
      _analysisError = null;
      _fullMetrics = const {};
      _previousMetrics = const {};
      _previousFocusAreaScan = null;
      _baselineFocusAreaScan = null;
      _priorFocusAreaScans = const [];
      _explicitBaselineSelection = false;
      _latestBackendAnalysisPayload = null;
      _metricContributorCounts = const {};
      _successfulAnalysisFrameCount = 0;
      _requestedAnalysisFrameCount = 0;
    });
    _refreshFocusAreaPhaseHint();
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0.5,
        iconTheme: IconThemeData(color: MyApp.clinicalNavy),
        title: Text(
          'Skin Scan',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: MyApp.clinicalNavy,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        actions: [
          if (kDebugMode)
            Builder(
              builder: (buttonContext) => PopupMenuButton<_DebugExportAction>(
                tooltip: 'Debug exports',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (action) async {
                  switch (action) {
                    case _DebugExportAction.burstLog:
                      await _exportBurstLuminanceLog(buttonContext);
                    case _DebugExportAction.scanData:
                      await _exportScanData(buttonContext);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _DebugExportAction.burstLog,
                    child: Row(
                      children: [
                        Icon(Icons.bug_report_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Export Burst Log'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _DebugExportAction.scanData,
                    child: Row(
                      children: [
                        Icon(Icons.table_view_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Export Scan Data'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_stage == _Stage.results)
            IconButton(
              tooltip: 'New progress report',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _startOver,
            ),
        ],
      ),
      body: SafeArea(
        child: switch (_stage) {
          _Stage.capture => _buildCaptureStage(),
          _Stage.analyzing => _buildAnalyzingStage(),
          _Stage.results => _buildResultsStage(),
        },
      ),
    );
  }

  // ── Stage 1: capture ──────────────────────────────────────────────

  Widget _buildCaptureStage() {
    // Run stays disabled until BOTH a photo is ready (camera/gallery photos
    // always pass through the mandatory crop step) AND the user has accepted
    // the pre-analysis disclaimer.
    final canRun = (_imagePath ?? '').isNotEmpty && _consentAccepted;
    final actionLabel = _capturePrimaryActionLabel();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _heroIntro(),
        const SizedBox(height: 18),
        if (_analysisError != null) ...[
          _errorBanner(_analysisError!),
          const SizedBox(height: 14),
        ],
        _captureSectionCard(
          title: '1. Select Baseline Reference',
          eyebrow: 'Clinical setup',
          icon: Icons.history_toggle_off_rounded,
          child: _ghostReferenceScan?.imagePath?.trim().isNotEmpty == true
              ? _ghostOverlayCard()
              : _baselineSetupEmptyCard(),
        ),
        const SizedBox(height: 14),
        _captureSectionCard(
          title: '2. Capture Current Follow-Up Photo',
          eyebrow: 'Current scan input',
          icon: Icons.photo_camera_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _photoPickerCard(),
              const SizedBox(height: 10),
              Text(
                'Fill more of the frame with your face — closer, even light.',
                style: TextStyle(
                  fontSize: 11.8,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: AppColors.refinedSlate.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _captureSectionCard(
          title: '3. Tracking Scope & Context',
          eyebrow: 'Progress tracking settings',
          icon: Icons.tune_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _regionCard(),
              if (_focusAreaError != null) ...[
                const SizedBox(height: 8),
                _focusAreaErrorNote(_focusAreaError!),
              ],
              const SizedBox(height: 10),
              _contextCard(),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _captureSectionCard(
          title: '4. Clinical Context & Consent',
          eyebrow: 'Required before report generation',
          icon: Icons.verified_user_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _consentGateCard(),
              const SizedBox(height: 12),
              _legalDisclaimerCard(),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _runButton(canRun, actionLabel),
        const SizedBox(height: 14),
        _disclaimerFootnote(),
      ],
    );
  }

  String _capturePrimaryActionLabel() {
    // Label should match tracking state, not onboarding flags.
    // First scan in this focus/procedure path establishes baseline.
    // Any later scan is a comparison/follow-up capture.
    final hasBaseline = _hasPriorFocusAreaScan || _explicitBaselineSelection;
    return hasBaseline ? 'Add Comparison Photo' : 'Save Baseline';
  }

  Widget _heroIntro() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.warmAlabaster.withValues(alpha: 0.6),
                    width: 0.8,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timeline_rounded,
                      size: 11,
                      color: AppColors.onChampagneGold,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'PROGRESS TRACKING',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        color: AppColors.onChampagneGold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Unified Clinical Skin Tracking',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AppColors.refinedSlate,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select a baseline reference, capture a current follow-up photo, '
            'and generate one consistent clinical-style progress report with '
            'trend deltas, directional status, and before/after comparison.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.refinedSlate.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFD06B6B).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD06B6B).withValues(alpha: 0.45),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFD06B6B),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFA84A4A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _captureSectionCard({
    required String title,
    required String eyebrow,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClinicalSectionHeader(icon: icon, title: title, eyebrow: eyebrow),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _baselineSetupEmptyCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.26),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.history_rounded,
            size: 17,
            color: AppColors.champagneGold,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _loadingLatest
                  ? 'Loading your latest saved scan for baseline reference...'
                  : 'No baseline reference selected yet. Use "Use Baseline" in the photo section to set your latest scan as the comparison baseline.',
              style: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.84),
                fontSize: 11.3,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPickerCard() {
    final hasPhoto = (_imagePath ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPhoto) _selectedPhotoPreview() else _photoPlaceholder(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _sourceTile(
                  icon: Icons.photo_camera_rounded,
                  label: 'Current Camera',
                  accent: AppColors.champagneGold,
                  filled: true,
                  onTap: _pickFromCamera,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _sourceTile(
                  icon: Icons.photo_library_rounded,
                  label: 'Current Gallery',
                  accent: MyApp.clinicalTeal,
                  onTap: _pickFromGallery,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _sourceTile(
                  icon: Icons.history_toggle_off_rounded,
                  label: 'Use Baseline',
                  accent: MyApp.clinicalNavy,
                  enabled: !_loadingLatest && _latestScan != null,
                  onTap: _useLatestAsBaseline,
                ),
              ),
            ],
          ),
          if (hasPhoto) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: MyApp.clinicalTeal,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Current follow-up photo selected — ready for progress report.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: MyApp.clinicalTeal,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _imagePath = null;
                    _croppedBytes = null;
                    _analysisFrameBytes = const [];
                    _analysisFrameExposureMetadata = const [];
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: MyApp.clinicalSlate,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 28),
                  ),
                  child: const Text(
                    'Remove',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
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

  Widget _selectedPhotoPreview() {
    final path = _imagePath!;
    final ghost = _ghostReferenceImageProvider();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            kIsWeb
                ? Image.network(path, fit: BoxFit.cover)
                : Image.file(File(path), fit: BoxFit.cover),
            if (ghost != null)
              IgnorePointer(child: _ghostSilhouetteLayer(ghost)),
            IgnorePointer(
              child: CustomPaint(
                painter: _ScanFramePainter(
                  color: AppColors.champagneGold.withValues(alpha: 0.85),
                  ringColor: AppColors.champagneGold.withValues(alpha: 0.10),
                ),
              ),
            ),
            if (ghost != null)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: const Text(
                    'Current follow-up',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    final ghost = _ghostReferenceImageProvider();
    if (ghost == null) return const _PulsingScanFrame();

    return Container(
      height: 178,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.42),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: AppColors.warmAlabaster),
            _ghostSilhouetteLayer(ghost),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.20),
                    AppColors.champagneGold.withValues(alpha: 0.10),
                  ],
                ),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _ScanFramePainter(
                  color: AppColors.champagneGold.withValues(alpha: 0.72),
                  ringColor: AppColors.champagneGold.withValues(alpha: 0.18),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.46),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Baseline silhouette ready',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Match eyes, nose, jaw, and distance',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.refinedSlate,
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

  Widget _ghostOverlayCard() {
    final reference = _ghostReferenceScan;
    final provider =
        _ghostReferenceImageProvider() ??
        _imageProviderForPath(reference?.imagePath);
    if (reference == null || provider == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ghost silhouette overlay',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: MyApp.clinicalNavy,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _ghostOverlayEnabled,
                onChanged: (value) => setState(() {
                  _ghostOverlayEnabled = value;
                }),
                activeThumbColor: AppColors.champagneGold,
              ),
            ],
          ),
          Text(
            'For follow-up and healing scans, reuse your most recent saved photo as a 20% silhouette guide so eye line, nose position, jaw width, and distance stay as repeatable as possible.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: MyApp.textBrown.withValues(alpha: 0.84),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: AppColors.refinedSlate.withValues(alpha: 0.05),
                      ),
                      _ghostSilhouetteLayer(provider),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _ScanFramePainter(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.65,
                            ),
                            ringColor: AppColors.champagneGold.withValues(
                              alpha: 0.10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Reference: ${reference.focusArea?.trim().isNotEmpty == true ? reference.focusArea!.trim() : 'previous saved scan'}\nTurn this on before a new capture to line up with your baseline image.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: MyApp.clinicalSlate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sourceTile({
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
    bool enabled = true,
    bool filled = false,
  }) {
    final bg = filled ? accent : accent.withValues(alpha: 0.07);
    final fg = filled ? AppColors.onChampagneGold : accent;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: filled
                    ? AppColors.goldHover.withValues(alpha: 0.70)
                    : accent.withValues(alpha: 0.35),
                width: filled ? 1 : 0.7,
              ),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: AppColors.champagneGold.withValues(alpha: 0.34),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Icon(icon, size: filled ? 22 : 20, color: fg),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: filled ? FontWeight.w900 : FontWeight.w800,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _regionCard() {
    const regions = FacialRegion.values;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in regions)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: _region == r
                    ? [
                        BoxShadow(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.45,
                          ),
                          blurRadius: 14,
                          spreadRadius: 0.5,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: ChoiceChip(
                label: Text(_regionLabel(r)),
                selected: _region == r,
                onSelected: (_) {
                  setState(() {
                    _region = r;
                    _focusAreaError = null;
                  });
                  _refreshFocusAreaPhaseHint();
                },
                selectedColor: AppColors.champagneGold,
                backgroundColor: AppColors.cardBackground,
                side: BorderSide(
                  color: _region == r
                      ? AppColors.champagneGold
                      : AppColors.borders,
                  width: _region == r ? 1.8 : 0.8,
                ),
                labelStyle: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: _region == r
                      ? AppColors.onChampagneGold
                      : AppColors.refinedSlate,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _contextCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: _cycleRelated,
            onChanged: (v) => setState(() => _cycleRelated = v),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: MyApp.clinicalTeal,
            title: const Text(
              'Cycle-related flare',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              'Breakouts that follow your menstrual cycle.',
              style: TextStyle(fontSize: 11, color: MyApp.clinicalSlate),
            ),
          ),
          Divider(
            height: 1,
            color: MyApp.clinicalSlate.withValues(alpha: 0.15),
          ),
          SwitchListTile.adaptive(
            value: _adultOnset,
            onChanged: (v) => setState(() => _adultOnset = v),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: MyApp.clinicalTeal,
            title: const Text(
              'Adult-onset acne',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              'Breakouts persisting past your mid-20s.',
              style: TextStyle(fontSize: 11, color: MyApp.clinicalSlate),
            ),
          ),
        ],
      ),
    );
  }

  Widget _runButton(bool enabled, String label) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.5,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.goldHover,
              AppColors.champagneGold,
              AppColors.goldHover,
            ],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.champagneGold.withValues(alpha: 0.55),
                    blurRadius: 28,
                    spreadRadius: 1,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? _onRunPressed : null,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.timeline_rounded,
                    size: 20,
                    color: AppColors.onChampagneGold,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: AppColors.onChampagneGold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _disclaimerFootnote() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 13,
          color: MyApp.clinicalSlate.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'AI-assisted observations — not a diagnosis and not a substitute '
            'for professional medical advice. Always consult a qualified '
            'healthcare professional for any concern, diagnosis, or treatment '
            'decision.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: MyApp.clinicalSlate,
            ),
          ),
        ),
      ],
    );
  }

  Widget _legalDisclaimerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.30),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.champagneGold.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.32),
              ),
            ),
            child: const Icon(
              Icons.health_and_safety_outlined,
              size: 16,
              color: AppColors.goldHover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wellness tracking disclaimer',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.refinedSlate,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'AestheticSkinTracker is a personal wellness and tracking tool. '
                  'It is not a medical device, is not intended for diagnosis or '
                  'medical advice, and is not HIPAA compliant. Consult a qualified '
                  'healthcare professional for any medical concerns.',
                  style: TextStyle(
                    fontSize: 11.2,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: AppColors.refinedSlate.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Non-dismissible pre-analysis consent. The user must explicitly accept
  /// before the "Run AI Analysis" button unlocks. Reinforces that this is
  /// not medical advice, not a diagnosis, and for personal tracking only.
  Future<void> _reviewConsent() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.health_and_safety_outlined,
                  color: AppColors.champagneGold,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Before you continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _consentBullet(
                  Icons.info_outline_rounded,
                  'This is not medical advice',
                  'This tool does not diagnose any condition and is not a '
                      'substitute for a licensed dermatologist or physician.',
                ),
                _consentBullet(
                  Icons.auto_awesome_outlined,
                  'Educational & personal tracking only',
                  'Results are estimates generated from a photo to help you '
                      'observe and track changes over time — not to make '
                      'treatment decisions.',
                ),
                _consentBullet(
                  Icons.warning_amber_rounded,
                  'Photos can be misread',
                  'Lighting, angle, makeup and image quality all affect the '
                      'output. Findings may be incomplete or inaccurate.',
                ),
                _consentBullet(
                  Icons.local_hospital_outlined,
                  'Seek professional care',
                  'For any concern, changing or painful lesion, or a '
                      'persistent symptom, please consult a qualified '
                      'healthcare professional.',
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: MyApp.clinicalSlate,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: MyApp.primaryGoldButton,
              child: const Text(
                'I Understand and Continue',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (accepted == true) setState(() => _consentAccepted = true);
  }

  Widget _consentBullet(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: MyApp.clinicalTeal),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: MyApp.clinicalNavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: MyApp.textBrown.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Capture-stage gate: surfaces the consent requirement inline and unlocks
  /// the Run button only after the disclaimer is read and accepted.
  Widget _consentGateCard() {
    final accepted = _consentAccepted;
    final accent = accepted ? AppColors.mutedSage : AppColors.champagneGold;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: accepted ? null : _reviewConsent,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 0.9,
            ),
          ),
          child: Row(
            children: [
              Icon(
                accepted ? Icons.verified_rounded : Icons.shield_outlined,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accepted
                          ? 'Disclaimer accepted'
                          : 'Review the progress-tracking disclaimer',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      accepted
                          ? 'You can generate your progress report below. Tap “View” to read it again.'
                          : 'Required before report generation. Tap to read and accept.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: MyApp.textBrown.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              if (accepted)
                TextButton(
                  onPressed: _reviewConsent,
                  child: Text(
                    'View',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  /// Prominent top-of-results disclaimer. One of three repeated disclaimers
  /// (top, near the metrics banner, and footer) framing every result as a
  /// non-diagnostic, educational estimate.
  Widget _resultsTopDisclaimer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.10),
            AppColors.mutedSage.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.health_and_safety_outlined,
            size: 18,
            color: AppColors.champagneGold,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: MyApp.textBrown.withValues(alpha: 0.9),
                ),
                children: const [
                  TextSpan(
                    text:
                        'These are AI-assisted observations, not a diagnosis. ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  TextSpan(
                    text:
                        'Results are estimates from a single photo and may be '
                        'inaccurate. They are for education and personal '
                        'tracking only — please consult a licensed '
                        'dermatologist for any medical concern.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _multiFrameConfidenceCard() {
    final entries = _metricContributorCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.photo_library_outlined,
                size: 17,
                color: AppColors.champagneGold,
              ),
              const SizedBox(width: 8),
              Text(
                'Multi-frame confidence: '
                '$_successfulAnalysisFrameCount/$_requestedAnalysisFrameCount frames',
                style: const TextStyle(
                  color: AppColors.refinedSlate,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in entries)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.mutedSage.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.mutedSage.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    '${entry.key.replaceAll('_', ' ')}: '
                    '${entry.value}/$_requestedAnalysisFrameCount',
                    style: const TextStyle(
                      color: AppColors.refinedSlate,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Stage 2: analyzing ────────────────────────────────────────────

  Widget _buildAnalyzingStage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _LuxeScanningIndicator(),
            const SizedBox(height: 30),
            const Text(
              'Building your progress report…',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                color: AppColors.refinedSlate,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Reading redness, texture, pore and tone metrics for a unified '
              'clinical-style progress dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.refinedSlate.withValues(alpha: 0.66),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.champagneGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.30),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: AppColors.goldHover,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'On-device AI · private & secure',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.refinedSlate.withValues(alpha: 0.80),
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

  // ── Stage 3: results ──────────────────────────────────────────────

  Widget _buildResultsStage() {
    final r = _result!;
    final isFollowUpPhase =
        _explicitLocalFollowUpFlag || _localHistoryCountForFocusArea >= 2;
    final gateReason = isFollowUpPhase
        ? (_explicitLocalFollowUpFlag
              ? 'explicit isFollowUp flag from local scan records'
              : 'localHistoryCount >= 2')
        : 'missing prior local baseline scan in history';
    debugPrint(
      'LUXE GATE: localHistoryCount=$_localHistoryCountForFocusArea isFollowUp=$isFollowUpPhase willRenderCards=$isFollowUpPhase reason=$gateReason',
    );
    final luxePayload = _buildLuxeResultsPayload(
      r,
      backendResponse: _latestBackendAnalysisPayload,
    );
    // Single source of truth for every results-stage widget below that
    // must be backend-only: the same cleaned metric_matrix LuxeReportLayout
    // itself renders (see _buildLuxeResultsPayload — sourced entirely from
    // backendResponse, never from the local AcneRosaceaPhotoAnalyzer
    // heuristic or the on-device TFLite model).
    final backendMetricMatrix =
        _asDynamicMap(luxePayload['metric_matrix']) ?? const <String, dynamic>{};
    final coachInsight = _coachInsightForPhase(
      metricMatrix: backendMetricMatrix,
      isFollowUp: isFollowUpPhase,
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _resultsTopDisclaimer(),
              const SizedBox(height: 14),
              _resultHeroCard(backendMetricMatrix),
              if (_experimentalScinCard() != null) ...[
                const SizedBox(height: 14),
                _experimentalScinCard()!,
              ],
              if (_requestedAnalysisFrameCount > 1) ...[
                const SizedBox(height: 14),
                _multiFrameConfidenceCard(),
              ],
              const SizedBox(height: 14),
              isFollowUpPhase
                  ? _followUpSummaryLine()
                  : _baselinePhaseSummaryCard(),
              const SizedBox(height: 18),
              ClinicalSectionHeader(
                icon: Icons.analytics_rounded,
                eyebrow: isFollowUpPhase ? 'PROGRESS METRICS' : 'STARTING METRICS',
                title: _isBodyProcedure
                    ? 'Body recovery report'
                    : _showCoreFaceMetricSetOnly
                    ? 'Core skin-quality report'
                    : 'Skin analysis report',
              ),
              const SizedBox(height: 10),
              LuxeReportLayout(
                rawPayload: luxePayload,
                baselineImageProvider: _resultsBaselineImageProvider(r),
                currentImageProvider: _imageProviderForPath(_imagePath),
                baselineLabel: 'Baseline',
                currentLabel: isFollowUpPhase ? 'Current Follow-Up' : 'Current Scan',
                localHistoryCount: _localHistoryCountForFocusArea,
                isFollowUp: isFollowUpPhase,
                gateReason: gateReason,
                baselineNotSavedReason: _baselineNotSavedReason,
                requireBackendVerdict: true,
              ),
              const SizedBox(height: 18),
              const ClinicalSectionHeader(
                icon: Icons.psychology_alt_rounded,
                eyebrow: 'AI COACH INSIGHT',
                title: 'What this scan suggests today',
              ),
              const SizedBox(height: 10),
              SmartNarrativeContainer(narrativeText: coachInsight),
              const SizedBox(height: 18),
              const ClinicalSectionHeader(
                icon: Icons.assessment_rounded,
                eyebrow: 'PHOTO OBSERVATIONS',
                title: 'What the current scan highlighted',
              ),
              const SizedBox(height: 8),
              _aiModelBanner(),
              const SizedBox(height: 18),
              const ClinicalSectionHeader(
                icon: Icons.spa_rounded,
                eyebrow: 'SAFETY & PRODUCTS',
                title: 'Recommended for your skin today',
              ),
              const SizedBox(height: 10),
              _buildRecommendationsSection(backendMetricMatrix),
              const SizedBox(height: 18),
              _scanPhaseCtaCard(isFollowUpPhase),
              const SizedBox(height: 14),
              _disclaimerFootnote(),
            ],
          ),
        ),
        if (!isFollowUpPhase) _firstScanActionDock(),
      ],
    );
  }

  Widget? _experimentalScinCard() {
    final payload = _latestBackendAnalysisPayload;
    if (payload == null) return null;
    final metrics = _asDynamicMap(payload['experimental_metrics']) ?? const {};
    if (metrics.isEmpty) return null;

    String formatProbability(dynamic value) {
      final numeric = value is num ? value.toDouble() : double.tryParse('$value');
      return numeric == null ? 'Unavailable' : '${(numeric * 100).toStringAsFixed(0)}%';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, size: 18, color: AppColors.champagneGold),
              const SizedBox(width: 8),
              Text(
                'EXPERIMENTAL MODEL OUTPUT',
                style: TextStyle(
                  color: MyApp.textBrown.withValues(alpha: 0.72),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Research-only SCIN classifiers. These probabilities are not canonical skin metrics and do not affect scoring or recommendations.',
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.72),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _experimentalScinRow(
            'Rough / flaky pattern',
            formatProbability(metrics['texture_ml_rough_flaky_experimental']),
          ),
          const SizedBox(height: 8),
          _experimentalScinRow(
            'Dermatitis-family pattern',
            formatProbability(metrics['dermatitis_pattern_ml_experimental']),
          ),
        ],
      ),
    );
  }

  Widget _experimentalScinRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  // Generic, non-diagnostic text only — this used to summarize
  // AcneRosaceaPhotoAnalyzer's (local heuristic) detectionSummary, which
  // could name conditions the backend never confirmed.
  Widget _followUpSummaryLine() {
    const safeText =
        'Follow-up scan captured. Progress metrics are now compared against your saved baseline.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.timeline_rounded,
            size: 16,
            color: AppColors.champagneGold,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              safeText,
              style: TextStyle(
                fontSize: 11.8,
                height: 1.45,
                color: MyApp.textBrown.withValues(alpha: 0.86),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _coachInsightForPhase({
    required Map<String, dynamic> metricMatrix,
    required bool isFollowUp,
  }) {
    final scores = _recommendationScoresFromMetricMatrix(metricMatrix);
    final topConcerns = _coachTopConcerns(scores);
    // No backend equivalent exists for the old local-heuristic "skin
    // sensitivity" proxy, so barrier-stress is now judged purely from the
    // real redness/rosacea formula metrics instead of adding an invented
    // backend proxy for a signal the backend doesn't measure.
    final barrierStressed =
        (scores['redness'] ?? 0) >= 4.0 ||
        (scores['rosacea_intensity'] ?? 0) >= 4.0;
    final sentences = <String>[];

    if (topConcerns.isEmpty) {
      sentences.add(
        isFollowUp
            ? 'This follow-up reads fairly steady against baseline, so the safest move is to keep the routine simple and consistent.'
            : 'Starting point shows a fairly calm overall pattern, so this scan is best used as your benchmark rather than a progress claim.',
      );
    } else {
      final leadPhrase = _joinWithCommasAndAnd(
        topConcerns
            .take(3)
            .map(
              (entry) =>
                  '${entry.label} at ${entry.value.toStringAsFixed(1)}/10',
            )
            .toList(),
      );
      sentences.add(
        isFollowUp
            ? 'This follow-up centers on $leadPhrase.'
            : 'Starting point shows $leadPhrase.',
      );
    }

    final concernValues = topConcerns.take(3).map((entry) => entry.value).toList();
    if (concernValues.isNotEmpty) {
      final highest = concernValues.reduce((a, b) => a > b ? a : b);
      if (highest >= 4.0) {
        sentences.add(
          barrierStressed
              ? 'That pattern usually means calm-first care should lead, because the barrier looks a little reactive and the skin will tolerate less when actives are stacked.'
              : 'That pattern usually means one or two focused steps will help more than a long routine, because the main signals are still doing the talking.',
        );
      } else {
        sentences.add(
          'The scan is showing a lighter concern pattern overall, so the goal is to keep the skin steady and avoid overcorrecting too early.',
        );
      }
    }

    if (isFollowUp) {
      final trendSentences = _coachTrendSentences(scores);
      if (trendSentences.isEmpty) {
        sentences.add(
          'Most of the measured pattern looks stable versus baseline, which is useful because it means the current routine is at least holding its ground.',
        );
      } else {
        sentences.addAll(trendSentences.take(2));
      }
    } else {
      sentences.add(
        barrierStressed
            ? 'Prioritize a gentle cleanse, a barrier moisturizer, and daily SPF first, then introduce only one calm active if the skin is already tolerating it.'
            : 'Prioritize a gentle cleanse, a barrier moisturizer, and daily SPF first, then choose only one targeted active based on whether redness, pigment, texture, or breakouts are the leading concern.',
      );
    }

    final rosaceaSignal = scores['rosacea_intensity'] ?? 0;
    final acneSignal = scores['acne_severity'] ?? 0;
    if (rosaceaSignal >= 4.0) {
      sentences.add(
        'Avoid fragrance, menthol, scrubs, and high-strength acids for now, because those are more likely to aggravate redness or stinging than to help this pattern.',
      );
    } else if (acneSignal >= 3.5) {
      sentences.add(
        'Breakout care should stay targeted rather than stacked, so keep any acne step spot-only or very limited until the barrier stays calm.',
      );
    } else {
      final pigmentSignal = scores['pigment'] ?? 0;
      final textureSignal = scores['texture'] ?? 0;
      final wrinkleSignal = scores['wrinkle'] ?? 0;
      final visibleTargets = <String>[
        if (pigmentSignal >= 3.5) 'tone support for pigment',
        if (textureSignal >= 3.5) 'texture support',
        if (wrinkleSignal >= 3.5) 'firmness and line support',
      ];
      if (visibleTargets.isNotEmpty) {
        sentences.add(
          'The routine should stay centered on ${_joinWithCommasAndAnd(visibleTargets)} rather than on multiple actives at once.',
        );
      }
    }

    return sentences.where((sentence) => sentence.trim().isNotEmpty).take(6).join(' ');
  }

  List<({String key, String label, double value})> _coachTopConcerns(
    Map<String, double> scores,
  ) {
    final concerns = <({String key, String label, double value})>[
      (
        key: 'redness',
        label: 'redness / flushing',
        value: scores['redness'] ?? 0,
      ),
      (
        key: 'rosacea_intensity',
        label: 'rosacea-pattern reactivity',
        value: scores['rosacea_intensity'] ?? 0,
      ),
      (
        key: 'acne_severity',
        label: 'breakout activity',
        value: scores['acne_severity'] ?? 0,
      ),
      (
        key: 'texture',
        label: 'texture roughness',
        value: scores['texture'] ?? 0,
      ),
      (
        key: 'pigment',
        label: 'uneven tone / marks',
        value: scores['pigment'] ?? 0,
      ),
      (
        key: 'wrinkle',
        label: 'fine lines / wrinkles',
        value: scores['wrinkle'] ?? 0,
      ),
    ]..sort((a, b) => b.value.compareTo(a.value));

    return concerns.where((entry) => entry.value >= 0.5).take(3).toList();
  }

  List<String> _coachTrendSentences(Map<String, double> scores) {
    final trendSpecs = <({String key, String label, bool lowerIsBetter})>[
      (key: 'redness', label: 'Redness', lowerIsBetter: true),
      (key: 'texture', label: 'Texture', lowerIsBetter: true),
      (key: 'pigment', label: 'Pigment', lowerIsBetter: true),
      (key: 'wrinkle', label: 'Wrinkles', lowerIsBetter: true),
      (key: 'acne_severity', label: 'Breakouts', lowerIsBetter: true),
      (key: 'rosacea_intensity', label: 'Rosacea reactivity', lowerIsBetter: true),
    ];

    final sentences = <String>[];
    for (final spec in trendSpecs) {
      final current = scores[spec.key];
      if (current == null) continue;
      final trend = _trendFor(
        spec.key,
        current,
        lowerIsBetter: spec.lowerIsBetter,
      );
      if (trend == null) continue;

      if (trend.label == 'Improved' || trend.label == 'Worsened') {
        final direction = trend.label == 'Improved' ? 'improved' : 'worsened';
        final percentDelta = trend.percentDelta;
        final qualifier = (percentDelta != null && percentDelta.abs() >= 5.0)
            ? 'meaningfully'
            : 'slightly';
        sentences.add('${spec.label} has $direction $qualifier versus baseline.');
      } else if (trend.label == 'Stable') {
        sentences.add('${spec.label} is stable versus baseline, so there is no need to chase a bigger change right now.');
      }
      // Any other backend verdict (a standalone-entry lock, or insufficient
      // signal) intentionally produces no sentence here rather than guessing.

      if (sentences.length >= 2) break;
    }

    return sentences;
  }

  String _joinWithCommasAndAnd(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items.first} and ${items.last}';
    return '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}';
  }

  Widget _scanPhaseCtaCard(bool isFollowUpPhase) {
    final text = isFollowUpPhase
        ? 'Scan again in similar lighting to update progress.'
        : 'Add another photo in similar lighting to unlock personalized progress tracking.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          const Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.champagneGold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.6,
                color: MyApp.textBrown.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _baselinePhaseSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 16,
                color: AppColors.champagneGold,
              ),
              const SizedBox(width: 8),
              Text(
                'Baseline scan captured',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: MyApp.clinicalNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This is your baseline. Add a second scan with similar lighting to unlock progress metrics.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: MyApp.textBrown.withValues(alpha: 0.84),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactBaselinePhotoHeader(PhotoAnalysisResult r) {
    final image = _imageProviderForPath(r.input.imagePath);
    const obsidian = Color(0xFF121212);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: obsidian, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 252, minHeight: 220),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                Image(image: image, fit: BoxFit.cover)
              else
                Container(
                  color: const Color(0xFF141821),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 34,
                    color: Colors.white.withValues(alpha: 0.32),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.16),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.52),
                      ],
                      stops: const [0.0, 0.50, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2225).withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.mutedSage.withValues(alpha: 0.70),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.mutedSage.withValues(alpha: 0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Baseline Scan Captured • Day 0',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactBaselineDiagnosticGrid(PhotoAnalysisResult r) {
    final metrics = _singleScanMetricMap();
    final redness = (metrics['redness'] ?? 0).clamp(0, 100).toDouble();
    final textureRaw = _fullMetrics.isNotEmpty
        ? ((_fullMetrics['texture'] ?? 0) * 100)
        : ((timelineMetricsFromBackend(_fullMetrics)['texture'] ?? 0) * 10);
    final texture = textureRaw.clamp(0, 100).toDouble();
    final severity = r.severityIndex.clamp(0, 10).toDouble();
    final diagnosis = r.severityBandLabel.trim().isEmpty
        ? 'Monitor'
        : r.severityBandLabel.trim();

    final cards = <({String label, String value, IconData icon})>[
      (
        label: 'Severity Score',
        value: severity.toStringAsFixed(1),
        icon: Icons.analytics_outlined,
      ),
      (
        label: 'Primary Diagnosis Tag',
        value: diagnosis,
        icon: Icons.label_important_outline_rounded,
      ),
      (
        label: 'Redness %',
        value: '${redness.toStringAsFixed(1)}%',
        icon: Icons.water_drop_outlined,
      ),
      (
        label: 'Texture Index',
        value: '${texture.toStringAsFixed(1)}%',
        icon: Icons.grain_rounded,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.05,
      ),
      itemBuilder: (context, index) {
        final card = cards[index];
        return Container(
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.champagneGold.withValues(alpha: 0.24),
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(card.icon, size: 13, color: AppColors.champagneGold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      card.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.2,
                        fontWeight: FontWeight.w800,
                        color: MyApp.clinicalSlate,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                card.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.2,
                  fontWeight: FontWeight.w900,
                  color: MyApp.clinicalNavy,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _firstScanActionDock() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          border: Border(
            top: BorderSide(
              color: AppColors.champagneGold.withValues(alpha: 0.28),
              width: 0.9,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _onSaveBaselineAndGoHome,
                icon: const Icon(Icons.verified_rounded, size: 17),
                label: const Text('Save baseline'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.mutedSage,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF7A8B7B), width: 1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _startOver,
                icon: const Icon(Icons.camera_alt_rounded, size: 17),
                label: const Text('Scan again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MyApp.clinicalNavy,
                  side: BorderSide(
                    color: AppColors.mutedSage.withValues(alpha: 0.45),
                    width: 1,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSaveBaselineAndGoHome() async {
    final ok = await _onSaveAsBaselinePressed(
      navigateHomeOnSuccess: true,
      quietSuccessSnackBar: true,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save baseline for this scan.'),
        ),
      );
    }
  }

  Widget _followUpActionsCard() {
    final baselineDate = _baselineFocusAreaScan?.timestamp;
    final baselineLabel = baselineDate == null
        ? 'Baseline linked for this focus area.'
        : 'Baseline linked: ${baselineDate.toLocal().year}-${baselineDate.toLocal().month.toString().padLeft(2, '0')}-${baselineDate.toLocal().day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _resultActionButtonRow(),
          const SizedBox(height: 10),
          Text(
            baselineLabel,
            style: TextStyle(
              fontSize: 11.2,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: MyApp.textBrown.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider<Object>? _resultsBaselineImageProvider(PhotoAnalysisResult r) {
    final currentPath = r.input.imagePath.trim();

    final baselinePath = (_baselineFocusAreaScan?.imagePath ?? '').trim();
    if (baselinePath.isNotEmpty && baselinePath != currentPath) {
      return _imageProviderForPath(baselinePath);
    }

    final previousPath = (_previousFocusAreaScan?.imagePath ?? '').trim();
    if (previousPath.isNotEmpty && previousPath != currentPath) {
      return _imageProviderForPath(previousPath);
    }

    final ghostPath = (_ghostReferenceScan?.imagePath ?? '').trim();
    if (ghostPath.isNotEmpty && ghostPath != currentPath) {
      return _imageProviderForPath(ghostPath);
    }

    final latestPath = (_latestScan?.imagePath ?? '').trim();
    if (latestPath.isNotEmpty && latestPath != currentPath) {
      return _imageProviderForPath(latestPath);
    }

    return null;
  }

  static const double _baselineUsableFloor = 0.5;
  static const double _baselineUsableCeiling = 99.5;

  bool _isUsableBaselineCandidate(double? value) {
    if (value == null || !value.isFinite) return false;
    return value > _baselineUsableFloor && value < _baselineUsableCeiling;
  }

  String? _baselineRejectReason(double? value) {
    if (value == null || !value.isFinite) return 'non_finite';
    if (value <= _baselineUsableFloor) return 'floor';
    if (value >= _baselineUsableCeiling) return 'ceiling';
    return null;
  }

  void _logBaselineReject({
    required String metricKey,
    required double value,
    required String reason,
    String? source,
  }) {
    final sourceSuffix = (source == null || source.isEmpty)
        ? ''
        : ' source=$source';
    debugPrint(
      'BASELINE REJECT [$metricKey] value=${value.toStringAsFixed(1)} reason=$reason$sourceSuffix',
    );
  }

  String? _normalizeConfidenceLabel(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final numeric = value.toDouble();
      if (!numeric.isFinite) return null;
      if (numeric >= 0.75) return 'high';
      if (numeric >= 0.50) return 'medium';
      return 'low';
    }
    final text = value.toString().trim().toLowerCase();
    if (text == 'high' || text == 'medium' || text == 'low') return text;
    return null;
  }

  int _confidenceRank(String? label) {
    switch ((label ?? '').toLowerCase()) {
      case 'high':
        return 3;
      case 'medium':
        return 2;
      case 'low':
        return 1;
      default:
        return 0;
    }
  }

  String? _confidenceForMetricFromScan(ScanHistoryEntry scan, List<String> keys) {
    final payload = scan.rawPayload ?? const <String, dynamic>{};
    final metrics = _asDynamicMap(payload['metrics']) ?? const <String, dynamic>{};
    final luxePayload =
        _asDynamicMap(payload['luxePayload']) ?? const <String, dynamic>{};
    final luxeMetrics =
        _asDynamicMap(luxePayload['metrics']) ?? const <String, dynamic>{};

    final confidenceMaps = <Map<String, dynamic>>[
      _asDynamicMap(payload['metric_confidence']) ?? const <String, dynamic>{},
      _asDynamicMap(metrics['metric_confidence']) ?? const <String, dynamic>{},
      _asDynamicMap(luxePayload['metric_confidence']) ?? const <String, dynamic>{},
      _asDynamicMap(luxeMetrics['metric_confidence']) ?? const <String, dynamic>{},
    ];

    for (final map in confidenceMaps) {
      if (map.isEmpty) continue;
      for (final key in keys) {
        final direct = _normalizeConfidenceLabel(map[key]);
        if (direct != null) return direct;
      }
    }

    return null;
  }

  ({double value, String sourceKey})? _firstUsableMetricFromMap(
    Map<String, dynamic> map,
    List<String> keys,
    String sourceLabel,
    String metricKey,
  ) {
    for (final key in keys) {
      final raw = map[key];
      final numeric = raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '');
      if (numeric == null || !numeric.isFinite) continue;
      if (_isUsableBaselineCandidate(numeric)) {
        return (
          value: numeric,
          sourceKey: '$sourceLabel.$key',
        );
      }
      final reason = _baselineRejectReason(numeric);
      if (reason != null) {
        _logBaselineReject(
          metricKey: metricKey,
          value: numeric,
          reason: reason,
          source: '$sourceLabel.$key',
        );
      }
    }
    return null;
  }

  ({
    double value,
    String sourceKey,
    String confidenceLabel,
    int confidenceRank,
  })? _firstUsableMetricFromScan(
    ScanHistoryEntry scan,
    String metricKey,
    List<String> orderedKeys,
  ) {
    final payload = scan.rawPayload ?? const <String, dynamic>{};
    final metrics = _asDynamicMap(payload['metrics']) ?? const <String, dynamic>{};
    final luxePayload =
        _asDynamicMap(payload['luxePayload']) ?? const <String, dynamic>{};
    final luxeMetrics =
        _asDynamicMap(luxePayload['metrics']) ?? const <String, dynamic>{};

    final sources = <({String label, Map<String, dynamic> map})>[
      (label: 'scan.metrics', map: Map<String, dynamic>.from(scan.metrics)),
      (
        label: 'rawPayload.metric_matrix',
        map: _asDynamicMap(payload['metric_matrix']) ?? const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.baseline_metric_matrix',
        map: _asDynamicMap(payload['baseline_metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.baseline',
        map: _asDynamicMap(payload['baseline']) ?? const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.opencv_metrics',
        map: _asDynamicMap(payload['opencv_metrics']) ?? const <String, dynamic>{},
      ),
      (label: 'rawPayload.metrics', map: metrics),
      (
        label: 'rawPayload.metrics.metric_matrix',
        map: _asDynamicMap(metrics['metric_matrix']) ?? const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.metrics.baseline_metric_matrix',
        map: _asDynamicMap(metrics['baseline_metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.metrics.baseline',
        map: _asDynamicMap(metrics['baseline']) ?? const <String, dynamic>{},
      ),
      (label: 'rawPayload.luxePayload', map: luxePayload),
      (
        label: 'rawPayload.luxePayload.metric_matrix',
        map: _asDynamicMap(luxePayload['metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.luxePayload.baseline_metric_matrix',
        map: _asDynamicMap(luxePayload['baseline_metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.luxePayload.baseline',
        map: _asDynamicMap(luxePayload['baseline']) ?? const <String, dynamic>{},
      ),
      (label: 'rawPayload.luxePayload.metrics', map: luxeMetrics),
      (
        label: 'rawPayload.luxePayload.metrics.metric_matrix',
        map: _asDynamicMap(luxeMetrics['metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.luxePayload.metrics.baseline_metric_matrix',
        map: _asDynamicMap(luxeMetrics['baseline_metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.luxePayload.metrics.baseline',
        map: _asDynamicMap(luxeMetrics['baseline']) ?? const <String, dynamic>{},
      ),
    ];

    for (final source in sources) {
      if (source.map.isEmpty) continue;
      final hit = _firstUsableMetricFromMap(
        source.map,
        orderedKeys,
        source.label,
        metricKey,
      );
      if (hit == null) continue;
      final confLabel = _confidenceForMetricFromScan(scan, orderedKeys) ?? 'unknown';
      return (
        value: hit.value,
        sourceKey: hit.sourceKey,
        confidenceLabel: confLabel,
        confidenceRank: _confidenceRank(confLabel),
      );
    }

    return null;
  }

  ({
    double value,
    String sourceKey,
    String priorScanId,
    int priorIndex,
    String confidenceLabel,
    int confidenceRank,
  })?
  _resolvePriorBaselineForMetric(
    String metricKey,
    List<String> aliases,
  ) {
    if (_priorFocusAreaScans.isEmpty) return null;
    final orderedKeys = <String>[metricKey, ...aliases];
    ({
      double value,
      String sourceKey,
      String priorScanId,
      int priorIndex,
      String confidenceLabel,
      int confidenceRank,
    })? best;

    for (var i = 0; i < _priorFocusAreaScans.length; i++) {
      final scan = _priorFocusAreaScans[i];
      final hit = _firstUsableMetricFromScan(scan, metricKey, orderedKeys);
      if (hit == null) continue;

      final candidate = (
        value: hit.value,
        sourceKey: hit.sourceKey,
        priorScanId: scan.id,
        priorIndex: i,
        confidenceLabel: hit.confidenceLabel,
        confidenceRank: hit.confidenceRank,
      );

      if (best == null) {
        best = candidate;
        continue;
      }

      final hasBetterConfidence =
          candidate.confidenceRank > best.confidenceRank;
      final sameConfidenceMoreRecent =
          candidate.confidenceRank == best.confidenceRank &&
          candidate.priorIndex < best.priorIndex;

      if (hasBetterConfidence || sameConfidenceMoreRecent) {
        best = candidate;
      }
    }

    return best;
  }

  Map<String, dynamic> _buildLuxeBaselineMetricMatrix() {
    final priorScan = _previousFocusAreaScan;
    final isFollowUp =
        _explicitLocalFollowUpFlag || _localHistoryCountForFocusArea >= 2;
    if (!isFollowUp || priorScan == null) return const <String, dynamic>{};

    // Backend-first baseline: only canonical keys from persisted history.
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
      'pore_contraction_index',
      'structural_firmness_elasticity',
      'rosacea_severity',
    };
    final canonicalBaseline = <String, dynamic>{};

    void mergeSource(dynamic source) {
      if (source is! Map) return;
      final map = Map<String, dynamic>.from(source);
      for (final entry in map.entries) {
        final value = entry.value;
        final numeric = value is num
            ? value.toDouble()
            : double.tryParse(value.toString());
        if (numeric == null || !numeric.isFinite || numeric <= 0.0) continue;
        final rawKey = entry.key.toString().trim().toLowerCase();
        // Baseline must come from canonical backend-style keys only.
        if (!canonicalKeys.contains(rawKey)) continue;
        canonicalBaseline[rawKey] = numeric;
      }
    }

    final rawPayload = priorScan.rawPayload ?? const <String, dynamic>{};
    final nestedMetrics = rawPayload['metrics'];
    final nestedLuxePayload = rawPayload['luxePayload'];

    mergeSource(rawPayload['metric_matrix']);
    mergeSource(rawPayload['baseline_metric_matrix']);
    mergeSource(rawPayload['baseline']);
    mergeSource(rawPayload['opencv_metrics']);
    mergeSource(nestedMetrics);
    if (nestedMetrics is Map) {
      mergeSource(nestedMetrics['metric_matrix']);
      mergeSource(nestedMetrics['baseline_metric_matrix']);
      mergeSource(nestedMetrics['baseline']);
      mergeSource(nestedMetrics['opencv_metrics']);
    }
    if (nestedLuxePayload is Map) {
      mergeSource(nestedLuxePayload);
      mergeSource(nestedLuxePayload['metric_matrix']);
      mergeSource(nestedLuxePayload['baseline_metric_matrix']);
      mergeSource(nestedLuxePayload['baseline']);
      final luxeMetrics = nestedLuxePayload['metrics'];
      mergeSource(luxeMetrics);
      if (luxeMetrics is Map) {
        mergeSource(luxeMetrics['metric_matrix']);
        mergeSource(luxeMetrics['baseline_metric_matrix']);
        mergeSource(luxeMetrics['baseline']);
        mergeSource(luxeMetrics['opencv_metrics']);
      }
    }
    mergeSource(priorScan.metrics);

    final metricAliasFallbacks = <String, List<String>>{
      // Keep empty alias lists to enforce canonical backend key-only baselines.
      'localized_redness': const <String>[],
      'texture_smoothness': const <String>[],
      'pigment_load': const <String>[],
      'wrinkle_load': const <String>[],
      'pore_visibility': const <String>[],
      'breakout_activity': const <String>[],
    };

    for (final entry in metricAliasFallbacks.entries) {
      final metricKey = entry.key;
      final aliases = entry.value;
      final existing = canonicalBaseline[metricKey];
      final existingNumeric = existing is num
          ? existing.toDouble()
          : double.tryParse(existing?.toString() ?? '');
      final hasUsableExisting = _isUsableBaselineCandidate(existingNumeric);
      if (!hasUsableExisting && existingNumeric != null && existingNumeric.isFinite) {
        final reason = _baselineRejectReason(existingNumeric);
        if (reason != null) {
          _logBaselineReject(
            metricKey: metricKey,
            value: existingNumeric,
            reason: reason,
            source: 'baseline_matrix.$metricKey',
          );
        }
      }
      if (hasUsableExisting) {
        final immediateScanId = _priorFocusAreaScans.isNotEmpty
            ? _priorFocusAreaScans.first.id
            : priorScan.id;
        debugPrint(
          'BASELINE PRIOR SELECT [$metricKey] priorScanId=$immediateScanId priorIndex=0 nonImmediate=false source=baseline_matrix.$metricKey value=${existingNumeric!.toStringAsFixed(2)}',
        );
        continue;
      }

      final resolved = _resolvePriorBaselineForMetric(metricKey, aliases);
      if (resolved == null) {
        debugPrint(
          'BASELINE PRIOR SELECT [$metricKey] priorScanId=none priorIndex=-1 nonImmediate=false source=none value=0.00',
        );
        continue;
      }

      canonicalBaseline[metricKey] = resolved.value;
      debugPrint(
        'BASELINE PRIOR SELECT [$metricKey] priorScanId=${resolved.priorScanId} priorIndex=${resolved.priorIndex} nonImmediate=${resolved.priorIndex > 0} confidence=${resolved.confidenceLabel} source=${resolved.sourceKey} value=${resolved.value.toStringAsFixed(2)}',
      );
    }

    return canonicalBaseline;
  }

  Map<String, String> _buildLuxeBaselineExtractionPaths() {
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
      'pore_contraction_index',
      'structural_firmness_elasticity',
      'rosacea_severity',
      'skin_hydration',
    };

    final out = <String, String>{
      for (final key in canonicalKeys) key: 'unknown',
    };

    final priorScan = _previousFocusAreaScan;
    final rawPayload = priorScan?.rawPayload;
    if (rawPayload == null || rawPayload.isEmpty) {
      return out;
    }

    void mergePathSource(dynamic source) {
      final map = _asDynamicMap(source);
      if (map == null || map.isEmpty) return;
      for (final entry in map.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        if (!canonicalKeys.contains(key)) continue;
        out[key] = preservedAiExtractionPath(entry.value) ?? 'unknown';
      }
    }

    mergePathSource(rawPayload['metric_extraction_paths']);
    final nestedMetrics = _asDynamicMap(rawPayload['metrics']);
    mergePathSource(nestedMetrics?['metric_extraction_paths']);
    final nestedLuxe = _asDynamicMap(rawPayload['luxePayload']);
    mergePathSource(nestedLuxe?['metric_extraction_paths']);
    final nestedLuxeMetrics = _asDynamicMap(nestedLuxe?['metrics']);
    mergePathSource(nestedLuxeMetrics?['metric_extraction_paths']);

    return out;
  }

  Map<String, dynamic> _buildLuxeResultsPayload(
    PhotoAnalysisResult r, {
    Map<String, dynamic>? backendResponse,
  }) {
    final isFollowUp =
        _explicitLocalFollowUpFlag || _localHistoryCountForFocusArea >= 2;

    final backendMetricsNode = _asDynamicMap(backendResponse?['metrics']) ??
        const <String, dynamic>{};
    final backendMetricMatrix =
        _asDynamicMap(backendResponse?['metric_matrix']) ??
        _asDynamicMap(backendMetricsNode['metric_matrix']) ??
        const <String, dynamic>{};

    final cleanedMetricMatrix = <String, dynamic>{};
    for (final entry in backendMetricMatrix.entries) {
      final parsed = _safeToDouble(entry.value);
      if (parsed == null || parsed.isNaN || parsed.isInfinite) continue;
      final clamped = parsed.clamp(0.0, 100.0).toDouble();
      if (clamped <= 0.0) continue;
      cleanedMetricMatrix[entry.key] = clamped;
    }

    final baselineMetricMatrix = _buildLuxeBaselineMetricMatrix();
    final baselineExtractionPaths = _buildLuxeBaselineExtractionPaths();
    final usedPriorScan = baselineMetricMatrix.isNotEmpty;
    final priorScanId = usedPriorScan ? _previousFocusAreaScan?.id : null;
    final baselineKeys = baselineMetricMatrix.keys.toList()..sort();
    debugPrint(
      'BASELINE SOURCE: localHistoryCount=$_localHistoryCountForFocusArea priorScanId=${priorScanId ?? 'none'} baselineKeys=$baselineKeys usedPriorScan=$usedPriorScan',
    );

    final trendDeltas = isFollowUp
      ? <String, dynamic>{..._serverTrendDeltas}
      : <String, dynamic>{};
    // trend_status/trend_lock_reasons must travel alongside trend_deltas --
    // LuxeReportLayout's _assessMetricHonesty only trusts the backend trend
    // for a metric when trend_deltas AND trend_status are both present.
    // Omitting these two (as this map previously did) silently forced every
    // card on the LIVE results screen into its own local recompute (flat 8%
    // / 2.0pt bands, no per-metric noise floor) even when the backend had
    // already computed an honest, gated verdict.
    final trendStatusForPayload = isFollowUp
      ? <String, dynamic>{..._serverTrendStatus}
      : <String, dynamic>{};
    final trendLockReasonsForPayload = isFollowUp
      ? <String, dynamic>{..._serverTrendLockReasons}
      : <String, dynamic>{};

    if (isFollowUp && trendDeltas.isEmpty && _previousMetrics.isNotEmpty) {
      // Legacy fallback deltas had no extraction-path provenance. Keep these
      // scans in tracking-only mode to avoid directional claims.
      debugPrint(
        'TREND DELTA FALLBACK: skipped directional fallback due to unknown extraction paths',
      );
    }

    return <String, dynamic>{
      'metric_matrix': cleanedMetricMatrix,
      'baseline_metric_matrix': baselineMetricMatrix,
      // NOTE: this whole map also gets persisted verbatim as the nested
      // rawPayload['luxePayload'] key (see _mergePayloadForPersistence),
      // where it becomes a point-in-time snapshot that is never refreshed.
      // metric_extraction_paths/baseline_metric_extraction_paths below are
      // fine for immediate live rendering, but progress_report_screen.dart's
      // _buildLuxePayloadForAiScan must keep preferring the top-level
      // rawPayload.metric_extraction_paths (which stays authoritative) over
      // this nested copy when reconstructing an archived scan's payload.
      'metric_extraction_paths': _asDynamicMap(
            backendResponse?['metric_extraction_paths'],
          ) ??
          const <String, dynamic>{},
      ...luxePrecisionMetadataFromBackend(backendResponse),
      'baseline_metric_extraction_paths': baselineExtractionPaths,
      'baseline': baselineMetricMatrix,
      'trend_deltas': trendDeltas,
      'trend_status': trendStatusForPayload,
      'trend_lock_reasons': trendLockReasonsForPayload,
      'metrics': cleanedMetricMatrix,
      'local_history_count': _localHistoryCountForFocusArea,
      'is_follow_up': isFollowUp,
    };
  }

  // ── 6-metric breakdown (SkinAnalysisService) ──────────────────────

  /// Beautiful breakdown of the six unified metrics produced by
  /// [SkinAnalysisService]. Model outputs arrive on a 0–1 scale and are
  /// surfaced here on the app-wide 0–10 clinical scale, grouped into
  /// General Skin Quality (teal accents) and Inflammatory Conditions
  /// (red/pink accents to signal attention), topped with an overall
  /// skin-health score. When a previous scan exists, each metric shows a
  /// trend indicator (improved / worsened / stable) versus that scan.
  Widget _fullMetricsCard({bool showTrends = true}) {
    // Convert a stored 0–1 model output to the clinical 0–10 scale.
    double to10(String key) =>
        ((_fullMetrics[key] ?? 0) * 10).clamp(0, 10).toDouble();

    final pigment = to10('pigment');
    final redness = to10('redness');
    final texture = to10('texture');
    final wrinkle = to10('wrinkle');
    final acne = to10('acne_severity');
    final rosacea = to10('rosacea_intensity');
    final double? pore = _qualityScores?.pores == null
        ? null
        : ((1 - _qualityScores!.pores!) * 10).clamp(0, 10).toDouble();

    if (_isBodyProcedure) {
      final source = {
        'pigment': pigment,
        'redness': redness,
        'texture': texture,
        'wrinkle': wrinkle,
        'acne_severity': acne,
        'rosacea_intensity': rosacea,
      };
      final bodyScores = _bodyRecoveryScoresFor(source);
      final metricSet = getMetricsForProcedure(_selectedProcedureType);
      final skin = SkinMetrics(
        redness: redness,
        texture: texture,
        wrinkle: wrinkle,
        darkSpots: pigment,
        elasticity: (10 - (texture * 0.5 + wrinkle * 0.5))
            .clamp(0, 10)
            .toDouble(),
      );
      final healingScore = bodyScores['overallHealingScore'] ?? 0;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _overallHealthHeader(
              healingScore,
              title: 'OVERALL HEALING SCORE',
              description:
                  'Composite of swelling, firmness, smoothness, bruising, pigment, and contour stability.',
            ),
            const SizedBox(height: 18),
            _metricGroup(
              icon: Icons.monitor_heart_rounded,
              title: 'Body Recovery Metrics',
              accent: MyApp.clinicalTeal,
              rows: [
                for (final metric in metricSet.additional)
                  _buildMetricRowWithTrend(
                    label: metric.label,
                    metricKey: _bodyMetricStorageKey(metric.label),
                    value: metric.valueFor(skin, rawMetrics: bodyScores),
                    lowerIsBetter: metric.lowerIsBetter,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _framingNote(
              'Body recovery scores are displayed on a 0-100 scale with direction shown per metric. '
              'Higher is better for fat retention, firmness, smoothness, and overall healing; '
              'lower is better for swelling, bruising, and hyperpigmentation. Educational only - not a diagnosis.',
            ),
          ],
        ),
      );
    }

    // The four quality metrics are "higher = more concern", so overall
    // skin health is the inverse of their average (higher = healthier).
    final avgConcern = (pigment + redness + texture + wrinkle) / 4;
    final healthScore = (10 - avgConcern).clamp(0, 10).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall skin-health gauge.
          _overallHealthHeader(healthScore),
          const SizedBox(height: 18),
          // Group 1 — general skin quality (teal accents).
          _metricGroup(
            icon: Icons.spa_rounded,
            title: 'General Skin Quality',
            accent: MyApp.clinicalTeal,
            rows: [
              _buildMetricRowWithTrend(
                label: 'Pigmentation',
                metricKey: 'pigment',
                value: pigment,
                showTrend: showTrends,
              ),
              _buildMetricRowWithTrend(
                label: 'Redness',
                metricKey: 'redness',
                value: redness,
                showTrend: showTrends,
              ),
              _buildMetricRowWithTrend(
                label: 'Texture',
                metricKey: 'texture',
                value: texture,
                showTrend: showTrends,
              ),
              _buildMetricRowWithTrend(
                label: 'Wrinkles',
                metricKey: 'wrinkle',
                value: wrinkle,
                showTrend: showTrends,
              ),
              if (pore != null)
                _buildMetricRowWithTrend(
                  label: 'Pores',
                  metricKey: 'pore',
                  value: pore,
                  showTrend: showTrends,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _framingNote(
            'Full-face view is focused on core skin-quality metrics '
            '(pigmentation, redness, texture, wrinkles, pores) for cleaner '
            'trend tracking. Educational only — not a diagnosis.',
          ),
        ],
      ),
    );
  }

  /// Prominent gradient header showing the overall skin-health score
  /// (0–100, higher = healthier) with a circular gauge.
  Widget _overallHealthHeader(
    double score, {
    String title = 'OVERALL SKIN HEALTH',
    String description = 'Averaged from the four general skin-quality metrics.',
  }) {
    final score100 = (score * 10).clamp(0.0, 100.0);
    final pct = (score100 / 100.0).clamp(0.0, 1.0);
    final label = score100 >= 80
        ? 'Excellent'
        : score100 >= 60
        ? 'Good'
        : score100 >= 40
        ? 'Fair'
        : 'Needs care';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MyApp.clinicalNavy.withValues(alpha: 0.94),
            MyApp.clinicalTeal.withValues(alpha: 0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Circular gauge with the score centered inside.
          SizedBox(
            width: 66,
            height: 66,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 66,
                  height: 66,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.20),
                    valueColor: AlwaysStoppedAnimation(MyApp.goldShimmer),
                  ),
                ),
                Text(
                  score100.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w900,
                    color: MyApp.goldShimmer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$label · ${score100.toStringAsFixed(1)} / 100',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Renders one accented metric group (a tinted, bordered container with
  /// an icon header) and lays out its [rows] with consistent spacing.
  Widget _metricGroup({
    required IconData icon,
    required String title,
    required Color accent,
    required List<Widget> rows,
    String? eyebrow,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[
                      Text(
                        eyebrow,
                        style: TextStyle(
                          fontSize: 8.5,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 1),
                    ],
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w900,
                        color: MyApp.clinicalNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            rows[i],
          ],
        ],
      ),
    );
  }

  /// A single 0–100 metric row with an optional trend indicator: label +
  /// trend chip, severity band, a 2-decimal value pill, and a
  /// colour-coded progress bar. Severity colours come from the shared
  /// [_valueColor] / [_severityBandForValue] helpers for consistency.
  Widget _buildMetricRowWithTrend({
    required String label,
    required String metricKey,
    required double value,
    bool lowerIsBetter = true,
    bool showTrend = true,
  }) {
    final color = _directedValueColor(value, lowerIsBetter: lowerIsBetter);
    final band = _directedSeverityBand(value, lowerIsBetter: lowerIsBetter);
    final trend = showTrend
        ? _trendFor(metricKey, value, lowerIsBetter: lowerIsBetter)
        : null;
    final value100 = (value * 10).clamp(0.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: MyApp.clinicalNavy,
                      ),
                    ),
                  ),
                  if (trend != null) ...[
                    const SizedBox(width: 7),
                    _trendChip(trend),
                  ],
                ],
              ),
            ),
            Text(
              band.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${value100.toStringAsFixed(1)} / 100',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (value100 / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  /// Compact trend pill: arrow icon + word (Improved / Worsened /
  /// Stable) plus the numeric delta for non-stable changes (e.g.
  /// "Improved +12%"). Green for improvement, coral for worsening, grey when
  /// stable.
  Widget _trendChip(
    ({
      IconData icon,
      Color color,
      String label,
      double? delta,
      double? percentDelta,
    })
    trend,
  ) {
    final showsPercent = trend.label == 'Improved' || trend.label == 'Worsened';
    final percentDelta = trend.percentDelta;
    final deltaText = (showsPercent && percentDelta != null)
        ? ' ${percentDelta > 0 ? '+' : ''}${percentDelta.toStringAsFixed(0)}%'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: trend.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: trend.color.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(trend.icon, size: 10, color: trend.color),
          const SizedBox(width: 3),
          Text(
            '${trend.label}$deltaText',
            style: TextStyle(
              fontSize: 8.5,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w900,
              color: trend.color,
            ),
          ),
        ],
      ),
    );
  }

  /// Resolves the trend for [metricKey] using ONLY the backend's own
  /// trend_status/trend_lock_reason for that metric (via [resolveTrendLabel])
  /// — never a locally recomputed threshold on raw deltas. Returns null when
  /// the backend supplied no verdict for this metric (e.g. no prior scan on
  /// record yet, or a metric this backend build doesn't trend), which
  /// callers must treat as "no trend chip", not as license to fall back to
  /// comparing two raw numbers themselves.
  ({
    IconData icon,
    Color color,
    String label,
    double? delta,
    double? percentDelta,
  })?
  _trendFor(String metricKey, double current, {bool lowerIsBetter = true}) {
    String? serverKeyForMetric(String key) {
      switch (key) {
        case 'redness':
          return 'localized_redness';
        case 'texture':
          return 'texture_smoothness';
        case 'pore':
          return 'pore_visibility';
        case 'acne_severity':
          return 'breakout_activity';
        case 'pigment':
          return 'pigment_load';
        case 'wrinkle':
          return 'wrinkle_load';
        case 'rosacea_intensity':
          return 'rosacea_severity';
      }
      return null;
    }

    final serverKey = serverKeyForMetric(metricKey);
    if (serverKey == null) return null;

    final resolved = resolveTrendLabel(
      trendStatus: _serverTrendStatus[serverKey],
      trendLockReason: _serverTrendLockReasons[serverKey],
      trendDeltaPct: _serverTrendDeltas[serverKey],
    );
    if (resolved == null) return null;

    final label = resolved.lockHeadline ?? resolved.label;
    switch (resolved.direction) {
      case TrendDirection.improved:
        return (
          icon: lowerIsBetter
              ? Icons.arrow_downward_rounded
              : Icons.arrow_upward_rounded,
          color: AppColors.mutedSage,
          label: label,
          delta: resolved.deltaPct,
          percentDelta: resolved.deltaPct,
        );
      case TrendDirection.worsened:
        return (
          icon: lowerIsBetter
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded,
          color: AppColors.softTerracotta,
          label: label,
          delta: resolved.deltaPct,
          percentDelta: resolved.deltaPct,
        );
      case TrendDirection.stable:
        return (
          icon: Icons.trending_flat_rounded,
          color: MyApp.clinicalSlate,
          label: label,
          delta: 0,
          percentDelta: resolved.deltaPct,
        );
      case TrendDirection.insufficientSignal:
        return (
          icon: Icons.trending_flat_rounded,
          color: MyApp.clinicalSlate,
          label: label,
          delta: null,
          percentDelta: null,
        );
    }
  }

  Color _directedValueColor(double value, {required bool lowerIsBetter}) {
    if (lowerIsBetter) return _valueColor(value.round());
    if (value >= 8) return const Color(0xFF4FAE8B);
    if (value >= 6) return const Color(0xFF7AA874);
    if (value >= 4) return const Color(0xFFB89A6E);
    return const Color(0xFFC76A55);
  }

  String _directedSeverityBand(double value, {required bool lowerIsBetter}) {
    if (lowerIsBetter) return _severityBandForValue(value.round());
    if (value >= 8) return 'Strong';
    if (value >= 6) return 'Good';
    if (value >= 4) return 'Fair';
    return 'Low';
  }

  /// Reads the six metrics from the baseline scan (oldest Day 0 scan),
  /// normalised to the 0–10 scale so they can be compared against the current
  /// scan. Returns an empty map when no prior scan exists. Must be called
  /// BEFORE the current scan is persisted.
  /// The focus area persisted with the current scan. Prefers the active
  /// procedure's configured focus area, falling back to the region the user
  /// selected in the analysis screen. Used for both saving and same-region
  /// retrieval so before/after comparisons stay accurate.
  String _resolvedFocusArea() =>
      (_selectedProcedureFocusArea ??
              (_region == null ? '' : PhotoAnalysisUi.regionLabel(_region!)))
          .trim();

  /// Canonical key for comparing focus-area strings. Normalises case and
  /// collapses any internal/edge whitespace so visually-identical values
  /// like "Full Face", "Full face" and "full  face" all match.
  String _normalizeFocus(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Registers [savedEntry] as the baseline for its own key IF no valid
  /// baseline existed for that key yet (see
  /// [AiBaselineResolution.isFirstForKey]) AND it itself passes the
  /// single-scan honesty gates -- a scan that fails those (e.g. degraded
  /// capture quality) is never stored as a baseline, even as the first
  /// attempt for a key. Never overwrites an EXISTING baseline; that only
  /// happens through explicit pinning ("Save as Baseline"/"Update
  /// baseline") or a reset.
  Future<void> _registerAiBaselineIfNeeded(ScanHistoryEntry savedEntry) async {
    if (!_aiBaselineResolution.isFirstForKey) return;
    final rejectionReason = aiBaselineRejectionReason(savedEntry);
    if (rejectionReason != null) {
      // Eligible to be the first baseline for this key, but this scan
      // itself failed a single-scan gate -- must not be saved as one, and
      // the results screen must say so instead of claiming success.
      if (!mounted) return;
      setState(() {
        _baselineNotSavedReason = rejectionReason;
      });
      return;
    }
    final key = _aiBaselineResolution.key ?? savedEntry.aiBaselineKey;
    await AppPrefs.setAiBaselineScanId(key, savedEntry.id);
    if (!mounted) return;
    setState(() {
      _currentScanBecameNewBaseline = true;
    });
  }

  /// Resolves this capture's baseline per the product rule: the first
  /// real, comparable scan for each (procedureId, focusArea, poseTemplate,
  /// guideType) key is that key's baseline.
  ///
  /// A valid pin stays fixed. A reset marker excludes pre-reset history until
  /// the first eligible post-reset scan replaces it. A broken pin blocks
  /// comparison. Only legacy keys with no registry state may choose their
  /// earliest eligible historical scan.
  ///
  /// Pairwise gates (resolution, extraction-path match, capture-quality
  /// match, formula-version match) are checked only at comparison time, by
  /// the backend's existing trend gates -- this never re-picks a different
  /// baseline because the resolved one fails a pairwise check against the
  /// current scan; that shows as "not comparable" via trend_lock_reason
  /// instead.
  ///
  /// Must be called BEFORE the current scan is persisted.
  Future<Map<String, double>> _getPreviousMetrics() async {
    try {
      _previousFocusAreaScan = null;
      _baselineFocusAreaScan = null;
      _priorFocusAreaScans = const [];
      _localHistoryCountForFocusArea = 1;
      _explicitLocalFollowUpFlag = false;
      _noComparableBaselineMessage = null;
      _ignoredBaselinePinMessage = null;
      _currentScanBecameNewBaseline = false;
      _baselineNotSavedReason = null;
      _aiBaselineRegistryScanId = null;

      final key = _currentAiBaselineKey();

      final scans = await SkinHistoryRepository.instance.getAllScans();
      // getAllScans() is newest-first; sort oldest-first so "earliest" is
      // simply ".first".
      final keyMatches = scans.where((scan) => scan.aiBaselineKey == key).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      bool readFollowUpFlagFromPayload(ScanHistoryEntry scan) {
        final payload = scan.rawPayload ?? const <String, dynamic>{};
        final raw =
            payload['is_follow_up'] ??
            payload['isFollowUp'] ??
            payload['follow_up'] ??
            payload['followUp'];
        if (raw is bool) return raw;
        if (raw is num) return raw != 0;
        final normalized = raw?.toString().trim().toLowerCase();
        return normalized == 'true' || normalized == '1' || normalized == 'yes';
      }

      _localHistoryCountForFocusArea = keyMatches.length + 1;
      _explicitLocalFollowUpFlag = keyMatches.any(readFollowUpFlagFromPayload);

      final registryState = await AppPrefs.getAiBaselineRegistryState(key);
      final pinnedId = registryState.baselineScanId;
      _aiBaselineRegistryScanId = pinnedId;
      final resolution = resolveAiBaseline(
        key: key,
        keyMatches: keyMatches,
        allScans: scans,
        pinnedScanId: pinnedId,
        registryEntryExists: registryState.hasEntry,
        resetAt: registryState.resetAt,
      );
      if (resolution.shouldPinResolvedBaseline &&
          resolution.baselineScan != null) {
        await AppPrefs.setAiBaselineScanId(key, resolution.baselineScan!.id);
        _aiBaselineRegistryScanId = resolution.baselineScan!.id;
      }
      _aiBaselineResolution = resolution;
      _priorFocusAreaScans = resolution.eligibleScansForKey;
      _ignoredBaselinePinMessage = resolution.ignoredPinReason;

      debugPrint(
        'AI BASELINE: key=$key keyMatches=${keyMatches.length} '
        'eligible=${resolution.eligibleScansForKey.length} '
        'resolved=${resolution.baselineScan?.id ?? 'none'} '
        'ignoredPin=${resolution.ignoredPinReason != null}',
      );

      final resolvedBaseline = resolution.baselineScan;
      if (resolvedBaseline == null) {
        // Only the "angle unknown" case is set here -- whether this scan
        // actually BECOMES the baseline isn't known until after it's saved
        // and passes its own single-scan gates (see
        // _registerAiBaselineIfNeeded / _currentScanBecameNewBaseline),
        // which is what the results UI actually shows as confirmation.
        _noComparableBaselineMessage = _capturedPoseTemplate == null
            ? 'This photo\'s angle is unknown, so it can\'t be compared '
                'with earlier scans.'
            : null;
        return const {};
      }

      _previousFocusAreaScan = resolvedBaseline;
      _baselineFocusAreaScan = resolvedBaseline;

      // Scans persisted by this service store 0–1 values; legacy /
      // fallback scans may already be 0–10. Normalise either way.
      double norm(double v) => (v <= 1.0 ? v * 10 : v).clamp(0, 10).toDouble();
      final raw = resolvedBaseline.metrics;
      return {for (final entry in raw.entries) entry.key: norm(entry.value)};
    } catch (_) {
      // Non-fatal — simply show no trend indicators.
    }
    _previousFocusAreaScan = null;
    _baselineFocusAreaScan = null;
    _priorFocusAreaScans = const [];
    _localHistoryCountForFocusArea = 1;
    _explicitLocalFollowUpFlag = false;
    return const {};
  }

  /// Backend-only, non-diagnostic hero card. Built exclusively from
  /// [metricMatrix] (the same cleaned backend metric_matrix
  /// LuxeReportLayout renders — see _buildLuxeResultsPayload) and honest
  /// capture-pipeline metadata (capture-quality tag, frame count). Does
  /// NOT read AcneRosaceaPhotoAnalyzer's report, the on-device TFLite
  /// model, or any local pixel heuristic, and never names a condition
  /// (acne/rosacea/telangiectasia) — see [buildBackendHeroCopy], the
  /// top-level pure function (testable without this screen's state) that
  /// actually derives the copy.
  Widget _resultHeroCard(Map<String, dynamic> metricMatrix) {
    final heroCopy = buildBackendHeroCopy(metricMatrix);
    final captureQualityLabel = captureQualityBadgeLabel(_currentCaptureQuality);
    final image = _imageProviderForPath(_imagePath);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 0.78,
            child: image == null
                ? Container(
                    color: const Color(0xFF141821),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 34,
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_fullMetrics.isNotEmpty)
                        SkinHeatmapOverlay.laser(
                          photo: image,
                          redness: _fullMetrics['redness'] ?? 0,
                          wrinkles: _fullMetrics['wrinkle'] ?? 0,
                          improvement: _fullMetrics['texture'] ?? 0,
                        )
                      else
                        Image(image: image, fit: BoxFit.cover),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.18),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.58),
                              ],
                              stops: const [0.0, 0.52, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            _heroBadge('Single Scan'),
                            const SizedBox(width: 8),
                            _heroBadge(captureQualityLabel),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              heroCopy.headline,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              heroCopy.subheadline,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 12.5,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          Container(
            color: const Color(0xFF151922),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Calibrated scan summary',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reset baseline benchmark',
                      onPressed: () => _showResetConfirmationDialog(context),
                      icon: Icon(
                        Icons.restart_alt_rounded,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                      splashRadius: 20,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (_firstBaselineConfirmationMessage != null) ...[
                  Text(
                    _firstBaselineConfirmationMessage!,
                    style: TextStyle(
                      color: AppColors.champagneGold.withValues(alpha: 0.9),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else if (_ignoredBaselinePinMessage != null) ...[
                  Text(
                    _ignoredBaselinePinMessage!,
                    style: TextStyle(
                      color: AppColors.champagneGold.withValues(alpha: 0.9),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else if (_noComparableBaselineMessage != null) ...[
                  Text(
                    _noComparableBaselineMessage!,
                    style: TextStyle(
                      color: AppColors.champagneGold.withValues(alpha: 0.9),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (kDebugMode) ...[
                  Text(
                    'Backend commit: ${_debugBackendCommit ?? 'unknown'}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 9.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _miniStat('Metrics', metricMatrix.length.toString()),
                    const SizedBox(width: 10),
                    _miniStat(
                      'Frames',
                      '$_successfulAnalysisFrameCount/$_requestedAnalysisFrameCount',
                    ),
                    const SizedBox(width: 10),
                    _miniStat(
                      'Mode',
                      _showCoreFaceMetricSetOnly ? 'Core face' : 'Full scan',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultActionButtonRow() {
    final hasComparison = _hasBeforeAfterComparisonAvailable();
    final addComparisonLabel = hasComparison
        ? 'Add Another Comparison Photo'
        : 'Add Comparison Photo';
    final baselineMetricMatrix = _buildLuxeBaselineMetricMatrix();
    final hasBaseline = baselineMetricMatrix.isNotEmpty;
    final baselineSourceDate = _previousFocusAreaScan?.timestamp.toLocal();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasBaseline) ...[
          OutlinedButton.icon(
            onPressed: _confirmUpdateBaselinePressed,
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text(
              'Update baseline',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.15,
              ),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: Colors.white,
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.34),
                width: 1.0,
              ),
              backgroundColor: Colors.white.withValues(alpha: 0.03),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (baselineSourceDate != null) ...[
            const SizedBox(height: 6),
            Text(
              'Baseline set • ${baselineSourceDate.toIso8601String().split('T').first}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ] else ...[
          if (_noComparableBaselineMessage != null) ...[
            Text(
              _noComparableBaselineMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
          ],
          _luxeActionButton(
            icon: Icons.verified_rounded,
            label: 'Save as Baseline',
            onPressed: _onSaveAsBaselinePressed,
          ),
        ],
        const SizedBox(height: 10),
        _luxeActionButton(
          icon: Icons.compare_arrows_rounded,
          label: 'Compare Before & After',
          onPressed: hasComparison
              ? _openBeforeAfterSplitView
              : _showComparisonUnavailableToast,
        ),
        const SizedBox(height: 10),
        _luxeActionButton(
          icon: Icons.add_a_photo_outlined,
          label: addComparisonLabel,
          onPressed: _openComparisonCapture,
        ),
        const SizedBox(height: 10),
        _luxeActionButton(
          icon: Icons.psychology_alt_rounded,
          label: 'AI Recovery Coach',
          onPressed: _openAiRecoveryCoach,
        ),
        const SizedBox(height: 10),
        _luxeActionButton(
          icon: Icons.home_rounded,
          label: 'Home',
          onPressed: _goHome,
        ),
      ],
    );
  }

  Widget _luxeActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    const goldButton = Color(0xFF7A8B7B);
    const obsidian = Colors.white;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.15,
          ),
        ),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          foregroundColor: obsidian,
          side: BorderSide(
            color: goldButton.withValues(alpha: 0.28),
            width: 0.9,
          ),
          backgroundColor: goldButton,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Future<String?> _resolveCurrentScanIdForActions() async {
    final report = _result;
    if (report == null) return null;

    final selectedProcedureId = (_selectedProcedureId ?? '').trim();
    final currentPath = report.input.imagePath.trim();
    final scans = await AppPrefs.getScanEntries();

    final candidates = scans.where((scan) {
      if ((scan.imagePath ?? '').trim() != currentPath) return false;
      if (selectedProcedureId.isNotEmpty &&
          (scan.procedureId ?? '').trim() != selectedProcedureId) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (candidates.isNotEmpty) return candidates.first.id;
    return null;
  }

  /// Pins the current scan as the baseline for ITS OWN key (procedureId,
  /// focusArea, poseTemplate, guideType) -- following the same precedence
  /// as automatic registration: a pin is only ever accepted for a scan
  /// that has a known angle and region and passes the single-scan honesty
  /// gates (see scanPassesSingleScanBaselineGates). Never falls back to a
  /// synthetic "ai_focus_..." procedure bucket the way the old
  /// procedureId-only pinning did -- the new registry key already allows a
  /// null procedureId (matching only other null procedureIds), so there's
  /// nothing to work around.
  Future<bool> _onSaveAsBaselinePressed({
    bool navigateHomeOnSuccess = false,
    bool quietSuccessSnackBar = false,
  }) async {
    final currentScanId = await _resolveCurrentScanIdForActions();
    if (!mounted) return false;

    if (currentScanId == null || currentScanId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current scan is not saved yet. Save it first.'),
        ),
      );
      return false;
    }

    final scans = await AppPrefs.getScanEntries();
    ScanHistoryEntry? target;
    for (final scan in scans) {
      if (scan.id == currentScanId) {
        target = scan;
        break;
      }
    }

    bool ok = false;
    String? failureReason;
    if (target == null) {
      failureReason = 'Current scan could not be found.';
    } else {
      // Same aiBaselineRejectionReason used by automatic registration, so
      // the button's snackbar and the results screen never disagree about
      // which check failed.
      failureReason = aiBaselineRejectionReason(target);
      if (failureReason == null) {
        await AppPrefs.setAiBaselineScanId(target.aiBaselineKey, target.id);
        ok = true;
      }
    }

    if (!mounted) return false;

    if (ok && navigateHomeOnSuccess) {
      _goHome();
      return true;
    }

    if (!(ok && quietSuccessSnackBar)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? MyApp.clinicalTeal : AppColors.mutedSage,
          content: Text(
            ok
                ? 'Baseline updated successfully.'
                : (failureReason ?? 'Unable to set baseline for this scan.'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    return ok;
  }

  Future<void> _confirmUpdateBaselinePressed() async {
    final shouldUpdate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Update baseline?'),
          content: const Text(
            'This will overwrite the current baseline with the current scan for progress tracking.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Update baseline'),
            ),
          ],
        );
      },
    );

    if (shouldUpdate == true) {
      await _onSaveAsBaselinePressed();
    }
  }

  void _openBeforeAfterSplitView() {
    final report = _result;
    if (report == null) return;

    final baselineProvider = _resultsBaselineImageProvider(report);
    final currentProvider = _imageProviderForPath(report.input.imagePath);

    if (baselineProvider == null || currentProvider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Need both baseline and current scan images to compare.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SkinAiSplitComparisonScreen(
          baselineImage: baselineProvider,
          currentImage: currentProvider,
        ),
      ),
    );
  }

  bool _hasBeforeAfterComparisonAvailable() {
    final report = _result;
    if (report == null) return false;

    final baselineProvider = _resultsBaselineImageProvider(report);
    final currentPath = report.input.imagePath.trim();
    if (baselineProvider == null || currentPath.isEmpty) return false;

    final candidatePaths = <String>[
      (_baselineFocusAreaScan?.imagePath ?? '').trim(),
      (_previousFocusAreaScan?.imagePath ?? '').trim(),
      (_ghostReferenceScan?.imagePath ?? '').trim(),
      (_latestScan?.imagePath ?? '').trim(),
    ];

    return candidatePaths.any(
      (path) => path.isNotEmpty && path != currentPath,
    );
  }

  void _showComparisonUnavailableToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Add a second photo first, then Compare Before & After will open.',
        ),
      ),
    );
  }

  void _openComparisonCapture() {
    _startOver();
  }

  void _openAiRecoveryCoach() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AIRecoveryCoachScreen()),
    );
  }

  void _goHome() {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);

    // In some web/navigation stacks this screen can be the first route,
    // so popUntil will not leave the page. Ensure Home always lands on
    // the app home route.
    if (!mounted) return;
    final routeName = ModalRoute.of(context)?.settings.name ?? '';
    if (routeName != '/home') {
      navigator.pushNamedAndRemoveUntil('/home', (_) => false);
    }
  }

  Map<String, double> _singleScanMetricMap() {
    if (_fullMetrics.isNotEmpty) {
      final redness = (_fullMetrics['redness'] ?? 0) * 100;
      final wrinkles = (_fullMetrics['wrinkle'] ?? 0) * 100;
      final darkSpots = (_fullMetrics['pigment'] ?? 0) * 100;

      return <String, double>{
        'redness': redness.clamp(0, 100).toDouble(),
        'wrinkles': wrinkles.clamp(0, 100).toDouble(),
        'darkSpots': darkSpots.clamp(0, 100).toDouble(),
      };
    }

    // Backend / rule-analysis path: use the already-normalized timeline metric
    // projection (0..10) and map to the UI's 0..100 scale.
    final result = _result;
    if (result != null) {
      final timeline = timelineMetricsFromBackend(_fullMetrics);
      final redness = (timeline['redness'] ?? 0) * 10;
      final wrinkles = (timeline['wrinkle'] ?? 0) * 10;
      final darkSpots = (timeline['pigment'] ?? 0) * 10;

      return <String, double>{
        'redness': redness.clamp(0, 100).toDouble(),
        'wrinkles': wrinkles.clamp(0, 100).toDouble(),
        'darkSpots': darkSpots.clamp(0, 100).toDouble(),
      };
    }

    return <String, double>{'redness': 0, 'wrinkles': 0, 'darkSpots': 0};
  }

  Widget _severityChip(String label, double index) {
    final color = _severityColor(index);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.6),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.9,
          color: color,
        ),
      ),
    );
  }

  /// Honest-disclosure banner shown above the metrics. When a real AI
  /// model is loaded it surfaces the model name, dataset, and reported
  /// accuracy alongside a "research-grade, not diagnostic" caveat. When
  /// only the rule engine is active it explicitly says so.
  Widget _aiModelBanner() {
    final info = _modelInfo;
    final isAi = !info.isFallback;
    final meshUsed = _meshUsed;
    final yoloUsed = _yoloUsed;
    final effUsed = _efficientNetUsed;
    final anyEngine = isAi || meshUsed;
    final color = anyEngine ? MyApp.clinicalTeal : MyApp.clinicalSlate;
    final icon = anyEngine
        ? Icons.psychology_alt_rounded
        : Icons.calculate_rounded;
    final stack = <String>[
      if (meshUsed) 'ML Kit Face Mesh',
      if (yoloUsed) 'YOLOv8-Nano Lesion Detector',
      if (effUsed) 'EfficientNet-B0 Skin Quality',
      if (isAi && !yoloUsed && !effUsed) 'TensorFlow Lite',
    ];
    final headline = stack.isEmpty
        ? 'Analysis completed successfully'
        : 'Powered by ${stack.join(" + ")}';
    final confLine = (_modelConfidence != null)
        ? '  ·  Model confidence: ${(_modelConfidence! * 100).round()}%'
        : '';
    // "Full-frame face coverage" here is bounding-box-area / full-image-area
    // -- a different denominator than the live capture guide's percentage
    // (which divides by a fixed 68%x84% guide box, not the full frame), so
    // the two are NOT directly comparable. Label explicitly to avoid a
    // normal or even slightly-too-close capture reading as alarmingly
    // low just because this number uses a larger denominator.
    final meshLine = meshUsed
        ? '\nFace Mesh: '
              '${_faceCoverage != null ? "full-frame face coverage: ${(_faceCoverage! * 100).round()}%" : "face cropped"}'
              '${_symmetryScore != null ? " · L/R symmetry ${(_symmetryScore! * 100).round()}%" : ""}'
        : '';
    final detLine = yoloUsed
        ? '\nYOLO: ${_detections.length} lesion${_detections.length == 1 ? "" : "s"} detected'
              '${_lesionBreakdown()}'
        : '';
    final qLine = (effUsed && _qualityScores != null)
        ? '\nEfficientNet: ${_qualitySummary(_qualityScores!)}'
        : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: color,
                  ),
                ),
              ),
              if (isAi)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'AI',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isAi
                ? 'Dataset: ${info.dataset}\n'
                      'Accuracy: ${info.reportedAccuracy}\n'
                      'Backend: ${info.backend}$confLine$meshLine$detLine$qLine\n'
                      'Research-grade benchmark — NOT a diagnostic tool. Drives '
                      'only the active-acne score; rosacea, vessels, flushing, '
                      'sensitivity and scarring use evidence-informed heuristics.'
                : 'Your analysis has been generated successfully using the '
                      'configured backend pipeline.$meshLine$detLine$qLine',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.45,
              color: MyApp.textBrown.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AI-assisted analysis — not a substitute for professional '
            'medical advice. Consult a board-certified dermatologist for '
            'diagnosis and treatment.',
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: MyApp.clinicalSlate,
            ),
          ),
        ],
      ),
    );
  }

  String _lesionBreakdown() {
    if (_detections.isEmpty) return '';
    final counts = <String, int>{};
    for (final d in _detections) {
      counts[d.label] = (counts[d.label] ?? 0) + 1;
    }
    final parts = counts.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.value} ${e.key}${e.value == 1 ? "" : "s"}')
        .toList();
    return parts.isEmpty ? '' : ' (${parts.join(", ")})';
  }

  String _qualitySummary(SkinQualityScores q) {
    int pct(double? v) => ((v ?? 0) * 100).round();
    final parts = <String>[
      if (q.overall != null) 'overall ${pct(q.overall)}%',
      if (q.texture != null) 'texture ${pct(q.texture)}%',
      if (q.wrinkles != null) 'wrinkles ${pct(q.wrinkles)}%',
      if (q.pores != null) 'pores ${pct(q.pores)}%',
      if (q.elasticity != null) 'elasticity ${pct(q.elasticity)}%',
    ];
    return parts.join(' · ');
  }

  /// Severity band label matching the overall band convention used by
  /// the analyzer (Clear / Mild / Moderate / Marked / Severe).
  String _severityBandForValue(int v) {
    if (v <= 1) return 'Clear';
    if (v <= 3) return 'Mild';
    if (v <= 5) return 'Moderate';
    if (v <= 7) return 'Marked';
    return 'Severe';
  }

  Widget _buildRecommendationsSection(Map<String, dynamic> metricMatrix) {
    final scores = _recommendationScoresFromMetricMatrix(metricMatrix);
    if (_isBodyProcedure) {
      return _buildBodyRecoveryRecommendationsSection(scores);
    }

    final isFollowUp = _explicitLocalFollowUpFlag || _localHistoryCountForFocusArea >= 2;
    // No backend equivalent exists for the old local-heuristic "skin
    // sensitivity" proxy (see _coachInsightForPhase's identical note) —
    // kept as an explicit 0.0 rather than removed from
    // _routineForScores/_coachRoutineHeaderText's shared signatures below.
    const sensitivitySignal = 0.0;
    final barrierStressed =
        sensitivitySignal >= 4.0 ||
        (scores['redness'] ?? 0) >= 4.0 ||
        (scores['rosacea_intensity'] ?? 0) >= 4.0;

    final redness = scores['redness'] ?? 0;
    final rosacea = scores['rosacea_intensity'] ?? 0;
    final acne = scores['acne_severity'] ?? 0;
    final inflammation = [
      redness,
      rosacea,
      acne,
    ].reduce((a, b) => a > b ? a : b);
    final treatInflammationFirst = inflammation >= 4.0 || barrierStressed;

    final recommendations = _productRecommendationsForScores(scores);
    final routine = _routineForScores(
      scores,
      isFollowUp: isFollowUp,
      sensitivitySignal: sensitivitySignal,
      barrierStressed: barrierStressed,
    );
    final routineHeader = _coachRoutineHeaderText(
      scores,
      isFollowUp: isFollowUp,
      barrierStressed: barrierStressed,
      sensitivitySignal: sensitivitySignal,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MyApp.clinicalTeal.withValues(alpha: 0.13),
                  const Color(0xFFD06B6B).withValues(alpha: 0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: MyApp.clinicalTeal.withValues(alpha: 0.20),
                width: 0.8,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: MyApp.clinicalTeal.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: MyApp.clinicalTeal,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        treatInflammationFirst
                            ? 'Calm first, actives second'
                            : isFollowUp
                            ? 'Keep the gains steady'
                            : 'Build around the main signals',
                        style: TextStyle(
                          color: MyApp.clinicalNavy,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        routineHeader,
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.82),
                          fontSize: 11.5,
                          height: 1.42,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < recommendations.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            _recommendationTile(recommendations[i], index: i + 1),
          ],
          const SizedBox(height: 16),
          _routineExpansionTile(
            amSteps: routine.$1,
            pmSteps: routine.$2,
            pmAccent: const Color(0xFFD06B6B),
            title: 'Suggested routine',
          ),
          const SizedBox(height: 14),
          _framingNote(
            'These are popular options that often help with similar concerns. '
            'Patch test new products, introduce one change at a time, and consult '
            'a professional if your skin is painful, worsening, or highly reactive.',
          ),
        ],
      ),
    );
  }

  Widget _buildBodyRecoveryRecommendationsSection(Map<String, double> scores) {
    final bodyScores = _bodyRecoveryScoresFor(scores);
    final swelling = bodyScores['swelling'] ?? 0;
    final bruising = bodyScores['scarringBruising'] ?? 0;
    final firmness = bodyScores['firmness'] ?? 0;
    final healing = bodyScores['overallHealingScore'] ?? 0;
    final subtype = procedure_intel.ProcedureIntelligence.bodyContouringSubtype(
      _selectedProcedureType,
    );
    final recommendations = _bodyProductRecommendationsForScores(
      bodyScores,
      subtype,
    );
    final routine = _bodyRoutineForScores(bodyScores, subtype);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MyApp.clinicalTeal.withValues(alpha: 0.13),
                  MyApp.goldShimmer.withValues(alpha: 0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: MyApp.clinicalTeal.withValues(alpha: 0.20),
                width: 0.8,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: MyApp.clinicalTeal.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.monitor_heart_rounded,
                    color: MyApp.clinicalTeal,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        swelling >= 4 || bruising >= 4
                            ? 'Prioritize swelling and bruising control'
                            : 'Protect contour and healing momentum',
                        style: TextStyle(
                          color: MyApp.clinicalNavy,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Body recovery readout: swelling ${swelling.toStringAsFixed(1)}, bruising/scarring ${bruising.toStringAsFixed(1)}, firmness ${firmness.toStringAsFixed(1)}, overall healing ${healing.toStringAsFixed(1)}. Follow your surgeon\'s restrictions first, then use supportive care consistently.',
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.82),
                          fontSize: 11.5,
                          height: 1.42,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < recommendations.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            _recommendationTile(recommendations[i], index: i + 1),
          ],
          const SizedBox(height: 16),
          _routineExpansionTile(
            amSteps: routine.$1,
            pmSteps: routine.$2,
            pmAccent: MyApp.goldShimmer,
            title: 'Suggested routine',
          ),
          const SizedBox(height: 14),
          _framingNote(
            'Body recovery suggestions are supportive only. Do not start massage, arnica, scar products, or compression changes unless your surgeon has cleared them, especially after BBL, liposuction, or tummy tuck.',
          ),
        ],
      ),
    );
  }

  /// Backend-only replacement for the old `_recommendationScoresFor`,
  /// which sourced these six scores from the on-device TFLite model
  /// (`_fullMetrics`) or, failing that, the local pixel-heuristic
  /// AcneRosaceaPhotoAnalyzer report — neither backed by the real
  /// backend. [metricMatrix] is the same cleaned backend metric_matrix
  /// LuxeReportLayout renders (see _buildLuxeResultsPayload). Maps each
  /// real formula-metric key onto the 0–10 scale this screen's
  /// recommendation/coach copy already expects; a key absent from
  /// metricMatrix (the backend didn't trust it for this scan) scores 0,
  /// same as "no concern found" rather than a fabricated guess.
  Map<String, double> _recommendationScoresFromMetricMatrix(
    Map<String, dynamic> metricMatrix,
  ) {
    double pct10(String key) {
      final raw = metricMatrix[key];
      final parsed = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (parsed == null || parsed.isNaN || parsed.isInfinite) return 0.0;
      return (parsed.clamp(0.0, 100.0) / 10.0).toDouble();
    }

    final textureSmoothness = pct10('texture_smoothness');
    return {
      'pigment': pct10('pigment_load'),
      'redness': pct10('localized_redness'),
      // Inverted: texture_smoothness is "higher = smoother = better", but
      // this map's convention (matching the rest of this file) is
      // "higher = more concern".
      'texture': (10.0 - textureSmoothness).clamp(0.0, 10.0).toDouble(),
      'wrinkle': pct10('wrinkle_load'),
      'acne_severity': pct10('breakout_activity'),
      'rosacea_intensity': pct10('rosacea_severity'),
    };
  }

  String _coachRoutineHeaderText(
    Map<String, double> scores, {
    required bool isFollowUp,
    required bool barrierStressed,
    required double sensitivitySignal,
  }) {
    final redness = scores['redness'] ?? 0;
    final rosacea = scores['rosacea_intensity'] ?? 0;
    final acne = scores['acne_severity'] ?? 0;
    final pigment = scores['pigment'] ?? 0;
    final texture = scores['texture'] ?? 0;
    final wrinkle = scores['wrinkle'] ?? 0;
    final concernParts = <String>[
      if (redness >= 4.0) 'redness ${redness.toStringAsFixed(1)}',
      if (rosacea >= 4.0) 'rosacea ${rosacea.toStringAsFixed(1)}',
      if (acne >= 3.5) 'breakouts ${acne.toStringAsFixed(1)}',
      if (texture >= 3.5) 'texture ${texture.toStringAsFixed(1)}',
      if (pigment >= 3.5) 'pigment ${pigment.toStringAsFixed(1)}',
      if (wrinkle >= 3.5) 'wrinkles ${wrinkle.toStringAsFixed(1)}',
    ];

    final concernText = concernParts.isEmpty
        ? 'a fairly calm baseline overall'
        : _joinWithCommasAndAnd(concernParts);

    if (isFollowUp) {
      if (barrierStressed || sensitivitySignal >= 4.0) {
        return 'The follow-up is still reading as a calm-first day, with barrier support more important than pushing stronger actives. The main signals are $concernText, so keep the plan simple and steady.';
      }
      return 'The follow-up is centered on $concernText, which means the best move is to keep one clear routine in place and only adjust a single step if the skin is already tolerating it.';
    }

    if (barrierStressed || sensitivitySignal >= 4.0) {
      return 'Starting point shows $concernText, and the barrier looks a bit reactive, so the routine should stay gentle, fragrance-free, and low-spirited on actives until the skin feels calmer.';
    }

    return 'Starting point shows $concernText, so I would build around a gentle cleanse, hydration, barrier support, and one targeted active rather than trying to do everything at once.';
  }

  List<({String title, String reason, IconData icon, Color accent})>
  _productRecommendationsForScores(Map<String, double> scores) {
    final redness = scores['redness'] ?? 0;
    final rosacea = scores['rosacea_intensity'] ?? 0;
    final acne = scores['acne_severity'] ?? 0;
    final pigment = scores['pigment'] ?? 0;
    final texture = scores['texture'] ?? 0;
    final wrinkle = scores['wrinkle'] ?? 0;
    final inflammation = [
      redness,
      rosacea,
      acne,
    ].reduce((a, b) => a > b ? a : b);

    final recs =
        <({String title, String reason, IconData icon, Color accent})>[];
    void add(String title, String reason, IconData icon, Color accent) {
      if (recs.any((r) => r.title == title)) return;
      if (recs.length < 6) {
        recs.add((title: title, reason: reason, icon: icon, accent: accent));
      }
    }

    if (inflammation >= 4) {
      add(
        'SKIN1004 Madagascar Centella Ampoule',
        'Best first step when redness/rosacea/acne are leading. Centella keeps the routine calming before stronger actives.',
        Icons.local_florist_rounded,
        MyApp.clinicalTeal,
      );
      add(
        'COSRX Advanced Snail 96 Mucin Essence',
        'A light barrier-support layer for reactive days; helpful when redness is ${redness.toStringAsFixed(1)} or texture feels stressed.',
        Icons.water_drop_outlined,
        MyApp.clinicalTeal,
      );
    }

    if (acne >= 3.5) {
      add(
        'COSRX Acne Pimple Master Patch',
        'Spot-focused support for active breakouts without adding an all-over active while inflammation is high.',
        Icons.radio_button_checked_rounded,
        const Color(0xFFD06B6B),
      );
      add(
        'Some By Mi AHA-BHA-PHA 30 Days Miracle Toner',
        'Consider only 1-2 nights weekly after skin feels calm; acne score ${acne.toStringAsFixed(1)} suggests pores may benefit from slow exfoliation.',
        Icons.science_outlined,
        const Color(0xFFD06B6B),
      );
    }

    if (rosacea >= 3.5 || redness >= 3.5) {
      add(
        'SKIN1004 Centella Probio-Cica Intensive Ampoule',
        'A richer cica option for redness/rosacea-prone days; pairs well with a simple moisturizer and SPF.',
        Icons.spa_rounded,
        MyApp.clinicalTeal,
      );
    }

    if (pigment >= 3.5 || redness < 4 && acne < 4) {
      add(
        'COSRX The Niacinamide 15 Serum',
        'Niacinamide is a good bridge active for pigment ${pigment.toStringAsFixed(1)} and visible redness, but start slowly if skin is reactive.',
        Icons.tonality_rounded,
        MyApp.goldShimmer,
      );
    }

    if ((texture >= 3.5 || wrinkle >= 3.5) && inflammation < 6) {
      add(
        'Copper peptide serum / GHK-Cu peptide serum',
        'A barrier-friendly PM option for texture ${texture.toStringAsFixed(1)} and wrinkle ${wrinkle.toStringAsFixed(1)} support without jumping straight to harsh actives.',
        Icons.grain_rounded,
        MyApp.clinicalNavy,
      );
    }

    add(
      'COSRX Balancium Comfort Ceramide Cream',
      'A gentle barrier-repair moisturizer to buffer actives and keep redness, acne, and texture routines easier to tolerate.',
      Icons.shield_outlined,
      MyApp.clinicalTeal,
    );
    add(
      'Daily broad-spectrum SPF 30+',
      'SPF is the quiet workhorse for pigment, redness, and collagen support. Use it every morning, especially with niacinamide or exfoliating acids.',
      Icons.wb_sunny_outlined,
      MyApp.goldShimmer,
    );

    return recs.take(6).toList();
  }

  List<({String title, String reason, IconData icon, Color accent})>
  _bodyProductRecommendationsForScores(
    Map<String, double> scores,
    procedure_intel.ProcedureBodyContouringSubtype subtype,
  ) {
    final swelling = scores['swelling'] ?? 0;
    final bruising = scores['scarringBruising'] ?? 0;
    final pigment = scores['hyperpigmentation'] ?? 0;
    final firmness = scores['firmness'] ?? 0;
    final recs =
        <({String title, String reason, IconData icon, Color accent})>[];

    void add(String title, String reason, IconData icon, Color accent) {
      if (recs.any((r) => r.title == title)) return;
      if (recs.length < 6) {
        recs.add((title: title, reason: reason, icon: icon, accent: accent));
      }
    }

    add(
      'Surgeon-approved compression garment',
      'Compression is the anchor for swelling control and contour support. Keep fit smooth and even; avoid rolling, bunching, or pressure points.',
      Icons.checkroom_outlined,
      MyApp.clinicalTeal,
    );

    if (subtype == procedure_intel.ProcedureBodyContouringSubtype.bbl) {
      add(
        'BBL pillow / no-pressure positioning',
        'For BBL recovery, protect transferred fat by avoiding direct sitting pressure until your surgeon clears it.',
        Icons.airline_seat_recline_extra_rounded,
        MyApp.goldShimmer,
      );
    }

    if (swelling >= 3.5) {
      add(
        'Manual lymphatic drainage when cleared',
        'Swelling ${swelling.toStringAsFixed(1)} suggests lymphatic support may help, but timing matters. Start only after surgical clearance.',
        Icons.waves_rounded,
        MyApp.clinicalTeal,
      );
    }

    if (bruising >= 3.5) {
      add(
        'Arnica gel or oral arnica if approved',
        'Bruising/scarring ${bruising.toStringAsFixed(1)} makes arnica a reasonable supportive option if it is safe with your medications and surgeon protocol.',
        Icons.local_florist_outlined,
        const Color(0xFFD06B6B),
      );
    }

    if (firmness < 6) {
      add(
        'Gentle walking and hydration routine',
        'Firmness ${firmness.toStringAsFixed(1)} can reflect swelling or tissue tightness. Short walks and hydration support circulation without stressing incisions.',
        Icons.directions_walk_rounded,
        MyApp.clinicalTeal,
      );
    }

    if (pigment >= 3.5) {
      add(
        'Silicone scar care plus SPF on exposed areas',
        'Pigment ${pigment.toStringAsFixed(1)} suggests marks need protection. Use silicone only on closed, healed incisions and protect exposed areas from UV.',
        Icons.healing_outlined,
        MyApp.goldShimmer,
      );
    }

    add(
      'Protein-forward meals and electrolyte support',
      'Adequate protein, fluids, and electrolytes support wound healing and reduce the temptation to overcorrect swelling with aggressive massage or activity.',
      Icons.restaurant_menu_rounded,
      MyApp.clinicalNavy,
    );

    return recs.take(6).toList();
  }

  (List<String>, List<String>) _routineForScores(
    Map<String, double> scores, {
    required bool isFollowUp,
    required double sensitivitySignal,
    required bool barrierStressed,
  }) {
    final redness = scores['redness'] ?? 0;
    final rosacea = scores['rosacea_intensity'] ?? 0;
    final acne = scores['acne_severity'] ?? 0;
    final pigment = scores['pigment'] ?? 0;
    final texture = scores['texture'] ?? 0;
    final wrinkle = scores['wrinkle'] ?? 0;
    final inflammation = [
      redness,
      rosacea,
      acne,
    ].reduce((a, b) => a > b ? a : b);
    final calmFirst = inflammation >= 4 || barrierStressed || sensitivitySignal >= 4;
    final allowActives = !calmFirst && isFollowUp;

    final am = <String>[
      calmFirst
          ? 'Gentle low-pH cleanser or a water rinse if your skin is dry, so the barrier stays quiet while redness and sensitivity settle.'
          : 'Gentle low-pH cleanser to lift overnight oil and sunscreen without stripping the skin that this scan is trying to protect.',
      calmFirst
          ? 'Centella or heartleaf toner / essence, because that is the calmest way to support a reactive barrier before any active treatment.'
          : pigment >= 3.5
          ? 'Hydrating toner or essence, because the scan shows tone support is useful and hydration keeps brightening steps better tolerated.'
          : texture >= 3.5 || wrinkle >= 3.5
          ? 'Peptide-friendly hydrating essence, because texture and firmness work best when the skin is comfortable first.'
          : 'Simple hydrating essence, because the skin does not need extra noise in the morning.',
      calmFirst
          ? 'Ceramide moisturizer only, or a niacinamide 2-5% serum if you already know your skin tolerates it, so the morning stays barrier-first.'
          : acne >= 3.5
          ? 'Niacinamide 2-5% serum or a light breakout-support serum, because the scan shows acne is present but the routine should still avoid stacking actives.'
          : pigment >= 3.5
          ? 'Niacinamide 2-5% serum, because it fits uneven tone and visible redness without pushing the skin too hard.'
          : 'Ceramide moisturizer, because keeping water in the skin is still the safest way to support the current scan pattern.',
      'Broad-spectrum SPF 30+, because it protects collagen, pigment, redness, and any progress this scan is tracking.',
    ];

    final pm = <String>[
      'Gentle cleanse, and if you wore sunscreen or makeup, double cleanse first so the evening routine starts from a clean surface.',
      calmFirst
          ? 'Centella, snail mucin, or a bland hydrating serum tonight, because the scan says calming the barrier should come before any stronger treatment.'
          : allowActives && (texture >= 3.5 || wrinkle >= 3.5)
          ? 'GHK-Cu Copper Tripeptide-1 at night, because texture and firmness concerns respond best when the barrier is calm and the routine stays consistent.'
          : allowActives && pigment >= 3.5
          ? 'GHK-Cu Copper Tripeptide-1 or another gentle peptide serum, because the scan favors quiet repair more than aggressive exfoliation.'
          : 'Hydrating serum or peptide step only if the skin stays comfortable, because the routine does not need to be overloaded.',
      calmFirst
          ? 'Ceramide barrier cream, because sealing the routine with lipids is the safest way to keep the skin quiet while redness or sensitivity is visible.'
          : acne >= 3.5
          ? 'Barrier cream plus a spot-only acne patch on active blemishes, because breakout support should stay targeted instead of turning into a full-face stack.'
          : 'Barrier cream, because this scan still benefits more from steady repair than from piling on more treatment steps.',
      calmFirst
          ? 'Skip acids, retinoids, and scrubs for now; if you want a weekly active later, wait until the skin is calm for several nights in a row.'
          : allowActives && (texture >= 3.5 || wrinkle >= 3.5 || pigment >= 3.5)
          ? 'If you add an exfoliant later, keep it to one calm night a week and do not stack it with GHK-Cu or spot acne care.'
          : 'If the skin feels stable, keep any extra treatment step optional rather than mandatory so you do not crowd the routine.',
    ];

    return (am, pm);
  }

  (List<String>, List<String>) _bodyRoutineForScores(
    Map<String, double> scores,
    procedure_intel.ProcedureBodyContouringSubtype subtype,
  ) {
    final swelling = scores['swelling'] ?? 0;
    final bruising = scores['scarringBruising'] ?? 0;
    final am = <String>[
      'Check garment fit and incision comfort',
      subtype == procedure_intel.ProcedureBodyContouringSubtype.bbl
          ? 'Use BBL pillow / no direct sitting if still restricted'
          : 'Short easy walk if cleared',
      swelling >= 4
          ? 'Elevate/rest between walks'
          : 'Hydrate and keep protein steady',
      'Call clinic for sudden pain, heat, fever, or one-sided swelling',
    ];
    final pm = <String>[
      'Gentle shower and dry garment-safe skin fully',
      bruising >= 4 ? 'Arnica only if approved' : 'Moisturize intact skin only',
      'Scar silicone only on closed healed incisions',
      'Sleep in surgeon-approved position',
    ];
    return (am, pm);
  }

  Widget _routineExpansionTile({
    required List<String> amSteps,
    required List<String> pmSteps,
    required Color pmAccent,
    String title = 'Suggested routine',
  }) {
    final hasRoutine = amSteps.isNotEmpty || pmSteps.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.24),
          width: 0.8,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: MyApp.clinicalNavy,
          collapsedIconColor: MyApp.clinicalNavy,
          title: Text(
            title,
            style: TextStyle(
              color: MyApp.clinicalNavy,
              fontSize: 12.4,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            'Tap to view AM/PM steps',
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.74),
              fontSize: 10.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            if (hasRoutine)
              Row(
                children: [
                  Expanded(
                    child: _routineColumn('AM', amSteps, MyApp.clinicalTeal),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _routineColumn('PM', pmSteps, pmAccent),
                  ),
                ],
              )
            else
              _framingNote(
                'Routine tips unlock from your scores.',
              ),
          ],
        ),
      ),
    );
  }

  Widget _recommendationTile(
    ({String title, String reason, IconData icon, Color accent}) rec, {
    required int index,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: rec.accent.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: rec.accent.withValues(alpha: 0.18),
          width: 0.7,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: rec.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(rec.icon, size: 15, color: rec.accent),
                Positioned(
                  right: 3,
                  bottom: 2,
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: rec.accent,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.title,
                  style: TextStyle(
                    color: MyApp.clinicalNavy,
                    fontSize: 12.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  rec.reason,
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.82),
                    fontSize: 11.5,
                    height: 1.42,
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

  Widget _routineColumn(String label, List<String> steps, Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: accent.withValues(alpha: 0.20), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                label == 'AM'
                    ? Icons.wb_sunny_outlined
                    : Icons.nights_stay_outlined,
                color: accent,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                '$label ROUTINE',
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}.',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    steps[i],
                    style: TextStyle(
                      color: MyApp.textBrown.withValues(alpha: 0.82),
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
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

  Widget _proceduresCard(PhotoAnalysisResult r) {
    return Column(
      children: [
        for (int i = 0; i < r.procedures.take(4).length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: i == 0
                    ? AppColors.champagneGold.withValues(alpha: 0.45)
                    : MyApp.clinicalSlate.withValues(alpha: 0.15),
                width: i == 0 ? 1.0 : 0.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: (i == 0 ? AppColors.champagneGold : MyApp.clinicalNavy)
                      .withValues(alpha: i == 0 ? 0.10 : 0.04),
                  blurRadius: i == 0 ? 16 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (i == 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.champagneGold.withValues(alpha: 0.18),
                            MyApp.goldShimmer.withValues(alpha: 0.18),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.45,
                          ),
                          width: 0.6,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 11,
                            color: AppColors.champagneGold,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'COMMONLY EXPLORED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.9,
                              color: AppColors.champagneGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.procedures[i].name,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: MyApp.clinicalNavy,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: MyApp.clinicalTeal.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${r.procedures[i].suitabilityPct}% relevance',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: MyApp.clinicalTeal,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  r.procedures[i].indication,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: MyApp.textBrown.withValues(alpha: 0.85),
                  ),
                ),
                if (r.procedures[i].pros.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final pro in r.procedures[i].pros.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.add_circle_outline_rounded,
                            size: 11,
                            color: Color(0xFF4FAE8B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              pro,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                color: MyApp.textBrown.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _miniMeta(
                      Icons.fitness_center_rounded,
                      _intensityLabel(r.procedures[i].intensity),
                    ),
                    _miniMeta(
                      Icons.event_repeat_rounded,
                      r.procedures[i].expectedSessions,
                    ),
                    _miniMeta(
                      Icons.timelapse_rounded,
                      r.procedures[i].timelineWeeks,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _intensityLabel(ProcedureIntensity i) {
    switch (i) {
      case ProcedureIntensity.gentle:
        return 'Gentle';
      case ProcedureIntensity.moderate:
        return 'Moderate';
      case ProcedureIntensity.intensive:
        return 'Intensive';
      case ProcedureIntensity.systemic:
        return 'Systemic / Rx';
    }
  }

  Widget _miniMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: MyApp.clinicalSlate),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: MyApp.clinicalSlate,
          ),
        ),
      ],
    );
  }

  Widget _productCuesCard(PhotoAnalysisResult r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final cue in r.productCues)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 13,
                    color: MyApp.clinicalTeal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cue,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: MyApp.textBrown.withValues(alpha: 0.88),
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

  // ── Helpers ───────────────────────────────────────────────────────

  /// Inline validation note shown beneath the focus-area chips when the
  /// user tries to run analysis without selecting a focus area.
  Widget _focusAreaErrorNote(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBEDED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD06B6B).withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Color(0xFFC0504D),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: Color(0xFFC0504D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heatmapImageForPath(
    String path, {
    Map<String, double>? heatmapScores,
  }) {
    final provider = _imageProviderForPath(path);
    if (provider == null) {
      return Container(color: AppColors.champagneGold.withValues(alpha: 0.06));
    }

    if (heatmapScores == null || heatmapScores.isEmpty) {
      return Image(image: provider, fit: BoxFit.cover);
    }

    if (_isBodyProcedure) {
      return SkinHeatmapOverlay.bodyContouring(
        photo: provider,
        region: _analysisBodyHeatmapRegion(),
        inflammation: _scoreOrZero(heatmapScores, 'redness'),
        textureIrregularity: _scoreOrZero(heatmapScores, 'texture'),
        improvement: _estimatedHeatmapImprovement(heatmapScores),
      );
    }

    return SkinHeatmapOverlay.laser(
      photo: provider,
      redness: _scoreOrZero(heatmapScores, 'redness'),
      wrinkles: _scoreOrZero(heatmapScores, 'wrinkle'),
      improvement: _estimatedHeatmapImprovement(heatmapScores),
    );
  }

  ImageProvider<Object>? _imageProviderForPath(String? path) {
    final p = (path ?? '').trim();
    if (p.isEmpty) return null;

    if (kIsWeb ||
        p.startsWith('data:image') ||
        p.startsWith('http://') ||
        p.startsWith('https://')) {
      return NetworkImage(p);
    }
    return FileImage(File(p));
  }

  double _scoreOrZero(Map<String, double> scores, String key) {
    final raw = scores[key] ?? 0;
    return raw.clamp(0, 10).toDouble();
  }

  double _estimatedHeatmapImprovement(Map<String, double> scores) {
    final redness = _scoreOrZero(scores, 'redness');
    final texture = _scoreOrZero(scores, 'texture');
    final wrinkle = _scoreOrZero(scores, 'wrinkle');
    final pigment = _scoreOrZero(scores, 'pigment');
    final concernAvg = (redness + texture + wrinkle + pigment) / 4;
    return (10 - concernAvg).clamp(0, 10).toDouble();
  }

  SkinHeatmapBodyRegion _analysisBodyHeatmapRegion() {
    final subtype = procedure_intel.ProcedureIntelligence.bodyContouringSubtype(
      _selectedProcedureType,
    );
    if (subtype == procedure_intel.ProcedureBodyContouringSubtype.bbl) {
      return SkinHeatmapBodyRegion.flanks;
    }
    if (subtype == procedure_intel.ProcedureBodyContouringSubtype.liposuction) {
      return SkinHeatmapBodyRegion.abdomen;
    }

    final canonical = (_selectedProcedureType ?? '').toLowerCase().trim();
    if (canonical.contains('thigh')) return SkinHeatmapBodyRegion.thighs;
    if (canonical.contains('arm')) return SkinHeatmapBodyRegion.arms;
    if (canonical.contains('breast')) return SkinHeatmapBodyRegion.breasts;
    if (canonical.contains('tummy') || canonical.contains('abdomen')) {
      return SkinHeatmapBodyRegion.abdomen;
    }
    return SkinHeatmapBodyRegion.generic;
  }

  /// Small italic caption used to frame procedure / ingredient sections as
  /// general information rather than a personalised recommendation.
  Widget _framingNote(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 12,
          color: MyApp.clinicalSlate.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: MyApp.clinicalSlate,
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: AppColors.cardBackground,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: AppColors.champagneGold.withValues(alpha: 0.22),
      width: 0.8,
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.refinedSlate.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );

  String _regionLabel(FacialRegion r) {
    switch (r) {
      case FacialRegion.fullFace:
        return 'Full face';
      case FacialRegion.forehead:
        return 'Forehead';
      case FacialRegion.cheeks:
        return 'Cheeks';
      case FacialRegion.jawlineChin:
        return 'Jawline / chin';
      case FacialRegion.nose:
        return 'Nose';
      case FacialRegion.perioral:
        return 'Around mouth';
    }
  }

  Color _severityColor(double index) {
    if (index < 1.5) return const Color(0xFF4FAE8B);
    if (index < 4) return const Color(0xFFB89A6E);
    if (index < 6.5) return const Color(0xFFD08A4A);
    if (index < 8.5) return const Color(0xFFC76A55);
    return const Color(0xFFA64A4A);
  }

  Color _valueColor(int v) {
    if (v <= 2) return const Color(0xFF4FAE8B);
    if (v <= 5) return const Color(0xFFB89A6E);
    if (v <= 7) return const Color(0xFFD08A4A);
    return const Color(0xFFC76A55);
  }
}

class _SkinAiSplitComparisonScreen extends StatelessWidget {
  const _SkinAiSplitComparisonScreen({
    required this.baselineImage,
    required this.currentImage,
  });

  final ImageProvider<Object> baselineImage;
  final ImageProvider<Object> currentImage;

  Widget _panel({
    required String label,
    required ImageProvider<Object> image,
    required Color accent,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF11151F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.4), width: 0.9),
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            Expanded(child: Image(image: image, fit: BoxFit.cover)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        title: const Text('Before & After Comparison'),
        backgroundColor: const Color(0xFF0F1117),
        foregroundColor: const Color(0xFFF3EBDD),
      ),
      body: SafeArea(
        child: Row(
          children: [
            _panel(
              label: 'BASELINE',
              image: baselineImage,
              accent: const Color(0xFFE5C287),
            ),
            _panel(
              label: 'CURRENT',
              image: currentImage,
              accent: const Color(0xFF9BC9AE),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable results screen for the backend-powered Deep Analysis flow in
/// [CameraScreen]. It accepts flexible JSON so future trained-model payloads
/// can be displayed without coupling the camera screen to a specific schema.
class SkinAiAnalysisResultsScreen extends StatelessWidget {
  final Map<String, dynamic> analysisResult;
  final Uint8List? croppedImageBytes;

  const SkinAiAnalysisResultsScreen({
    super.key,
    required this.analysisResult,
    required this.croppedImageBytes,
  });

  Map<String, dynamic> get _body {
    final nested =
        analysisResult['analysis'] ??
        analysisResult['result'] ??
        analysisResult['data'] ??
        analysisResult['results'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    return analysisResult;
  }

  @override
  Widget build(BuildContext context) {
    final metricsPayload = _buildLuxeRenderPayload();
    final baselineImage = _baselineImageProvider();
    final currentImage = _currentImageProvider();
    final recommendedProducts = _recommendedProducts();
    final narrative =
        _stringValue([
          'smart_narrative',
          'narrative',
          'summary',
          'overall_summary',
          'interpretation',
          'description',
        ]) ??
        'Single-scan analysis completed successfully.';

    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.warmAlabaster,
        foregroundColor: MyApp.clinicalNavy,
        title: const Text(
          'Skin AI Analysis',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topDisclaimer(),
                  const SizedBox(height: 14),
                  LuxeReportLayout(
                    rawPayload: metricsPayload,
                    baselineImageProvider: baselineImage,
                    currentImageProvider: currentImage,
                    baselineLabel: 'Baseline Image',
                    currentLabel: 'Current Scan',
                  ),
                  if (recommendedProducts.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _recommendedProductsCarousel(context, recommendedProducts),
                  ],
                  const SizedBox(height: 16),
                  SmartNarrativeContainer(narrativeText: narrative),
                  const SizedBox(height: 18),
                  _actionsCard(context),
                  const SizedBox(height: 14),
                  _footerDisclaimer(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Map<String, dynamic> _buildLuxeRenderPayload() {
    final metrics = _firstMap(['metrics']) ?? _body;
    final merged = Map<String, dynamic>.from(metrics);

    Map<String, dynamic>? readMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    final rootTrend = readMap(
      _body['trend_deltas'] ?? analysisResult['trend_deltas'],
    );
    final nestedTrend = readMap(metrics['trend_deltas']);
    final rootMatrix = readMap(
      _body['metric_matrix'] ?? analysisResult['metric_matrix'],
    );
    final nestedMatrix = readMap(metrics['metric_matrix']);

    // Same dropped-field pattern as metric_matrix above -- _assessMetricHonesty
    // resolves hasComparisonBaseline from baseline_metric_matrix, so without
    // this a baseline value is never available at all (a different symptom
    // than the trend_status gap below, but the same missing-merge bug).
    final rootBaselineMatrix = readMap(
      _body['baseline_metric_matrix'] ?? analysisResult['baseline_metric_matrix'],
    );
    final nestedBaselineMatrix = readMap(metrics['baseline_metric_matrix']);

    // trend_status must travel alongside trend_deltas -- _assessMetricHonesty
    // (luxe_report_layout.dart) only trusts the backend trend for a metric
    // when BOTH trend_deltas and trend_status are present; dropping either
    // one silently forces every metric on this screen into the Dart-recompute
    // fallback (LUXE TREND FALLBACK) even when the backend sent a real trend.
    final rootTrendStatus = readMap(
      _body['trend_status'] ?? analysisResult['trend_status'],
    );
    final nestedTrendStatus = readMap(metrics['trend_status']);

    // Same dropped-field pattern as trend_deltas/metric_matrix above, for the
    // extraction-path fields the honesty/path-mismatch guard depends on.
    final rootExtractionPaths = readMap(
      _body['metric_extraction_paths'] ?? analysisResult['metric_extraction_paths'],
    );
    final nestedExtractionPaths = readMap(metrics['metric_extraction_paths']);
    final rootBaselineExtractionPaths = readMap(
      _body['baseline_metric_extraction_paths'] ??
          analysisResult['baseline_metric_extraction_paths'],
    );
    final nestedBaselineExtractionPaths = readMap(
      metrics['baseline_metric_extraction_paths'],
    );

    final trendDeltas = rootTrend ?? nestedTrend;
    final metricMatrix = rootMatrix ?? nestedMatrix;
    final baselineMatrix = rootBaselineMatrix ?? nestedBaselineMatrix;
    final trendStatus = rootTrendStatus ?? nestedTrendStatus;
    final extractionPaths = rootExtractionPaths ?? nestedExtractionPaths;
    final baselineExtractionPaths =
        rootBaselineExtractionPaths ?? nestedBaselineExtractionPaths;

    if (trendDeltas != null) {
      merged['trend_deltas'] = trendDeltas;
    }
    if (metricMatrix != null) {
      merged['metric_matrix'] = metricMatrix;
    }
    if (baselineMatrix != null) {
      merged['baseline_metric_matrix'] = baselineMatrix;
    }
    if (trendStatus != null) {
      merged['trend_status'] = trendStatus;
    }
    if (extractionPaths != null) {
      merged['metric_extraction_paths'] = extractionPaths;
    }
    if (baselineExtractionPaths != null) {
      merged['baseline_metric_extraction_paths'] = baselineExtractionPaths;
    }

    return merged;
  }

  ImageProvider<Object>? _currentImageProvider() {
    if (croppedImageBytes != null && croppedImageBytes!.isNotEmpty) {
      return MemoryImage(croppedImageBytes!);
    }
    final path = _stringValue([
      'image_path',
      'imagePath',
      'current_image_path',
      'currentImagePath',
    ]);
    return _imageProviderFromDynamic(path);
  }

  ImageProvider<Object>? _baselineImageProvider() {
    final baselineFromMap = _firstMap([
      'baseline',
      'baseline_image',
      'baselineImage',
    ]);

    final baselinePath =
        baselineFromMap?['image_path']?.toString() ??
        baselineFromMap?['imagePath']?.toString() ??
        _stringValue([
          'baseline_image_path',
          'baselineImagePath',
          'baseline_path',
          'baselinePath',
          'baseline_image',
          'baselineImage',
        ]);
    final provider = _imageProviderFromDynamic(baselinePath);
    if (provider != null) return provider;

    final baselineBytesRaw =
        baselineFromMap?['image_bytes'] ??
        baselineFromMap?['imageBytes'] ??
        _body['baseline_image_bytes'] ??
        _body['baselineImageBytes'] ??
        analysisResult['baseline_image_bytes'] ??
        analysisResult['baselineImageBytes'];
    if (baselineBytesRaw is String && baselineBytesRaw.trim().isNotEmpty) {
      try {
        final raw = baselineBytesRaw.trim();
        final comma = raw.indexOf(',');
        final payload = comma >= 0 ? raw.substring(comma + 1) : raw;
        return MemoryImage(base64Decode(payload));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  ImageProvider<Object>? _imageProviderFromDynamic(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) return null;

    if (value.startsWith('data:image')) {
      try {
        final comma = value.indexOf(',');
        if (comma < 0) return null;
        return MemoryImage(base64Decode(value.substring(comma + 1)));
      } catch (_) {
        return null;
      }
    }

    if (value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('blob:')) {
      return NetworkImage(value);
    }

    if (!kIsWeb) {
      final file = File(value);
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    return null;
  }

  Widget _topDisclaimer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.10),
            AppColors.mutedSage.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.health_and_safety_outlined,
            size: 18,
            color: AppColors.champagneGold,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: MyApp.textBrown.withValues(alpha: 0.9),
                ),
                children: const [
                  TextSpan(
                    text:
                        'These are AI-assisted observations, not medical advice. ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  TextSpan(
                    text:
                        'They are not a diagnosis and are for personal cosmetic tracking only. Consult a dermatologist or qualified healthcare professional for medical concerns.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendedProductsCarousel(
    BuildContext context,
    List<_RecommendedProduct> products,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RECOMMENDED PRODUCTS',
          style: TextStyle(
            color: Color(0xFFB76E79),
            fontSize: 11,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return Container(
                width: 280,
                margin: EdgeInsets.only(
                  right: index == products.length - 1 ? 0 : 12,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F2C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFB76E79).withValues(alpha: 0.85),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB76E79).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(
                            0xFFB76E79,
                          ).withValues(alpha: 0.55),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        product.reasonTag,
                        style: const TextStyle(
                          color: Color(0xFFF0B7C1),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      product.brand.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.price,
                      style: const TextStyle(
                        color: Color(0xFF7A8B7B),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () =>
                            _launchAffiliateUrl(context, product.affiliateUrl),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7A8B7B),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'BUY PRODUCT',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _launchAffiliateUrl(BuildContext context, String url) async {
    final raw = url.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
    if (uri == null) return;

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open product link.')),
      );
    }
  }

  Widget _modelDisclosure() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: MyApp.clinicalTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MyApp.clinicalTeal.withValues(alpha: 0.32),
          width: 0.7,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.psychology_alt_rounded,
            size: 15,
            color: MyApp.clinicalTeal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Model output is displayed as visual estimates from this single cropped photo. Lighting, angle and image quality can affect results.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: MyApp.textBrown.withValues(alpha: 0.88),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overallScoreCard(_ReportBundle report) {
    final scoreColor = _scoreAccent(report.overallScore);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFFCF7),
            const Color(0xFFFFF4F7),
            AppColors.champagneGold.withValues(alpha: 0.20),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.45),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.champagneGold.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: scoreColor.withValues(alpha: 0.45),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                report.overallScore.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: scoreColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall Skin Score',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: MyApp.clinicalNavy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${report.overallScore.toStringAsFixed(1)} / 10  •  ${report.overallBand}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scoreColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Balanced hydration, texture, clarity, and recovery markers from this analysis snapshot.',
                  style: TextStyle(
                    fontSize: 10.7,
                    height: 1.35,
                    color: MyApp.textBrown.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricsGrid(List<_ReportMetric> metrics) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.86,
      ),
      itemBuilder: (context, index) => _metricCard(metrics[index]),
    );
  }

  Widget _metricCard(_ReportMetric metric) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            const Color(0xFFFFFAFC),
            metric.accent.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: metric.accent.withValues(alpha: 0.34)),
        boxShadow: [
          BoxShadow(
            color: metric.accent.withValues(alpha: 0.12),
            blurRadius: 12,
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
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: metric.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(metric.icon, color: metric.accent, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.7,
                    fontWeight: FontWeight.w800,
                    color: MyApp.clinicalNavy,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            metric.displayValue,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: metric.accent,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metric.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.2,
              height: 1.28,
              fontWeight: FontWeight.w600,
              color: MyApp.textBrown.withValues(alpha: 0.74),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metric.status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
              color: MyApp.textBrown.withValues(alpha: 0.80),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: metric.score / 10,
              minHeight: 5,
              backgroundColor: metric.accent.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(metric.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationsCard(List<String> recommendations) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  color: AppColors.champagneGold,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Actionable Recommendations',
                style: TextStyle(
                  fontSize: 13.2,
                  fontWeight: FontWeight.w900,
                  color: MyApp.clinicalNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final tip in recommendations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.fiber_manual_record_rounded,
                      size: 8,
                      color: AppColors.champagneGold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tip,
                      style: TextStyle(
                        fontSize: 11.6,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: MyApp.textBrown.withValues(alpha: 0.88),
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

  Widget _clinicalInsightsCard(String narrative) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFFCF8),
            const Color(0xFFFFF5F7),
            AppColors.champagneGold.withValues(alpha: 0.16),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.36),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC98E97).withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.champagneGold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.champagneGold,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI CLINICAL INSIGHTS',
                  style: TextStyle(
                    fontSize: 11.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: MyApp.clinicalNavy,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  narrative,
                  style: TextStyle(
                    fontSize: 11.7,
                    height: 1.48,
                    fontWeight: FontWeight.w600,
                    color: MyApp.textBrown.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textItemsCard(List<_TextItem> items, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 18,
                color: MyApp.clinicalSlate.withValues(alpha: 0.12),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: MyApp.clinicalTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: MyApp.clinicalTeal),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: MyApp.clinicalNavy,
                        ),
                      ),
                      if (items[i].detail.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          items[i].detail,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: MyApp.textBrown.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
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

  String _getSmartNarrative(_ReportBundle report) {
    double metricValue(String key, {double fallback = 0}) {
      for (final metric in report.metrics) {
        if (metric.key == key) return metric.rawValue;
      }
      return fallback;
    }

    final wrinkle = metricValue('wrinkleScore', fallback: 4.1);
    final pigmentation = metricValue('pigmentationScore', fallback: 3.8);
    final overall = report.overallScore;
    final procedureContext =
        _stringValue([
          'procedure_context',
          'procedureContext',
          'procedure_type',
          'procedureType',
          'procedure',
          'selectedProcedureLabel',
        ]) ??
        'skin optimization';

    final bool wrinkleElevated = wrinkle >= 6.5;
    final bool wrinkleQuiet = wrinkle <= 3.5;
    final bool pigmentElevated = pigmentation >= 6.0;
    final bool pigmentQuiet = pigmentation <= 3.5;

    String leading;
    if (wrinkleElevated && pigmentElevated) {
      leading =
          'This scan shows a combined pattern of visible line formation and uneven tone, suggesting that both collagen support and pigment-calming strategies should stay central.';
    } else if (wrinkleElevated) {
      leading =
          'The strongest signal in this scan is wrinkle activity, with fine-line depth reading more prominently than pigment variation.';
    } else if (pigmentElevated) {
      leading =
          'Pigmentation is the dominant visual concern in this scan, with tone variation standing out more than structural line depth.';
    } else if (wrinkleQuiet && pigmentQuiet) {
      leading =
          'Wrinkle and pigmentation signals both read relatively calm here, which supports a maintenance-focused strategy rather than aggressive correction.';
    } else {
      leading =
          'This scan reads as moderately balanced, with subtle structural and tone concerns that are present but not dominant.';
    }

    String procedureNote;
    final contextLower = procedureContext.toLowerCase();
    if (contextLower.contains('microneed') ||
        contextLower.contains('laser') ||
        contextLower.contains('peel')) {
      procedureNote =
          'In the context of $procedureContext, this pattern usually benefits from disciplined barrier support and pigment-safe recovery while the skin remodels.';
    } else if (contextLower.contains('botox') ||
        contextLower.contains('filler') ||
        contextLower.contains('tox')) {
      procedureNote =
          'Against a $procedureContext backdrop, these readings are most useful for tracking surface quality around the treated result rather than volume change itself.';
    } else {
      procedureNote =
          'For $procedureContext, the most useful next step is consistent follow-up scanning under similar lighting so line depth and tone shift can be separated from day-to-day variability.';
    }

    String closing;
    if (overall >= 8.0) {
      closing =
          'Overall skin quality remains strong, so the emphasis should be on preserving clarity, smoothness, and treatment gains.';
    } else if (overall >= 6.0) {
      closing =
          'Overall skin quality is in a stable middle range, with room for targeted improvement where the highest-scoring concern is concentrated.';
    } else {
      closing =
          'Overall skin quality is still asking for closer support, and the wrinkle/pigment pattern suggests staying consistent with recovery-aware topical care and repeat tracking.';
    }

    return '$leading $procedureNote $closing';
  }

  Widget _actionsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text(
              'Run another analysis',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyApp.clinicalNavy,
              minimumSize: const Size(double.infinity, 46),
              side: BorderSide(
                color: MyApp.clinicalNavy.withValues(alpha: 0.35),
                width: 0.8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Results are based on one cropped photo and may change with '
            'better lighting, a different crop, or over time.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: MyApp.clinicalSlate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerDisclaimer() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 13,
          color: MyApp.clinicalSlate.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'AI-assisted observations — not a diagnosis and not a substitute '
            'for professional medical advice. Always consult a qualified '
            'healthcare professional for any concern, diagnosis, or '
            'treatment decision.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: MyApp.clinicalSlate,
            ),
          ),
        ),
      ],
    );
  }

  _ReportBundle _buildReportBundle() {
    final source = _firstMap(['metrics', 'scores', 'measurements']) ?? _body;
    final custom = _firstMap([
      'custom_metrics',
      'customMetrics',
      'user_metrics',
      'userTrackedMetrics',
      'tracked_metrics',
    ]);

    final ignored = <String>{
      'status',
      'success',
      'message',
      'headline',
      'summary',
      'overall_summary',
      'description',
      'interpretation',
      'confidence',
      'model_confidence',
      'confidence_score',
      'analysis',
      'result',
      'data',
      'results',
    };

    double normalizeScore(dynamic raw) {
      final parsed = _toNumber(raw);
      if (parsed == null) return double.nan;
      if (parsed >= 0 && parsed <= 1) return (parsed * 10).clamp(0.0, 10.0);
      if (parsed >= 0 && parsed <= 100) {
        return (parsed / 10).clamp(0.0, 10.0);
      }
      return parsed.clamp(0.0, 10.0).toDouble();
    }

    final numeric = <String, double>{};
    source.forEach((key, raw) {
      final k = key.toString();
      if (ignored.contains(k)) return;
      final n = normalizeScore(raw);
      if (n.isNaN) return;
      numeric[k] = n;
    });
    custom?.forEach((key, raw) {
      final n = normalizeScore(raw);
      if (n.isNaN) return;
      numeric[key.toString()] = n;
    });

    final cv = _extractCvSignals(croppedImageBytes);

    double? fromNumeric(List<String> keys) {
      for (final key in keys) {
        if (numeric.containsKey(key)) {
          return numeric[key]!.clamp(0.0, 10.0).toDouble();
        }
      }
      return null;
    }

    double? explicitNumeric(List<String> keys) => fromNumeric(keys);

    double pick(
      List<String> keys, {
      required double fallback,
      double? cvScore,
      bool invert = false,
    }) {
      final model = fromNumeric(keys);
      var resolved = model ?? cvScore ?? fallback;
      if (model != null && cvScore != null) {
        // Blend model output with lightweight CV estimates for stability.
        resolved = model * 0.65 + cvScore * 0.35;
      }
      resolved = resolved.clamp(0.0, 10.0).toDouble();
      return invert ? (10 - resolved).clamp(0.0, 10.0) : resolved;
    }

    final hydration = pick(
      ['hydrationLevel', 'hydration', 'waterRetention'],
      fallback: 6.6,
      cvScore: cv?.hydrationScore,
    );
    final oiliness = pick(
      ['oiliness', 'sebum', 'oilLevel'],
      fallback: 4.0,
      cvScore: cv?.oilinessLevelScore,
    );
    final pores = pick(
      ['poreSize', 'pores', 'poresVisibility'],
      fallback: 5.0,
      cvScore: cv?.poreVisibilityScore,
    );
    final sensitivity = pick(
      ['skinSensitivity', 'sensitivity'],
      fallback: 3.1,
      cvScore: cv?.sensitivityScore,
    );
    final collagen = pick(
      ['collagenScore', 'elasticity', 'firmness', 'skinLaxityFirmness'],
      fallback: 7.3,
      cvScore: cv?.collagenScore,
    );
    final redness = pick(
      ['redness', 'inflammation', 'rosaceaSeverity', 'erythema'],
      fallback: 3.3,
      cvScore: cv?.rednessScore,
    );
    final pigmentationScore = pick([
      'pigmentation_score',
      'pigmentationScore',
      'pigmentation',
      'pigment',
      'darkSpots',
      'postAcneScarring',
    ], fallback: 3.8);
    final darkSpots = pick([
      'darkSpots',
      'pigmentation',
      'pigment',
      'postAcneScarring',
    ], fallback: pigmentationScore);
    final texture = pick(
      ['texture', 'roughness', 'skinTexture'],
      fallback: 4.2,
      cvScore: cv?.textureRoughnessScore,
    );
    final wrinkleScore = pick([
      'wrinkle_score',
      'wrinkleScore',
      'wrinkle',
      'wrinkles',
      'rhytids',
      'fineLines',
    ], fallback: 4.1);
    final acne = pick([
      'acneSeverity',
      'breakoutSeverity',
      'activeBreakouts',
      'acneCount',
    ], fallback: 2.9);
    final scarProgress = pick(
      ['scarHealingProgress', 'overallHealingScore', 'scarringBruising'],
      fallback: 7.1,
      invert: numeric.containsKey('scarringBruising'),
    );

    final oilBalanceScore = (10 - (oiliness - 5).abs() * 2).clamp(0.0, 10.0);
    final explicitOverall = explicitNumeric([
      'overall_skin_score',
      'overallSkinScore',
      'overall_score',
      'skinScore',
      'overallHealingScore',
    ]);
    final computedOverall =
        (hydration * 0.16 +
                oilBalanceScore * 0.09 +
                collagen * 0.14 +
                (10 - redness) * 0.12 +
                (10 - darkSpots) * 0.10 +
                (10 - pigmentationScore) * 0.10 +
                (10 - texture) * 0.10 +
                (10 - wrinkleScore) * 0.09 +
                (10 - acne) * 0.06 +
                scarProgress * 0.04)
            .clamp(0.0, 10.0);
    final overall = explicitOverall != null
        ? explicitOverall.clamp(0.0, 10.0)
        : computedOverall;

    final hydrationPct = cv != null
        ? cv.hydrationPercent.round()
        : (40 + hydration * 5.5).clamp(0, 100).round();
    final oilinessPct = cv != null
        ? cv.oilinessPercent.round()
        : (20 + oiliness * 7).clamp(0, 100).round();
    final poreSizeMm = cv != null ? cv.poreSizeMm : (0.14 + pores * 0.018);

    final cards = <_ReportMetric>[
      _ReportMetric(
        key: 'hydrationLevel',
        label: 'Hydration Level',
        rawValue: hydration,
        score: hydration,
        displayValue: '$hydrationPct%',
        description: 'Surface water balance and bounce',
        status: _hydrationBand(hydration),
        icon: Icons.water_drop_rounded,
        accent: const Color(0xFFB989A3),
      ),
      _ReportMetric(
        key: 'oiliness',
        label: 'Oiliness',
        rawValue: oiliness,
        score: oilBalanceScore,
        displayValue: '$oilinessPct%',
        description: 'Sebum balance across the visible patch',
        status: _oilBand(oiliness),
        icon: Icons.opacity_rounded,
        accent: const Color(0xFFCFA67D),
      ),
      _ReportMetric(
        key: 'poreSize',
        label: 'Pore Size',
        rawValue: pores,
        score: (10 - pores).clamp(0.0, 10.0),
        displayValue: '${poreSizeMm.toStringAsFixed(2)}mm',
        description: 'Estimated pore opening visibility',
        status: '${_poreBand(pores)} (estimated)',
        icon: Icons.blur_on_rounded,
        accent: const Color(0xFFBC8CA5),
      ),
      _ReportMetric(
        key: 'skinSensitivity',
        label: 'Skin Sensitivity',
        rawValue: sensitivity,
        score: (10 - sensitivity).clamp(0.0, 10.0),
        displayValue: sensitivity.toStringAsFixed(1),
        description: 'Reactivity and comfort under visible stress',
        status: _lowMidHigh(sensitivity, reverse: true),
        icon: Icons.favorite_border_rounded,
        accent: const Color(0xFFB77D92),
      ),
      _ReportMetric(
        key: 'collagenScore',
        label: 'Collagen / Elasticity',
        rawValue: collagen,
        score: collagen,
        displayValue: '${collagen.toStringAsFixed(1)} / 10',
        description: 'Firmness and rebound appearance',
        status: _lowMidHigh(collagen),
        icon: Icons.spa_rounded,
        accent: const Color(0xFFC9A06D),
      ),
      _ReportMetric(
        key: 'rednessInflammation',
        label: 'Redness / Inflammation',
        rawValue: redness,
        score: (10 - redness).clamp(0.0, 10.0),
        displayValue: redness.toStringAsFixed(1),
        description: 'Visible flushing and inflammatory tone',
        status: _lowMidHigh(redness, reverse: true),
        icon: Icons.local_fire_department_outlined,
        accent: const Color(0xFFD08A74),
      ),
      _ReportMetric(
        key: 'darkSpotsPigmentation',
        label: 'Dark Spots / Pigmentation',
        rawValue: darkSpots,
        score: (10 - darkSpots).clamp(0.0, 10.0),
        displayValue: darkSpots.toStringAsFixed(1),
        description: 'Spot-specific discoloration and marks',
        status: _lowMidHigh(darkSpots, reverse: true),
        icon: Icons.tonality_rounded,
        accent: const Color(0xFFB48765),
      ),
      _ReportMetric(
        key: 'wrinkleScore',
        label: 'Wrinkle Score',
        rawValue: wrinkleScore,
        score: (10 - wrinkleScore).clamp(0.0, 10.0),
        displayValue: '${wrinkleScore.toStringAsFixed(1)} / 10',
        description: 'Fine lines and texture depth',
        status: _lowMidHigh(wrinkleScore, reverse: true),
        icon: Icons.auto_awesome_rounded,
        accent: const Color(0xFFD4AB6A),
      ),
      _ReportMetric(
        key: 'pigmentationScore',
        label: 'Pigmentation Score',
        rawValue: pigmentationScore,
        score: (10 - pigmentationScore).clamp(0.0, 10.0),
        displayValue: '${pigmentationScore.toStringAsFixed(1)} / 10',
        description: 'Tone variation and dark spot visibility',
        status: _lowMidHigh(pigmentationScore, reverse: true),
        icon: Icons.tonality_rounded,
        accent: const Color(0xFFC89B72),
      ),
      _ReportMetric(
        key: 'textureRoughness',
        label: 'Texture / Roughness',
        rawValue: texture,
        score: (10 - texture).clamp(0.0, 10.0),
        displayValue: texture.toStringAsFixed(1),
        description: 'Surface smoothness and uneven grain',
        status: _lowMidHigh(texture, reverse: true),
        icon: Icons.grain_rounded,
        accent: const Color(0xFFC697A8),
      ),
      _ReportMetric(
        key: 'acneSeverity',
        label: 'Acne / Breakout Severity',
        rawValue: acne,
        score: (10 - acne).clamp(0.0, 10.0),
        displayValue: acne.toStringAsFixed(1),
        description: 'Breakout load and active congestion',
        status: _lowMidHigh(acne, reverse: true),
        icon: Icons.healing_outlined,
        accent: const Color(0xFFCD836D),
      ),
      _ReportMetric(
        key: 'scarHealingProgress',
        label: 'Scar Healing Progress',
        rawValue: scarProgress,
        score: scarProgress,
        displayValue: '${scarProgress.toStringAsFixed(1)} / 10',
        description: 'Recovery trend across visible marks',
        status: _lowMidHigh(scarProgress),
        icon: Icons.timeline_rounded,
        accent: const Color(0xFFC9A975),
      ),
    ];

    const consumed = <String>{
      'hydrationLevel',
      'hydration',
      'waterRetention',
      'oiliness',
      'sebum',
      'oilLevel',
      'poreSize',
      'pores',
      'poresVisibility',
      'skinSensitivity',
      'sensitivity',
      'collagenScore',
      'elasticity',
      'firmness',
      'skinLaxityFirmness',
      'redness',
      'inflammation',
      'rosaceaSeverity',
      'erythema',
      'darkSpots',
      'pigmentation_score',
      'pigmentationScore',
      'pigmentation',
      'pigment',
      'postAcneScarring',
      'texture',
      'roughness',
      'skinTexture',
      'wrinkle_score',
      'wrinkleScore',
      'wrinkle',
      'wrinkles',
      'rhytids',
      'fineLines',
      'acneSeverity',
      'breakoutSeverity',
      'activeBreakouts',
      'acneCount',
      'scarHealingProgress',
      'overall_skin_score',
      'overallHealingScore',
      'scarringBruising',
      'overallSkinScore',
      'overall_score',
      'skinScore',
    };

    final extraEntries =
        numeric.entries.where((e) => !consumed.contains(e.key)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    for (final e in extraEntries.take(6)) {
      final value = e.value.clamp(0.0, 10.0);
      cards.add(
        _ReportMetric(
          key: e.key,
          label: _humanize(e.key),
          rawValue: value,
          score: value,
          displayValue: '${value.toStringAsFixed(1)} / 10',
          description: 'Custom tracked metric from backend output',
          status: 'Custom tracked metric',
          icon: Icons.tune_rounded,
          accent: const Color(0xFFB08A58),
        ),
      );
    }

    return _ReportBundle(
      overallScore: overall,
      overallBand: _overallBand(overall),
      metrics: cards,
    );
  }

  _CvSignals? _extractCvSignals(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    const int targetW = 144;
    final int targetH = math.max(
      96,
      (decoded.height * targetW / decoded.width).round(),
    );
    final sampled = img.copyResize(decoded, width: targetW, height: targetH);

    final w = sampled.width;
    final h = sampled.height;
    final x0 = (w * 0.12).round();
    final x1 = (w * 0.88).round();
    final y0 = (h * 0.10).round();
    final y1 = (h * 0.92).round();
    final cx = (x0 + x1) / 2.0;
    final cy = (y0 + y1) / 2.0;
    final rx = (x1 - x0) * 0.46;
    final ry = (y1 - y0) * 0.47;

    final luma = List<double>.filled(w * h, 0);
    int n = 0;
    double sumL = 0;
    double sumL2 = 0;
    double sumSat = 0;
    double sumRedness = 0;
    int oilySpecularCount = 0;

    bool inFaceMask(int x, int y) {
      final nx = (x - cx) / rx;
      final ny = (y - cy) / ry;
      return nx * nx + ny * ny <= 1.0;
    }

    for (int y = y0; y < y1; y++) {
      for (int x = x0; x < x1; x++) {
        if (!inFaceMask(x, y)) continue;
        final p = sampled.getPixel(x, y);
        final r = p.r.toDouble() / 255.0;
        final g = p.g.toDouble() / 255.0;
        final b = p.b.toDouble() / 255.0;
        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final delta = maxC - minC;
        final sat = maxC <= 0 ? 0.0 : delta / maxC;
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        final redness = (r - (g + b) * 0.5 + 0.2).clamp(0.0, 1.0);

        luma[y * w + x] = lum;
        sumL += lum;
        sumL2 += lum * lum;
        sumSat += sat;
        sumRedness += redness;
        if (lum > 0.76 && sat < 0.20) oilySpecularCount++;
        n++;
      }
    }

    if (n < 100) return null;

    final meanL = sumL / n;
    final varL = (sumL2 / n) - (meanL * meanL);
    final stdL = math.sqrt(math.max(0.0, varL));
    final meanSat = sumSat / n;
    final meanRedness = sumRedness / n;
    final specularFrac = oilySpecularCount / n;

    double edgeSum = 0;
    double diffSum = 0;
    int edgeN = 0;
    int highEdgeN = 0;
    for (int y = y0 + 1; y < y1 - 1; y++) {
      for (int x = x0 + 1; x < x1 - 1; x++) {
        if (!inFaceMask(x, y)) continue;
        final c = luma[y * w + x];
        final gx = luma[y * w + (x + 1)] - luma[y * w + (x - 1)];
        final gy = luma[(y + 1) * w + x] - luma[(y - 1) * w + x];
        final grad = math.sqrt(gx * gx + gy * gy);
        edgeSum += grad;
        if (grad > 0.11) highEdgeN++;

        final right = luma[y * w + (x + 1)];
        final down = luma[(y + 1) * w + x];
        diffSum += (c - right).abs() + (c - down).abs();
        edgeN++;
      }
    }

    if (edgeN == 0) return null;
    final edgeMean = edgeSum / edgeN;
    final edgeDensity = highEdgeN / edgeN;
    final roughnessNorm = (diffSum / (edgeN * 2) / 0.18).clamp(0.0, 1.0);
    final contrastNorm = (stdL / 0.24).clamp(0.0, 1.0);
    final edgeNorm = ((edgeMean - 0.04) / 0.24).clamp(0.0, 1.0);

    final hydrationNorm =
        (meanL * 0.54 + (1 - contrastNorm) * 0.24 + (1 - roughnessNorm) * 0.22)
            .clamp(0.0, 1.0);
    final oilinessNorm =
        (specularFrac * 0.55 + meanSat * 0.25 + edgeNorm * 0.20).clamp(
          0.0,
          1.0,
        );
    final poreNorm = (edgeDensity * 0.65 + roughnessNorm * 0.35).clamp(
      0.0,
      1.0,
    );
    final rednessNorm = (meanRedness * 0.72 + meanSat * 0.28).clamp(0.0, 1.0);
    final sensitivityNorm =
        (rednessNorm * 0.62 + contrastNorm * 0.20 + roughnessNorm * 0.18).clamp(
          0.0,
          1.0,
        );
    final collagenNorm =
        ((1 - roughnessNorm) * 0.62 + (1 - poreNorm) * 0.23 + meanL * 0.15)
            .clamp(0.0, 1.0);

    return _CvSignals(
      hydrationPercent: (hydrationNorm * 100).clamp(0.0, 100.0),
      hydrationScore: (hydrationNorm * 10).clamp(0.0, 10.0),
      oilinessPercent: (oilinessNorm * 100).clamp(0.0, 100.0),
      oilinessLevelScore: (oilinessNorm * 10).clamp(0.0, 10.0),
      poreVisibilityScore: (poreNorm * 10).clamp(0.0, 10.0),
      poreSizeMm: (0.14 + poreNorm * 0.20).clamp(0.10, 0.45),
      sensitivityScore: (sensitivityNorm * 10).clamp(0.0, 10.0),
      rednessScore: (rednessNorm * 10).clamp(0.0, 10.0),
      textureRoughnessScore: (roughnessNorm * 10).clamp(0.0, 10.0),
      collagenScore: (collagenNorm * 10).clamp(0.0, 10.0),
    );
  }

  List<String> _buildActionableRecommendations(_ReportBundle report) {
    final byKey = <String, _ReportMetric>{
      for (final m in report.metrics) m.key: m,
    };

    final tips = <String>[];
    final hydration = byKey['hydrationLevel']?.score ?? 6.6;
    if (hydration < 6.0) {
      tips.add(
        'Increase barrier hydration: use a hyaluronic acid serum followed by a ceramide-rich moisturizer morning and evening.',
      );
    }

    final sensitivity = 10 - (byKey['skinSensitivity']?.score ?? 6.9);
    if (sensitivity > 4.5) {
      tips.add(
        'Reduce irritation load for 7-10 days: pause exfoliants, use a fragrance-free routine, and prioritize soothing repair products.',
      );
    }

    final redness = 10 - (byKey['rednessInflammation']?.score ?? 6.7);
    if (redness > 4.5) {
      tips.add(
        'Support anti-redness recovery with daily SPF 50, cool-water cleansing, and anti-inflammatory actives like niacinamide or azelaic acid.',
      );
    }

    final acne = 10 - (byKey['acneSeverity']?.score ?? 7.1);
    if (acne > 4.0) {
      tips.add(
        'For breakout control, keep routine simple: non-comedogenic cleanser, targeted BHA at night, and avoid heavy occlusive layering in active zones.',
      );
    }

    if (tips.isEmpty) {
      tips.add(
        'Maintain your current routine consistency: daily SPF, gentle cleansing, nightly hydration, and weekly photo tracking under similar lighting.',
      );
      tips.add(
        'Continue collagen-supportive care with peptides, antioxidant protection, and sleep-recovery habits to preserve elasticity and tone.',
      );
    }

    tips.add(
      'Re-scan in 10-14 days with identical angle and lighting to confirm trend direction before making major routine changes.',
    );

    return tips.take(5).toList();
  }

  List<AIProductRecommendation> _buildProductRecommendationsFromReport(
    _ReportBundle report,
  ) {
    final byKey = <String, _ReportMetric>{
      for (final m in report.metrics) m.key: m,
    };

    double metric(String key, double fallback) => byKey[key]?.score ?? fallback;

    final skinMetrics = SkinMetrics(
      redness: (10 - metric('rednessInflammation', 6.5)).clamp(0.0, 10.0),
      texture: (10 - metric('textureRoughness', 6.0)).clamp(0.0, 10.0),
      wrinkle: (10 - metric('collagenScore', 7.0)).clamp(0.0, 10.0),
      pore: (10 - metric('poreSize', 6.0)).clamp(0.0, 10.0),
      darkSpots: (10 - metric('darkSpotsPigmentation', 6.0)).clamp(0.0, 10.0),
      elasticity: metric('collagenScore', 6.8).clamp(0.0, 10.0),
    );

    final cvContext = CvSkinMetricsContext(
      hydrationLevel: metric('hydrationLevel', 6.5),
      oilinessLevel:
          ((byKey['oiliness'] != null) ? (byKey['oiliness']!.score / 2.0) : 4.5)
              .clamp(0.0, 10.0),
      poreVisibility: (10 - metric('poreSize', 6.0)).clamp(0.0, 10.0),
      sensitivityLevel: (10 - metric('skinSensitivity', 6.8)).clamp(0.0, 10.0),
      rednessLevel: (10 - metric('rednessInflammation', 6.5)).clamp(0.0, 10.0),
      textureRoughness: (10 - metric('textureRoughness', 6.0)).clamp(0.0, 10.0),
      collagenElasticity: metric('collagenScore', 6.8).clamp(0.0, 10.0),
      poreSizeMm: _parsePoreSizeMm(byKey['poreSize']?.displayValue),
    );

    final concerns = <String>[];
    if ((cvContext.hydrationLevel ?? 10) < 5.8) concerns.add('dryness');
    if ((cvContext.oilinessLevel ?? 0) > 6.0) concerns.add('oiliness');
    if ((cvContext.sensitivityLevel ?? 0) > 5.8) concerns.add('sensitive');
    if ((cvContext.rednessLevel ?? 0) > 5.8) concerns.add('redness');
    if ((cvContext.textureRoughness ?? 0) > 5.8) concerns.add('texture');

    final resolvedProcedureType = (() {
      final candidates = <String?>[
        _stringValue(['procedure', 'procedure_type']),
        _stringValue(['scanProcedure', 'scan_procedure']),
        _stringValue(['selectedProcedureType', 'selected_procedure_type']),
        _stringValue(['analysisContextProcedureType']),
      ];
      for (final candidate in candidates) {
        final normalized = (candidate ?? '').trim();
        if (normalized.isNotEmpty && normalized.toLowerCase() != 'unknown') {
          return normalized;
        }
      }
      return 'General Skincare';
    })();
    AppLogger.verbose(
      '[SkinAiAnalysisScreen] resolvedProcedureType=$resolvedProcedureType',
    );

    return AIProductRecommendationEngine.generateRecommendations(
      skinMetrics,
      procedureType: resolvedProcedureType,
      maxRecommendations: 4,
      cvMetrics: cvContext,
      userSkinConcerns: concerns,
      recentProcedureTypes:
          resolvedProcedureType.toLowerCase() != 'general skincare'
          ? [resolvedProcedureType]
          : null,
    );
  }

  double? _parsePoreSizeMm(String? displayValue) {
    if (displayValue == null || displayValue.trim().isEmpty) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(displayValue);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  List<_TextItem> _extractTextItems(List<String> keys) {
    final items = <_TextItem>[];
    for (final key in keys) {
      final value = _body[key] ?? analysisResult[key];
      items.addAll(_parseTextItems(value));
    }
    final seen = <String>{};
    return items
        .where((item) {
          final sig = '${item.title}|${item.detail}';
          if (seen.contains(sig)) return false;
          seen.add(sig);
          return true;
        })
        .take(8)
        .toList();
  }

  List<_TextItem> _parseTextItems(dynamic value) {
    if (value == null) return const [];
    if (value is String && value.trim().isNotEmpty) {
      return [_TextItem('Observation', value.trim())];
    }
    if (value is List) {
      return value.expand(_parseTextItems).toList();
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.containsKey('title') ||
          map.containsKey('detail') ||
          map.containsKey('description')) {
        return [
          _TextItem(
            map['title']?.toString() ?? 'Observation',
            (map['detail'] ?? map['description'] ?? map['text'] ?? '')
                .toString(),
          ),
        ];
      }
      return map.entries
          .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
          .map(
            (e) => _TextItem(_humanize(e.key.toString()), e.value.toString()),
          )
          .toList();
    }
    return [_TextItem('Observation', value.toString())];
  }

  Map<String, dynamic>? _firstMap(List<String> keys) {
    for (final key in keys) {
      final value = _body[key] ?? analysisResult[key];
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String? _stringValue(List<String> keys) {
    for (final key in keys) {
      final value = _body[key] ?? analysisResult[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  double? _numericValue(List<String> keys) {
    for (final key in keys) {
      final value = _toNumber(_body[key] ?? analysisResult[key]);
      if (value != null) return value;
    }
    return null;
  }

  double? _toNumber(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    if (value is Map && value['score'] != null) {
      return _toNumber(value['score']);
    }
    return null;
  }

  String _humanize(String key) {
    final spaced = key
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .trim();
    if (spaced.isEmpty) return 'Metric';
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  String _overallBand(double score) {
    if (score >= 8.5) return 'Excellent';
    if (score >= 7.2) return 'Healthy';
    if (score >= 5.8) return 'Good';
    return 'Needs Attention';
  }

  List<_RecommendedProduct> _recommendedProducts() {
    final raw =
        _body['recommended_products'] ?? analysisResult['recommended_products'];
    if (raw is! List) return const [];

    final out = <_RecommendedProduct>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final brand = (map['brand'] ?? '').toString().trim();
      final name = (map['name'] ?? '').toString().trim();
      final price = (map['price'] ?? '').toString().trim();
      final reasonTag = (map['reason_tag'] ?? '').toString().trim();
      final affiliateUrl = (map['affiliate_url'] ?? '').toString().trim();
      if (brand.isEmpty || name.isEmpty || affiliateUrl.isEmpty) continue;
      out.add(
        _RecommendedProduct(
          brand: brand,
          name: name,
          price: price.isEmpty ? 'See details' : price,
          reasonTag: reasonTag.isEmpty ? 'Recommended' : reasonTag,
          affiliateUrl: affiliateUrl,
        ),
      );
    }
    return out;
  }

  String _hydrationBand(double score) {
    if (score >= 7.6) return 'Well Hydrated';
    if (score >= 5.8) return 'Normal';
    return 'Low Hydration';
  }

  String _oilBand(double rawOilScore) {
    if (rawOilScore >= 3.5 && rawOilScore <= 6.0) return 'Balanced';
    if (rawOilScore < 3.5) return 'Dry-leaning';
    return 'Oil-leaning';
  }

  String _poreBand(double score) {
    if (score <= 3.0) return 'Refined';
    if (score <= 5.5) return 'Average';
    return 'Visible';
  }

  String _lowMidHigh(double score, {bool reverse = false}) {
    final s = score.clamp(0.0, 10.0);
    if (reverse) {
      if (s <= 3.3) return 'Low';
      if (s <= 6.6) return 'Moderate';
      return 'High';
    }
    if (s >= 7.0) return 'Strong';
    if (s >= 4.5) return 'Moderate';
    return 'Low';
  }

  Color _scoreAccent(double score) {
    if (score >= 8.5) return const Color(0xFFB68A4E);
    if (score >= 7.0) return const Color(0xFFC29560);
    if (score >= 5.5) return const Color(0xFFBD7C85);
    return const Color(0xFFC76A55);
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: MyApp.clinicalSlate.withValues(alpha: 0.15),
      width: 0.6,
    ),
    boxShadow: [
      BoxShadow(
        color: MyApp.clinicalNavy.withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

class _TextItem {
  final String title;
  final String detail;

  const _TextItem(this.title, this.detail);
}

class _ReportBundle {
  final double overallScore;
  final String overallBand;
  final List<_ReportMetric> metrics;

  const _ReportBundle({
    required this.overallScore,
    required this.overallBand,
    required this.metrics,
  });
}

class _ReportMetric {
  final String key;
  final String label;
  final double rawValue;
  final String displayValue;
  final String description;
  final String status;
  final double score;
  final IconData icon;
  final Color accent;

  const _ReportMetric({
    required this.key,
    required this.label,
    required this.rawValue,
    required this.displayValue,
    required this.description,
    required this.status,
    required this.score,
    required this.icon,
    required this.accent,
  });
}

class _CvSignals {
  final double hydrationPercent;
  final double hydrationScore;
  final double oilinessPercent;
  final double oilinessLevelScore;
  final double poreVisibilityScore;
  final double poreSizeMm;
  final double sensitivityScore;
  final double rednessScore;
  final double textureRoughnessScore;
  final double collagenScore;

  const _CvSignals({
    required this.hydrationPercent,
    required this.hydrationScore,
    required this.oilinessPercent,
    required this.oilinessLevelScore,
    required this.poreVisibilityScore,
    required this.poreSizeMm,
    required this.sensitivityScore,
    required this.rednessScore,
    required this.textureRoughnessScore,
    required this.collagenScore,
  });
}

class _RecommendedProduct {
  const _RecommendedProduct({
    required this.brand,
    required this.name,
    required this.price,
    required this.reasonTag,
    required this.affiliateUrl,
  });

  final String brand;
  final String name;
  final String price;
  final String reasonTag;
  final String affiliateUrl;
}

/// Calm, premium scanning indicator: a gold core with expanding concentric
/// pulse rings, a rotating sweep arc, and orbiting particle glints. Used in
/// the analyzing stage to make AI processing feel expensive and unhurried.
class _LuxeScanningIndicator extends StatefulWidget {
  const _LuxeScanningIndicator();

  @override
  State<_LuxeScanningIndicator> createState() => _LuxeScanningIndicatorState();
}

class _LuxeScanningIndicatorState extends State<_LuxeScanningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 152,
      height: 152,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ScanPulsePainter(
              progress: _controller.value,
              gold: AppColors.champagneGold,
            ),
            child: Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.champagneGold,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.champagneGold.withValues(alpha: 0.45),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.onChampagneGold,
                  size: 26,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Animated concentric pulse + rotating sweep + orbiting particles for the
/// [_LuxeScanningIndicator]. Purely decorative.
class _ScanPulsePainter extends CustomPainter {
  final double progress;
  final Color gold;

  _ScanPulsePainter({required this.progress, required this.gold});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    const twoPi = math.pi * 2;

    // Expanding concentric pulse rings.
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = 30 + t * (maxRadius - 30);
      final opacity = ((1 - t) * 0.5).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = gold.withValues(alpha: opacity),
      );
    }

    // Faint static guide ring.
    canvas.drawCircle(
      center,
      maxRadius - 6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = gold.withValues(alpha: 0.12),
    );

    // Rotating sweep arc.
    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius - 6);
    canvas.drawArc(
      sweepRect,
      progress * twoPi,
      1.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [gold.withValues(alpha: 0.0), gold.withValues(alpha: 0.9)],
          transform: GradientRotation(progress * twoPi),
        ).createShader(sweepRect),
    );

    // Orbiting particle glints.
    for (var i = 0; i < 6; i++) {
      final angle = progress * twoPi + i * (twoPi / 6);
      final r = maxRadius - 18;
      final dot = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      final dotOpacity = (0.25 + 0.55 * ((math.sin(angle * 2) + 1) / 2)).clamp(
        0.0,
        1.0,
      );
      canvas.drawCircle(
        dot,
        2.2,
        Paint()..color = gold.withValues(alpha: dotOpacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScanPulsePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Static gold "scan target" overlay: corner brackets plus faint concentric
/// guide rings, with an optional animated expanding [pulse] ring. Layered over
/// the selected photo preview and the empty photo placeholder to give the
/// capture flow a calibrated, clinical-luxury feel.
class _ScanFramePainter extends CustomPainter {
  final Color color;
  final Color ringColor;
  final double? pulse;

  _ScanFramePainter({required this.color, required this.ringColor, this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 14.0;
    const len = 22.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = color;

    final w = size.width;
    final h = size.height;

    // Top-left.
    canvas.drawLine(
      const Offset(inset, inset),
      const Offset(inset + len, inset),
      paint,
    );
    canvas.drawLine(
      const Offset(inset, inset),
      const Offset(inset, inset + len),
      paint,
    );
    // Top-right.
    canvas.drawLine(
      Offset(w - inset, inset),
      Offset(w - inset - len, inset),
      paint,
    );
    canvas.drawLine(
      Offset(w - inset, inset),
      Offset(w - inset, inset + len),
      paint,
    );
    // Bottom-left.
    canvas.drawLine(
      Offset(inset, h - inset),
      Offset(inset + len, h - inset),
      paint,
    );
    canvas.drawLine(
      Offset(inset, h - inset),
      Offset(inset, h - inset - len),
      paint,
    );
    // Bottom-right.
    canvas.drawLine(
      Offset(w - inset, h - inset),
      Offset(w - inset - len, h - inset),
      paint,
    );
    canvas.drawLine(
      Offset(w - inset, h - inset),
      Offset(w - inset, h - inset - len),
      paint,
    );

    // Concentric guide rings.
    final center = Offset(w / 2, h / 2);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ringColor;
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, 16.0 * i, ringPaint);
    }

    // Animated expanding pulse ring + orbiting glints when a pulse value is
    // supplied (used by the empty-state placeholder).
    final p = pulse;
    if (p != null) {
      const twoPi = math.pi * 2;
      final t = p % 1.0;
      final radius = 16 + t * 54;
      final opacity = ((1 - t) * 0.55).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = ringColor.withValues(alpha: opacity),
      );
      for (var i = 0; i < 6; i++) {
        final angle = p * twoPi + i * (twoPi / 6);
        const orbit = 44.0;
        final dot = Offset(
          center.dx + orbit * math.cos(angle),
          center.dy + orbit * math.sin(angle),
        );
        final glint = (0.25 + 0.5 * ((math.sin(angle * 2) + 1) / 2)).clamp(
          0.0,
          1.0,
        );
        canvas.drawCircle(
          dot,
          1.8,
          Paint()..color = ringColor.withValues(alpha: glint),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.pulse != pulse;
}

/// Empty-state capture target: an animated, softly glowing gold scan frame with
/// a breathing border, pulse ring and orbiting glints. Shown before a photo is
/// selected to make the capture step feel premium and alive.
class _PulsingScanFrame extends StatefulWidget {
  const _PulsingScanFrame();

  @override
  State<_PulsingScanFrame> createState() => _PulsingScanFrameState();
}

class _PulsingScanFrameState extends State<_PulsingScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glow = 0.5 + 0.5 * math.sin(_controller.value * math.pi * 2);
        return Container(
          height: 178,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.warmAlabaster,
                AppColors.champagneGold.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.champagneGold.withValues(
                alpha: 0.45 + 0.35 * glow,
              ),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.champagneGold.withValues(
                  alpha: 0.12 + 0.18 * glow,
                ),
                blurRadius: 18 + 12 * glow,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScanFramePainter(
                      color: AppColors.champagneGold.withValues(
                        alpha: 0.6 + 0.3 * glow,
                      ),
                      ringColor: AppColors.champagneGold.withValues(alpha: 0.5),
                      pulse: _controller.value,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.champagneGold.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.5 + 0.3 * glow,
                          ),
                          width: 1.2,
                        ),
                      ),
                      child: const Icon(
                        Icons.add_a_photo_outlined,
                        size: 24,
                        color: AppColors.goldHover,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Add a clear face photo',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.refinedSlate,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Good lighting · neutral expression · no makeup if possible',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.refinedSlate.withValues(alpha: 0.74),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
