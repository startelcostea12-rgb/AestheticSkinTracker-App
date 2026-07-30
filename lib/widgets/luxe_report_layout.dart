import 'dart:async';

import 'package:flutter/material.dart';

import 'before_after_split_slider.dart';

class LuxeMetric {
  const LuxeMetric({
    required this.key,
    required this.name,
    required this.baselineScore,
    required this.currentScore,
    required this.improvementPercent,
    required this.lowerIsBetter,
    this.initialBaseline = false,
    this.currentConfidence,
    this.hasDetectedCurrentValue = false,
    this.hasComparableCurrentValue = true,
  });

  final String key;
  final String name;
  final double baselineScore;
  final double currentScore;
  final double improvementPercent;
  final bool lowerIsBetter;
  final bool initialBaseline;
  final Object? currentConfidence;
  final bool hasDetectedCurrentValue;
  final bool hasComparableCurrentValue;
}

class _ExtractedMetricValue {
  const _ExtractedMetricValue({
    required this.value,
    required this.sourceMapKey,
  });

  final double value;
  final String sourceMapKey;
}

class LuxeMetricParser {
  const LuxeMetricParser._();

  static const double _baselineUsableFloor = 0.5;
  static const double _baselineUsableCeiling = 99.5;
  static const double _displayDeltaCapPercent = 100.0;
  static const double _displayDeltaPointsBaselineThreshold = 10.0;

  static bool shouldDisplayPointDelta(double baseline) {
    return baseline > 0.0 && baseline < _displayDeltaPointsBaselineThreshold;
  }

  static String formatDisplayDelta({
    required double baseline,
    required double current,
    required double deltaPct,
    bool includeSign = false,
  }) {
    if (shouldDisplayPointDelta(baseline)) {
      final points = (current - baseline).abs();
      final sign = includeSign
          ? (deltaPct > 0
                ? '+'
                : (deltaPct < 0 ? '-' : ''))
          : '';
      return '$sign${points.toStringAsFixed(1)} pts';
    }

    final capped = deltaPct.clamp(
      -_displayDeltaCapPercent,
      _displayDeltaCapPercent,
    ).toDouble();
    if (includeSign) {
      final sign = capped > 0 ? '+' : '';
      return '$sign${capped.toStringAsFixed(1)}%';
    }
    return '${capped.abs().toStringAsFixed(1)}%';
  }

  static double displayDeltaMagnitude({
    required double baseline,
    required double current,
    required double deltaPct,
  }) {
    if (shouldDisplayPointDelta(baseline)) {
      return (current - baseline).abs();
    }
    return deltaPct.abs().clamp(0.0, _displayDeltaCapPercent).toDouble();
  }

  static const Map<String, String> _metricKeyAliases = {
    // Canonical-only display pipeline: no legacy aliases.
  };

  static const Set<String> _defectMetricKeys = {
    'localized_redness',
    'breakout_activity',
    'pigment_load',
    'wrinkle_load',
    'pore_visibility',
    'adaptive_dark_ratio',
    'sebum_excess_oil_gloss',
    'diffuse_flushing_erythema',
    'glabellar_wrinkle_depth',
    'pore_contraction_index',
    'rosacea_severity',
  };

  static const Set<String> _benefitMetricKeys = {
    'texture_smoothness',
    'skin_tone_radiance_evenness',
    'structural_firmness_elasticity',
    'skin_hydration',
  };

  static bool _isDefectMetric(String metricKey) {
    if (_benefitMetricKeys.contains(metricKey)) return false;
    return _defectMetricKeys.contains(metricKey);
  }

  static const Set<String> _continuousClinicalKeys = {
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
    'pore_contraction_index',
    'structural_firmness_elasticity',
    'rosacea_severity',
  };

