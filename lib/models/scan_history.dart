// ====================== CORE MODELS ======================

class SkinMetrics {
  final double redness;
  final double texture;
  final double wrinkle;
  final double pore;
  final double darkSpots;
  final double elasticity;
  final DateTime? date; // Added for analysis_results_screen.dart
  final String? procedure; // Added for app_prefs.dart and other usage

  const SkinMetrics({
    this.redness = 5.0,
    this.texture = 5.0,
    this.wrinkle = 5.0,
    this.pore = 5.0,
    this.darkSpots = 5.0,
    this.elasticity = 5.0,
    this.date,
    this.procedure,
  });

  // Static simulatedScan method used in camera_screen.dart
  static SkinMetrics simulatedScan({SkinMetrics? previous}) {
    final prev = previous ?? const SkinMetrics();
    return SkinMetrics(
      redness: prev.redness.clamp(0.0, 10.0),
      texture: prev.texture.clamp(0.0, 10.0),
      wrinkle: prev.wrinkle.clamp(0.0, 10.0),
      pore: prev.pore.clamp(0.0, 10.0),
      darkSpots: prev.darkSpots.clamp(0.0, 10.0),
      elasticity: prev.elasticity.clamp(0.0, 10.0),
      date: DateTime.now(),
      procedure: prev.procedure,
    );
  }
}

/// Canonical baseline-scoping key for the AI Skin Analysis flow -- see
/// [ScanHistoryEntry.resolveAiBaselineKey]. A plain record so equality/
/// hashing are structural for free, and so it's trivially JSON-round-
/// trippable field-by-field wherever it needs to be persisted.
typedef AiBaselineKey = ({
  String? procedureId,
  String? focusArea,
  String? poseTemplate,
  String? guideType,
});

class ScanHistoryEntry {
  static const String scanTypeProcedure = 'procedure';
  static const String scanTypeSkincare = 'skincare';
  static const String scanTypeAiAnalysis = 'ai_analysis';

  /// On-device TFLite analysis (SkinAnalysisService in lib/services/).
  static const String engineLocalTflite = 'local-tflite';

  /// Remote backend analysis (main.py /api/skin/analyze-single or
  /// /api/analyze-skin, reached via lib/utils/skin_analysis_service.dart).
  static const String engineBackendOpencv = 'backend_opencv';

  /// Legacy scans saved before scan provenance was tracked, or scans with
  /// no engine-identifying data (e.g. manually-entered body metrics).
  static const String engineUnknown = 'unknown';

  /// Resolves a scan's analysis engine from a raw result payload's
  /// `modelUsed` (or `model_used`) tag, falling back to [fallback] when the
  /// payload carries no such tag.
  static String resolveScanEngine(
    Map<String, dynamic>? payload, {
    String fallback = engineUnknown,
  }) {
    final raw = payload?['modelUsed'] ?? payload?['model_used'];
    final text = raw?.toString().trim();
    return (text == null || text.isEmpty) ? fallback : text;
  }

  /// True only when [a] and [b] are the same known engine. Different
  /// engines (or either being [engineUnknown]) measure metrics with
  /// different instruments and are not directly comparable — callers
  /// computing trend deltas between two scans should force "stable" /
  /// insufficient-comparison instead of reporting a real delta when this
  /// returns false, same principle as the capture-quality/path-mismatch
  /// honesty guard.
  static bool scanEnginesComparable(String a, String b) {
    if (a == engineUnknown || b == engineUnknown) return false;
    return a == b;
  }

