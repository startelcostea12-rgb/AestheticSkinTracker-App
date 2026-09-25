import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_theme.dart';

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

// ====================== ANALYSIS RESULT CLASSES ======================
class DarkSpotAnalysisResult {
  final double score;
  final int fadePercent;
  final List<Offset> hotSpots;

  const DarkSpotAnalysisResult({
    required this.score,
    required this.fadePercent,
    required this.hotSpots,
  });
}

class AcneScarAnalysisResult {
  final double score;
  final int fadePercent;
  final List<Offset> improvingSpots;

  const AcneScarAnalysisResult({
    required this.score,
    required this.fadePercent,
    required this.improvingSpots,
  });
}

class HydrationAnalysisResult {
  final double score;
  final int improvedPercent;

  const HydrationAnalysisResult({
    required this.score,
    required this.improvedPercent,
  });
}

class PoreSizeAnalysisResult {
  final double score;
  final int reductionPercent;
  final List<Offset> tightenedAreas;

  const PoreSizeAnalysisResult({
    required this.score,
    required this.reductionPercent,
    required this.tightenedAreas,
  });
}

class HyperpigmentationAnalysisResult {
  final double score;
  final int reductionPercent;
  final List<Offset> improvedAreas;

  const HyperpigmentationAnalysisResult({
    required this.score,
    required this.reductionPercent,
    required this.improvedAreas,
  });
}

class ElasticityAnalysisResult {
  final double score;
  final int improvedPoints;
  final List<Offset> firmAreas;

  const ElasticityAnalysisResult({
    required this.score,
    required this.improvedPoints,
    required this.firmAreas,
  });
}

class OilinessAnalysisResult {
  final double score;
  final int reductionPercent;
  final List<Offset> mattifiedAreas;

  const OilinessAnalysisResult({
    required this.score,
    required this.reductionPercent,
    required this.mattifiedAreas,
  });
}

class SkinConcernAnalysis {
  final DarkSpotAnalysisResult darkSpot;
  final AcneScarAnalysisResult acneScar;
  final HydrationAnalysisResult hydration;
  final PoreSizeAnalysisResult poreSize;
  final HyperpigmentationAnalysisResult hyperpigmentation;
  final ElasticityAnalysisResult elasticity;
  final OilinessAnalysisResult oiliness;
  final double overlayConfidence;
  final String? photoQualityMessage;

  const SkinConcernAnalysis({
    required this.darkSpot,
    required this.acneScar,
    required this.hydration,
    required this.poreSize,
    required this.hyperpigmentation,
    required this.elasticity,
    required this.oiliness,
    this.overlayConfidence = 0.9,
    this.photoQualityMessage,
  });
}

class PhotoQualityAssessment {
  final bool poorLighting;
  final double confidence;
  final String? message;

  const PhotoQualityAssessment({
    required this.poorLighting,
    required this.confidence,
    required this.message,
  });
}

// ====================== FALLBACK FUNCTIONS ======================
DarkSpotAnalysisResult _darkSpotFallbackFromMetrics(SkinMetrics metrics) {
  final score = ((metrics.redness * 5.2) + (metrics.texture * 4.1)).clamp(
    0.0,
    100.0,
  );
  final fadePercent = ((58.0 - score).round()).clamp(6, 38);
  return DarkSpotAnalysisResult(
    score: score,
    fadePercent: fadePercent,
    hotSpots: const [
      Offset(0.31, 0.34),
      Offset(0.67, 0.39),
      Offset(0.43, 0.58),
      Offset(0.58, 0.64),
    ],
  );
}

AcneScarAnalysisResult _acneScarFallbackFromMetrics(SkinMetrics metrics) {
  final score = ((metrics.texture * 5.0) + (metrics.pore * 4.7)).clamp(
    0.0,
    100.0,
  );
  final fadePercent = ((54.0 - score).round()).clamp(6, 34);
  return AcneScarAnalysisResult(
    score: score,
    fadePercent: fadePercent,
    improvingSpots: const [
      Offset(0.36, 0.41),
      Offset(0.55, 0.47),
      Offset(0.48, 0.61),
    ],
  );
}

HydrationAnalysisResult _hydrationFallbackFromMetrics(SkinMetrics metrics) {
  final score = (100 - ((metrics.redness * 4.0) + (metrics.texture * 3.6)))
      .clamp(0.0, 100.0);
  final improvedPercent = ((score - 55.0).round()).clamp(8, 30);
  return HydrationAnalysisResult(
    score: score,
    improvedPercent: improvedPercent,
  );
}

PoreSizeAnalysisResult _poreSizeFallbackFromMetrics(SkinMetrics metrics) {
  final score = ((metrics.pore * 7.2) + (metrics.texture * 2.8)).clamp(
    0.0,
    100.0,
  );
  final reductionPercent = ((62.0 - score).round()).clamp(8, 34);
  return PoreSizeAnalysisResult(
    score: score,
    reductionPercent: reductionPercent,
    tightenedAreas: const [
      Offset(0.42, 0.46),
      Offset(0.56, 0.49),
      Offset(0.49, 0.57),
    ],
  );
}

HyperpigmentationAnalysisResult _hyperpigmentationFallbackFromMetrics(
  SkinMetrics metrics,
) {
  final score = ((metrics.redness * 3.8) + (metrics.texture * 3.3)).clamp(
    0.0,
    100.0,
  );
  final reductionPercent = ((61.0 - score).round()).clamp(9, 34);
  return HyperpigmentationAnalysisResult(
    score: score,
    reductionPercent: reductionPercent,
    improvedAreas: const [Offset(0.39, 0.44), Offset(0.60, 0.47)],
  );
}