  static bool _isDisplayableClinicalKey(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized.endsWith('_detected')) return false;
    return _continuousClinicalKeys.contains(normalized);
  }

  static List<LuxeMetric> parseTimelinePayload(Map<String, dynamic> payload) {
    final nestedLuxePayload = _asMap(payload['luxePayload']);
    final mergedPayload = nestedLuxePayload.isEmpty
        ? payload
        : {
            ...payload,
            ...nestedLuxePayload,
            'metrics': {
              ..._asMap(nestedLuxePayload['metrics']),
              ..._asMap(payload['metrics']),
            },
            'metric_matrix': {
              ..._asMap(nestedLuxePayload['metric_matrix']),
              ..._asMap(payload['metric_matrix']),
            },
            'trend_deltas': {
              ..._asMap(nestedLuxePayload['trend_deltas']),
              ..._asMap(payload['trend_deltas']),
            },
          };

    final initialBaseline = mergedPayload['initial_baseline'] == true;
    final explicitFollowUp =
        mergedPayload['is_follow_up'] == true ||
        mergedPayload['isFollowUp'] == true;
    final localHistoryCount = _asDouble(
      mergedPayload['local_history_count'] ?? mergedPayload['localHistoryCount'],
    ).round();
    final hasRealLocalPriorBaseline =
        explicitFollowUp || localHistoryCount >= 2;

    if (initialBaseline || !hasRealLocalPriorBaseline) {
      debugPrint(
        'LUXE CARDS: final visible metrics (0) -> [] (baseline-only state)',
      );
      return const [];
    }
    return _extractServerDeltaMetrics(
      mergedPayload,
      initialBaseline: initialBaseline,
    );
  }

  static List<LuxeMetric> _extractServerDeltaMetrics(
    Map<String, dynamic> payload, {
    required bool initialBaseline,
  }) {
    debugPrint('=== TRACE PAYLOAD: TOP LEVEL KEYS ===');
    debugPrint(payload.keys.toList().toString());
    debugPrint('=== TRACE PAYLOAD: metric_matrix ===');
    debugPrint(payload['metric_matrix']?.toString());
    debugPrint('=== TRACE PAYLOAD: opencv_metrics ===');
    debugPrint(payload['opencv_metrics']?.toString());
    debugPrint('=== TRACE PAYLOAD: metrics SUBMAP ===');
    debugPrint(payload['metrics']?.toString());
    debugPrint('=== TRACE PAYLOAD: baseline SUBMAP ===');
    debugPrint(payload['baseline']?.toString());
    debugPrint('=== TRACE PAYLOAD: current SUBMAP ===');
    debugPrint(payload['current']?.toString());

    final baselineNode = _canonicalizeMetricMap(payload['baseline']);
    final metricsNode = _canonicalizeMetricMap(payload['metrics']);

    final metricMatrix = _canonicalizeMetricMap(payload['metric_matrix']);
    final baselineMetricMatrix = _canonicalizeMetricMap(
      payload['baseline_metric_matrix'],
    );
    final metricConfidence = _canonicalizeMetricMap(payload['metric_confidence']);
    final nestedMetricConfidence = _canonicalizeMetricMap(metricsNode['metric_confidence']);
    final nestedMetricsRoot = _asMap(payload['metrics']);
    final nestedRootMetricConfidence = _canonicalizeMetricMap(
      nestedMetricsRoot['metric_confidence'],
    );

    _traceMapEntries('payload.baseline', baselineNode);
    _traceMapEntries('payload.baseline_metric_matrix', baselineMetricMatrix);
    _traceMapEntries('payload.metric_matrix', metricMatrix);
    debugPrint(
      'BASELINE KEYS current=${metricMatrix.keys.toList()} baseline=${baselineMetricMatrix.keys.toList()}',
    );

    const traceMetrics = <String>[
      'sebum_excess_oil_gloss',
      'diffuse_flushing_erythema',
      'skin_tone_radiance_evenness',
      'glabellar_wrinkle_depth',
    ];
    for (final metricKey in traceMetrics) {
      final paths = _findKeyPaths(payload, metricKey, path: 'payload');
      debugPrint(
        'LUXE TRACE PAYLOAD METRIC PRESENCE: key=$metricKey exists=${paths.isNotEmpty} paths=$paths',
      );
    }

    debugPrint('LUXE TRACE: metric_matrix keys=${metricMatrix.keys.toList()}');
    const knownSpecs = <_ServerMetricSpec>[
      _ServerMetricSpec(
        deltaKey: 'localized_redness',
        name: 'Localized Redness',
        currentKeys: ['localized_redness'],
      ),
      _ServerMetricSpec(
        deltaKey: 'texture_smoothness',
        name: 'Texture Smoothness',
        currentKeys: ['texture_smoothness'],
      ),
      _ServerMetricSpec(
        deltaKey: 'pigment_load',
        name: 'Pigment Load',
        currentKeys: ['pigment_load'],
      ),
      _ServerMetricSpec(
        deltaKey: 'wrinkle_load',
        name: 'Wrinkle Load',
        currentKeys: ['wrinkle_load'],
      ),
      _ServerMetricSpec(
        deltaKey: 'pore_visibility',
        name: 'Pore Visibility',
        currentKeys: ['pore_visibility'],
      ),
      _ServerMetricSpec(
        deltaKey: 'breakout_activity',
        name: 'Breakout Activity',
        currentKeys: ['breakout_activity'],
      ),
      _ServerMetricSpec(
        deltaKey: 'sebum_excess_oil_gloss',
        name: 'Sebum & Oil Gloss',
        currentKeys: ['sebum_excess_oil_gloss'],
      ),
      _ServerMetricSpec(
        deltaKey: 'diffuse_flushing_erythema',
        name: 'Diffuse Flushing (Erythema)',
        currentKeys: ['diffuse_flushing_erythema'],
      ),
      _ServerMetricSpec(
        deltaKey: 'skin_tone_radiance_evenness',
        name: 'Skin Radiance & Evenness',
        currentKeys: ['skin_tone_radiance_evenness'],
      ),
      _ServerMetricSpec(
        deltaKey: 'glabellar_wrinkle_depth',
        name: "Glabellar '11' Lines Depth",
        currentKeys: ['glabellar_wrinkle_depth'],
      ),
      _ServerMetricSpec(
        deltaKey: 'under_eye_texture_density',
        name: 'Under-Eye Texture Density',
        currentKeys: ['under_eye_texture_density'],
      ),
      _ServerMetricSpec(
        deltaKey: 'under_eye_dark_circle_density',
        name: 'Under-Eye Dark Circle Density',
        currentKeys: ['under_eye_dark_circle_density'],
      ),
      _ServerMetricSpec(
        deltaKey: 'pore_contraction_index',
        name: 'Pore Contraction Index',
        currentKeys: ['pore_contraction_index'],
      ),
      _ServerMetricSpec(
        deltaKey: 'structural_firmness_elasticity',
        name: 'Structural Firmness & Elasticity',
        currentKeys: [
          'structural_firmness_elasticity',
        ],
      ),
      _ServerMetricSpec(
        deltaKey: 'rosacea_severity',
        name: 'Rosacea Severity',
        currentKeys: [
          'rosacea_severity',
        ],
        higherIsWorse: true,
      ),
    ];

    final knownSpecByKey = {
      for (final spec in knownSpecs) spec.deltaKey: spec,
    };

    final activeMetricMatrix = metricMatrix.isNotEmpty
        ? metricMatrix
        : _canonicalizeMetricMap(metricsNode['metric_matrix']);
    final supportedSpecs = <_ServerMetricSpec>[];
    for (final entry in activeMetricMatrix.entries) {
      final key = entry.key.toString();
      if (!_isDisplayableClinicalKey(key)) continue;
      final rawValue = _asDouble(entry.value);
      if (!rawValue.isFinite || rawValue <= 0.0) continue;
      final knownSpec = knownSpecByKey[key];
      if (knownSpec != null) {
        supportedSpecs.add(knownSpec);
        continue;
      }
      supportedSpecs.add(
        _ServerMetricSpec(
          deltaKey: key,
          name: _labelFromMetricKey(key),
          currentKeys: [key],
        ),
      );
    }

    final supportedKeys = supportedSpecs.map((s) => s.deltaKey).join(', ');
    debugPrint(
      'LUXE CARDS: dynamically rendering these ${supportedSpecs.length} metrics: [$supportedKeys]',
    );
    if (supportedSpecs.isEmpty) {
      debugPrint('TRACE CARD: No supported metrics found in selected overlay source map.');
      return const [];
    }

    double detectScaleMultiplier(
      Map<String, dynamic> sourceMap,
      String sourceName,
    ) {
      if (sourceMap.isEmpty) {
        debugPrint(
          'TRACE SCALING [$sourceName]: source empty -> multiplier=1.0',
        );
        return 1.0;
      }
      double maxRaw = 0.0;
      for (final spec in supportedSpecs) {
        final v = extractValue(sourceMap, spec.currentKeys);
        if (v > maxRaw) maxRaw = v;
      }
      final multiplier = (maxRaw > 0.0 && maxRaw <= 10.0) ? 10.0 : 1.0;
      debugPrint(
        'TRACE SCALING [$sourceName]: maxRaw=$maxRaw -> sourceMultiplier=$multiplier',
      );
      return multiplier;
    }

    double normalizeToHundred({
      required String metricKey,
      required String sourceName,
      required String sourceMapKey,
      required double raw,
      required double multiplier,
    }) {
      final normalized = raw.clamp(0.0, 100.0).toDouble();
      return normalized;
    }

    final metricMatrixScale = detectScaleMultiplier(activeMetricMatrix, 'payload.metric_matrix');

    final out = <LuxeMetric>[];
    for (final spec in supportedSpecs) {
      final currentRaw = extractValue(activeMetricMatrix, <String>[spec.deltaKey]);
      const currentSourceName = 'payload.metric_matrix';
      final currentScale = metricMatrixScale;
      final currentSourceMapKey = 'metric_matrix.${spec.deltaKey}';
      final hasComparableCurrentValue = currentRaw > 0.0;

      final current = normalizeToHundred(
        metricKey: spec.deltaKey,
        sourceName: currentSourceName,
        sourceMapKey: currentSourceMapKey,
        raw: currentRaw,
        multiplier: currentScale,
      );
      final hasDetectedCurrentValue = currentRaw > 0.0;

        final lowerIsBetter =
          spec.higherIsWorse ?? _isDefectMetric(spec.deltaKey);
      final rawBaseline = baselineMetricMatrix[spec.deltaKey];
      final baseline = (rawBaseline is num) ? rawBaseline.toDouble() : double.nan;
      final hasBaseline = baseline.isFinite;
      final hasComparisonBaseline = _isUsableBaselineValue(baseline);

      final currentConfidenceValue = _resolveMetricConfidenceValue(
        metricKey: spec.deltaKey,
        candidateKeys: spec.currentKeys,
        confidenceMaps: <Map<String, dynamic>>[
          metricConfidence,
          nestedMetricConfidence,
          nestedRootMetricConfidence,
        ],
      );

      debugPrint(
        'BASELINE MATCH [${spec.deltaKey}] matchedKey=${hasBaseline ? 'baseline_metric_matrix.${spec.deltaKey}' : 'not_found'} raw=${hasBaseline ? baseline.toStringAsFixed(2) : 'nan'} aliasUsed=none final=${hasBaseline ? baseline.toStringAsFixed(2) : 'nan'}',
      );

      var resolvedCurrent = current;

      double improvementPercent;
      if (hasComparisonBaseline && resolvedCurrent > 0.0) {
        improvementPercent = ((resolvedCurrent - baseline) / baseline) * 100.0;
      } else {
        improvementPercent = 0.0;
      }

      debugPrint(
        'TRACE BASELINE [${spec.deltaKey}] hasBaseline=$hasBaseline initialBaselineInput=$initialBaseline comparisonBaseline=$hasComparisonBaseline',
      );

      if (!resolvedCurrent.isFinite || resolvedCurrent <= 0.0) {
        continue;
      }

      if (spec.deltaKey == 'localized_redness' ||
          spec.deltaKey == 'pore_visibility' ||
          spec.deltaKey == 'breakout_activity' ||
          spec.deltaKey == 'texture_smoothness') {
        debugPrint(
          'LUXE TRACE TARGET [${spec.deltaKey}]: current=$resolvedCurrent baseline=$baseline deltaPct=$improvementPercent source=$currentSourceName',
        );
      }

      if (!hasComparableCurrentValue || !hasComparisonBaseline) {
        // Progress view requires real canonical baseline + current values.
        continue;
      }

      out.add(
        LuxeMetric(
          key: spec.deltaKey,
          name: spec.name,
          baselineScore: baseline,
          currentScore: resolvedCurrent.clamp(0.0, 100.0).toDouble(),
          improvementPercent: improvementPercent,
          lowerIsBetter: lowerIsBetter,
          initialBaseline: initialBaseline,
          currentConfidence: currentConfidenceValue,
          hasDetectedCurrentValue: hasDetectedCurrentValue,
          hasComparableCurrentValue: hasComparableCurrentValue,
        ),
      );
    }
    final loaded = out.where((m) => m.hasDetectedCurrentValue).toList();
    if (loaded.isEmpty) {
      debugPrint(
        'TRACE CARD: No non-zero current metrics resolved. Cards may show 0.0/No baseline trend.',
      );
    }
    final loadedKeys = loaded.map((m) => m.key).join(', ');
    debugPrint('FINAL VISIBLE METRICS count=${loaded.length} keys=$loadedKeys');
    return loaded;
  }

  static double extractValue(Map<String, dynamic> data, List<String> targetKeys) {
    return _extractValueWithKey(data, targetKeys).value;
  }

  static _ExtractedMetricValue _extractValueWithKey(
    Map<String, dynamic> data,
    List<String> targetKeys,
  ) {
    double? parse(dynamic value) {
      if (value is num) return value.toDouble();
      if (value == null) return null;
      return double.tryParse(value.toString());
    }

    for (final key in targetKeys) {
      final rootParsed = parse(data[key]);
      if (rootParsed != null && rootParsed.isFinite) {
        return _ExtractedMetricValue(value: rootParsed, sourceMapKey: key);
      }

      final matrix = _asMap(data['metric_matrix']);
      final matrixParsed = parse(matrix[key]);
      if (matrixParsed != null && matrixParsed.isFinite) {
        return _ExtractedMetricValue(
          value: matrixParsed,
          sourceMapKey: 'metric_matrix.$key',
        );
      }

      final opencv = _asMap(data['opencv_metrics']);
      final opencvParsed = parse(opencv[key]);
      if (opencvParsed != null && opencvParsed.isFinite) {
        return _ExtractedMetricValue(
          value: opencvParsed,
          sourceMapKey: 'opencv_metrics.$key',
        );
      }

      final metrics = _asMap(data['metrics']);
      final metricsParsed = parse(metrics[key]);
      if (metricsParsed != null && metricsParsed.isFinite) {
        return _ExtractedMetricValue(
          value: metricsParsed,
          sourceMapKey: 'metrics.$key',
        );
      }

      final nestedMetricsMatrix = _asMap(metrics['metric_matrix']);
      final nestedMatrixParsed = parse(nestedMetricsMatrix[key]);
      if (nestedMatrixParsed != null && nestedMatrixParsed.isFinite) {
        return _ExtractedMetricValue(
          value: nestedMatrixParsed,
          sourceMapKey: 'metrics.metric_matrix.$key',
        );
      }

      final nestedMetricsOpencv = _asMap(metrics['opencv_metrics']);
      final nestedOpencvParsed = parse(nestedMetricsOpencv[key]);
      if (nestedOpencvParsed != null && nestedOpencvParsed.isFinite) {
        return _ExtractedMetricValue(
          value: nestedOpencvParsed,
          sourceMapKey: 'metrics.opencv_metrics.$key',
        );
      }

      final flatMatrixParsed = parse(
        data['metric_matrix.$key'] ?? data['metric_matrix_$key'],
      );
      if (flatMatrixParsed != null && flatMatrixParsed.isFinite) {
        return _ExtractedMetricValue(
          value: flatMatrixParsed,
          sourceMapKey: 'metric_matrix.$key',
        );
      }

      final flatOpencvParsed = parse(
        data['opencv_metrics.$key'] ?? data['opencv_metrics_$key'],
      );
      if (flatOpencvParsed != null && flatOpencvParsed.isFinite) {
        return _ExtractedMetricValue(
          value: flatOpencvParsed,
          sourceMapKey: 'opencv_metrics.$key',
        );
      }
    }

    return const _ExtractedMetricValue(value: 0.0, sourceMapKey: 'not_found');
  }

  static bool _isUsableBaselineValue(double? value) {
    if (value == null || !value.isFinite) return false;
    return value > _baselineUsableFloor && value < _baselineUsableCeiling;
  }

  static Object? _resolveMetricConfidenceValue({
    required String metricKey,
    required List<String> candidateKeys,
    required List<Map<String, dynamic>> confidenceMaps,
  }) {
    final keys = <String>[metricKey, ...candidateKeys];
    for (final map in confidenceMaps) {
      if (map.isEmpty) continue;
      for (final key in keys) {
        final raw = map[key];
        final normalized = _normalizeConfidenceValue(raw);
        if (normalized != null) return normalized;
      }
    }
    return null;
  }

  static Object? _normalizeConfidenceValue(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final numeric = value.toDouble();
      return numeric.isFinite ? numeric : null;
    }
    final text = value.toString().trim().toLowerCase();
    if (text == 'high' || text == 'medium' || text == 'low') return text;
    return null;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static void _traceMapEntries(String label, Map<String, dynamic> map) {
    debugPrint('=== TRACE PAYLOAD MAP DUMP: $label (count=${map.length}) ===');
    if (map.isEmpty) {
      debugPrint('$label=<empty>');
      return;
    }
    final sortedKeys = map.keys.toList()..sort();
    for (final key in sortedKeys) {
      debugPrint('$label[$key]=${map[key]}');
    }
  }

  static List<String> _findKeyPaths(
    dynamic node,
    String targetKey, {
    required String path,
  }) {
    final matches = <String>[];
    final targetLower = targetKey.toLowerCase();

    void visit(dynamic value, String currentPath) {
      if (value is Map) {
        value.forEach((rawKey, nestedValue) {
          final key = rawKey.toString();
          final nextPath = '$currentPath.$key';
          if (key.toLowerCase() == targetLower) {
            matches.add(nextPath);
          }
          visit(nestedValue, nextPath);
        });
        return;
      }
      if (value is Iterable) {
        var index = 0;
        for (final nestedValue in value) {
          visit(nestedValue, '$currentPath[$index]');
          index += 1;
        }
      }
    }

    visit(node, path);
    return matches;
  }

  static String _canonicalMetricKey(String rawKey) {
    final normalized = rawKey.trim().toLowerCase();
    return _metricKeyAliases[normalized] ?? normalized;
  }

  static Map<String, dynamic> _canonicalizeMetricMap(dynamic value) {
    final source = _asMap(value);
    if (source.isEmpty) return const <String, dynamic>{};

    final canonical = <String, dynamic>{};
    for (final entry in source.entries) {
      final canonicalKey = _canonicalMetricKey(entry.key.toString());
      if (canonicalKey.endsWith('_detected')) continue;
      final rawValue = entry.value;
      if (rawValue is Map) {
        canonical[canonicalKey] = _canonicalizeMetricMap(rawValue);
      } else {
        canonical[canonicalKey] = rawValue;
      }
    }
    return canonical;
  }

  static String _labelFromMetricKey(String key) {
    final segments = key.split('_').where((part) => part.isNotEmpty).toList();
    if (segments.isEmpty) return key;
    return segments
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

}

