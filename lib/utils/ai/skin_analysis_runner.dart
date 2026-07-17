// SkinAnalysisRunner — single entry point used by the UI.
//
// Orchestrates the on-device hybrid pipeline:
//   Stage 1 — ML Kit Face Mesh: detect face + crop + symmetry signal.
//   Stage 2 — YOLOv8/v11-Nano: lesion detection (papules, pustules,
//             cysts, comedones, dark spots) on the cropped face.
//   Stage 3 — EfficientNet-B0: global skin-quality heads (texture,
//             wrinkles, pores, elasticity, overall).
//   Stage 4 — Legacy ACNE04 classifier: fires only when YOLO did NOT
//             produce a usable acne signal, so the user always gets
//             *some* AI score when any model is bundled.
//   Stage 5 — Rule engine (in the caller): owns whichever metrics
//             the AI didn't.
//
// Every stage is independently fallible — a missing asset, a runtime
// error, or an unsupported platform downgrades that stage to a no-op
// without affecting the others. The augmentation honestly reports
// which engines actually fired so the UI badge can label the result.

import 'dart:typed_data';

import '../acne_rosacea_photo_analysis.dart';
import 'efficientnet_skin_quality.dart';
import 'face_mesh_service.dart';
import 'skin_analysis_model.dart';
import 'skin_detections.dart';
import 'yolo_acne_detector.dart';

/// All AI-derived signals for one analysis pass.
class SkinAnalysisAugmentation {
  /// (Possibly model-overridden) input for `AcneRosaceaPhotoAnalyzer`.
  final PhotoAnalysisInput input;

  /// Model identity card for the *primary* lesion engine (YOLO if it
  /// fired, else ACNE04, else fallback). Surfaced in the badge.
  final ModelInfo modelInfo;

  /// Confidence of the primary engine (0–1) when it fired.
  final double? modelConfidence;

  /// Tracker metric keys that an AI engine owns this pass.
  final Set<String> modelOwnedMetrics;

  /// True when ML Kit Face Mesh successfully cropped the face.
  final bool meshUsed;
  final double? symmetryScore;
  final double? faceCoverage;

  /// True when YOLO loaded and produced at least one detection.
  final bool yoloUsed;
  final List<Detection> detections;

  /// True when EfficientNet loaded and returned scores.
  final bool efficientNetUsed;
  final SkinQualityScores? qualityScores;

  const SkinAnalysisAugmentation({
    required this.input,
    required this.modelInfo,
    required this.modelConfidence,
    required this.modelOwnedMetrics,
    required this.meshUsed,
    required this.symmetryScore,
    required this.faceCoverage,
    required this.yoloUsed,
    required this.detections,
    required this.efficientNetUsed,
    required this.qualityScores,
  });

  bool get aiInferenceUsed => !modelInfo.isFallback;
}

class SkinAnalysisRunner {
  // Cached singletons — each engine loaded once on first use.
  static SkinAnalysisAi? _classifier;
  static bool _classifierAttempted = false;
  static YoloAcneDetector? _yolo;
  static bool _yoloAttempted = false;
  static EfficientNetSkinQuality? _eff;
  static bool _effAttempted = false;
  static final Map<int, SkinAnalysisAugmentation> _deterministicCache =
      <int, SkinAnalysisAugmentation>{};

  /// Legacy entrypoint used elsewhere — returns the ACNE04 classifier
  /// (or null). Kept for backward compatibility.
  static Future<SkinAnalysisAi?> ensureModel() async {
    if (_classifierAttempted) return _classifier;
    _classifierAttempted = true;
    _classifier = await SkinAnalysisAi.tryLoad();
    return _classifier;
  }

  static Future<YoloAcneDetector?> _ensureYolo() async {
    if (_yoloAttempted) return _yolo;
    _yoloAttempted = true;
    _yolo = await loadYoloAcneDetector();
    return _yolo;
  }