ElasticityAnalysisResult _elasticityFallbackFromMetrics(SkinMetrics metrics) {
  final score = (100 - ((metrics.wrinkle * 6.2) + (metrics.texture * 2.7)))
      .clamp(0.0, 100.0);
  final improvedPoints = ((score - 63).round()).clamp(2, 16);
  return ElasticityAnalysisResult(
    score: score,
    improvedPoints: improvedPoints,
    firmAreas: const [Offset(0.46, 0.55), Offset(0.56, 0.56)],
  );
}

OilinessAnalysisResult _oilinessFallbackFromMetrics(SkinMetrics metrics) {
  final score = ((metrics.pore * 4.4) + (metrics.redness * 3.0)).clamp(
    0.0,
    100.0,
  );
  final reductionPercent = ((58.0 - score).round()).clamp(8, 32);
  return OilinessAnalysisResult(
    score: score,
    reductionPercent: reductionPercent,
    mattifiedAreas: const [Offset(0.50, 0.30), Offset(0.45, 0.40)],
  );
}

// ====================== SKIN CONCERN ANALYSIS ======================
Future<SkinConcernAnalysis> analyzeSkinConcerns({
  String? imagePath,
  Uint8List? imageBytes,
  required SkinMetrics metrics,
}) async {
  PhotoQualityAssessment quality = const PhotoQualityAssessment(
    poorLighting: false,
    confidence: 0.92,
    message: null,
  );

  if (imagePath != null && !kIsWeb) {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 180);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData != null && image.width > 0 && image.height > 0) {
        quality = _assessPhotoQuality(
          rgba: byteData.buffer.asUint8List(),
          width: image.width,
          height: image.height,
        );
      }
    } catch (_) {
      quality = const PhotoQualityAssessment(
        poorLighting: true,
        confidence: 0.5,
        message: 'Bad lighting - try again in better conditions',
      );
    }
  }

  final results = await Future.wait([
    analyzeDarkSpots(imagePath: imagePath, metrics: metrics),
    analyzeAcneScars(imagePath: imagePath, metrics: metrics),
    analyzeHydration(imagePath: imagePath, metrics: metrics),
    analyzePoreSize(imagePath: imagePath, metrics: metrics),
    analyzeHyperpigmentation(imagePath: imagePath, metrics: metrics),
    analyzeElasticity(imagePath: imagePath, metrics: metrics),
    analyzeOiliness(imagePath: imagePath, metrics: metrics),
  ]);

  return SkinConcernAnalysis(
    darkSpot: results[0] as DarkSpotAnalysisResult,
    acneScar: results[1] as AcneScarAnalysisResult,
    hydration: results[2] as HydrationAnalysisResult,
    poreSize: results[3] as PoreSizeAnalysisResult,
    hyperpigmentation: results[4] as HyperpigmentationAnalysisResult,
    elasticity: results[5] as ElasticityAnalysisResult,
    oiliness: results[6] as OilinessAnalysisResult,
    overlayConfidence: quality.confidence,
    photoQualityMessage: quality.message,
  );
}

PhotoQualityAssessment _assessPhotoQuality({
  required Uint8List rgba,
  required int width,
  required int height,
}) {
  if (rgba.isEmpty || width == 0 || height == 0) {
    return const PhotoQualityAssessment(
      poorLighting: true,
      confidence: 0.5,
      message: 'Bad lighting - try again in better conditions',
    );
  }

  const stride = 2;
  double mean = 0;
  double m2 = 0;
  int count = 0;
  double edgeSum = 0;
  int edgeCount = 0;

  double brightnessAt(int x, int y) {
    final idx = (y * width + x) * 4;
    final r = rgba[idx].toDouble();
    final g = rgba[idx + 1].toDouble();
    final b = rgba[idx + 2].toDouble();
    return (0.299 * r) + (0.587 * g) + (0.114 * b);
  }

  for (int y = 1; y < height - 1; y += stride) {
    for (int x = 1; x < width - 1; x += stride) {
      final center = brightnessAt(x, y);
      count++;
      final delta = center - mean;
      mean += delta / count;
      m2 += delta * (center - mean);

      final edge =
          ((brightnessAt(x - 1, y) - brightnessAt(x + 1, y)).abs() +
              (brightnessAt(x, y - 1) - brightnessAt(x, y + 1)).abs()) /
          510.0;
      edgeSum += edge;
      edgeCount++;
    }
  }

  final stdev = count > 1
      ? sqrt((m2 / (count - 1)).clamp(0.0, double.infinity))
      : 0.0;
  final avgEdge = edgeCount == 0 ? 0.0 : edgeSum / edgeCount;
  final brightnessScore = ((mean - 72.0) / 120.0).clamp(0.0, 1.0);
  final contrastScore = (stdev / 64.0).clamp(0.0, 1.0);
  final sharpnessScore = (avgEdge / 0.22).clamp(0.0, 1.0);

  final confidence =
      ((brightnessScore * 0.48) +
              (contrastScore * 0.22) +
              (sharpnessScore * 0.30))
          .clamp(0.35, 0.97);

  if (confidence < 0.56) {
    return PhotoQualityAssessment(
      poorLighting: true,
      confidence: confidence,
      message: 'Bad lighting - try again in better conditions',
    );
  }

  if (confidence < 0.7) {
    return PhotoQualityAssessment(
      poorLighting: false,
      confidence: confidence,
      message:
          'Photo quality is moderate - better lighting can improve accuracy.',
    );
  }

  return PhotoQualityAssessment(
    poorLighting: false,
    confidence: confidence,
    message: null,
  );
}

