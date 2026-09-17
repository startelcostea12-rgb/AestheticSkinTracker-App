import '../models/scan_history.dart';

class CaptureConsistencyResult {
  const CaptureConsistencyResult({
    required this.score,
    required this.checkCount,
  });

  final double? score;
  final int checkCount;

  String get displayText => score == null
      ? 'Capture consistency unavailable'
      : 'Capture consistency: ${score!.toStringAsFixed(0)}% · $checkCount checks';
}

CaptureConsistencyResult captureConsistencyForScanPair({
  required bool isBodyProcedure,
  required ScanHistoryEntry? baseline,
  required ScanHistoryEntry? latest,
}) {
  if (baseline == null || latest == null) {
    return const CaptureConsistencyResult(score: null, checkCount: 0);
  }

  final scores = <double>[];
  final qualityScore = _captureQualityScore(
    baseline.captureQuality,
    latest.captureQuality,
  );
  if (qualityScore != null) scores.add(qualityScore);

  final resolutionScore = _resolutionScore(
    baseline.sourceImageWidth,
    baseline.sourceImageHeight,
    latest.sourceImageWidth,
    latest.sourceImageHeight,
  );
  if (resolutionScore != null) scores.add(resolutionScore);

  final alignmentScore = _alignmentScore(latest.metrics);
  if (alignmentScore != null) scores.add(alignmentScore);

  if (isBodyProcedure) {
    final modeScore = _binaryMatchScore(
      baseline.captureMode,
      latest.captureMode,
    );
    if (modeScore != null) scores.add(modeScore);

    final scaleScore = _scaleScore(baseline.rawPayload, latest.rawPayload);
    if (scaleScore != null) scores.add(scaleScore);
  } else {
    final pathScore = _pathMatchScore(baseline, latest);
    if (pathScore != null) scores.add(pathScore);
  }

  return _average(scores);
}

CaptureConsistencyResult captureConsistencyForPayload(
  Map<String, dynamic> payload, {
  required bool isBodyProcedure,
}) {
  final scores = <double>[];
  final qualityScore = _captureQualityScore(
    _stringValue(payload['baseline_capture_quality'] ?? payload['baselineCaptureQuality']),
    _stringValue(payload['capture_quality'] ?? payload['captureQuality']),
  );
  if (qualityScore != null) scores.add(qualityScore);

  final resolutionScore = _resolutionScore(
    _intValue(payload['baseline_source_image_width'] ?? payload['baselineSourceImageWidth']),
    _intValue(payload['baseline_source_image_height'] ?? payload['baselineSourceImageHeight']),
    _intValue(payload['source_image_width'] ?? payload['sourceImageWidth']),
    _intValue(payload['source_image_height'] ?? payload['sourceImageHeight']),
  );
  if (resolutionScore != null) scores.add(resolutionScore);

  final alignmentScore = _alignmentScore(payload['capture_reference_alignment_score']);
  if (alignmentScore != null) scores.add(alignmentScore);

  if (isBodyProcedure) {
    final modeScore = _binaryMatchScore(
      _stringValue(payload['baseline_capture_mode'] ?? payload['baselineCaptureMode']),
      _stringValue(payload['capture_mode'] ?? payload['captureMode']),
    );
    if (modeScore != null) scores.add(modeScore);
    final scaleScore = _scaleScore(payload['baseline_result'], payload['result']);
    if (scaleScore != null) scores.add(scaleScore);
  } else {
    final pathScore = _pathMapMatchScore(
      payload['baseline_metric_extraction_paths'],
      payload['metric_extraction_paths'],
    );
    if (pathScore != null) scores.add(pathScore);
  }

  return _average(scores);
}

CaptureConsistencyResult _average(List<double> scores) {
  if (scores.isEmpty) {
    return const CaptureConsistencyResult(score: null, checkCount: 0);
  }
  final total = scores.fold<double>(0.0, (sum, value) => sum + value);
  return CaptureConsistencyResult(
    score: total / scores.length,
    checkCount: scores.length,
  );
}