  /// True only when both scans have the SAME non-null pose template (view
  /// angle -- e.g. "Front", "Left 45°", "Left Profile") AND the SAME
  /// non-null guide type ("facial"/"body"/"general"). A null on either
  /// side means the angle or region is unknown for that scan and must
  /// never be treated as a match -- there is no "unknown matches
  /// anything" fallback, and no falling back to a different angle (e.g.
  /// "Left 45°" is never treated as "Left Profile"). This is in addition
  /// to, not a replacement for, the existing procedureId and focusArea
  /// gates callers already apply.
  static bool scansComparableByAngleAndGuide({
    required String? poseTemplateA,
    required String? guideTypeA,
    required String? poseTemplateB,
    required String? guideTypeB,
  }) {
    if (poseTemplateA == null || poseTemplateB == null) return false;
    if (poseTemplateA != poseTemplateB) return false;
    if (guideTypeA == null || guideTypeB == null) return false;
    if (guideTypeA != guideTypeB) return false;
    return true;
  }

  /// Canonical baseline-scoping key for the AI Skin Analysis flow: a scan
  /// can only ever serve as the baseline for other scans sharing the exact
  /// same (procedureId, focusArea, poseTemplate, guideType). Records have
  /// structural equality in Dart, so two keys built from equivalent inputs
  /// compare `==` without a custom class.
  ///
  /// Nulls are significant, not wildcards: a null procedureId matches only
  /// another null procedureId, and a null focusArea matches only another
  /// null focusArea (see [resolveAiBaselineKey]'s doc comment) -- there is
  /// no "unscoped" fallback that would let a scan from a different
  /// procedure or focus area silently qualify.
  static AiBaselineKey resolveAiBaselineKey({
    required String? procedureId,
    required String? focusArea,
    required String? poseTemplate,
    required String? guideType,
  }) {
    String? trimmedOrNull(String? value) {
      final trimmed = value?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    }

    String? normalizedFocusOrNull(String? value) {
      final normalized = value
          ?.trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ');
      return (normalized == null || normalized.isEmpty) ? null : normalized;
    }

    return (
      procedureId: trimmedOrNull(procedureId),
      focusArea: normalizedFocusOrNull(focusArea),
      poseTemplate: trimmedOrNull(poseTemplate),
      guideType: trimmedOrNull(guideType),
    );
  }

  /// This scan's own [AiBaselineKey], for matching it against a capture's
  /// resolved key. A scan with a null [poseTemplate] or [guideType] gets a
  /// key with that field null, which [resolveAiBaselineKey] guarantees can
  /// never equal a real (non-null) capture's key -- so such a scan can
  /// never be selected as anyone's baseline, exactly the "missing angle or
  /// region disqualifies it" rule.
  AiBaselineKey get aiBaselineKey => resolveAiBaselineKey(
    procedureId: procedureId,
    focusArea: focusArea,
    poseTemplate: poseTemplate,
    guideType: guideType,
  );

  final String id;
  final DateTime timestamp;
  final String? imagePath;
  final String? procedureId;
  final String? parentBaselineId;
  final String? scanType;

  /// The specific [PeptideEntry.id] this scan was taken for.
  /// Null for legacy scans that pre-date per-peptide tracking.
  final String? peptideId;
  final double estimatedSkinAge;
  final Map<String, double> metrics;
  final Map<String, dynamic>? rawPayload;
  final String? procedure;
  final String? productName;
  final String? poseTemplate;

  /// The camera guide type ([ProcedureCameraGuideType.name] -- 'facial',
  /// 'body', or 'general') actually resolved for this capture (see
  /// resolveCameraGuideType in camera_screen.dart). Saved verbatim from what
  /// the capture flow used, never inferred here from a product name or
  /// procedure label. Null for scans saved before this field existed --
  /// trend/before-after comparisons must treat a null guideType as unknown,
  /// not as a match.
  final String? guideType;
  final String? focusArea;
  final String? customDescription;
  final double? lightingConfidence;
  final bool preferredReference;
  final bool isBaseline; // TRUE if this is the first photo for a procedure
  final Map<String, double>? bodyReferenceGeometry;
  final Map<String, double>? faceReferenceGeometry;

  /// True if the user disclosed that they were wearing makeup, sunscreen, or
  /// active skincare products at capture time. Clinical accuracy is reduced
  /// for these scans; downstream consumers should surface a badge and may
  /// down-weight or exclude these entries from trend calculations.
  final bool makeupPresent;

