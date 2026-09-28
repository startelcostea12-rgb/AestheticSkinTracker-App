import '../models/scan_history.dart';
import 'ai_comparison_baseline.dart';

const List<String> aiScanDataCanonicalMetricKeys = <String>[
  'localized_redness',
  'texture_smoothness',
  'pigment_load',
  'pore_visibility',
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
    'image_width',
    'image_height',
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
    'image_quality.redness_cheek_side',
    'image_quality.cheek_side_convention',
    'image_quality.redness_cheek_roi_pixels',
    'image_quality.redness_cheek_mean_a_after_wb',
    'image_quality.redness_cheek_mean_b_after_wb',
    'image_quality.redness_cheek_p10_a_after_wb',
    'image_quality.redness_cheek_p95_a_after_wb',
    'image_quality.redness_cheek_p10_a_before_wb',
    'image_quality.redness_cheek_p95_a_before_wb',
    'image_quality.redness_baseline_cheek_p95_a',
  ];

  static const List<String> _metricFields = <String>[
    'value',
    'frame_min',
    'frame_max',
    'trend_status',
    'trend_lock_reason',
    'extraction_path',
    'formula_version',
  ];

  static const List<String> perFrameFields = <String>[
    'cheek_side',
    'cheek_side_convention',
    'mask_pixel_count',
    'cheek_p95_a_after_wb',
    'cheek_p10_a_after_wb',
    'cheek_p10_a_before_wb',
    'localized_redness',
    'iso',
    'exposure_bias',
    'shutter_seconds',
    'brightness_value',
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
    'diffuse_flushing_erythema_mask_kind',
    'diffuse_flushing_erythema_mask_pixels',
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
    ];
    final perFrameColumns = <String>[
      for (var frame = 1; frame <= 3; frame++)
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
      'image_width':
          scan.sourceImageWidth ??
          _storedValue(payload, const ['source_image_width']),
      'image_height':
          scan.sourceImageHeight ??
          _storedValue(payload, const ['source_image_height']),
      ...flattenedQuality,
    };

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
    }

    for (var index = 0; index < 3; index++) {
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