class _ServerMetricSpec {
  const _ServerMetricSpec({
    required this.deltaKey,
    required this.name,
    required this.currentKeys,
    this.higherIsWorse,
  });

  final String deltaKey;
  final String name;
  final List<String> currentKeys;
  final bool? higherIsWorse;
}

class _MetricRowData {
  const _MetricRowData({
    required this.baselineValue,
    required this.currentValue,
    required this.trendDelta,
    required this.badgePercent,
    required this.badgeValueText,
    required this.subtext,
    required this.initialBaseline,
    required this.honestyStatus,
    required this.honestyLabel,
    required this.hasRealBaseline,
    required this.hasComparableCurrentValue,
  });

  final double baselineValue;
  final double currentValue;
  final double? trendDelta;
  final double? badgePercent;
  final String? badgeValueText;
  final String subtext;
  final bool initialBaseline;
  final _HonestyStatus honestyStatus;
  final String honestyLabel;
  final bool hasRealBaseline;
  final bool hasComparableCurrentValue;
}

enum _HonestyStatus {
  improved,
  worsened,
  stable,
  insufficientSignal,
}

class _HonestyAssessment {
  const _HonestyAssessment({
    required this.status,
    required this.reason,
    required this.deltaPct,
    required this.hasRealBaseline,
  });