  /// Estimated subject-to-lens distance signal (0..1). Derived from face
  /// landmark detection quality at capture. Higher = better framed.
  final double? distanceEstimate;

  /// Head tilt magnitude in degrees (sum of |yaw|+|pitch|+|roll| or
  /// rotation-proxy fallback). Lower = more neutral head pose.
  final double? headTiltAngle;

  /// Confidence (0..1) that the subject's expression was neutral and the
  /// face was acceptably visible at capture.
  final double? expressionConfidence;

  /// Capture-time quality tag: normal | low_light | face_offcenter |
  /// partial_body_framing | poor_angle | uneven_lighting | blurry.
  final String? captureQuality;

  /// Which analysis engine produced [metrics]: [engineLocalTflite],
  /// [engineBackendOpencv], or [engineUnknown] for legacy/manual scans.
  /// Scans from different engines are not directly comparable — see
  /// trend-delta guards in progress_report_screen.dart.
  final String scanEngine;

  /// Real-world capture setup for body-region scans: [captureModeMirror],
  /// [captureModeAssisted], or [captureModeTimer]. Null for face/general
  /// scans and for legacy body scans predating this field. A mirror-mode
  /// scan's photo is left-right flipped back to normal orientation before
  /// being saved, so this does not affect metric comparability the way
  /// [scanEngine] does — it exists so a captureMode MISMATCH between a
  /// baseline and a later scan can be treated as an honesty-gate signal
  /// (same principle as a scale_reference_pixels mismatch), since switching
  /// capture methods can shift framing/depth even with correct orientation.
  static const String captureModeMirror = 'mirror';
  static const String captureModeAssisted = 'assisted';
  static const String captureModeTimer = 'timer';

  final String? captureMode;

  /// Original camera/gallery image dimensions before the manual crop.
  /// Null for scans saved before resolution provenance was introduced.
  final int? sourceImageWidth;
  final int? sourceImageHeight;

  const ScanHistoryEntry({
    required this.id,
    required this.timestamp,
    this.imagePath,
    this.procedureId,
    this.parentBaselineId,
    this.scanType,
    this.peptideId,
    required this.estimatedSkinAge,
    required this.metrics,
    this.rawPayload,
    this.procedure,
    this.productName,
    this.poseTemplate,
    this.guideType,
    this.focusArea,
    this.customDescription,
    this.lightingConfidence,
    this.preferredReference = false,
    this.isBaseline = false,
    this.bodyReferenceGeometry,
    this.faceReferenceGeometry,
    this.makeupPresent = false,
    this.distanceEstimate,
    this.headTiltAngle,
    this.expressionConfidence,
    this.captureQuality,
    this.scanEngine = engineUnknown,
    this.captureMode,
    this.sourceImageWidth,
    this.sourceImageHeight,
  });
  factory ScanHistoryEntry.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? asDynamicMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    final metricSource =
        asDynamicMap(json['metrics']) ??
        asDynamicMap(json['metric_matrix']) ??
        asDynamicMap(json['opencv_metrics']) ??
        Map<String, dynamic>.from(json);

    final numericMetrics = <String, double>{};
    for (final entry in metricSource.entries) {
      final value = entry.value;
      double? parsed;
      if (value is num) {
        parsed = value.toDouble();
      } else if (value != null) {
        parsed = double.tryParse(value.toString());
      }
      if (parsed == null || !parsed.isFinite) continue;
      numericMetrics[entry.key] = parsed;
    }
    final migratedMetrics = migrateMetricsForLuxe(numericMetrics);

    final payload =
        asDynamicMap(json['rawPayload']) ??
        asDynamicMap(json['extraMetrics']) ??
        Map<String, dynamic>.from(json);

