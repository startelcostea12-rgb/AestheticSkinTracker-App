import '../models/scan_history.dart';
import 'ai_capture_sharpness.dart';
import 'ai_comparison_baseline.dart';
import 'display_aggregation.dart';
import 'display_noise_floors.dart';

const List<String> aiScanDataCanonicalMetricKeys = <String>[
  'localized_redness',
  'texture_smoothness',
  'pigment_load',
  'pore_visibility',
  'chin_pore_visibility',
  'wrinkle_load',
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
];

class AiScanDataCsvExporter {
  const AiScanDataCsvExporter._();

  static const List<String> _baseColumns = <String>[
    'timestamp',
    'scan_id',
    'poseTemplate',
    'guideType',
    'captureQuality',
    'backend_commit',
    'is_baseline',
    'comparison_baseline_scan_id',
    'comparison_baseline_source',
    'scan_note',
    // "quick" (single-photo quick scan) or "controlled"; empty for scans
    // saved before the mode was recorded.
    'scan_mode',
    aiCaptureCropSharpnessKey,
    aiCaptureFullStillSharpnessKey,
    aiCaptureSharpnessFloorKey,
    'redness_cheek_lock_skipped_low_values',
    'redness_region_lock_skipped_low_values',
    'image_width',
    'image_height',
    'a_p95',
    'image_quality.lighting_mean_l',
    'image_quality.lighting_std_l',
    'image_quality.chroma_cast',
    'image_quality.lighting_balance_score',
    ...colorDiagnosticColumns,
  ];

  /// Signed color / redness-branch logging fields main.py adds to
  /// image_quality. Always present as columns; empty on scans saved before
  /// the backend emitted them. The post-clip white-balance adjustments get
  /// their own columns rather than reusing white_balance_profile's.
  static const List<String> colorDiagnosticColumns = <String>[
    'image_quality.color_lab_units',
    'image_quality.whole_image_mean_a_before_wb',
    'image_quality.whole_image_mean_b_before_wb',
    'image_quality.whole_image_mean_a_after_wb',
    'image_quality.whole_image_mean_b_after_wb',
    'image_quality.wb_a_adjustment_post_clip',
    'image_quality.wb_b_adjustment_post_clip',
    'image_quality.redness_branch',
    'image_quality.redness_reference_source',
    'image_quality.redness_cheek_side',
    'image_quality.cheek_side_convention',
    'image_quality.redness_both_cheeks_in_dead_zone',
    'image_quality.redness_cheek_roi_pixels',
    'image_quality.redness_cheek_mean_a_after_wb',
    'image_quality.redness_cheek_mean_b_after_wb',
    'image_quality.redness_cheek_p10_a_after_wb',
    'image_quality.redness_cheek_p95_a_after_wb',
    'image_quality.redness_cheek_p10_a_before_wb',
    'image_quality.redness_cheek_p95_a_before_wb',
    'image_quality.redness_baseline_cheek_p95_a',
    // Gray-card white balance, scan-level summary across frames (see
    // summarizeGrayCardFrames); per frame under frameN_gray_card_*.
    'image_quality.gray_card_marked',
    'image_quality.gray_card_mean_L',
    'image_quality.gray_card_mean_a',
    'image_quality.gray_card_mean_b',
    'image_quality.gray_card_correction_applied',
    'image_quality.gray_card_frames_applied',
    'image_quality.gray_card_reason',
    'image_quality.gray_card_region_space',
    'image_quality.gray_card_region_x',
    'image_quality.gray_card_region_y',
    'image_quality.gray_card_region_w',
    'image_quality.gray_card_region_h',
    // Region boxes for region_position_mismatch (face-width units).
    'image_quality.wrinkle_region_box_cx',
    'image_quality.wrinkle_region_box_cy',
    'image_quality.wrinkle_region_box_w',
    'image_quality.wrinkle_region_box_h',
    'image_quality.pore_contraction_roi_box_cx',
    'image_quality.pore_contraction_roi_box_cy',
    'image_quality.pore_contraction_roi_box_w',
    'image_quality.pore_contraction_roi_box_h',
    'image_quality.under_eye_left_box_cx',
    'image_quality.under_eye_left_box_cy',
    'image_quality.under_eye_left_box_w',
    'image_quality.under_eye_left_box_h',
    'image_quality.under_eye_right_box_cx',
    'image_quality.under_eye_right_box_cy',
    'image_quality.under_eye_right_box_w',
    'image_quality.under_eye_right_box_h',
  ];