  static Future<EfficientNetSkinQuality?> _ensureEfficientNet() async {
    if (_effAttempted) return _eff;
    _effAttempted = true;
    _eff = await loadEfficientNetSkinQuality();
    return _eff;
  }

  /// Run the full hybrid pipeline. Always safe — never throws.
  static Future<SkinAnalysisAugmentation> augment({
    required PhotoAnalysisInput baseInput,
    required Uint8List? imageBytes,
  }) async {
    if (imageBytes == null) return _empty(baseInput);

    final fingerprint = _hashBytes(imageBytes);
    final cached = _deterministicCache[fingerprint];
    if (cached != null) return cached;

    // Stage 1 — Face Mesh crop.
    final mesh = await FaceMeshService.analyze(imageBytes);
    final cropped = mesh.bytes;

    // Stage 2 — YOLO lesion detection.
    List<Detection> detections = const [];
    bool yoloFired = false;
    try {
      final yolo = await _ensureYolo();
      if (yolo != null) {
        final res = await yolo.detect(cropped);
        if (res != null) {
          detections = res;
          yoloFired = true;
        }
      }
    } catch (_) {}

    // Stage 3 — EfficientNet skin quality.
    SkinQualityScores? quality;
    bool effFired = false;
    try {
      final eff = await _ensureEfficientNet();
      if (eff != null) {
        final res = await eff.analyze(cropped);
        if (res != null && !res.isEmpty) {
          quality = res;
          effFired = true;
        }
      }
    } catch (_) {}

    // Stage 4 — derive metrics from YOLO counts; falls through to
    // ACNE04 classifier ONLY if YOLO didn't fire.
    PhotoAnalysisInput input = baseInput;
    final ownedMetrics = <String>{};
    ModelInfo primaryInfo = ModelInfo.fallback;
    double? primaryConf;

    if (yoloFired) {
      final counts = _countByLabel(detections);
      final inflam = (counts['papule'] ?? 0) + (counts['pustule'] ?? 0);
      final cystic = counts['cyst'] ?? 0;
      final comedo = (counts['blackhead'] ?? 0) + (counts['whitehead'] ?? 0);

      input = PhotoAnalysisInput(
        imagePath: baseInput.imagePath,
        capturedAt: baseInput.capturedAt,
        region: baseInput.region,
        inflammatoryAcne: _bandFromCount(inflam, [1, 3, 6, 12, 20]),
        comedonalLoad: _bandFromCount(comedo, [1, 4, 8, 15, 25]),
        cysticActivity: _bandFromCount(cystic, [1, 2, 4, 6, 8]),
        redness: baseInput.redness,
        visibleVessels: baseInput.visibleVessels,
        flushingEpisodes: baseInput.flushingEpisodes,
        sensitivity: baseInput.sensitivity,
        cycleRelatedFlare: baseInput.cycleRelatedFlare,
        adultOnset: baseInput.adultOnset,
      );
      ownedMetrics.addAll(const {
        'acneSeverity',
        'cysticAcneSeverity',
        'hormonalAcneSeverity',
      });
      primaryInfo = const ModelInfo(
        name: 'YOLOv8-Nano Acne Detector',
        dataset:
            'Custom acne-lesion dataset (papule / pustule / cyst / '
            'comedone / dark spot)',
        reportedAccuracy: 'Per-class mAP — see model card',
        backend: 'TFLite (native) · YOLOv8',
      );
      primaryConf = detections.isEmpty
          ? 0.5
          : detections.map((d) => d.score).reduce((a, b) => a + b) /
                detections.length;
    } else {
      // Stage 4b — Legacy ACNE04 classifier as the fallback when YOLO
      // isn't bundled.
      try {
        final classifier = await ensureModel();
        if (classifier != null) {
          final out = await classifier.analyze(cropped);
          if (out != null && out.acneSeverity != null) {
            input = PhotoAnalysisInput(
              imagePath: baseInput.imagePath,
              capturedAt: baseInput.capturedAt,
              region: baseInput.region,
              inflammatoryAcne: out.acneSeverity!,
              comedonalLoad: baseInput.comedonalLoad,
              cysticActivity: baseInput.cysticActivity,
              redness: baseInput.redness,
              visibleVessels: baseInput.visibleVessels,
              flushingEpisodes: baseInput.flushingEpisodes,
              sensitivity: baseInput.sensitivity,
              cycleRelatedFlare: baseInput.cycleRelatedFlare,
              adultOnset: baseInput.adultOnset,
            );
            ownedMetrics.addAll(out.modelMetrics);
            primaryInfo = out.info;
            primaryConf = out.confidence;
          }
        }
      } catch (_) {}
    }

    // Stage 4c — EfficientNet blends in vascular / sensitivity heads.
    if (effFired && quality != null) {
      // dark_spot count from YOLO contributes a small redness/PIH bump
      // (post-inflammatory hyperpigmentation often co-presents with
      // residual erythema).
      final darkSpotCount = yoloFired
          ? detections.where((d) => d.label == 'dark_spot').length
          : 0;
      final inflamCount = yoloFired
          ? detections
                .where((d) => d.label == 'papule' || d.label == 'pustule')
                .length
          : 0;
      final redness = _mapRednessFromQuality(
        quality,
        baseInput.redness,
        darkSpotCount: darkSpotCount,
        inflamCount: inflamCount,
      );
      final vessels = _mapVesselsFromQuality(quality, baseInput.visibleVessels);
      final flushing = _mapFlushingFromQuality(
        quality,
        baseInput.flushingEpisodes,
        inflamCount: inflamCount,
      );
      final sens = _mapSensitivityFromQuality(quality, baseInput.sensitivity);
      input = PhotoAnalysisInput(
        imagePath: input.imagePath,
        capturedAt: input.capturedAt,
        region: input.region,
        inflammatoryAcne: input.inflammatoryAcne,
        comedonalLoad: input.comedonalLoad,
        cysticActivity: input.cysticActivity,
        redness: redness,
        visibleVessels: vessels,
        flushingEpisodes: flushing,
        sensitivity: sens,
        cycleRelatedFlare: input.cycleRelatedFlare,
        adultOnset: input.adultOnset,
      );
      ownedMetrics.addAll(const {
        'skinSensitivity',
        'rosaceaSeverity',
        'rosaceaFlushing',
        'visibleBloodVessels',
        'postAcneScarring',
      });
      if (yoloFired) {
        primaryInfo = const ModelInfo(
          name: 'YOLOv8-Nano + EfficientNet-B0',
          dataset: 'Lesion detector + skin-quality multi-head',
          reportedAccuracy: 'See per-model cards (acne mAP + B0 head AUC)',
          backend: 'TFLite (native) · hybrid',
        );
      } else if (primaryInfo.isFallback) {
        primaryInfo = const ModelInfo(
          name: 'EfficientNet-B0 Skin Quality',
          dataset: 'Multi-head: texture / wrinkles / pores / elasticity',
          reportedAccuracy: 'See model card',
          backend: 'TFLite (native) · EfficientNet-B0',
        );
        primaryConf ??= quality.overall ?? 0.5;
      }
    }

    final out = SkinAnalysisAugmentation(
      input: input,
      modelInfo: primaryInfo,
      modelConfidence: primaryConf,
      modelOwnedMetrics: ownedMetrics,
      meshUsed: mesh.meshDetected,
      symmetryScore: mesh.symmetryScore,
      faceCoverage: mesh.faceCoverage,
      yoloUsed: yoloFired,
      detections: detections,
      efficientNetUsed: effFired,
      qualityScores: quality,
    );
    _deterministicCache[fingerprint] = out;
    return out;
  }