// ====================== FULL ANALYSIS FUNCTIONS ======================
Future<DarkSpotAnalysisResult> analyzeDarkSpots({
  String? imagePath,
  required SkinMetrics metrics,
}) async {
  if (imagePath == null || kIsWeb) {
    return _darkSpotFallbackFromMetrics(metrics);
  }

  try {
    final Uint8List bytes = await File(imagePath).readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 180,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;

    final int width = image.width;
    final int height = image.height;
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null || width == 0 || height == 0) {
      return _darkSpotFallbackFromMetrics(metrics);
    }

    final Uint8List rgba = byteData.buffer.asUint8List();
    final int totalPixels = width * height;

    double brightnessSum = 0;
    for (int i = 0; i < rgba.length; i += 4) {
      final r = rgba[i].toDouble();
      final g = rgba[i + 1].toDouble();
      final b = rgba[i + 2].toDouble();
      brightnessSum += (0.299 * r) + (0.587 * g) + (0.114 * b);
    }

    final meanBrightness = brightnessSum / totalPixels;

    double varianceSum = 0;
    for (int i = 0; i < rgba.length; i += 4) {
      final r = rgba[i].toDouble();
      final g = rgba[i + 1].toDouble();
      final b = rgba[i + 2].toDouble();
      final brightness = (0.299 * r) + (0.587 * g) + (0.114 * b);
      final diff = brightness - meanBrightness;
      varianceSum += diff * diff;
    }
    final variance = varianceSum / totalPixels;

    const int stride = 2;
    final candidates = <MapEntry<double, Offset>>[];
    double signalSum = 0;
    int signalCount = 0;
    int localMinimaCount = 0;
    double localMinimaDarknessSum = 0;
    int darkAreaCount = 0;

    for (int y = 0; y < height; y += stride) {
      for (int x = 0; x < width; x += stride) {
        final idx = (y * width + x) * 4;
        final r = rgba[idx].toDouble();
        final g = rgba[idx + 1].toDouble();
        final b = rgba[idx + 2].toDouble();
        final brightness = (0.299 * r) + (0.587 * g) + (0.114 * b);

        final darkness = ((110.0 - brightness) / 110.0).clamp(0.0, 1.0);
        if (darkness <= 0.13) continue;
        darkAreaCount++;

        final localContrast = (meanBrightness - brightness).abs() / 255.0;
        final pigmentationSignal = (darkness * 0.75) + (localContrast * 0.25);
        signalSum += pigmentationSignal;
        signalCount++;

        final leftX = max(0, x - stride);
        final rightX = min(width - 1, x + stride);
        final upY = max(0, y - stride);
        final downY = min(height - 1, y + stride);

        double neighborMinBrightness = 255;
        for (final ny in [upY, y, downY]) {
          for (final nx in [leftX, x, rightX]) {
            if (nx == x && ny == y) continue;
            final nIdx = (ny * width + nx) * 4;
            final nr = rgba[nIdx].toDouble();
            final ng = rgba[nIdx + 1].toDouble();
            final nb = rgba[nIdx + 2].toDouble();
            final nBrightness = (0.299 * nr) + (0.587 * ng) + (0.114 * nb);
            if (nBrightness < neighborMinBrightness) {
              neighborMinBrightness = nBrightness;
            }
          }
        }

        final isLocalMinimum = brightness <= neighborMinBrightness + 1.0;
        if (isLocalMinimum && darkness > 0.22) {
          localMinimaCount++;
          localMinimaDarknessSum += darkness;
        }

        if (pigmentationSignal > 0.28) {
          candidates.add(
            MapEntry(
              pigmentationSignal,
              Offset(x / max(1, width - 1), y / max(1, height - 1)),
            ),
          );
        }
      }
    }

    final avgSignal = signalCount == 0 ? 0.0 : signalSum / signalCount;
    final avgMinimaDarkness = localMinimaCount == 0
        ? 0.0
        : (localMinimaDarknessSum / localMinimaCount);
    final sampledPixels = max(1.0, (width * height) / (stride * stride));
    final minimaDensity = localMinimaCount / sampledPixels;
    final darkAreaRatio = darkAreaCount / sampledPixels;
    final darknessComponent = (avgSignal * 100.0).clamp(0.0, 1.0);
    final minimaComponent = ((avgMinimaDarkness * 0.7) + (minimaDensity * 22.0))
        .clamp(0.0, 1.0);
    final areaComponent = (darkAreaRatio * 120.0).clamp(0.0, 1.0);
    final textureVarianceComponent = ((sqrt(variance) / 255.0) * 0.35).clamp(
      0.0,
      1.0,
    );

    final score =
        ((darknessComponent * 0.44) +
            (minimaComponent * 0.34) +
            (areaComponent * 0.17) +
            (textureVarianceComponent * 0.05)) *
        100.0;

    candidates.sort((a, b) => b.key.compareTo(a.key));
    final hotSpots = candidates.take(20).map((entry) => entry.value).toList();
    final fadePercent = ((58.0 - score).round()).clamp(6, 38);

    return DarkSpotAnalysisResult(
      score: score,
      fadePercent: fadePercent,
      hotSpots: hotSpots,
    );
  } catch (_) {
    return _darkSpotFallbackFromMetrics(metrics);
  }
}