double? _captureQualityScore(String? baseline, String? latest) {
  final left = _normalized(baseline);
  final right = _normalized(latest);
  if (left == null || right == null) return null;
  return left == 'normal' && right == 'normal' ? 100.0 : 0.0;
}

double? _binaryMatchScore(String? baseline, String? latest) {
  final left = _normalized(baseline);
  final right = _normalized(latest);
  if (left == null || right == null) return null;
  return left == right ? 100.0 : 0.0;
}

double? _resolutionScore(
  int? baselineWidth,
  int? baselineHeight,
  int? latestWidth,
  int? latestHeight,
) {
  if (baselineWidth == null ||
      baselineHeight == null ||
      latestWidth == null ||
      latestHeight == null ||
      baselineWidth <= 0 ||
      baselineHeight <= 0 ||
      latestWidth <= 0 ||
      latestHeight <= 0) {
    return null;
  }
  final delta = [
    (latestWidth - baselineWidth).abs() / baselineWidth,
    (latestHeight - baselineHeight).abs() / baselineHeight,
  ].reduce((left, right) => left > right ? left : right);
  return _thresholdScore(delta);
}

double? _scaleScore(dynamic baselinePayload, dynamic latestPayload) {
  final baseline = _scaleReference(baselinePayload);
  final latest = _scaleReference(latestPayload);
  if (baseline == null || latest == null || baseline <= 0.0) return null;
  return _thresholdScore((latest - baseline).abs() / baseline);
}

double _thresholdScore(double delta) =>
    (100.0 * (1.0 - (delta / 0.20))).clamp(0.0, 100.0).toDouble();

double? _alignmentScore(dynamic value) {
  final numeric = _doubleValue(value);
  if (numeric == null || !numeric.isFinite) return null;
  return numeric.clamp(0.0, 100.0).toDouble() <= 1.0
      ? numeric.clamp(0.0, 1.0).toDouble() * 100.0
      : numeric.clamp(0.0, 100.0).toDouble();
}

double? _pathMatchScore(ScanHistoryEntry baseline, ScanHistoryEntry latest) {
  final baselinePaths = _pathMap(baseline);
  final latestPaths = _pathMap(latest);
  return _pathMapsScore(baselinePaths, latestPaths);
}

double? _pathMapMatchScore(dynamic baseline, dynamic latest) =>
    _pathMapsScore(_asStringMap(baseline), _asStringMap(latest));

double? _pathMapsScore(
  Map<String, String> baseline,
  Map<String, String> latest,
) {
  if (baseline.isEmpty || latest.isEmpty) return null;
  final keys = {...baseline.keys, ...latest.keys};
  if (keys.isEmpty) return null;
  final matches = keys.where(
    (key) => baseline[key] != null && baseline[key] == latest[key],
  );
  return 100.0 * matches.length / keys.length;
}

Map<String, String> _pathMap(ScanHistoryEntry entry) {
  final raw = entry.rawPayload;
  final nested = raw?['metrics'];
  return _asStringMap(
    raw?['metric_extraction_paths'] ??
        (nested is Map ? nested['metric_extraction_paths'] : null),
  );
}

Map<String, String> _asStringMap(dynamic value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key.toString().trim().isNotEmpty &&
          entry.value?.toString().trim().isNotEmpty == true)
        entry.key.toString().trim().toLowerCase():
            entry.value.toString().trim().toLowerCase(),
  };
}

double? _scaleReference(dynamic payload) {
  if (payload is! Map) return null;
  final result = payload['result'];
  final value = result is Map
      ? result['scale_reference_pixels'] ?? result['scaleReferencePixels']
      : payload['scale_reference_pixels'] ?? payload['scaleReferencePixels'];
  return _doubleValue(value);
}

String? _normalized(dynamic value) {
  final text = value?.toString().trim().toLowerCase();
  return text == null || text.isEmpty ? null : text;
}

String? _stringValue(dynamic value) => _normalized(value);

int? _intValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}