  static const List<String> _metricFields = <String>[
    'value',
    'frame_min',
    'frame_max',
    'trend_status',
    'trend_lock_reason',
    'extraction_path',
    'formula_version',
    'noise_floor',
    'display_aggregation',
  ];

  /// Metrics with a rolling-average trend note (rolling_trend in the saved
  /// payload) and the note fields exported as `<metric>_rolling_<field>`.
  static const List<String> rollingTrendExportMetricKeys = <String>[
    'wrinkle_load',
    'pore_contraction_index',
    'under_eye_dark_circle_density',
    'under_eye_texture_density',
  ];
  static const List<String> rollingTrendExportFields = <String>[
    'method',
    'current_value',
    'baseline_value',
    'baseline_method',
  ];

  /// Per-frame columns frame1..frame5 (the AI scan captures five frames;
  /// older three-frame scans leave frames 4-5 empty).
  static const int exportedFrameCount = 5;

  static const List<String> perFrameFields = <String>[
    'cheek_side',
    'cheek_side_convention',
    'redness_both_cheeks_in_dead_zone',
    'mask_pixel_count',
    'cheek_p95_a_after_wb',
    'cheek_p10_a_after_wb',
    'cheek_p10_a_before_wb',
    'localized_redness',
    'gray_card_marked',
    'gray_card_mean_L',
    'gray_card_mean_a',
    'gray_card_mean_b',
    'gray_card_correction_applied',
    'gray_card_reason',
    'gray_card_region_space',
    'gray_card_region_x',
    'gray_card_region_y',
    'gray_card_region_w',
    'gray_card_region_h',
    'iso',
    'exposure_bias',
    'shutter_seconds',
    'brightness_value',
    'flash_fired',
    'exposure_lock_succeeded',
    'lens_position',
    'white_balance_temperature',
    'white_balance_red_gain',
    'white_balance_green_gain',
    'white_balance_blue_gain',
    'face_skin_pixels',
    'pore_roi_pixels',
    'u_zone_pixels',
    'localized_redness_mask_kind',
    'localized_redness_mask_pixels',
    'texture_smoothness_mask_kind',
    'texture_smoothness_mask_pixels',
    'pigment_load_mask_kind',
    'pigment_load_mask_pixels',
    'pore_visibility_mask_kind',
    'pore_visibility_mask_pixels',
    'pore_visibility_extraction_path',
    'chin_pore_visibility_mask_kind',
    'chin_pore_visibility_mask_pixels',
    'diffuse_flushing_erythema_mask_kind',
    'diffuse_flushing_erythema_mask_pixels',
    'under_eye_dark_circle_density_mask_kind',
    'under_eye_dark_circle_density_mask_pixels',
    'under_eye_dark_circle_density_omit_reason',
    'under_eye_texture_density_mask_kind',
    'under_eye_texture_density_mask_pixels',
    'under_eye_texture_density_omit_reason',
  ];

  static List<ScanHistoryEntry> exportableScans(
    Iterable<ScanHistoryEntry> scans,
  ) => scans
      .where(
        (scan) =>
            scan.scanType == ScanHistoryEntry.scanTypeAiAnalysis &&
            _hasAiBackendPayload(scan.rawPayload),
      )
      .toList(growable: false);