Future<AcneScarAnalysisResult> analyzeAcneScars({
  String? imagePath,
  required SkinMetrics metrics,
}) async {
  if (imagePath == null || kIsWeb) {
    return _acneScarFallbackFromMetrics(metrics);
  }

  try {
    final Uint8List bytes = await File(imagePath).readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 180,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;

    final int width = image.width;
    final int height = image.height;
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null || width == 0 || height == 0) {
      return _acneScarFallbackFromMetrics(metrics);
    }

    final Uint8List rgba = byteData.buffer.asUint8List();
    const int stride = 2;
    final roughnessCandidates = <MapEntry<double, Offset>>[];

    double roughnessSum = 0;
    int roughnessCount = 0;
    double darkMarkSum = 0;
    int darkMarkCount = 0;

    for (int y = 1; y < height - 1; y += stride) {
      for (int x = 1; x < width - 1; x += stride) {
        final idx = (y * width + x) * 4;
        final r = rgba[idx].toDouble();
        final g = rgba[idx + 1].toDouble();
        final b = rgba[idx + 2].toDouble();
        final brightness = (0.299 * r) + (0.587 * g) + (0.114 * b);

        final leftIdx = (y * width + (x - 1)) * 4;
        final rightIdx = (y * width + (x + 1)) * 4;
        final upIdx = ((y - 1) * width + x) * 4;
        final downIdx = ((y + 1) * width + x) * 4;

        double neighborBrightness(int index) {
          final nr = rgba[index].toDouble();
          final ng = rgba[index + 1].toDouble();
          final nb = rgba[index + 2].toDouble();
          return (0.299 * nr) + (0.587 * ng) + (0.114 * nb);
        }

        final leftB = neighborBrightness(leftIdx);
        final rightB = neighborBrightness(rightIdx);
        final upB = neighborBrightness(upIdx);
        final downB = neighborBrightness(downIdx);

        final gradient = ((leftB - rightB).abs() + (upB - downB).abs()) / 510.0;
        final laplacian =
            ((leftB + rightB + upB + downB) - (4 * brightness)).abs() / 255.0;

        final roughnessSignal = (gradient * 0.58) + (laplacian * 0.42);
        if (roughnessSignal > 0.08) {
          roughnessSum += roughnessSignal;
          roughnessCount++;
        }

        final darkness = ((125.0 - brightness) / 125.0).clamp(0.0, 1.0);
        if (darkness > 0.14) {
          darkMarkSum += darkness;
          darkMarkCount++;
        }

        final combined = (roughnessSignal * 0.74) + (darkness * 0.26);
        if (combined > 0.19) {
          roughnessCandidates.add(
            MapEntry(
              combined,
              Offset(x / max(1, width - 1), y / max(1, height - 1)),
            ),
          );
        }
      }
    }

    final avgRoughness = roughnessCount == 0
        ? 0.0
        : roughnessSum / roughnessCount;
    final avgDarkMarks = darkMarkCount == 0 ? 0.0 : darkMarkSum / darkMarkCount;
    final scarDensity =
        roughnessCandidates.length /
        max(1.0, (width * height) / (stride * stride));

    final score =
        ((avgRoughness * 58.0) + (avgDarkMarks * 28.0) + (scarDensity * 1200))
            .clamp(0.0, 100.0);
    final fadePercent = ((54.0 - score).round()).clamp(6, 34);

    roughnessCandidates.sort((a, b) => b.key.compareTo(a.key));
    final improvingSpots = roughnessCandidates
        .take(18)
        .map((e) => e.value)
        .toList();

    return AcneScarAnalysisResult(
      score: score,
      fadePercent: fadePercent,
      improvingSpots: improvingSpots,
    );
  } catch (_) {
    return _acneScarFallbackFromMetrics(metrics);
  }
}

Future<HydrationAnalysisResult> analyzeHydration({
  String? imagePath,
  required SkinMetrics metrics,
}) async {
  if (imagePath == null || kIsWeb) {
    return _hydrationFallbackFromMetrics(metrics);
  }

  try {
    final Uint8List bytes = await File(imagePath).readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 180,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;

    final int width = image.width;
    final int height = image.height;
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null || width == 0 || height == 0) {
      return _hydrationFallbackFromMetrics(metrics);
    }

    final Uint8List rgba = byteData.buffer.asUint8List();
    const int stride = 2;

    double reflectanceSum = 0;
    int reflectanceCount = 0;
    double smoothnessSum = 0;
    int smoothnessCount = 0;
    double fineLineSignalSum = 0;
    int fineLineCount = 0;
    double inflammationSignalSum = 0;
    int inflammationCount = 0;

    double brightnessAt(int x, int y) {
      final idx = (y * width + x) * 4;
      final r = rgba[idx].toDouble();
      final g = rgba[idx + 1].toDouble();
      final b = rgba[idx + 2].toDouble();
      return (0.299 * r) + (0.587 * g) + (0.114 * b);
    }

    for (int y = 1; y < height - 1; y += stride) {
      for (int x = 1; x < width - 1; x += stride) {
        final idx = (y * width + x) * 4;
        final r = rgba[idx].toDouble();
        final g = rgba[idx + 1].toDouble();
        final b = rgba[idx + 2].toDouble();
        final center = (0.299 * r) + (0.587 * g) + (0.114 * b);
        final left = brightnessAt(x - 1, y);
        final right = brightnessAt(x + 1, y);
        final up = brightnessAt(x, y - 1);
        final down = brightnessAt(x, y + 1);

        final localGradient =
            ((left - right).abs() + (up - down).abs()) / 510.0;
        final localVariance =
            (((left - center).abs() +
                    (right - center).abs() +
                    (up - center).abs() +
                    (down - center).abs()) /
                4.0) /
            255.0;

        final smoothness =
            (1.0 - ((localGradient * 0.62) + (localVariance * 0.38))).clamp(
              0.0,
              1.0,
            );
        smoothnessSum += smoothness;
        smoothnessCount++;

        final reflectance = ((center - 85.0) / 125.0).clamp(0.0, 1.0);
        reflectanceSum += reflectance;
        reflectanceCount++;

        final fineLineVisibility =
            ((localGradient * 0.72) + (localVariance * 0.28)).clamp(0.0, 1.0);
        fineLineSignalSum += fineLineVisibility;
        fineLineCount++;

        final rednessBias = ((r - ((g + b) / 2.0)) / 255.0).clamp(0.0, 1.0);
        inflammationSignalSum += rednessBias;
        inflammationCount++;
      }
    }

    final avgSmoothness = smoothnessCount == 0
        ? 0.0
        : smoothnessSum / smoothnessCount;
    final avgReflectance = reflectanceCount == 0
        ? 0.0
        : reflectanceSum / reflectanceCount;
    final avgFineLines = fineLineCount == 0
        ? 0.0
        : fineLineSignalSum / fineLineCount;
    final avgInflammation = inflammationCount == 0
        ? 0.0
        : inflammationSignalSum / inflammationCount;
    final suppressedFineLines = (1.0 - avgFineLines).clamp(0.0, 1.0);
    final rednessSuppression =
        (1.0 - ((metrics.redness / 10.0) * 0.65 + (avgInflammation * 0.35)))
            .clamp(0.0, 1.0);

    final score =
        ((avgSmoothness * 36.0) +
                (avgReflectance * 28.0) +
                (suppressedFineLines * 21.0) +
                (rednessSuppression * 15.0))
            .clamp(0.0, 100.0);
    final improvedPercent = ((score - 55.0).round()).clamp(8, 30);

    return HydrationAnalysisResult(
      score: score,
      improvedPercent: improvedPercent,
    );
  } catch (_) {
    return _hydrationFallbackFromMetrics(metrics);
  }
}