  final _HonestyStatus status;
  final String reason;
  final double? deltaPct;
  final bool hasRealBaseline;

  String get label {
    switch (status) {
      case _HonestyStatus.improved:
        return 'Improved';
      case _HonestyStatus.worsened:
        return 'Worsened';
      case _HonestyStatus.stable:
        return 'Stable';
      case _HonestyStatus.insufficientSignal:
        return 'Insufficient signal';
    }
  }

}

_HonestyAssessment _assessMetricHonesty({
  required String metricKey,
  required double current,
  required double baseline,
  required bool higherIsWorse,
  bool hasComparableCurrentValue = true,
  Object? currentConfidence,
  bool emitLog = true,
}) {
  bool isLowConfidenceValue(Object? value) {
    if (value == null) return false;
    if (value is num) {
      final numeric = value.toDouble();
      return numeric.isFinite && numeric < 0.65;
    }
    final text = value.toString().trim().toLowerCase();
    return text == 'low';
  }

  final hasRealBaseline = baseline > 0.0;
  final deltaPct = hasRealBaseline
      ? ((current - baseline) / baseline) * 100.0
      : null;
    final deltaPoints = hasRealBaseline ? (current - baseline).abs() : null;
  final nearZeroNoise = hasRealBaseline && current < 1.0 && baseline < 1.0;
  final lowConfidence = isLowConfidenceValue(currentConfidence);
  final swingThreshold = _getMaxConfidenceSwingThreshold(metricKey);
  final lowConfidenceZeroCurrent = lowConfidence && current <= 0.0;
  final lowConfidenceLargeSwing =
      lowConfidence && deltaPct != null && deltaPct.abs() >= swingThreshold;
    final withinClinicalStableBand =
      hasRealBaseline &&
      deltaPoints != null &&
      deltaPct != null &&
      (deltaPoints < 5.0 || deltaPct.abs() < 10.0);

  var status = _HonestyStatus.insufficientSignal;
  var reason = 'baseline pending';

  if (!hasComparableCurrentValue) {
    status = _HonestyStatus.insufficientSignal;
    reason = 'Not compared';
  } else if (!hasRealBaseline) {
    status = _HonestyStatus.insufficientSignal;
    reason = 'baseline pending';
  } else if (lowConfidenceZeroCurrent) {
    status = _HonestyStatus.insufficientSignal;
    reason = 'low-confidence zero current';
  } else if (lowConfidenceLargeSwing) {
    status = _HonestyStatus.insufficientSignal;
    reason = 'Re-scan recommended (Lighting/Angle variance)';
  } else if (lowConfidence) {
    status = _HonestyStatus.stable;
    reason = 'low-confidence conservative';
  } else if (nearZeroNoise) {
    status = _HonestyStatus.insufficientSignal;
    reason = 'near-zero scale noise';
  } else if (withinClinicalStableBand) {
    status = _HonestyStatus.stable;
    reason = 'clinical threshold band';
  } else if (deltaPct != null) {
    final increased = deltaPct > 0;
    final improved = higherIsWorse ? !increased : increased;
    status = improved ? _HonestyStatus.improved : _HonestyStatus.worsened;
    reason = higherIsWorse
        ? (increased ? 'higherIsWorse increase' : 'higherIsWorse decrease')
        : (increased ? 'higherIsBetter increase' : 'higherIsBetter decrease');
  }

  final formattedDelta = deltaPct == null ? 'null' : deltaPct.toStringAsFixed(1);
  if (emitLog) {
    debugPrint(
      'HONESTY [$metricKey]= current=${current.toStringAsFixed(2)} baseline=${baseline.toStringAsFixed(2)} deltaPct=$formattedDelta higherIsWorse=$higherIsWorse status=${status.name} reason=$reason',
    );
  }

  return _HonestyAssessment(
    status: status,
    reason: reason,
    deltaPct: status == _HonestyStatus.insufficientSignal ? null : deltaPct,
    hasRealBaseline: hasRealBaseline && !lowConfidenceZeroCurrent,
  );
}

