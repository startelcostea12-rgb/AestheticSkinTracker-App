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

import 'dart:convert' show base64Decode, base64Encode, jsonEncode, utf8;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
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
import 'package:aesthetic_skin_tracker/utils/ai_capture_sharpness.dart';
import 'package:aesthetic_skin_tracker/utils/display_aggregation.dart';
import 'package:aesthetic_skin_tracker/utils/ai/skin_analysis_model.dart';
import 'package:aesthetic_skin_tracker/utils/ai/skin_analysis_runner.dart';
import 'package:aesthetic_skin_tracker/utils/ai/skin_detections.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/upload_gate.dart';
import 'package:aesthetic_skin_tracker/utils/free_scan_limit.dart';
import 'package:aesthetic_skin_tracker/widgets/consistent_setup_guide.dart';
import 'package:aesthetic_skin_tracker/widgets/gray_card_sample_card.dart';
import 'package:aesthetic_skin_tracker/utils/untrusted_trend_metrics.dart';
import 'package:aesthetic_skin_tracker/utils/comparable_pair_pdf.dart';
import 'package:aesthetic_skin_tracker/utils/last_comparable_pair.dart';
import 'package:aesthetic_skin_tracker/widgets/scan_note_field.dart';
import 'package:aesthetic_skin_tracker/utils/protocol_checklist.dart';
import 'package:aesthetic_skin_tracker/widgets/lighting_tip_card.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_mode.dart';
import 'package:aesthetic_skin_tracker/widgets/paywall_screen.dart';
import 'free_local_scan_results_screen.dart';
import 'package:aesthetic_skin_tracker/utils/gray_card_region.dart';
import 'package:aesthetic_skin_tracker/utils/backend_config.dart';
import 'package:aesthetic_skin_tracker/utils/skin_analysis_service.dart'
    as remote_analysis;
import 'package:aesthetic_skin_tracker/utils/procedure_intelligence.dart'
    as procedure_intel;
import 'package:aesthetic_skin_tracker/utils/trend_label_resolver.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:aesthetic_skin_tracker/widgets/clinical_section_header.dart';
import 'package:aesthetic_skin_tracker/widgets/image_crop_dialog.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:aesthetic_skin_tracker/widgets/skin_heatmap_overlay.dart';
import 'package:aesthetic_skin_tracker/widgets/smart_narrative_container.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';

class SkinAiAnalysisScreen extends StatefulWidget {
  const SkinAiAnalysisScreen({super.key});

  @override
  State<SkinAiAnalysisScreen> createState() => _SkinAiAnalysisScreenState();
}

enum _Stage { capture, analyzing, results }

enum _DebugExportAction { setupGuide, burstLog, scanData, comparisonPdf }

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