Future<PoreSizeAnalysisResult> analyzePoreSize({
  String? imagePath,
  required SkinMetrics metrics,
}) async {
  if (imagePath == null || kIsWeb) {
    return _poreSizeFallbackFromMetrics(metrics);
  }

  try {
    final Uint8List bytes = await File(imagePath).readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 180,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;

    final int width = image.width;
    final int height = image.height;
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null || width == 0 || height == 0) {
      return _poreSizeFallbackFromMetrics(metrics);
    }

    final Uint8List rgba = byteData.buffer.asUint8List();
    const int stride = 2;

    double poreVisibilitySum = 0;
    int poreCount = 0;
    double sizeSignalSum = 0;
    final candidates = <MapEntry<double, Offset>>[];

    double brightnessAt(int x, int y) {
      final idx = (y * width + x) * 4;
      final r = rgba[idx].toDouble();
      final g = rgba[idx + 1].toDouble();
      final b = rgba[idx + 2].toDouble();
      return (0.299 * r) + (0.587 * g) + (0.114 * b);
    }

    for (int y = 1; y < height - 1; y += stride) {
      for (int x = 1; x < width - 1; x += stride) {
        final center = brightnessAt(x, y);
        final left = brightnessAt(x - 1, y);
        final right = brightnessAt(x + 1, y);
        final up = brightnessAt(x, y - 1);
        final down = brightnessAt(x, y + 1);

        final localMean = (left + right + up + down) / 4.0;
        final localMin = min(min(left, right), min(up, down));
        final isLocalMinimum = center <= localMin + 1.5;
        if (!isLocalMinimum) continue;

        final visibility = ((localMean - center) / 255.0).clamp(0.0, 1.0);
        if (visibility < 0.08) continue;

        final surroundingVariance =
            (((left - localMean).abs() +
                    (right - localMean).abs() +
                    (up - localMean).abs() +
                    (down - localMean).abs()) /
                4.0) /
            255.0;
        final sizeSignal = (visibility * 0.65 + surroundingVariance * 0.35)
            .clamp(0.0, 1.0);

        poreVisibilitySum += visibility;
        sizeSignalSum += sizeSignal;
        poreCount++;

        final candidateScore = (visibility * 0.7 + sizeSignal * 0.3);
        if (candidateScore > 0.16) {
          candidates.add(
            MapEntry(
              candidateScore,
              Offset(x / max(1, width - 1), y / max(1, height - 1)),
            ),
          );
        }
      }
    }

    final sampleCount = max(1, (width * height) ~/ (stride * stride));
    final poreDensity = poreCount / sampleCount;
    final avgVisibility = poreCount == 0 ? 0.0 : poreVisibilitySum / poreCount;
    final avgSizeSignal = poreCount == 0 ? 0.0 : sizeSignalSum / poreCount;

    final score =
        ((poreDensity * 2400) + (avgSizeSignal * 46.0) + (avgVisibility * 34.0))
            .clamp(0.0, 100.0);
    final reductionPercent = ((62.0 - score).round()).clamp(8, 34);

    candidates.sort((a, b) => b.key.compareTo(a.key));
    final tightenedAreas = candidates.take(16).map((e) => e.value).toList();

    return PoreSizeAnalysisResult(
      score: score,
      reductionPercent: reductionPercent,
      tightenedAreas: tightenedAreas,
    );
  } catch (_) {
    return _poreSizeFallbackFromMetrics(metrics);
  }
}