  /// Recommended confidence to pass to
  /// `AcneRosaceaPhotoAnalyzer.analyze` based on whether inference
  /// succeeded.
  static double resolveConfidence({
    required double featureConfidence,
    required double? modelConfidence,
  }) {
    return modelConfidence != null
        ? (0.55 + modelConfidence * 0.40).clamp(0.0, 1.0)
        : featureConfidence;
  }

  // ── helpers ─────────────────────────────────────────────────────

  static SkinAnalysisAugmentation _empty(PhotoAnalysisInput baseInput) =>
      SkinAnalysisAugmentation(
        input: baseInput,
        modelInfo: ModelInfo.fallback,
        modelConfidence: null,
        modelOwnedMetrics: const {},
        meshUsed: false,
        symmetryScore: null,
        faceCoverage: null,
        yoloUsed: false,
        detections: const [],
        efficientNetUsed: false,
        qualityScores: null,
      );

  static Map<String, int> _countByLabel(List<Detection> dets) {
    final map = <String, int>{
      'papule': 0,
      'pustule': 0,
      'cyst': 0,
      'blackhead': 0,
      'whitehead': 0,
      'dark_spot': 0,
    };
    for (final d in dets) {
      map[d.label] = (map[d.label] ?? 0) + 1;
    }
    return map;
  }

