import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/capture_consistency.dart';
import '../utils/severity_band.dart';
import '../utils/trend_label_resolver.dart';
import '../utils/trend_lock_reason.dart';
import 'before_after_split_slider.dart';

const Set<String> metricsWithHiddenTrendVerdicts = <String>{
  'wrinkle_load',
  'rosacea_severity',
  'diffuse_flushing_erythema',
  'pore_contraction_index',
  'chin_pore_visibility',
  'under_eye_dark_circle_density',
  'under_eye_texture_density',
};

bool shouldShowTrendVerdict(String metricKey) =>
    !metricsWithHiddenTrendVerdicts.contains(metricKey);

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
    this.hasBaselineValue = false,
    this.showTrendVerdict = true,
    this.currentExtractionPath = 'unknown',
    this.baselineExtractionPath = 'unknown',
    this.backendTrendDeltaPct,
    this.backendTrendStatus,
    this.usesBackendTrend = false,
    this.backendTrendLockReason,
    this.currentRangeMin,
    this.currentRangeMax,
    this.currentNoiseFloor2sd,
    this.contributorCount,
    this.requestedFrameCount,
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
  final bool hasBaselineValue;
  final bool showTrendVerdict;
  final String currentExtractionPath;
  final String baselineExtractionPath;
  final double? backendTrendDeltaPct;
  final String? backendTrendStatus;
  final bool usesBackendTrend;
  // Populated only when backendTrendStatus == 'stable': explains whether that
  // "stable" is a genuine small delta (null) or a forced lock from one of the
  // capture-provenance honesty gates (capture_quality_mismatch,
  // path_mismatch, resolution_mismatch, ...). Purely informational — see
  // lib/utils/trend_lock_reason.dart.
  final String? backendTrendLockReason;
  final double? currentRangeMin;
  final double? currentRangeMax;
  final double? currentNoiseFloor2sd;
  final int? contributorCount;
  final int? requestedFrameCount;
}

class MetricPrecisionPresentation {
  const MetricPrecisionPresentation({
    required this.rangeSuffix,
    required this.detailText,
    required this.hasRealRange,
  });

  final String rangeSuffix;
  final String detailText;
  final bool hasRealRange;
}

