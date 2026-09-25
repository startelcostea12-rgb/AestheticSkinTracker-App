import '../models/scan_history.dart';

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
    'image_width',
    'image_height',
    'image_quality.lighting_mean_l',
    'image_quality.lighting_std_l',
    'image_quality.chroma_cast',
    'image_quality.lighting_balance_score',
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

  static List<ScanHistoryEntry> exportableScans(
    Iterable<ScanHistoryEntry> scans,
  ) => scans
      .where(
        (scan) =>
            scan.scanType == ScanHistoryEntry.scanTypeAiAnalysis &&
            _hasAiBackendPayload(scan.rawPayload),
      )
      .toList(growable: false);

  static String format(Iterable<ScanHistoryEntry> scans) {
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
    final columns = <String>[
      ..._baseColumns,
      ...metricColumns,
      ...qualityColumns.where((column) => !_baseColumns.contains(column)),
    ];

    final rows = <List<String>>[
      columns,
      for (final entry in entries)
        _rowFor(entry, columns, flattenedQuality[entry]!),
    ];
    return rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
  }

  static List<String> _rowFor(
    ScanHistoryEntry scan,
    List<String> columns,
    Map<String, dynamic> flattenedQuality,
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
      'is_baseline': scan.isBaseline,
      'comparison_baseline_scan_id':
          scan.parentBaselineId ??
          _storedValue(payload, const [
            'comparison_baseline_scan_id',
            'comparisonBaselineScanId',
            'baseline_scan_id',
            'baselineScanId',
          ]),
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