    final bodyReferenceGeometry = (() {
      final raw = json['bodyReferenceGeometry'] ?? json['body_reference_geometry'];
      if (raw is Map) {
        final out = <String, double>{};
        for (final entry in raw.entries) {
          final value = entry.value;
          if (value is num) {
            out[entry.key.toString()] = value.toDouble();
          } else if (value is String) {
            final parsed = double.tryParse(value);
            if (parsed != null) out[entry.key.toString()] = parsed;
          }
        }
        return out.isEmpty ? null : out;
      }
      return null;
    })();
    final faceReferenceGeometry = (() {
      final raw = json['faceReferenceGeometry'] ?? json['face_reference_geometry'];
      if (raw is Map) {
        final out = <String, double>{};
        for (final entry in raw.entries) {
          final value = entry.value;
          if (value is num) {
            out[entry.key.toString()] = value.toDouble();
          } else if (value is String) {
            final parsed = double.tryParse(value);
            if (parsed != null) out[entry.key.toString()] = parsed;
          }
        }
        return out.isEmpty ? null : out;
      }
      return null;
    })();

    return ScanHistoryEntry(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      imagePath: json['imagePath'] as String?,
      procedureId: json['procedureId'] as String?,
      parentBaselineId: json['parentBaselineId'] as String?,
      scanType: _normalizeScanType(json['scanType'] as String?),
      peptideId: json['peptideId'] as String?,
      estimatedSkinAge: (json['estimatedSkinAge'] as num?)?.toDouble() ?? 0,
      metrics: migratedMetrics,
      rawPayload: payload,
      procedure: json['procedure'] as String?,
      productName: json['productName'] as String?,
      poseTemplate: json['poseTemplate'] as String?,
      guideType: (json['guideType'] as String?)?.trim().isNotEmpty == true
          ? (json['guideType'] as String).trim()
          : null,
      focusArea: json['focusArea'] as String?,
      customDescription:
          (json['customDescription'] as String?)?.trim().isNotEmpty == true
          ? (json['customDescription'] as String).trim()
          : null,
      lightingConfidence: (json['lightingConfidence'] as num?)?.toDouble(),
      preferredReference: json['preferredReference'] as bool? ?? false,
      isBaseline: json['isBaseline'] as bool? ?? false,
      bodyReferenceGeometry: bodyReferenceGeometry,
      faceReferenceGeometry: faceReferenceGeometry,
      makeupPresent: json['makeupPresent'] as bool? ?? false,
      distanceEstimate: (json['distanceEstimate'] as num?)?.toDouble(),
      headTiltAngle: (json['headTiltAngle'] as num?)?.toDouble(),
      expressionConfidence: (json['expressionConfidence'] as num?)?.toDouble(),
      captureQuality: (json['captureQuality'] as String?)?.trim().isNotEmpty == true
        ? (json['captureQuality'] as String).trim()
        : ((json['capture_quality'] as String?)?.trim().isNotEmpty == true
          ? (json['capture_quality'] as String).trim()
          : null),
      scanEngine: (json['scanEngine'] as String?)?.trim().isNotEmpty == true
          ? (json['scanEngine'] as String).trim()
          : engineUnknown,
      captureMode: (json['captureMode'] as String?)?.trim().isNotEmpty == true
          ? (json['captureMode'] as String).trim()
          : null,
        sourceImageWidth: (json['sourceImageWidth'] as num?)?.toInt() ??
          (json['source_image_width'] as num?)?.toInt(),
        sourceImageHeight: (json['sourceImageHeight'] as num?)?.toInt() ??
          (json['source_image_height'] as num?)?.toInt(),
    );
  }

  /// Backward-compatible metric migration:
  /// preserves old keys while adding unified 0-100 Luxe keys used by newer UI.
  static Map<String, double> migrateMetricsForLuxe(Map<String, double> source) {
    final migrated = Map<String, double>.from(source);

    double? pick(List<String> keys) {
      for (final key in keys) {
        final value = migrated[key];
        if (value == null || value.isNaN || value.isInfinite) continue;
        return value;
      }
      return null;
    }

    double toPercentConcern(double value) {
      if (value <= 1.2) return (value * 100).clamp(0.0, 100.0).toDouble();
      if (value <= 10.0) return (value * 10).clamp(0.0, 100.0).toDouble();
      return value.clamp(0.0, 100.0).toDouble();
    }

    double toPercentBenefit(double value) {
      if (value <= 1.2) return (value * 100).clamp(0.0, 100.0).toDouble();
      if (value <= 10.0) return (value * 10).clamp(0.0, 100.0).toDouble();
      return value.clamp(0.0, 100.0).toDouble();
    }

    final redness = pick(['redness', 'erythema']);
    final textureConcern = pick(['texture', 'roughness']);
    final smoothness = pick(['smoothness', 'texture_smoothness']);
    final wrinkle = pick(['wrinkle', 'wrinkles', 'rhytids', 'fineLines']);
    final pigment = pick(['darkSpots', 'pigmentation', 'pigment']);
    final elasticity = pick(['elasticity', 'firmness']);

    if (!migrated.containsKey('localized_redness') && redness != null) {
      migrated['localized_redness'] = toPercentConcern(redness);
    }

    if (!migrated.containsKey('texture_smoothness')) {
      if (smoothness != null) {
        migrated['texture_smoothness'] = toPercentBenefit(smoothness);
      } else if (textureConcern != null) {
        final concern01 = (toPercentConcern(textureConcern) / 100.0).clamp(
          0.0,
          1.0,
        );
        migrated['texture_smoothness'] = ((1.0 - concern01) * 100.0)
            .clamp(0.0, 100.0)
            .toDouble();
      }
    }

    if (!migrated.containsKey('wrinkle_load') && wrinkle != null) {
      migrated['wrinkle_load'] = toPercentConcern(wrinkle);
    }

    if (!migrated.containsKey('pigment_load') && pigment != null) {
      migrated['pigment_load'] = toPercentConcern(pigment);
    }

    if (!migrated.containsKey('structural_firmness_elasticity') &&
        elasticity != null) {
      migrated['structural_firmness_elasticity'] = toPercentBenefit(elasticity);
    }

    // Explicit LuxeMetricGrid-aligned keys (concern-style 0-100) used by
    // migrated displays while preserving older aliases.
    if (!migrated.containsKey('luxe_redness_score') && redness != null) {
      migrated['luxe_redness_score'] = toPercentConcern(redness);
    }
    if (!migrated.containsKey('luxe_texture_score') && textureConcern != null) {
      migrated['luxe_texture_score'] = toPercentConcern(textureConcern);
    }
    if (!migrated.containsKey('luxe_wrinkle_depth_score') && wrinkle != null) {
      migrated['luxe_wrinkle_depth_score'] = toPercentConcern(wrinkle);
    }

    return migrated;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'imagePath': imagePath,
      'procedureId': procedureId,
      'parentBaselineId': parentBaselineId,
      'scanType': resolvedScanType,
      'peptideId': peptideId,
      'estimatedSkinAge': estimatedSkinAge,
      'metrics': metrics,
      'rawPayload': rawPayload,
      'procedure': procedure,
      'productName': productName,
      'poseTemplate': poseTemplate,
      'guideType': guideType,
      'focusArea': focusArea,
      'customDescription': customDescription,
      'lightingConfidence': lightingConfidence,
      'preferredReference': preferredReference,
      'isBaseline': isBaseline,
      'bodyReferenceGeometry': bodyReferenceGeometry,
      'body_reference_geometry': bodyReferenceGeometry,
      'faceReferenceGeometry': faceReferenceGeometry,
      'face_reference_geometry': faceReferenceGeometry,
      'makeupPresent': makeupPresent,
      'distanceEstimate': distanceEstimate,
      'headTiltAngle': headTiltAngle,
      'expressionConfidence': expressionConfidence,
      'captureQuality': captureQuality,
      'capture_quality': captureQuality,
      'scanEngine': scanEngine,
      'captureMode': captureMode,
      'sourceImageWidth': sourceImageWidth,
      'sourceImageHeight': sourceImageHeight,
      'source_image_width': sourceImageWidth,
      'source_image_height': sourceImageHeight,
    };
  }

  /// Relative weight this scan should carry in trend averaging. Makeup-present
  /// scans receive half weight to reflect their reduced clinical reliability.
  double get trendWeight => makeupPresent ? 0.5 : 1.0;

  bool get hasTrustworthyEstimatedSkinAge {
    final normalizedQuality = (captureQuality ?? '').trim().toLowerCase();
    if (normalizedQuality.isNotEmpty && normalizedQuality != 'normal') {
      return false;
    }

    final confidenceValues = _metricConfidenceValues;
    if (confidenceValues.isNotEmpty &&
        confidenceValues.values.any((value) => value < 0.65)) {
      return false;
    }

    return estimatedSkinAge > 0;
  }

  double? get trustworthyEstimatedSkinAge {
    return hasTrustworthyEstimatedSkinAge ? estimatedSkinAge : null;
  }

  Map<String, double> get _metricConfidenceValues {
    final extracted = <String, double>{};

    void addFrom(dynamic value, String key) {
      if (value is num) {
        final numeric = value.toDouble();
        if (numeric.isFinite) extracted[key] = numeric.clamp(0.0, 1.0);
        return;
      }
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'low') {
          extracted[key] = 0.45;
        } else if (normalized == 'medium') {
          extracted[key] = 0.72;
        } else if (normalized == 'high') {
          extracted[key] = 0.9;
        } else {
          final parsed = double.tryParse(normalized);
          if (parsed != null && parsed.isFinite) {
            extracted[key] = parsed.clamp(0.0, 1.0);
          }
        }
      }
    }

    final payloadMap = rawPayload ?? const <String, dynamic>{};
    final metricsMap = metrics;

    void addConfidenceEntries(Map<dynamic, dynamic>? confidenceData) {
      if (confidenceData == null) return;
      for (final entry in confidenceData.entries) {
        final key = entry.key;
        if (key is String) {
          addFrom(entry.value, key);
        }
      }
    }

    addConfidenceEntries(payloadMap['metric_confidence'] as Map<dynamic, dynamic>?);
    addConfidenceEntries(metricsMap['metric_confidence'] as Map<dynamic, dynamic>?);

    final relevantKeys = <String>{
      'redness',
      'texture',
      'wrinkle',
      'wrinkles',
      'pore',
      'pores',
      'darkSpots',
      'dark_spots',
      'elasticity',
      'localized_redness',
      'texture_smoothness',
      'wrinkle_load',
      'pore_visibility',
      'pigment_load',
      'structural_firmness_elasticity',
    };

    for (final key in relevantKeys) {
      if (metricsMap.containsKey(key)) {
        final value = metricsMap[key];
        if (value != null) {
          extracted[key] = value.toDouble().clamp(0.0, 1.0);
        }
      }
    }

    return extracted;
  }

  String get resolvedScanType {
    final explicit = _normalizeScanType(scanType);
    if (explicit != null) return explicit;
    if (metrics['sourceSkinAiAnalysis'] == 1 ||
        procedureId == 'ai_skin_analysis') {
      return scanTypeAiAnalysis;
    }
    if ((productName ?? '').trim().isNotEmpty) return scanTypeSkincare;
    return scanTypeProcedure;
  }

  bool get isAiAnalysisScan => resolvedScanType == scanTypeAiAnalysis;
  bool get isSkincareScan => resolvedScanType == scanTypeSkincare;
  bool get isProcedureScan => resolvedScanType == scanTypeProcedure;

  SkinMetrics toSkinMetrics() {
    return SkinMetrics(
      redness: metrics['redness'] ?? 5.0,
      texture: metrics['texture'] ?? 5.0,
      wrinkle: metrics['wrinkles'] ?? metrics['wrinkle'] ?? 5.0,
      pore: metrics['pores'] ?? metrics['pore'] ?? 5.0,
      darkSpots: metrics['darkSpots'] ?? 5.0,
      elasticity: metrics['elasticity'] ?? 5.0,
      date: timestamp,
      procedure: procedure,
    );
  }

  static String generateId(DateTime timestamp, String? imagePath) {
    final ts = timestamp.millisecondsSinceEpoch;
    final pathHash = imagePath?.hashCode ?? 0;
    return 'scan_${ts}_$pathHash';
  }

  bool isEquivalentTo(ScanHistoryEntry other) {
    bool close(double a, double b) => (a - b).abs() < 0.0001;
    if (id != other.id) return false;
    if ((procedureId ?? '') != (other.procedureId ?? '')) return false;
    if ((parentBaselineId ?? '') != (other.parentBaselineId ?? '')) {
      return false;
    }
    if (resolvedScanType != other.resolvedScanType) return false;
    if ((peptideId ?? '') != (other.peptideId ?? '')) return false;
    if ((imagePath ?? '') != (other.imagePath ?? '')) return false;
    if ((productName ?? '') != (other.productName ?? '')) return false;
    if ((poseTemplate ?? '') != (other.poseTemplate ?? '')) return false;
    if ((guideType ?? '') != (other.guideType ?? '')) return false;
    if ((focusArea ?? '') != (other.focusArea ?? '')) return false;
    if ((customDescription ?? '') != (other.customDescription ?? '')) {
      return false;
    }
    if ((lightingConfidence ?? -1) != (other.lightingConfidence ?? -1)) {
      return false;
    }
    if (preferredReference != other.preferredReference) return false;
    if (isBaseline != other.isBaseline) return false;
    final refGeo = bodyReferenceGeometry ?? const <String, double>{};
    final otherGeo = other.bodyReferenceGeometry ?? const <String, double>{};
    final geoKeys = {...refGeo.keys, ...otherGeo.keys};
    for (final key in geoKeys) {
      if (!close(refGeo[key] ?? 0, otherGeo[key] ?? 0)) return false;
    }
    final faceGeo = faceReferenceGeometry ?? const <String, double>{};
    final otherFaceGeo = other.faceReferenceGeometry ?? const <String, double>{};
    final faceGeoKeys = {...faceGeo.keys, ...otherFaceGeo.keys};
    for (final key in faceGeoKeys) {
      if (!close(faceGeo[key] ?? 0, otherFaceGeo[key] ?? 0)) return false;
    }
    if (makeupPresent != other.makeupPresent) return false;
    if (!close(estimatedSkinAge, other.estimatedSkinAge)) return false;
    // Canonicalize both sides through the same backward-compat migration
    // fromJson applies before comparing. migrateMetricsForLuxe is a pure,
    // idempotent, additive backfill (it only ever adds a derived key when
    // absent, never overwrites), so this doesn't hide real metric
    // differences — it just stops an unmigrated map (e.g. a freshly
    // constructed entry) and its already-migrated counterpart (e.g. after
    // a toJson/fromJson round-trip) from registering as "different" when
    // their underlying source metrics are identical.
    final migratedMetrics = migrateMetricsForLuxe(metrics);
    final otherMigratedMetrics = migrateMetricsForLuxe(other.metrics);
    final keys = {...migratedMetrics.keys, ...otherMigratedMetrics.keys};
    for (final key in keys) {
      if (!close(migratedMetrics[key] ?? 0, otherMigratedMetrics[key] ?? 0)) {
        return false;
      }
    }
    if ((captureQuality ?? '') != (other.captureQuality ?? '')) return false;
    if (scanEngine != other.scanEngine) return false;
    if ((captureMode ?? '') != (other.captureMode ?? '')) return false;
    if (sourceImageWidth != other.sourceImageWidth) return false;
    if (sourceImageHeight != other.sourceImageHeight) return false;
    return true;
  }

  static String? _normalizeScanType(String? value) {
    final clean = value?.trim().toLowerCase();
    if (clean == null || clean.isEmpty) return null;
    switch (clean) {
      case scanTypeProcedure:
      case 'procedure_scan':
        return scanTypeProcedure;
      case scanTypeSkincare:
      case 'skincare_log':
      case 'skincare_scan':
        return scanTypeSkincare;
      case scanTypeAiAnalysis:
      case 'ai':
      case 'skin_ai':
      case 'ai_deep_analysis':
        return scanTypeAiAnalysis;
      default:
        return clean;
    }
  }
}

