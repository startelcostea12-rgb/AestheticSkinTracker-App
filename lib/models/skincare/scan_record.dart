/// A normalized skin scan record for AI, progress tracking, and reporting.
///
/// Store local file paths or opaque storage keys in [imagePath]. Avoid storing
/// direct cloud URLs with user identifiers when white-label or HIPAA controls
/// are enabled.
class ScanRecord {
  final String id;
  final DateTime capturedAt;
  final ScanSource source;
  final String? imagePath;
  final String? procedureId;
  final List<String> productIds;
  final SkinMetricSet metrics;
  final List<String> visibleFindings;
  final String aiSummary;
  final String poseTemplate;
  final String focusArea;
  final bool makeupPresent;
  final double? lightingConfidence;
  final double? expressionConfidence;
  final double? distanceEstimate;
  final bool isBaseline;
  final bool preferredReference;
  final String notes;
  final DateTime createdAt;

  const ScanRecord({
    required this.id,
    required this.capturedAt,
    this.source = ScanSource.aiAnalysis,
    this.imagePath,
    this.procedureId,
    this.productIds = const [],
    this.metrics = const SkinMetricSet(),
    this.visibleFindings = const [],
    this.aiSummary = '',
    this.poseTemplate = '',
    this.focusArea = '',
    this.makeupPresent = false,
    this.lightingConfidence,
    this.expressionConfidence,
    this.distanceEstimate,
    this.isBaseline = false,
    this.preferredReference = false,
    this.notes = '',
    required this.createdAt,
  });

  factory ScanRecord.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ScanRecord(
      id: _readString(json['id']),
      capturedAt: _readDate(json['capturedAt']) ?? now,
      source: ScanSourceX.fromJson(json['source']),
      imagePath: _readNullableString(json['imagePath']),
      procedureId: _readNullableString(json['procedureId']),
      productIds: _readStringList(json['productIds']),
      metrics: json['metrics'] is Map
          ? SkinMetricSet.fromJson(Map<String, dynamic>.from(json['metrics']))
          : const SkinMetricSet(),
      visibleFindings: _readStringList(json['visibleFindings']),
      aiSummary: _readString(json['aiSummary']),
      poseTemplate: _readString(json['poseTemplate']),
      focusArea: _readString(json['focusArea']),
      makeupPresent: json['makeupPresent'] as bool? ?? false,
      lightingConfidence: _readDouble(json['lightingConfidence']),
      expressionConfidence: _readDouble(json['expressionConfidence']),
      distanceEstimate: _readDouble(json['distanceEstimate']),
      isBaseline: json['isBaseline'] as bool? ?? false,
      preferredReference: json['preferredReference'] as bool? ?? false,
      notes: _readString(json['notes']),
      createdAt: _readDate(json['createdAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'capturedAt': capturedAt.toIso8601String(),
    'source': source.jsonValue,
    'imagePath': imagePath,
    'procedureId': procedureId,
    'productIds': productIds,
    'metrics': metrics.toJson(),
    'visibleFindings': visibleFindings,
    'aiSummary': aiSummary,
    'poseTemplate': poseTemplate,
    'focusArea': focusArea,
    'makeupPresent': makeupPresent,
    'lightingConfidence': lightingConfidence,
    'expressionConfidence': expressionConfidence,
    'distanceEstimate': distanceEstimate,
    'isBaseline': isBaseline,
    'preferredReference': preferredReference,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
  };

  ScanRecord copyWith({
    String? id,
    DateTime? capturedAt,
    ScanSource? source,
    String? imagePath,
    bool clearImagePath = false,
    String? procedureId,
    bool clearProcedureId = false,
    List<String>? productIds,
    SkinMetricSet? metrics,
    List<String>? visibleFindings,
    String? aiSummary,
    String? poseTemplate,
    String? focusArea,
    bool? makeupPresent,
    double? lightingConfidence,
    bool clearLightingConfidence = false,
    double? expressionConfidence,
    bool clearExpressionConfidence = false,
    double? distanceEstimate,
    bool clearDistanceEstimate = false,
    bool? isBaseline,
    bool? preferredReference,
    String? notes,
    DateTime? createdAt,
  }) {
    return ScanRecord(
      id: id ?? this.id,
      capturedAt: capturedAt ?? this.capturedAt,
      source: source ?? this.source,
      imagePath: clearImagePath ? null : imagePath ?? this.imagePath,
      procedureId: clearProcedureId ? null : procedureId ?? this.procedureId,
      productIds: productIds ?? this.productIds,
      metrics: metrics ?? this.metrics,
      visibleFindings: visibleFindings ?? this.visibleFindings,
      aiSummary: aiSummary ?? this.aiSummary,
      poseTemplate: poseTemplate ?? this.poseTemplate,
      focusArea: focusArea ?? this.focusArea,
      makeupPresent: makeupPresent ?? this.makeupPresent,
      lightingConfidence: clearLightingConfidence
          ? null
          : lightingConfidence ?? this.lightingConfidence,
      expressionConfidence: clearExpressionConfidence
          ? null
          : expressionConfidence ?? this.expressionConfidence,
      distanceEstimate: clearDistanceEstimate
          ? null
          : distanceEstimate ?? this.distanceEstimate,
      isBaseline: isBaseline ?? this.isBaseline,
      preferredReference: preferredReference ?? this.preferredReference,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class SkinMetricSet {
  final double redness;
  final double texture;
  final double fineLines;
  final double pores;
  final double pigmentation;
  final double firmness;
  final double hydration;
  final double sensitivity;

  const SkinMetricSet({
    this.redness = 0,
    this.texture = 0,
    this.fineLines = 0,
    this.pores = 0,
    this.pigmentation = 0,
    this.firmness = 0,
    this.hydration = 0,
    this.sensitivity = 0,
  });

  factory SkinMetricSet.fromJson(Map<String, dynamic> json) => SkinMetricSet(
    redness: _readDouble(json['redness']) ?? 0,
    texture: _readDouble(json['texture']) ?? 0,
    fineLines: _readDouble(json['fineLines'] ?? json['wrinkles']) ?? 0,
    pores: _readDouble(json['pores']) ?? 0,
    pigmentation: _readDouble(json['pigmentation'] ?? json['darkSpots']) ?? 0,
    firmness: _readDouble(json['firmness'] ?? json['elasticity']) ?? 0,
    hydration: _readDouble(json['hydration']) ?? 0,
    sensitivity: _readDouble(json['sensitivity']) ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'redness': redness,
    'texture': texture,
    'fineLines': fineLines,
    'pores': pores,
    'pigmentation': pigmentation,
    'firmness': firmness,
    'hydration': hydration,
    'sensitivity': sensitivity,
  };
}

enum ScanSource { onboarding, aiAnalysis, procedure, routine, progress, manual }

extension ScanSourceX on ScanSource {
  String get jsonValue => name;

  static ScanSource fromJson(Object? value) =>
      _enumFromName(ScanSource.values, value, ScanSource.aiAnalysis);
}

T _enumFromName<T extends Enum>(List<T> values, Object? value, T fallback) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return fallback;
  final normalized = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
  for (final candidate in values) {
    if (candidate.name.toLowerCase() == normalized) return candidate;
  }
  return fallback;
}

String _readString(Object? value) => value?.toString().trim() ?? '';

String? _readNullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

double? _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

DateTime? _readDate(Object? value) {
  if (value is DateTime) return value;
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

List<String> _readStringList(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