MetricPrecisionPresentation metricPrecisionPresentation(LuxeMetric metric) {
  final contributors = metric.contributorCount;
  final requested = metric.requestedFrameCount;
  final min = metric.currentRangeMin;
  final max = metric.currentRangeMax;
  final hasRealRange =
      contributors != null &&
      contributors >= 2 &&
      min != null &&
      max != null &&
      min.isFinite &&
      max.isFinite;

  if (hasRealRange) {
    return MetricPrecisionPresentation(
      rangeSuffix: ' (${min.toStringAsFixed(1)}–${max.toStringAsFixed(1)})',
      detailText: '$contributors/${requested ?? contributors} frames',
      hasRealRange: true,
    );
  }

  final rawConfidence = metric.currentConfidence;
  String confidenceText;
  if (rawConfidence is num && rawConfidence.toDouble().isFinite) {
    final numeric = rawConfidence.toDouble();
    final percent = numeric <= 1.0 ? numeric * 100.0 : numeric;
    confidenceText = 'Confidence: ${percent.toStringAsFixed(0)}%';
  } else {
    final normalized = rawConfidence?.toString().trim().toLowerCase();
    if (normalized == 'high' || normalized == 'medium' || normalized == 'low') {
      confidenceText =
          'Confidence: ${normalized![0].toUpperCase()}${normalized.substring(1)}';
    } else {
      confidenceText = 'Confidence unavailable';
    }
  }

  final frameSuffix = contributors == null
      ? ''
      : ' · $contributors/${requested ?? contributors} frames';
  return MetricPrecisionPresentation(
    rangeSuffix: '',
    detailText: '$confidenceText$frameSuffix',
    hasRealRange: false,
  );
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
    return baseline >= 0.0 && baseline < _displayDeltaPointsBaselineThreshold;
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
          ? (deltaPct > 0 ? '+' : (deltaPct < 0 ? '-' : ''))
          : '';
      return '$sign${points.toStringAsFixed(1)} pts';
    }

    final capped = deltaPct
        .abs()
        .clamp(0.0, _displayDeltaCapPercent)
        .toDouble();
    if (includeSign) {
      final sign = deltaPct > 0 ? '+' : '';
      return '$sign${capped.toStringAsFixed(1)}%';
    }
    return '${capped.toStringAsFixed(1)}%';
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
    // Pigment aliases
    'pigmentation': 'pigment_load',
    'pigmentation_score': 'pigment_load',
    'dark_spots': 'pigment_load',
    'darkspots': 'pigment_load',

    // Rosacea aliases
    'rosacea': 'rosacea_severity',
    'rosacea_score': 'rosacea_severity',

    // Radiance/evenness aliases
    'radiance': 'skin_tone_radiance_evenness',
    'skin_radiance': 'skin_tone_radiance_evenness',
    'evenness': 'skin_tone_radiance_evenness',

    // Firmness/elasticity aliases
    'firmness': 'structural_firmness_elasticity',
    'elasticity': 'structural_firmness_elasticity',
    'structural_firmness': 'structural_firmness_elasticity',
  };

  static const Set<String> _defectMetricKeys = {
    'rosacea_severity',
    'localized_redness',
    'diffuse_flushing_erythema',
    'pigment_load',
    'wrinkle_load',
    'glabellar_wrinkle_depth',
    'pore_visibility',
    'breakout_activity',
    'adaptive_dark_ratio',
    'sebum_excess_oil_gloss',
    'pore_contraction_index',
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
    'pore_visibility',
    'wrinkle_load',
    'pigment_load',
    'rosacea_severity',
    'diffuse_flushing_erythema',
    'pore_contraction_index',
    'under_eye_dark_circle_density',
    'under_eye_texture_density',
    'skin_tone_radiance_evenness',
    'structural_firmness_elasticity',
  };

  // NOTE: the on-device acne/rosacea TFLite regressor's `acne_severity` /
  // `rosacea_intensity` outputs are deliberately NOT in this allowlist yet.
  // A corrected-normalization probe against 5 reference photos found no
  // output index that ranks them by visible redness/rosacea severity in a
  // sensible order (see skin_analysis_service_io.dart's `_allMetrics` doc
  // comment for the full evidence) — the assumed index mapping is not just
  // unconfirmed, it's contradicted by the one unambiguous test case
  // available. Add them here only once a real index mapping is confirmed
  // against labeled data, not before.
  static bool _isDisplayableClinicalKey(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized.endsWith('_detected')) return false;
    return _continuousClinicalKeys.contains(normalized);
  }

  static bool _isBodyMetricKey(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    const bodyMetricSignals = {
      'fatretention',
      'fat_retention',
      'fatretentionpct',
      'fatretentionpercent',
      'swelling',
      'postopswelling',
      'swellingindex',
      'swellinglevel',
      'firmness',
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
      'bodyhealing',
      'body_healing',
      'bodycontour',
      'body_contour',
      'abdominal_contour',
      'waist',
      'flank',
      'buttock',
      'thigh',
      'arm_contour',
      'bbl',
    };
    return bodyMetricSignals.contains(normalized) ||
        normalized.contains('body') ||
        normalized.contains('contour');
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
            'trend_status': {
              ..._asMap(nestedLuxePayload['trend_status']),
              ..._asMap(payload['trend_status']),
            },
            'trend_lock_reasons': {
              ..._asMap(nestedLuxePayload['trend_lock_reasons']),
              ..._asMap(payload['trend_lock_reasons']),
            },
          };

    return _extractServerDeltaMetrics(
      mergedPayload,
      initialBaseline: mergedPayload['initial_baseline'] == true,
    );
  }

  static List<LuxeMetric> _extractServerDeltaMetrics(
    Map<String, dynamic> payload, {
    required bool initialBaseline,
  }) {
    final metricsNode = _canonicalizeMetricMap(payload['metrics']);

    final metricMatrix = _canonicalizeMetricMap(payload['metric_matrix']);
    final baselineMetricMatrix = _canonicalizeMetricMap(
      payload['baseline_metric_matrix'],
    );
    final metricConfidence = _canonicalizeMetricMap(
      payload['metric_confidence'],
    );
    final nestedMetricConfidence = _canonicalizeMetricMap(
      metricsNode['metric_confidence'],
    );
    final nestedMetricsRoot = _asMap(payload['metrics']);
    final nestedRootMetricConfidence = _canonicalizeMetricMap(
      nestedMetricsRoot['metric_confidence'],
    );
    final extractionPaths = _canonicalizeMetricMap(
      payload['metric_extraction_paths'],
    );
    final baselineExtractionPaths = _canonicalizeMetricMap(
      payload['baseline_metric_extraction_paths'],
    );
    final trendDeltas = _canonicalizeMetricMap(payload['trend_deltas']);
    final trendStatus = _canonicalizeMetricMap(payload['trend_status']);
    final trendLockReasons = _canonicalizeMetricMap(
      payload['trend_lock_reasons'],
    );
    final metricNoiseFloor2sd = _canonicalizeMetricMap(
      payload['metric_noise_floor_2sd'],
    );
    final multiFrameAnalysis = _asMap(payload['multi_frame_analysis']);
    final metricRanges = _canonicalizeMetricMap(
      multiFrameAnalysis['metric_ranges'],
    );
    final metricContributorCounts = _canonicalizeMetricMap(
      multiFrameAnalysis['metric_contributor_counts'],
    );
    final requestedFrameCount = _asIntOrNull(
      multiFrameAnalysis['requested_frames'],
    );

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
        deltaKey: 'pore_visibility',
        name: 'Pore Visibility',
        currentKeys: ['pore_visibility'],
      ),
      _ServerMetricSpec(
        deltaKey: 'wrinkle_load',
        name: 'Wrinkle Load',
        currentKeys: ['wrinkle_load'],
      ),
      _ServerMetricSpec(
        deltaKey: 'pigment_load',
        name: 'Pigment Load',
        currentKeys: [
          'pigment_load',
          'pigmentation',
          'pigmentation_score',
          'dark_spots',
          'darkspots',
        ],
      ),
      _ServerMetricSpec(
        deltaKey: 'rosacea_severity',
        name: 'Rosacea Severity',
        currentKeys: ['rosacea_severity', 'rosacea', 'rosacea_score'],
        higherIsWorse: true,
      ),
      _ServerMetricSpec(
        deltaKey: 'skin_tone_radiance_evenness',
        name: 'Skin Radiance & Evenness',
        currentKeys: [
          'skin_tone_radiance_evenness',
          'radiance',
          'skin_radiance',
          'evenness',
        ],
      ),
      _ServerMetricSpec(
        deltaKey: 'structural_firmness_elasticity',
        name: 'Structural Firmness & Elasticity',
        currentKeys: [
          'structural_firmness_elasticity',
          'firmness',
          'elasticity',
          'structural_firmness',
        ],
      ),
    ];

    final knownSpecByKey = {for (final spec in knownSpecs) spec.deltaKey: spec};

    final activeMetricMatrix = metricMatrix.isNotEmpty
        ? metricMatrix
        : _canonicalizeMetricMap(metricsNode['metric_matrix']);
    final supportedSpecs = <_ServerMetricSpec>[];
    for (final entry in activeMetricMatrix.entries) {
      final key = entry.key.toString();
      if (!_isDisplayableClinicalKey(key)) continue;
      final rawValue = _asDouble(entry.value);
      final allowZeroForCoreKeys =
          key == 'localized_redness' || key == 'texture_smoothness';
      if (!rawValue.isFinite || (!allowZeroForCoreKeys && rawValue <= 0.0)) {
        continue;
      }
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

    if (supportedSpecs.isEmpty) {
      return const [];
    }

    double normalizeToHundred({required double raw}) =>
        raw.clamp(0.0, 100.0).toDouble();

    final out = <LuxeMetric>[];
    for (final spec in supportedSpecs) {
      final extractedCurrent = _extractValueWithKey(
        activeMetricMatrix,
        <String>[spec.deltaKey],
      );
      final currentRaw = extractedCurrent.value;
      final hasComparableCurrentValue =
          extractedCurrent.sourceMapKey != 'not_found' && currentRaw >= 0.0;
      final currentExtractionPath = _normalizeExtractionPath(
        extractionPaths[spec.deltaKey],
      );
      final baselineExtractionPath = _normalizeExtractionPath(
        baselineExtractionPaths[spec.deltaKey],
      );

      final current = normalizeToHundred(raw: currentRaw);
      final hasDetectedCurrentValue = hasComparableCurrentValue;

      final lowerIsBetter =
          spec.higherIsWorse ?? _isDefectMetric(spec.deltaKey);
      final baselineCandidates = _baselineCandidateKeys(spec.deltaKey);
      final showTrendVerdict = shouldShowTrendVerdict(spec.deltaKey);
      final baseline = showTrendVerdict
          ? _findUsableBaselineValue(baselineMetricMatrix, baselineCandidates)
          : _findPresentBaselineValue(baselineMetricMatrix, baselineCandidates);
      final hasBaseline = baseline != null && baseline.isFinite;
      final hasComparisonBaseline =
          hasBaseline &&
          (showTrendVerdict
              ? _isUsableBaselineValue(baseline)
              : baseline >= 0.0);

      final currentConfidenceValue = _resolveMetricConfidenceValue(
        metricKey: spec.deltaKey,
        candidateKeys: spec.currentKeys,
        confidenceMaps: <Map<String, dynamic>>[
          metricConfidence,
          nestedMetricConfidence,
          nestedRootMetricConfidence,
        ],
      );
      final rangeNode = _asMap(metricRanges[spec.deltaKey]);
      final rangeMin = _asDoubleOrNull(rangeNode['min']);
      final rangeMax = _asDoubleOrNull(rangeNode['max']);
      final contributorCount =
          _asIntOrNull(metricContributorCounts[spec.deltaKey]) ??
          _asIntOrNull(rangeNode['count']);

      var resolvedCurrent = current;

      double improvementPercent;
      final backendTrendDelta = _asDoubleOrNull(trendDeltas[spec.deltaKey]);
      final backendTrendStatus = trendStatus[spec.deltaKey]?.toString().trim();
      final backendTrendLockReasonRaw = trendLockReasons[spec.deltaKey]
          ?.toString()
          .trim();
      final backendTrendLockReason =
          backendTrendLockReasonRaw == null || backendTrendLockReasonRaw.isEmpty
          ? null
          : backendTrendLockReasonRaw;
      final hasBackendTrendDelta =
          backendTrendDelta != null && backendTrendDelta.isFinite;
      final hasBackendTrendStatus =
          backendTrendStatus != null && backendTrendStatus.isNotEmpty;
      final usesBackendTrend = hasBackendTrendDelta && hasBackendTrendStatus;

      if (usesBackendTrend) {
        improvementPercent = backendTrendDelta;
      } else {
        if (hasComparisonBaseline && baseline != 0.0) {
          improvementPercent =
              ((resolvedCurrent - baseline) / baseline) * 100.0;
        } else {
          improvementPercent = 0.0;
        }
      }

      if (!resolvedCurrent.isFinite || resolvedCurrent < 0.0) {
        continue;
      }

      if (!hasComparableCurrentValue) {
        continue;
      }

      final baselineForCard = hasComparisonBaseline ? baseline : 0.0;
      final improvementForCard = hasComparisonBaseline
          ? improvementPercent
          : 0.0;

      out.add(
        LuxeMetric(
          key: spec.deltaKey,
          name: spec.name,
          baselineScore: baselineForCard,
          currentScore: resolvedCurrent.clamp(0.0, 100.0).toDouble(),
          improvementPercent: improvementForCard,
          lowerIsBetter: lowerIsBetter,
          initialBaseline: initialBaseline,
          currentConfidence: currentConfidenceValue,
          hasDetectedCurrentValue: hasDetectedCurrentValue,
          hasComparableCurrentValue: hasComparableCurrentValue,
          hasBaselineValue: hasComparisonBaseline,
          showTrendVerdict: showTrendVerdict,
          currentExtractionPath: currentExtractionPath,
          baselineExtractionPath: baselineExtractionPath,
          backendTrendDeltaPct: usesBackendTrend ? backendTrendDelta : null,
          backendTrendStatus: usesBackendTrend ? backendTrendStatus : null,
          usesBackendTrend: usesBackendTrend,
          backendTrendLockReason: backendTrendLockReason,
          currentRangeMin: rangeMin,
          currentRangeMax: rangeMax,
          currentNoiseFloor2sd: _asDoubleOrNull(
            metricNoiseFloor2sd[spec.deltaKey],
          ),
          contributorCount: contributorCount,
          requestedFrameCount: requestedFrameCount,
        ),
      );
    }
    final loaded = out.where((m) => m.hasDetectedCurrentValue).toList();
    return loaded;
  }

  static double extractValue(
    Map<String, dynamic> data,
    List<String> targetKeys,
  ) {
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
    if (value == 0.0) return true;
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

  static String _normalizeExtractionPath(dynamic value) {
    final text = value?.toString().trim().toLowerCase() ?? 'unknown';
    if (text == 'primary_roi' || text == 'fallback' || text == 'skipped') {
      return text;
    }
    return 'unknown';
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

  static double? _asDoubleOrNull(dynamic value) {
    if (value is num) {
      final numeric = value.toDouble();
      return numeric.isFinite ? numeric : null;
    }
    if (value == null) return null;
    final parsed = double.tryParse(value.toString());
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  static int? _asIntOrNull(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _canonicalMetricKey(String rawKey) {
    final normalized = rawKey.trim().toLowerCase();
    return _metricKeyAliases[normalized] ?? normalized;
  }

  static List<String> _baselineCandidateKeys(String metricKey) {
    final canonical = _canonicalMetricKey(metricKey);
    final base = <String>{canonical, metricKey.trim().toLowerCase()};

    switch (canonical) {
      case 'localized_redness':
        base.addAll([
          'localized_redness',
          'redness',
          'redness_score',
          'calibrated_redness_score',
        ]);
        break;
      case 'texture_smoothness':
        base.addAll([
          'texture_smoothness',
          'smoothness_score',
          'calibrated_smoothness_score',
          'texture',
          'skin_texture',
        ]);
        break;
      case 'pigment_load':
        base.addAll([
          'pigment_load',
          'pigment',
          'pigment_score',
          'pigmentation',
          'pigmentation_score',
          'dark_spots',
          'darkspots',
          'skin_tone_radiance_evenness',
          'radiance',
          'skin_radiance',
          'evenness',
        ]);
        break;
      case 'wrinkle_load':
        base.addAll([
          'wrinkle_load',
          'wrinkle',
          'wrinkle_score',
          'glabellar_wrinkle_depth',
          'fine_lines',
        ]);
        break;
      case 'pore_visibility':
        break;
      case 'rosacea_severity':
        base.addAll(['rosacea_severity', 'rosacea', 'rosacea_score']);
        break;
      case 'skin_tone_radiance_evenness':
        base.addAll([
          'skin_tone_radiance_evenness',
          'radiance',
          'skin_radiance',
          'evenness',
        ]);
        break;
      case 'structural_firmness_elasticity':
        base.addAll([
          'structural_firmness_elasticity',
          'firmness',
          'elasticity',
          'structural_firmness',
        ]);
        break;
      default:
        break;
    }

    final ordered = <String>[];
    for (final candidate in base) {
      final key = candidate.trim().toLowerCase();
      if (key.isEmpty || ordered.contains(key)) continue;
      ordered.add(key);
    }
    return ordered;
  }

  static double? _findUsableBaselineValue(
    Map<String, dynamic> targetMap,
    List<String> candidateKeys,
  ) {
    final map = _canonicalizeMetricMap(targetMap);
    for (final candidate in candidateKeys) {
      final key = _canonicalMetricKey(candidate);
      final raw = map[key];
      final value = _asDoubleOrNull(raw);
      if (value != null && _isUsableBaselineValue(value)) {
        return value;
      }
    }
    return null;
  }

  static double? _findPresentBaselineValue(
    Map<String, dynamic> targetMap,
    List<String> candidateKeys,
  ) {
    final map = _canonicalizeMetricMap(targetMap);
    for (final candidate in candidateKeys) {
      final key = _canonicalMetricKey(candidate);
      final value = _asDoubleOrNull(map[key]);
      if (value != null && value.isFinite && value >= 0.0) return value;
    }
    return null;
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
    required this.trendLocked,
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
  final bool trendLocked;
  final bool hasRealBaseline;
  final bool hasComparableCurrentValue;
}

enum _HonestyStatus {
  improved,
  worsened,
  stable,
  insufficientSignal,
  // Backend sent no trend_status at all for this metric, and the caller
  // (the live results screen) has opted out of the legacy local-recompute
  // fallback via _assessMetricHonesty's requireBackendVerdict. Distinct from
  // insufficientSignal: that means "the backend judged this", this means
  // "the backend never weighed in".
  noVerdict,
}

bool _hideResultVerdictForRepeatNoise({
  required String metricKey,
  required double baseline,
  required double current,
  required bool hasRealBaseline,
  required bool hasComparableCurrentValue,
  required _HonestyStatus status,
  String? lockReason,
}) {
  if (!hasComparableCurrentValue || (lockReason?.trim().isNotEmpty ?? false)) {
    return false;
  }

  switch (metricKey.trim().toLowerCase()) {
    case 'localized_redness':
      // A 0.0 reading sits at the formula's dead-zone floor; keep it
      // verdict-free as before. Any other unlocked redness keeps its verdict.
      return current <= 0.0;
    case 'structural_firmness_elasticity':
      return status != _HonestyStatus.stable &&
          hasRealBaseline &&
          (current - baseline).abs() < 4.0;
    default:
      return false;
  }
}

// Trusted metrics: a backend stable/improved/worsened verdict is shown as-is
// (the frame-spread check below never replaces it with "No verdict"), and
// with LuxeReportLayout.requireBackendVerdictForTrustedMetrics they never get
// a locally recomputed verdict either.
const Set<String> _trustedVerdictMetricKeys = <String>{
  'texture_smoothness',
  'pigment_load',
  'skin_tone_radiance_evenness',
  'pore_visibility',
  'localized_redness',
  'structural_firmness_elasticity',
};

bool _hasFrameSpreadAboveNoiseBand(LuxeMetric metric) {
  if (metric.usesBackendTrend &&
      _trustedVerdictMetricKeys.contains(metric.key.trim().toLowerCase())) {
    return false;
  }
  final min = metric.currentRangeMin;
  final max = metric.currentRangeMax;
  final noiseFloor = metric.currentNoiseFloor2sd;
  if (metric.contributorCount == null || metric.contributorCount! < 2) {
    return false;
  }
  if (min == null || max == null || noiseFloor == null) return false;
  if (!min.isFinite || !max.isFinite || !noiseFloor.isFinite) return false;
  return max - min > noiseFloor;
}

class _HonestyAssessment {
  const _HonestyAssessment({
    required this.status,
    required this.reason,
    required this.deltaPct,
    required this.hasRealBaseline,
    this.lockReason,
  });

  final _HonestyStatus status;
  final String reason;
  final double? deltaPct;
  final bool hasRealBaseline;
  // Only meaningful when status == stable: null means a genuine small delta
  // (real, honest stability); a non-null value names which honesty gate
  // forced the lock (see lib/utils/trend_lock_reason.dart for the copy).
  final String? lockReason;

  String get label {
    switch (status) {
      case _HonestyStatus.improved:
        return 'Improved';
      case _HonestyStatus.worsened:
        return 'Worsened';
      case _HonestyStatus.stable:
        return 'Stable - change within tracking noise';
      case _HonestyStatus.insufficientSignal:
        return 'Insufficient signal';
      case _HonestyStatus.noVerdict:
        return 'No verdict for this metric';
    }
  }

  /// Terse (headline/badge-safe) replacement for [label] when "stable" was
  /// reached via a capture-provenance mismatch gate, or null for a genuine
  /// small delta / any other status — callers should keep [label] unchanged
  /// in that case.
  String? get stableLockHeadline {
    if (status != _HonestyStatus.stable) return null;
    return trendLockReasonHeadline(lockReason);
  }

  /// Fuller, one-sentence explanation of the same lock, for a subtext/detail
  /// slot rather than a headline. Null under the same conditions as
  /// [stableLockHeadline].
  String? get stableLockDetail {
    if (status != _HonestyStatus.stable) return null;
    return trendLockReasonShortLabel(lockReason);
  }
}

_HonestyAssessment _assessMetricHonesty({
  required String metricKey,
  required double current,
  required double baseline,
  required bool higherIsWorse,
  bool hasComparableCurrentValue = true,
  bool? hasBaselineValue,
  Object? currentConfidence,
  String currentExtractionPath = 'unknown',
  String baselineExtractionPath = 'unknown',
  double? backendTrendDeltaPct,
  String? backendTrendStatus,
  bool usesBackendTrend = false,
  String? backendTrendLockReason,
  // See LuxeReportLayout.requireBackendVerdict. When true, a metric with a
  // real baseline and a comparable current value but no usable backend
  // trend_status (resolvedFromBackend below is null) returns noVerdict
  // instead of falling into the legacy recompute further down. Never
  // touches the !hasComparableCurrentValue / !hasRealBaseline branches --
  // those are structural facts, not a recompute, and stay honest either way.
  bool requireBackendVerdict = false,
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

  final hasRealBaseline = hasBaselineValue ?? baseline > 0.0;
  final normalizedBackendTrendStatus = backendTrendStatus?.trim().toLowerCase();
  final resolvedFromBackend = resolveTrendLabel(
    trendStatus: backendTrendStatus,
    trendLockReason: backendTrendLockReason,
    trendDeltaPct: backendTrendDeltaPct,
  );
  final normalizedLockReason = backendTrendLockReason?.trim();
  if (resolvedFromBackend == null &&
      normalizedLockReason != null &&
      normalizedLockReason.isNotEmpty) {
    return _HonestyAssessment(
      status: _HonestyStatus.stable,
      reason: 'backend trend lock=$normalizedLockReason',
      deltaPct: null,
      hasRealBaseline: hasRealBaseline,
      lockReason: normalizedLockReason,
    );
  }
  // The legacy local-recompute fallback below must be reachable ONLY when
  // the backend genuinely sent no trend_status for this metric (i.e.
  // resolvedFromBackend is null) — never merely because a caller forgot to
  // set usesBackendTrend while real status data was available. Gating on
  // resolvedFromBackend alone (not on usesBackendTrend) makes that
  // structural; this assertion catches a caller whose flag disagrees with
  // that fact instead of letting it fail silently.
  assert(
    resolvedFromBackend != null || !usesBackendTrend,
    'usesBackendTrend=true was passed for metric "$metricKey" but no usable '
    'backendTrendStatus was supplied ("$backendTrendStatus") — fix the '
    'caller instead of relying on the local-recompute fallback.',
  );
  if (resolvedFromBackend != null) {
    final mappedBackendStatus = _fromTrendDirection(
      resolvedFromBackend.direction,
    );
    return _HonestyAssessment(
      status: mappedBackendStatus,
      reason:
          'backend trend_status=${normalizedBackendTrendStatus ?? 'unknown'}',
      deltaPct: resolvedFromBackend.deltaPct,
      hasRealBaseline: hasRealBaseline,
      lockReason: resolvedFromBackend.lockReason,
    );
  }

  final normalizedMetricKey = metricKey.trim().toLowerCase();
  final hidesTrendVerdict = metricsWithHiddenTrendVerdicts.contains(
    normalizedMetricKey,
  );
  final higherIsWorseMap = <String>{
    'pore_visibility',
    'breakout_activity',
    'wrinkle_load',
    'pigment_load',
    'rosacea_severity',
    'localized_redness',
  };
  final higherIsBetterMap = <String>{
    'skin_tone_radiance_evenness',
    'structural_firmness_elasticity',
    'texture_smoothness',
    'skin_hydration',
  };
  final effectiveHigherIsWorse = higherIsWorseMap.contains(normalizedMetricKey)
      ? true
      : (higherIsBetterMap.contains(normalizedMetricKey)
            ? false
            : higherIsWorse);
  final deltaPct = hasRealBaseline && baseline != 0.0
      ? ((current - baseline) / baseline) * 100.0
      : null;
  const honestyStableBandPct = 8.0;
  final pointDelta = hasRealBaseline ? (current - baseline).abs() : null;
  final pathUnknown =
      currentExtractionPath == 'unknown' || baselineExtractionPath == 'unknown';
  final pathMismatch =
      !pathUnknown && currentExtractionPath != baselineExtractionPath;
  final nearZeroNoise = hasRealBaseline && current < 1.0 && baseline < 1.0;
  final lowConfidence = isLowConfidenceValue(currentConfidence);
  final swingThreshold = _getMaxConfidenceSwingThreshold(metricKey);
  final lowConfidenceZeroCurrent = lowConfidence && current <= 0.0;
  final lowConfidenceLargeSwing =
      lowConfidence && deltaPct != null && deltaPct.abs() >= swingThreshold;
  final withinClinicalStableBand =
      hasRealBaseline &&
      deltaPct != null &&
      deltaPct.abs() < honestyStableBandPct;
  final withinPointNoiseBand =
      hasRealBaseline && pointDelta != null && pointDelta < 2.0;

  var status = _HonestyStatus.insufficientSignal;
  var reason = hidesTrendVerdict && hasRealBaseline
      ? current.toStringAsFixed(1)
      : 'Starting point';
  // Only set for the legacy-payload path-mismatch case below; every other
  // branch here (unknown path, low confidence, near-zero noise) predates the
  // trend_lock_reason field and isn't one of the recognized reasons, so it
  // keeps the default "genuine stable" wording.
  String? lockReason;

  if (!hasComparableCurrentValue) {
    status = _HonestyStatus.insufficientSignal;
    reason = 'Not compared';
  } else if (!hasRealBaseline) {
    status = _HonestyStatus.stable;
    reason = 'Starting point';
  } else if (requireBackendVerdict) {
    status = _HonestyStatus.noVerdict;
    reason = 'No backend verdict supplied';
  } else if (pathUnknown) {
    status = _HonestyStatus.stable;
    reason = 'tracking only (unknown extraction path)';
  } else if (pathMismatch) {
    status = _HonestyStatus.stable;
    reason =
        'tracking only (path mismatch: $baselineExtractionPath->$currentExtractionPath)';
    lockReason = 'path_mismatch';
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
  } else if (withinClinicalStableBand || withinPointNoiseBand) {
    status = _HonestyStatus.stable;
    reason = 'Stable - change within tracking noise';
  } else if (deltaPct != null) {
    final increased = deltaPct > 0;
    final improved = effectiveHigherIsWorse ? !increased : increased;
    status = improved ? _HonestyStatus.improved : _HonestyStatus.worsened;
    reason = effectiveHigherIsWorse
        ? (increased ? 'higherIsWorse increase' : 'higherIsWorse decrease')
        : (increased ? 'higherIsBetter increase' : 'higherIsBetter decrease');
  }

  return _HonestyAssessment(
    status: status,
    reason: reason,
    deltaPct:
        (status == _HonestyStatus.insufficientSignal ||
            status == _HonestyStatus.noVerdict)
        ? null
        : deltaPct,
    hasRealBaseline: hasRealBaseline && !lowConfidenceZeroCurrent,
    lockReason: lockReason,
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

_HonestyStatus _fromTrendDirection(TrendDirection direction) {
  switch (direction) {
    case TrendDirection.improved:
      return _HonestyStatus.improved;
    case TrendDirection.worsened:
      return _HonestyStatus.worsened;
    case TrendDirection.stable:
      return _HonestyStatus.stable;
    case TrendDirection.insufficientSignal:
      return _HonestyStatus.insufficientSignal;
  }
}

/// Short, live-results-only phrase for a trend_lock_reason, used to build
/// "Not comparable: <phrase>" (see LuxeReportLayout.requireBackendVerdict).
/// Deliberately separate from trend_lock_reason.dart's own
/// trendLockReasonHeadline/trendLockReasonShortLabel -- those are shared by
/// other screens (Track Procedure's body silhouette trend, bridge_card.dart)
/// with their own established wording, which this must not change.
String _shortLockReasonPhrase(String reason) {
  switch (reason) {
    case 'capture_quality_mismatch':
      return 'capture conditions differed from your last scan';
    case 'path_mismatch':
      return 'a different analysis method was used than your last scan';
    case 'resolution_mismatch':
      return 'photo resolution differed too much to compare';
    case 'capture_mode_mismatch':
      return 'capture setup differed from your last scan';
    case 'scale_mismatch':
      return 'framing or distance differed too much to compare';
    case 'formula_version_mismatch':
      return "this metric's scoring was updated since your last scan";
    case 'angle_or_guide_mismatch':
      return 'a different angle or region was captured than your baseline';
    case 'frame_range_overlap':
      return 'frame-to-frame variability was too high to confirm a change';
    case 'below_noise_floor':
      return "the change is smaller than this metric's measurement noise";
    case 'cheek_mismatch':
      return 'a different cheek drove the redness score';
    case 'cast_mismatch':
      return 'the cheek color shift exceeded frame-to-frame variation';
    case 'region_mismatch':
      return 'redness was read from a different skin region than your baseline';
    case 'lighting_mismatch':
      return 'capture brightness differed too much from your baseline';
    default:
      return reason;
  }
}

/// The ONLY place that decides a metric's headline text on the live AI Skin
/// Analysis results screen (LuxeReportLayout.requireBackendVerdict == true).
/// Never used by any other caller of _assessMetricHonesty, so it cannot
/// change Track Procedure's, progress report's, or history's existing
/// wording (including the "Standalone entry" lock headline those screens
/// already show and already have passing tests for).
String _liveHonestyLabel(
  _HonestyAssessment assessment, {
  required bool isBodyMetric,
}) {
  if (assessment.status == _HonestyStatus.insufficientSignal && isBodyMetric) {
    return 'Body tracking';
  }
  switch (assessment.status) {
    case _HonestyStatus.noVerdict:
      return 'No verdict for this metric';
    case _HonestyStatus.insufficientSignal:
      return "Not enough signal: change is smaller than this metric's "
          'measurement noise';
    case _HonestyStatus.stable:
      final lockReason = assessment.lockReason;
      return lockReason == null
          ? assessment.label
          : 'Not comparable: ${_shortLockReasonPhrase(lockReason)}';
    case _HonestyStatus.improved:
    case _HonestyStatus.worsened:
      return assessment.label;
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
    this.baselineNotSavedReason,
    this.requireBackendVerdict = false,
    this.requireBackendVerdictForTrustedMetrics = false,
    this.hiddenMetricKeys = const <String>{},
  });

  final Map<String, dynamic> rawPayload;
  final ImageProvider<Object>? baselineImageProvider;
  final ImageProvider<Object>? currentImageProvider;
  final String baselineLabel;
  final String currentLabel;
  final int? localHistoryCount;
  final bool? isFollowUp;
  final String? gateReason;

  /// When true, every metric card and the clinical progress summary show
  /// ONLY the backend's own trend_status/trend_lock_reason verdict for a
  /// comparison -- never the legacy local recompute in _assessMetricHonesty
  /// (flat 8% / 2.0pt bands with no per-metric noise floor). A metric the
  /// backend marked "insufficient_signal" shows a not-enough-signal label,
  /// one it locked to "stable" via a mismatch gate shows "Not comparable:
  /// <reason>" instead of a plain "Stable", and one the backend sent no
  /// trend_status for at all shows "No verdict for this metric" -- in every
  /// one of these cases there is no arrow and no percent, though the raw
  /// current/baseline values still show. Defaults to false so every other
  /// caller (Track Procedure's local-vision payload, which never has a
  /// trend_status; progress report and history, which replay whatever an
  /// older archived scan happened to store) keeps its existing behavior,
  /// including the legacy recompute fallback, unchanged. Only the live AI
  /// Skin Analysis results screen sets this to true.
  final bool requireBackendVerdict;

  /// [requireBackendVerdict] for the trusted metrics only (texture, pigment,
  /// radiance, pore visibility, redness, firmness): with no backend
  /// trend_status they show the number and "No verdict for this metric"
  /// instead of the legacy local recompute. Every other metric keeps the
  /// caller's existing behavior. Ignored when [requireBackendVerdict] is set.
  final bool requireBackendVerdictForTrustedMetrics;

  /// Metric keys this view does not render at all: no card, number,
  /// verdict, "No verdict" row, or summary line. Display-only -- the
  /// metric is still in [rawPayload] and wherever else it is saved or
  /// exported. Empty (the default) keeps every caller's existing behavior.
  final Set<String> hiddenMetricKeys;

  bool _requiresBackendVerdictFor(String metricKey) =>
      requireBackendVerdict ||
      (requireBackendVerdictForTrustedMetrics &&
          _trustedVerdictMetricKeys.contains(metricKey.trim().toLowerCase()));

  /// Non-null when the caller determined this scan was ELIGIBLE to become
  /// the baseline (no earlier one existed) but did NOT actually become one
  /// (failed a single-scan honesty gate) -- e.g. AI Skin Analysis's
  /// scanPassesSingleScanBaselineGates. When set, this widget must never
  /// claim "Baseline scan captured" (that scan was never saved as a
  /// baseline); it shows this rejection reason instead. Null preserves the
  /// existing metrics/history-count heuristic unchanged for every other
  /// caller (Track Procedure, progress report).
  final String? baselineNotSavedReason;

  static const Color bg = Color(0xFF0F1013);
  static const Color card = Color(0xFF1A1F2C);
  // Brand/decorative accent (borders, section icons, badges) — never used
  // for improved/worsened status; see _chipColor below for those.
  static const Color gold = AppColors.brandAccent;
  static const Color roseGold = AppColors.brandAccent;

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
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.brandAccent.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.medical_information_outlined,
            size: 18,
            color: AppColors.brandAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clinical Context & Disclaimer',
                  style: TextStyle(
                    color: AppColors.textStructure,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'These AI-derived values are designed for progress tracking across your own baseline and follow-up scans. They do not diagnose disease, replace medical evaluation, or prescribe treatment.',
                  style: TextStyle(
                    color: AppColors.textStructure.withValues(alpha: 0.78),
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
    final rejection = widget.baselineNotSavedReason;
    if (rejection != null) {
      // This scan was eligible to become the baseline but failed a single-
      // scan honesty gate -- it was never saved as one, so this must never
      // claim "Baseline scan captured".
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.softTerracotta.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.flag_outlined,
                  size: 16,
                  color: AppColors.softTerracotta,
                ),
                SizedBox(width: 8),
                Text(
                  'Not saved as baseline',
                  style: TextStyle(
                    color: AppColors.textStructure,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              rejection,
              style: TextStyle(
                color: AppColors.textStructure.withValues(alpha: 0.80),
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.brandAccent.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.flag_rounded, size: 16, color: AppColors.brandAccent),
              SizedBox(width: 8),
              Text(
                'Baseline scan captured',
                style: TextStyle(
                  color: AppColors.textStructure,
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
              color: AppColors.textStructure.withValues(alpha: 0.80),
              fontSize: 11.2,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            style: TextStyle(
              color: AppColors.textStructure.withValues(alpha: 0.62),
              fontSize: 10.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicalProgressSummary(List<LuxeMetric> metrics) {
    if (metrics.isEmpty || metrics.every((m) => m.initialBaseline)) {
      return const SizedBox.shrink();
    }

    final statements = <String>[];
    for (final metric in metrics) {
      if (!metric.showTrendVerdict) continue;
      final assessment = _assessMetricHonesty(
        metricKey: metric.key,
        current: metric.currentScore,
        baseline: metric.baselineScore,
        higherIsWorse: metric.lowerIsBetter,
        hasComparableCurrentValue: metric.hasComparableCurrentValue,
        hasBaselineValue: metric.hasBaselineValue,
        currentConfidence: metric.currentConfidence,
        currentExtractionPath: metric.currentExtractionPath,
        baselineExtractionPath: metric.baselineExtractionPath,
        backendTrendDeltaPct: metric.backendTrendDeltaPct,
        backendTrendStatus: metric.backendTrendStatus,
        usesBackendTrend: metric.usesBackendTrend,
        backendTrendLockReason: metric.backendTrendLockReason,
        requireBackendVerdict: widget._requiresBackendVerdictFor(metric.key),
      );
      final metricName = metric.name;
      if (assessment.lockReason == null &&
          _hasFrameSpreadAboveNoiseBand(metric)) {
        statements.add('$metricName: No verdict for this metric.');
        continue;
      }
      if (_hideResultVerdictForRepeatNoise(
        metricKey: metric.key,
        baseline: metric.baselineScore,
        current: metric.currentScore,
        hasRealBaseline: assessment.hasRealBaseline,
        hasComparableCurrentValue: metric.hasComparableCurrentValue,
        status: assessment.status,
        lockReason: assessment.lockReason,
      )) {
        statements.add('$metricName: No verdict for this metric.');
        continue;
      }
      if (assessment.status == _HonestyStatus.noVerdict) {
        statements.add('$metricName: No verdict for this metric.');
        continue;
      }
      if (assessment.status == _HonestyStatus.insufficientSignal) {
        final isBodyMetric = LuxeMetricParser._isBodyMetricKey(metric.key);
        statements.add(
          isBodyMetric
              ? '$metricName: Body tracking is still building your baseline — trends will appear as more scans accumulate. Check back after a few more sessions.'
              : '$metricName: Insufficient signal.',
        );
        continue;
      }
      if (assessment.status == _HonestyStatus.stable) {
        final lockDetail = assessment.stableLockDetail;
        statements.add('$metricName: ${lockDetail ?? 'Stable.'}');
        continue;
      }
      statements.add('$metricName: ${assessment.label}.');
    }

    if (statements.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.brandAccent.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Clinical Progress Summary',
            style: TextStyle(
              color: AppColors.textStructure,
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
                    color: AppColors.brandAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: TextStyle(
                      color: AppColors.textStructure.withValues(alpha: 0.80),
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
    final localHistoryCount =
        widget.localHistoryCount ??
        LuxeMetricParser._asDouble(
          widget.rawPayload['local_history_count'] ??
              widget.rawPayload['localHistoryCount'],
        ).round();
    final explicitFollowUp =
        widget.isFollowUp ??
        (widget.rawPayload['is_follow_up'] == true ||
            widget.rawPayload['isFollowUp'] == true);
    final initialBaseline = widget.rawPayload['initial_baseline'] == true;
    final showProgressComparison =
        (explicitFollowUp || localHistoryCount >= 2) && !initialBaseline;
    final metrics = LuxeMetricParser.parseTimelinePayload(
      widget.rawPayload,
    ).where((m) => !widget.hiddenMetricKeys.contains(m.key)).toList();
    final visibleMetrics = metrics.where((m) => !m.initialBaseline).toList();
    final willRenderCards = visibleMetrics.isNotEmpty;
    final showBaselinePendingFooter =
        localHistoryCount < 2 &&
        !explicitFollowUp &&
        metrics.isNotEmpty &&
        metrics.every((m) => m.initialBaseline);
    final reason =
        widget.gateReason ??
        (willRenderCards
            ? (showProgressComparison
                  ? (hasLocalHistoryMetadata
                        ? (explicitFollowUp
                              ? 'explicit follow-up flag from local history'
                              : 'local history count >= 2')
                        : 'baseline-follow-up pair detected from scan payload')
                  : 'baseline metrics available (progress compare pending)')
            : 'no displayable metric_matrix keys in payload');

    if (!willRenderCards) {
      if (!showBaselinePendingFooter) {
        return const SizedBox.shrink();
      }
      return Container(
        color: AppColors.cardBackground,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_buildBaselineCapturedMessage(reason)],
        ),
      );
    }
    if (visibleMetrics.isEmpty) {
      return showBaselinePendingFooter
          ? Container(
              color: AppColors.cardBackground,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_buildBaselineCapturedMessage(reason)],
              ),
            )
          : const SizedBox.shrink();
    }
    final showComparisonFrames =
        showProgressComparison &&
        widget.baselineImageProvider != null &&
        widget.currentImageProvider != null;
    final captureConsistency = captureConsistencyForPayload(
      widget.rawPayload,
      isBodyProcedure: false,
    );

    return Container(
      color: AppColors.cardBackground,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showProgressComparison && captureConsistency.checkCount > 0) ...[
            _buildCaptureConsistencyNote(captureConsistency),
            const SizedBox(height: 12),
          ],
          if (showComparisonFrames) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.brandAccent.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: AppColors.brandAccent,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Before vs After comparison',
                      style: TextStyle(
                        color: AppColors.textStructure,
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
                          ? AppColors.brandAccent
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
                        showProgressComparison: showProgressComparison,
                        selected: _selectedMetricKey == metric.key,
                        onTap: () => _handleMetricTap(metric),
                        requireBackendVerdict: widget
                            ._requiresBackendVerdictFor(metric.key),
                      ),
                    ),
                ],
              );
            },
          ),
          if (visibleMetrics.isNotEmpty && showProgressComparison) ...[
            const SizedBox(height: 16),
            _buildClinicalProgressSummary(visibleMetrics),
            const SizedBox(height: 16),
            _buildClinicalContextCard(),
          ] else if (visibleMetrics.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildBaselineCapturedMessage(
              'Baseline captured. Add another photo in similar lighting to unlock personalized progress tracking.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCaptureConsistencyNote(CaptureConsistencyResult result) {
    return Row(
      children: [
        const Icon(Icons.tune_rounded, size: 15, color: AppColors.brandAccent),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            result.displayText,
            softWrap: true,
            style: const TextStyle(
              color: AppColors.textStructure,
              fontSize: 11.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
    required this.showProgressComparison,
    required this.selected,
    required this.onTap,
    this.requireBackendVerdict = false,
  });

  final LuxeMetric metric;
  final bool showProgressComparison;
  final bool selected;
  final VoidCallback onTap;
  final bool requireBackendVerdict;

  _MetricRowData _buildMetricRowData() {
    final hasComparisonContext =
        showProgressComparison || metric.hasBaselineValue;
    if (!hasComparisonContext && !metric.showTrendVerdict) {
      return _MetricRowData(
        baselineValue: 0.0,
        currentValue: metric.currentScore,
        trendDelta: null,
        badgePercent: null,
        badgeValueText: null,
        subtext: 'Starting point for future progress tracking',
        initialBaseline: true,
        honestyStatus: _HonestyStatus.insufficientSignal,
        honestyLabel: metric.hasComparableCurrentValue
            ? metric.name
            : 'Starting point',
        trendLocked: false,
        hasRealBaseline: false,
        hasComparableCurrentValue: metric.hasComparableCurrentValue,
      );
    }

    if (!metric.showTrendVerdict) {
      final hasBaseline = metric.hasBaselineValue;
      return _MetricRowData(
        baselineValue: metric.baselineScore,
        currentValue: metric.currentScore,
        trendDelta: null,
        badgePercent: null,
        badgeValueText: null,
        subtext: '',
        initialBaseline: !hasBaseline,
        honestyStatus: _HonestyStatus.noVerdict,
        honestyLabel: metric.hasComparableCurrentValue
            ? metric.name
            : 'Starting point',
        trendLocked: false,
        hasRealBaseline: hasBaseline,
        hasComparableCurrentValue: metric.hasComparableCurrentValue,
      );
    }

    final baselineValue = metric.baselineScore;
    final currentValue = metric.currentScore;
    final resolvedAssessment = _assessMetricHonesty(
      metricKey: metric.key,
      current: currentValue,
      baseline: baselineValue,
      higherIsWorse: metric.lowerIsBetter,
      hasComparableCurrentValue: metric.hasComparableCurrentValue,
      hasBaselineValue: metric.hasBaselineValue,
      currentConfidence: metric.currentConfidence,
      currentExtractionPath: metric.currentExtractionPath,
      baselineExtractionPath: metric.baselineExtractionPath,
      backendTrendDeltaPct: metric.backendTrendDeltaPct,
      backendTrendStatus: metric.backendTrendStatus,
      usesBackendTrend: metric.usesBackendTrend,
      backendTrendLockReason: metric.backendTrendLockReason,
      requireBackendVerdict: requireBackendVerdict,
    );
    final assessment =
        resolvedAssessment.lockReason == null &&
            _hasFrameSpreadAboveNoiseBand(metric)
        ? _HonestyAssessment(
            status: _HonestyStatus.noVerdict,
            reason: 'frame spread exceeds the existing noise floor',
            deltaPct: null,
            hasRealBaseline: resolvedAssessment.hasRealBaseline,
          )
        : _hideResultVerdictForRepeatNoise(
            metricKey: metric.key,
            baseline: baselineValue,
            current: currentValue,
            hasRealBaseline: resolvedAssessment.hasRealBaseline,
            hasComparableCurrentValue: metric.hasComparableCurrentValue,
            status: resolvedAssessment.status,
            lockReason: resolvedAssessment.lockReason,
          )
        ? _HonestyAssessment(
            status: _HonestyStatus.noVerdict,
            reason: 'within repeat noise',
            deltaPct: null,
            hasRealBaseline: resolvedAssessment.hasRealBaseline,
          )
        : resolvedAssessment;
    final isBodyMetric = LuxeMetricParser._isBodyMetricKey(metric.key);
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
    // A "stable" trend can mean a genuine small delta OR a forced lock from
    // a capture-provenance mismatch gate (capture quality, extraction path,
    // resolution, ...) — the stableLock* getters are only non-null in the
    // latter case, so they take priority over the generic "Stable" wording
    // without touching a genuine stable's existing copy. The headline uses
    // the terse form (it renders in a large, tightly-constrained slot); the
    // subtext uses the fuller one-sentence explanation.
    final stableLockDetail = assessment.stableLockDetail;
    final subtext = assessment.hasRealBaseline
        ? (assessment.reason == 'Re-scan recommended (Lighting/Angle variance)'
              ? assessment.reason
              : stableLockDetail ?? assessment.label)
        : 'Tracks visible appearance in key zones';
    const bodyEarlyAccessMessage =
        'Body tracking is still building your baseline — trends will appear as more scans accumulate. Check back after a few more sessions.';

    final honestyLabel = requireBackendVerdict
        ? _liveHonestyLabel(assessment, isBodyMetric: isBodyMetric)
        : (assessment.status == _HonestyStatus.insufficientSignal &&
                  isBodyMetric
              ? 'Body tracking'
              : assessment.stableLockHeadline ?? assessment.label);
    final finalSubtext =
        assessment.status == _HonestyStatus.insufficientSignal && isBodyMetric
        ? bodyEarlyAccessMessage
        : subtext;

    return _MetricRowData(
      baselineValue: baselineValue,
      currentValue: currentValue,
      trendDelta: trendDelta,
      badgePercent: badgePercent,
      badgeValueText: badgeValueText,
      subtext: finalSubtext,
      initialBaseline: initialBaseline,
      honestyStatus: assessment.status,
      honestyLabel: honestyLabel,
      trendLocked: assessment.lockReason != null,
      hasRealBaseline: assessment.hasRealBaseline,
      hasComparableCurrentValue: metric.hasComparableCurrentValue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = _buildMetricRowData();
    final chipColor = row.trendLocked
        ? const Color(0xFF8E7F6D)
        : _chipColor(row.honestyStatus);
    const titleColor = AppColors.textStructure;
    final headlineDelta = row.honestyLabel;
    final hideDuplicateMetricName =
        metricsWithHiddenTrendVerdicts.contains(metric.key) &&
        row.hasComparableCurrentValue;
    final precision = metricPrecisionPresentation(metric);
    final currentDisplayText = row.hasComparableCurrentValue
        ? formatScoreWithSeverityBand(metric.key, row.currentValue)
        : 'Not compared';
    final comparisonSubtitle = !metric.showTrendVerdict
        ? currentDisplayText
        : row.trendLocked
        ? 'Current $currentDisplayText${precision.rangeSuffix}'
        : row.hasRealBaseline
        ? 'Current $currentDisplayText${precision.rangeSuffix} · Baseline ${row.baselineValue.toStringAsFixed(1)}'
        : 'Current $currentDisplayText${precision.rangeSuffix}';
    final progressionLine = !row.hasComparableCurrentValue
        ? '${metric.name}: Not compared (${row.subtext})'
        : row.trendLocked
        ? '${metric.name}: ${row.subtext}'
        : row.hasRealBaseline
        ? '${metric.name}: ${row.baselineValue.toStringAsFixed(1)} -> ${row.currentValue.toStringAsFixed(1)} '
              '(${row.subtext})'
        : '${metric.name}: ${row.currentValue.toStringAsFixed(1)} current scan (${row.subtext})';

    return Material(
      key: ValueKey('result_metric_${metric.key}'),
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
                  ? AppColors.brandAccent
                  : AppColors.borders.withValues(alpha: 0.65),
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
                comparisonSubtitle,
                style: const TextStyle(
                  color: titleColor,
                  fontSize: 10.9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              if (metric.showTrendVerdict) ...[
                const SizedBox(height: 3),
                Text(
                  precision.detailText,
                  style: TextStyle(
                    color: titleColor.withValues(alpha: 0.66),
                    fontSize: 10.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (!hideDuplicateMetricName) ...[
                const SizedBox(height: 5),
                Text(
                  metric.name,
                  style: TextStyle(
                    color: titleColor.withValues(alpha: 0.88),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (metric.showTrendVerdict) ...[
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
              ],
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

  Color _chipColor(_HonestyStatus status) {
    switch (status) {
      case _HonestyStatus.improved:
        return AppColors.kMetricImprovedColor;
      case _HonestyStatus.worsened:
        return AppColors.kMetricWorsenedColor;
      case _HonestyStatus.stable:
        // Was `gold` (brand accent) — stable is grouped with improved under
        // the same status-green per the palette spec, and must not borrow
        // the brand accent (critical rule: status colors never = accent).
        return AppColors.kMetricImprovedColor;
      case _HonestyStatus.insufficientSignal:
      case _HonestyStatus.noVerdict:
        return const Color(0xFF8E7F6D);
    }
  }
}

class _AiOverlayPainter extends CustomPainter {
  _AiOverlayPainter({required this.highlightedZone, required this.pulse})
    : super(repaint: pulse);

  final String? highlightedZone;
  final Animation<double>? pulse;

  bool _isZone(String zone) =>
      highlightedZone == zone || highlightedZone == 'full_face';

  @override
  void paint(Canvas canvas, Size size) {
    final pulseBoost = pulse == null ? 0.0 : (pulse!.value * 0.28);

    final forehead = Paint()
      ..color = (_isZone('glabella') || _isZone('tzone'))
          ? AppColors.brandAccent.withValues(alpha: 0.20 + pulseBoost)
          : AppColors.brandAccent.withValues(alpha: 0.40);
    final cheek = Paint()
      ..color = (_isZone('cheeks') || _isZone('cheeks_nose'))
          ? AppColors.brandAccent.withValues(alpha: 0.20 + pulseBoost)
          : AppColors.kMetricImprovedColor.withValues(alpha: 0.40);
    final tzone = Paint()
      ..color = (_isZone('tzone') || _isZone('cheeks_nose'))
          ? AppColors.brandAccent.withValues(alpha: 0.22 + pulseBoost)
          : AppColors.kMetricWorsenedColor.withValues(alpha: 0.40);
    final jawline = Paint()
      ..color = _isZone('jawline')
          ? AppColors.brandAccent.withValues(alpha: 0.20 + pulseBoost)
          : AppColors.kMetricImprovedColor.withValues(alpha: 0.33);

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