double _getMaxConfidenceSwingThreshold(String metricKey) {
  switch (metricKey) {
    case 'localized_redness':
    case 'diffuse_flushing_erythema':
    case 'sebum_excess_oil_gloss':
      return 40.0;
    case 'pigment_load':
    case 'glabellar_wrinkle_depth':
    case 'wrinkle_load':
    case 'pore_visibility':
      return 30.0;
    default:
      return 50.0;
  }
}

class LuxeReportLayout extends StatefulWidget {
  const LuxeReportLayout({
    super.key,
    required this.rawPayload,
    this.baselineImageProvider,
    this.currentImageProvider,
    this.baselineLabel = 'Baseline Image',
    this.currentLabel = 'Current Scan',
    this.localHistoryCount,
    this.isFollowUp,
    this.gateReason,
  });

  final Map<String, dynamic> rawPayload;
  final ImageProvider<Object>? baselineImageProvider;
  final ImageProvider<Object>? currentImageProvider;
  final String baselineLabel;
  final String currentLabel;
  final int? localHistoryCount;
  final bool? isFollowUp;
  final String? gateReason;

  static const Color bg = Color(0xFF0F1013);
  static const Color card = Color(0xFF1A1F2C);
  static const Color gold = Color(0xFFD4AF37);
  static const Color roseGold = Color(0xFFB76E79);

  @override
  State<LuxeReportLayout> createState() => _LuxeReportLayoutState();
}