Map<String, dynamic> aiBaselineMetricMatrixFromPayload(
  Map<String, dynamic> payload,
) {
  const canonicalKeys = <String>{
    'a_p95',
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
  final metrics = _dynamicMap(payload['metrics']);
  final luxePayload = _dynamicMap(payload['luxePayload']);
  final luxeMetrics = _dynamicMap(luxePayload['metrics']);
  final matrixSources = <dynamic>[
    payload['metric_matrix'],
    metrics['metric_matrix'],
    luxePayload['metric_matrix'],
    luxeMetrics['metric_matrix'],
  ];
  final result = <String, dynamic>{};

  for (final source in matrixSources) {
    final matrix = _dynamicMap(source);
    for (final entry in matrix.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      if (!canonicalKeys.contains(key) || result.containsKey(key)) continue;
      final value = entry.value;
      final numeric = value is num
          ? value.toDouble()
          : double.tryParse(value.toString());
      if (numeric == null || !numeric.isFinite || numeric < 0.0) continue;
      result[key] = numeric;
    }
  }

  return result;
}

Map<String, dynamic>? _asPlainMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

/// Metrics the live results views (the main results card and
/// SkinAiAnalysisResultsScreen) do not render. They are still computed,
/// saved, and exported; Track Procedure, history, and the progress report
/// are unaffected.
const Set<String> liveResultsHiddenMetricKeys = <String>{
  'pore_contraction_index',
};

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

/// The baseline extraction paths sent with a follow-up scan, read from the
/// baseline scan's stored [rawPayload]. Older metrics default to 'unknown'
/// when no path was stored. The under-eye metrics send only a path the
/// baseline actually stored; a missing one stays missing.
Map<String, String> aiBaselineExtractionPathsForRequest(
  Map<String, dynamic>? rawPayload,
) {
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
  const storedOnlyKeys = <String>{
    'under_eye_texture_density',
    'under_eye_dark_circle_density',
  };

  final out = <String, String>{for (final key in canonicalKeys) key: 'unknown'};

  if (rawPayload == null || rawPayload.isEmpty) {
    return out;
  }

  void mergePathSource(dynamic source) {
    final map = _asPlainMap(source);
    if (map == null || map.isEmpty) return;
    for (final entry in map.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      if (storedOnlyKeys.contains(key)) {
        final path = preservedAiExtractionPath(entry.value);
        if (path != null) out[key] = path;
        continue;
      }
      if (!canonicalKeys.contains(key)) continue;
      out[key] = preservedAiExtractionPath(entry.value) ?? 'unknown';
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
  final payload = scan.rawPayload ?? const <String, dynamic>{};
  final cardQuality = _dynamicMap(payload['image_quality']);
  if (payload['gray_card_baseline_eligible'] == false ||
      cardQuality['gray_card_baseline_eligible'] == false) {
    return 'Not saved as baseline: ${cardQuality['gray_card_message'] ?? payload['gray_card_message'] ?? 'the gray card could not be used. Please retake.'}';
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
  int? sourceImageWidth,
  int? sourceImageHeight,
  int? baselineSourceImageWidth,
  int? baselineSourceImageHeight,
  ({double x, double y, double w, double h})? grayCardRegion,
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
    if (sourceImageWidth != null && sourceImageWidth > 0)
      'source_image_width': '$sourceImageWidth',
    if (sourceImageHeight != null && sourceImageHeight > 0)
      'source_image_height': '$sourceImageHeight',
    if (baselineSourceImageWidth != null && baselineSourceImageWidth > 0)
      'baseline_source_image_width': '$baselineSourceImageWidth',
    if (baselineSourceImageHeight != null && baselineSourceImageHeight > 0)
      'baseline_source_image_height': '$baselineSourceImageHeight',
    // Optional gray-card white balance: the marked box as fractions of the
    // full still (logged and exported; the card's pixels travel separately
    // as gray_card_image). Omitted unless a card was marked.
    if (grayCardRegion != null)
      'gray_card_still_region': jsonEncode({
        'x': grayCardRegion.x,
        'y': grayCardRegion.y,
        'w': grayCardRegion.w,
        'h': grayCardRegion.h,
      }),
  };
}

Map<String, int> aiScanSourceResolutionMetadata(Map<String, String> fields) {
  final metadata = <String, int>{};
  for (final key in const [
    'source_image_width',
    'source_image_height',
    'baseline_source_image_width',
    'baseline_source_image_height',
  ]) {
    final value = int.tryParse(fields[key] ?? '');
    if (value != null && value > 0) metadata[key] = value;
  }
  return metadata;
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

/// Leaves the current screen for HomePage. Pops back to the `/home` route
/// when it is in the stack. The bottom navigation opens Routines / Procedure
/// History / Profile with pushReplacement, so the first route is not always
/// HomePage -- popping "to the first route" alone used to land on that
/// screen (e.g. the procedure/peptide picker). When HomePage isn't in the
/// stack, the stack is replaced with a fresh `/home`.
void navigateHomeFrom(NavigatorState navigator) {
  var reachedHome = false;
  navigator.popUntil((route) {
    if (route.settings.name == '/home') {
      reachedHome = true;
      return true;
    }
    return route.isFirst;
  });
  if (!reachedHome) {
    navigator.pushNamedAndRemoveUntil('/home', (_) => false);
  }
}

/// Metrics whose trend verdict is never kept: the number is saved and
/// exported, but trend_status and trend_deltas are dropped, so neither the
/// card nor the scan-data export shows improved/worsened/stable or a
/// percent. A lock reason is still kept, so a locked one shows "Not
/// comparable".
const Set<String> untrustedTrendVerdictMetricKeys =
    untrustedTrendVerdictMetrics;

/// Where the gray-card box was drawn, as logged by main.py: the space
/// ("full_still" for an uploaded patch) and the box as fractions of it.
const List<String> grayCardRegionFields = <String>[
  'gray_card_region_space',
  'gray_card_region_x',
  'gray_card_region_y',
  'gray_card_region_w',
  'gray_card_region_h',
];

/// Scan-level gray-card summary over the frames' image_quality (main.py
/// logs it per frame): marked if any frame was marked, correction applied
/// only if a strict majority of readable frames applied it, and the mean of the frames' raw card
/// samples. Empty when no frame reports gray-card fields (older backend).
Map<String, dynamic> summarizeGrayCardFrames(
  List<Map<String, dynamic>> responses,
) {
  final qualities = [
    for (final response in responses)
      _dynamicMap(response['image_quality']).isNotEmpty
          ? _dynamicMap(response['image_quality'])
          : _dynamicMap(_dynamicMap(response['metrics'])['image_quality']),
  ].where((q) => q.containsKey('gray_card_marked')).toList();
  if (qualities.isEmpty) return const <String, dynamic>{};

  double? mean(String key) {
    final values = [
      for (final q in qualities)
        if (q[key] is num && (q[key] as num).isFinite)
          (q[key] as num).toDouble(),
    ];
    if (values.isEmpty) return null;
    final average = values.reduce((a, b) => a + b) / values.length;
    return double.parse(average.toStringAsFixed(3));
  }

  final applied = qualities
      .where((q) => q['gray_card_correction_applied'] == true)
      .length;
  final read = qualities
      .where(
        (q) =>
            q['gray_card_correction_applied'] == true ||
            (q['gray_card_mean_L'] is num &&
                (q['gray_card_mean_L'] as num).isFinite &&
                q['gray_card_mean_a'] is num &&
                (q['gray_card_mean_a'] as num).isFinite &&
                q['gray_card_mean_b'] is num &&
                (q['gray_card_mean_b'] as num).isFinite),
      )
      .length;
  final marked = qualities.any((q) => q['gray_card_marked'] == true);
  final majority = applied > 0 && applied * 2 > read;
  final partial = applied > 0 && !majority;
  final reason = qualities
      .map((q) => q['gray_card_reason'])
      .firstWhere(
        (r) => r != null && r.toString().isNotEmpty,
        orElse: () => null,
      );
  final status = !marked
      ? 'not_marked'
      : majority
      ? 'applied'
      : partial
      ? 'partial'
      : switch (reason) {
          'implausible_card_color' => 'rejected_wrong_area',
          'disagrees_with_scene' => 'rejected_scene_mismatch',
          'implausible_exposure' => 'rejected_bad_exposure',
          _ => 'rejected_unreadable',
        };
  final rejectedQuality = qualities.firstWhere(
    (q) => q['gray_card_reason'] == reason,
    orElse: () => const <String, dynamic>{},
  );
  return <String, dynamic>{
    'gray_card_marked': marked,
    'gray_card_mean_L': mean('gray_card_mean_L'),
    'gray_card_mean_a': mean('gray_card_mean_a'),
    'gray_card_mean_b': mean('gray_card_mean_b'),
    'gray_card_chroma_offset': mean('gray_card_chroma_offset'),
    'gray_card_scene_disagreement': mean('gray_card_scene_disagreement'),
    'gray_card_correction_applied': majority,
    'gray_card_frames_applied': applied,
    'gray_card_frames_read': read,
    'gray_card_status': status,
    'gray_card_message': partial
        ? 'The gray card was not steady across the burst. Please retake with the card held steady.'
        : majority || !marked
        ? null
        : rejectedQuality['gray_card_message'],
    'gray_card_retake_recommended': marked && !majority,
    'gray_card_baseline_eligible': !marked || majority,
    'gray_card_reason': majority ? null : reason,
    // The same box is sent with every frame; take the first frame's.
    for (final field in grayCardRegionFields)
      field: qualities
          .map((q) => q[field])
          .firstWhere((v) => v != null, orElse: () => null),
  };
}

/// Frames the AI scan captures and uploads per scan.
const int aiScanCaptureFrameCount = 5;

/// Every metric except [fiveFrameMedianMetricKeys] is combined from the
/// first this-many captured frames only, exactly as before five frames were
/// captured.
const int standardMetricFrameCount = 3;

/// Noisy metrics combined as the median of five frames, emitted only when
/// all five frames produced a value (main.py bumped their formula versions
/// for this: wrinkle_load v4, pore_contraction_index v3, under-eye v5).
const Set<String> fiveFrameMedianMetricKeys = <String>{
  'wrinkle_load',
  'pore_contraction_index',
  'under_eye_dark_circle_density',
  'under_eye_texture_density',
};

double _medianOf(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2.0;
}

/// [frameNumbers], when given, is each response's 1-based capture frame
/// number (parallel to [responses]); otherwise responses are taken as
/// frames 1, 2, 3, ... in order.
MultiFrameAnalysisAggregate averageBackendAnalysisFrames(
  List<Map<String, dynamic>> responses, {
  required int requestedFrames,
  List<int>? frameNumbers,
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

  for (
    var responseIndex = 0;
    responseIndex < responses.length;
    responseIndex++
  ) {
    final response = responses[responseIndex];
    final frameNumber =
        frameNumbers != null && responseIndex < frameNumbers.length
        ? frameNumbers[responseIndex]
        : responseIndex + 1;
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
      // Standard metrics keep the three-frame path: frames 4+ only feed
      // fiveFrameMedianMetricKeys.
      if (frameNumber > standardMetricFrameCount &&
          !fiveFrameMedianMetricKeys.contains(entry.key)) {
        continue;
      }
      frameMetrics[entry.key] = numeric;
    }
    if (frameMetrics.isEmpty) continue;
    successfulResponses.add(response);
    final frameIndex = successfulResponses.length - 1;
    for (final entry in frameMetrics.entries) {
      samples.putIfAbsent(entry.key, () => <double>[]).add(entry.value);
      sampleFrameIndices.putIfAbsent(entry.key, () => <int>[]).add(frameIndex);
      final confidence = confidenceForMetric(response, metricsNode, entry.key);
      if (confidence != null) {
        confidenceSamples
            .putIfAbsent(entry.key, () => <Object>[])
            .add(confidence);
      }
    }
  }

  if (successfulResponses.isEmpty || samples.isEmpty) {
    throw StateError('No captured frame produced usable backend metrics.');
  }

  final averagedMatrix = <String, double>{};
  final contributorCounts = <String, int>{};
  final metricRanges = <String, Map<String, num>>{};
  final fiveFrameMedianOmitted = <String>[];
  for (final entry in samples.entries) {
    if (fiveFrameMedianMetricKeys.contains(entry.key)) {
      // Median of five; omitted unless all five frames produced a value.
      if (entry.value.length < aiScanCaptureFrameCount) {
        fiveFrameMedianOmitted.add(entry.key);
        continue;
      }
      averagedMatrix[entry.key] = _medianOf(entry.value);
    } else {
      averagedMatrix[entry.key] =
          entry.value.reduce((a, b) => a + b) / entry.value.length;
    }
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
  // Metrics whose contributing frames reported different trend statuses,
  // so no verdict was kept -- recorded so the card can say why.
  final trendStatusDisagreements = <String>[];
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
    // A verdict is kept only when every frame that contributed a value for
    // this metric reports the same trend status. If they disagree, the
    // averaged number is still shown, with no status and no percent -- the
    // status is never recomputed from the mean. Untrusted metrics never
    // keep a verdict at all (see untrustedTrendVerdictMetricKeys).
    final frameStatuses = <String?>{
      for (final index in indices)
        _perFrameTrendNode(
          successfulResponses[index],
          _dynamicMap(successfulResponses[index]['metrics']),
          'trend_status',
        )[key]?.toString().trim().toLowerCase(),
    };
    final keepVerdict =
        frameStatuses.length == 1 &&
        !untrustedTrendVerdictMetricKeys.contains(key);
    if (frameStatuses.length > 1 &&
        !untrustedTrendVerdictMetricKeys.contains(key)) {
      trendStatusDisagreements.add(key);
    }
    final status = _perFrameTrendNode(
      nearestResponse,
      nearestMetricsNode,
      'trend_status',
    )[key];
    if (status != null && keepVerdict) resolvedTrendStatus[key] = status;
    final delta = _perFrameTrendNode(
      nearestResponse,
      nearestMetricsNode,
      'trend_deltas',
    )[key];
    if (delta != null && keepVerdict) resolvedTrendDeltas[key] = delta;
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

  if (averagedMatrix.containsKey('pore_visibility')) {
    resolvedExtractionPaths['pore_visibility'] = 'primary_roi';
  } else {
    const poreOmissionPaths = {'pose', 'dog_spread', 'crop', 'skipped'};
    for (final response in responses) {
      final metricsNode = _dynamicMap(response['metrics']);
      final path = _perFrameTrendNode(
        response,
        metricsNode,
        'metric_extraction_paths',
      )['pore_visibility']?.toString();
      if (path != null && poreOmissionPaths.contains(path)) {
        resolvedExtractionPaths['pore_visibility'] = path;
        break;
      }
    }
    resolvedExtractionPaths.putIfAbsent('pore_visibility', () => 'skipped');
  }

  // Any other metric no frame produced a value for keeps the backend's own
  // 'skipped' path, as pore_visibility does above, instead of dropping out
  // and being saved later as 'unknown'.
  for (final response in responses) {
    final metricsNode = _dynamicMap(response['metrics']);
    final paths = _perFrameTrendNode(
      response,
      metricsNode,
      'metric_extraction_paths',
    );
    for (final entry in paths.entries) {
      if (averagedMatrix.containsKey(entry.key)) continue;
      if (entry.value?.toString() != 'skipped') continue;
      resolvedExtractionPaths.putIfAbsent(entry.key, () => 'skipped');
    }
  }

  // A median-of-five metric without five values is not emitted at all:
  // never fall back to a frame's own value, and record it as skipped.
  for (final key in fiveFrameMedianOmitted) {
    resolvedExtractionPaths[key] = 'skipped';
  }

  final first = successfulResponses.first;
  final response = Map<String, dynamic>.from(first);
  final metricsNode = Map<String, dynamic>.from(_dynamicMap(first['metrics']));
  for (final key in fiveFrameMedianOmitted) {
    response.remove(key);
    metricsNode.remove(key);
  }
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
  final grayCardSummary = summarizeGrayCardFrames(successfulResponses);
  if (grayCardSummary.isNotEmpty) {
    final firstQuality = _dynamicMap(first['image_quality']).isNotEmpty
        ? _dynamicMap(first['image_quality'])
        : _dynamicMap(_dynamicMap(first['metrics'])['image_quality']);
    response['image_quality'] = <String, dynamic>{
      ...firstQuality,
      ...grayCardSummary,
    };
    metricsNode['image_quality'] = response['image_quality'];
    for (final key in const [
      'gray_card_status',
      'gray_card_message',
      'gray_card_retake_recommended',
      'gray_card_baseline_eligible',
      'gray_card_correction_applied',
      'gray_card_frames_applied',
      'gray_card_frames_read',
    ]) {
      response[key] = grayCardSummary[key];
      metricsNode[key] = grayCardSummary[key];
    }
  }
  response['multi_frame_analysis'] = <String, dynamic>{
    'requested_frames': requestedFrames,
    'successful_frames': successfulResponses.length,
    'metric_contributor_counts': contributorCounts,
    if (trendStatusDisagreements.isNotEmpty)
      'trend_status_disagreements': trendStatusDisagreements,
    'metric_frame_values': <String, List<double>>{
      for (final entry in samples.entries)
        entry.key: List<double>.unmodifiable(entry.value),
    },
    'metric_ranges': metricRanges,
    if (fiveFrameMedianOmitted.isNotEmpty)
      'five_frame_median_omitted': fiveFrameMedianOmitted..sort(),
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

/// Per-metric noise floors measured from same-lamp repeat pairs, in each
/// metric's own 0-100 points. A move strictly below its floor is reported
/// as "stable" (see [forceStableWithinMeasuredNoiseFloors]). Separate from
/// the backend's METRIC_NOISE_FLOOR_2SD and from the live cards'
/// displayVerdictNoiseFloors.
const Map<String, double> measuredStableNoiseFloors = <String, double>{
  'texture_smoothness': 2.5,
  'pigment_load': 3.0,
  'skin_tone_radiance_evenness': 4.0,
  'pore_visibility': 3.0,
  'structural_firmness_elasticity': 2.0,
};

/// For the metrics in [measuredStableNoiseFloors]: when the averaged value's
/// absolute change from the baseline is strictly below that metric's floor,
/// the trend status becomes "stable" and its delta 0.0, so no percentage is
/// shown. Locks take priority: a metric with any lock reason, or an
/// "insufficient_signal" status, is left exactly as it is, and a metric
/// with no status or missing values is untouched. Every other metric is
/// unchanged.
({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, String> trendLockReasons,
})
forceStableWithinMeasuredNoiseFloors({
  required Map<String, String> trendStatus,
  required Map<String, double> trendDeltas,
  required Map<String, String> trendLockReasons,
  required Map<String, dynamic> averagedMetricMatrix,
  required Map<String, dynamic> baselineMetricMatrix,
}) {
  final updatedStatus = Map<String, String>.from(trendStatus);
  final updatedDeltas = Map<String, double>.from(trendDeltas);
  for (final entry in measuredStableNoiseFloors.entries) {
    final key = entry.key;
    final status = trendStatus[key]?.trim().toLowerCase();
    if (status == null || status == 'insufficient_signal') continue;
    if (trendLockReasons[key]?.trim().isNotEmpty ?? false) continue;
    final current = _parseFiniteDouble(averagedMetricMatrix[key]);
    final baseline = _parseFiniteDouble(baselineMetricMatrix[key]);
    if (current == null || baseline == null) continue;
    if ((current - baseline).abs() < entry.value) {
      updatedStatus[key] = 'stable';
      updatedDeltas[key] = 0.0;
    }
  }
  return (
    trendStatus: updatedStatus,
    trendDeltas: updatedDeltas,
    trendLockReasons: Map<String, String>.from(trendLockReasons),
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

/// rawPayload flag: true when the redness cheek_mismatch lock was skipped
/// because one scan read a single cheek ("left"/"right"), the other read
/// "both", and both localized_redness values were at or below
/// [rednessCheekLockLowValueCeiling]. False otherwise.
const String rednessCheekLockSkippedLowValuesKey =
    'redness_cheek_lock_skipped_low_values';

/// rawPayload flag: true when the redness region_mismatch lock was skipped
/// because one scan read a single-cheek region (left_cheek/right_cheek),
/// the other read u_zone, and both localized_redness values were at or
/// below [rednessCheekLockLowValueCeiling]. False otherwise.
const String rednessRegionLockSkippedLowValuesKey =
    'redness_region_lock_skipped_low_values';

/// Redness values at or below this are treated as low enough that a
/// single-cheek vs both-cheeks reading difference is not a cheek_mismatch.
const double rednessCheekLockLowValueCeiling = 5.0;

/// A single-cheek ("left"/"right") reading on one scan and a both-cheeks
/// reading on the other is not a cheek_mismatch when the two
/// localized_redness values differ by at most this much: the readings agree,
/// so the side difference did not change the result.
const double rednessCheekLockMatchingValueTolerance = 1.0;

/// image_quality.redness_branch for a follow-up whose redness is read over
/// the whole U-zone against the baseline p95 (side "both"); the cheek lock
/// is not applied when either scan used it.
const String rednessBranchBaselineP95Anchor = 'baseline_p95_anchor';
const String cheekSideConventionSubjectAnatomical = 'subject_anatomical';
const double provisionalBrightnessValueMismatchLimit = 1.0;

({double? iso, double? brightnessValue}) _representativeScanExposure(
  Map<String, dynamic> payload,
) {
  final rawFrames = payload[aiScanPerFrameDiagnosticsKey];
  if (rawFrames is! List) return (iso: null, brightnessValue: null);

  final isoValues = <double>[];
  final brightnessValues = <double>[];
  for (final rawFrame in rawFrames) {
    final frame = _dynamicMap(rawFrame);
    final iso = _parseFiniteDouble(frame['iso']);
    final brightness = _parseFiniteDouble(frame['brightness_value']);
    if (iso != null) isoValues.add(iso);
    if (brightness != null) brightnessValues.add(brightness);
  }

  double? median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2.0;
  }

  return (iso: median(isoValues), brightnessValue: median(brightnessValues));
}

({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, String> trendLockReasons,
})
lockTrendsForLightingMismatch({
  required Map<String, String> trendStatus,
  required Map<String, double> trendDeltas,
  required Map<String, String> trendLockReasons,
  required Map<String, dynamic> currentPayload,
  required Map<String, dynamic> baselinePayload,
}) {
  final current = _representativeScanExposure(currentPayload);
  final baseline = _representativeScanExposure(baselinePayload);
  final missingExposure =
      current.iso == null ||
      current.brightnessValue == null ||
      baseline.iso == null ||
      baseline.brightnessValue == null;
  final brightnessMismatch =
      !missingExposure &&
      (current.brightnessValue! - baseline.brightnessValue!).abs() >
          provisionalBrightnessValueMismatchLimit;
  if (!missingExposure && !brightnessMismatch) {
    return (
      trendStatus: Map<String, String>.from(trendStatus),
      trendDeltas: Map<String, double>.from(trendDeltas),
      trendLockReasons: Map<String, String>.from(trendLockReasons),
    );
  }

  final updatedStatus = Map<String, String>.from(trendStatus);
  final updatedDeltas = Map<String, double>.from(trendDeltas);
  final updatedLockReasons = Map<String, String>.from(trendLockReasons);
  for (final metricKey in trendStatus.keys.toList()) {
    updatedStatus.remove(metricKey);
    updatedDeltas.remove(metricKey);
    updatedLockReasons[metricKey] = 'lighting_mismatch';
  }
  return (
    trendStatus: updatedStatus,
    trendDeltas: updatedDeltas,
    trendLockReasons: updatedLockReasons,
  );
}

/// Rolling-average trend for [fiveFrameMedianMetricKeys]: the median of the
/// last [rollingTrendWindowSize] same-light, same-path scans (the current
/// one plus the most recent qualifying earlier scans after the baseline) is
/// compared against the baseline, or against the median of the baseline's
/// own last three when those exist.
const int rollingTrendWindowSize = 3;

/// One scan as seen by [applyRollingTrend].
typedef RollingTrendScan = ({
  String id,
  DateTime timestamp,
  String? poseTemplate,
  String? guideType,
  String? captureQuality,
  Map<String, dynamic> payload,
});

RollingTrendScan rollingTrendScanOf(ScanHistoryEntry scan) => (
  id: scan.id,
  timestamp: scan.timestamp,
  poseTemplate: scan.poseTemplate,
  guideType: scan.guideType,
  captureQuality: scan.captureQuality,
  payload: scan.rawPayload ?? const <String, dynamic>{},
);

Map<String, dynamic> _payloadNode(Map<String, dynamic> payload, String key) {
  final direct = _dynamicMap(payload[key]);
  if (direct.isNotEmpty) return direct;
  return _dynamicMap(_dynamicMap(payload['metrics'])[key]);
}

double? _rollingValue(RollingTrendScan scan, String key) =>
    _parseFiniteDouble(_payloadNode(scan.payload, 'metric_matrix')[key]);

String? _rollingPath(RollingTrendScan scan, String key) {
  final path = _payloadNode(
    scan.payload,
    'metric_extraction_paths',
  )[key]?.toString().trim();
  if (path == null || path.isEmpty || path == 'unknown' || path == 'skipped') {
    return null;
  }
  return path;
}

String? _rollingVersion(RollingTrendScan scan, String key) =>
    _payloadNode(scan.payload, 'metric_formula_versions')[key]?.toString();

/// Whether [candidate] (an earlier scan) can share a rolling window with
/// [reference] for [key]: same angle and region, both captured at normal
/// quality (no capture_quality_mismatch), |ΔBv| within the lighting limit,
/// and the same extraction path and formula version for [key].
bool rollingTrendScanQualifies({
  required RollingTrendScan candidate,
  required RollingTrendScan reference,
  required String key,
}) {
  if (!candidate.timestamp.isBefore(reference.timestamp)) return false;
  if (candidate.poseTemplate == null ||
      candidate.poseTemplate != reference.poseTemplate ||
      candidate.guideType == null ||
      candidate.guideType != reference.guideType) {
    return false;
  }
  if (candidate.captureQuality?.trim().toLowerCase() != 'normal' ||
      reference.captureQuality?.trim().toLowerCase() != 'normal') {
    return false;
  }
  final candidateBv = _representativeScanExposure(
    candidate.payload,
  ).brightnessValue;
  final referenceBv = _representativeScanExposure(
    reference.payload,
  ).brightnessValue;
  if (candidateBv == null ||
      referenceBv == null ||
      (candidateBv - referenceBv).abs() >
          provisionalBrightnessValueMismatchLimit) {
    return false;
  }
  if (_rollingValue(candidate, key) == null) return false;
  final path = _rollingPath(reference, key);
  if (path == null || _rollingPath(candidate, key) != path) return false;
  final version = _rollingVersion(reference, key);
  return version != null && _rollingVersion(candidate, key) == version;
}

/// The backend's _trend_delta_and_status decision after its comparability
/// gates, applied to rolling values with the policy main.py echoes in the
/// response (honesty_band_percent, metric_noise_floor_2sd,
/// trend_noise_floor_exceeds_useful_range,
/// trend_noise_floor_excluded_multiplier, metric_higher_is_worse). None of
/// [fiveFrameMedianMetricKeys] is floor-only. Null when the policy is
/// missing (an older backend).
({double delta, String status})? rollingTrendStatus({
  required String key,
  required double current,
  required double baseline,
  required Map<String, dynamic> policy,
}) {
  final band = _parseFiniteDouble(policy['honesty_band_percent']);
  final higherIsWorse = _dynamicMap(policy['metric_higher_is_worse'])[key];
  if (band == null || higherIsWorse is! bool) return null;
  if (baseline.abs() < 1e-9) return (delta: 0.0, status: 'stable');
  final denominator = baseline.abs();
  final directional = higherIsWorse
      ? (baseline - current) / denominator * 100.0
      : (current - baseline) / denominator * 100.0;
  final floor = _parseFiniteDouble(
    _dynamicMap(policy['metric_noise_floor_2sd'])[key],
  );
  if (floor != null) {
    final absolute = (current - baseline).abs();
    final excluded = _stringSetFromDynamic(
      policy['trend_noise_floor_exceeds_useful_range'],
    );
    if (excluded.contains(key)) {
      final multiplier =
          _parseFiniteDouble(policy['trend_noise_floor_excluded_multiplier']) ??
          1.0;
      if (absolute < floor * multiplier) {
        return (delta: 0.0, status: 'insufficient_signal');
      }
    } else if (absolute < floor) {
      return (delta: 0.0, status: 'stable');
    }
  }
  if (directional.abs() < band) return (delta: 0.0, status: 'stable');
  final rounded = double.parse(directional.toStringAsFixed(1));
  if (rounded > 0) return (delta: rounded, status: 'improved');
  if (rounded < 0) return (delta: rounded, status: 'worsened');
  return (delta: 0.0, status: 'stable');
}

/// Replaces the single-scan trend of [fiveFrameMedianMetricKeys] with the
/// rolling comparison when [rollingTrendWindowSize] qualifying scans exist;
/// otherwise keeps the single-scan result (which, for these untrusted
/// metrics, carries no verdict) and notes the fallback. A metric that is
/// already locked keeps its lock. [rollingTrend] records, per metric, the
/// method used and the values compared ("rolling_median_3",
/// "single_scan_fallback", or "locked").
({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, Map<String, dynamic>> rollingTrend,
})
applyRollingTrend({
  required Map<String, String> trendStatus,
  required Map<String, double> trendDeltas,
  required Map<String, String> trendLockReasons,
  required RollingTrendScan current,
  required RollingTrendScan? baseline,
  required List<RollingTrendScan> history,
}) {
  final updatedStatus = Map<String, String>.from(trendStatus);
  final updatedDeltas = Map<String, double>.from(trendDeltas);
  final notes = <String, Map<String, dynamic>>{};

  List<RollingTrendScan> recentQualifying(
    RollingTrendScan reference,
    String key, {
    DateTime? after,
    required Set<String> excludeIds,
  }) =>
      history
          .where(
            (scan) =>
                !excludeIds.contains(scan.id) &&
                (after == null || scan.timestamp.isAfter(after)) &&
                rollingTrendScanQualifies(
                  candidate: scan,
                  reference: reference,
                  key: key,
                ),
          )
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  for (final key in fiveFrameMedianMetricKeys) {
    final currentValue = _rollingValue(current, key);
    if (currentValue == null) continue;
    final lockReason = trendLockReasons[key]?.trim() ?? '';
    if (lockReason.isNotEmpty) {
      notes[key] = {'method': 'locked', 'lock_reason': lockReason};
      continue;
    }
    if (baseline == null || _rollingValue(baseline, key) == null) {
      notes[key] = {
        'method': 'single_scan_fallback',
        'reason': 'no_baseline_value',
      };
      continue;
    }
    final window = <RollingTrendScan>[
      current,
      ...recentQualifying(
        current,
        key,
        after: baseline.timestamp,
        excludeIds: {current.id, baseline.id},
      ).take(rollingTrendWindowSize - 1),
    ];
    if (window.length < rollingTrendWindowSize) {
      notes[key] = {
        'method': 'single_scan_fallback',
        'reason': 'fewer_than_three_scans',
        'qualifying_scans': window.length,
      };
      continue;
    }
    final baselineWindow = <RollingTrendScan>[
      baseline,
      ...recentQualifying(
        baseline,
        key,
        excludeIds: {current.id, baseline.id},
      ).take(rollingTrendWindowSize - 1),
    ];
    final baselineRolling = baselineWindow.length == rollingTrendWindowSize;
    final rollingCurrent = _medianOf([
      for (final scan in window) _rollingValue(scan, key)!,
    ]);
    final baselineValue = baselineRolling
        ? _medianOf([
            for (final scan in baselineWindow) _rollingValue(scan, key)!,
          ])
        : _rollingValue(baseline, key)!;
    final result = rollingTrendStatus(
      key: key,
      current: rollingCurrent,
      baseline: baselineValue,
      policy: current.payload,
    );
    if (result == null) {
      notes[key] = {
        'method': 'single_scan_fallback',
        'reason': 'policy_unavailable',
      };
      continue;
    }
    updatedStatus[key] = result.status;
    updatedDeltas[key] = result.delta;
    notes[key] = {
      'method': 'rolling_median_3',
      'current_value': double.parse(rollingCurrent.toStringAsFixed(2)),
      'baseline_value': double.parse(baselineValue.toStringAsFixed(2)),
      'baseline_method': baselineRolling ? 'rolling_median_3' : 'single_scan',
      'scan_ids': [for (final scan in window) scan.id],
      'baseline_scan_ids': [
        for (final scan in baselineRolling ? baselineWindow : [baseline])
          scan.id,
      ],
    };
  }
  return (
    trendStatus: updatedStatus,
    trendDeltas: updatedDeltas,
    rollingTrend: notes,
  );
}

/// region_position_mismatch: a tracked region's box (logged by main.py in
/// image_quality as `<prefix>_box_cx/cy/w/h`, in face-width units) whose
/// center moved more than this many face widths from the baseline's...
const double regionPositionCenterShiftLimit = 0.04;

/// ...or whose area changed by more than this fraction of the baseline's.
const double regionPositionAreaChangeLimit = 0.08;

/// Which logged region boxes each metric is measured in.
const Map<String, List<String>> regionPositionBoxPrefixes = {
  'wrinkle_load': ['wrinkle_region'],
  'pore_contraction_index': ['pore_contraction_roi'],
  'under_eye_dark_circle_density': ['under_eye_left', 'under_eye_right'],
  'under_eye_texture_density': ['under_eye_left', 'under_eye_right'],
};

({double cx, double cy, double area})? _regionBox(
  Map<String, dynamic> imageQuality,
  String prefix,
) {
  final cx = _parseFiniteDouble(imageQuality['${prefix}_box_cx']);
  final cy = _parseFiniteDouble(imageQuality['${prefix}_box_cy']);
  final w = _parseFiniteDouble(imageQuality['${prefix}_box_w']);
  final h = _parseFiniteDouble(imageQuality['${prefix}_box_h']);
  if (cx == null || cy == null || w == null || h == null) return null;
  return (cx: cx, cy: cy, area: w * h);
}

/// Whether [prefix]'s region moved or resized past the limits above between
/// [baselineQuality] and [currentQuality]. False when either scan did not
/// log the box (e.g. scans saved before boxes were logged).
bool regionPositionShifted({
  required Map<String, dynamic> currentQuality,
  required Map<String, dynamic> baselineQuality,
  required String prefix,
}) {
  final current = _regionBox(currentQuality, prefix);
  final baseline = _regionBox(baselineQuality, prefix);
  if (current == null || baseline == null) return false;
  final dx = current.cx - baseline.cx;
  final dy = current.cy - baseline.cy;
  final centerShift = math.sqrt(dx * dx + dy * dy);
  final areaChange = baseline.area <= 0
      ? double.infinity
      : (current.area - baseline.area).abs() / baseline.area;
  return centerShift > regionPositionCenterShiftLimit ||
      areaChange > regionPositionAreaChangeLimit;
}

/// Locks wrinkle_load, pore_contraction_index and the under-eye metrics with
/// region_position_mismatch when their region shifted (see
/// [regionPositionShifted]), clearing status and delta like the other locks.
/// Applies to every one of those metrics the current scan emitted -- they
/// can carry a lock reason even with no status -- and never replaces a lock
/// reason that is already set.
({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, String> trendLockReasons,
})
lockTrendsForRegionPositionMismatch({
  required Map<String, String> trendStatus,
  required Map<String, double> trendDeltas,
  required Map<String, String> trendLockReasons,
  required Map<String, dynamic> currentPayload,
  required Map<String, dynamic> baselinePayload,
}) {
  Map<String, dynamic> imageQuality(Map<String, dynamic> payload) {
    final direct = _dynamicMap(payload['image_quality']);
    if (direct.isNotEmpty) return direct;
    return _dynamicMap(_dynamicMap(payload['metrics'])['image_quality']);
  }

  final currentQuality = imageQuality(currentPayload);
  final baselineQuality = imageQuality(baselinePayload);
  final currentMatrix = _dynamicMap(currentPayload['metric_matrix']).isNotEmpty
      ? _dynamicMap(currentPayload['metric_matrix'])
      : _dynamicMap(_dynamicMap(currentPayload['metrics'])['metric_matrix']);
  final updatedStatus = Map<String, String>.from(trendStatus);
  final updatedDeltas = Map<String, double>.from(trendDeltas);
  final updatedLockReasons = Map<String, String>.from(trendLockReasons);
  if (baselinePayload.isEmpty) {
    return (
      trendStatus: updatedStatus,
      trendDeltas: updatedDeltas,
      trendLockReasons: updatedLockReasons,
    );
  }
  for (final entry in regionPositionBoxPrefixes.entries) {
    final metricKey = entry.key;
    if (!currentMatrix.containsKey(metricKey)) continue;
    if ((updatedLockReasons[metricKey] ?? '').trim().isNotEmpty) continue;
    final shifted = entry.value.any(
      (prefix) => regionPositionShifted(
        currentQuality: currentQuality,
        baselineQuality: baselineQuality,
        prefix: prefix,
      ),
    );
    if (!shifted) continue;
    updatedStatus.remove(metricKey);
    updatedDeltas.remove(metricKey);
    updatedLockReasons[metricKey] = 'region_position_mismatch';
  }
  return (
    trendStatus: updatedStatus,
    trendDeltas: updatedDeltas,
    trendLockReasons: updatedLockReasons,
  );
}

/// Pre-upload check: would this capture's frames be locked as
/// lighting_mismatch against [baselinePayload] by the same rule the
/// results use ([lockTrendsForLightingMismatch])? [wouldLock] is true only
/// for a measured brightness mismatch -- both scans have ISO and Bv and
/// |delta Bv| exceeds provisionalBrightnessValueMismatchLimit -- since a
/// retake under the lamp can fix that. Missing exposure metadata, which the
/// same rule also locks on, is reported separately as [missingExposure]
/// because retaking cannot add it to an older baseline.
({
  bool wouldLock,
  bool missingExposure,
  double? currentBrightnessValue,
  double? baselineBrightnessValue,
})
aiScanPreUploadLightingCheck({
  required List<AiScanFrameExposure> frameExposure,
  required Map<String, dynamic>? baselinePayload,
}) {
  if (baselinePayload == null || baselinePayload.isEmpty) {
    return (
      wouldLock: false,
      missingExposure: false,
      currentBrightnessValue: null,
      baselineBrightnessValue: null,
    );
  }
  final currentPayload = <String, dynamic>{
    aiScanPerFrameDiagnosticsKey: [
      for (final frame in frameExposure) frame.toJson(),
    ],
  };
  const probeKey = '_pre_upload_probe';
  final locked =
      lockTrendsForLightingMismatch(
        trendStatus: const {probeKey: 'stable'},
        trendDeltas: const {probeKey: 0.0},
        trendLockReasons: const {},
        currentPayload: currentPayload,
        baselinePayload: baselinePayload,
      ).trendLockReasons[probeKey] ==
      'lighting_mismatch';
  final current = _representativeScanExposure(currentPayload);
  final baseline = _representativeScanExposure(baselinePayload);
  final missingExposure =
      current.iso == null ||
      current.brightnessValue == null ||
      baseline.iso == null ||
      baseline.brightnessValue == null;
  return (
    wouldLock: locked && !missingExposure,
    missingExposure: locked && missingExposure,
    currentBrightnessValue: current.brightnessValue,
    baselineBrightnessValue: baseline.brightnessValue,
  );
}

({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, String> trendLockReasons,
})
clearLockedTrendVerdicts({
  required Map<String, String> trendStatus,
  required Map<String, double> trendDeltas,
  required Map<String, String> trendLockReasons,
}) {
  final updatedStatus = Map<String, String>.from(trendStatus);
  final updatedDeltas = Map<String, double>.from(trendDeltas);
  for (final entry in trendLockReasons.entries) {
    if (entry.value.trim().isEmpty) continue;
    updatedStatus.remove(entry.key);
    updatedDeltas.remove(entry.key);
  }
  return (
    trendStatus: updatedStatus,
    trendDeltas: updatedDeltas,
    trendLockReasons: Map<String, String>.from(trendLockReasons),
  );
}

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
    final metricExtractionPaths =
        _dynamicMap(response?['metric_extraction_paths']).isNotEmpty
        ? _dynamicMap(response?['metric_extraction_paths'])
        : _dynamicMap(metricsNode['metric_extraction_paths']);
    final exposure = index < frameExposureMetadata.length
        ? frameExposureMetadata[index]
        : const AiScanFrameExposure();
    return <String, dynamic>{
      'frame_number': index + 1,
      'cheek_side': imageQuality['redness_cheek_side'],
      'cheek_side_convention': imageQuality['cheek_side_convention'],
      'redness_both_cheeks_in_dead_zone':
          imageQuality['redness_both_cheeks_in_dead_zone'],
      'mask_pixel_count': imageQuality['redness_cheek_roi_pixels'],
      'cheek_p95_a_after_wb': imageQuality['redness_cheek_p95_a_after_wb'],
      'cheek_p10_a_after_wb': imageQuality['redness_cheek_p10_a_after_wb'],
      'cheek_p10_a_before_wb': imageQuality['redness_cheek_p10_a_before_wb'],
      'localized_redness': metricMatrix['localized_redness'],
      'gray_card_marked': imageQuality['gray_card_marked'],
      'gray_card_mean_L': imageQuality['gray_card_mean_L'],
      'gray_card_mean_a': imageQuality['gray_card_mean_a'],
      'gray_card_mean_b': imageQuality['gray_card_mean_b'],
      'gray_card_correction_applied':
          imageQuality['gray_card_correction_applied'],
      'gray_card_reason': imageQuality['gray_card_reason'],
      'gray_card_chroma_offset': imageQuality['gray_card_chroma_offset'],
      'gray_card_scene_disagreement':
          imageQuality['gray_card_scene_disagreement'],
      for (final field in grayCardRegionFields) field: imageQuality[field],
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
      'pore_visibility_extraction_path':
          metricExtractionPaths['pore_visibility'],
      'chin_pore_visibility_mask_kind':
          imageQuality['chin_pore_visibility_mask_kind'],
      'chin_pore_visibility_mask_pixels':
          imageQuality['chin_pore_visibility_mask_pixels'],
      'diffuse_flushing_erythema_mask_kind':
          imageQuality['diffuse_flushing_erythema_mask_kind'],
      'diffuse_flushing_erythema_mask_pixels':
          imageQuality['diffuse_flushing_erythema_mask_pixels'],
      'under_eye_dark_circle_density_mask_kind':
          imageQuality['under_eye_dark_circle_density_mask_kind'],
      'under_eye_dark_circle_density_mask_pixels':
          imageQuality['under_eye_dark_circle_density_mask_pixels'],
      'under_eye_dark_circle_density_omit_reason':
          imageQuality['under_eye_dark_circle_density_omit_reason'],
      'under_eye_texture_density_mask_kind':
          imageQuality['under_eye_texture_density_mask_kind'],
      'under_eye_texture_density_mask_pixels':
          imageQuality['under_eye_texture_density_mask_pixels'],
      'under_eye_texture_density_omit_reason':
          imageQuality['under_eye_texture_density_omit_reason'],
      ...exposure.toJson(),
    };
  }, growable: false);
}

bool aiScanHasCheekSideMismatch({
  required Map<String, dynamic> currentPayload,
  required Map<String, dynamic> baselinePayload,
}) {
  Map<String, dynamic> imageQuality(Map<String, dynamic> payload) {
    final direct = _dynamicMap(payload['image_quality']);
    if (direct.isNotEmpty) return direct;
    return _dynamicMap(_dynamicMap(payload['metrics'])['image_quality']);
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
  final baselineSide =
      baselineConvention == cheekSideConventionSubjectAnatomical
      ? storedBaselineSide
      : switch (storedBaselineSide) {
          'left' => 'right',
          'right' => 'left',
          _ => storedBaselineSide,
        };
  final sideIndependent =
      currentQuality['redness_both_cheeks_in_dead_zone'] == true ||
      baselineQuality['redness_both_cheeks_in_dead_zone'] == true;
  return !sideIndependent &&
      currentSide != null &&
      currentSide.isNotEmpty &&
      baselineSide != null &&
      baselineSide.isNotEmpty &&
      currentSide != baselineSide;
}

({
  Map<String, String> trendStatus,
  Map<String, double> trendDeltas,
  Map<String, String> trendLockReasons,
  Set<String> rednessLockReasons,
  bool cheekLockSkippedLowValues,
  bool regionLockSkippedLowValues,
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
    final updatedStatus = Map<String, String>.from(trendStatus);
    final updatedDeltas = Map<String, double>.from(trendDeltas);
    final updatedLockReasons = Map<String, String>.from(trendLockReasons);
    return (
      trendStatus: updatedStatus,
      trendDeltas: updatedDeltas,
      trendLockReasons: updatedLockReasons,
      rednessLockReasons: const <String>{},
      cheekLockSkippedLowValues: false,
      regionLockSkippedLowValues: false,
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
        .map(
          (frame) =>
              _parseFiniteDouble(_dynamicMap(frame)['cheek_p95_a_after_wb']),
        )
        .whereType<double>()
        .toList(growable: false);
  }

  final currentQuality = imageQuality(currentPayload);
  final baselineQuality = imageQuality(baselinePayload);
  final reasons = <String>{};
  if (existingRednessLockReason == 'path_mismatch') {
    reasons.add('path_mismatch');
  }
  // A single-cheek reading on one scan and a both-cheeks reading on the
  // other is not treated as a cheek mismatch when both redness values are
  // low (at or below rednessCheekLockLowValueCeiling): at that level the
  // difference is noise. Any missing or higher value keeps the lock.
  double? rednessValue(Map<String, dynamic> payload) => _parseFiniteDouble(
    _dynamicMap(payload['metric_matrix'])['localized_redness'] ??
        _dynamicMap(
          _dynamicMap(payload['metrics'])['metric_matrix'],
        )['localized_redness'],
  );
  // baseline_p95_anchor (follow-up redness read over the whole U-zone
  // against the baseline's stored U-zone p95; side "both", mask u_zone) is
  // not tied to one cheek or to the baseline's single-cheek mask, so a side
  // or mask difference against it only means the measurement method
  // changed. Payloads without redness_branch are recognised by what only
  // that method reports: side "both" (cheek check) or mask u_zone (region
  // and cast checks; side "both" when no mask was recorded).
  bool branchIsAnchor(Map<String, dynamic> quality) =>
      quality['redness_branch']?.toString().trim() ==
      rednessBranchBaselineP95Anchor;
  bool sideIsAnchor(Map<String, dynamic> quality) =>
      branchIsAnchor(quality) ||
      quality['redness_cheek_side']?.toString().trim() == 'both';
  bool maskIsAnchor(Map<String, dynamic> quality) {
    if (branchIsAnchor(quality)) return true;
    final mask = quality['localized_redness_mask_kind']?.toString().trim();
    // No mask recorded (older payload): fall back to the side label.
    if (mask == null || mask.isEmpty) return sideIsAnchor(quality);
    return mask == 'u_zone';
  }

  final methodChanged =
      sideIsAnchor(currentQuality) || sideIsAnchor(baselineQuality);
  final currentMaskAnchored = maskIsAnchor(currentQuality);
  final baselineMaskAnchored = maskIsAnchor(baselineQuality);
  var cheekLockSkippedLowValues = false;
  if (aiScanHasCheekSideMismatch(
    currentPayload: currentPayload,
    baselinePayload: baselinePayload,
  )) {
    const singleCheeks = {'left', 'right'};
    final currentSide = currentQuality['redness_cheek_side']?.toString().trim();
    final baselineSide = baselineQuality['redness_cheek_side']
        ?.toString()
        .trim();
    final singleVsBoth =
        (singleCheeks.contains(currentSide) && baselineSide == 'both') ||
        (currentSide == 'both' && singleCheeks.contains(baselineSide));
    final currentValue = rednessValue(currentPayload);
    final baselineValue = rednessValue(baselinePayload);
    final bothLow =
        currentValue != null &&
        baselineValue != null &&
        currentValue <= rednessCheekLockLowValueCeiling &&
        baselineValue <= rednessCheekLockLowValueCeiling;
    final valuesMatch =
        currentValue != null &&
        baselineValue != null &&
        (currentValue - baselineValue).abs() <=
            rednessCheekLockMatchingValueTolerance;
    // Cheek sides are compared only when both scans used
    // within_cheek_spread (see methodChanged above).
    if (singleVsBoth && bothLow) {
      cheekLockSkippedLowValues = true;
    } else if (singleVsBoth && valuesMatch) {
      // Matching values: no lock, and no new export field for this skip.
    } else if (methodChanged) {
      // Measurement method changed: not a cheek mismatch (no export field).
    } else {
      reasons.add('cheek_mismatch');
    }
  }

  // A changed redness region (e.g. left_cheek vs u_zone) reads its p10/p95
  // from different pixels, so comparing those percentiles would report a
  // "cast" that is really the region change: lock as region_mismatch and
  // skip the cast check. A dead-zone 0.0 score, or a scan whose cheeks are
  // both in the dead zone, has no redness to protect from a cast, so it
  // never takes cast_mismatch. Neither changes the redness value.
  final currentRegion = currentQuality['localized_redness_mask_kind']
      ?.toString()
      .trim();
  final baselineRegion = baselineQuality['localized_redness_mask_kind']
      ?.toString()
      .trim();
  final regionChanged =
      currentRegion != null &&
      currentRegion.isNotEmpty &&
      baselineRegion != null &&
      baselineRegion.isNotEmpty &&
      currentRegion != baselineRegion;
  final currentRedness = _parseFiniteDouble(
    _dynamicMap(currentPayload['metric_matrix'])['localized_redness'] ??
        _dynamicMap(
          _dynamicMap(currentPayload['metrics'])['metric_matrix'],
        )['localized_redness'],
  );
  final eitherInDeadZone =
      currentQuality['redness_both_cheeks_in_dead_zone'] == true ||
      baselineQuality['redness_both_cheeks_in_dead_zone'] == true;
  final skipCastCheck =
      (currentRedness != null && currentRedness <= 0.0) || eitherInDeadZone;

  // A single-cheek region against u_zone is not a region mismatch when both
  // redness values are low (at or below rednessCheekLockLowValueCeiling).
  // The percentiles are still not compared across different regions.
  var regionLockSkippedLowValues = false;
  if (regionChanged) {
    const singleCheekRegions = {'left_cheek', 'right_cheek'};
    final singleCheekVsUZone =
        (singleCheekRegions.contains(currentRegion) &&
            baselineRegion == 'u_zone') ||
        (currentRegion == 'u_zone' &&
            singleCheekRegions.contains(baselineRegion));
    final currentValue = rednessValue(currentPayload);
    final baselineValue = rednessValue(baselinePayload);
    final bothLow =
        currentValue != null &&
        baselineValue != null &&
        currentValue <= rednessCheekLockLowValueCeiling &&
        baselineValue <= rednessCheekLockLowValueCeiling;
    if (singleCheekVsUZone && bothLow) {
      regionLockSkippedLowValues = true;
    } else if (currentMaskAnchored || baselineMaskAnchored) {
      // Measurement method changed: the follow-up already compares U-zone
      // with the baseline's stored U-zone p95, so the mask label
      // difference is not a region change (no export field).
    } else {
      reasons.add('region_mismatch');
    }
  } else if (!skipCastCheck && currentMaskAnchored == baselineMaskAnchored) {
    // Skipped when only one scan is anchored: the other scan's cheek
    // p10/p95 may come from a single-cheek mask, so comparing them with
    // U-zone percentiles would report a cast that is really the method
    // change. Two anchored scans (U-zone vs U-zone) still compare.
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
  }

  final updatedStatus = Map<String, String>.from(trendStatus);
  final updatedDeltas = Map<String, double>.from(trendDeltas);
  final updatedLockReasons = Map<String, String>.from(trendLockReasons);
  if (reasons.isNotEmpty) {
    updatedStatus.remove('localized_redness');
    updatedDeltas.remove('localized_redness');
    updatedLockReasons['localized_redness'] = reasons.contains('cheek_mismatch')
        ? 'cheek_mismatch'
        : reasons.contains('region_mismatch')
        ? 'region_mismatch'
        : reasons.contains('cast_mismatch')
        ? 'cast_mismatch'
        : 'path_mismatch';
  }
  return (
    trendStatus: updatedStatus,
    trendDeltas: updatedDeltas,
    trendLockReasons: updatedLockReasons,
    rednessLockReasons: Set<String>.unmodifiable(reasons),
    cheekLockSkippedLowValues: cheekLockSkippedLowValues,
    regionLockSkippedLowValues: regionLockSkippedLowValues,
  );
}

Future<MultiFrameAnalysisAggregate> analyzeBackendFrames(
  List<Uint8List> frames, {
  required bool photoUploadAccepted,
  required Future<Map<String, dynamic>> Function(
    Uint8List frame,
    int frameNumber,
  )
  uploadFrame,
  Future<Map<String, dynamic>> Function(Uint8List frame, int frameNumber)?
  uploadFrameWithoutGrayCard,
  List<AiScanFrameExposure> frameExposureMetadata =
      const <AiScanFrameExposure>[],
}) async {
  if (!photoUploadAccepted) {
    throw StateError('Face photo upload acknowledgment is required.');
  }
  final responses = <Map<String, dynamic>>[];
  final responseFrameNumbers = <int>[];
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
      responseFrameNumbers.add(frameNumber);
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
  final grayCardSummary = summarizeGrayCardFrames(responses);
  if (grayCardSummary['gray_card_status'] == 'partial') {
    if (uploadFrameWithoutGrayCard == null) {
      throw StateError(
        'A partial gray-card burst must be reprocessed without the card.',
      );
    }
    final uncorrected = <Map<String, dynamic>>[];
    for (final frameNumber in responseFrameNumbers) {
      uncorrected.add(
        await uploadFrameWithoutGrayCard(frames[frameNumber - 1], frameNumber),
      );
    }
    responses
      ..clear()
      ..addAll(uncorrected);
  }
  try {
    final aggregate = averageBackendAnalysisFrames(
      responses,
      requestedFrames: frames.length,
      frameNumbers: responseFrameNumbers,
    );
    if (grayCardSummary.isNotEmpty) {
      aggregate.response['image_quality'] = {
        ..._dynamicMap(aggregate.response['image_quality']),
        ...grayCardSummary,
      };
      _dynamicMap(aggregate.response['metrics'])['image_quality'] =
          aggregate.response['image_quality'];
      for (final key in grayCardSummary.keys.where(
        (key) => key.startsWith('gray_card_'),
      )) {
        aggregate.response[key] = grayCardSummary[key];
        _dynamicMap(aggregate.response['metrics'])[key] = grayCardSummary[key];
      }
    }
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
) => <String, dynamic>{
  'metric_confidence': _dynamicMap(backendResponse?['metric_confidence']),
  'multi_frame_analysis': _dynamicMap(backendResponse?['multi_frame_analysis']),
  'metric_noise_floor_2sd': _dynamicMap(
    backendResponse?['metric_noise_floor_2sd'],
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
    firmness =
        (10 - (textureFinal * 0.45 + wrinkleFinal * 0.20 + swelling * 0.15))
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
    overallHealing =
        ((10 - swelling) * 0.22 +
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
    // Never chosen implicitly; an explicit pin (above) still counts.
    if (isQuickAiScan(scan)) return false;
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
    eligibleScansForKey: resolvedBaseline == null
        ? const []
        : [resolvedBaseline],
    isFirstForKey: resolvedBaseline == null,
  );
}

/// Opens the existing PaywallScreen and returns true when a free user has
/// used the free AI scan ([kFreeAiScanLimit]) or every free local scan
/// ([kFreeLocalScanLimit]) without upload access; the caller must then stop
/// without scanning. Premium and Test Premium are never stopped.
Future<bool> openPaywallIfFreeScanCapReached(BuildContext context) async {
  if (!await FreeAiScans.limitReached() && !await FreeLocalScans.capReached()) {
    return false;
  }
  if (!context.mounted) return true;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PaywallScreen()));
  return true;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export burst log: $e')),
        );
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

  /// One-page PDF of the last comparable pair, saved and shared the same way
  /// as the scan-data CSV (temporary directory, then the share sheet).
  Future<void> _exportComparisonPdf(BuildContext buttonContext) async {
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
      final pair = lastComparablePair(
        await AppPrefs.getScanEntriesWithoutNormalization(),
      );
      if (pair == null) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No saved AI scan to export.')),
          );
        }
        return;
      }
      final bytes = await buildComparablePairPdf(pair);
      final fileName =
          'ai_skin_comparison_${DateTime.now().toIso8601String().replaceAll(':', '-')}.pdf';
      final XFile file;
      if (kIsWeb) {
        file = XFile.fromData(
          bytes,
          mimeType: 'application/pdf',
          name: fileName,
        );
      } else {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}${Platform.pathSeparator}$fileName';
        await File(path).writeAsBytes(bytes, flush: true);
        file = XFile(path, mimeType: 'application/pdf', name: fileName);
      }
      await Share.shareXFiles(
        [file],
        text: 'AI Skin Analysis comparison',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to export comparison PDF: $e')),
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

  /// First visit only: the "Recommended lighting" tip (see LightingTipCard).
  bool _showLightingTip = false;

  /// Id of the scan this results screen saved (for "Note for this scan").
  String? _savedScanId;

  String? _imagePath;

  /// Cropped JPEG bytes from the mandatory crop step (camera/gallery). When
  /// non-null these exact bytes are what the analyzer receives — never the
  /// uncropped original. A "latest scan" selection leaves this null and is
  /// read from its stored path instead.
  Uint8List? _croppedBytes;
  List<Uint8List> _analysisFrameBytes = const [];
  List<AiScanFrameExposure> _analysisFrameExposureMetadata = const [];
  int? _capturedSourceImageWidth;
  int? _capturedSourceImageHeight;

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
  ({double? crop, double? fullStill, double? floor}) _currentCaptureSharpness =
      (crop: null, fullStill: null, floor: null);

  /// The view angle and camera guide type from the CameraScreen capture
  /// that produced [_imagePath] (see AiSkinAnalysisCaptureResult). Null
  /// when the photo came from the gallery instead of the live camera --
  /// the angle/region are then genuinely unknown for that scan, and are
  /// saved as null rather than guessed.
  String? _capturedPoseTemplate;
  String? _capturedGuideType;

  /// Off by default: when on, the camera shows the fixed under-chin gray-card
  /// target and samples it at capture. [_grayCardRegion] is that target as
  /// fractions of the full still and [_grayCardPatches] the patch per frame;
  /// both empty when the switch is off (nothing extra is sent).
  bool _markGrayCard = false;

  /// Scan path for the next camera capture: false (default) is the
  /// controlled multi-frame scan; true is the single-photo quick scan.
  bool _quickScanMode = false;

  /// Mode of the photo currently selected for analysis: 'controlled' or
  /// 'quick' for camera captures, null for gallery / latest-scan sources.
  String? _capturedScanMode;
  GrayCardRegion? _grayCardRegion;
  List<Uint8List> _grayCardPatches = const [];

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
    shouldShowLightingTip().then((show) {
      if (show && mounted) setState(() => _showLightingTip = true);
    });
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
    if (await openPaywallIfFreeScanCapReached(context)) return;
    if (!mounted) return;
    // First face scan (scans start on the Front pose): the one-time
    // Consistent Setup guide, before the camera opens.
    if (!_isBodyProcedure) {
      await showConsistentSetupGuideIfFirstTime(context);
      if (!mounted) return;
    }
    try {
      final selectedProcedureId = (_selectedProcedureId ?? '').trim();
      final checklistToken = await frontBaselineResetToken(
        procedureId: selectedProcedureId.isEmpty ? null : selectedProcedureId,
        focusArea: _resolvedFocusArea(),
      );
      if (!mounted) return;
      final captured = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
          builder: (_) => CameraScreen(
            isSkincareScan: true,
            aiMultiFrameCapture: true,
            capturePurpose: CameraCapturePurpose.aiSkinAnalysis,
            markGrayCardAfterCapture: _markGrayCard,
            protocolChecklistResetToken: checklistToken,
            aiQuickScan: _quickScanMode,
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
          _currentCaptureSharpness = (
            crop: captured.cropSharpness,
            fullStill: captured.fullStillSharpness,
            floor: captured.sharpnessFloor,
          );
          _capturedPoseTemplate = captured.poseTemplate;
          _capturedGuideType = captured.guideType;
          _capturedSourceImageWidth = captured.sourceImageWidth;
          _capturedSourceImageHeight = captured.sourceImageHeight;
          _grayCardRegion = captured.grayCardRegion;
          _grayCardPatches = captured.grayCardPatches;
          _capturedScanMode = captured.quickScan
              ? aiScanModeQuick
              : aiScanModeControlled;
        } else {
          _analysisFrameBytes = const [];
          _analysisFrameExposureMetadata = const [];
          _croppedBytes = null;
          _currentCaptureQuality = null;
          _currentCaptureSharpness = (crop: null, fullStill: null, floor: null);
          _capturedPoseTemplate = null;
          _capturedGuideType = null;
          _capturedSourceImageWidth = null;
          _capturedSourceImageHeight = null;
          _grayCardRegion = null;
          _grayCardPatches = const [];
          _capturedScanMode = null;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Camera unavailable: $e')));
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
    if (await openPaywallIfFreeScanCapReached(context)) return;
    if (!mounted) return;
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
          _capturedSourceImageWidth = null;
          _capturedSourceImageHeight = null;
          _grayCardRegion = null;
          _grayCardPatches = const [];
          _capturedScanMode = null;
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
        _capturedSourceImageWidth = null;
        _capturedSourceImageHeight = null;
        _grayCardRegion = null;
        _grayCardPatches = const [];
        _capturedScanMode = null;
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

  /// Asks whether to retake before analyzing a capture whose brightness
  /// would lock it against the baseline. True = retake.
  Future<bool> _confirmRetakeForLighting(
    ({
      bool wouldLock,
      bool missingExposure,
      double? currentBrightnessValue,
      double? baselineBrightnessValue,
    })
    check,
  ) async {
    String bv(double? value) => value == null ? '—' : value.toStringAsFixed(2);
    final retake = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('pre_upload_lighting_dialog'),
        title: const Text('Light differs from your baseline'),
        content: Text(
          'This photo\'s brightness (Bv ${bv(check.currentBrightnessValue)}) '
          'differs from your baseline (Bv ${bv(check.baselineBrightnessValue)}) '
          'by more than the lighting check allows, so it would not be '
          'compared. Retake under your lamp to compare.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Analyze anyway'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Retake under your lamp'),
          ),
        ],
      ),
    );
    return retake ?? false;
  }

  Future<void> _runAnalysis() async {
    final path = _imagePath;
    if (path == null || path.isEmpty) return;
    if (await openPaywallIfFreeScanCapReached(context)) return;
    if (!mounted) return;
    if (!_consentAccepted && !await _reviewConsent()) return;
    if (!mounted || !_consentAccepted) return;
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

      // Pre-upload light check: if these frames would be locked as
      // lighting_mismatch against the baseline (same rule as the results),
      // offer a retake before spending an analysis on a locked scan.
      final lightingCheck = aiScanPreUploadLightingCheck(
        frameExposure: _analysisFrameExposureMetadata,
        baselinePayload: _previousFocusAreaScan?.rawPayload,
      );
      if (lightingCheck.wouldLock && mounted) {
        final retake = await _confirmRetakeForLighting(lightingCheck);
        if (!mounted) return;
        if (retake) {
          setState(() => _stage = _Stage.capture);
          await _pickFromCamera();
          return;
        }
      }

      // Paid gate: everything above ran on-device. No photo leaves the
      // device without a subscription or scan credit (see UploadGate).
      // Free users get a limited local results view instead, up to
      // kFreeLocalScanLimit scans, then the paywall.
      final scanRoute = await resolveScanRoute();
      // A free user's one free AI scan runs as a full backend scan under a
      // one-scan upload pass, closed in the finally below.
      if (scanRoute == ScanRoute.freeAiScan) {
        UploadGate.beginFreeAiScanUpload();
      }
      if (scanRoute != ScanRoute.backend && scanRoute != ScanRoute.freeAiScan) {
        if (!mounted) return;
        setState(() => _stage = _Stage.capture);
        if (scanRoute == ScanRoute.paywall) {
          setState(() => _analysisError = UploadGate.blockedMessage);
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PaywallScreen()),
          );
          return;
        }
        await FreeLocalScans.recordLocalScan();
        await FreeAiScans.recordScan();
        final summary = FreeLocalScanSummary.fromLocal(
          faceFound: aug.meshUsed,
          faceCoverage: aug.faceCoverage,
          symmetryScore: aug.symmetryScore,
          captureQuality: _currentCaptureQuality,
          hasBaseline: _previousFocusAreaScan?.rawPayload?.isNotEmpty ?? false,
          lightingCheck: lightingCheck,
          frames: _analysisFrameExposureMetadata,
          scansUsed: await FreeLocalScans.used(),
        );
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FreeLocalScanResultsScreen(summary: summary),
          ),
        );
        return;
      }

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
        sourceImageWidth: _capturedSourceImageWidth,
        sourceImageHeight: _capturedSourceImageHeight,
        baselineSourceImageWidth: _previousFocusAreaScan?.sourceImageWidth,
        baselineSourceImageHeight: _previousFocusAreaScan?.sourceImageHeight,
        grayCardRegion: _grayCardRegion,
      );
      final sourceResolutionMetadata = aiScanSourceResolutionMetadata(
        backendFields,
      );

      final frames = _analysisFrameBytes.isNotEmpty
          ? _analysisFrameBytes
          : <Uint8List>[backendBytes];
      // Both the metric matrix AND its extraction-path provenance now come
      // from the SAME resolved baseline entry (_previousFocusAreaScan) --
      // no more device-global manual-matrix branch that could describe a
      // different scan than the one whose provenance fields were sent.
      final resolvedBaselineMatrix = _buildLuxeBaselineMetricMatrix();
      final baselineMetricMatrixForTrend = resolvedBaselineMatrix.isEmpty
          ? null
          : resolvedBaselineMatrix;
      final storedBaselineFormulaVersions = _previousFocusAreaScan == null
          ? const <String, int>{}
          : aiScanFormulaVersions(_previousFocusAreaScan!);
      Future<Map<String, dynamic>> uploadFrame(
        Uint8List frame,
        int frameNumber, {
        bool withGrayCard = true,
      }) => remote_analysis.SkinAnalysisService.uploadSingleImageFile(
        image: XFile.fromData(
          frame,
          name: 'skin_ai_analysis_frame_$frameNumber.jpg',
          mimeType: 'image/jpeg',
        ),
        fields: withGrayCard
            ? backendFields
            : (Map<String, String>.from(backendFields)
                ..removeWhere((key, _) => key.startsWith('gray_card_'))),
        baselineMetricMatrix: baselineMetricMatrixForTrend,
        baselineExtractionPaths: _buildLuxeBaselineExtractionPaths(),
        baselineFormulaVersions: storedBaselineFormulaVersions.isEmpty
            ? null
            : storedBaselineFormulaVersions,
        grayCardPatch: withGrayCard && frameNumber - 1 < _grayCardPatches.length
            ? _grayCardPatches[frameNumber - 1]
            : null,
        allowBackend: true,
      );
      final aggregate = await analyzeBackendFrames(
        frames,
        photoUploadAccepted: _consentAccepted,
        frameExposureMetadata: _analysisFrameExposureMetadata,
        uploadFrame: uploadFrame,
        uploadFrameWithoutGrayCard: (frame, frameNumber) =>
            uploadFrame(frame, frameNumber, withGrayCard: false),
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
      // Measured same-lamp floors for texture, pigment, pores, and
      // firmness: a move strictly below the floor is "stable" with no
      // percentage. Runs before the backend-floor gate below so these moves
      // read as stable rather than locked; locks already set (and the
      // lighting lock applied later) still win.
      final measuredFloorTrend = forceStableWithinMeasuredNoiseFloors(
        trendStatus: overlapAdjustedTrend.trendStatus,
        trendDeltas: overlapAdjustedTrend.trendDeltas,
        trendLockReasons: overlapAdjustedTrend.trendLockReasons,
        averagedMetricMatrix: _dynamicMap(backendResponse['metric_matrix']),
        baselineMetricMatrix: baselineMetricMatrixForTrend ?? const {},
      );
      final noiseFloorAdjustedTrend = downgradeTrendBelowMeasuredNoiseFloor(
        trendStatus: measuredFloorTrend.trendStatus,
        trendDeltas: measuredFloorTrend.trendDeltas,
        trendLockReasons: measuredFloorTrend.trendLockReasons,
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
      // Rolling-average trend for the median-of-five metrics; runs before
      // the lock steps below so a lock still clears its verdict.
      final rollingAdjustedTrend = applyRollingTrend(
        trendStatus: noiseFloorAdjustedTrend.trendStatus,
        trendDeltas: noiseFloorAdjustedTrend.trendDeltas,
        trendLockReasons: noiseFloorAdjustedTrend.trendLockReasons,
        current: (
          id: 'current',
          timestamp: input.capturedAt,
          poseTemplate: _capturedPoseTemplate,
          guideType: _capturedGuideType,
          captureQuality: _currentCaptureQuality,
          payload: backendResponse,
        ),
        baseline: _previousFocusAreaScan == null
            ? null
            : rollingTrendScanOf(_previousFocusAreaScan!),
        history: [
          for (final scan in await AppPrefs.getScanEntries())
            if (scan.scanType == ScanHistoryEntry.scanTypeAiAnalysis)
              rollingTrendScanOf(scan),
        ],
      );
      backendResponse['rolling_trend'] = rollingAdjustedTrend.rollingTrend;
      if (_capturedScanMode != null) {
        backendResponse[aiScanModeKey] = _capturedScanMode;
      }
      final rednessAdjustedTrend = downgradeRednessTrendForCaptureMismatch(
        trendStatus: rollingAdjustedTrend.trendStatus,
        trendDeltas: rollingAdjustedTrend.trendDeltas,
        trendLockReasons: noiseFloorAdjustedTrend.trendLockReasons,
        currentPayload: backendResponse,
        baselinePayload:
            _previousFocusAreaScan?.rawPayload ?? const <String, dynamic>{},
      );
      final lightingAdjustedTrend = lockTrendsForLightingMismatch(
        trendStatus: rednessAdjustedTrend.trendStatus,
        trendDeltas: rednessAdjustedTrend.trendDeltas,
        trendLockReasons: rednessAdjustedTrend.trendLockReasons,
        currentPayload: backendResponse,
        baselinePayload:
            _previousFocusAreaScan?.rawPayload ?? const <String, dynamic>{},
      );
      final regionAdjustedTrend = lockTrendsForRegionPositionMismatch(
        trendStatus: lightingAdjustedTrend.trendStatus,
        trendDeltas: lightingAdjustedTrend.trendDeltas,
        trendLockReasons: lightingAdjustedTrend.trendLockReasons,
        currentPayload: backendResponse,
        baselinePayload:
            _previousFocusAreaScan?.rawPayload ?? const <String, dynamic>{},
      );
      final unlockedVerdictsOnly = clearLockedTrendVerdicts(
        trendStatus: regionAdjustedTrend.trendStatus,
        trendDeltas: regionAdjustedTrend.trendDeltas,
        trendLockReasons: regionAdjustedTrend.trendLockReasons,
      );
      final Map<String, double> serverTrendDeltas =
          unlockedVerdictsOnly.trendDeltas;
      final Map<String, String> serverTrendStatus =
          unlockedVerdictsOnly.trendStatus;
      final Map<String, String> serverTrendLockReasons =
          unlockedVerdictsOnly.trendLockReasons;
      // Write the (possibly downgraded) trend fields back into
      // backendResponse -- both locations _mergePayloadForPersistence reads
      // from -- so what gets persisted to ScanHistoryEntry.rawPayload
      // matches what is displayed now, rather than the pre-downgrade
      // backend verdict.
      backendResponse['trend_status'] = serverTrendStatus;
      backendResponse['trend_deltas'] = serverTrendDeltas;
      backendResponse['trend_lock_reasons'] = serverTrendLockReasons;
      backendResponse[rednessTrendLockReasonsKey] = rednessAdjustedTrend
          .rednessLockReasons
          .toList(growable: false);
      backendResponse[rednessCheekLockSkippedLowValuesKey] =
          rednessAdjustedTrend.cheekLockSkippedLowValues;
      backendResponse[rednessRegionLockSkippedLowValuesKey] =
          rednessAdjustedTrend.regionLockSkippedLowValues;
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
      )..addAll(sourceResolutionMetadata);
      // The baseline whose metrics/paths were actually sent with this
      // scan's frames -- none when no baseline matrix was sent.
      recordAiComparisonBaseline(
        persistencePayload,
        baselineScanId: baselineMetricMatrixForTrend == null
            ? null
            : _previousFocusAreaScan?.id,
        registryScanId: _aiBaselineRegistryScanId,
      );
      recordAiCaptureSharpness(
        persistencePayload,
        cropSharpness: _currentCaptureSharpness.crop,
        fullStillSharpness: _currentCaptureSharpness.fullStill,
        sharpnessFloor: _currentCaptureSharpness.floor,
      );
      final Map<String, double> rawMetricScores = _rawMetricScoresForStorage(
        persistencePayload,
      );
      final persistedMetricsNode =
          _asDynamicMap(persistencePayload['metrics']) ?? <String, dynamic>{};
      persistencePayload['metrics'] = {...persistedMetricsNode};

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
          sourceImageWidth: sourceResolutionMetadata['source_image_width'],
          sourceImageHeight: sourceResolutionMetadata['source_image_height'],
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
            sourceImageWidth: sourceResolutionMetadata['source_image_width'],
            sourceImageHeight: sourceResolutionMetadata['source_image_height'],
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
        _meshUsed = aug.meshUsed;
        _symmetryScore = aug.symmetryScore;
        _faceCoverage = aug.faceCoverage;
        _yoloUsed = aug.yoloUsed;
        _detections = aug.detections;
        _efficientNetUsed = aug.efficientNetUsed;
        _qualityScores = aug.qualityScores;
        _savedScanId = savedEntry?.id;
        _stage = _Stage.results;
      });
      await UploadGate.recordCompletedBackendScan();
      await FreeAiScans.recordScan();

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
    } finally {
      UploadGate.endFreeAiScanUpload();
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
        if (lower == 'a_p95') return;
        if (lower.endsWith('_detected')) return;
        final parsed = _safeToDouble(v);
        if (parsed == null || parsed.isNaN || parsed.isInfinite) return;
        if (parsed < 0.0) return;
        final clamped = parsed.clamp(0.0, 100.0).toDouble();
        rawScores[key] = clamped;
      });
    }

    final metricsNode = _asDynamicMap(responseMap['metrics']) ?? const {};
    final metricMatrixNode =
        _asDynamicMap(responseMap['metric_matrix']) ?? const {};
    final nestedMetricMatrixNode =
        _asDynamicMap(metricsNode['metric_matrix']) ?? const {};
    final luxeNode = _asDynamicMap(responseMap['luxePayload']) ?? const {};
    final luxeMetricMatrixNode =
        _asDynamicMap(luxeNode['metric_matrix']) ?? const {};

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
        if (parsed < 0.0) continue;
        out[key] = key == 'a_p95'
            ? parsed
            : parsed.clamp(0.0, 100.0).toDouble();
      }
      return out;
    }

    final merged = <String, dynamic>{
      ...backendResponse,
      'luxePayload': luxePayload,
    };

    final backendMetrics =
        _asDynamicMap(backendResponse['metrics']) ?? const {};
    final luxeMetrics = _asDynamicMap(luxePayload['metrics']) ?? const {};
    const backendFirstCoreKeys = <String>{
      'a_p95',
      'localized_redness',
      'texture_smoothness',
      'pigment_load',
      'pore_visibility',
      'wrinkle_load',
      'breakout_activity',
    };

    final mergedMetrics = <String, dynamic>{...backendMetrics, ...luxeMetrics};
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
    final mergedMatrix = <String, dynamic>{...backendMatrix, ...luxeMatrix};
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
    merged['trend_deltas'] = {...backendTrend, ...luxeTrend};

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

  void _startOver() {
    setState(() {
      _stage = _Stage.capture;
      _imagePath = null;
      _croppedBytes = null;
      _analysisFrameBytes = const [];
      _analysisFrameExposureMetadata = const [];
      _capturedSourceImageWidth = null;
      _capturedSourceImageHeight = null;
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        backgroundColor: AppColors.warmAlabaster,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: BackButton(
            key: const ValueKey('scan_back_home_button'),
            onPressed: _goHome,
          ),
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
            Builder(
              builder: (buttonContext) => PopupMenuButton<_DebugExportAction>(
                tooltip: 'Debug exports',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (action) async {
                  switch (action) {
                    case _DebugExportAction.setupGuide:
                      await showConsistentSetupGuide(buttonContext);
                    case _DebugExportAction.burstLog:
                      await _exportBurstLuminanceLog(buttonContext);
                    case _DebugExportAction.scanData:
                      await _exportScanData(buttonContext);
                    case _DebugExportAction.comparisonPdf:
                      await _exportComparisonPdf(buttonContext);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    key: ValueKey('menu_setup_guide'),
                    value: _DebugExportAction.setupGuide,
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Setup Guide'),
                      ],
                    ),
                  ),
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
                  PopupMenuItem(
                    value: _DebugExportAction.comparisonPdf,
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf_outlined, size: 18),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Export Comparison PDF',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
            if (_stage == _Stage.results)
              TextButton.icon(
                key: const ValueKey('results_done_button'),
                onPressed: _goHome,
                icon: const Icon(Icons.home_rounded, size: 18),
                label: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: MyApp.clinicalTeal,
                ),
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
      ),
    );
  }

  // ── Stage 1: capture ──────────────────────────────────────────────

  Widget _buildCaptureStage() {
    final canRun = (_imagePath ?? '').isNotEmpty;
    final actionLabel = _capturePrimaryActionLabel();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _heroIntro(),
        const SizedBox(height: 18),
        _captureSectionCard(
          title: 'Routines & Products',
          eyebrow: 'Procedure tools',
          icon: Icons.spa_outlined,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/routines'),
                icon: const Icon(Icons.event_note_outlined),
                label: const Text('Routines'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/log-skincare-product'),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Log Product'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/store'),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Product Store'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_showLightingTip) ...[
          LightingTipCard(
            onDismiss: () {
              setState(() => _showLightingTip = false);
              markLightingTipSeen();
            },
          ),
          const SizedBox(height: 14),
        ],
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

  Widget _scanModeChoice() {
    Widget option({
      required bool quick,
      required String title,
      required String subtitle,
    }) {
      final selected = _quickScanMode == quick;
      return Expanded(
        child: InkWell(
          key: ValueKey(quick ? 'scan_mode_quick' : 'scan_mode_controlled'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _quickScanMode = quick),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? MyApp.clinicalTeal : AppColors.borders,
                width: selected ? 1.6 : 1,
              ),
              color: selected
                  ? MyApp.clinicalTeal.withValues(alpha: 0.08)
                  : Colors.transparent,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11.5)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        option(
          quick: false,
          title: 'Controlled scan',
          subtitle: 'Recommended for tracking',
        ),
        const SizedBox(width: 8),
        option(
          quick: true,
          title: 'Quick scan',
          subtitle: 'Single photo, faster',
        ),
      ],
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
          _scanModeChoice(),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            key: const ValueKey('gray_card_switch'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _markGrayCard,
            onChanged: (value) => setState(() => _markGrayCard = value),
            title: const Text('Gray card in shot'),
            subtitle: const Text(
              'Hold a gray card in the "Place gray card here" box under your '
              'chin to correct white balance. Off sends nothing.',
            ),
          ),
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
                    _capturedSourceImageWidth = null;
                    _capturedSourceImageHeight = null;
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
              // Fixed-height button: shrink the label slightly on narrow
              // phones instead of overflowing.
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
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

  /// The scan stays local until the photo-upload acknowledgment is accepted.
  Future<bool> _reviewConsent() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                Icons.cloud_upload_outlined,
                'Face photo upload',
                'Your face photo leaves this phone and is sent to the '
                    'analysis server for processing. Accept only if you '
                    'agree to send it.',
              ),
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
    );
    if (!mounted) return false;
    if (accepted == true) setState(() => _consentAccepted = true);
    return accepted == true;
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
                          ? 'Photo upload acknowledged'
                          : 'Review face photo upload',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      accepted
                          ? 'You can run your scan. Tap “View” to read the acknowledgment again.'
                          : 'Your photo will be sent to the analysis server. Tap to review before uploading.',
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

  /// The sampled gray-card region for a scan marked as having a card, so
  /// the user can see whether the box caught the card or skin. Null when no
  /// card was marked.
  Widget? _grayCardSampleCard() {
    final quality =
        _asDynamicMap(_latestBackendAnalysisPayload?['image_quality']) ??
        const <String, dynamic>{};
    if (_grayCardPatches.isEmpty || quality['gray_card_marked'] != true) {
      return null;
    }
    return GrayCardSampleCard(
      patch: _grayCardPatches.first,
      imageQuality: quality,
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
        _asDynamicMap(luxePayload['metric_matrix']) ??
        const <String, dynamic>{};
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
              if (_grayCardSampleCard() case final card?) ...[
                const SizedBox(height: 14),
                card,
              ],
              const SizedBox(height: 14),
              isFollowUpPhase
                  ? _followUpSummaryLine()
                  : _baselinePhaseSummaryCard(),
              const SizedBox(height: 18),
              ClinicalSectionHeader(
                icon: Icons.analytics_rounded,
                eyebrow: isFollowUpPhase
                    ? 'PROGRESS METRICS'
                    : 'STARTING METRICS',
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
                currentLabel: isFollowUpPhase
                    ? 'Current Follow-Up'
                    : 'Current Scan',
                localHistoryCount: _localHistoryCountForFocusArea,
                isFollowUp: isFollowUpPhase,
                gateReason: gateReason,
                baselineNotSavedReason: _baselineNotSavedReason,
                requireBackendVerdict: true,
                hiddenMetricKeys: liveResultsHiddenMetricKeys,
                applyDisplayNoiseFloors: true,
                medianDisplayMetricKeys: medianDisplayMetricKeys,
                onRetakeForLighting: () {
                  _pickFromCamera();
                },
                onSetNewBaseline: () {
                  _confirmUpdateBaselinePressed();
                },
              ),
              if (_capturedScanMode == aiScanModeQuick) ...[
                const SizedBox(height: 10),
                const Text(
                  'Quick scan: single photo. Wrinkle load, pore contraction '
                  'and under-eye metrics need the controlled scan and are '
                  'not shown. Comparisons use the same locks.',
                  key: ValueKey('quick_scan_results_note'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              if (_savedScanId != null) ...[
                const SizedBox(height: 14),
                ScanNoteField(
                  key: ValueKey('scan_note_${_savedScanId!}'),
                  scanId: _savedScanId!,
                ),
              ],
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
      final numeric = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      return numeric == null
          ? 'Unavailable'
          : '${(numeric * 100).toStringAsFixed(0)}%';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.science_outlined,
                size: 18,
                color: AppColors.champagneGold,
              ),
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
        _meetsConcernCutoff(scores['redness'] ?? 0, 4.0) ||
        _meetsConcernCutoff(scores['rosacea_intensity'] ?? 0, 4.0);
    final sentences = <String>[];

    if (topConcerns.isEmpty) {
      sentences.add(
        isFollowUp
            ? 'This follow-up reads fairly steady against baseline, so the safest move is to keep the routine simple and consistent.'
            : 'Starting point shows a fairly calm overall pattern, so this scan is best used as your benchmark rather than a progress claim.',
      );
    } else {
      final leadPhrase = _joinWithCommasAndAnd(
        topConcerns.take(3).map((entry) => entry.label).toList(),
      );
      sentences.add(
        isFollowUp
            ? 'This follow-up centers on $leadPhrase.'
            : 'Starting point shows $leadPhrase.',
      );
    }

    final concernValues = topConcerns
        .take(3)
        .map((entry) => entry.value)
        .toList();
    if (concernValues.isNotEmpty) {
      final highest = concernValues.reduce((a, b) => a > b ? a : b);
      if (_meetsConcernCutoff(highest, 4.0)) {
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
    if (_meetsConcernCutoff(rosaceaSignal, 4.0)) {
      sentences.add(
        'Avoid fragrance, menthol, scrubs, and high-strength acids for now, because those are more likely to aggravate redness or stinging than to help this pattern.',
      );
    } else if (_meetsConcernCutoff(acneSignal, 3.5)) {
      sentences.add(
        'Breakout care should stay targeted rather than stacked, so keep any acne step spot-only or very limited until the barrier stays calm.',
      );
    } else {
      final pigmentSignal = scores['pigment'] ?? 0;
      final textureSignal = scores['texture'] ?? 0;
      final wrinkleSignal = scores['wrinkle'] ?? 0;
      final visibleTargets = <String>[
        if (_meetsConcernCutoff(pigmentSignal, 3.5)) 'tone support for pigment',
        if (_meetsConcernCutoff(textureSignal, 3.5)) 'texture support',
        if (_meetsConcernCutoff(wrinkleSignal, 3.5))
          'firmness and line support',
      ];
      if (visibleTargets.isNotEmpty) {
        sentences.add(
          'The routine should stay centered on ${_joinWithCommasAndAnd(visibleTargets)} rather than on multiple actives at once.',
        );
      }
    }

    return sentences
        .where((sentence) => sentence.trim().isNotEmpty)
        .take(6)
        .join(' ');
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

    return concerns
        .where((entry) => _meetsConcernCutoff(entry.value, 0.5))
        .take(3)
        .toList();
  }

  List<String> _coachTrendSentences(Map<String, double> scores) {
    final trendSpecs = <({String key, String label, bool lowerIsBetter})>[
      (key: 'redness', label: 'Redness', lowerIsBetter: true),
      (key: 'texture', label: 'Texture', lowerIsBetter: true),
      (key: 'pigment', label: 'Pigment', lowerIsBetter: true),
      (key: 'wrinkle', label: 'Wrinkles', lowerIsBetter: true),
      (key: 'acne_severity', label: 'Breakouts', lowerIsBetter: true),
      (
        key: 'rosacea_intensity',
        label: 'Rosacea reactivity',
        lowerIsBetter: true,
      ),
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
        sentences.add(
          '${spec.label} has $direction $qualifier versus baseline.',
        );
      } else if (trend.label == 'Stable') {
        sentences.add(
          '${spec.label} is stable versus baseline, so there is no need to chase a bigger change right now.',
        );
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
          const Icon(
            Icons.camera_alt_rounded,
            size: 16,
            color: AppColors.champagneGold,
          ),
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
        const SnackBar(content: Text('Unable to save baseline for this scan.')),
      );
    }
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
    if (value == 0.0) return true;
    return value > _baselineUsableFloor && value < _baselineUsableCeiling;
  }

  String? _baselineRejectReason(double? value) {
    if (value == null || !value.isFinite) return 'non_finite';
    if (value == 0.0) return null;
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

  String? _confidenceForMetricFromScan(
    ScanHistoryEntry scan,
    List<String> keys,
  ) {
    final payload = scan.rawPayload ?? const <String, dynamic>{};
    final metrics =
        _asDynamicMap(payload['metrics']) ?? const <String, dynamic>{};
    final luxePayload =
        _asDynamicMap(payload['luxePayload']) ?? const <String, dynamic>{};
    final luxeMetrics =
        _asDynamicMap(luxePayload['metrics']) ?? const <String, dynamic>{};

    final confidenceMaps = <Map<String, dynamic>>[
      _asDynamicMap(payload['metric_confidence']) ?? const <String, dynamic>{},
      _asDynamicMap(metrics['metric_confidence']) ?? const <String, dynamic>{},
      _asDynamicMap(luxePayload['metric_confidence']) ??
          const <String, dynamic>{},
      _asDynamicMap(luxeMetrics['metric_confidence']) ??
          const <String, dynamic>{},
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
        return (value: numeric, sourceKey: '$sourceLabel.$key');
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
  })?
  _firstUsableMetricFromScan(
    ScanHistoryEntry scan,
    String metricKey,
    List<String> orderedKeys,
  ) {
    final payload = scan.rawPayload ?? const <String, dynamic>{};
    final metrics =
        _asDynamicMap(payload['metrics']) ?? const <String, dynamic>{};
    final luxePayload =
        _asDynamicMap(payload['luxePayload']) ?? const <String, dynamic>{};
    final luxeMetrics =
        _asDynamicMap(luxePayload['metrics']) ?? const <String, dynamic>{};

    final sources = <({String label, Map<String, dynamic> map})>[
      (label: 'scan.metrics', map: Map<String, dynamic>.from(scan.metrics)),
      (
        label: 'rawPayload.metric_matrix',
        map:
            _asDynamicMap(payload['metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.baseline_metric_matrix',
        map:
            _asDynamicMap(payload['baseline_metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.baseline',
        map: _asDynamicMap(payload['baseline']) ?? const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.opencv_metrics',
        map:
            _asDynamicMap(payload['opencv_metrics']) ??
            const <String, dynamic>{},
      ),
      (label: 'rawPayload.metrics', map: metrics),
      (
        label: 'rawPayload.metrics.metric_matrix',
        map:
            _asDynamicMap(metrics['metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.metrics.baseline_metric_matrix',
        map:
            _asDynamicMap(metrics['baseline_metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.metrics.baseline',
        map: _asDynamicMap(metrics['baseline']) ?? const <String, dynamic>{},
      ),
      (label: 'rawPayload.luxePayload', map: luxePayload),
      (
        label: 'rawPayload.luxePayload.metric_matrix',
        map:
            _asDynamicMap(luxePayload['metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.luxePayload.baseline_metric_matrix',
        map:
            _asDynamicMap(luxePayload['baseline_metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.luxePayload.baseline',
        map:
            _asDynamicMap(luxePayload['baseline']) ?? const <String, dynamic>{},
      ),
      (label: 'rawPayload.luxePayload.metrics', map: luxeMetrics),
      (
        label: 'rawPayload.luxePayload.metrics.metric_matrix',
        map:
            _asDynamicMap(luxeMetrics['metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.luxePayload.metrics.baseline_metric_matrix',
        map:
            _asDynamicMap(luxeMetrics['baseline_metric_matrix']) ??
            const <String, dynamic>{},
      ),
      (
        label: 'rawPayload.luxePayload.metrics.baseline',
        map:
            _asDynamicMap(luxeMetrics['baseline']) ?? const <String, dynamic>{},
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
      final confLabel =
          _confidenceForMetricFromScan(scan, orderedKeys) ?? 'unknown';
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
  _resolvePriorBaselineForMetric(String metricKey, List<String> aliases) {
    if (_priorFocusAreaScans.isEmpty) return null;
    final orderedKeys = <String>[metricKey, ...aliases];
    ({
      double value,
      String sourceKey,
      String priorScanId,
      int priorIndex,
      String confidenceLabel,
      int confidenceRank,
    })?
    best;

    for (var i = 0; i < _priorFocusAreaScans.length; i++) {
      final scan = _priorFocusAreaScans[i];
      final hit = _firstUsableMetricFromScan(scan, metricKey, orderedKeys);
      if (hit == null || !hit.sourceKey.contains('metric_matrix')) continue;

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

    final rawPayload = priorScan.rawPayload ?? const <String, dynamic>{};
    final canonicalBaseline = aiBaselineMetricMatrixFromPayload(rawPayload);

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
      if (!hasUsableExisting &&
          existingNumeric != null &&
          existingNumeric.isFinite) {
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

  Map<String, String> _buildLuxeBaselineExtractionPaths() =>
      aiBaselineExtractionPathsForRequest(_previousFocusAreaScan?.rawPayload);

  Map<String, dynamic> _buildLuxeResultsPayload(
    PhotoAnalysisResult r, {
    Map<String, dynamic>? backendResponse,
  }) {
    final isFollowUp =
        _explicitLocalFollowUpFlag || _localHistoryCountForFocusArea >= 2;

    final backendMetricsNode =
        _asDynamicMap(backendResponse?['metrics']) ?? const <String, dynamic>{};
    final backendMetricMatrix =
        _asDynamicMap(backendResponse?['metric_matrix']) ??
        _asDynamicMap(backendMetricsNode['metric_matrix']) ??
        const <String, dynamic>{};

    final cleanedMetricMatrix = <String, dynamic>{};
    for (final entry in backendMetricMatrix.entries) {
      final parsed = _safeToDouble(entry.value);
      if (parsed == null || parsed.isNaN || parsed.isInfinite) continue;
      if (parsed < 0.0) continue;
      cleanedMetricMatrix[entry.key] = entry.key == 'a_p95'
          ? parsed
          : parsed.clamp(0.0, 100.0).toDouble();
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
      'metric_extraction_paths':
          _asDynamicMap(backendResponse?['metric_extraction_paths']) ??
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
    // A quick scan becomes a baseline only when the user explicitly sets it.
    if (isQuickAiScan(savedEntry)) {
      if (!mounted) return;
      setState(() {
        _baselineNotSavedReason =
            'Quick scans are not saved as a baseline automatically. Use '
            'a controlled scan, or set this one as your baseline.';
      });
      return;
    }
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
      final keyMatches =
          scans.where((scan) => scan.aiBaselineKey == key).toList()
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
    final captureQualityLabel = captureQualityBadgeLabel(
      _currentCaptureQuality,
    );
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
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

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

  void _goHome() => navigateHomeFrom(Navigator.of(context));

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

  Widget _buildRecommendationsSection(Map<String, dynamic> metricMatrix) {
    final scores = _recommendationScoresFromMetricMatrix(metricMatrix);
    if (_isBodyProcedure) {
      return _buildBodyRecoveryRecommendationsSection(scores);
    }

    final isFollowUp =
        _explicitLocalFollowUpFlag || _localHistoryCountForFocusArea >= 2;
    // No backend equivalent exists for the old local-heuristic "skin
    // sensitivity" proxy (see _coachInsightForPhase's identical note) —
    // kept as an explicit 0.0 rather than removed from
    // _routineForScores/_coachRoutineHeaderText's shared signatures below.
    const sensitivitySignal = 0.0;
    final barrierStressed =
        sensitivitySignal >= 4.0 ||
        _meetsConcernCutoff(scores['redness'] ?? 0, 4.0) ||
        _meetsConcernCutoff(scores['rosacea_intensity'] ?? 0, 4.0);

    final redness = scores['redness'] ?? 0;
    final rosacea = scores['rosacea_intensity'] ?? 0;
    final acne = scores['acne_severity'] ?? 0;
    final inflammation = [
      redness,
      rosacea,
      acne,
    ].reduce((a, b) => a > b ? a : b);
    final treatInflammationFirst =
        _meetsConcernCutoff(inflammation, 4.0) || barrierStressed;

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
  /// real formula-metric key onto the backend's 0–100 scale; a key absent from
  /// metricMatrix (the backend didn't trust it for this scan) scores 0,
  /// same as "no concern found" rather than a fabricated guess.
  Map<String, double> _recommendationScoresFromMetricMatrix(
    Map<String, dynamic> metricMatrix,
  ) {
    double backendValue(String key) {
      final raw = metricMatrix[key];
      final parsed = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (parsed == null || parsed.isNaN || parsed.isInfinite) return 0.0;
      return (parsed.clamp(0.0, 100.0) as num).toDouble();
    }

    final textureSmoothness = backendValue('texture_smoothness');
    return {
      'pigment': backendValue('pigment_load'),
      'redness': backendValue('localized_redness'),
      // Inverted: texture_smoothness is "higher = smoother = better", but
      // this map's convention (matching the rest of this file) is
      // "higher = more concern".
      'texture': (100.0 - textureSmoothness).clamp(0.0, 100.0).toDouble(),
      'wrinkle': backendValue('wrinkle_load'),
      'acne_severity': backendValue('breakout_activity'),
      'rosacea_intensity': backendValue('rosacea_severity'),
    };
  }

  bool _meetsConcernCutoff(double backendValue, double tenPointCutoff) =>
      backendValue >= tenPointCutoff * 10.0;

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
      if (_meetsConcernCutoff(redness, 4.0)) 'redness',
      if (_meetsConcernCutoff(rosacea, 4.0)) 'rosacea',
      if (_meetsConcernCutoff(acne, 3.5)) 'breakouts',
      if (_meetsConcernCutoff(texture, 3.5)) 'texture',
      if (_meetsConcernCutoff(pigment, 3.5)) 'pigment',
      if (_meetsConcernCutoff(wrinkle, 3.5)) 'wrinkles',
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

    if (_meetsConcernCutoff(inflammation, 4)) {
      add(
        'SKIN1004 Madagascar Centella Ampoule',
        'Best first step when redness/rosacea/acne are leading. Centella keeps the routine calming before stronger actives.',
        Icons.local_florist_rounded,
        MyApp.clinicalTeal,
      );
      add(
        'COSRX Advanced Snail 96 Mucin Essence',
        'A light barrier-support layer for reactive days; helpful when redness or texture feels stressed.',
        Icons.water_drop_outlined,
        MyApp.clinicalTeal,
      );
    }

    if (_meetsConcernCutoff(acne, 3.5)) {
      add(
        'COSRX Acne Pimple Master Patch',
        'Spot-focused support for active breakouts without adding an all-over active while inflammation is high.',
        Icons.radio_button_checked_rounded,
        const Color(0xFFD06B6B),
      );
      add(
        'Some By Mi AHA-BHA-PHA 30 Days Miracle Toner',
        'Consider only 1-2 nights weekly after skin feels calm; active breakouts suggest pores may benefit from slow exfoliation.',
        Icons.science_outlined,
        const Color(0xFFD06B6B),
      );
    }

    if (_meetsConcernCutoff(rosacea, 3.5) ||
        _meetsConcernCutoff(redness, 3.5)) {
      add(
        'SKIN1004 Centella Probio-Cica Intensive Ampoule',
        'A richer cica option for redness/rosacea-prone days; pairs well with a simple moisturizer and SPF.',
        Icons.spa_rounded,
        MyApp.clinicalTeal,
      );
    }

    if (_meetsConcernCutoff(pigment, 3.5) ||
        !_meetsConcernCutoff(redness, 4) && !_meetsConcernCutoff(acne, 4)) {
      add(
        'COSRX The Niacinamide 15 Serum',
        'Niacinamide is a good bridge active for pigment and visible redness, but start slowly if skin is reactive.',
        Icons.tonality_rounded,
        MyApp.goldShimmer,
      );
    }

    if ((_meetsConcernCutoff(texture, 3.5) ||
            _meetsConcernCutoff(wrinkle, 3.5)) &&
        !_meetsConcernCutoff(inflammation, 6)) {
      add(
        'Copper peptide serum / GHK-Cu peptide serum',
        'A barrier-friendly PM option for texture and wrinkle support without jumping straight to harsh actives.',
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
    final calmFirst =
        _meetsConcernCutoff(inflammation, 4) ||
        barrierStressed ||
        sensitivitySignal >= 4;
    final allowActives = !calmFirst && isFollowUp;

    final am = <String>[
      calmFirst
          ? 'Gentle low-pH cleanser or a water rinse if your skin is dry, so the barrier stays quiet while redness and sensitivity settle.'
          : 'Gentle low-pH cleanser to lift overnight oil and sunscreen without stripping the skin that this scan is trying to protect.',
      calmFirst
          ? 'Centella or heartleaf toner / essence, because that is the calmest way to support a reactive barrier before any active treatment.'
          : _meetsConcernCutoff(pigment, 3.5)
          ? 'Hydrating toner or essence, because the scan shows tone support is useful and hydration keeps brightening steps better tolerated.'
          : _meetsConcernCutoff(texture, 3.5) ||
                _meetsConcernCutoff(wrinkle, 3.5)
          ? 'Peptide-friendly hydrating essence, because texture and firmness work best when the skin is comfortable first.'
          : 'Simple hydrating essence, because the skin does not need extra noise in the morning.',
      calmFirst
          ? 'Ceramide moisturizer only, or a niacinamide 2-5% serum if you already know your skin tolerates it, so the morning stays barrier-first.'
          : _meetsConcernCutoff(acne, 3.5)
          ? 'Niacinamide 2-5% serum or a light breakout-support serum, because the scan shows acne is present but the routine should still avoid stacking actives.'
          : _meetsConcernCutoff(pigment, 3.5)
          ? 'Niacinamide 2-5% serum, because it fits uneven tone and visible redness without pushing the skin too hard.'
          : 'Ceramide moisturizer, because keeping water in the skin is still the safest way to support the current scan pattern.',
      'Broad-spectrum SPF 30+, because it protects collagen, pigment, redness, and any progress this scan is tracking.',
    ];

    final pm = <String>[
      'Gentle cleanse, and if you wore sunscreen or makeup, double cleanse first so the evening routine starts from a clean surface.',
      calmFirst
          ? 'Centella, snail mucin, or a bland hydrating serum tonight, because the scan says calming the barrier should come before any stronger treatment.'
          : allowActives &&
                (_meetsConcernCutoff(texture, 3.5) ||
                    _meetsConcernCutoff(wrinkle, 3.5))
          ? 'GHK-Cu Copper Tripeptide-1 at night, because texture and firmness concerns respond best when the barrier is calm and the routine stays consistent.'
          : allowActives && _meetsConcernCutoff(pigment, 3.5)
          ? 'GHK-Cu Copper Tripeptide-1 or another gentle peptide serum, because the scan favors quiet repair more than aggressive exfoliation.'
          : 'Hydrating serum or peptide step only if the skin stays comfortable, because the routine does not need to be overloaded.',
      calmFirst
          ? 'Ceramide barrier cream, because sealing the routine with lipids is the safest way to keep the skin quiet while redness or sensitivity is visible.'
          : _meetsConcernCutoff(acne, 3.5)
          ? 'Barrier cream plus a spot-only acne patch on active blemishes, because breakout support should stay targeted instead of turning into a full-face stack.'
          : 'Barrier cream, because this scan still benefits more from steady repair than from piling on more treatment steps.',
      calmFirst
          ? 'Skip acids, retinoids, and scrubs for now; if you want a weekly active later, wait until the skin is calm for several nights in a row.'
          : allowActives &&
                (_meetsConcernCutoff(texture, 3.5) ||
                    _meetsConcernCutoff(wrinkle, 3.5) ||
                    _meetsConcernCutoff(pigment, 3.5))
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
                  Expanded(child: _routineColumn('PM', pmSteps, pmAccent)),
                ],
              )
            else
              _framingNote('Routine tips unlock from your scores.'),
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
                    requireBackendVerdictForTrustedMetrics: true,
                    hiddenMetricKeys: liveResultsHiddenMetricKeys,
                    applyDisplayNoiseFloors: true,
                    medianDisplayMetricKeys: medianDisplayMetricKeys,
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
      _body['baseline_metric_matrix'] ??
          analysisResult['baseline_metric_matrix'],
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
      _body['metric_extraction_paths'] ??
          analysisResult['metric_extraction_paths'],
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