  /// [registryBaselineScanIds] is every scan id currently registered in the
  /// per-key AI baseline registry (AppPrefs.getAllAiBaselineScanIds);
  /// is_baseline is membership in it, never the procedure isBaseline flag.
  static String format(
    Iterable<ScanHistoryEntry> scans, {
    required Set<String> registryBaselineScanIds,
  }) {
    final entries = exportableScans(scans);
    final flattenedQuality = <ScanHistoryEntry, Map<String, dynamic>>{
      for (final entry in entries)
        entry: _flattenMap(
          _payloadMap(entry.rawPayload, 'image_quality'),
          prefix: 'image_quality',
        ),
    };
    final qualityColumns =
        flattenedQuality.values.expand((values) => values.keys).toSet().toList()
          ..sort();
    final metricColumns = <String>[
      for (final metric in aiScanDataCanonicalMetricKeys)
        for (final field in _metricFields) '${metric}_$field',
      // Rolling-average trend note (median-of-five metrics only).
      for (final metric in rollingTrendExportMetricKeys)
        for (final field in rollingTrendExportFields)
          '${metric}_rolling_$field',
    ];
    final perFrameColumns = <String>[
      for (var frame = 1; frame <= exportedFrameCount; frame++)
        for (final field in perFrameFields) 'frame${frame}_$field',
    ];
    final columns = <String>[
      ..._baseColumns,
      ...metricColumns,
      ...perFrameColumns,
      ...qualityColumns.where((column) => !_baseColumns.contains(column)),
    ];

    final rows = <List<String>>[
      columns,
      for (final entry in entries)
        _rowFor(
          entry,
          columns,
          flattenedQuality[entry]!,
          registryBaselineScanIds,
        ),
    ];
    return rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
  }

  static List<String> _rowFor(
    ScanHistoryEntry scan,
    List<String> columns,
    Map<String, dynamic> flattenedQuality,
    Set<String> registryBaselineScanIds,
  ) {
    final payload = scan.rawPayload!;
    final values = <String, dynamic>{
      'timestamp': scan.timestamp.toIso8601String(),
      'scan_id': scan.id,
      'poseTemplate': scan.poseTemplate,
      'guideType': scan.guideType,
      'captureQuality':
          scan.captureQuality ??
          _storedValue(payload, const ['capture_quality']),
      'backend_commit': _storedValue(payload, const [
        'backend_commit',
        'backendCommit',
        'git_commit',
        'gitCommit',
        'commit',
      ]),
      'is_baseline': registryBaselineScanIds.contains(scan.id),
      // Only the id recorded at comparison time; empty on older scans.
      'comparison_baseline_scan_id': payload[aiComparisonBaselineScanIdKey],
      'comparison_baseline_source': payload[aiComparisonBaselineSourceKey],
      // Empty notes are never stored, so the cell is empty without one.
      'scan_note': payload['scan_note'],
      'scan_mode': payload['ai_scan_mode'],
      // Sharpness that decided captureQuality; empty on older scans.
      aiCaptureCropSharpnessKey: payload[aiCaptureCropSharpnessKey],
      aiCaptureFullStillSharpnessKey: payload[aiCaptureFullStillSharpnessKey],
      aiCaptureSharpnessFloorKey: payload[aiCaptureSharpnessFloorKey],
      // True when redness compared despite a single-cheek vs both-cheeks
      // reading because both values were low; empty on older scans.
      'redness_cheek_lock_skipped_low_values':
          payload['redness_cheek_lock_skipped_low_values'],
      // True when redness compared despite a single-cheek vs U-zone region
      // because both values were low; empty on older scans.
      'redness_region_lock_skipped_low_values':
          payload['redness_region_lock_skipped_low_values'],
      'image_width':
          scan.sourceImageWidth ??
          _storedValue(payload, const ['source_image_width']),
      'image_height':
          scan.sourceImageHeight ??
          _storedValue(payload, const ['source_image_height']),
      ...flattenedQuality,
      'a_p95': _payloadMap(payload, 'metric_matrix')['a_p95'],
    };
    values.putIfAbsent(
      'image_quality.redness_reference_source',
      () => _storedValue(payload, const ['redness_reference_source']),
    );

    final matrix = _payloadMap(payload, 'metric_matrix');
    final ranges = _nestedPayloadMap(
      payload,
      'multi_frame_analysis',
      'metric_ranges',
    );
    final statuses = _payloadMap(payload, 'trend_status');
    final lockReasons = _payloadMap(payload, 'trend_lock_reasons');
    final extractionPaths = _payloadMap(payload, 'metric_extraction_paths');
    final formulaVersions = _payloadMap(payload, 'metric_formula_versions');
    final frameDiagnostics = payload['per_frame_diagnostics'] is List
        ? payload['per_frame_diagnostics'] as List
        : const <dynamic>[];

    for (final metric in aiScanDataCanonicalMetricKeys) {
      final range = _asMap(ranges[metric]);
      values['${metric}_value'] = matrix[metric];
      values['${metric}_frame_min'] = range['min'];
      values['${metric}_frame_max'] = range['max'];
      values['${metric}_trend_status'] = statuses[metric];
      values['${metric}_trend_lock_reason'] = lockReasons[metric];
      values['${metric}_extraction_path'] = extractionPaths[metric];
      values['${metric}_formula_version'] = formulaVersions[metric];
      // The display noise floor the live results card applies to this
      // metric's verdict; empty for metrics without one.
      values['${metric}_noise_floor'] = displayVerdictNoiseFloors[metric];
      // How the live results views aggregate this metric's frames for the
      // shown number; *_value above is always the saved mean.
      values['${metric}_display_aggregation'] = liveDisplayAggregationFor(
        metric,
      );
    }

    final rollingTrend = _payloadMap(payload, 'rolling_trend');
    for (final metric in rollingTrendExportMetricKeys) {
      final note = _asMap(rollingTrend[metric]);
      for (final field in rollingTrendExportFields) {
        values['${metric}_rolling_$field'] = note[field];
      }
    }

    for (var index = 0; index < exportedFrameCount; index++) {
      final frame = index < frameDiagnostics.length
          ? _asMap(frameDiagnostics[index])
          : const <String, dynamic>{};
      for (final field in perFrameFields) {
        values['frame${index + 1}_$field'] = frame[field];
      }
    }

    return columns.map((column) => _csvCell(values[column])).toList();
  }