Future<HyperpigmentationAnalysisResult> analyzeHyperpigmentation({
  String? imagePath,
  required SkinMetrics metrics,
}) async {
  if (imagePath == null || kIsWeb) {
    return _hyperpigmentationFallbackFromMetrics(metrics);
  }

  try {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 180);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null || width == 0 || height == 0) {
      return _hyperpigmentationFallbackFromMetrics(metrics);
    }

    final rgba = byteData.buffer.asUint8List();
    const stride = 2;

    int sampleCount = 0;
    double mean = 0;
    double m2 = 0;
    int darkCount = 0;
    final quadrants = [0, 0, 0, 0];
    final candidates = <MapEntry<double, Offset>>[];

    for (int y = 0; y < height; y += stride) {
      for (int x = 0; x < width; x += stride) {
        final idx = (y * width + x) * 4;
        final r = rgba[idx].toDouble();
        final g = rgba[idx + 1].toDouble();
        final b = rgba[idx + 2].toDouble();
        final brightness = (0.299 * r) + (0.587 * g) + (0.114 * b);

        sampleCount++;
        final delta = brightness - mean;
        mean += delta / sampleCount;
        m2 += delta * (brightness - mean);

        final maxChannel = max(r, max(g, b));
        final minChannel = min(r, min(g, b));
        final chromaSpread = (maxChannel - minChannel) / 255.0;

        if (brightness < 102) {
          darkCount++;
          final isRight = x >= width ~/ 2;
          final isBottom = y >= height ~/ 2;
          final quadrantIndex = (isBottom ? 2 : 0) + (isRight ? 1 : 0);
          quadrants[quadrantIndex]++;
        }

        final smoothBlend = (0.34 - chromaSpread).clamp(0.0, 0.34) / 0.34;
        final darknessSignal = ((118 - brightness) / 118).clamp(0.0, 1.0);
        final candidateScore = (darknessSignal * 0.65 + smoothBlend * 0.35);
        if (candidateScore > 0.38 && brightness < 126) {
          candidates.add(
            MapEntry(
              candidateScore,
              Offset(x / max(1, width - 1), y / max(1, height - 1)),
            ),
          );
        }
      }
    }

    final variance = sampleCount > 1 ? m2 / (sampleCount - 1) : 0.0;
    final toneVariance = (sqrt(max(0.0, variance)) / 255.0).clamp(0.0, 1.0);
    final darkRatio = sampleCount == 0 ? 0.0 : darkCount / sampleCount;
    final maxQuadrant = quadrants.reduce(max).toDouble();
    final minQuadrant = quadrants.reduce(min).toDouble();
    final distributionSkew = maxQuadrant <= 0
        ? 0.0
        : ((maxQuadrant - minQuadrant) / maxQuadrant).clamp(0.0, 1.0);

    final score =
        ((toneVariance * 120) + (darkRatio * 190) + (distributionSkew * 38))
            .clamp(0.0, 100.0);
    final reductionPercent = ((61.0 - score).round()).clamp(9, 34);

    candidates.sort((a, b) => b.key.compareTo(a.key));
    final improvedAreas = candidates.take(12).map((e) => e.value).toList();

    return HyperpigmentationAnalysisResult(
      score: score,
      reductionPercent: reductionPercent,
      improvedAreas: improvedAreas,
    );
  } catch (_) {
    return _hyperpigmentationFallbackFromMetrics(metrics);
  }
}

Future<ElasticityAnalysisResult> analyzeElasticity({
  String? imagePath,
  required SkinMetrics metrics,
}) async {
  if (imagePath == null || kIsWeb) {
    return _elasticityFallbackFromMetrics(metrics);
  }

  try {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 180);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null || width == 0 || height == 0) {
      return _elasticityFallbackFromMetrics(metrics);
    }

    final rgba = byteData.buffer.asUint8List();
    const stride = 2;

    double textureVarianceSum = 0;
    int textureCount = 0;
    double wrinkleDepthSum = 0;
    int wrinkleCount = 0;
    double fineLineVisibilitySum = 0;
    int fineLineCount = 0;
    final firmCandidates = <MapEntry<double, Offset>>[];

    double brightnessAt(int x, int y) {
      final idx = (y * width + x) * 4;
      final r = rgba[idx].toDouble();
      final g = rgba[idx + 1].toDouble();
      final b = rgba[idx + 2].toDouble();
      return (0.299 * r) + (0.587 * g) + (0.114 * b);
    }

    for (int y = 1; y < height - 1; y += stride) {
      for (int x = 1; x < width - 1; x += stride) {
        final center = brightnessAt(x, y);
        final left = brightnessAt(x - 1, y);
        final right = brightnessAt(x + 1, y);
        final up = brightnessAt(x, y - 1);
        final down = brightnessAt(x, y + 1);

        final horizontalVar = (left - right).abs() / 255.0;
        final verticalVar = (up - down).abs() / 255.0;
        final edgeSignal = ((horizontalVar + verticalVar) * 0.5).clamp(
          0.0,
          1.0,
        );
        final localVariance =
            (((left - center).abs() +
                    (right - center).abs() +
                    (up - center).abs() +
                    (down - center).abs()) /
                4.0) /
            255.0;
        final textureSignal = ((localVariance * 0.58) + (edgeSignal * 0.42))
            .clamp(0.0, 1.0);

        final localMean = (left + right + up + down) / 4.0;
        final wrinkleDepth = ((localMean - center) / 255.0).clamp(0.0, 1.0);
        final fineLineSignal =
            (max(horizontalVar, verticalVar) * (wrinkleDepth + 0.35)).clamp(
              0.0,
              1.0,
            );

        textureVarianceSum += textureSignal;
        textureCount++;
        wrinkleDepthSum += wrinkleDepth;
        wrinkleCount++;
        fineLineVisibilitySum += fineLineSignal;
        fineLineCount++;

        final firmScore =
            (1.0 -
                    (textureSignal * 0.55 +
                        wrinkleDepth * 0.30 +
                        fineLineSignal * 0.15))
                .clamp(0.0, 1.0);
        if (firmScore > 0.63 && center > 70 && center < 210) {
          firmCandidates.add(
            MapEntry(
              firmScore,
              Offset(x / max(1, width - 1), y / max(1, height - 1)),
            ),
          );
        }
      }
    }

    final textureVariance = textureCount == 0
        ? 0.0
        : textureVarianceSum / textureCount;
    final wrinkleDepth = wrinkleCount == 0
        ? 0.0
        : wrinkleDepthSum / wrinkleCount;
    final fineLineVisibility = fineLineCount == 0
        ? 0.0
        : fineLineVisibilitySum / fineLineCount;

    final firmnessPenalty =
        (textureVariance * 0.42) +
        (wrinkleDepth * 0.36) +
        (fineLineVisibility * 0.22);
    final score =
        (100.0 -
                (firmnessPenalty * 84.0) -
                (metrics.wrinkle * 1.9) -
                (metrics.texture * 1.3))
            .clamp(0.0, 100.0);
    final improvedPoints = ((score - 63).round()).clamp(2, 16);

    firmCandidates.sort((a, b) => b.key.compareTo(a.key));
    final firmAreas = firmCandidates.take(12).map((e) => e.value).toList();

    return ElasticityAnalysisResult(
      score: score,
      improvedPoints: improvedPoints,
      firmAreas: firmAreas,
    );
  } catch (_) {
    return _elasticityFallbackFromMetrics(metrics);
  }
}