class _LuxeReportLayoutState extends State<LuxeReportLayout>
  with SingleTickerProviderStateMixin {
  bool _showAiOverlay = true;
  String? _selectedMetricKey;
  String? _highlightedZone;
  bool _flashActive = false;
  Timer? _flashTimer;
  late final AnimationController _flashController;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _flashController.dispose();
    super.dispose();
  }

  String _zoneForMetric(String key) {
    switch (key) {
      case 'glabellar_wrinkle_depth':
        return 'glabella';
      case 'pore_contraction_index':
      case 'pore_visibility':
        return 'cheeks_nose';
      case 'localized_redness':
      case 'diffuse_flushing_erythema':
        return 'cheeks';
      case 'breakout_activity':
      case 'sebum_excess_oil_gloss':
        return 'tzone';
      case 'structural_firmness_elasticity':
        return 'jawline';
      default:
        return 'full_face';
    }
  }

  void _handleMetricTap(LuxeMetric metric) {
    final zone = _zoneForMetric(metric.key);
    setState(() {
      _selectedMetricKey = metric.key;
      _highlightedZone = zone;
      _flashActive = true;
    });

    _flashTimer?.cancel();
    _flashController
      ..stop()
      ..value = 0
      ..repeat(reverse: true);

    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _flashController.stop();
      setState(() {
        _flashActive = false;
      });
    });
  }

  Widget _buildClinicalContextCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.medical_information_outlined,
            size: 18,
            color: Color(0xFFB76E79),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clinical Context & Disclaimer',
                  style: TextStyle(
                    color: Color(0xFF1F232D),
                    fontSize: 12.8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'These AI-derived values are designed for progress tracking across your own baseline and follow-up scans. They do not diagnose disease, replace medical evaluation, or prescribe treatment.',
                  style: TextStyle(
                    color: const Color(0xFF1F232D).withValues(alpha: 0.78),
                    fontSize: 11.2,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBaselineCapturedMessage(String reason) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.flag_rounded,
                size: 16,
                color: Color(0xFFD4AF37),
              ),
              SizedBox(width: 8),
              Text(
                'Baseline scan captured',
                style: TextStyle(
                  color: Color(0xFF1F232D),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Take another local scan to unlock before/after comparison, progress deltas, and clinical summary cards.',
            style: TextStyle(
              color: const Color(0xFF1F232D).withValues(alpha: 0.80),
              fontSize: 11.2,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            style: TextStyle(
              color: const Color(0xFF1F232D).withValues(alpha: 0.62),
              fontSize: 10.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicalProgressSummary(
    List<LuxeMetric> metrics,
  ) {
    if (metrics.isEmpty || metrics.every((m) => m.initialBaseline)) {
      return const SizedBox.shrink();
    }

    final statements = <String>[];
    for (final metric in metrics) {
      final assessment = _assessMetricHonesty(
        metricKey: metric.key,
        current: metric.currentScore,
        baseline: metric.baselineScore,
        higherIsWorse: metric.lowerIsBetter,
        hasComparableCurrentValue: metric.hasComparableCurrentValue,
        currentConfidence: metric.currentConfidence,
        emitLog: false,
      );
      final metricName = metric.name;
      if (assessment.status == _HonestyStatus.insufficientSignal) {
        statements.add('$metricName: Insufficient signal.');
        continue;
      }
      if (assessment.status == _HonestyStatus.stable) {
        statements.add('$metricName: Stable.');
        continue;
      }
      final delta = assessment.deltaPct ?? 0.0;
      final deltaText = LuxeMetricParser.formatDisplayDelta(
        baseline: metric.baselineScore,
        current: metric.currentScore,
        deltaPct: delta,
      );
      statements.add(
        '$metricName: ${assessment.label}${delta.abs() > 0 ? ' by $deltaText' : ''}.',
      );
    }

    if (statements.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Clinical Progress Summary',
            style: TextStyle(
              color: Color(0xFF1F232D),
              fontSize: 12.8,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in statements) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.circle,
                    size: 6,
                    color: Color(0xFFB76E79),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: TextStyle(
                      color: const Color(0xFF1F232D).withValues(alpha: 0.80),
                      fontSize: 11.0,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLocalHistoryMetadata =
        widget.localHistoryCount != null ||
        widget.isFollowUp != null ||
        widget.rawPayload.containsKey('local_history_count') ||
        widget.rawPayload.containsKey('localHistoryCount') ||
        widget.rawPayload.containsKey('is_follow_up') ||
        widget.rawPayload.containsKey('isFollowUp');
    final localHistoryCount = widget.localHistoryCount ??
        LuxeMetricParser._asDouble(
          widget.rawPayload['local_history_count'] ??
              widget.rawPayload['localHistoryCount'],
        ).round();
    final procedureIdForLog =
      (widget.rawPayload['procedure_id'] ??
          widget.rawPayload['procedureId'] ??
          widget.rawPayload['selected_procedure_id'])
        ?.toString() ??
      'unknown';
    final explicitFollowUp = widget.isFollowUp ??
        (widget.rawPayload['is_follow_up'] == true ||
            widget.rawPayload['isFollowUp'] == true);
    final initialBaseline = widget.rawPayload['initial_baseline'] == true;
    final hasRealLocalPriorBaseline =
      explicitFollowUp || localHistoryCount >= 2;
    final willRenderCards = hasRealLocalPriorBaseline && !initialBaseline;
    final reason = widget.gateReason ??
        (willRenderCards
        ? (hasLocalHistoryMetadata
          ? (explicitFollowUp
                ? 'explicit follow-up flag from local history'
          : 'local history count >= 2')
          : 'baseline-follow-up pair detected from scan payload')
            : 'no local baseline-follow-up pair yet');

    debugPrint(
      'LUXE GATE: localHistoryCount=$localHistoryCount isFollowUp=$explicitFollowUp willRenderCards=$willRenderCards reason=$reason',
    );
    debugPrint(
      '[BASELINE_READ] source=payload_history_gate procedureId=$procedureIdForLog '
      'baselineScanId=${widget.rawPayload['baselineScanId'] ?? 'none'} '
      'latestScanId=${widget.rawPayload['latestScanId'] ?? 'none'} '
      'localHistoryCount=$localHistoryCount isFollowUp=$explicitFollowUp '
      'willRenderCards=$willRenderCards reason=$reason',
    );

    if (!willRenderCards) {
      debugPrint(
        '[BASELINE_READ] source=payload_history_gate procedureId=$procedureIdForLog '
        'baselineScanId=${widget.rawPayload['baselineScanId'] ?? 'none'} '
        'latestScanId=${widget.rawPayload['latestScanId'] ?? 'none'} '
        'reason=baseline_pending_gate_block',
      );
      return Container(
        color: const Color(0xFFFFF8EE),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_buildBaselineCapturedMessage(reason)],
        ),
      );
    }

    final metrics = LuxeMetricParser.parseTimelinePayload(widget.rawPayload);
    final visibleMetrics = metrics.where((m) => !m.initialBaseline).toList();
    debugPrint(
      'FOLLOWUP UI: localHistoryCount=$localHistoryCount isFollowUp=$explicitFollowUp cardsRendered=${visibleMetrics.length}',
    );
    if (visibleMetrics.isEmpty) {
      return Container(
        color: const Color(0xFFFFF8EE),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_buildBaselineCapturedMessage(reason)],
        ),
      );
    }
    final showComparisonFrames =
      widget.baselineImageProvider != null && widget.currentImageProvider != null;

    return Container(
      color: const Color(0xFFFFF8EE),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showComparisonFrames) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.28)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: Color(0xFFD4AF37),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Before vs After comparison',
                      style: TextStyle(
                        color: Color(0xFF1F232D),
                        fontSize: 11.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _showAiOverlay = !_showAiOverlay);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: _showAiOverlay
                          ? const Color(0xFF4FAE8B)
                          : Colors.white.withValues(alpha: 0.7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      _showAiOverlay
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 14,
                    ),
                    label: Text(
                      _showAiOverlay ? 'AI Overlay On' : 'AI Overlay Off',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: InteractiveBeforeAfterSlider(
                beforeImage: widget.baselineImageProvider!,
                afterImage: widget.currentImageProvider!,
                beforeLabel: widget.baselineLabel,
                afterLabel: widget.currentLabel,
                aspectRatio: 0.96,
                metricTags: const <BeforeAfterMetricTag>[],
                beforeLayerBuilder: (context, image) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image(image: image, fit: BoxFit.cover),
                      if (_showAiOverlay)
                        CustomPaint(
                          painter: _AiOverlayPainter(
                            highlightedZone: _highlightedZone,
                            pulse: _flashActive ? _flashController : null,
                          ),
                        ),
                    ],
                  );
                },
                afterLayerBuilder: (context, image) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image(image: image, fit: BoxFit.cover),
                      if (_showAiOverlay)
                        CustomPaint(
                          painter: _AiOverlayPainter(
                            highlightedZone: _highlightedZone,
                            pulse: _flashActive ? _flashController : null,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final colWidth = (width - 14) / 2;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final metric in visibleMetrics)
                    SizedBox(
                      width: colWidth,
                      child: _MetricCard(
                        metric: metric,
                        selected: _selectedMetricKey == metric.key,
                        onTap: () => _handleMetricTap(metric),
                      ),
                    ),
                ],
              );
            },
          ),
          if (visibleMetrics.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildClinicalProgressSummary(visibleMetrics),
            const SizedBox(height: 16),
            _buildClinicalContextCard(),
          ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
    required this.selected,
    required this.onTap,
  });

  final LuxeMetric metric;
  final bool selected;
  final VoidCallback onTap;

  static const Color gold = LuxeReportLayout.gold;

  _MetricRowData _buildMetricRowData() {
    final baselineValue = metric.baselineScore;
    final currentValue = metric.currentScore;
    final assessment = _assessMetricHonesty(
      metricKey: metric.key,
      current: currentValue,
      baseline: baselineValue,
      higherIsWorse: metric.lowerIsBetter,
      hasComparableCurrentValue: metric.hasComparableCurrentValue,
      currentConfidence: metric.currentConfidence,
    );
    final directionalStatus =
        assessment.status == _HonestyStatus.improved ||
        assessment.status == _HonestyStatus.worsened;
    double? trendDelta = directionalStatus ? assessment.deltaPct : null;
    String? badgeValueText;
    double? badgePercent = trendDelta;
    if (directionalStatus && assessment.deltaPct != null) {
      badgeValueText = LuxeMetricParser.formatDisplayDelta(
        baseline: baselineValue,
        current: currentValue,
        deltaPct: assessment.deltaPct!,
        includeSign: true,
      );
      badgePercent = LuxeMetricParser.displayDeltaMagnitude(
        baseline: baselineValue,
        current: currentValue,
        deltaPct: assessment.deltaPct!,
      );
    }
    const initialBaseline = false;
    final subtext = assessment.hasRealBaseline
      ? (assessment.reason ==
            'Re-scan recommended (Lighting/Angle variance)'
          ? assessment.reason
          : assessment.label)
        : 'Tracks visible appearance in key zones';

    if (currentValue <= 0.0) {
      badgePercent = null;
      badgeValueText = null;
      trendDelta = null;
    }

    return _MetricRowData(
      baselineValue: baselineValue,
      currentValue: currentValue,
      trendDelta: trendDelta,
      badgePercent: badgePercent,
      badgeValueText: badgeValueText,
      subtext: subtext,
      initialBaseline: initialBaseline,
      honestyStatus: assessment.status,
      honestyLabel: assessment.label,
      hasRealBaseline: assessment.hasRealBaseline,
      hasComparableCurrentValue: metric.hasComparableCurrentValue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = _buildMetricRowData();
    final chipLabel = row.honestyLabel;
    final chipIcon = _chipIcon(row.honestyStatus);
    final chipColor = _chipColor(row.honestyStatus);
    const titleColor = Color(0xFF1E242F);
    final headlineDelta = row.honestyLabel;
    final currentDisplayText = row.hasComparableCurrentValue
        ? row.currentValue.toStringAsFixed(1)
        : 'Not compared';
    final baselineDisplayText = row.hasRealBaseline
        ? row.baselineValue.toStringAsFixed(1)
        : 'pending';
    final progressionDeltaText =
      row.badgeValueText == null ? '' : ' (${row.badgeValueText})';
    final progressionLine = !row.hasComparableCurrentValue
      ? '${metric.name}: Not compared (${row.subtext})'
      : row.hasRealBaseline
      ? '${metric.name}: ${row.baselineValue.toStringAsFixed(1)} -> ${row.currentValue.toStringAsFixed(1)}$progressionDeltaText '
        '(${row.subtext})'
        : '${metric.name}: ${row.currentValue.toStringAsFixed(1)} current scan (Baseline pending)';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFFD4AF37)
                  : const Color(0xFFDACDB2).withValues(alpha: 0.65),
              width: selected ? 1.8 : 0.9,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headlineDelta,
                style: TextStyle(
                  color: chipColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Current $currentDisplayText  |  Baseline $baselineDisplayText',
                style: const TextStyle(
                  color: titleColor,
                  fontSize: 10.9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                metric.name,
                style: TextStyle(
                  color: titleColor.withValues(alpha: 0.88),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (row.badgePercent != null &&
                  row.badgeValueText != null &&
                  row.currentValue > 0.0 &&
                  row.baselineValue > 0.0 &&
                  row.badgePercent!.abs() > 0.0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(chipIcon, size: 11.5, color: chipColor),
                      const SizedBox(width: 6),
                      Text(
                        chipLabel,
                        style: TextStyle(
                          color: chipColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                      ),
                      if (row.badgeValueText != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          row.badgeValueText!,
                          style: TextStyle(
                            color: chipColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                const SizedBox.shrink(),
              const SizedBox(height: 8),
              Text(
                progressionLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: titleColor,
                  fontSize: 10.8,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _metricDescription(metric),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: titleColor.withValues(alpha: 0.76),
                  fontSize: 10.6,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metricDescription(LuxeMetric metric) {
    switch (metric.key) {
      case 'pore_contraction_index':
      case 'pore_visibility':
        return 'Tracks visible pore appearance in key zones under consistent lighting for cosmetic progress checks.';
      case 'glabellar_wrinkle_depth':
        return 'Follows visible line contrast in the brow zone to reflect surface texture smoothing trends.';
      case 'sebum_excess_oil_gloss':
        return 'Summarizes shine concentration across the T-zone to monitor oil-balance consistency over time.';
      case 'diffuse_flushing_erythema':
      case 'localized_redness':
        return 'Reflects broad visible redness distribution to help track calmness and tone consistency.';
      case 'skin_tone_radiance_evenness':
        return 'Represents overall tone uniformity and brightness balance for a smoother, more radiant look.';
      case 'structural_firmness_elasticity':
        return 'Compares facial support geometry trends to indicate tighter, more lifted visual structure.';
      case 'texture_smoothness':
        return 'Measures surface uniformity signals associated with smoother visual skin texture.';
      case 'breakout_activity':
        return 'Tracks visible breakout pattern intensity to monitor cosmetic flare-up frequency changes.';
      default:
        return 'Compares baseline and current scan vectors to track visible skin-quality progression.';
    }
  }

  IconData _chipIcon(_HonestyStatus status) {
    switch (status) {
      case _HonestyStatus.improved:
        return Icons.trending_up_rounded;
      case _HonestyStatus.worsened:
        return Icons.trending_down_rounded;
      case _HonestyStatus.stable:
        return Icons.trending_flat_rounded;
      case _HonestyStatus.insufficientSignal:
        return Icons.help_outline_rounded;
    }
  }

  Color _chipColor(_HonestyStatus status) {
    switch (status) {
      case _HonestyStatus.improved:
        return const Color(0xFF4FAE8B);
      case _HonestyStatus.worsened:
        return const Color(0xFFC76A55);
      case _HonestyStatus.stable:
        return gold;
      case _HonestyStatus.insufficientSignal:
        return const Color(0xFF8E7F6D);
    }
  }
}

class _AiOverlayPainter extends CustomPainter {
  _AiOverlayPainter({
    required this.highlightedZone,
    required this.pulse,
  }) : super(repaint: pulse);

  final String? highlightedZone;
  final Animation<double>? pulse;

  bool _isZone(String zone) => highlightedZone == zone || highlightedZone == 'full_face';

  @override
  void paint(Canvas canvas, Size size) {
    final pulseBoost = pulse == null ? 0.0 : (pulse!.value * 0.28);

    final forehead = Paint()
      ..color = (_isZone('glabella') || _isZone('tzone'))
          ? const Color(0xFFD4AF37).withValues(alpha: 0.20 + pulseBoost)
          : const Color(0x66D4AF37);
    final cheek = Paint()
      ..color = (_isZone('cheeks') || _isZone('cheeks_nose'))
          ? const Color(0xFFD4AF37).withValues(alpha: 0.20 + pulseBoost)
          : const Color(0x664FAE8B);
    final tzone = Paint()
      ..color = (_isZone('tzone') || _isZone('cheeks_nose'))
          ? const Color(0xFFD4AF37).withValues(alpha: 0.22 + pulseBoost)
          : const Color(0x66C76A55);
    final jawline = Paint()
      ..color = _isZone('jawline')
          ? const Color(0xFFD4AF37).withValues(alpha: 0.20 + pulseBoost)
          : const Color(0x554FAE8B);

    final foreheadPath = Path()
      ..moveTo(size.width * 0.24, size.height * 0.20)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.06,
        size.width * 0.76,
        size.height * 0.20,
      )
      ..lineTo(size.width * 0.70, size.height * 0.33)
      ..lineTo(size.width * 0.30, size.height * 0.33)
      ..close();
    canvas.drawPath(foreheadPath, forehead);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.30, size.height * 0.58),
        width: size.width * 0.28,
        height: size.height * 0.24,
      ),
      cheek,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.70, size.height * 0.58),
        width: size.width * 0.28,
        height: size.height * 0.24,
      ),
      cheek,
    );

    final tzonePath = Path()
      ..moveTo(size.width * 0.44, size.height * 0.32)
      ..lineTo(size.width * 0.56, size.height * 0.32)
      ..lineTo(size.width * 0.62, size.height * 0.64)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.72,
        size.width * 0.38,
        size.height * 0.64,
      )
      ..close();
    canvas.drawPath(tzonePath, tzone);

    final jawlinePath = Path()
      ..moveTo(size.width * 0.22, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.92,
        size.width * 0.78,
        size.height * 0.78,
      )
      ..lineTo(size.width * 0.72, size.height * 0.88)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.97,
        size.width * 0.28,
        size.height * 0.88,
      )
      ..close();
    canvas.drawPath(jawlinePath, jawline);
  }

  @override
  bool shouldRepaint(covariant _AiOverlayPainter oldDelegate) {
    return oldDelegate.highlightedZone != highlightedZone ||
        oldDelegate.pulse != pulse;
  }
}