  static bool _hasAiBackendPayload(Map<String, dynamic>? payload) {
    if (payload == null || payload.isEmpty) return false;
    const markers = <String>{
      'metric_matrix',
      'multi_frame_analysis',
      'image_quality',
      'trend_status',
      'trend_lock_reasons',
      'metric_formula_versions',
      'modelUsed',
      'model_used',
    };
    return _payloadCandidates(
      payload,
    ).any((candidate) => markers.any(candidate.containsKey));
  }

  static Map<String, dynamic> _payloadMap(
    Map<String, dynamic>? payload,
    String key,
  ) {
    if (payload == null) return const <String, dynamic>{};
    for (final candidate in _payloadCandidates(payload)) {
      final direct = _asMap(candidate[key]);
      if (direct.isNotEmpty) return direct;
    }
    return const <String, dynamic>{};
  }

  static Map<String, dynamic> _nestedPayloadMap(
    Map<String, dynamic>? payload,
    String parent,
    String key,
  ) {
    if (payload == null) return const <String, dynamic>{};
    for (final candidate in _payloadCandidates(payload)) {
      final nested = _asMap(_asMap(candidate[parent])[key]);
      if (nested.isNotEmpty) return nested;
    }
    return const <String, dynamic>{};
  }

  static Iterable<Map<String, dynamic>> _payloadCandidates(
    Map<String, dynamic> payload,
  ) sync* {
    yield payload;
    final metrics = _asMap(payload['metrics']);
    if (metrics.isNotEmpty) yield metrics;
    final luxePayload = _asMap(payload['luxePayload']);
    if (luxePayload.isNotEmpty) {
      yield luxePayload;
      final luxeMetrics = _asMap(luxePayload['metrics']);
      if (luxeMetrics.isNotEmpty) yield luxeMetrics;
    }
  }

  static Map<String, dynamic> _flattenMap(
    Map<String, dynamic> source, {
    required String prefix,
  }) {
    final output = <String, dynamic>{};
    void visit(Map<String, dynamic> values, String path) {
      for (final entry in values.entries) {
        final key = '$path.${entry.key}';
        if (entry.value is Map) {
          visit(_asMap(entry.value), key);
        } else {
          output[key] = entry.value is Iterable
              ? (entry.value as Iterable).map(_csvCell).join('|')
              : entry.value;
        }
      }
    }

    visit(source, prefix);
    return output;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static Object? _storedValue(Map<String, dynamic> payload, List<String> keys) {
    for (final candidate in _payloadCandidates(payload)) {
      for (final key in keys) {
        final value = candidate[key];
        if (value != null) return value;
      }
    }
    return null;
  }

  static String _csvCell(Object? value) {
    if (value == null) return '';
    final text = value.toString();
    if (!text.contains(RegExp('[",\r\n]'))) return text;
    return '"${text.replaceAll('"', '""')}"';
  }
}