Future<OilinessAnalysisResult> analyzeOiliness({
  String? imagePath,
  required SkinMetrics metrics,
}) async {
  if (imagePath == null || kIsWeb) {
    return _oilinessFallbackFromMetrics(metrics);
  }

  try {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 180);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null || width == 0 || height == 0) {
      return _oilinessFallbackFromMetrics(metrics);
    }

    final rgba = byteData.buffer.asUint8List();
    const stride = 2;

    double tZoneReflectanceSum = 0;
    int tZoneCount = 0;
    int specularCount = 0;
    final mattifiedCandidates = <MapEntry<double, Offset>>[];

    for (int y = 0; y < height; y += stride) {
      for (int x = 0; x < width; x += stride) {
        final nx = x / max(1, width - 1);
        final ny = y / max(1, height - 1);
        final inTZone = nx >= 0.28 && nx <= 0.72 && ny >= 0.14 && ny <= 0.64;
        if (!inTZone) continue;

        final idx = (y * width + x) * 4;
        final r = rgba[idx].toDouble();
        final g = rgba[idx + 1].toDouble();
        final b = rgba[idx + 2].toDouble();
        final brightness = (0.299 * r) + (0.587 * g) + (0.114 * b);
        final reflectance = (brightness / 255.0).clamp(0.0, 1.0);

        final maxChannel = max(r, max(g, b));
        final minChannel = min(r, min(g, b));
        final chromaSpread = (maxChannel - minChannel) / 255.0;

        tZoneReflectanceSum += reflectance;
        tZoneCount++;

        final specular = brightness > 198 && chromaSpread < 0.12;
        if (specular) specularCount++;

        final mattifiedScore =
            ((0.78 - reflectance).clamp(0.0, 0.78) / 0.78) *
            (1.0 - chromaSpread * 0.5);
        if (mattifiedScore > 0.38) {
          mattifiedCandidates.add(MapEntry(mattifiedScore, Offset(nx, ny)));
        }
      }
    }

    final avgReflectance = tZoneCount == 0
        ? 0.0
        : tZoneReflectanceSum / tZoneCount;
    final specularDensity = tZoneCount == 0 ? 0.0 : specularCount / tZoneCount;

    final score =
        ((avgReflectance * 72.0) +
                (specularDensity * 58.0) +
                (metrics.pore * 1.2))
            .clamp(0.0, 100.0);
    final reductionPercent = ((58.0 - score).round()).clamp(8, 32);

    mattifiedCandidates.sort((a, b) => b.key.compareTo(a.key));
    final mattifiedAreas = mattifiedCandidates
        .take(12)
        .map((e) => e.value)
        .toList();

    return OilinessAnalysisResult(
      score: score,
      reductionPercent: reductionPercent,
      mattifiedAreas: mattifiedAreas,
    );
  } catch (_) {
    return _oilinessFallbackFromMetrics(metrics);
  }
}

// ====================== OVERLAY PAINTERS ======================
class DarkSpotOverlayPainter extends CustomPainter {
  final List<Offset> hotSpots;
  final double confidence;

  DarkSpotOverlayPainter(this.hotSpots, {this.confidence = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    if (hotSpots.isEmpty) return;
    final confidenceAlpha = confidence.clamp(0.35, 1.0);

    for (var i = 0; i < hotSpots.length; i++) {
      final center = Offset(
        hotSpots[i].dx.clamp(0.0, 1.0) * size.width,
        hotSpots[i].dy.clamp(0.0, 1.0) * size.height,
      );
      final radius = 7.0 + ((i % 4) * 2.3);
      final opacity = ((0.24 - (i * 0.007)).clamp(0.07, 0.24) * confidenceAlpha)
          .clamp(0.05, 0.28);

      final fill = Paint()
        ..color = Colors.redAccent.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      final ring = Paint()
        ..color = Colors.red.withValues(alpha: (opacity * 1.4).clamp(0.1, 0.35))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius + 1.6, ring);
    }
  }

  @override
  bool shouldRepaint(covariant DarkSpotOverlayPainter oldDelegate) {
    return oldDelegate.hotSpots != hotSpots ||
        oldDelegate.confidence != confidence;
  }
}

class AcneScarOverlayPainter extends CustomPainter {
  final List<Offset> improvingSpots;
  final int fadePercent;
  final double confidence;