  /// Maps a count to a 0–10 severity band using ascending thresholds.
  /// `bands` is a 5-element list where each entry is the lower bound
  /// for the next severity step (returning 1, 3, 5, 7, 9, then 10).
  static int _bandFromCount(int count, List<int> bands) {
    assert(bands.length == 5);
    if (count <= 0) return 0;
    if (count < bands[0]) return 1;
    if (count < bands[1]) return 3;
    if (count < bands[2]) return 5;
    if (count < bands[3]) return 7;
    if (count < bands[4]) return 9;
    return 10;
  }

  static int _mapRednessFromQuality(
    SkinQualityScores q,
    int baseline, {
    int darkSpotCount = 0,
    int inflamCount = 0,
  }) {
    final p = q.pores;
    if (p == null && darkSpotCount == 0 && inflamCount == 0) return baseline;
    // Conservative mapping: reduce false severe redness from lighting/noise.
    final poreBoost = ((p ?? 0) * 1.6).round();
    final darkBoost = (darkSpotCount * 0.2).round();
    final inflamBoost = (inflamCount * 0.2).round();
    return (baseline + poreBoost + darkBoost + inflamBoost)
        .clamp(0, 10)
        .toInt();
  }

  static int _mapVesselsFromQuality(SkinQualityScores q, int baseline) {
    final p = q.pores;
    final e = q.elasticity;
    if (p == null && e == null) return baseline;
    // Conservative vessel mapping to avoid over-flagging minor noise.
    final boost = ((p ?? 0) * 1.2 + (1 - (e ?? 0.5)) * 1.0).round();
    return (baseline + boost).clamp(0, 10).toInt();
  }

  static int _mapFlushingFromQuality(
    SkinQualityScores q,
    int baseline, {
    int inflamCount = 0,
  }) {
    final o = q.overall;
    final w = q.wrinkles;
    if (o == null && w == null && inflamCount == 0) return baseline;
    final qualityBoost = (((1 - (o ?? 0.5)) * 3) + ((w ?? 0) * 2)).round();
    final inflamBoost = (inflamCount * 0.4).round();
    return (baseline + qualityBoost + inflamBoost).clamp(0, 10).toInt();
  }

  static int _mapSensitivityFromQuality(SkinQualityScores q, int baseline) {
    final w = q.wrinkles ?? 0.0;
    final o = q.overall ?? 0.5;
    final boost = ((w * 4) + ((1 - o) * 4)).round();
    return ((baseline + boost) ~/ 2).clamp(0, 10);
  }

  static int _hashBytes(Uint8List bytes) {
    // FNV-1a 32-bit for stable, deterministic per-image cache key.
    var hash = 0x811C9DC5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