// ====================== HELPER FUNCTION ======================
/// Calculates the apparent (visual) skin age from scan metrics.
///
/// Weights wrinkles (30%) and elasticity (25%) most heavily as the strongest
/// visible age indicators. Elasticity is inverted because higher = better skin
/// firmness = younger appearance.
///
/// Scale: 1–10 per metric; redness/texture/wrinkle/pore/darkSpots = lower is
/// better; elasticity = higher is better.
/// Output range: 18–70 years.
double estimateVisualSkinAge(SkinMetrics metrics) {
  return estimateVisualSkinAgeFromAiMetrics({
        'pigment': metrics.darkSpots,
        'redness': metrics.redness,
        'texture': metrics.texture,
        'wrinkle': metrics.wrinkle,
        'acne_severity': metrics.pore * 0.45,
        'rosacea_intensity': metrics.redness,
      }) ??
      32.0;
}

/// Estimates apparent skin age from the six AI Skin Analysis metrics.
///
/// Accepts either native model values on a 0-1 scale or timeline values on a
/// 0-10 scale. Wrinkle and texture carry the highest weights because they are
/// the strongest visual-aging signals; inflammation still contributes, but less
/// than structural surface changes.
double? estimateVisualSkinAgeFromAiMetrics(Map<String, double> metrics) {
  double? readMetric(List<String> keys) {
    for (final key in keys) {
      final raw = metrics[key];
      if (raw == null || raw.isNaN || raw.isInfinite) continue;
      final normalized = raw <= 1.2 ? raw * 10 : raw;
      return normalized.clamp(0.0, 10.0).toDouble();
    }
    return null;
  }

  final pigment = readMetric(['pigment', 'pigmentation', 'darkSpots']);
  final redness = readMetric(['redness', 'erythema']);
  final texture = readMetric(['texture', 'roughness', 'smoothness']);
  final wrinkle = readMetric(['wrinkle', 'wrinkles', 'rhytids']);
  final acne = readMetric(['acne_severity', 'acneSeverity', 'activeBreakouts']);
  final rosacea = readMetric(['rosacea_intensity', 'rosaceaSeverity']);

  final values = [
    pigment,
    redness,
    texture,
    wrinkle,
    acne,
    rosacea,
  ].whereType<double>().where((v) => v > 0.05).toList();
  if (values.isEmpty) return null;

  final weightedScore =
      (wrinkle ?? 0) * 0.28 +
      (texture ?? 0) * 0.23 +
      (pigment ?? 0) * 0.16 +
      (redness ?? 0) * 0.13 +
      (acne ?? 0) * 0.10 +
      (rosacea ?? 0) * 0.10;
  final presentWeight =
      (wrinkle == null ? 0 : 0.28) +
      (texture == null ? 0 : 0.23) +
      (pigment == null ? 0 : 0.16) +
      (redness == null ? 0 : 0.13) +
      (acne == null ? 0 : 0.10) +
      (rosacea == null ? 0 : 0.10);
  if (presentWeight <= 0) return null;

  final normalizedSeverity = weightedScore / presentWeight;
  return (27.0 + normalizedSeverity * 3.1).clamp(24.0, 60.0).toDouble();
}