  AcneScarOverlayPainter({
    required this.improvingSpots,
    required this.fadePercent,
    this.confidence = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (improvingSpots.isEmpty) return;

    final blend = (fadePercent / 35).clamp(0.0, 1.0);
    final confidenceAlpha = confidence.clamp(0.35, 1.0);
    for (var i = 0; i < improvingSpots.length; i++) {
      final center = Offset(
        improvingSpots[i].dx.clamp(0.0, 1.0) * size.width,
        improvingSpots[i].dy.clamp(0.0, 1.0) * size.height,
      );

      final radius = 6.5 + ((i % 4) * 2.0);
      final baseOpacity =
          ((0.20 - (i * 0.006)).clamp(0.06, 0.20) * confidenceAlpha).clamp(
            0.05,
            0.24,
          );
      final fillColor = Color.lerp(
        const Color(0xFF2D8BFF),
        const Color(0xFF21D07A),
        blend,
      )!;
      final ringColor = Color.lerp(
        const Color(0xFF66B2FF),
        const Color(0xFF67F2A7),
        blend,
      )!;

      final fill = Paint()
        ..color = fillColor.withValues(alpha: baseOpacity)
        ..style = PaintingStyle.fill;
      final ring = Paint()
        ..color = ringColor.withValues(
          alpha: (baseOpacity * 1.6).clamp(0.10, 0.34),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius + 1.6, ring);
    }
  }

  @override
  bool shouldRepaint(covariant AcneScarOverlayPainter oldDelegate) {
    return oldDelegate.improvingSpots != improvingSpots ||
        oldDelegate.fadePercent != fadePercent ||
        oldDelegate.confidence != confidence;
  }
}

// ====================== REUSABLE WIDGETS ======================
Widget buildAgeCard(int lowAge, int highAge, Color textColor) {
  return Card(
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MyApp.goldShimmer.withValues(alpha: 0.5),
                  MyApp.surface,
                  MyApp.goldShimmer.withValues(alpha: 0.5),
                ],
                stops: const [0.0, 0.5, 1.0],
                begin: const Alignment(-1, 0),
                end: const Alignment(1, 0),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Estimated $lowAge-$highAge years',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Skin Age (premium)',
            style: TextStyle(color: textColor.withValues(alpha: 0.7)),
          ),
        ],
      ),
    ),
  );
}

String _homeScanDateLabel(DateTime dt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${dt.day} ${months[(dt.month - 1).clamp(0, 11)]} ${dt.year}';
}

// ====================== POLISHED HOME SCREEN ======================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ScanHistoryEntry> recentScans = [];
  bool isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadRecentScans();
  }

  Future<void> _loadRecentScans() async {
    // TODO: connect to your real data loading from AppPrefs
  }

  @override
  Widget build(BuildContext context) {
    final latest = recentScans.isNotEmpty ? recentScans.first : null;
    final metrics = latest?.toSkinMetrics();
    final skinAge = metrics != null
        ? estimateVisualSkinAge(metrics).round()
        : 32;
    final textColor = MyApp.textBrown;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F5),
      appBar: AppBar(
        title: const Text(
          'AestheticSkinTracker',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: const Color(0xFFF8F6F0),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/logo/logo.png',
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.spa_rounded,
                        color: Color(0xFFD4AF37),
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Welcome back,', style: TextStyle(fontSize: 14)),
                    Text(
                      'Your progress',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 30),

            Row(
              children: [
                _buildStatCard(
                  'Scans',
                  recentScans.length.toString(),
                  Icons.camera_alt,
                ),
                const SizedBox(width: 12),
                _buildStatCard('Est. Skin Age', '$skinAge', Icons.face),
              ],
            ),
            const SizedBox(height: 32),

            Text(
              recentScans.isNotEmpty
                  ? 'Scan #${recentScans.length} · ${_homeScanDateLabel(recentScans.first.timestamp)}'
                  : 'Your Latest Scan Results',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            if (recentScans.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 2),
                child: Text(
                  'Your most recent progress scan',
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor.withValues(alpha: 0.55),
                  ),
                ),
              ),
            const SizedBox(height: 12),

            if (latest == null)
              _buildNoScansCard()
            else if (!isPremium)
              _buildFreeMetricsCard(metrics!, skinAge, textColor)
            else
              _buildPremiumMetricsCard(metrics!, textColor),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyApp.goldShimmer,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.camera_alt),
                label: const Text(
                  'New Progress Scan',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),

            if (!isPremium)
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/paywall'),
                  child: const Text(
                    'Unlock full metrics, trends & AI advice →',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: MyApp.goldShimmer),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoScansCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.camera_alt_outlined, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No scans yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              'Take your first scan to see results',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFreeMetricsCard(
    SkinMetrics metrics,
    int skinAge,
    Color textColor,
  ) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Estimated Skin Age',
              style: TextStyle(
                fontSize: 16,
                color: textColor.withValues(alpha: 0.8),
              ),
            ),
            Text(
              '$skinAge years',
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Upgrade to Premium for full metric breakdown, trends, and AI recommendations',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/paywall'),
              child: const Text('Unlock Premium'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumMetricsCard(SkinMetrics metrics, Color textColor) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Key Metrics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            metricCard('Redness', metrics.redness, textColor),
            metricCard('Texture', metrics.texture, textColor),
            metricCard('Wrinkles', metrics.wrinkle, textColor),
            metricCard('Pores', metrics.pore, textColor),
            metricCard('Dark Spots', metrics.darkSpots, textColor),
            metricCard('Elasticity', metrics.elasticity, textColor),
            const SizedBox(height: 20),
            Container(
              height: 90,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('Trend charts with fl_chart coming next'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget metricCard(String title, double value, Color textColor) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(color: textColor.withValues(alpha: 0.85)),
            ),
            Row(
              children: [
                Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 70,
                  height: 6,
                  decoration: BoxDecoration(
                    color: MyApp.goldShimmer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (value / 10).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: MyApp.goldShimmer,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
