import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, FileMode, Platform;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:aesthetic_skin_tracker/app_theme.dart';
import 'package:aesthetic_skin_tracker/models/skin_profile.dart';
import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/landmark_assessment.dart';
import 'package:aesthetic_skin_tracker/utils/local_image_bytes.dart';
import 'package:aesthetic_skin_tracker/utils/premium_access.dart';
import 'package:aesthetic_skin_tracker/utils/premium_recovery_service.dart';
import 'package:aesthetic_skin_tracker/services/skin_analysis_service.dart'
    as local_skin_analysis;
import 'package:aesthetic_skin_tracker/utils/web_upload_image_utils.dart';
import 'package:aesthetic_skin_tracker/utils/web_image_picker.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/widgets/adaptive_camera_guide_visuals.dart';
import 'package:aesthetic_skin_tracker/widgets/clinical_camera_guidance.dart';
import 'package:aesthetic_skin_tracker/widgets/clinical_section_header.dart';
import 'package:aesthetic_skin_tracker/widgets/image_crop_dialog.dart';
import 'package:aesthetic_skin_tracker/widgets/local_image_preview.dart';
import 'package:aesthetic_skin_tracker/widgets/makeup_badge.dart';
import 'package:aesthetic_skin_tracker/widgets/makeup_disclosure_dialog.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';

// ─────────────────────────────────────────────────────────────────────────
// Pure tilt/alignment helpers
//
// Extracted out of _CameraScreenState so they're unit-testable without the
// full widget/CameraController lifecycle. Behavior is unchanged from their
// original private-method form — these are the exact same calculations,
// just taking a LandmarkAssessment/values as parameters instead of reading
// instance state.
// ─────────────────────────────────────────────────────────────────────────

/// Resolves the camera guide type for a [CameraScreen] instance.
///
/// The AI Skin Analysis flow (`skin_ai_analysis_screen.dart`'s
/// `_pickFromCamera`) never attaches a [Procedure] to [CameraScreen] --
/// without this override, [_CameraScreenState._guideType] fell through to
/// whatever "active procedure" happened to be stored via
/// `AppPrefs.resolveActiveProcedureId()` (or `general` if none was set),
/// entirely incidental to the fact that this flow always captures a face.
/// That incidental type drove real thresholds (lighting/backlight/scale)
/// and UI (guide shape/overlays/copy) that have nothing to do with
/// whatever unrelated procedure the user last had active.
///
/// Pulled out of the `_guideType` getter as a pure function so this
/// resolution -- and its priority order -- is unit-testable without a
/// camera, widget, or AppPrefs.
ProcedureCameraGuideType resolveCameraGuideType({
  required bool isSkincareScan,
  required CameraCapturePurpose capturePurpose,
  required ProcedureBodyRegion? procedureBodyRegion,
  required String effectiveGuideProcedureType,
}) {
  if (isSkincareScan && capturePurpose == CameraCapturePurpose.aiSkinAnalysis) {
    return ProcedureCameraGuideType.facial;
  }
  if (procedureBodyRegion != null) {
    switch (procedureBodyRegion) {
      case ProcedureBodyRegion.face:
        return ProcedureCameraGuideType.facial;
      case ProcedureBodyRegion.body:
        return ProcedureCameraGuideType.body;
      case ProcedureBodyRegion.general:
        return ProcedureCameraGuideType.general;
    }
  }
  return procedureCameraGuideType(effectiveGuideProcedureType);
}

/// Aggregate head-tilt magnitude in degrees for FACE mode. Uses yaw+pitch+
/// roll when available; falls back to a rotationProxy+eyeTilt synthetic
/// value only when all three are unset (sparse-signal case — this is a
/// face-only fallback and was never intended for body assessments, which
/// never populate yaw/pitch/roll at all).
double? headTiltAngleFromAssessment(LandmarkAssessment a) {
  if (!a.available) return null;
  final yaw = a.yaw?.abs() ?? 0.0;
  final pitch = a.pitch?.abs() ?? 0.0;
  final roll = a.roll?.abs() ?? 0.0;
  if (yaw == 0 && pitch == 0 && roll == 0) {
    // Fallback: use rotation proxy + eye tilt as a synthetic degree value.
    return (a.rotationProxy * 30.0).abs() + ((a.eyeTilt?.abs() ?? 0.0) * 30.0);
  }
  return yaw + pitch + roll;
}

/// Body-mode tilt magnitude in degrees, using the actual shoulder-line
/// angle relative to horizontal ([LandmarkAssessment.shoulderTilt]) — a
/// genuine tilt measurement, unlike rotationProxy (shoulder/hip width
/// ratio), which has no angular meaning and must never drive this value.
double? bodyTiltAngleFromAssessment(LandmarkAssessment a) {
  if (!a.available) return null;
  return a.shoulderTilt?.abs();
}

/// Pure red/yellow/green classification for the Alignment quality signal.
/// [tilt] should come from [headTiltAngleFromAssessment] (face) or
/// [bodyTiltAngleFromAssessment] (body) — pass null when unavailable, which
/// resolves to a 999° sentinel that always classifies as red.
QualityState alignmentQualityStatus({
  required bool isBodyGuide,
  required double? tilt,
  required double centerDelta,
}) {
  final resolvedTilt = tilt ?? 999.0;
  final redThreshold = isBodyGuide ? 15.0 : 40.0;
  final yellowThreshold = isBodyGuide ? 8.0 : 30.0;
  if (centerDelta > 0.35 || resolvedTilt > redThreshold) {
    return QualityState.red;
  }
  if (centerDelta > 0.25 || resolvedTilt > yellowThreshold) {
    return QualityState.yellow;
  }
  return QualityState.green;
}

/// Pure decision of whether the current frame counts as "too dark" for
/// [_lightingFromCameraImage]'s verdict. A face ROI sample
/// ([faceRoiLuma] > 0) is a direct read of the subject's own brightness,
/// so once one exists it alone decides tooDark -- the whole-frame mean/
/// darkRatio (which include the background) are used only when there is
/// no face sample (body mode, or no face detected this frame). Without
/// this, a bright face over a dark background could fail the whole-frame
/// check even though the face itself is well lit.
bool isLightingTooDark({
  required double faceRoiLuma,
  required double wholeFrameMean,
  required double wholeFrameDarkRatio,
  required double darkMeanFloor,
  required double darkRatioCeil,
}) {
  if (faceRoiLuma > 0) {
    return faceRoiLuma < darkMeanFloor;
  }
  return wholeFrameMean < darkMeanFloor || wholeFrameDarkRatio > darkRatioCeil;
}

/// Pure decision of whether the current frame counts as "harsh
/// backlighting" for the LIGHTING chip. Same principle as
/// [isLightingTooDark] (commit 67609bd): once a face ROI sample exists,
/// backlighting is judged by comparing the face against its surroundings
/// -- here, [wholeFrameMean] as the simplest available "surroundings"
/// signal -- not by [wholeFrameEdgeDelta] (the whole-frame quadrant
/// left/right-top/bottom asymmetry) alone, which a well-lit face over a
/// dim or unevenly-lit background can trip even when nothing is actually
/// backlighting the subject. [backlightDeltaCeil] is reused unchanged for
/// both branches -- no new threshold value is introduced.
///
/// The face-relative comparison is deliberately signed, not absolute: real
/// backlighting means the surroundings are brighter than the face
/// ([wholeFrameMean] pulled up past the face's own level), so a face
/// brighter than its surroundings (a bright light on the face over a dim
/// background) must never register as backlit.
bool isBacklit({
  required double faceRoiLuma,
  required double wholeFrameMean,
  required double wholeFrameEdgeDelta,
  required double backlightDeltaCeil,
}) {
  if (faceRoiLuma > 0) {
    return (wholeFrameMean - faceRoiLuma) > backlightDeltaCeil;
  }
  return wholeFrameEdgeDelta > backlightDeltaCeil;
}

/// Pure computation of _estimateFaceRoiLumaFromStream's lighting-sampling
/// ROI rectangle, in RAW CameraImage pixel space -- pulled out purely so
/// the ROI's placement (not the byte-sampling loop, which needs a real
/// CameraImage) is unit-testable on its own.
///
/// [rawCenterXNorm]/[rawCenterYNorm]/[rawFaceWidthNorm]/[rawFaceHeightNorm]
/// must be the RAW (pre-mirror, pre-crop-conversion) face box -- the same
/// box ML Kit returned, normalized against the same raw frame [width]/
/// [height] -- never the visible-preview-space (mirrored/BoxFit.cover-
/// cropped) centerOffsetX/Y or faceFillRatio, which live in a different
/// coordinate space (the visible preview, not the raw stream buffer these
/// pixels are actually sampled from) and would misplace and mis-scale the
/// ROI, especially vertically, since the preview is a BoxFit.cover crop of
/// the taller raw stream.
///
/// Size rule is unchanged from before this fix: fill (now the RAW face
/// box's own area, as a fraction of the full raw frame) is clamped to
/// [0.10, 0.40], then roiW = width*sqrt(fill)*0.90, roiH =
/// height*sqrt(fill)*1.05, each clamped to [24, that dimension].
({int left, int top, int right, int bottom}) faceRoiRectInRawStreamPixels({
  required double rawCenterXNorm,
  required double rawCenterYNorm,
  required double rawFaceWidthNorm,
  required double rawFaceHeightNorm,
  required int width,
  required int height,
}) {
  final centerX = (rawCenterXNorm * width).round();
  final centerY = (rawCenterYNorm * height).round();
  final fill = (rawFaceWidthNorm * rawFaceHeightNorm).clamp(0.10, 0.40);
  final roiW = (width * math.sqrt(fill) * 0.90).round().clamp(24, width);
  final roiH = (height * math.sqrt(fill) * 1.05).round().clamp(24, height);

  final left = (centerX - (roiW ~/ 2)).clamp(0, width - 1);
  final top = (centerY - (roiH ~/ 2)).clamp(0, height - 1);
  final right = (left + roiW).clamp(left + 1, width);
  final bottom = (top + roiH).clamp(top + 1, height);

  return (left: left, top: top, right: right, bottom: bottom);
}

/// Mean luminance for one decoded burst-capture JPEG. Logging-only support
/// for the 3-frame burst in `_captureFromLiveCamera` — see that function's
/// comment for why this exists as a standalone top-level function instead
/// of reusing `_summarizeDecodedImage` (an instance method) or
/// `_summarizeCameraImage` (which needs a live CameraImage's planes/format,
/// not decoded JPEG bytes, and cannot run on captured burst frames at all).
///
/// This is a DENSE, every-pixel mean — deliberately different from
/// `_summarizeDecodedImage`'s `mean` field, which samples a sparse ~36x36
/// grid instead of every pixel. Both apply the same Rec.601 luma weights
/// (0.299/0.587/0.114) to the same gamma-encoded (sRGB-style) JPEG byte
/// values — neither linearizes first — so that part is consistent. Neither
/// function itself applies any additional rotation; whatever EXIF-
/// orientation handling `img.decodeImage` performs by default happens
/// identically upstream of both, so orientation cannot be a source of
/// difference between them specifically — this is not a claim that no
/// rotation happens at all, only that it can't explain a divergence here.
/// Because the two functions visit different pixel sets (every pixel vs.
/// a coarse grid), they will NOT produce the same number on a real photo.
/// Do not average, scale, or reconcile this value against
/// `_summarizeDecodedImage.mean`, and do not use
/// `_summarizeDecodedImage.mean` as a substitute floor for burst-luminance
/// logging — they are two independent measurements. `uneven_lighting`
/// (left-minus-right on the LIVE preview, via `_summarizeCameraImage`) is a
/// third, unrelated measurement, derived from neither function here.
///
/// Returns null if the bytes don't decode.
double? meanLuminanceFromImageBytes(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // decodeImage's format-sniffing can throw (not just return null) on
    // malformed/truncated input — same RangeError case documented on
    // flipForStorageIfMirror above.
    return null;
  }
  if (decoded == null || decoded.width == 0 || decoded.height == 0) {
    return null;
  }
  var total = 0.0;
  var count = 0;
  for (var y = 0; y < decoded.height; y++) {
    for (var x = 0; x < decoded.width; x++) {
      final pixel = decoded.getPixel(x, y);
      total += (0.299 * pixel.r) + (0.587 * pixel.g) + (0.114 * pixel.b);
      count += 1;
    }
  }
  return count == 0 ? null : total / count;
}

/// How a body-procedure photo was captured. Only meaningful for body scans
/// (face/general scans are always a direct front-camera selfie, equivalent
/// to [assisted] in framing terms, and don't set this).
///
/// [mirror] photos are a FRONT-camera capture of the user's reflection in a
/// mirror — the sensor sees a left-right-flipped view of the subject, which
/// must be flipped back before any landmark/symmetry analysis (see
/// [flipForStorageIfMirror]). [assisted] and [timer] are direct camera
/// captures (someone else holding the phone, or the phone propped up) with
/// no mirroring involved.
enum BodyCaptureMode {
  mirror,
  assisted,
  timer;

  String get storageValue => switch (this) {
    BodyCaptureMode.mirror => 'mirror',
    BodyCaptureMode.assisted => 'assisted',
    BodyCaptureMode.timer => 'timer',
  };

  static BodyCaptureMode? fromStorageValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'mirror':
        return BodyCaptureMode.mirror;
      case 'assisted':
        return BodyCaptureMode.assisted;
      case 'timer':
        return BodyCaptureMode.timer;
      default:
        return null;
    }
  }

  String get label => switch (this) {
    BodyCaptureMode.mirror => 'Mirror',
    BodyCaptureMode.assisted => 'Someone else is taking this photo',
    BodyCaptureMode.timer => 'Timer + propped phone',
  };

  String get description => switch (this) {
    BodyCaptureMode.mirror =>
      'Stand in front of a mirror and use the front camera. Recommended for solo capture.',
    BodyCaptureMode.assisted =>
      'A partner, friend, or clinic staff holds the phone and takes the photo directly.',
    BodyCaptureMode.timer =>
      'Prop the phone up, start a countdown, and step into frame.',
  };
}

enum CameraCapturePurpose {
  trackProcedure,
  aiSkinAnalysis,
  skincareTracking,
  challenge,
  generic,
}

bool isTrackProcedureCapturePurpose(CameraCapturePurpose purpose) =>
    purpose == CameraCapturePurpose.trackProcedure;

bool referencePoseLockingEnabled(CameraCapturePurpose purpose) =>
  isTrackProcedureCapturePurpose(purpose);

const double minimumComparableReferenceAlignmentScore = 60.0;

double? bodyReferenceAlignmentScore(
  Map<String, double>? reference,
  Map<String, double>? live,
) {
  if (reference == null || live == null || reference.isEmpty || live.isEmpty) {
    return null;
  }

  double component(String key, double tolerance) {
    final referenceValue = reference[key];
    final liveValue = live[key];
    if (referenceValue == null || liveValue == null) return 0.0;
    final normalizedDelta = (liveValue - referenceValue).abs() / tolerance;
    return (1.0 - normalizedDelta.clamp(0.0, 1.0)).clamp(0.0, 1.0);
  }

  final shoulderWidth = component('shoulderWidthNorm', 0.12);
  final hipWidth = component('hipWidthNorm', 0.12);
  final shoulderToHip = component('shoulderToHipRatio', 0.18);
  final centerDelta =
      ((live['centerOffsetX'] ?? 0.0) -
              (reference['centerOffsetX'] ?? 0.0))
          .abs() +
      ((live['centerOffsetY'] ?? 0.0) -
              (reference['centerOffsetY'] ?? 0.0))
          .abs();
  final centerScore = (1.0 - (centerDelta / 0.20).clamp(0.0, 1.0))
      .clamp(0.0, 1.0);

  return ((shoulderWidth * 0.40) +
          (hipWidth * 0.30) +
          (shoulderToHip * 0.20) +
          (centerScore * 0.10)) *
      100.0;
}

double? faceReferenceAlignmentScore(
  Map<String, double>? reference,
  Map<String, double>? live,
) {
  if (reference == null || live == null || reference.isEmpty || live.isEmpty) {
    return null;
  }

  double component(String key, double tolerance) {
    final referenceValue = reference[key];
    final liveValue = live[key];
    if (referenceValue == null || liveValue == null) return 0.0;
    final normalizedDelta = (liveValue - referenceValue).abs() / tolerance;
    return (1.0 - normalizedDelta.clamp(0.0, 1.0)).clamp(0.0, 1.0);
  }

  final eyeDistance = component('eyeDistanceNorm', 0.06);
  final faceWidth = component('faceWidthNorm', 0.10);
  final faceHeight = component('faceHeightNorm', 0.12);
  final faceAspect = component('faceAspectRatio', 0.18);
  final centerDelta =
      ((live['centerOffsetX'] ?? 0.0) -
              (reference['centerOffsetX'] ?? 0.0))
          .abs() +
      ((live['centerOffsetY'] ?? 0.0) -
              (reference['centerOffsetY'] ?? 0.0))
          .abs();
  final centerScore = (1.0 - (centerDelta / 0.16).clamp(0.0, 1.0))
      .clamp(0.0, 1.0);

  return ((eyeDistance * 0.35) +
          (faceWidth * 0.20) +
          (faceHeight * 0.20) +
          (faceAspect * 0.15) +
          (centerScore * 0.10)) *
      100.0;
}

ScanHistoryEntry? lockedProcedureReference(
  List<ScanHistoryEntry> history,
  String? procedureId,
) {
  final normalizedId = procedureId?.trim();
  if (normalizedId == null || normalizedId.isEmpty) return null;
  final matches = history
      .where((entry) => (entry.procedureId ?? '').trim() == normalizedId)
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (matches.isEmpty) return null;
  return matches.firstWhere(
    (entry) => entry.isBaseline,
    orElse: () => matches.first,
  );
}

/// Horizontally flips [bytes] when [mode] is [BodyCaptureMode.mirror] —
/// mirror captures show a left-right-flipped view of the subject, so this
/// must run BEFORE the bytes are persisted, analyzed for landmarks, or sent
/// to any backend, so every downstream consumer (including a future
/// symmetry analysis) sees the same un-mirrored orientation as an
/// assisted/timer capture. Returns [bytes] unchanged for any other mode, or
/// if decoding fails (caller keeps the original capture rather than losing
/// the photo).
Uint8List flipForStorageIfMirror(Uint8List bytes, BodyCaptureMode? mode) {
  if (mode != BodyCaptureMode.mirror) return bytes;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final flipped = img.flipHorizontal(decoded);
    return Uint8List.fromList(img.encodeJpg(flipped, quality: 92));
  } catch (_) {
    // decodeImage's format-sniffing can throw (not just return null) on
    // malformed/truncated input — e.g. a short buffer that partially
    // matches a format's magic bytes. Confirmed by
    // camera_screen_body_capture_test.dart's "undecodable bytes" case,
    // which threw a RangeError here before this try/catch existed. Either
    // way the contract is the same: keep the original capture rather than
    // losing the photo or crashing the save.
    return bytes;
  }
}

/// Request parameters for the body-silhouette backend call, as decided by
/// the current capture-mode/reference-scan state. Returned as data (not
/// dispatched) so the "what do we send, and where does each field come
/// from" logic is unit-testable without a full CameraScreen/
/// CameraController lifecycle — same rationale as the tilt/alignment
/// helpers above and [flipForStorageIfMirror].
class BodySilhouetteRequestParams {
  final String? captureMode;
  final String? captureQuality;
  final Map<String, dynamic>? baselineResult;
  final String? baselineCaptureMode;
  final String? baselineCaptureQuality;
  final int? currentConsistentScanCount;
  final int? baselineConsistentScanCount;
  final int? sourceImageWidth;
  final int? sourceImageHeight;
  final int? baselineSourceImageWidth;
  final int? baselineSourceImageHeight;

  const BodySilhouetteRequestParams({
    this.captureMode,
    this.captureQuality,
    this.baselineResult,
    this.baselineCaptureMode,
    this.baselineCaptureQuality,
    this.currentConsistentScanCount,
    this.baselineConsistentScanCount,
    this.sourceImageWidth,
    this.sourceImageHeight,
    this.baselineSourceImageWidth,
    this.baselineSourceImageHeight,
  });
}

/// Pure builder for [BodySilhouetteRequestParams]. [baselineRawPayload] is
/// the reference (previous) scan's `ScanHistoryEntry.rawPayload` — the
/// verbatim response saved by a prior call to this same endpoint; only its
/// `result` map (normalized_area_index/scale_reference_pixels/etc.) is
/// forwarded as the new request's baseline, matching what
/// `analyze_body_silhouette_endpoint` in main.py expects under
/// `baselineResult`.
BodySilhouetteRequestParams buildBodySilhouetteRequestParams({
  required BodyCaptureMode? selectedCaptureMode,
  required String? lastCaptureQualityTag,
  required Map<String, dynamic>? baselineRawPayload,
  required String? baselineCaptureMode,
  String? baselineCaptureQuality,
  int priorConsistentScanCount = 0,
  int? sourceImageWidth,
  int? sourceImageHeight,
  int? baselineSourceImageWidth,
  int? baselineSourceImageHeight,
}) {
  final baselineResultRaw = baselineRawPayload?['result'];
  final baselineResult = baselineResultRaw is Map
      ? Map<String, dynamic>.from(baselineResultRaw)
      : null;
  return BodySilhouetteRequestParams(
    captureMode: selectedCaptureMode?.storageValue,
    captureQuality: lastCaptureQualityTag,
    baselineResult: baselineResult,
    baselineCaptureMode: baselineCaptureMode,
    baselineCaptureQuality: baselineCaptureQuality,
    currentConsistentScanCount: priorConsistentScanCount + 1,
    baselineConsistentScanCount: priorConsistentScanCount,
    sourceImageWidth: sourceImageWidth,
    sourceImageHeight: sourceImageHeight,
    baselineSourceImageWidth: baselineSourceImageWidth,
    baselineSourceImageHeight: baselineSourceImageHeight,
  );
}

class CameraScreen extends StatefulWidget {
  final Procedure? procedure;
  final bool isSkincareScan;
  final bool aiMultiFrameCapture;
  final CameraCapturePurpose capturePurpose;
  final String? productName;
  final String? initialProcedureId;
  final String? initialProcedureLabel;
  final Map<String, dynamic>? initialTrackProcedureBaselineRecord;

  const CameraScreen({
    this.procedure,
    this.isSkincareScan = false,
    this.aiMultiFrameCapture = false,
    this.capturePurpose = CameraCapturePurpose.generic,
    this.productName,
    this.initialProcedureId,
    this.initialProcedureLabel,
    this.initialTrackProcedureBaselineRecord,
  }) : assert(
         !aiMultiFrameCapture ||
             capturePurpose == CameraCapturePurpose.aiSkinAnalysis,
       ),
       super(key: null);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class AiSkinAnalysisCaptureResult {
  const AiSkinAnalysisCaptureResult({
    required this.primaryImagePath,
    required this.croppedFrames,
    required this.captureQuality,
  });

  final String primaryImagePath;
  final List<Uint8List> croppedFrames;
  final String captureQuality;
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  bool _capturing = false;

  bool get _isTrackProcedureFlow =>
      referencePoseLockingEnabled(widget.capturePurpose);
  bool _cameraReady = false;
  bool _cameraInitFailed = false;
  bool _lightingStreamActive = false;
  late final AnimationController _shimmerController;
  late final AnimationController _successController;
  late final Animation<double> _successAnim;
  bool _showSuccessBurst = false;
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = const [];
  String? _cameraError;

  String _scanProcedureLabel = '';
  String? _selectedProcedureId;
  String? _scanFocusArea;
  String? _scanCustomDescription;

  static const List<String> _faceGuidanceTips = [
    'Keep your face at the same angle for every scan',
    'Use the same lighting conditions each time',
    'Hold the camera at the same distance from your face',
    'Remove makeup and keep skin clean',
    'Use a plain background for best results',
    'Keep a neutral expression and relax your jaw',
    'Avoid shadows and glare on your face',
  ];

  static const List<String> _bodyGuidanceTips = [
    'Keep the same body area centered in every scan',
    'Stand at the same distance from the camera each time',
    'Use even front lighting without overhead shadows',
    'Wear consistent fitted clothing or expose the same treatment area',
    'Keep posture neutral and avoid twisting your torso',
    'Use a plain background so contour changes are easier to compare',
    'Avoid cropping the hips, waist, or treatment edges',
  ];

  int _currentTipIndex = 0;
  ScanHistoryEntry? _referenceScan;
  String? _referenceImagePath;
  Uint8List? _referenceImageBytes;
  bool _showGhostOverlay = true;
  double _ghostOverlayOpacity = 0.20;
  bool _isGoodReferencePhoto = false;
  double _liveReferenceAlignmentScore = 0.0;
  String _selectedPoseTemplate = 'Front';
  _LightingGuidance _lightingGuidance = const _LightingGuidance.unknown();
  LandmarkAssessment _liveLandmarkAssessment = LandmarkAssessment.unsupported;
  bool _landmarkAssessmentInFlight = false;
  int _landmarkFrameCounter = 0;
  static const int _landmarkSmoothingWindow = 5;
  final List<LandmarkAssessment> _landmarkHistory = <LandmarkAssessment>[];
  int? _lastConsistencyScore;

  // ── Debug-only framing telemetry (kDebugMode) ─────────────────────────
  // Captures the latest UNSMOOTHED, single-frame ML Kit result exactly as
  // it came back from analyzeLiveLandmarks — i.e. before
  // _stabilizeLandmarkAssessment folds it into the 5-sample
  // _landmarkHistory buffer. Purely observational: nothing here is read by
  // any gating/threshold logic, only by _buildDebugFramingOverlay. Left
  // null (and never assigned to) outside kDebugMode, so this costs nothing
  // in release builds.
  bool? _debugRawAvailable;
  double? _debugRawYaw;
  double? _debugRawPitch;
  double? _debugRawRoll;

  // Raw CameraImage/CameraDescription properties for the same frame — added
  // to investigate the iOS "never gets landmarks" report: these let the
  // overlay show exactly what format/rotation is actually arriving at
  // analyzeLiveLandmarks, independent of what CameraController was *asked*
  // to produce (see the ImageFormatGroup passed to CameraController in
  // _initializeController). `_debugRawFormatCode` is `dynamic` because
  // CameraImageFormat.raw itself is `dynamic` (an Android ImageFormat int
  // on Android, a FourCharCode-style int on iOS).
  String? _debugRawFormatGroup;
  Object? _debugRawFormatCode;
  int? _debugRawPlaneCount;
  int? _debugSensorOrientation;

  // Most recent lighting-ROI rectangle _estimateFaceRoiLumaFromStream
  // sampled from, in RAW CameraImage pixel space (the same buffer the Y
  // plane bytes are indexed against) -- purely observational, for
  // _buildDebugFramingOverlay to show alongside the raw/converted face
  // geometry readout. Never read by any gating/threshold logic. Left null
  // outside kDebugMode and whenever no face ROI was sampled this frame.
  int? _debugFaceRoiLeft;
  int? _debugFaceRoiTop;
  int? _debugFaceRoiRight;
  int? _debugFaceRoiBottom;

  // Most recent whole-frame lighting-summary darkRatio (_summarizeCameraImage)
  // and Y/BGRA-plane row-stride info, purely observational for
  // _buildDebugFramingOverlay -- see _lightingFromCameraImage for how
  // darkRatio can independently drive the "Too dark" verdict even when the
  // face-only ROI (_liveFaceRoiLuma) is bright. Left null outside
  // kDebugMode.
  double? _debugLiveDarkRatio;
  int? _debugPlaneBytesPerRow;
  int? _debugPlaneWidthTimesBpp;

  /// Result of the pre-scan makeup disclosure dialog. `null` until the user
  /// answers. Once the user has chosen, the scan flow proceeds and this flag
  /// is propagated onto every [ScanHistoryEntry] saved from this session.
  bool? _makeupPresent;
  bool _disclosureInFlight = false;

  /// Which real-world capture setup produced (or will produce) this scan's
  /// photos. Only prompted for body-region procedures — face/general scans
  /// are always a direct front-camera selfie and leave this null.
  BodyCaptureMode? _selectedBodyCaptureMode;
  bool _captureModePromptInFlight = false;

  /// Countdown (seconds remaining) for the user-initiated timer-capture
  /// flow. Distinct from [_autoCaptureCountdown], which is the
  /// quality-gated auto-capture countdown — this one starts only when the
  /// user taps "Start timer" in [BodyCaptureMode.timer] and fires
  /// regardless of live quality signals, since the whole point is to let
  /// the user step away from the phone.
  int? _timerCaptureCountdown;
  Timer? _timerCaptureTimer;

  String? _postOpDaysForBackend() {
    final procedure = widget.procedure;
    if (procedure == null) return null;
    final days = DateTime.now().difference(procedure.startDate).inDays + 1;
    if (days < 0) return null;
    return days.toString();
  }

  Future<double?> _latestTrackerMetric(String metricKey) async {
    final logs = await AppPrefs.getAcneRosaceaLogsForMetric(metricKey);
    if (logs.isEmpty) return null;
    return logs.first.value.toDouble().clamp(0.0, 10.0);
  }

  double _sensitivityFromProfile(SensitivityLevel level) {
    switch (level) {
      case SensitivityLevel.low:
        return 2.5;
      case SensitivityLevel.moderate:
        return 4.5;
      case SensitivityLevel.high:
        return 7.0;
      case SensitivityLevel.veryHigh:
        return 8.5;
    }
  }

  bool _containsAnyToken(String text, List<String> tokens) {
    final lower = text.toLowerCase();
    for (final token in tokens) {
      if (lower.contains(token)) return true;
    }
    return false;
  }

  Future<Map<String, String>> _buildSafetySignalFields() async {
    const defaultRosacea = 2.5;
    const defaultSensitivity = 4.5;

    final profile = await AppPrefs.getSkinProfileOrNull();
    final recentRosacea = await _latestTrackerMetric('rosaceaSeverity');
    final recentSensitivity = await _latestTrackerMetric('skinSensitivity');

    final concernText = [
      ...?profile?.mainConcerns,
      ...?profile?.goals,
      profile?.notes ?? '',
      _scanCustomDescription ?? '',
      _focusAreaForSave ?? '',
    ].join(' ').toLowerCase();

    final rosaceaConcern = _containsAnyToken(concernText, const [
      'rosacea',
      'flushing',
      'persistent redness',
      'redness',
      'vascular',
    ]);
    final barrierConcern = _containsAnyToken(concernText, const [
      'barrier',
      'compromised',
      'irritation',
      'reactive',
      'stinging',
      'burning',
      'sensitive',
    ]);

    final profileSensitivity = profile == null
        ? null
        : _sensitivityFromProfile(profile.sensitivityLevel);

    final rosacea =
        (recentRosacea ?? (rosaceaConcern ? 6.0 : null) ?? defaultRosacea)
            .clamp(0.0, 10.0);
    final sensitivity =
        (recentSensitivity ?? profileSensitivity ?? defaultSensitivity).clamp(
          0.0,
          10.0,
        );

    final compromisedBarrier =
        barrierConcern ||
        sensitivity >= 7.0 ||
        (profile?.skinType == SkinType.sensitive);

    return {
      'rosacea_score': rosacea.toStringAsFixed(1),
      'sensitivity_score': sensitivity.toStringAsFixed(1),
      'compromised_barrier': compromisedBarrier ? 'true' : 'false',
    };
  }

  // ── Clinical auto-capture state ──────────────────────────────────────────
  /// Timestamp at which all four quality signals became green. Reset whenever
  /// any signal drops out of green.
  DateTime? _qualityGreenSince;

  /// Countdown shown to the user once the green-stable window is met. When
  /// non-null, the capture button renders a progress ring + "Hold still…"
  /// label and an internal [Timer] fires the actual capture.
  int? _autoCaptureCountdown;
  Timer? _autoCaptureTimer;

  /// Set true when [_handleCaptureTap] is in flight to prevent double-fires
  /// from the auto-capture timer and a manual tap simultaneously.
  bool _captureInProgress = false;

  /// The most recent cropped image bytes from the user's crop step.
  /// Populated after a successful crop and used by [_handleDeepAnalysis].
  Uint8List? _croppedImageBytes;

  /// Cached Premium state for the deep-analysis gate.
  bool _hasPremiumAccess = false;
  bool _premiumStatusLoading = true;

  /// Hard gate: the user must explicitly accept the pre-analysis disclaimer
  /// before any image is sent to the backend. The Deep Analysis button stays
  /// disabled until a cropped image exists AND this is true.
  bool _consentAccepted = false;

  /// True while [_handleDeepAnalysis] is awaiting a backend response.
  bool _isAnalyzing = false;

  final List<String> _affirmations = [
    "Every scan brings you closer to the skin you deserve.",
    "Consistency is beautiful. You're doing amazing.",
    "Your skin is healing and glowing — keep going!",
    "Progress looks good on you.",
    "Small steps today create big transformations tomorrow.",
    "You're investing in yourself — that's powerful.",
    "Patience and persistence create radiant skin.",
    "You're building something beautiful, one photo at a time.",
  ];
  int _lastAffirmationIndex = 0;

  final ImagePicker _picker = ImagePicker();
  int _lightingFrameCounter = 0;
  int _sharpnessFrameCounter = 0;
  double _liveSharpness = 0;
  double _liveMeanBrightness = 0;
  double _liveFaceRoiLuma = 0;
  double _liveBacklightDelta = 0;
  // Signed left-minus-right frame luma delta (reuses the same sampling as
  // _liveBacklightDelta, which only keeps the unsigned max of horizontal vs
  // vertical). Positive = left half of frame brighter than right.
  double _liveLightHorizontalDelta = 0;
  double _liveFaceFillRatio = 0;
  // Neutral placeholder only — widget.procedure isn't attached yet at field
  // init time so _isBodyGuide can't be read here. Overwritten by the first
  // _buildClinicalQualityReport() call, which does branch on it.
  String _qaBannerMessage = 'Center yourself inside the guide';
  String? _lastCaptureQualityTag;

  List<String> get _guidanceTips =>
      _isBodyGuide ? _bodyGuidanceTips : _faceGuidanceTips;

  ProcedureCameraGuideType get _guideType {
    return resolveCameraGuideType(
      isSkincareScan: widget.isSkincareScan,
      capturePurpose: widget.capturePurpose,
      procedureBodyRegion: widget.procedure?.bodyRegion,
      effectiveGuideProcedureType: _effectiveGuideProcedureType,
    );
  }

  String get _effectiveGuideProcedureType {
    if (widget.procedure != null) return widget.procedure!.type;
    return _scanProcedureLabel;
  }

  bool get _isBodyGuide {
    return _guideType == ProcedureCameraGuideType.body;
  }

  List<String> get _overlayAngles {
    return _poseTemplates;
  }

  List<String> get _poseTemplates {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        return const [
          'Front',
          'Left 45°',
          'Left Profile',
          'Right 45°',
          'Right Profile',
        ];
      case ProcedureCameraGuideType.body:
        return const [
          'Front',
          'Left 45°',
          'Left Side',
          'Back',
          'Right 45°',
          'Right Side',
        ];
      case ProcedureCameraGuideType.general:
        return const ['Front'];
    }
  }

  String? get _focusAreaForSave {
    if (widget.isSkincareScan) return null;
    final focusArea = (_scanFocusArea ?? widget.procedure?.focusArea)?.trim();
    return focusArea == null || focusArea.isEmpty ? null : focusArea;
  }

  String? get _customDescriptionForSave {
    return normalizedCustomDescription(
      _scanCustomDescription ?? widget.procedure?.customDescription,
    );
  }

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _successAnim = CurvedAnimation(
      parent: _successController,
      curve: Curves.easeOutCubic,
    );
    _loadScanProcedureContext();
    _refreshPremiumStatus();
    // Surface the makeup disclosure before any camera resources are claimed.
    // _initLiveCamera() runs only after the patient acknowledges either the
    // "clean face" or "wearing makeup" path. A cancel pops the screen.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _promptMakeupDisclosure(),
    );
  }

  Future<void> _promptMakeupDisclosure() async {
    if (_disclosureInFlight || _makeupPresent != null) return;
    _disclosureInFlight = true;
    final result = await MakeupDisclosureDialog.show(context);
    _disclosureInFlight = false;
    if (!mounted) return;
    if (result == null) {
      // User dismissed without choosing — leave the camera screen.
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _makeupPresent = result);

    if (_isBodyGuide && _selectedBodyCaptureMode == null) {
      final mode = await _promptBodyCaptureMode();
      if (!mounted) return;
      if (mode == null) {
        // User backed out of choosing a capture method — leave the screen
        // rather than guessing, same as declining the makeup disclosure.
        Navigator.of(context).maybePop();
        return;
      }
      setState(() => _selectedBodyCaptureMode = mode);
    }

    // Now that the patient has acknowledged the disclosure (and, for body
    // scans, chosen a capture method), start the camera.
    _initLiveCamera();
  }

  /// Blocking capture-method picker for body-region procedures. Mirrors the
  /// makeup-disclosure dialog's shape: no dismiss-by-tapping-outside, and a
  /// null result (explicit "Cancel") pops the camera screen rather than
  /// silently defaulting to a mode the user didn't choose — capture mode
  /// materially changes downstream analysis (mirror-flip), so it must be an
  /// explicit user choice, never guessed.
  Future<BodyCaptureMode?> _promptBodyCaptureMode() async {
    if (_captureModePromptInFlight) return _selectedBodyCaptureMode;
    _captureModePromptInFlight = true;
    try {
      return await showDialog<BodyCaptureMode>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          BodyCaptureMode selected = BodyCaptureMode.mirror;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Widget option(BodyCaptureMode mode, {bool recommended = false}) {
                final isSelected = selected == mode;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setDialogState(() => selected = mode),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? MyApp.goldShimmer.withValues(alpha: 0.14)
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? MyApp.goldShimmer
                            : AppColors.borders,
                        width: isSelected ? 1.6 : 1.0,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected
                              ? MyApp.goldShimmer
                              : AppColors.refinedSlate,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      mode.label,
                                      style: TextStyle(
                                        color: MyApp.clinicalNavy,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (recommended) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.mutedSage.withValues(
                                          alpha: 0.2,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          8,
                                        ),
                                      ),
                                      child: Text(
                                        'RECOMMENDED',
                                        style: TextStyle(
                                          color: AppColors.mutedSage,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                mode.description,
                                style: TextStyle(
                                  color: MyApp.textBrown,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return AlertDialog(
                title: const Text('How are you taking this photo?'),
                content: SizedBox(
                  width: 340,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      option(BodyCaptureMode.mirror, recommended: true),
                      option(BodyCaptureMode.assisted),
                      option(BodyCaptureMode.timer),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(null),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(selected),
                    child: const Text('Continue'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      _captureModePromptInFlight = false;
    }
  }

  /// Lets the user switch capture method mid-session (e.g. they started in
  /// mirror mode but a partner walked in to help). Re-runs the same prompt
  /// and, if the front/rear camera preference changed, re-initializes the
  /// controller on the right lens.
  Future<void> _changeBodyCaptureMode() async {
    final previous = _selectedBodyCaptureMode;
    final mode = await _promptBodyCaptureMode();
    if (!mounted || mode == null || mode == previous) return;
    setState(() => _selectedBodyCaptureMode = mode);
    final wantsRearNow =
        mode == BodyCaptureMode.assisted || mode == BodyCaptureMode.timer;
    final wantsRearBefore =
        previous == BodyCaptureMode.assisted ||
        previous == BodyCaptureMode.timer;
    if (wantsRearNow != wantsRearBefore && _availableCameras.isNotEmpty) {
      final target = wantsRearNow
          ? _availableCameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => _availableCameras.first,
            )
          : _availableCameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => _availableCameras.first,
            );
      await _initializeController(target);
    }
  }

  /// Guidance copy shown alongside the chosen capture mode, per PRIORITY
  /// 1.3/2.1/3 of the body-capture redesign — distance/angle/addressee
  /// differ enough between the three setups that a single shared string
  /// would be wrong for at least two of them.
  String get _bodyCaptureModeInstruction {
    switch (_selectedBodyCaptureMode) {
      case BodyCaptureMode.mirror:
        return 'Stand facing the mirror, phone at chest height, arm fully '
            'extended toward the mirror. The reflection adds real depth vs. '
            'a normal selfie — step back until your full treatment area '
            'fits inside the outline before capturing.';
      case BodyCaptureMode.assisted:
        return 'Photographer: stand facing away from the light source, '
            'center their treatment area inside the outline, and hold the '
            'phone steady at chest height — avoid tilting up or down.';
      case BodyCaptureMode.timer:
        return 'Prop the phone against something stable at chest height and '
            'level. Tap "Start timer", then step back into frame and hold '
            'your pose until the shutter fires.';
      case null:
        return '';
    }
  }

  /// User-initiated countdown for [BodyCaptureMode.timer]. Deliberately
  /// ignores the live quality gate that [_evaluateAutoCapture] enforces —
  /// the entire point of this mode is that the user has stepped away from
  /// the phone and can't react to a "hold still" prompt, so it fires on a
  /// fixed clock instead of waiting for green quality signals.
  void _startTimerCapture() {
    if (_timerCaptureCountdown != null || _capturing) return;
    const totalSeconds = 8;
    setState(() => _timerCaptureCountdown = totalSeconds);
    _timerCaptureTimer?.cancel();
    _timerCaptureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = (_timerCaptureCountdown ?? 1) - 1;
      if (remaining <= 0) {
        timer.cancel();
        setState(() => _timerCaptureCountdown = null);
        // bypassFramingGate: true — by the time the countdown ends the user
        // has stepped away from the phone and can't react to a "hold
        // still"/framing warning the way a manual tap or the quality-gated
        // auto-capture can. Capture on the fixed clock regardless; any real
        // framing/lighting problem still lands honestly in the saved scan's
        // captureQuality tag instead of silently doing nothing.
        _handleCaptureTap(auto: true, bypassFramingGate: true);
        return;
      }
      setState(() => _timerCaptureCountdown = remaining);
    });
  }

  Future<void> _refreshPremiumStatus() async {
    final isPremium = await PremiumAccess.isPremiumUser();
    if (!mounted) return;
    setState(() {
      _hasPremiumAccess = isPremium;
      _premiumStatusLoading = false;
    });
  }

  Future<void> _initLiveCamera() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _cameraInitFailed = true;
          _cameraError = 'No camera detected on this device.';
        });
        return;
      }
      _availableCameras = cameras;
      // Mirror mode needs the front (selfie) camera so the live preview
      // shows the user their own reflection framing. Assisted/timer modes
      // are a direct shot of the subject by someone else (or a propped
      // phone) — the rear camera gives better image quality and isn't
      // constrained by needing to face a screen, so prefer it there when
      // available.
      final wantsRearCamera =
          _isBodyGuide &&
          (_selectedBodyCaptureMode == BodyCaptureMode.assisted ||
              _selectedBodyCaptureMode == BodyCaptureMode.timer);
      final preferred = wantsRearCamera
          ? cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first,
            )
          : cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => cameras.first,
            );
      await _initializeController(preferred);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraInitFailed = true;
        _cameraError = 'Unable to start camera: $e';
      });
    }
  }

  Future<void> _initializeController(CameraDescription description) async {
    final old = _cameraController;
    if (old != null) {
      await old.dispose();
    }

    // iOS's camera stream never delivers YUV420 in practice — asking for it
    // there made analyzeLiveLandmarks's InputImage conversion (which
    // requires exactly bgra8888 on iOS) return null for essentially every
    // frame, so landmarks/face-fill/etc. never populated on iOS at all.
    // Android's ML Kit path accepts yuv420 directly, so it stays as-is.
    // The live-stream pixel readers below (lighting/sharpness/face-ROI
    // luma) are format-aware via _primaryPlaneBytesPerPixel /
    // _luminanceFromBytes and handle both layouts correctly.
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      await _setCameraAutoModes(controller);

      setState(() {
        _cameraController = controller;
        _cameraReady = true;
        _cameraInitFailed = false;
        _cameraError = null;
      });

      _startLightingStream(controller);
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
        _cameraInitFailed = true;
        _cameraError = 'Camera initialization failed: $e';
      });
    }
  }

  Future<void> _setCameraAutoModes(CameraController controller) async {
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (e) {
      debugPrint('Camera exposure auto mode unsupported: $e');
    }
  }

  Future<void> _toggleCameraLens() async {
    if (_availableCameras.length < 2) return;
    final current = _cameraController?.description;
    final currentIndex = _availableCameras.indexWhere(
      (c) => c.name == current?.name,
    );
    final nextIndex = currentIndex == -1
        ? 0
        : (currentIndex + 1) % _availableCameras.length;
    await _initializeController(_availableCameras[nextIndex]);
  }

  void _startLightingStream(CameraController controller) {
    if (kIsWeb || _lightingStreamActive) {
      return;
    }
    if (!controller.value.isInitialized) {
      return;
    }

    _lightingStreamActive = true;
    if (mounted) {
      setState(() {});
    }
    controller
        .startImageStream((image) async {
          if (!mounted || _capturing) return;

          _sharpnessFrameCounter = (_sharpnessFrameCounter + 1) % 3;
          final shouldRefreshSharpness = _sharpnessFrameCounter == 0;

          _lightingFrameCounter = (_lightingFrameCounter + 1) % 4;
          final shouldRefreshLighting = _lightingFrameCounter == 0;
          if (shouldRefreshLighting || shouldRefreshSharpness) {
            final summary = _summarizeCameraImage(image);
            final faceRoiLuma = _estimateFaceRoiLumaFromStream(image);
            if (kDebugMode) {
              _debugLiveDarkRatio = summary.darkRatio;
              final debugPlane = image.planes.firstOrNull;
              if (debugPlane != null) {
                _debugPlaneBytesPerRow = debugPlane.bytesPerRow;
                _debugPlaneWidthTimesBpp =
                    image.width * _primaryPlaneBytesPerPixel(image, debugPlane);
              }
            }
            final guidance = shouldRefreshLighting
                ? _lightingFromCameraImage(image, faceRoiLuma: faceRoiLuma)
                : _lightingGuidance;

            final horizontalLightDelta = summary.leftMean - summary.rightMean;
            final edgeDelta = [
              horizontalLightDelta.abs(),
              (summary.topMean - summary.bottomMean).abs(),
            ].reduce(math.max);
            final sharpness = shouldRefreshSharpness
                ? _estimateLaplacianVarianceFromYPlane(image)
                : _liveSharpness;
            final needsUiUpdate =
                guidance.level != _lightingGuidance.level ||
                guidance.label != _lightingGuidance.label ||
                (_liveSharpness - sharpness).abs() >= 1.5 ||
                (_liveMeanBrightness - summary.mean).abs() >= 2.0 ||
                (_liveFaceRoiLuma - faceRoiLuma).abs() >= 2.0 ||
                (_liveBacklightDelta - edgeDelta).abs() >= 2.0 ||
                (_liveLightHorizontalDelta - horizontalLightDelta).abs() >= 2.0;

            if (needsUiUpdate && mounted) {
              setState(() {
                _lightingGuidance = guidance;
                _liveSharpness = sharpness;
                _liveMeanBrightness = summary.mean;
                _liveFaceRoiLuma = faceRoiLuma;
                _liveBacklightDelta = edgeDelta;
                _liveLightHorizontalDelta = horizontalLightDelta;
              });
            }
          }

          if (kIsWeb || _landmarkAssessmentInFlight) return;
          _landmarkFrameCounter = (_landmarkFrameCounter + 1) % 6;
          if (_landmarkFrameCounter != 0) return;

          _landmarkAssessmentInFlight = true;
          try {
            final assessment = await analyzeLiveLandmarks(
              image: image,
              camera: controller.description,
              deviceOrientation: _currentDeviceOrientation(controller),
              isBody: _isBodyGuide,
              poseTemplate: _selectedPoseTemplate,
              previewAspectRatio: _isBodyGuide
                  ? _bodyPreviewAspectRatio
                  : _facePreviewAspectRatio,
            );
            if (!mounted) return;
            // Debug-only: record this frame's UNSMOOTHED result before it
            // goes anywhere near _landmarkHistory/_stabilizeLandmarkAssessment,
            // so _buildDebugFramingOverlay can show raw vs. smoothed side by
            // side. Updates on every analyzed frame (not gated by
            // _shouldRefreshLandmarkAssessment below) so it reflects true
            // per-frame jitter. No effect on any gating logic.
            if (kDebugMode) {
              setState(() {
                _debugRawAvailable = assessment.available;
                _debugRawYaw = assessment.yaw;
                _debugRawPitch = assessment.pitch;
                _debugRawRoll = assessment.roll;
                _debugRawFormatGroup = image.format.group.toString();
                _debugRawFormatCode = image.format.raw;
                _debugRawPlaneCount = image.planes.length;
                _debugSensorOrientation = controller.description.sensorOrientation;
              });
            }
            final stabilized = _stabilizeLandmarkAssessment(assessment);
            final shouldRefresh = _shouldRefreshLandmarkAssessment(stabilized);
            if (shouldRefresh || stabilized.available) {
              print(
                '[LIVE FACE POSE] available=${stabilized.available} yaw=${(stabilized.yaw ?? 0.0).toStringAsFixed(2)}° pitch=${(stabilized.pitch ?? 0.0).toStringAsFixed(2)}° roll=${(stabilized.roll ?? 0.0).toStringAsFixed(2)}° centerDelta=${((stabilized.centerOffsetX.abs() + stabilized.centerOffsetY.abs())).toStringAsFixed(3)} faceFillRatio=${stabilized.faceFillRatio.toStringAsFixed(3)} poseSimilarity=${stabilized.poseSimilarity.toStringAsFixed(2)}',
              );
              setState(() {
                _liveLandmarkAssessment = stabilized;
                if (stabilized.faceFillRatio > 0) {
                  _liveFaceFillRatio = stabilized.faceFillRatio;
                }
              });
            }
          } catch (_) {
            if (!mounted) return;
          } finally {
            _landmarkAssessmentInFlight = false;
          }
        })
        .catchError((Object error, StackTrace stack) {
          _lightingStreamActive = false;
          if (mounted) {
            setState(() {});
          }
        });
  }

  _LightingGuidance _lightingFromCameraImage(
    CameraImage image, {
    required double faceRoiLuma,
  }) {
    final plane = image.planes.firstOrNull;
    if (plane == null || plane.bytes.isEmpty) {
      return _lightingGuidance;
    }

    final thresholds = _lightingThresholds;
    final summary = _summarizeCameraImage(image);
    if (summary.isEmpty) return _lightingGuidance;

    final hasFaceSample = faceRoiLuma > 0;
    final isTooDark = isLightingTooDark(
      faceRoiLuma: faceRoiLuma,
      wholeFrameMean: summary.mean,
      wholeFrameDarkRatio: summary.darkRatio,
      darkMeanFloor: thresholds.darkMeanFloor,
      darkRatioCeil: thresholds.darkRatioCeil,
    );
    if (isTooDark) {
      return _LightingGuidance(
        level: LightingLevel.tooDark,
        label: 'Too dark',
        instruction: hasFaceSample
            ? 'Move to better light for a cleaner scan.'
            : _buildLightingInstruction(summary, tooDark: true),
      );
    }
    if (summary.mean > thresholds.harshMeanCeil ||
        summary.brightRatio > thresholds.harshRatioCeil) {
      return _LightingGuidance(
        level: LightingLevel.tooHarsh,
        label: 'Too harsh',
        instruction: _buildLightingInstruction(summary, tooDark: false),
      );
    }
    return const _LightingGuidance(
      level: LightingLevel.optimal,
      label: 'Lighting optimal',
      instruction:
          'Lighting is optimal. Keep this exact setup for reliable comparison.',
    );
  }

  /// Debug-only (see [_buildDebugFramingOverlay]): names exactly which
  /// rule [_lightingFromCameraImage] used to reach its current tooDark
  /// verdict, using the same fields/thresholds/branch order that function
  /// itself uses -- so this can never disagree with the real verdict. Pure
  /// read-only formatting, not gating logic.
  String _debugLightingTooDarkTrigger() {
    final thresholds = _lightingThresholds;
    final hasFaceSample = _liveFaceRoiLuma > 0;
    if (hasFaceSample) {
      if (_liveFaceRoiLuma < thresholds.darkMeanFloor) {
        return 'face-ROI rule: faceRoiLuma '
            '${_liveFaceRoiLuma.toStringAsFixed(1)} < floor '
            '${thresholds.darkMeanFloor.toStringAsFixed(0)}';
      }
      return 'none — not tooDark (face-ROI rule applies; '
          'whole-frame mean/darkRatio ignored while a face sample exists)';
    }
    if (_liveMeanBrightness < thresholds.darkMeanFloor) {
      return 'whole-frame rule: wholeFrameMean '
          '${_liveMeanBrightness.toStringAsFixed(1)} < floor '
          '${thresholds.darkMeanFloor.toStringAsFixed(0)}';
    }
    final darkRatio = _debugLiveDarkRatio;
    if (darkRatio != null && darkRatio > thresholds.darkRatioCeil) {
      return 'whole-frame rule: darkRatio ${darkRatio.toStringAsFixed(3)} '
          '> ceil ${thresholds.darkRatioCeil.toStringAsFixed(2)}';
    }
    return 'none — not tooDark (whole-frame rule applies; no face sample)';
  }

  Future<void> _playSuccessBurst() async {
    if (!mounted) return;
    setState(() => _showSuccessBurst = true);
    await _successController.forward(from: 0);
    if (!mounted) return;
    setState(() => _showSuccessBurst = false);
  }

  Future<void> _loadScanProcedureContext() async {
    if (widget.procedure != null) {
      _selectedProcedureId = widget.procedure!.id;
      _scanProcedureLabel = widget.procedure!.type;
      _scanFocusArea = widget.procedure!.focusArea;
      _scanCustomDescription = widget.procedure!.customDescription;
      await _loadReferenceContext();
      if (mounted) setState(() {});
      return;
    }

    if (widget.isSkincareScan &&
        widget.productName != null &&
        widget.productName!.isNotEmpty) {
      _selectedProcedureId = null;
      _scanProcedureLabel = widget.productName!;
      _scanFocusArea = null;
      _scanCustomDescription = null;
      await _loadReferenceContext();
      if (mounted) setState(() {});
      return;
    }

    final selectedId =
        widget.initialProcedureId ?? await AppPrefs.resolveActiveProcedureId();
    var procedureLabel = widget.initialProcedureLabel ?? '';
    String? focusArea;
    String? customDescription;
    if (selectedId != null && selectedId.isNotEmpty) {
      try {
        final procedures = await AppPrefs.getProcedureEntries();
        final match = procedures.firstWhere(
          (p) => (p['id']?.toString() ?? '') == selectedId,
        );
        final procedure = Procedure.fromJson(Map<String, dynamic>.from(match));
        if (procedureLabel.trim().isEmpty) {
          procedureLabel = procedure.type.trim();
        }
        focusArea = procedure.focusArea;
        customDescription = procedure.customDescription;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _selectedProcedureId = selectedId;
      _scanProcedureLabel = procedureLabel;
      _scanFocusArea = focusArea;
      _scanCustomDescription = customDescription;
    });
    if (widget.initialTrackProcedureBaselineRecord != null) {
      // Baseline capture state is no longer stored in this screen.
    }
    await _loadReferenceContext();
  }

  Map<String, dynamic> _currentTrackProcedureCalibrationRecord() {
    return {
      'euler_x': _liveLandmarkAssessment.yaw,
      'euler_y': _liveLandmarkAssessment.pitch,
      'euler_z': _liveLandmarkAssessment.roll,
      'ambient_brightness': _liveMeanBrightness,
    };
  }

  double _bodyAlignmentScoreFromReference() {
    if (!_isTrackProcedureFlow) return 0.0;
    final score = bodyReferenceAlignmentScore(
      _referenceScan?.bodyReferenceGeometry,
      _liveLandmarkAssessment.bodyReferenceGeometry,
    );
    if (score == null) {
      return 0.0;
    }
    _liveReferenceAlignmentScore = score / 100.0;
    return _liveReferenceAlignmentScore;
  }

  double _faceAlignmentScoreFromReference() {
    if (!_isTrackProcedureFlow || _isBodyGuide) return 0.0;
    final score = faceReferenceAlignmentScore(
      _referenceScan?.faceReferenceGeometry,
      _liveLandmarkAssessment.faceReferenceGeometry,
    );
    if (score == null) return 0.0;
    _liveReferenceAlignmentScore = score / 100.0;
    return _liveReferenceAlignmentScore;
  }

  double get _activeReferenceAlignmentScore =>
      _liveReferenceAlignmentScore > 0.0
      ? _liveReferenceAlignmentScore
      : (_isBodyGuide
            ? _bodyAlignmentScoreFromReference()
            : _faceAlignmentScoreFromReference());

  String get _referenceAlignmentStatusLabel {
    if (!_isTrackProcedureFlow) return 'Reference alignment';
    final score = _activeReferenceAlignmentScore;
    if (score >= 0.82) return 'Aligned';
    if (score >= 0.60) return 'Adjust position';
    return 'Re-align';
  }

  Color get _referenceAlignmentStatusColor {
    if (!_isTrackProcedureFlow) return Colors.transparent;
    final score = _activeReferenceAlignmentScore;
    if (score >= 0.82) return AppColors.mutedSage;
    if (score >= 0.60) return AppColors.champagneGold;
    return AppColors.softTerracotta;
  }

  Future<void> _loadReferenceContext() async {
    final history = await AppPrefs.getScanEntries();
    final filtered = history.where(_isComparableEntry).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    ScanHistoryEntry? ref;
    String? refPath;
    Uint8List? refBytes;
    var selectedGoodReference = false;
    var bestScore = double.negativeInfinity;

    if (_isTrackProcedureFlow) {
      final procedureId = widget.procedure?.id ?? _selectedProcedureId;
      ref = lockedProcedureReference(history, procedureId);
      final candidatePath = ref?.imagePath;
      if (candidatePath != null && candidatePath.trim().isNotEmpty) {
        refBytes = await _bytesFromImagePath(candidatePath);
        if (refBytes != null && refBytes.isNotEmpty) {
          refPath = candidatePath;
          final candidateLighting = _analyzeLighting(refBytes);
          final landmarkQuality =
              ref?.metrics['capture_landmark_quality'] ?? 0.0;
          selectedGoodReference =
              candidateLighting.level == LightingLevel.optimal &&
              landmarkQuality >= 0.72;
        }
      }
    }

    for (final entry in _isTrackProcedureFlow
        ? const <ScanHistoryEntry>[]
        : filtered.take(12)) {
      final candidatePath = entry.imagePath;
      if (candidatePath == null || candidatePath.trim().isEmpty) {
        continue;
      }
      final candidateBytes = await _bytesFromImagePath(candidatePath);

      if (candidateBytes == null || candidateBytes.isEmpty) {
        continue;
      }

      final candidateLighting = _analyzeLighting(candidateBytes);
      final candidateConfidence =
          entry.lightingConfidence ??
          _estimateLightingConfidence(candidateBytes);
      final samePose =
          (entry.poseTemplate ?? '').trim() == _selectedPoseTemplate;
      final landmarkQuality = entry.metrics['capture_landmark_quality'] ?? 0.0;
      final poseSimilarity = entry.metrics['capture_pose_similarity'] ?? 0.0;
      final isGood =
          entry.preferredReference ||
          candidateLighting.level == LightingLevel.optimal;
      final score =
          (samePose ? 45.0 : 0.0) +
          (isGood ? 30.0 : 0.0) +
          (entry.preferredReference ? 15.0 : 0.0) +
          (candidateConfidence * 10.0) +
          (landmarkQuality * 20.0) +
          (poseSimilarity * 0.12);

      if (score > bestScore) {
        bestScore = score;
        ref = entry;
        refPath = candidatePath;
        refBytes = candidateBytes;
        selectedGoodReference = isGood && samePose && landmarkQuality >= 0.72;
      }
    }

    final lighting = _analyzeLighting(refBytes);

    if (!mounted) return;
    setState(() {
      _referenceScan = ref;
      _referenceImagePath = refPath;
      _referenceImageBytes = refBytes;
      _isGoodReferencePhoto = selectedGoodReference;
      _lightingGuidance = lighting;
      final templates = _poseTemplates;
      if (!templates.contains(_selectedPoseTemplate)) {
        _selectedPoseTemplate = templates.first;
      }
    });
  }

  bool _isComparableEntry(ScanHistoryEntry entry) {
    if (widget.isSkincareScan) {
      final product = widget.productName?.trim() ?? '';
      if (product.isEmpty) {
        return entry.productName == null ||
            (entry.productName ?? '').trim().isEmpty;
      }
      return (entry.productName ?? '').trim().toLowerCase() ==
          product.toLowerCase();
    }

    final selectedId = widget.procedure?.id ?? _selectedProcedureId;
    if (selectedId != null && selectedId.isNotEmpty) {
      return entry.procedureId == selectedId;
    }

    return (entry.productName ?? '').trim().isEmpty;
  }

  Future<Uint8List?> _bytesFromImagePath(String? imagePath) async {
    if (imagePath == null || imagePath.trim().isEmpty) return null;
    final ref = imagePath.trim();
    if (ref.startsWith('data:image')) {
      final comma = ref.indexOf(',');
      if (comma == -1) return null;
      try {
        return base64Decode(ref.substring(comma + 1));
      } catch (_) {
        return null;
      }
    }
    return readLocalImageBytes(ref);
  }

  _LightingGuidance _analyzeLighting(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return const _LightingGuidance.unknown();
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const _LightingGuidance.unknown();
    }

    final thresholds = _lightingThresholds;
    final summary = _summarizeDecodedImage(decoded);

    if (summary.mean < thresholds.darkMeanFloor ||
        summary.darkRatio > thresholds.darkRatioCeil) {
      return _LightingGuidance(
        level: LightingLevel.tooDark,
        label: 'Too dark',
        instruction: _buildLightingInstruction(summary, tooDark: true),
      );
    }
    if (summary.mean > thresholds.harshMeanCeil ||
        summary.brightRatio > thresholds.harshRatioCeil) {
      return _LightingGuidance(
        level: LightingLevel.tooHarsh,
        label: 'Too harsh',
        instruction: _buildLightingInstruction(summary, tooDark: false),
      );
    }

    return const _LightingGuidance(
      level: LightingLevel.optimal,
      label: 'Lighting optimal',
      instruction:
          'Lighting is optimal. Keep this exact setup for reliable comparison.',
    );
  }

  int _calculateConsistencyScore(
    Uint8List currentBytes,
    SkinMetrics currentMetrics, {
    LandmarkAssessment? landmarkAssessment,
  }) {
    var lightingScore = 78.0;
    var alignmentScore = 76.0;
    final refBytes = _referenceImageBytes;
    if (refBytes != null && refBytes.isNotEmpty) {
      final currentStats = _quickImageStats(currentBytes);
      final refStats = _quickImageStats(refBytes);
      final brightnessDelta = (currentStats.$1 - refStats.$1).abs();
      final contrastDelta = (currentStats.$2 - refStats.$2).abs();
      lightingScore = (100 - (brightnessDelta * 0.72))
          .clamp(50, 100)
          .toDouble();
      alignmentScore = (100 - (contrastDelta * 1.08)).clamp(50, 100).toDouble();
    }

    var poseScore = 80.0;
    final previous = _referenceScan?.toSkinMetrics();
    if (previous != null) {
      final deltas = [
        (currentMetrics.redness - previous.redness).abs(),
        (currentMetrics.texture - previous.texture).abs(),
        (currentMetrics.wrinkle - previous.wrinkle).abs(),
        (currentMetrics.pore - previous.pore).abs(),
        (currentMetrics.darkSpots - previous.darkSpots).abs(),
        (currentMetrics.elasticity - previous.elasticity).abs(),
      ];
      final avgDelta = deltas.reduce((a, b) => a + b) / deltas.length;
      poseScore = (100 - (avgDelta * 11.6)).clamp(50, 100).toDouble();
      if ((_referenceScan?.poseTemplate ?? '').trim() ==
          _selectedPoseTemplate) {
        poseScore = (poseScore + 8).clamp(50, 100).toDouble();
      } else if ((_referenceScan?.poseTemplate ?? '').trim().isNotEmpty) {
        poseScore = (poseScore - 10).clamp(40, 100).toDouble();
      }
    }

    final landmarkScore =
        landmarkAssessment == null || !landmarkAssessment.available
        ? null
        : _landmarkConsistencyScore(landmarkAssessment);

    final finalScore = landmarkScore == null
        ? ((alignmentScore * 0.40) +
                  (lightingScore * 0.35) +
                  (poseScore * 0.25))
              .round()
        : ((alignmentScore * 0.28) +
                  (lightingScore * 0.24) +
                  (poseScore * 0.16) +
                  (landmarkScore * 0.32))
              .round();
    return finalScore.clamp(55, 100);
  }

  double _landmarkConsistencyScore(LandmarkAssessment assessment) {
    final refMetrics = _referenceScan?.metrics ?? const <String, double>{};
    var score = assessment.poseSimilarity.clamp(0, 100).toDouble();
    score =
        (score * 0.72) +
        ((assessment.landmarkQuality * 100).clamp(0, 100) * 0.28);

    final refCenterOffsetX = refMetrics['capture_center_offset_x'];
    final refCenterOffsetY = refMetrics['capture_center_offset_y'];
    if (refCenterOffsetX != null) {
      score -= (assessment.centerOffsetX - refCenterOffsetX).abs() * 170;
    }
    if (refCenterOffsetY != null) {
      score -= (assessment.centerOffsetY - refCenterOffsetY).abs() * 150;
    }

    final refYaw = refMetrics['capture_yaw'];
    if (assessment.yaw != null && refYaw != null) {
      score -= (assessment.yaw! - refYaw).abs() * 1.05;
    }
    final refPitch = refMetrics['capture_pitch'];
    if (assessment.pitch != null && refPitch != null) {
      score -= (assessment.pitch! - refPitch).abs() * 0.9;
    }
    final refRoll = refMetrics['capture_roll'];
    if (assessment.roll != null && refRoll != null) {
      score -= (assessment.roll! - refRoll).abs() * 0.95;
    }
    final refEyeTilt = refMetrics['capture_eye_tilt'];
    if (assessment.eyeTilt != null && refEyeTilt != null) {
      score -= (assessment.eyeTilt! - refEyeTilt).abs() * 0.95;
    }
    final refShoulderTilt = refMetrics['capture_shoulder_tilt'];
    if (assessment.shoulderTilt != null && refShoulderTilt != null) {
      score -= (assessment.shoulderTilt! - refShoulderTilt).abs() * 1.15;
    }
    final refRotationProxy = refMetrics['capture_rotation_proxy'];
    if (refRotationProxy != null) {
      final delta = (assessment.rotationProxy - refRotationProxy).abs();
      score -= _isBodyGuide ? delta * 58 : delta * 0.9;
    }

    return score.clamp(45, 100).toDouble();
  }

  Map<String, double> _captureProvenanceMetrics(
    LandmarkAssessment assessment,
  ) {
    final metrics = <String, double>{...assessment.toMetricMap()};
    if (_isTrackProcedureFlow && _isBodyGuide) {
      final score = bodyReferenceAlignmentScore(
        _referenceScan?.bodyReferenceGeometry,
        assessment.bodyReferenceGeometry,
      );
      if (score != null) {
        metrics['capture_reference_alignment_score'] = score;
      }
    } else if (_isTrackProcedureFlow) {
      final score = faceReferenceAlignmentScore(
        _referenceScan?.faceReferenceGeometry,
        assessment.faceReferenceGeometry,
      );
      if (score != null) {
        metrics['capture_reference_alignment_score'] = score;
      }
    }
    return metrics;
  }

  Map<String, dynamic>? _baselineMetricMatrix() {
    final refMetrics = _referenceScan?.metrics;
    if (refMetrics == null || refMetrics.isEmpty) {
      return null;
    }

    double readMetric(List<String> keys) {
      for (final key in keys) {
        final raw = refMetrics[key];
        if (raw == null) continue;
        return raw.clamp(0.0, 10.0).toDouble();
      }
      return 0.0;
    }

    final redness = readMetric(const ['redness', 'erythema']);
    final texture = readMetric(const ['texture', 'roughness']);
    final pores = readMetric(const ['pores', 'pore']);
    final acne = readMetric(const ['acne_severity', 'acneSeverity']);

    return {
      'localized_redness': double.parse((redness * 10).toStringAsFixed(1)),
      'texture_smoothness': double.parse(
        ((10 - texture).clamp(0.0, 10.0) * 10).toStringAsFixed(1),
      ),
      'pore_visibility': double.parse((pores * 10).toStringAsFixed(1)),
      'breakout_activity': double.parse((acne * 10).toStringAsFixed(1)),
    };
  }

  Widget _buildGhostReferenceOverlay() {
    final path = _referenceImagePath;
    if (!_showGhostOverlay || path == null) {
      return const SizedBox.shrink();
    }

    final imageChild = path.startsWith('data:image')
        ? Image.memory(
            _referenceImageBytes ?? Uint8List(0),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          )
        : buildLocalImagePreview(
            path,
            width: double.infinity,
            height: double.infinity,
            borderRadius: 28,
          );

    return Positioned.fill(
      child: Opacity(
        opacity: _ghostOverlayOpacity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0.2126,
              0.7152,
              0.0722,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: imageChild,
          ),
        ),
      ),
    );
  }

  DeviceOrientation _currentDeviceOrientation(CameraController controller) {
    return controller.value.deviceOrientation;
  }

  LandmarkAssessment _stabilizeLandmarkAssessment(LandmarkAssessment next) {
    if (!next.available) return next;

    _landmarkHistory.add(next);
    if (_landmarkHistory.length > _landmarkSmoothingWindow) {
      _landmarkHistory.removeAt(0);
    }

    final yaw = _average(
      _landmarkHistory.map((item) => item.yaw ?? 0.0),
    );
    final pitch = _average(
      _landmarkHistory.map((item) => item.pitch ?? 0.0),
    );
    final roll = _average(
      _landmarkHistory.map((item) => item.roll ?? 0.0),
    );
    final eyeTilt = _average(
      _landmarkHistory.map((item) => item.eyeTilt ?? 0.0),
    );
    final shoulderTilt = _average(
      _landmarkHistory.map((item) => item.shoulderTilt ?? 0.0),
    );
    final centerOffsetX = _average(
      _landmarkHistory.map((item) => item.centerOffsetX),
    );
    final centerOffsetY = _average(
      _landmarkHistory.map((item) => item.centerOffsetY),
    );
    final landmarkQuality = _average(
      _landmarkHistory.map((item) => item.landmarkQuality),
    );
    final poseSimilarity = _average(
      _landmarkHistory.map((item) => item.poseSimilarity),
    );
    final rotationProxy = _average(
      _landmarkHistory.map((item) => item.rotationProxy),
    );
    final faceFillRatio = _average(
      _landmarkHistory.map((item) => item.faceFillRatio),
    );

    return LandmarkAssessment(
      available: true,
      primaryInstruction: next.primaryInstruction,
      secondaryInstruction: next.secondaryInstruction,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      eyeTilt: eyeTilt,
      shoulderTilt: shoulderTilt,
      centerOffsetX: centerOffsetX,
      centerOffsetY: centerOffsetY,
      landmarkQuality: landmarkQuality,
      poseSimilarity: poseSimilarity,
      rotationProxy: rotationProxy,
      faceFillRatio: faceFillRatio,
      mode: next.mode,
      bodyReferenceGeometry: next.bodyReferenceGeometry,
      faceReferenceGeometry: next.faceReferenceGeometry,
    );
  }

  double _average(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return 0.0;
    return list.reduce((a, b) => a + b) / list.length;
  }

  bool _shouldRefreshLandmarkAssessment(LandmarkAssessment next) {
    final current = _liveLandmarkAssessment;
    final pitchDelta = ((current.pitch ?? 0.0) - (next.pitch ?? 0.0)).abs();
    final yawDelta = ((current.yaw ?? 0.0) - (next.yaw ?? 0.0)).abs();
    final rollDelta = ((current.roll ?? 0.0) - (next.roll ?? 0.0)).abs();
    final centerChanged =
        (current.centerOffsetX - next.centerOffsetX).abs() >= 0.02 ||
        (current.centerOffsetY - next.centerOffsetY).abs() >= 0.02;

    final pitchChanged = (current.pitch ?? 0.0) != (next.pitch ?? 0.0) &&
        pitchDelta >= 1.0;
    final yawChanged = (current.yaw ?? 0.0) != (next.yaw ?? 0.0) &&
        yawDelta >= 1.0;
    final rollChanged = (current.roll ?? 0.0) != (next.roll ?? 0.0) &&
        rollDelta >= 1.0;

    return current.available != next.available ||
        current.primaryInstruction != next.primaryInstruction ||
        current.secondaryInstruction != next.secondaryInstruction ||
        (current.poseSimilarity - next.poseSimilarity).abs() >= 3 ||
        (current.landmarkQuality - next.landmarkQuality).abs() >= 0.04 ||
        pitchChanged ||
        yawChanged ||
        rollChanged ||
        centerChanged ||
        (current.faceFillRatio - next.faceFillRatio).abs() >= 0.03;
  }

  ({Color color, String label, String note}) _consistencyVisuals(int score) {
    if (score >= 90) {
      return (
        color: AppColors.mutedSage,
        label: 'Excellent Match',
        note:
            'Alignment, lighting, and pose are highly consistent with your reference photo.',
      );
    }
    if (score >= 78) {
      return (
        color: AppColors.champagneGold,
        label: 'Good Match',
        note:
            'Small differences detected. Your photo is still suitable for trend metrics.',
      );
    }
    return (
      color: AppColors.softTerracotta,
      label: 'Needs Better Match',
      note:
          'Re-align using the ghost overlay and improve lighting for more reliable metrics.',
    );
  }

  Future<void> _showConsistencyResultSheet({
    required int score,
    String? premiumInsightText,
  }) async {
    final visuals = _consistencyVisuals(score);
    final progressValue = (score / 100).clamp(0.0, 1.0);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.08),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: visuals.color.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: visuals.color.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Icon(
                        Icons.verified_outlined,
                        color: visuals.color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Consistency Score',
                            style: MyApp.pageTitleStyle(),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Progress comparison completed',
                            style: TextStyle(
                              color: MyApp.textBrown.withValues(alpha: 0.66),
                              fontWeight: FontWeight.w600,
                              fontSize: 11.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: visuals.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: visuals.color.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '$score%',
                            style: TextStyle(
                              color: visuals.color,
                              fontSize: 33,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              visuals.label,
                              style: TextStyle(
                                color: visuals.color,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                          Text(
                            score >= 90
                                ? 'High confidence'
                                : score >= 78
                                ? 'Reliable'
                                : 'Retake suggested',
                            style: TextStyle(
                              color: visuals.color.withValues(alpha: 0.88),
                              fontSize: 11.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progressValue,
                          minHeight: 7,
                          backgroundColor: visuals.color.withValues(
                            alpha: 0.14,
                          ),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            visuals.color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        visuals.note,
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.84),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        score >= 78
                            ? 'This capture quality is suitable for trusted trend tracking.'
                            : 'For the most trustworthy comparison, retake with matched angle and light.',
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.63),
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                          height: 1.32,
                        ),
                      ),
                    ],
                  ),
                ),
                if (premiumInsightText != null &&
                    premiumInsightText.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: MyApp.goldShimmer.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: MyApp.goldShimmer,
                          size: 17,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Premium insight: $premiumInsightText',
                            style: TextStyle(
                              color: MyApp.textBrown.withValues(alpha: 0.82),
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: MyApp.primaryGoldButton,
                    child: const Text('Save & Continue'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  (double, double) _quickImageStats(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return (128, 24);
    final summary = _summarizeDecodedImage(decoded);
    return (summary.mean, summary.contrast);
  }

  double _estimateLightingConfidence(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return 0.0;
    final summary = _summarizeDecodedImage(decoded);
    final balancePenalty = (summary.leftMean - summary.rightMean).abs() / 255.0;
    final exposureScore = (1 - ((summary.mean - 138).abs() / 138)).clamp(
      0.0,
      1.0,
    );
    final shadowScore = (1 - summary.darkRatio).clamp(0.0, 1.0);
    return ((exposureScore * 0.45) +
            (shadowScore * 0.35) +
            ((1 - balancePenalty) * 0.20))
        .clamp(0.0, 1.0);
  }

  double _lightingConfidenceFromGuidance(_LightingGuidance guidance) {
    switch (guidance.level) {
      case LightingLevel.optimal:
        return 0.84;
      case LightingLevel.tooHarsh:
        return 0.46;
      case LightingLevel.tooDark:
        return 0.38;
      case LightingLevel.unknown:
        return 0.56;
    }
  }

  Uint8List _prepareWebStorageBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final maxSide = math.max(decoded.width, decoded.height);
    if (maxSide <= 960) {
      return Uint8List.fromList(img.encodeJpg(decoded, quality: 58));
    }

    final resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 960 : null,
      height: decoded.height > decoded.width ? 960 : null,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 58));
  }

  // ── Format-aware pixel readers for the live CameraImage stream ─────────
  // The stream's first plane is a single-channel 8-bit Y (luma) plane for
  // every YUV-family ImageFormatGroup this app requests (yuv420 on
  // Android, and previously — incorrectly — on iOS too), but is a single
  // interleaved 4-byte-per-pixel BGRA plane for ImageFormatGroup.bgra8888
  // (now used on iOS — see _initializeController). Every consumer below
  // that reads `image.planes.first`/`firstOrNull` byte-by-byte
  // (_summarizeCameraImage, _estimateFaceRoiLumaFromStream,
  // _estimateLaplacianVarianceFromYPlane) goes through these two helpers
  // so none of them silently mis-read BGRA as if it were 1-byte-per-pixel
  // Y data (which would sample a different, effectively random channel
  // byte per pixel and produce meaningless brightness/sharpness values).

  /// Bytes-per-pixel for [plane] under [image]'s actual format group.
  /// `Plane.bytesPerPixel` is Android-only (it is documented — and
  /// confirmed in practice — to always be `null` on iOS), so this can't
  /// simply trust that field; it's used only as a defensive first choice,
  /// falling back to the known layout for the two format groups this app
  /// actually requests: 4 for bgra8888, 1 for every YUV-family group.
  int _primaryPlaneBytesPerPixel(CameraImage image, Plane plane) {
    final reported = plane.bytesPerPixel;
    if (reported != null && reported > 0) return reported;
    return image.format.group == ImageFormatGroup.bgra8888 ? 4 : 1;
  }

  /// Luminance for the pixel whose first byte is at [pixelStart] in
  /// [bytes]. For a 1-byte-per-pixel Y plane this is just that byte. For
  /// 4-byte BGRA this derives luma from B/G/R (byte order confirmed via
  /// package:camera's `Plane` docs — iOS delivers `kCVPixelFormatType_
  /// 32BGRA`) using the same Rec.709 weights already used elsewhere in
  /// this file for the grayscale preview ColorFilter, ignoring alpha.
  double _luminanceFromBytes(Uint8List bytes, int pixelStart, int bytesPerPixel) {
    if (bytesPerPixel <= 1) return bytes[pixelStart].toDouble();
    final b = bytes[pixelStart].toDouble();
    final g = bytes[pixelStart + 1].toDouble();
    final r = bytes[pixelStart + 2].toDouble();
    return (0.2126 * r) + (0.7152 * g) + (0.0722 * b);
  }

  _LightingFrameSummary _summarizeCameraImage(CameraImage image) {
    final plane = image.planes.first;
    final bytesPerPixel = _primaryPlaneBytesPerPixel(image, plane);
    final width = image.width;
    final height = image.height;
    final stepX = math.max(1, width ~/ 28);
    final stepY = math.max(1, height ~/ 28);
    var total = 0.0;
    var leftTotal = 0.0;
    var rightTotal = 0.0;
    var topTotal = 0.0;
    var bottomTotal = 0.0;
    var count = 0;
    var leftCount = 0;
    var rightCount = 0;
    var topCount = 0;
    var bottomCount = 0;
    var darkPixels = 0;
    var brightPixels = 0;
    final samples = <double>[];

    for (var y = 0; y < height; y += stepY) {
      final rowStart = y * plane.bytesPerRow;
      for (var x = 0; x < width; x += stepX) {
        final index = rowStart + x * bytesPerPixel;
        if (index + bytesPerPixel > plane.bytes.length) continue;
        final luminance = _luminanceFromBytes(plane.bytes, index, bytesPerPixel);
        samples.add(luminance);
        total += luminance;
        count += 1;
        if (x < width / 2) {
          leftTotal += luminance;
          leftCount += 1;
        } else {
          rightTotal += luminance;
          rightCount += 1;
        }
        if (y < height / 2) {
          topTotal += luminance;
          topCount += 1;
        } else {
          bottomTotal += luminance;
          bottomCount += 1;
        }
        if (luminance < 58) darkPixels += 1;
        if (luminance > 210) brightPixels += 1;
      }
    }

    if (count == 0) return const _LightingFrameSummary.empty();

    final mean = total / count;
    var variance = 0.0;
    for (final sample in samples) {
      final delta = sample - mean;
      variance += delta * delta;
    }
    variance /= samples.length;

    return _LightingFrameSummary(
      mean: mean,
      contrast: math.sqrt(variance),
      darkRatio: darkPixels / count,
      brightRatio: brightPixels / count,
      leftMean: leftCount == 0 ? mean : leftTotal / leftCount,
      rightMean: rightCount == 0 ? mean : rightTotal / rightCount,
      topMean: topCount == 0 ? mean : topTotal / topCount,
      bottomMean: bottomCount == 0 ? mean : bottomTotal / bottomCount,
    );
  }

  _LightingFrameSummary _summarizeDecodedImage(img.Image image) {
    final stepX = math.max(1, image.width ~/ 36);
    final stepY = math.max(1, image.height ~/ 36);
    var total = 0.0;
    var leftTotal = 0.0;
    var rightTotal = 0.0;
    var topTotal = 0.0;
    var bottomTotal = 0.0;
    var count = 0;
    var leftCount = 0;
    var rightCount = 0;
    var topCount = 0;
    var bottomCount = 0;
    var darkPixels = 0;
    var brightPixels = 0;
    final samples = <double>[];

    for (var y = 0; y < image.height; y += stepY) {
      for (var x = 0; x < image.width; x += stepX) {
        final pixel = image.getPixel(x, y);
        final luminance =
            (0.299 * pixel.r) + (0.587 * pixel.g) + (0.114 * pixel.b);
        samples.add(luminance);
        total += luminance;
        count += 1;
        if (x < image.width / 2) {
          leftTotal += luminance;
          leftCount += 1;
        } else {
          rightTotal += luminance;
          rightCount += 1;
        }
        if (y < image.height / 2) {
          topTotal += luminance;
          topCount += 1;
        } else {
          bottomTotal += luminance;
          bottomCount += 1;
        }
        if (luminance < 54) darkPixels += 1;
        if (luminance > 218) brightPixels += 1;
      }
    }

    if (count == 0) {
      return const _LightingFrameSummary.empty();
    }

    final mean = total / count;
    var variance = 0.0;
    for (final sample in samples) {
      final delta = sample - mean;
      variance += delta * delta;
    }
    variance /= samples.length;

    return _LightingFrameSummary(
      mean: mean,
      contrast: math.sqrt(variance),
      darkRatio: darkPixels / count,
      brightRatio: brightPixels / count,
      leftMean: leftCount == 0 ? mean : leftTotal / leftCount,
      rightMean: rightCount == 0 ? mean : rightTotal / rightCount,
      topMean: topCount == 0 ? mean : topTotal / topCount,
      bottomMean: bottomCount == 0 ? mean : bottomTotal / bottomCount,
    );
  }

  String _buildLightingInstruction(
    _LightingFrameSummary summary, {
    required bool tooDark,
  }) {
    final horizontalDelta = summary.leftMean - summary.rightMean;
    final verticalDelta = summary.topMean - summary.bottomMean;

    if (tooDark) {
      if (horizontalDelta > 18) {
        return 'Move closer to a window and brighten the right side of the frame.';
      }
      if (horizontalDelta < -18) {
        return 'Move closer to a window and brighten the left side of the frame.';
      }
      if (verticalDelta > 20) {
        return 'Lift the light source slightly or reduce overhead shadow on the lower face/body.';
      }
      return 'Move closer to a window and keep soft front light evenly across the treatment area.';
    }

    if (horizontalDelta > 20) {
      return 'Soften shadows on the right side and reduce strong light from the left.';
    }
    if (horizontalDelta < -20) {
      return 'Soften shadows on the left side and reduce strong light from the right.';
    }
    if (verticalDelta.abs() > 22) {
      return 'Reduce overhead glare and aim for softer front lighting.';
    }
    return 'Diffuse the light slightly and reduce strong highlights for more reliable comparison.';
  }

  String get _liveAlignmentInstruction {
    if (_lightingGuidance.level == LightingLevel.tooDark ||
        _lightingGuidance.level == LightingLevel.tooHarsh) {
      return _lightingGuidance.instruction;
    }
    if (_liveLandmarkAssessment.available) {
      return _liveLandmarkAssessment.primaryInstruction;
    }
    if (_showGhostOverlay && _referenceImagePath != null) {
      if (_isBodyGuide) {
        if (_selectedPoseTemplate == 'Front') {
          return 'Align with ghost and straighten shoulders before capture.';
        }
        if (_selectedPoseTemplate.contains('Side')) {
          return 'Match the ghost profile and keep hips stacked vertically.';
        }
        if (_selectedPoseTemplate == 'Back') {
          return 'Center the back view and keep shoulders level with the ghost.';
        }
        return 'Rotate until your body contour matches the ghost outline.';
      }
      if (_selectedPoseTemplate == 'Front') {
        return 'Align eyes, nose, and chin with the ghost for the closest match.';
      }
      if (_selectedPoseTemplate.contains('Profile')) {
        return 'Turn to profile and keep chin level with the ghost outline.';
      }
      return 'Rotate until the cheek and nose line match the ghost overlay.';
    }
    return _isBodyGuide
        ? 'Keep posture neutral and center the treatment area inside the guide.'
        : 'Keep a neutral expression and center the face inside the outline.';
  }

  String get _liveAlignmentSecondary {
    if (_liveLandmarkAssessment.available) {
      final poseMatch = _liveLandmarkAssessment.poseSimilarity.round().clamp(
        0,
        100,
      );
      return '${_liveLandmarkAssessment.secondaryInstruction} Landmark match $poseMatch%.';
    }
    if (_referenceImagePath != null) {
      return 'Match distance, framing, and camera height before capturing.';
    }
    return 'Capture one strong baseline photo first to unlock more exact ghost matching.';
  }

  void _cycleGuidance() {
    setState(() {
      _currentTipIndex = (_currentTipIndex + 1) % _guidanceTips.length;
    });
  }

  Future<void> _showPhotoGuide() async {
    final isBodyGuide = _isBodyGuide;
    final bodyModePoint = switch (_selectedBodyCaptureMode) {
      BodyCaptureMode.mirror =>
        'Mirror mode: phone at chest height, arm extended toward the mirror — step back for real depth',
      BodyCaptureMode.assisted =>
        'Assisted mode: photographer holds the phone steady at chest height, facing away from the light',
      BodyCaptureMode.timer =>
        'Timer mode: prop the phone level at chest height before starting the countdown',
      null => null,
    };
    final correctPoints = isBodyGuide
        ? [
            if (bodyModePoint != null) bodyModePoint,
            'Keep the full treatment area centered inside the body outline',
            'Stand upright with even front lighting and a neutral stance',
            'Match distance, clothing coverage, and camera height each time',
          ]
        : const [
            'Keep your face centered inside the outline with forehead and chin fully visible',
            'Use even front lighting with no hard shadows across the cheeks or eyes',
            'Match your angle, expression, and camera distance each time',
          ];
    final incorrectPoints = isBodyGuide
        ? const [
            'Twisted torso, cropped hips, or framing only one side of the body',
            'Overhead shadows, backlighting, or bright glare across the treatment area',
            'Different stance, zoom level, or loose clothing that hides contour changes',
          ]
        : const [
            'Tilted angle, cropped forehead, or off-center framing',
            'Overhead shadows, strong side light, or bright glare on the skin',
            'Smiling, turning your head, or moving much closer or farther away',
          ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.08),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: MyApp.goldShimmer.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_enhance_outlined,
                        color: MyApp.goldShimmer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Photo Guide', style: MyApp.pageTitleStyle()),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 240,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CameraExampleImageCard(
                        guideType: _guideType,
                        title: 'Good example',
                        caption: correctPoints.join(' '),
                        isGood: true,
                      ),
                      const SizedBox(width: 12),
                      CameraExampleImageCard(
                        guideType: _guideType,
                        title: 'Bad example',
                        caption: incorrectPoints.join(' '),
                        isGood: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: MyApp.primaryGoldButton,
                    child: const Text('Close Guide'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<String> _buildProcedurePhotoSummaryPaths(
    List<ScanHistoryEntry> history,
    String procedureId,
  ) {
    final procedureScans =
        history
            .where((entry) => entry.procedureId == procedureId)
            .where((entry) => (entry.imagePath ?? '').trim().isNotEmpty)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (procedureScans.isEmpty) {
      return const [];
    }

    final latestPath = procedureScans.first.imagePath!;
    final baselinePath = procedureScans.last.imagePath!;
    if (baselinePath == latestPath) {
      return [baselinePath];
    }
    return [baselinePath, latestPath];
  }

  Procedure _buildUpdatedProcedurePhotoSummary({
    required Procedure currentProc,
    required List<ScanHistoryEntry> history,
    required String procedureId,
    required Uint8List latestBytes,
  }) {
    final summaryPaths = _buildProcedurePhotoSummaryPaths(history, procedureId);
    if (kIsWeb) {
      return currentProc.copyWith(
        taggedPhotos: summaryPaths,
        beforePhotoBytes: null,
        afterPhotoBytes: null,
      );
    }

    final hasBaseline =
        currentProc.beforePhotoBytes != null &&
        currentProc.beforePhotoBytes!.isNotEmpty;
    final baselineBytes = hasBaseline
        ? currentProc.beforePhotoBytes
        : latestBytes;
    final hasProgressPhoto = summaryPaths.length > 1;

    return currentProc.copyWith(
      taggedPhotos: summaryPaths,
      beforePhotoBytes: baselineBytes,
      afterPhotoBytes: hasProgressPhoto ? latestBytes : null,
    );
  }

  /// Shows the Cropper.js dialog for web. Creates a temporary blob URL from
  /// [bytes], launches the image_cropper dialog so the user can select a
  /// skin patch, then returns the cropped bytes. Returns null if the user
  /// cancels the crop.
  Future<Uint8List?> _cropWebBytes(Uint8List bytes) async {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImageCropDialog(imageBytes: bytes),
    );
  }

  Future<String> _persistScanImage(
    Uint8List bytes, {
    String? sourcePath,
    required String prefix,
  }) async {
    if (kIsWeb) {
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${docsDir.path}${Platform.pathSeparator}scans');
    if (!await scansDir.exists()) {
      await scansDir.create(recursive: true);
    }

    final extension = (() {
      final normalized = (sourcePath ?? '').replaceAll('\\', '/');
      final dot = normalized.lastIndexOf('.');
      if (dot == -1 || dot == normalized.length - 1) return '.jpg';
      final raw = normalized.substring(dot).toLowerCase();
      if (raw == '.jpeg' || raw == '.jpg' || raw == '.png') return raw;
      return '.jpg';
    })();

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final entropy = math.Random().nextInt(1 << 32).toRadixString(16);
    final file = File(
      '${scansDir.path}${Platform.pathSeparator}${prefix}_${timestamp}_$entropy$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Appends one timestamped line per burst frame to
  /// `<app documents dir>/burst_luminance.log`, alongside the existing
  /// [BURST_LUMINANCE] debugPrint — logging only, never read back by the
  /// app itself. Best-effort: a write failure must not break capture.
  ///
  /// [source] identifies which capture path produced these frames --
  /// "liveCamera" for `_captureFromLiveCamera`, "aiSkinAnalysis" for
  /// `_captureAiSkinAnalysisFrames`. The two paths capture under different
  /// conditions (single vs. multi-frame flows) and are separate measurement
  /// series sharing one log file; every line must carry this tag so the two
  /// series can be told apart when reading the file back later. There is no
  /// default — every call site must pass one explicitly.
  ///
  /// [extraFields], when given, must have one entry per frame (same order
  /// as [luminances]) and is appended verbatim to the end of that frame's
  /// line, after the existing fields -- used by aiSkinAnalysis to log EXIF
  /// exposure metadata without changing liveCamera's line format at all.
  Future<void> _appendBurstLuminanceLogLine(
    List<double?> luminances, {
    required String source,
    List<String>? extraFields,
  }) async {
    if (kIsWeb) return;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final logFile = File(
        '${docsDir.path}${Platform.pathSeparator}burst_luminance.log',
      );
      final timestamp = DateTime.now().toIso8601String();
      final lines = StringBuffer();
      for (var i = 0; i < luminances.length; i++) {
        final extra = (extraFields != null && i < extraFields.length)
            ? ' ${extraFields[i]}'
            : '';
        lines.writeln(
          '$timestamp source=$source frame=$i luminance=${luminances[i]}$extra',
        );
      }
      await logFile.writeAsString(
        lines.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      debugPrint('[BURST_LUMINANCE] failed to append log file: $e');
    }
  }

  /// Reads EXIF exposure metadata directly from one aiSkinAnalysis burst
  /// frame's own JPEG bytes -- logging only, so a later burst-to-burst
  /// comparison can tell an exposure change (auto-exposure/ISO drift)
  /// apart from a framing change. Never used for cropping, frame
  /// selection, or anything sent to analysis.
  ///
  /// Each value is logged exactly as the `image` package's EXIF reader
  /// returns it -- a rational as e.g. "1/60", a double as that double --
  /// never rounded or reformatted, with "null" when the tag is missing or
  /// unreadable. [brightnessValue] is the EXIF APEX BrightnessValue tag, a
  /// separate field from this file's luminance= that must never be merged
  /// or compared against it in code.
  ///
  /// Also returns the still's decoded pixel width/height (null if the
  /// bytes didn't decode) -- reusing this function's own existing decode
  /// rather than adding a second one, purely so the burst log can record
  /// still_w/still_h alongside the EXIF fields.
  ({String fields, int? stillWidth, int? stillHeight})
  _burstFrameExifAndStillSize(Uint8List bytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }
    final exif = decoded?.exif;
    String? readTag(int tag) {
      final value = exif?.exifIfd[tag] ?? exif?.getTag(tag);
      if (value == null) return null;
      switch (value.type) {
        case img.IfdValueType.rational:
        case img.IfdValueType.sRational:
          // Both IfdValueRational and IfdValueSRational format their own
          // toString() as "numerator/denominator" (e.g. "1/60" or "-1/3");
          // toRational() is NOT used here because IfdValueSRational (unlike
          // IfdValueRational) doesn't override it and would silently return
          // the abstract base's Rational(0, 1) stub for every signed value
          // (ExposureBiasValue, BrightnessValue) -- verified against the
          // image package's own source (ifd_value.dart) for this pinned
          // version.
          return value.toString();
        case img.IfdValueType.single:
        case img.IfdValueType.double:
          return value.toDouble().toString();
        default:
          return value.toInt().toString();
      }
    }

    // 0x829A ExposureTime, 0x8827 ISOSpeedRatings/PhotographicSensitivity
    // (same tag; readers label it differently, logged once here as iso=),
    // 0x9204 ExposureBiasValue, 0x9203 BrightnessValue.
    final exposureTime = readTag(0x829A);
    final iso = readTag(0x8827);
    final exposureBias = readTag(0x9204);
    final brightnessValue = readTag(0x9203);
    return (
      fields:
          'exposure_time=$exposureTime iso=$iso '
          'exposure_bias=$exposureBias brightness_value=$brightnessValue',
      stillWidth: decoded?.width,
      stillHeight: decoded?.height,
    );
  }

  // ── Deep Analysis flow (Premium gated + disclaimer + backend) ────────────
  Future<void> _handleDeepAnalysis() async {
    // 1. A cropped image is mandatory — ONLY cropped bytes are ever sent.
    if (_croppedImageBytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please capture and crop a photo first.'),
            backgroundColor: AppColors.softTerracotta,
          ),
        );
      }
      return;
    }

    // 2. Premium gate.
    if (_premiumStatusLoading) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checking your membership status...'),
            backgroundColor: AppColors.champagneGold,
          ),
        );
      }
      return;
    }

    if (!_hasPremiumAccess) {
      final bool? shouldSubscribe = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Premium Feature'),
          content: const Text(
            'Deep Analysis uses our advanced AI models and is available to Premium members.\n\n'
            'Upgrade to unlock unlimited analysis, richer progress tracking, and provider-ready insights.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Maybe Later'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Upgrade to Premium'),
            ),
          ],
        ),
      );
      if (shouldSubscribe == true) {
        if (!mounted) return;
        final navigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        final unlocked = await navigator.pushNamed('/paywall');
        await _refreshPremiumStatus();
        if (!mounted) return;
        if (_hasPremiumAccess || unlocked == true) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Premium unlocked. You can continue with Deep Analysis.',
              ),
              backgroundColor: AppColors.mutedSage,
            ),
          );
          if (_consentAccepted) {
            await _handleDeepAnalysis();
          }
        }
      }
      return;
    }

    // 3. Hard consent gate — must be accepted before any backend call.
    if (!_consentAccepted) {
      final accepted = await _showDeepAnalysisConsent();
      if (accepted != true) return;
    }

    // 4. Start analysis with loading state
    if (mounted) setState(() => _isAnalyzing = true);

    try {
      final deepFile = XFile.fromData(
        _croppedImageBytes!,
        name: 'deep_analysis_${DateTime.now().millisecondsSinceEpoch}.jpg',
        mimeType: 'image/jpeg',
      );

      final postOpDays = _postOpDaysForBackend();
      final safetyFields = await _buildSafetySignalFields();
      final baselineMetricMatrix = _baselineMetricMatrix();

      final fields = <String, String>{
        if ((widget.procedure?.type ?? '').trim().isNotEmpty)
          'procedure_type': widget.procedure!.type.trim(),
        if (postOpDays != null) 'days_post_op': postOpDays,
        if ((_lastCaptureQualityTag ?? '').trim().isNotEmpty)
          'capture_quality': _lastCaptureQualityTag!.trim(),
        if ((_scanCustomDescription ?? '').trim().isNotEmpty)
          'skin_profile_note': (_scanCustomDescription ?? '').trim(),
        if ((_focusAreaForSave ?? '').trim().isNotEmpty)
          'selected_skin_profile_note': (_focusAreaForSave ?? '').trim(),
        ...safetyFields,
      };

      dynamic result;
      try {
        result =
            await local_skin_analysis.SkinAnalysisService.uploadSingleImageFile(
              image: deepFile,
              fields: fields,
              baselineMetricMatrix: baselineMetricMatrix,
            );
      } catch (_) {
        // Fallback to legacy JSON-bytes route where multipart is unavailable.
        result =
            await local_skin_analysis.SkinAnalysisService.analyzeImageFromBytes(
              _croppedImageBytes!,
              filename: deepFile.name,
              baselineMetricMatrix: baselineMetricMatrix,
            );
      }

      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      debugPrint('[DeepAnalysis] Result: $result');
      final resultMap = _normalizeDeepAnalysisResult(result);
      final status = resultMap['status']?.toString().toLowerCase();
      final isSuccess =
          resultMap['success'] == true ||
          status == null ||
          status == 'success' ||
          status == 'ok' ||
          status == 'completed';

      if (isSuccess) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SkinAiAnalysisResultsScreen(
              analysisResult: resultMap,
              croppedImageBytes: _croppedImageBytes,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              resultMap['message']?.toString() ??
                  'Analysis could not be completed.',
            ),
            backgroundColor: AppColors.softTerracotta,
          ),
        );
      }
    } catch (e) {
      debugPrint('[DeepAnalysis] Failed: $e');
      if (!mounted) return;
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Analysis failed: ${e.toString()}'),
          backgroundColor: AppColors.softTerracotta,
        ),
      );
    }
  }

  Map<String, dynamic> _normalizeDeepAnalysisResult(dynamic result) {
    final root = result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{'status': 'success', 'analysis': result};

    final nestedMetrics = (() {
      final raw = root['metrics'];
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return <String, dynamic>{};
    })();

    final normalized = Map<String, dynamic>.from(root);
    if (nestedMetrics.isNotEmpty) {
      normalized['metrics'] = nestedMetrics;
    }

    final trendDeltas =
        normalized['trend_deltas'] ?? nestedMetrics['trend_deltas'];
    if (trendDeltas is Map) {
      normalized['trend_deltas'] = Map<String, dynamic>.from(trendDeltas);
    }

    final metricMatrix =
        normalized['metric_matrix'] ?? nestedMetrics['metric_matrix'];
    if (metricMatrix is Map) {
      normalized['metric_matrix'] = Map<String, dynamic>.from(metricMatrix);
    }

    return normalized;
  }

  /// Non-dismissible pre-analysis consent. Returns true only when the user
  /// explicitly taps "I Understand and Continue", and records [_consentAccepted]
  /// so the Deep Analysis button unlocks. Uses cautious, non-diagnostic language.
  Future<bool> _showDeepAnalysisConsent() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.health_and_safety_outlined,
                  color: AppColors.champagneGold,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Before you continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _deepConsentBullet(
                  Icons.info_outline_rounded,
                  'This is not medical advice',
                  'Deep Analysis does not diagnose any condition and is not a '
                      'substitute for a licensed dermatologist or physician.',
                ),
                _deepConsentBullet(
                  Icons.auto_awesome_outlined,
                  'Personal cosmetic tracking only',
                  'Results are estimates generated from your photo to help you '
                      'observe and track changes over time \u2014 not to make '
                      'treatment decisions.',
                ),
                _deepConsentBullet(
                  Icons.lock_outline_rounded,
                  'Your photo stays private',
                  'Only the cropped image is sent for processing and it is '
                      'deleted immediately afterwards.',
                ),
                _deepConsentBullet(
                  Icons.local_hospital_outlined,
                  'Seek professional care',
                  'For any concern, changing or painful lesion, or a '
                      'persistent symptom, please consult a qualified '
                      'healthcare professional.',
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: MyApp.clinicalSlate,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.champagneGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'I Understand and Continue',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      setState(() => _consentAccepted = true);
    }
    return accepted == true;
  }

  Widget _deepConsentBullet(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: MyApp.clinicalTeal),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: MyApp.clinicalNavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: MyApp.textBrown.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<SkinMetrics> _metricsFromBackendOrThrow(String imagePath) async {
    final raw = await local_skin_analysis.SkinAnalysisService.instance
        .runFullAnalysis(imagePath);

    if (raw.isEmpty) {
      return SkinMetrics.simulatedScan(
        previous: _referenceScan?.toSkinMetrics(),
      );
    }

    double readScore(List<String> keys, {double fallback = 5.0}) {
      for (final key in keys) {
        final value = raw[key];
        if (value == null) continue;
        final parsed = double.tryParse(value.toString());
        if (parsed == null) continue;
        if (parsed <= 1.0) return (parsed * 10.0).clamp(0.0, 10.0);
        if (parsed <= 10.0) return parsed.clamp(0.0, 10.0);
        return (parsed / 10.0).clamp(0.0, 10.0);
      }
      return fallback.clamp(0.0, 10.0);
    }

    final previous = _referenceScan?.toSkinMetrics() ?? const SkinMetrics();
    final redness = readScore([
      'redness',
      'rosacea_intensity',
    ], fallback: previous.redness);
    final texture = readScore(['texture'], fallback: previous.texture);
    final wrinkle = readScore(['wrinkle'], fallback: previous.wrinkle);
    final pore = readScore(['acne_severity', 'pore'], fallback: previous.pore);
    final darkSpots = readScore([
      'pigment',
      'dark_spots',
    ], fallback: previous.darkSpots);
    final elasticity = (10.0 - texture).clamp(0.0, 10.0);

    return SkinMetrics(
      redness: redness,
      texture: texture,
      wrinkle: wrinkle,
      pore: pore,
      darkSpots: darkSpots,
      elasticity: elasticity,
      date: DateTime.now(),
    );
  }

  /// Premium Deep Analysis block: a top disclaimer, the consent gate, and the
  /// gated Run button. The button stays disabled until a cropped image exists
  /// AND the disclaimer has been accepted.
  Widget _buildDeepAnalysisSection() {
    final hasCrop = _croppedImageBytes != null;
    final needsPremium = !_premiumStatusLoading && !_hasPremiumAccess;
    final canRun =
        hasCrop &&
        !_isAnalyzing &&
        !_premiumStatusLoading &&
        (_hasPremiumAccess ? _consentAccepted : true);
    final gateAccent = _consentAccepted
        ? AppColors.mutedSage
        : AppColors.champagneGold;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MyApp.clinicalNavy.withValues(alpha: 0.04),
            AppColors.champagneGold.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.30),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: AppColors.champagneGold,
              ),
              const SizedBox(width: 7),
              Text(
                'AI DEEP ANALYSIS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: MyApp.clinicalNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'AI-assisted observations for personal cosmetic tracking only. Premium unlocks the full analysis flow and richer progress insights.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: MyApp.textBrown.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MyApp.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    (_premiumStatusLoading
                            ? MyApp.clinicalSlate
                            : needsPremium
                            ? AppColors.softTerracotta
                            : hasCrop
                            ? AppColors.mutedSage
                            : AppColors.champagneGold)
                        .withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _premiumStatusLoading
                      ? Icons.hourglass_top_rounded
                      : needsPremium
                      ? Icons.workspace_premium_outlined
                      : hasCrop
                      ? Icons.check_circle_outline_rounded
                      : Icons.crop_free_rounded,
                  size: 18,
                  color: _premiumStatusLoading
                      ? MyApp.clinicalSlate
                      : needsPremium
                      ? AppColors.softTerracotta
                      : hasCrop
                      ? AppColors.mutedSage
                      : AppColors.champagneGold,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _premiumStatusLoading
                            ? 'Checking access'
                            : needsPremium
                            ? 'Premium required'
                            : hasCrop
                            ? 'Photo ready for analysis'
                            : 'Capture and crop a photo first',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: MyApp.clinicalNavy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _premiumStatusLoading
                            ? 'Verifying your membership so the correct analysis options appear.'
                            : needsPremium
                            ? 'Unlock unlimited Deep Analysis, richer recovery insights, and report-ready results.'
                            : hasCrop
                            ? 'Your cropped image is ready. Review the disclaimer once, then run analysis.'
                            : 'Deep Analysis only runs on a cropped image so results stay focused and private.',
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: MyApp.textBrown.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: (!hasCrop || _consentAccepted || needsPremium)
                  ? null
                  : _showDeepAnalysisConsent,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: gateAccent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: gateAccent.withValues(alpha: 0.45),
                    width: 0.9,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _consentAccepted
                          ? Icons.verified_rounded
                          : Icons.shield_outlined,
                      color: gateAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _consentAccepted
                                ? 'Disclaimer accepted'
                                : 'Review the analysis disclaimer',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: gateAccent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            !hasCrop
                                ? 'Capture and crop a photo first.'
                                : needsPremium
                                ? 'Upgrade to Premium to unlock the analysis flow.'
                                : _consentAccepted
                                ? 'You can run Deep Analysis below. Tap to read again.'
                                : 'Required before analysis. Tap to read and accept.',
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.35,
                              color: MyApp.textBrown.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_consentAccepted)
                      TextButton(
                        onPressed: _showDeepAnalysisConsent,
                        child: Text(
                          'View',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: gateAccent,
                          ),
                        ),
                      )
                    else if (hasCrop)
                      Icon(Icons.chevron_right_rounded, color: gateAccent),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: canRun ? _handleDeepAnalysis : null,
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.analytics_rounded, size: 18),
              label: Text(
                _isAnalyzing
                    ? 'Analyzing\u2026'
                    : needsPremium
                    ? 'Unlock Premium to Analyze'
                    : 'Run AI Analysis',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.champagneGold,
                foregroundColor: Colors.white,
                disabledBackgroundColor: MyApp.clinicalSlate.withValues(
                  alpha: 0.25,
                ),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (_isAnalyzing) ...[
            const SizedBox(height: 8),
            Text(
              'This usually takes 10-20 seconds. Keep the app open while we process your cropped photo.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: MyApp.clinicalSlate,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 12,
                color: MyApp.clinicalSlate.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Not a diagnosis and not a substitute for professional '
                  'medical advice. Always consult a qualified healthcare '
                  'professional for any concern.',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.4,
                    color: MyApp.clinicalSlate,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Reliable Web Gallery Picker (exact pattern that works in scar_healing_tracker) ──
  void _triggerWebGalleryPicker() {
    String? procedureIdToSave;
    String? productNameToSave;

    debugPrint(
      '[WEB PICKER] isSkincareScan=${widget.isSkincareScan} procedure=${widget.procedure?.id} selectedProcedureId=$_selectedProcedureId productName=${widget.productName}',
    );

    if (widget.isSkincareScan &&
        widget.productName != null &&
        widget.productName!.isNotEmpty) {
      productNameToSave = widget.productName;
    } else if (!widget.isSkincareScan) {
      final procedureId = widget.procedure?.id ?? _selectedProcedureId;
      if (procedureId == null || procedureId.isEmpty) {
        // Still open picker — save will prompt for procedure selection
        debugPrint('[WEB PICKER] No procedure ID — will open picker anyway');
      } else {
        procedureIdToSave = procedureId;
      }
    }

    setState(() {
      _capturing = true;
      _croppedImageBytes = null;
    });
    openWebImagePicker((bytes) async {
      debugPrint('[WEB PICKER] complete, bytes=${bytes?.length}');
      try {
        if (bytes == null || bytes.isEmpty) {
          if (mounted) setState(() => _capturing = false);
          return;
        }
        final sourceImage = img.decodeImage(bytes);
        final sourceImageWidth = sourceImage?.width;
        final sourceImageHeight = sourceImage?.height;

        final prepared = await prepareWebUploadImage(bytes);
        if (!prepared.isSuccess) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(prepared.errorMessage!)));
          }
          return;
        }

        final workingBytes = prepared.image!.bytes;
        if (!mounted) return;
        Uint8List? croppedBytes;
        try {
          croppedBytes = await _cropWebBytes(workingBytes);
        } catch (e) {
          debugPrint('[WEB PICKER] crop failed, using original bytes: $e');
          croppedBytes = workingBytes;
        }
        if (croppedBytes == null) {
          if (mounted) setState(() => _capturing = false);
          return;
        }
        if (mounted) setState(() => _croppedImageBytes = croppedBytes);
        await _saveWebGalleryBytes(
          croppedBytes,
          procedureIdToSave,
          productNameToSave,
          sourceImageWidth,
          sourceImageHeight,
        );
      } catch (e) {
        debugPrint('[WEB PICKER] exception: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'We could not process the selected image. Please choose a valid photo file and try again.',
              ),
            ),
          );
        }
      } finally {
        if (mounted && _capturing) {
          setState(() => _capturing = false);
        }
      }
    });
  }

  void _triggerGalleryPicker() {
    if (kIsWeb) {
      _triggerWebGalleryPicker();
      return;
    }
    _pickAndSavePhoto(source: ImageSource.gallery);
  }

  Future<void> _saveWebGalleryBytes(
    Uint8List bytes,
    String? procedureIdToSave,
    String? productNameToSave,
    int? sourceImageWidth,
    int? sourceImageHeight,
  ) async {
    final resolvedProcedureId = !widget.isSkincareScan
        ? (procedureIdToSave?.trim().isNotEmpty == true
              ? procedureIdToSave!.trim()
              : (widget.procedure?.id ??
                    _selectedProcedureId ??
                    await AppPrefs.resolveActiveProcedureId()))
        : null;

    if (!widget.isSkincareScan &&
        (resolvedProcedureId == null || resolvedProcedureId.isEmpty)) {
      debugPrint(
        '[_saveWebGalleryBytes] ERROR: Procedure scan but no procedureId!',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a procedure first.')),
        );
      }
      return;
    }

    debugPrint(
      '[_saveWebGalleryBytes] START bytes.length=${bytes.length} procedureIdToSave=$resolvedProcedureId productNameToSave=$productNameToSave isSkincareScan=${widget.isSkincareScan}',
    );

    // Same mirror un-flip as the native capture path (_pickAndSavePhoto) —
    // must happen before storage/landmark/backend use of `bytes` below.
    if (_isBodyGuide) {
      bytes = flipForStorageIfMirror(bytes, _selectedBodyCaptureMode);
    }

    final bytesForStorage = kIsWeb ? _prepareWebStorageBytes(bytes) : bytes;
    final imagePathToSave = await _persistScanImage(
      bytesForStorage,
      sourcePath: null,
      prefix: 'procedure_scan',
    );
    final nextMetrics = await _metricsFromBackendOrThrow(imagePathToSave);
    // Track Procedure is local-only for every region. Body silhouette data
    // remains absent until a genuine on-device implementation is available.
    const Map<String, dynamic>? bodySilhouettePayload = null;
    try {
      debugPrint(
        '[_saveWebGalleryBytes] imagePathToSave length=${imagePathToSave.length}, originalBytes=${bytes.length}, storedBytes=${bytesForStorage.length}',
      );
      List<ScanHistoryEntry> updatedHistory = const [];

      debugPrint('[_saveWebGalleryBytes] _cycleGuidance() starting');
      _cycleGuidance();
      debugPrint('[_saveWebGalleryBytes] _cycleGuidance() done');

      final liveLighting = _analyzeLighting(bytes);
      debugPrint(
        '[_saveWebGalleryBytes] liveLighting analyzed, level=${liveLighting.level}',
      );
      final lightingConfidence = kIsWeb
          ? _lightingConfidenceFromGuidance(liveLighting)
          : _estimateLightingConfidence(bytes);
      debugPrint(
        '[_saveWebGalleryBytes] lightingConfidence=$lightingConfidence',
      );

      debugPrint('[_saveWebGalleryBytes] analyzeCapturedLandmarks() starting');
      final capturedLandmarks = kIsWeb
          ? await analyzeCapturedLandmarks(
              bytes: bytes,
              filePath: null,
              isBody: _isBodyGuide,
              poseTemplate: _selectedPoseTemplate,
            ).timeout(
              const Duration(seconds: 4),
              onTimeout: () {
                debugPrint(
                  '[_saveWebGalleryBytes] analyzeCapturedLandmarks timeout on web, using unsupported fallback',
                );
                return LandmarkAssessment.unsupported;
              },
            )
          : await analyzeCapturedLandmarks(
              bytes: bytes,
              filePath: null,
              isBody: _isBodyGuide,
              poseTemplate: _selectedPoseTemplate,
            );
      debugPrint(
        '[_saveWebGalleryBytes] analyzeCapturedLandmarks() done, available=${capturedLandmarks.available}',
      );

      if (mounted) {
        setState(() {
          _lightingGuidance = liveLighting;
          if (capturedLandmarks.available) {
            _liveLandmarkAssessment = capturedLandmarks;
          }
        });
        debugPrint(
          '[_saveWebGalleryBytes] setState after landmark analysis done',
        );
      }

      debugPrint('[_saveWebGalleryBytes] nextMetrics created');

      final consistencyScore = _calculateConsistencyScore(
        bytes,
        nextMetrics,
        landmarkAssessment: capturedLandmarks,
      );
      debugPrint('[_saveWebGalleryBytes] consistencyScore=$consistencyScore');

      final preferredReference =
          liveLighting.level == LightingLevel.optimal &&
          lightingConfidence >= 0.72 &&
          (!capturedLandmarks.available ||
              capturedLandmarks.landmarkQuality >= 0.76) &&
          consistencyScore >= 84;
      _lastConsistencyScore = consistencyScore;
      debugPrint(
        '[_saveWebGalleryBytes] preferredReference=$preferredReference',
      );

      if (widget.isSkincareScan) {
        debugPrint('[_saveWebGalleryBytes] Saving skincare scan');
        updatedHistory = await AppPrefs.addScanMetric(
          nextMetrics,
          procedureId: null,
          productName: productNameToSave,
          imagePath: imagePathToSave,
          calibrationRecord: _currentTrackProcedureCalibrationRecord(),
          poseTemplate: _selectedPoseTemplate,
          focusArea: _focusAreaForSave,
          customDescription: _customDescriptionForSave,
          lightingConfidence: lightingConfidence,
          preferredReference: preferredReference,
            extraMetrics: _captureProvenanceMetrics(capturedLandmarks),
            bodyReferenceGeometry: _isTrackProcedureFlow
              ? capturedLandmarks.bodyReferenceGeometry
              : null,
              faceReferenceGeometry: _isTrackProcedureFlow
                ? capturedLandmarks.faceReferenceGeometry
                : null,
          makeupPresent: _makeupPresent ?? false,
          distanceEstimate: _distanceEstimate(),
          headTiltAngle: _isBodyGuide ? _bodyTiltAngle() : _headTiltAngle(),
          expressionConfidence: _expressionConfidence(),
          captureMode: _isBodyGuide
              ? _selectedBodyCaptureMode?.storageValue
              : null,
            sourceImageWidth: sourceImageWidth,
            sourceImageHeight: sourceImageHeight,
          rawPayload: bodySilhouettePayload,
        );
        debugPrint(
          '[_saveWebGalleryBytes] skincare scan saved, updatedHistory.length=${updatedHistory.length}',
        );
      } else {
        debugPrint(
          '[_saveWebGalleryBytes] Saving procedure scan, procedureIdToSave=$resolvedProcedureId',
        );
        updatedHistory = await AppPrefs.addScanMetric(
          nextMetrics,
          procedureId: resolvedProcedureId,
          productName: null,
          imagePath: imagePathToSave,
          calibrationRecord: _currentTrackProcedureCalibrationRecord(),
          poseTemplate: _selectedPoseTemplate,
          focusArea: _focusAreaForSave,
          customDescription: _customDescriptionForSave,
          lightingConfidence: lightingConfidence,
          preferredReference: preferredReference,
            extraMetrics: _captureProvenanceMetrics(capturedLandmarks),
            bodyReferenceGeometry: _isTrackProcedureFlow
              ? capturedLandmarks.bodyReferenceGeometry
              : null,
              faceReferenceGeometry: _isTrackProcedureFlow
                ? capturedLandmarks.faceReferenceGeometry
                : null,
          makeupPresent: _makeupPresent ?? false,
          distanceEstimate: _distanceEstimate(),
          headTiltAngle: _isBodyGuide ? _bodyTiltAngle() : _headTiltAngle(),
          expressionConfidence: _expressionConfidence(),
          captureMode: _isBodyGuide
              ? _selectedBodyCaptureMode?.storageValue
              : null,
            sourceImageWidth: sourceImageWidth,
            sourceImageHeight: sourceImageHeight,
          rawPayload: bodySilhouettePayload,
        );
        debugPrint(
          '[_saveWebGalleryBytes] procedure scan saved, updatedHistory.length=${updatedHistory.length}',
        );

        final proceduresJson = await AppPrefs.getProcedureEntries();
        final idx = proceduresJson.indexWhere(
          (p) => (p['id'] ?? '') == resolvedProcedureId,
        );
        debugPrint('[_saveWebGalleryBytes] proceduresJson idx=$idx');
        if (idx == -1) {
          throw Exception('Procedure not found for ID: $resolvedProcedureId');
        }
        Procedure currentProc = Procedure.fromJson(
          Map<String, dynamic>.from(proceduresJson[idx]),
        );
        final updatedProc = _buildUpdatedProcedurePhotoSummary(
          currentProc: currentProc,
          history: updatedHistory,
          procedureId: resolvedProcedureId!,
          latestBytes: bytes,
        );
        proceduresJson[idx] = updatedProc.toJson();
        debugPrint(
          '[_saveWebGalleryBytes] procedure updated in proceduresJson',
        );
        try {
          await AppPrefs.saveProcedureHistory(proceduresJson);
        } catch (e) {
          if (!kIsWeb || !e.toString().contains('QuotaExceededError')) {
            rethrow;
          }
          debugPrint(
            '[_saveWebGalleryBytes] Quota exceeded, compacting procedure history and retrying',
          );
          for (final procedure in proceduresJson) {
            procedure.remove('beforePhotoBytes');
            procedure.remove('afterPhotoBytes');
            procedure['taggedPhotos'] =
                ((procedure['taggedPhotos'] as List?) ?? const [])
                    .map((e) => e.toString())
                    .toList();
          }
          await AppPrefs.saveProcedureHistory(proceduresJson);
        }
        debugPrint('[_saveWebGalleryBytes] saveProcedureHistory done');
      }

      String? premiumInsightText;
      final isPremium = await PremiumAccess.isPremiumUser();
      debugPrint(
        '[_saveWebGalleryBytes] isPremium=$isPremium, updatedHistory.length=${updatedHistory.length}',
      );
      if (isPremium && updatedHistory.length >= 2) {
        debugPrint('[_saveWebGalleryBytes] Processing premium insights');
        final sorted = List<ScanHistoryEntry>.from(updatedHistory)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        final insight =
            await PremiumRecoveryService.autoAnalyzeLatestProgressFromHistory(
              sorted,
            );
        await PremiumRecoveryService.autoGenerateFuturePredictionFromHistory(
          sorted,
        );
        await PremiumRecoveryService.buildSmartRemindersFromLatestScan(sorted);
        premiumInsightText = insight?.summary;
        debugPrint('[_saveWebGalleryBytes] Premium insights done');
      }

      final affirmation = _affirmations[_lastAffirmationIndex];
      _lastAffirmationIndex =
          (_lastAffirmationIndex + 1) % _affirmations.length;

      if (mounted) {
        debugPrint('[_saveWebGalleryBytes] Widget is mounted, showing UI');
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        debugPrint('[_saveWebGalleryBytes] About to play success burst');
        await _playSuccessBurst();
        debugPrint('[_saveWebGalleryBytes] Success burst done');
        if (!mounted) {
          debugPrint(
            '[_saveWebGalleryBytes] Widget unmounted after success burst, returning early',
          );
          return;
        }
        debugPrint(
          '[_saveWebGalleryBytes] About to show consistency result sheet, score=$consistencyScore',
        );
        await _showConsistencyResultSheet(
          score: consistencyScore,
          premiumInsightText: premiumInsightText,
        );
        debugPrint('[_saveWebGalleryBytes] Consistency sheet closed');
        if (!mounted) {
          debugPrint(
            '[_saveWebGalleryBytes] Widget unmounted after consistency sheet, returning early',
          );
          return;
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(affirmation),
            duration: const Duration(seconds: 4),
          ),
        );
        debugPrint('[_saveWebGalleryBytes] Affirmation snackbar shown');
        await _loadReferenceContext();
        debugPrint('[_saveWebGalleryBytes] Reference context loaded');
        if (!mounted) {
          debugPrint(
            '[_saveWebGalleryBytes] Widget unmounted after loading context, returning early',
          );
          return;
        }
        debugPrint('[_saveWebGalleryBytes] About to pop navigator');
        navigator.pop(true);
        debugPrint('[_saveWebGalleryBytes] Navigator popped');
      } else {
        debugPrint(
          '[_saveWebGalleryBytes] Widget NOT mounted, skipping UI updates',
        );
      }
    } catch (e) {
      debugPrint('[_saveWebGalleryBytes] Exception caught: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save photo: $e')));
      }
    } finally {
      debugPrint(
        '[_saveWebGalleryBytes] Finally block, setting _capturing=false',
      );
      if (mounted) setState(() => _capturing = false);
    }
  }

  // ── Mobile / camera photo picker ──────────────────────────────────────────
  Future<void> _pickAndSavePhoto({
    ImageSource source = ImageSource.camera,
    String? captureQuality,
  }) async {
    if (source == ImageSource.gallery) {
      // Reset current selection; it becomes valid again only after crop success.
      setState(() {
        _capturing = true;
        _croppedImageBytes = null;
      });
    } else {
      setState(() => _capturing = true);
    }

    String? procedureIdToSave;
    String? productNameToSave;

    if (widget.isSkincareScan) {
      productNameToSave = widget.productName?.trim().isNotEmpty == true
          ? widget.productName!.trim()
          : null;
    } else {
      final procedureId =
          widget.procedure?.id ??
          _selectedProcedureId ??
          await AppPrefs.resolveActiveProcedureId();
      if (procedureId == null || procedureId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a procedure before taking a scan.'),
            ),
          );
        }
        setState(() => _capturing = false);
        return;
      }
      procedureIdToSave = procedureId;
    }

    try {
      final XFile? pickedFile = source == ImageSource.gallery
          ? await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            )
          : await _captureFromLiveCamera();

      if (pickedFile == null) {
        if (mounted && source == ImageSource.gallery) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No photo was selected.')),
          );
        }
        setState(() => _capturing = false);
        return;
      }

      String? selectedCaptureQuality = captureQuality;
      if (source == ImageSource.camera) {
        selectedCaptureQuality = await _resolveSelectedFrameCaptureQuality(
          pickedFile,
        );
        _lastCaptureQualityTag = selectedCaptureQuality;
      }

      // ── Manual crop: let the user select a focused skin patch ──────────
      final rawBytes = await pickedFile.readAsBytes();
      final sourceImage = img.decodeImage(rawBytes);
      final sourceImageWidth = sourceImage?.width;
      final sourceImageHeight = sourceImage?.height;
      if (!mounted) {
        setState(() => _capturing = false);
        return;
      }
      final croppedBytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            ImageCropDialog(imageBytes: Uint8List.fromList(rawBytes)),
      );
      if (croppedBytes == null) {
        // User cancelled the cropper
        if (mounted) setState(() => _capturing = false);
        return;
      }
      // Mirror captures are a front-camera view of the user's reflection —
      // left-right flipped relative to how they'd appear to someone facing
      // them directly. Flip back to a normal (un-mirrored) orientation here,
      // before anything downstream (persisted file, landmark analysis,
      // backend metrics) ever sees the bytes, so mirror/assisted/timer
      // scans are all analyzed in the same orientation.
      final bytes = _isBodyGuide
          ? flipForStorageIfMirror(croppedBytes, _selectedBodyCaptureMode)
          : croppedBytes;
      final imagePathToSave = await _persistScanImage(
        bytes,
        sourcePath: pickedFile.path,
        prefix: widget.isSkincareScan ? 'skincare_scan' : 'procedure_scan',
      );
      if (mounted) setState(() => _croppedImageBytes = bytes);

      List<ScanHistoryEntry> updatedHistory = const [];
      _cycleGuidance();

      final liveLighting = _analyzeLighting(bytes);
      final lightingConfidence = _estimateLightingConfidence(bytes);
      final capturedLandmarks = await analyzeCapturedLandmarks(
        bytes: bytes,
        filePath: imagePathToSave,
        isBody: _isBodyGuide,
        poseTemplate: _selectedPoseTemplate,
      );
      if (mounted) {
        setState(() {
          _lightingGuidance = liveLighting;
          if (capturedLandmarks.available) {
            _liveLandmarkAssessment = capturedLandmarks;
          }
        });
      }

      final nextMetrics = await _metricsFromBackendOrThrow(imagePathToSave);
      // Runs alongside _metricsFromBackendOrThrow, not instead of it — see
      // the matching comment in _saveWebGalleryBytes.
      // Track Procedure is local-only for every region. Body silhouette data
      // remains absent until a genuine on-device implementation is available.
      const Map<String, dynamic>? bodySilhouettePayload = null;
      final consistencyScore = _calculateConsistencyScore(
        bytes,
        nextMetrics,
        landmarkAssessment: capturedLandmarks,
      );
      final preferredReference =
          liveLighting.level == LightingLevel.optimal &&
          lightingConfidence >= 0.72 &&
          (!capturedLandmarks.available ||
              capturedLandmarks.landmarkQuality >= 0.76) &&
          consistencyScore >= 84;
      _lastConsistencyScore = consistencyScore;

      if (widget.isSkincareScan) {
        updatedHistory = await AppPrefs.addScanMetric(
          nextMetrics,
          procedureId: null,
          productName: productNameToSave,
          imagePath: imagePathToSave,
          calibrationRecord: _currentTrackProcedureCalibrationRecord(),
          poseTemplate: _selectedPoseTemplate,
          focusArea: _focusAreaForSave,
          customDescription: _customDescriptionForSave,
          lightingConfidence: lightingConfidence,
          preferredReference: preferredReference,
            extraMetrics: _captureProvenanceMetrics(capturedLandmarks),
            bodyReferenceGeometry: _isTrackProcedureFlow
              ? capturedLandmarks.bodyReferenceGeometry
              : null,
              faceReferenceGeometry: _isTrackProcedureFlow
                ? capturedLandmarks.faceReferenceGeometry
                : null,
          makeupPresent: _makeupPresent ?? false,
          distanceEstimate: _distanceEstimate(),
          headTiltAngle: _isBodyGuide ? _bodyTiltAngle() : _headTiltAngle(),
          expressionConfidence: _expressionConfidence(),
          captureQuality: selectedCaptureQuality,
          captureMode: _isBodyGuide
              ? _selectedBodyCaptureMode?.storageValue
              : null,
            sourceImageWidth: sourceImageWidth,
            sourceImageHeight: sourceImageHeight,
          rawPayload: bodySilhouettePayload,
        );
      } else {
        updatedHistory = await AppPrefs.addScanMetric(
          nextMetrics,
          procedureId: procedureIdToSave,
          productName: null,
          imagePath: imagePathToSave,
          calibrationRecord: _currentTrackProcedureCalibrationRecord(),
          poseTemplate: _selectedPoseTemplate,
          focusArea: _focusAreaForSave,
          customDescription: _customDescriptionForSave,
          lightingConfidence: lightingConfidence,
          preferredReference: preferredReference,
            extraMetrics: _captureProvenanceMetrics(capturedLandmarks),
            bodyReferenceGeometry: _isTrackProcedureFlow
              ? capturedLandmarks.bodyReferenceGeometry
              : null,
              faceReferenceGeometry: _isTrackProcedureFlow
                ? capturedLandmarks.faceReferenceGeometry
                : null,
          makeupPresent: _makeupPresent ?? false,
          distanceEstimate: _distanceEstimate(),
          headTiltAngle: _isBodyGuide ? _bodyTiltAngle() : _headTiltAngle(),
          expressionConfidence: _expressionConfidence(),
          captureQuality: selectedCaptureQuality,
          captureMode: _isBodyGuide
              ? _selectedBodyCaptureMode?.storageValue
              : null,
            sourceImageWidth: sourceImageWidth,
            sourceImageHeight: sourceImageHeight,
          rawPayload: bodySilhouettePayload,
        );

        final proceduresJson = await AppPrefs.getProcedureEntries();
        final idx = proceduresJson.indexWhere(
          (p) => (p['id'] ?? '') == procedureIdToSave,
        );
        if (idx == -1) throw Exception('Procedure not found');
        Procedure currentProc = Procedure.fromJson(
          Map<String, dynamic>.from(proceduresJson[idx]),
        );
        final updatedProc = _buildUpdatedProcedurePhotoSummary(
          currentProc: currentProc,
          history: updatedHistory,
          procedureId: procedureIdToSave!,
          latestBytes: bytes,
        );
        proceduresJson[idx] = updatedProc.toJson();
        await AppPrefs.saveProcedureHistory(proceduresJson);
      }

      String? premiumInsightText;
      final isPremium = await PremiumAccess.isPremiumUser();
      if (isPremium && updatedHistory.length >= 2) {
        final sorted = List<ScanHistoryEntry>.from(updatedHistory)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        final insight =
            await PremiumRecoveryService.autoAnalyzeLatestProgressFromHistory(
              sorted,
            );
        await PremiumRecoveryService.autoGenerateFuturePredictionFromHistory(
          sorted,
        );
        await PremiumRecoveryService.buildSmartRemindersFromLatestScan(sorted);
        premiumInsightText = insight?.summary;
      }

      final affirmation = _affirmations[_lastAffirmationIndex];
      _lastAffirmationIndex =
          (_lastAffirmationIndex + 1) % _affirmations.length;

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        await _playSuccessBurst();
        if (!mounted) return;
        await _showConsistencyResultSheet(
          score: consistencyScore,
          premiumInsightText: premiumInsightText,
        );
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(affirmation),
            duration: const Duration(seconds: 4),
          ),
        );
        await _loadReferenceContext();
        if (!mounted) return;

        if (widget.isSkincareScan) {
          navigator.pop(imagePathToSave);
          return;
        }
        navigator.pop(true);
      }
    } catch (e) {
      debugPrint('Photo save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  double _sharpnessFromImageBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return 0;

    final gray = img.grayscale(decoded);
    final width = gray.width;
    final height = gray.height;
    if (width < 6 || height < 6) return 0;

    const step = 2;
    var count = 0;
    var sum = 0.0;
    var sumSq = 0.0;

    for (var y = 1; y < height - 1; y += step) {
      for (var x = 1; x < width - 1; x += step) {
        final center = gray.getPixel(x, y).r.toDouble();
        final left = gray.getPixel(x - 1, y).r.toDouble();
        final right = gray.getPixel(x + 1, y).r.toDouble();
        final up = gray.getPixel(x, y - 1).r.toDouble();
        final down = gray.getPixel(x, y + 1).r.toDouble();

        final lap = (4 * center) - left - right - up - down;
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }

    if (count == 0) return 0;
    final mean = sum / count;
    final variance = (sumSq / count) - (mean * mean);
    return variance.isFinite ? variance.clamp(0.0, 5000.0) : 0.0;
  }

  double _burstFrameScoreFromPreview({required double sharpness}) {
    final assessment = _liveLandmarkAssessment;
    final centerDelta = assessment.available
        ? assessment.centerOffsetX.abs() + assessment.centerOffsetY.abs()
        : 0.25;
    final pitchPenalty = assessment.available && assessment.pitch != null
        ? assessment.pitch!.abs() / 30.0
        : 0.0;
    final alignmentScore = (1.0 - (centerDelta.clamp(0.0, 0.35) / 0.35)).clamp(
      0.0,
      1.0,
    );
    final pitchScore = (1.0 - pitchPenalty.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    final exposureScore = _lightingGuidance.level == LightingLevel.optimal
        ? 1.0
        : 0.6;

    return (sharpness / 75.0) +
        (alignmentScore * 6.0) +
        (pitchScore * 4.0) +
        exposureScore;
  }

  Future<String> _resolveSelectedFrameCaptureQuality(XFile file) async {
    final bytes = await file.readAsBytes();
    final sharpness = _sharpnessFromImageBytes(bytes);
    final pitch = _liveLandmarkAssessment.pitch;
    if (pitch != null && pitch.abs() > _pitchWarnThresholdDegrees) {
      return 'poor_angle';
    }
    if (sharpness > 0 && sharpness < _sharpnessVarianceFloor) {
      return 'blurry';
    }
    final lowLight =
        _lightingGuidance.level == LightingLevel.tooDark ||
        (_liveFaceRoiLuma > 0
            ? _liveFaceRoiLuma < _lightingThresholds.darkMeanFloor
            : _liveMeanBrightness < _lightingThresholds.darkMeanFloor);
    if (lowLight) return 'low_light';
    if (_isLightDirectionUneven) return 'uneven_lighting';
    return 'normal';
  }

  Future<XFile?> _captureFromLiveCamera() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      final reason = controller == null
          ? 'controller_null'
          : 'controller_not_initialized';
      debugPrint(
        'CAPTURE_FALLBACK: using gallery picker instead of camera, reason=$reason',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Live camera unavailable. Opening Gallery...'),
        ),
      );
      return _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    }
    if (controller.value.isTakingPicture) return null;

    final burstFiles = <XFile>[];

    try {
      if (_lightingStreamActive && !kIsWeb) {
        await controller.stopImageStream();
        _lightingStreamActive = false;
      }

      try {
        await controller.setExposureMode(ExposureMode.locked);
      } catch (e) {
        debugPrint('Camera exposure lock unsupported; continuing capture: $e');
      }

      await Future<void>.delayed(const Duration(milliseconds: 200));

      for (var i = 0; i < 3; i++) {
        final file = await controller.takePicture();
        burstFiles.add(file);
        if (i < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 110));
        }
      }

      if (burstFiles.isEmpty) return null;

      var bestFile = burstFiles.first;
      var bestScore = double.negativeInfinity;
      // Logging-only: per-frame mean luminance, purely for observability.
      // No measured luminance noise floor exists anywhere in this codebase
      // (checked METRIC_NOISE_FLOOR_2SD/tool/analyze_repeatability.py and
      // _lightingThresholds, which are tuned classification bounds, not
      // statistically-measured repeatability floors) to derive a real
      // keep/drop band from, and backward-deriving one from an unrelated
      // metric's score formula (e.g. redness's a*-unit floor) is invalid —
      // brightness doesn't pass through that formula. This must NOT affect
      // which frame gets selected below.
      final burstLuminances = <double?>[];
      for (final file in burstFiles) {
        final bytes = await file.readAsBytes();
        final sharpness = _sharpnessFromImageBytes(bytes);
        final score = _burstFrameScoreFromPreview(sharpness: sharpness);
        if (score > bestScore) {
          bestScore = score;
          bestFile = file;
        }
        burstLuminances.add(meanLuminanceFromImageBytes(bytes));
      }
      debugPrint('[BURST_LUMINANCE] source=liveCamera frames=$burstLuminances (logging only, selection unaffected)');
      await _appendBurstLuminanceLogLine(burstLuminances, source: 'liveCamera');

      for (final file in burstFiles) {
        if (file.path == bestFile.path) continue;
        try {
          final discardFile = File(file.path);
          if (await discardFile.exists()) {
            await discardFile.delete();
          }
        } catch (_) {
          // Best-effort cleanup only; do not fail the capture.
        }
      }

      return bestFile;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      return null;
    } finally {
      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint('Camera exposure reset unsupported: $e');
      }
      _startLightingStream(controller);
    }
  }

  Future<void> _captureAiSkinAnalysisFrames() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Live camera unavailable.')),
        );
      }
      return;
    }
    if (controller.value.isTakingPicture) return;

    if (mounted) setState(() => _capturing = true);
    final capturedFiles = <XFile>[];
    try {
      if (_lightingStreamActive && !kIsWeb) {
        await controller.stopImageStream();
        _lightingStreamActive = false;
      }

      try {
        await controller.setExposureMode(ExposureMode.locked);
      } catch (e) {
        debugPrint('AI burst exposure lock unsupported: $e');
      }

      await Future<void>.delayed(const Duration(milliseconds: 200));
      for (var index = 0; index < 3; index++) {
        capturedFiles.add(await controller.takePicture());
        if (index < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 110));
        }
      }
      if (!mounted || capturedFiles.length != 3) return;

      // Logging-only: per-frame mean luminance, purely for observability.
      // Must NOT affect frame selection or anything passed to analysis --
      // capturedFiles, their order, and every downstream use of them are
      // untouched by this block. See _appendBurstLuminanceLogLine for why
      // "aiSkinAnalysis" must tag every line here.
      final burstLuminances = <double?>[];
      final burstExifFields = <String>[];
      final burstStillWidths = <int?>[];
      final burstStillHeights = <int?>[];
      for (final file in capturedFiles) {
        final bytes = await file.readAsBytes();
        burstLuminances.add(meanLuminanceFromImageBytes(bytes));
        final exifAndSize = _burstFrameExifAndStillSize(bytes);
        burstExifFields.add(exifAndSize.fields);
        burstStillWidths.add(exifAndSize.stillWidth);
        burstStillHeights.add(exifAndSize.stillHeight);
      }

      final firstBytes = await capturedFiles.first.readAsBytes();
      if (!mounted) return;

      // Auto-crop around the detected face when possible, so a normal
      // arm's-length selfie doesn't default to a full-width square that
      // undershoots the backend's face-fill floor -- and skips the manual
      // crop dialog entirely in that case. Detection runs on the SAME
      // decoded (already upright) pixels the crop is cut from -- see
      // detectPrimaryFaceBoxOnDecodedImage's doc comment for why the raw
      // JPEG bytes are never used directly for this. Falls back to
      // showing ImageCropDialog with its existing full-width default
      // whenever the still fails to decode or no face is found -- never
      // blocks or alters capture, and never touches frame selection/
      // anything sent to analysis.
      NormalizedSquareCrop? autoRegion;
      try {
        final decodedFirst = img.decodeImage(firstBytes);
        if (decodedFirst != null) {
          final faceBox = await detectPrimaryFaceBoxOnDecodedImage(
            decodedFirst,
          );
          if (faceBox != null) {
            autoRegion = faceCenteredInitialCropSquare(
              faceLeft: faceBox.left,
              faceTop: faceBox.top,
              faceWidth: faceBox.width,
              faceHeight: faceBox.height,
              stillWidth: decodedFirst.width.toDouble(),
              stillHeight: decodedFirst.height.toDouble(),
            );
          }
        }
      } catch (e) {
        debugPrint('[AiScanCropPreset] face-centered crop preset failed: $e');
      }
      if (!mounted) return;

      final resolvedCrop = resolveAiScanFrame1Crop(
        firstBytes: firstBytes,
        autoRegion: autoRegion,
      );
      ImageCropSelection? cropSelection = resolvedCrop.selection;
      Uint8List? firstCropped = resolvedCrop.selection?.bytes;
      if (resolvedCrop.showDialog) {
        firstCropped = await showDialog<Uint8List>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ImageCropDialog(
            imageBytes: firstBytes,
            onCropSelected: (selection) => cropSelection = selection,
          ),
        );
      }
      if (!mounted || firstCropped == null || cropSelection == null) return;

      final croppedFrames = <Uint8List>[firstCropped];
      for (final file in capturedFiles.skip(1)) {
        croppedFrames.add(
          applyNormalizedSquareCrop(
            await file.readAsBytes(),
            cropSelection!.region,
          ),
        );
      }

      // Logging-only: per-frame still/crop/upload pixel sizes, appended
      // after the existing exposure-EXIF fields on the same aiSkinAnalysis
      // burst log lines -- written here (once the crop is known) rather
      // than right after capture, since crop_px/upload_w/upload_h don't
      // exist until the crop dialog completes. crop_px/crop_clamped mirror
      // applyNormalizedSquareCrop's own sourceSize/clamp formula (the exact
      // function frames 2-3 are cropped through) against each frame's own
      // still_w/still_h and the region actually selected in the crop
      // dialog; for frame 1 this reconstructs, rather than replays,
      // _doCrop's own internal clamp (which additionally bounds against
      // the crop box's on-screen position, not just the still's shorter
      // side), so it can disagree with _doCrop's own clamp only in the
      // rare case where the user drags the crop box hard against an edge.
      // upload_w/upload_h are not decoded separately -- croppedFrames are
      // always an unresized square crop of exactly crop_px pixels per side
      // (see _doCrop / applyNormalizedSquareCrop), and nothing resizes
      // them before upload, so upload_w = upload_h = crop_px by
      // construction. Must NOT affect frame selection or anything passed
      // to analysis -- capturedFiles, croppedFrames, their order, and
      // every downstream use of them are untouched by this block.
      final burstSizeFields = <String>[];
      for (var i = 0; i < capturedFiles.length; i++) {
        final stillW = burstStillWidths[i];
        final stillH = burstStillHeights[i];
        String sizeFields;
        if (stillW == null || stillH == null) {
          sizeFields =
              'still_w=null still_h=null crop_px=null crop_clamped=null '
              'upload_w=null upload_h=null';
        } else {
          final sourceSize = math.min(stillW, stillH);
          final rawCropPx = (cropSelection!.region.size * sourceSize).round();
          final cropPx = rawCropPx.clamp(1, sourceSize);
          final cropClamped = cropPx != rawCropPx;
          sizeFields =
              'still_w=$stillW still_h=$stillH crop_px=$cropPx '
              'crop_clamped=$cropClamped upload_w=$cropPx upload_h=$cropPx';
        }
        burstSizeFields.add('${burstExifFields[i]} $sizeFields');
      }
      debugPrint(
        '[BURST_LUMINANCE] source=aiSkinAnalysis frames=$burstLuminances (logging only, selection unaffected)',
      );
      await _appendBurstLuminanceLogLine(
        burstLuminances,
        source: 'aiSkinAnalysis',
        extraFields: burstSizeFields,
      );

      final primaryImagePath = await _persistScanImage(
        croppedFrames.first,
        sourcePath: capturedFiles.first.path,
        prefix: 'ai_skin_analysis_frame_1',
      );

      final captureQuality = await _resolveSelectedFrameCaptureQuality(
        capturedFiles.first,
      );
      _lastCaptureQualityTag = captureQuality;

      if (!mounted) return;
      Navigator.of(context).pop(
        AiSkinAnalysisCaptureResult(
          primaryImagePath: primaryImagePath,
          croppedFrames: List<Uint8List>.unmodifiable(croppedFrames),
          captureQuality: captureQuality,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Multi-frame capture failed: $e')),
        );
      }
    } finally {
      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint('AI burst exposure reset unsupported: $e');
      }
      _startLightingStream(controller);
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    if (_lightingStreamActive && !kIsWeb) {
      _cameraController?.stopImageStream();
    }
    closeLandmarkAnalyzers();
    _autoCaptureTimer?.cancel();
    _timerCaptureTimer?.cancel();
    _cameraController?.dispose();
    _shimmerController.dispose();
    _successController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web fallback: no live camera — patient supplies a still image instead.
      // We surface the clinical disclosure status and a deliberate
      // "Select Test Image from Computer" path for desktop QA.
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: MyApp.clinicalNavy),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 56,
                    color: MyApp.clinicalTeal.withValues(alpha: 0.85),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Progress scan upload',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MyApp.textBrown,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Live camera capture is best on a phone. On this device, '
                    'upload a still photo and the same AI-powered analysis will run.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MyApp.textBrown.withValues(alpha: 0.72),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const ClinicalSectionHeader(
                    icon: Icons.photo_camera_rounded,
                    eyebrow: 'STEP 1',
                    title: 'Choose a photo',
                  ),
                  const SizedBox(height: 10),

                  // ── Disclosure status and controls ──────────────────────
                  if (_makeupPresent == true)
                    const Center(child: MakeupBadge())
                  else if (_makeupPresent == false)
                    const _CleanFaceConfirmedChip()
                  else
                    const SizedBox.shrink(),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _capturing
                        ? null
                        : () async {
                            final result = await MakeupDisclosureDialog.show(
                              context,
                            );
                            if (!mounted || result == null) return;
                            setState(() => _makeupPresent = result);
                          },
                    icon: const Icon(Icons.face_retouching_natural, size: 18),
                    label: const Text('Update pre-scan disclosure'),
                    style: MyApp.secondaryOutlineButton(),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.photo_camera_rounded),
                          label: const Text('Take Photo'),
                          style: MyApp.secondaryOutlineButton(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _capturing
                              ? null
                              : () => _triggerGalleryPicker(),
                          icon: const Icon(Icons.photo_library_rounded),
                          label: Text(
                            _capturing ? 'Opening...' : 'Choose from Gallery',
                          ),
                          style: MyApp.primaryGoldButton,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Camera capture is available from the mobile scan screen; gallery upload is enabled here for fast testing.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MyApp.textBrown.withValues(alpha: 0.58),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: _showPhotoGuide,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Photo Guide'),
                    style: TextButton.styleFrom(
                      foregroundColor: MyApp.clinicalTeal,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ── Mobile camera UI (live preview + clinical-grade guidance) ────────
    return _buildMobileCameraBody(context);
  }

  // ───────────────────────────────────────────────────────────────────────
  // Clinical quality + auto-capture helpers
  // ───────────────────────────────────────────────────────────────────────

  /// Numeric estimate (0..1) of how well-framed the subject is, derived
  /// from landmark detection quality and centring offset.
  double? _distanceEstimate() {
    final a = _liveLandmarkAssessment;
    if (!a.available) return null;
    final centring =
        1.0 - (a.centerOffsetX.abs() + a.centerOffsetY.abs()).clamp(0.0, 1.0);
    return (a.landmarkQuality * 0.7 + centring * 0.3).clamp(0.0, 1.0);
  }

  /// Aggregate head-tilt magnitude in degrees. Lower = more neutral.
  /// Face mode only — [_assessBody] never populates yaw/pitch/roll/eyeTilt,
  /// so this always falls into the rotationProxy fallback for body
  /// assessments, which is meaningless there (rotationProxy is a
  /// shoulder/hip width ratio, not an angle). Use [_bodyTiltAngle] instead
  /// for body mode.
  double? _headTiltAngle() => headTiltAngleFromAssessment(_liveLandmarkAssessment);

  /// Body-mode tilt magnitude in degrees, using the actual shoulder-line
  /// angle relative to horizontal ([LandmarkAssessment.shoulderTilt]) —
  /// a genuine tilt measurement, unlike rotationProxy (shoulder/hip width
  /// ratio), which has no angular meaning and was never intended as a
  /// tilt proxy for body poses.
  double? _bodyTiltAngle() => bodyTiltAngleFromAssessment(_liveLandmarkAssessment);

  /// Synthesised pose-acceptability confidence (0..1), persisted with the
  /// scan record and averaged into procedure_profiles_screen's
  /// comparison-confidence label — not a transient display-only value, so
  /// this must use a genuine tilt measurement per mode, same as Alignment.
  /// High when a face/body is detected with neutral pose and good
  /// landmark quality.
  double? _expressionConfidence() {
    final a = _liveLandmarkAssessment;
    if (!a.available) return null;
    if (_isBodyGuide) {
      final tilt = _bodyTiltAngle() ?? 0.0;
      // Same ratio as face mode below (red threshold ⇒ ~2/3 penalty):
      // face's 40° red threshold sits at 40/60 of its zero-credit ceiling,
      // so body's 15° red threshold scales to a 22.5° ceiling.
      final tiltPenalty = (tilt / 22.5).clamp(0.0, 1.0);
      return (a.landmarkQuality * (1.0 - tiltPenalty * 0.6)).clamp(0.0, 1.0);
    }
    final tilt = _headTiltAngle() ?? 0.0;
    final tiltPenalty = (tilt / 60.0).clamp(0.0, 1.0); // 60°+ ⇒ zero credit
    return (a.landmarkQuality * (1.0 - tiltPenalty * 0.6)).clamp(0.0, 1.0);
  }

  bool _isAlignmentInRange() {
    final a = _liveLandmarkAssessment;
    if (!a.available) return false;
    final centerDelta = a.centerOffsetX.abs() + a.centerOffsetY.abs();
    final tilt = _headTiltAngle() ?? 999.0;
    final pitch = a.pitch ?? 0.0;
    final yaw = a.yaw ?? 0.0;
    final roll = a.roll ?? 0.0;
    print(
      '[FRONTEND LIVE POSE] pitch=${pitch.toStringAsFixed(2)} yaw=${yaw.toStringAsFixed(2)} tilt=${tilt.toStringAsFixed(2)} roll=${roll.toStringAsFixed(2)} centerDelta=${centerDelta.toStringAsFixed(3)}',
    );
    return centerDelta <= 0.25 && tilt <= 30.0;
  }

  bool _isCaptureFramingReady(ClinicalQualityReport report) {
    // Body capture guidance is intentionally warning-only: the overlay can coach
    // framing, but body photos should never be blocked by a slightly cropped or
    // offset frame. Keep the strict face gate unchanged.
    if (_isBodyGuide) {
      return true;
    }

    // Scale / distance and lighting are intentionally passive here: they can
    // guide the user, but they must never block a photo. The true capture gates
    // remain face-centering and alignment.
    return _isLiveFacePresentAndCentered() &&
        _isAlignmentInRange() &&
      report.headAngle.state == QualityState.green;
  }

  /// Debug-only (see [_buildDebugFramingOverlay]): names exactly which of
  /// _isCaptureFramingReady's three ANDed conditions is currently false,
  /// and — for the two custom predicates — which specific check inside it
  /// is the one failing. Calls the real predicates for the pass/fail
  /// decision itself (so this can never disagree with the actual gate);
  /// it only re-derives the underlying numbers to explain *why*, which is
  /// pure read-only formatting, not gating logic.
  String _debugFramingFailureReason(ClinicalQualityReport report) {
    if (_isBodyGuide) return 'body guide — always ready (face gate not applied)';

    if (!_isLiveFacePresentAndCentered()) {
      final a = _liveLandmarkAssessment;
      if (!a.available) {
        return '_isLiveFacePresentAndCentered: landmarks not available';
      }
      final centerDelta = a.centerOffsetX.abs() + a.centerOffsetY.abs();
      if (centerDelta > 0.35) {
        return '_isLiveFacePresentAndCentered: centerDelta '
            '${centerDelta.toStringAsFixed(3)} > 0.35';
      }
      final floor = _targetFaceFillFloor * 0.82;
      return '_isLiveFacePresentAndCentered: faceFill '
          '${a.faceFillRatio.toStringAsFixed(3)} < floor*0.82 '
          '(${floor.toStringAsFixed(3)})';
    }

    if (!_isAlignmentInRange()) {
      final a = _liveLandmarkAssessment;
      if (!a.available) return '_isAlignmentInRange: landmarks not available';
      final centerDelta = a.centerOffsetX.abs() + a.centerOffsetY.abs();
      if (centerDelta > 0.25) {
        return '_isAlignmentInRange: centerDelta '
            '${centerDelta.toStringAsFixed(3)} > 0.25';
      }
      final tilt = _headTiltAngle() ?? 999.0;
      return '_isAlignmentInRange: tilt ${tilt.toStringAsFixed(1)}° > 30.0°';
    }

    if (report.headAngle.state != QualityState.green) {
      return 'report.headAngle.state = ${report.headAngle.state.name} '
          '(needs green)';
    }

    return 'READY — all conditions pass';
  }

  bool _isLiveFacePresentAndCentered() {
    final a = _liveLandmarkAssessment;
    if (!a.available) return false;
    final centerDelta = a.centerOffsetX.abs() + a.centerOffsetY.abs();
    if (centerDelta > 0.35) return false;
    final fill = a.faceFillRatio;
    if (fill > 0 && fill < (_targetFaceFillFloor * 0.82)) return false;
    return true;
  }

  double _estimateFaceRoiLumaFromStream(CameraImage image) {
    final yPlane = image.planes.firstOrNull;
    if (yPlane == null || yPlane.bytes.isEmpty) return 0;
    final assessment = _liveLandmarkAssessment;
    if (!assessment.available) return 0;

    // This ROI is sampled directly from the raw CameraImage Y-plane buffer,
    // so it must be positioned/sized using the RAW (pre-mirror, pre-crop-
    // conversion) face box -- never centerOffsetX/Y or faceFillRatio, which
    // are in visible-preview space (mirrored and BoxFit.cover-cropped) and
    // would misplace/mis-scale the ROI against this buffer's own raw pixel
    // space. See faceRoiRectInRawStreamPixels's doc comment. Returns 0 (no
    // sample, same as !available above) whenever this raw geometry isn't
    // present -- e.g. body mode, which has no face box at all.
    final geometry = assessment.faceReferenceGeometry;
    final rawCenterXNorm = geometry?['rawFaceCenterXNorm'];
    final rawCenterYNorm = geometry?['rawFaceCenterYNorm'];
    final rawFaceWidthNorm = geometry?['faceWidthNorm'];
    final rawFaceHeightNorm = geometry?['faceHeightNorm'];
    if (rawCenterXNorm == null ||
        rawCenterYNorm == null ||
        rawFaceWidthNorm == null ||
        rawFaceHeightNorm == null) {
      return 0;
    }

    final bytesPerPixel = _primaryPlaneBytesPerPixel(image, yPlane);
    final width = image.width;
    final height = image.height;
    final rowStride = yPlane.bytesPerRow;
    if (width <= 4 || height <= 4 || rowStride < width * bytesPerPixel) return 0;

    final roi = faceRoiRectInRawStreamPixels(
      rawCenterXNorm: rawCenterXNorm,
      rawCenterYNorm: rawCenterYNorm,
      rawFaceWidthNorm: rawFaceWidthNorm,
      rawFaceHeightNorm: rawFaceHeightNorm,
      width: width,
      height: height,
    );
    final left = roi.left;
    final top = roi.top;
    final right = roi.right;
    final bottom = roi.bottom;
    if (kDebugMode) {
      _debugFaceRoiLeft = left;
      _debugFaceRoiTop = top;
      _debugFaceRoiRight = right;
      _debugFaceRoiBottom = bottom;
    }

    var sum = 0.0;
    var count = 0;
    const step = 4;
    final bytes = yPlane.bytes;
    for (var y = top; y < bottom; y += step) {
      final row = y * rowStride;
      for (var x = left; x < right; x += step) {
        final idx = row + x * bytesPerPixel;
        if (idx + bytesPerPixel > bytes.length) continue;
        sum += _luminanceFromBytes(bytes, idx, bytesPerPixel);
        count++;
      }
    }
    if (count == 0) return 0;
    return sum / count;
  }

  bool _isLowLightWarningActive() {
    final darkFloor = _lightingThresholds.darkMeanFloor;
    return _lightingGuidance.level == LightingLevel.tooDark ||
        (_liveFaceRoiLuma > 0 && _liveFaceRoiLuma < darkFloor);
  }

  // Face pose warnings should show up before capture when the subject is
  // noticeably tilted, but we intentionally allow a little more headroom than
  // the original capture gate so the user can still snap a good photo without
  // chasing nearly-perfect alignment.
  static const double _poseWarnThresholdDegrees = 32.0;

  // Pitch above this magnitude reliably breaks pore_visibility,
  // glabellar_wrinkle_depth, and under_eye metrics server-side (backend
  // pose_ok gate). This is a live, pre-capture warning threshold — kept a bit
  // more forgiving than the original gate so it coaches users without blocking
  // a usable shot.
  static const double _pitchWarnThresholdDegrees = 38.0;

  // Left/right frame luma imbalance above this is treated as "uneven
  // lighting direction." Slightly looser than before so normal room light and
  // camera asymmetry won't prevent capture unless the lighting is clearly off.
  static const double _lightDirectionImbalanceThreshold = 22.0;

  bool get _isPitchOutOfRange {
    final pitch = _liveLandmarkAssessment.pitch;
    if (!_liveLandmarkAssessment.available || pitch == null) return false;
    return pitch.abs() > _pitchWarnThresholdDegrees;
  }

  bool get _isYawOutOfRange {
    final yaw = _liveLandmarkAssessment.yaw;
    if (!_liveLandmarkAssessment.available || yaw == null) return false;
    return yaw.abs() > _poseWarnThresholdDegrees;
  }

  bool get _isFaceFramingOff {
    if (!_liveLandmarkAssessment.available) return false;
    final centerDelta =
        _liveLandmarkAssessment.centerOffsetX.abs() +
        _liveLandmarkAssessment.centerOffsetY.abs();
    return centerDelta > 0.16;
  }

  bool get _isBodyFramingOff {
    if (!_isBodyGuide || !_liveLandmarkAssessment.available) return false;
    final centerDelta =
        _liveLandmarkAssessment.centerOffsetX.abs() +
        _liveLandmarkAssessment.centerOffsetY.abs();
    return centerDelta > 0.18;
  }

  /// Live pose guidance text tuned for the actual face-angle telemetry. This is
  /// what the user sees before pressing capture so they know exactly why the
  /// current frame is not yet ideal.
  String get _livePoseGuidanceText {
    if (_isBodyGuide && _isBodyFramingOff) {
      return 'Step back — full body needed.';
    }

    final pitch = _liveLandmarkAssessment.pitch;
    final yaw = _liveLandmarkAssessment.yaw;

    if (_isPitchOutOfRange && pitch != null) {
      if (pitch > 0) return 'Level your head — lower your chin.';
      return 'Level your head — lift your chin.';
    }

    if (_isYawOutOfRange && yaw != null) {
      if (yaw > 0) return 'Hold phone straight — turn your face slightly left.';
      return 'Hold phone straight — turn your face slightly right.';
    }

    if (_isFaceFramingOff) {
      // _isFaceFramingOff uses a tighter threshold than _isBodyFramingOff
      // (already checked above), so this can still fire in body mode for a
      // delta between the two thresholds — keep the copy body-aware.
      return _isBodyGuide
          ? 'Center your body in the frame.'
          : 'Center your face in the frame.';
    }

    if (_isLowLightWarningActive()) {
      return 'Move to better light for a cleaner scan.';
    }

    if (_isLightDirectionUneven) {
      return 'Light is uneven — face your main light source.';
    }

    if (!_liveLandmarkAssessment.available) {
      return _isBodyGuide
          ? 'Center your body inside the guide.'
          : 'Center your face inside the guide.';
    }

    return 'Position OK';
  }

  /// Live pitch guidance text. Mirrors the sign convention already used by
  /// [LandmarkAssessment.primaryInstruction] (pitch > 0 ⇒ chin is high ⇒
  /// lower it; pitch < 0 ⇒ chin is low ⇒ lift it), just surfaced as its own
  /// always-visible indicator with a dedicated ~20° warning threshold.
  String get _pitchGuidanceLabel {
    final pitch = _liveLandmarkAssessment.pitch;
    if (!_liveLandmarkAssessment.available || pitch == null) {
      return _isBodyGuide
          ? 'Center your body to check angle'
          : 'Center your face to check angle';
    }
    if (pitch > _pitchWarnThresholdDegrees) {
      return 'Tilt your chin down slightly';
    }
    if (pitch < -_pitchWarnThresholdDegrees) {
      return 'Tilt your chin up slightly';
    }
    return 'Level';
  }

  bool get _isLightDirectionUneven =>
      _liveLightHorizontalDelta.abs() > _lightDirectionImbalanceThreshold;

  String _captureQualityForCurrentConditions(ClinicalQualityReport report) {
    if (!_isCaptureFramingReady(report)) {
      return _isBodyGuide ? 'partial_body_framing' : 'face_offcenter';
    }
    final thresholds = _lightingThresholds;
    final lowLight =
        _lightingGuidance.level == LightingLevel.tooDark ||
        (_liveFaceRoiLuma > 0
            ? _liveFaceRoiLuma < thresholds.darkMeanFloor
            : _liveMeanBrightness < thresholds.darkMeanFloor);

    // Priority when multiple issues are present at capture time (most
    // severe first, per the guided-capture investigation findings):
    //   1. face_offcenter / partial_body_framing — warn-only for body, hard
    //      gate for face; this remains the only body-only guidance path.
    //   2. poor_angle — excess pitch reliably breaks pore_visibility,
    //      glabellar_wrinkle_depth, and under_eye metrics outright.
    //   3. low_light — absolute darkness degrades every metric (existing).
    //   4. blurry — motion / focus softness degrades edge detail while still
    //      allowing a usable capture to proceed with a warning-tag.
    //   5. uneven_lighting — directional imbalance mainly destabilizes
    //      under_eye_dark_circle_density; the face is otherwise usably lit,
    //      so this is judged less severe than absolute low light.
    //   6. normal.
    if (_isBodyGuide && _isBodyFramingOff) return 'partial_body_framing';
    if (_isPitchOutOfRange) return 'poor_angle';
    if (lowLight) return 'low_light';
    if (_liveSharpness > 0 && _liveSharpness < _sharpnessVarianceFloor) {
      return 'blurry';
    }
    if (_isLightDirectionUneven) return 'uneven_lighting';
    return 'normal';
  }

  /// Compose the live 4-signal traffic-light report shown above the
  /// capture button.
  ClinicalQualityReport _buildClinicalQualityReport() {
    final hasFace = _liveLandmarkAssessment.available;

    // ── Scale / proximity (passive-only guide; never a hard capture blocker) ─
    // Detection math is unchanged (still driven by face-fill-ratio/landmark
    // signals even in body mode, per the existing _isBodyFramingOff pattern
    // elsewhere in this file) — only the displayed copy branches on
    // _isBodyGuide, since "face" wording was showing up on Body procedure
    // captures regardless of what was actually being framed.
    QualitySignal scale;
    final fill = _liveFaceFillRatio;
    if (!hasFace || fill <= 0) {
      scale = QualitySignal(
        label: 'Scale',
        state: QualityState.yellow,
        detail: _isBodyGuide
            ? 'Center your body inside the frame'
            : 'Center your face inside the mask',
      );
    } else if (fill < _targetFaceFillFloor) {
      scale = QualitySignal(
        label: 'Scale',
        state: QualityState.yellow,
        detail: _isBodyGuide
            ? 'Move closer — body is a bit too far away'
            : 'Move closer — face is a bit too far away',
      );
    } else if (fill > _targetFaceFillCeil) {
      scale = QualitySignal(
        label: 'Scale',
        state: QualityState.yellow,
        detail: _isBodyGuide
            ? 'Move slightly back — body is a bit too close'
            : 'Move slightly back — face is a bit too close',
      );
    } else if (fill < _targetFaceFillFloor * 1.12 ||
        fill > _targetFaceFillCeil * 0.92) {
      scale = const QualitySignal(
        label: 'Scale',
        state: QualityState.yellow,
        detail: 'Adjust distance to the center of the guide',
      );
    } else {
      scale = QualitySignal(
        label: 'Scale',
        state: QualityState.green,
        detail: _isBodyGuide ? 'Body size in target range' : 'Face size in target range',
      );
    }

    // ── Alignment (centering + neutral tilt) ──────────────────────────────
    // Tilt source and thresholds are mode-specific: face uses aggregate
    // head yaw+pitch+roll (30°/40° thresholds), body uses the actual
    // shoulder-line angle (8°/15° thresholds — a single-plane angle is
    // naturally much smaller than a 3-angle sum, and shoulder tilt is
    // visually obvious well before 15°). rotationProxy (shoulder/hip width
    // ratio) is not used here at all — it has no angular meaning and
    // previously made Alignment unreachable-green for anyone with
    // shoulders wider than hips, regardless of actual tilt/centering.
    QualitySignal alignment;
    final double? tilt = _isBodyGuide ? _bodyTiltAngle() : _headTiltAngle();
    final centerDelta =
        _liveLandmarkAssessment.centerOffsetX.abs() +
        _liveLandmarkAssessment.centerOffsetY.abs();
    // Threshold classification is delegated to the pure, unit-tested
    // alignmentQualityStatus() so the red/yellow/green cutoffs used here
    // are covered by an automated test, not just this call site.
    final alignmentStatus = alignmentQualityStatus(
      isBodyGuide: _isBodyGuide,
      tilt: tilt,
      centerDelta: centerDelta,
    );
    if (!hasFace) {
      alignment = QualitySignal(
        label: 'Alignment',
        state: QualityState.red,
        detail: _isBodyGuide
            ? 'Center your body inside the frame'
            : 'Center your face inside the mask',
      );
    } else if (alignmentStatus == QualityState.red) {
      alignment = QualitySignal(
        label: 'Alignment',
        state: QualityState.red,
        detail: _isBodyGuide
            ? 'Center your body inside the frame'
            : 'Center your face inside the mask',
      );
    } else if (alignmentStatus == QualityState.yellow) {
      alignment = QualitySignal(
        label: 'Alignment',
        state: QualityState.yellow,
        detail: _isBodyGuide
            ? 'Straighten and center your body'
            : 'Straighten and center your face',
      );
    } else {
      alignment = QualitySignal(
        label: 'Alignment',
        state: QualityState.green,
        detail: _isBodyGuide
            ? 'Body positioning looks aligned'
            : 'Eyes, nose, and chin are aligned',
      );
    }

    // ── Lighting & luminance/backlight checks ────────────────────────────
    QualitySignal lighting;
    if (_lightingGuidance.level == LightingLevel.tooDark) {
      lighting = const QualitySignal(
        label: 'Lighting',
        state: QualityState.yellow,
        detail: 'Dim light — try a brighter angle or softer front light',
      );
    } else if (_lightingGuidance.level == LightingLevel.tooHarsh ||
        isBacklit(
          faceRoiLuma: _liveFaceRoiLuma,
          wholeFrameMean: _liveMeanBrightness,
          wholeFrameEdgeDelta: _liveBacklightDelta,
          backlightDeltaCeil: _backlightDeltaCeil,
        )) {
      lighting = const QualitySignal(
        label: 'Lighting',
        state: QualityState.yellow,
        detail: 'Harsh backlighting detected',
      );
    } else if (_lightingGuidance.level == LightingLevel.unknown) {
      lighting = const QualitySignal(
        label: 'Lighting',
        state: QualityState.yellow,
        detail: 'Sampling exposure…',
      );
    } else {
      lighting = const QualitySignal(
        label: 'Lighting',
        state: QualityState.green,
        detail: 'Balanced, even lighting',
      );
    }

    // ── Sharpness / blur gate ─────────────────────────────────────────────
    QualitySignal sharpness;
    if (_liveSharpness <= 0) {
      sharpness = const QualitySignal(
        label: 'Sharpness',
        state: QualityState.yellow,
        detail: 'Hold steady while camera calibrates',
      );
    } else if (_liveSharpness < _sharpnessVarianceFloor) {
      sharpness = const QualitySignal(
        label: 'Sharpness',
        state: QualityState.red,
        detail: 'Camera blurry — hold steady',
      );
    } else {
      sharpness = const QualitySignal(
        label: 'Sharpness',
        state: QualityState.green,
        detail: 'Image detail is clear',
      );
    }

    // Priority message: blur -> lighting -> alignment -> scale.
    String primary = 'Ready to capture';
    for (final s in [sharpness, lighting, alignment, scale]) {
      if (s.state == QualityState.red) {
        primary = s.detail;
        break;
      }
    }
    if (primary == 'Ready to capture') {
      for (final s in [sharpness, lighting, alignment, scale]) {
        if (s.state == QualityState.yellow) {
          primary = s.detail;
          break;
        }
      }
    }

    final report = ClinicalQualityReport(
      distance: scale,
      headAngle: alignment,
      lighting: lighting,
      expression: sharpness,
      primaryInstruction: primary,
    );
    _updateQaBannerFromReport(report);
    return report;
  }

  /// Called from the lighting / landmark setState pipeline. Tracks how long
  /// all four signals have been green and kicks off a 3-second auto-capture
  /// countdown after a 2-second stable window.
  void _evaluateAutoCapture(ClinicalQualityReport report) {
    if (_capturing || _captureInProgress) return;
    if (!report.allGreen) {
      if (_qualityGreenSince != null ||
          _autoCaptureCountdown != null ||
          _autoCaptureTimer != null) {
        _qualityGreenSince = null;
        _autoCaptureTimer?.cancel();
        _autoCaptureTimer = null;
        if (mounted && _autoCaptureCountdown != null) {
          setState(() => _autoCaptureCountdown = null);
        } else {
          _autoCaptureCountdown = null;
        }
      }
      return;
    }

    final now = DateTime.now();
    _qualityGreenSince ??= now;
    final stableFor = now.difference(_qualityGreenSince!);
    if (stableFor.inMilliseconds < 2000) return;
    if (_autoCaptureTimer != null) return;

    setState(() => _autoCaptureCountdown = 3);
    _autoCaptureTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = (_autoCaptureCountdown ?? 0) - 1;
      if (next <= 0) {
        t.cancel();
        _autoCaptureTimer = null;
        setState(() => _autoCaptureCountdown = null);
        _handleCaptureTap(auto: true);
      } else {
        setState(() => _autoCaptureCountdown = next);
      }
    });
  }

  /// Unified capture entry point used by the manual button and the
  /// auto-capture timer. Honours the quality gate; if conditions are not
  /// ideal the user must explicitly confirm an override.
  Future<void> _handleCaptureTap({
    bool auto = false,
    bool bypassFramingGate = false,
  }) async {
    if (_captureInProgress || _capturing) return;
    final report = _buildClinicalQualityReport();

    if (!bypassFramingGate && !_isCaptureFramingReady(report)) {
      _updateQaBannerFromReport(report);
      if (!auto && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(report.primaryInstruction),
              duration: const Duration(milliseconds: 1200),
              backgroundColor: AppColors.softTerracotta,
            ),
          );
      }
      return;
    }

    final capturePitch = _liveLandmarkAssessment.pitch ?? 0.0;
    final captureYaw = _liveLandmarkAssessment.yaw ?? 0.0;
    final captureRoll = _liveLandmarkAssessment.roll ?? 0.0;
    final captureFaceFill = _liveLandmarkAssessment.faceFillRatio;
    final captureCenterDelta =
        _liveLandmarkAssessment.centerOffsetX.abs() +
        _liveLandmarkAssessment.centerOffsetY.abs();
    print(
      '[FRONTEND CAPTURE FINAL] pitch=${capturePitch.toStringAsFixed(2)} yaw=${captureYaw.toStringAsFixed(2)} roll=${captureRoll.toStringAsFixed(2)} faceFill=${captureFaceFill.toStringAsFixed(3)} centerDelta=${captureCenterDelta.toStringAsFixed(3)}',
    );

    _captureInProgress = true;
    try {
      final captureQuality = _captureQualityForCurrentConditions(report);
      _lastCaptureQualityTag = captureQuality;
      if (widget.aiMultiFrameCapture) {
        await _captureAiSkinAnalysisFrames();
        return;
      }
      // ImageSource.camera invokes the system camera which honours the
      // platform's hardware capture pipeline. The live preview above has
      // already coached the user into the correct pose. The actual burst
      // selection resolves the final capture_quality from the chosen frame.
      await _pickAndSavePhoto(
        source: ImageSource.camera,
        captureQuality: captureQuality,
      );
    } finally {
      _captureInProgress = false;
      // Reset quality stability so a new countdown starts fresh.
      _qualityGreenSince = null;
      _autoCaptureTimer?.cancel();
      _autoCaptureTimer = null;
      if (mounted) {
        setState(() => _autoCaptureCountdown = null);
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Mobile body
  // ───────────────────────────────────────────────────────────────────────

  Widget _buildMobileCameraBody(BuildContext context) {
    final report = _buildClinicalQualityReport();
    double signalScore(QualityState state) {
      switch (state) {
        case QualityState.green:
          return 1.0;
        case QualityState.yellow:
          return 0.55;
        case QualityState.red:
          return 0.10;
      }
    }

    final alignmentOverlayScore =
        (signalScore(report.distance.state) +
            signalScore(report.headAngle.state)) /
        2.0;
    // Drive the auto-capture state machine off every rebuild — this is fed
    // by setState calls in the lighting / landmark streams which already
    // throttle to roughly 6–10 Hz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _evaluateAutoCapture(report);
    });

    final disclosureBanner = _makeupPresent == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _makeupPresent == true
                ? const MakeupBadge()
                : const _CleanFaceConfirmedChip(),
          );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: MyApp.clinicalNavy),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.isSkincareScan
              ? (widget.productName ?? 'Skincare scan')
              : (_scanProcedureLabel.isEmpty
                    ? 'Progress scan'
                    : _scanProcedureLabel),
          style: TextStyle(
            color: MyApp.clinicalNavy,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Photo guide',
            icon: Icon(Icons.info_outline, color: MyApp.clinicalNavy),
            onPressed: _showPhotoGuide,
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  disclosureBanner,
                  const ClinicalSectionHeader(
                    icon: Icons.photo_camera_rounded,
                    eyebrow: 'STEP 1',
                    title: 'Choose a photo',
                  ),
                  const SizedBox(height: 18),
                  const ClinicalSectionHeader(
                    icon: Icons.center_focus_strong_rounded,
                    eyebrow: 'STEP 2',
                    title: 'Position photo',
                  ),
                  const SizedBox(height: 10),
                  _buildCameraStatusBar(),
                  const SizedBox(height: 12),

                  // ── Live preview with adaptive guide + crosshair overlay ──
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildPlacementGuide(),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _shimmerController,
                              builder: (_, __) => CustomPaint(
                                painter: ClinicalCameraOverlayPainter(
                                  score: alignmentOverlayScore,
                                  pulse: _shimmerController.value,
                                  bodyMode: _isBodyGuide,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Primary live instruction (always mounted) ───────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: MyApp.clinicalNavy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: MyApp.clinicalTeal.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isPitchOutOfRange || _isYawOutOfRange
                              ? Icons.warning_amber_rounded
                              : Icons.center_focus_strong_rounded,
                          color: _isPitchOutOfRange || _isYawOutOfRange
                              ? AppColors.softTerracotta
                              : MyApp.clinicalTeal,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _livePoseGuidanceText,
                            style: TextStyle(
                              color: _isPitchOutOfRange || _isYawOutOfRange
                                  ? AppColors.softTerracotta
                                  : MyApp.clinicalNavy,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ── Quality indicator chips ──────────────────────────────
                  ClinicalQualityIndicators(report: report),

                  // ── Live pitch (tilt) indicator ───────────────────────────
                  // Always visible while a face is detected — a dedicated,
                  // continuously-updating proxy for chin-up/chin-down tilt,
                  // separate from the combined Alignment chip above. Warns
                  // (color/text change) past ~20°; never blocks capture.
                  if (_liveLandmarkAssessment.available)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(
                            _isPitchOutOfRange
                                ? ((_liveLandmarkAssessment.pitch ?? 0) > 0
                                      ? Icons.keyboard_double_arrow_down_rounded
                                      : Icons.keyboard_double_arrow_up_rounded)
                                : Icons.height_rounded,
                            size: 16,
                            color: _isPitchOutOfRange
                                ? AppColors.softTerracotta
                                : AppColors.mutedSage,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _pitchGuidanceLabel,
                            style: TextStyle(
                              color: _isPitchOutOfRange
                                  ? AppColors.softTerracotta
                                  : AppColors.mutedSage,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_isBodyGuide && _isBodyFramingOff)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: AppColors.softTerracotta,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Move further from the camera — full body needed. You can still capture now.',
                              style: TextStyle(
                                color: AppColors.softTerracotta,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_isLowLightWarningActive())
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.wb_sunny_outlined,
                            size: 16,
                            color: AppColors.softTerracotta,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Move to better light for a cleaner scan. You can still capture now.',
                              style: TextStyle(
                                color: AppColors.softTerracotta,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Light-direction (left/right) evenness warning ────────
                  // Independent of the tooDark/tooHarsh lighting level above
                  // — the face can be adequately lit overall while still
                  // being lit unevenly from one side, which is what actually
                  // destabilizes under_eye_dark_circle_density.
                  if (_isLightDirectionUneven)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.flare_outlined,
                            size: 16,
                            color: AppColors.softTerracotta,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Light is uneven — try facing your main light source directly. You can still capture now.',
                              style: TextStyle(
                                color: AppColors.softTerracotta,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 18),

                  // ── Capture button (gated) ──────────────────────────────
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 26),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClinicalCaptureButton(
                            enabled: _isCaptureFramingReady(report),
                            busy: _capturing,
                            countdownProgress: _autoCaptureCountdown == null
                                ? null
                                : (3 - _autoCaptureCountdown!) / 3.0,
                            countdownLabel: _autoCaptureCountdown != null
                                ? 'Hold still… ${_autoCaptureCountdown!}s'
                                : null,
                            onPressed: _capturing
                                ? null
                                : () => _handleCaptureTap(),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Take Photo',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Secondary actions ────────────────────────────────────
                  OutlinedButton.icon(
                    onPressed: _capturing
                        ? null
                        : () async {
                            final result = await MakeupDisclosureDialog.show(
                              context,
                            );
                            if (!mounted || result == null) return;
                            setState(() => _makeupPresent = result);
                          },
                    icon: const Icon(Icons.face_retouching_natural, size: 18),
                    label: const Text('Update pre-scan disclosure'),
                    style: MyApp.secondaryOutlineButton(),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _capturing
                        ? null
                        : () => _triggerGalleryPicker(),
                    icon: const Icon(Icons.photo_library_rounded, size: 18),
                    label: const Text('Choose from Gallery'),
                    style: MyApp.secondaryOutlineButton(),
                  ),

                  const SizedBox(height: 14),
                  _buildDeepAnalysisSection(),

                  const SizedBox(height: 8),
                  _buildLiveGuidanceCard(),
                  const SizedBox(height: 12),
                  _buildClinicalControlsCard(),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: _buildQaTopBanner(report),
          ),
          _buildSuccessOverlay(),
          _buildLivePoseOverlay(),
          if (kDebugMode) _buildDebugFramingOverlay(report),
        ],
      ),
    );
  }

  /// Debug-only (kDebugMode) live telemetry HUD for the capture-framing
  /// gate — added purely for observability while investigating
  /// _isCaptureFramingReady's behavior. Does not read from, call, or
  /// affect any threshold/logic; it only displays values the real gate
  /// already computes (plus the debug-only raw/unsmoothed capture wired
  /// up alongside the landmark stream callback). Never built in release
  /// (`kDebugMode` is `false` and tree-shaken out).
  Widget _buildDebugFramingOverlay(ClinicalQualityReport report) {
    final a = _liveLandmarkAssessment;
    final available = a.available;
    final centerDelta = a.centerOffsetX.abs() + a.centerOffsetY.abs();
    final smoothedTilt = _headTiltAngle();

    final rawAvailable = _debugRawAvailable;
    final rawYaw = _debugRawYaw;
    final rawPitch = _debugRawPitch;
    final rawRoll = _debugRawRoll;
    final rawSummedTilt = (rawYaw == null && rawPitch == null && rawRoll == null)
        ? null
        : (rawYaw?.abs() ?? 0.0) + (rawPitch?.abs() ?? 0.0) + (rawRoll?.abs() ?? 0.0);

    String fmt(double? v, {String unit = '', int decimals = 2}) =>
        v == null ? 'null' : '${v.toStringAsFixed(decimals)}$unit';
    String passFail(bool pass) => pass ? 'PASS' : 'FAIL';

    // Per-check pass/fail against the exact thresholds _isCaptureFramingReady
    // (via _isLiveFacePresentAndCentered / _isAlignmentInRange /
    // alignmentQualityStatus) actually uses -- display-only mirrors of
    // those literal numbers, computed here purely for this readout. Never
    // read back by any gating/threshold logic, only shown to the user.
    const presenceCenterDeltaMax = 0.35;
    const alignmentCenterDeltaMax = 0.25;
    const alignmentTiltMaxDeg = 30.0;
    final faceFillFloorScaled = _targetFaceFillFloor * 0.82;
    final fill = a.faceFillRatio;
    final tiltForGate = smoothedTilt ?? 999.0;
    // alignmentQualityStatus's own red/yellow cutoffs (camera_screen.dart) —
    // body mode uses a much smaller shoulder-line-angle threshold (15°/8°)
    // than face mode's aggregate yaw+pitch+roll sum (40°/30°), since a
    // single-plane angle is naturally much smaller than a 3-angle sum.
    final headAngleRedThreshold = _isBodyGuide ? 15.0 : 40.0;
    final headAngleYellowThreshold = _isBodyGuide ? 8.0 : 30.0;

    // Pre-conversion (raw ML-Kit-normalized, no mirror/crop) numbers, for
    // side-by-side comparison against the corrected (visible-preview-
    // space) ones above -- see convertFaceBoxToVisiblePreviewSpace in
    // landmark_assessment_mlkit.dart. Null before the first face has been
    // detected this session, or on the body guide (face-only fix).
    final rawCenterOffsetX = debugRawCenterOffsetX;
    final rawCenterOffsetY = debugRawCenterOffsetY;
    final rawCenterDelta = (rawCenterOffsetX == null || rawCenterOffsetY == null)
        ? null
        : rawCenterOffsetX.abs() + rawCenterOffsetY.abs();
    final rawFill = debugRawFaceFillRatio;

    final lines = <String>[
      'DEBUG: capture framing (kDebugMode only)',
      'landmarks available: ${available ? 'y' : 'n'}'
          ' (raw frame: ${rawAvailable == null ? '—' : (rawAvailable ? 'y' : 'n')})',
      'raw yaw/pitch/roll: ${fmt(rawYaw, unit: '°')} / '
          '${fmt(rawPitch, unit: '°')} / ${fmt(rawRoll, unit: '°')}'
          ' (pre-smoothing, this frame only)',
      'summed tilt (raw, unsmoothed): ${fmt(rawSummedTilt, unit: '°', decimals: 1)}',
      'smoothed tilt (_headTiltAngle, gate uses this): '
          '${fmt(smoothedTilt, unit: '°', decimals: 1)}'
          ' (avg over last ${_landmarkHistory.length}/$_landmarkSmoothingWindow samples)',
      'centerDelta: raw=${fmt(rawCenterDelta, decimals: 3)} '
          'converted=${centerDelta.toStringAsFixed(3)}',
      'face-fill: raw=${fmt(rawFill, decimals: 3)} '
          'converted=${fill.toStringAsFixed(3)}'
          ' (floor=${_targetFaceFillFloor.toStringAsFixed(3)})',
      '— per-check pass/fail (raw = pre-mirror/crop, converted = visible-'
          'preview-space; checks run against converted) —',
      'presence: centerDelta raw=${fmt(rawCenterDelta, decimals: 3)} '
          'converted=${centerDelta.toStringAsFixed(3)} '
          '≤ $presenceCenterDeltaMax '
          '[${passFail(centerDelta <= presenceCenterDeltaMax)}]',
      'presence: faceFill raw=${fmt(rawFill, decimals: 3)} '
          'converted=${fill.toStringAsFixed(3)} '
          '≥ floor×0.82 (${faceFillFloorScaled.toStringAsFixed(3)}) '
          '[${passFail(!(fill > 0 && fill < faceFillFloorScaled))}]',
      'alignment: centerDelta raw=${fmt(rawCenterDelta, decimals: 3)} '
          'converted=${centerDelta.toStringAsFixed(3)} '
          '≤ $alignmentCenterDeltaMax '
          '[${passFail(centerDelta <= alignmentCenterDeltaMax)}]',
      'alignment: tilt raw=${fmt(smoothedTilt, unit: '°', decimals: 1)} '
          'converted=${fmt(smoothedTilt, unit: '°', decimals: 1)} '
          '(angle — never coordinate-converted) '
          '≤ $alignmentTiltMaxDeg° '
          '[${passFail(tiltForGate <= alignmentTiltMaxDeg)}]',
      'headAngle: ${report.headAngle.state.name} (need green; driven by '
          'converted centerDelta/tilt above; '
          'red>${headAngleRedThreshold.toStringAsFixed(1)}° '
          'yellow>${headAngleYellowThreshold.toStringAsFixed(1)}°) '
          '[${passFail(report.headAngle.state == QualityState.green)}]',
      'gate: ${_debugFramingFailureReason(report)}',
      // Added to investigate the iOS "never gets landmarks" report: what
      // CameraImage is actually arriving vs. what analyzeLiveLandmarks
      // does with it. See landmark_assessment_mlkit.dart's
      // _inputImageFromCameraImage for the format/rotation rules this is
      // checking.
      'raw CameraImage: format=${_debugRawFormatGroup ?? '—'}'
          ' (raw=${_debugRawFormatCode?.toString() ?? '—'})'
          ' planes=${_debugRawPlaneCount?.toString() ?? '—'}'
          ' sensorOrientation=${_debugSensorOrientation?.toString() ?? '—'}°',
      'landmark pipeline totals — conversion-null: $debugConversionNullCount'
          '  zero-detections: $debugZeroDetectionsCount'
          '  found: $debugDetectedCount',
      // Added to investigate a centerDelta miscalculation on rotated
      // (90/270deg) frames: the raw Face.boundingBox center ML Kit
      // returned, and the width/height _assessFace actually divided by to
      // normalize it into centerOffsetX/Y (see that function's doc
      // comment in landmark_assessment_mlkit.dart). Compare these against
      // the raw CameraImage line above to check normalization is using
      // the coordinate space the box is actually in.
      'raw face box center (px): (${fmt(debugFaceBoxCenterXPx, decimals: 1)}, '
          '${fmt(debugFaceBoxCenterYPx, decimals: 1)})'
          '  normalize w/h (px): (${fmt(debugNormalizeWidthPx, decimals: 1)}, '
          '${fmt(debugNormalizeHeightPx, decimals: 1)})',
      // Lighting-sampling ROI, in RAW CameraImage pixel space (see
      // faceRoiRectInRawStreamPixels) -- must land on the raw face box
      // above, never on a visible-preview-space (mirrored/cover-cropped)
      // position.
      'lighting ROI (raw px): left=${_debugFaceRoiLeft?.toString() ?? '—'} '
          'top=${_debugFaceRoiTop?.toString() ?? '—'} '
          'right=${_debugFaceRoiRight?.toString() ?? '—'} '
          'bottom=${_debugFaceRoiBottom?.toString() ?? '—'}',
      // Added to investigate the "Dim light" warning firing with a bright
      // face: _lightingFromCameraImage (this file) now decides tooDark from
      // the face-only ROI luma alone whenever a face sample exists (a
      // bright face over a dark background no longer fails the whole-frame
      // mean/darkRatio check, since that check is skipped in that case) --
      // whole-frame rules only apply with no face sample. This re-derives
      // (read-only) which rule actually decided, using the same
      // darkMeanFloor/darkRatioCeil the real check compares against.
      'lighting: roiLuma=${_liveFaceRoiLuma.toStringAsFixed(1)} '
          'wholeFrameMean=${_liveMeanBrightness.toStringAsFixed(1)} '
          'darkRatio=${fmt(_debugLiveDarkRatio, decimals: 3)} '
          '(floor=${_lightingThresholds.darkMeanFloor.toStringAsFixed(0)} '
          'darkRatioCeil=${_lightingThresholds.darkRatioCeil.toStringAsFixed(2)})',
      'lighting verdict: ${_lightingGuidance.level.name} '
          '(triggered by: ${_debugLightingTooDarkTrigger()})',
      'Y/BGRA plane: bytesPerRow=${_debugPlaneBytesPerRow?.toString() ?? '—'} '
          'width×bpp=${_debugPlaneWidthTimesBpp?.toString() ?? '—'}'
          ' (row padding present: '
          '${_debugPlaneBytesPerRow != null && _debugPlaneWidthTimesBpp != null ? (_debugPlaneBytesPerRow! > _debugPlaneWidthTimesBpp! ? 'y' : 'n') : '—'})',
      // LIGHTING chip's "Harsh backlighting detected" rule (see isBacklit)
      // -- a face sample compares the face against the whole-frame mean
      // (mean−roiLuma, signed: only a brighter SURROUNDING counts as
      // backlit); with no face sample it falls back to the whole-frame
      // quadrant edgeDelta, unchanged from before.
      'backlight: faceRoiLuma=${_liveFaceRoiLuma.toStringAsFixed(1)} '
          'wholeFrameMean=${_liveMeanBrightness.toStringAsFixed(1)} '
          'faceVsFrame(mean−roi)=${(_liveMeanBrightness - _liveFaceRoiLuma).toStringAsFixed(1)} '
          'edgeDelta(whole-frame)=${_liveBacklightDelta.toStringAsFixed(1)} '
          '(ceil=${_backlightDeltaCeil.toStringAsFixed(1)})',
      'backlight verdict: '
          '${isBacklit(faceRoiLuma: _liveFaceRoiLuma, wholeFrameMean: _liveMeanBrightness, wholeFrameEdgeDelta: _liveBacklightDelta, backlightDeltaCeil: _backlightDeltaCeil) ? 'BACKLIT' : 'ok'} '
          '(rule: ${_liveFaceRoiLuma > 0 ? 'face-relative' : 'whole-frame edgeDelta'})',
      // SCALE chip's "too close"/"too far" rule -- fill is the same
      // converted faceFillRatio shown in the face-fill line above.
      'scale: fill=${_liveFaceFillRatio.toStringAsFixed(3)} '
          '(floor=${_targetFaceFillFloor.toStringAsFixed(3)} '
          'ceil=${_targetFaceFillCeil.toStringAsFixed(3)}) '
          '${_liveFaceFillRatio > _targetFaceFillCeil
              ? 'TOO CLOSE'
              : (_liveFaceFillRatio < _targetFaceFillFloor ? 'TOO FAR' : 'ok')}',
    ];

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          bottom: false,
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.limeAccent, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in lines)
                  Text(
                    line,
                    style: const TextStyle(
                      color: Colors.limeAccent,
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLivePoseOverlay() {
    final warning = _isPitchOutOfRange || _isYawOutOfRange;

    return Positioned(
      top: 130,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: SafeArea(
          bottom: false,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.yellow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.38),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  warning
                      ? Icons.warning_amber_rounded
                      : Icons.center_focus_strong_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _livePoseGuidanceText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    if (!_showSuccessBurst) return const SizedBox.shrink();

    final sparkles = <({Alignment align, double size, IconData icon})>[
      (align: Alignment.topCenter, size: 34, icon: Icons.auto_awesome),
      (align: Alignment.centerLeft, size: 22, icon: Icons.star_rounded),
      (align: Alignment.centerRight, size: 24, icon: Icons.star_rounded),
      (align: const Alignment(-0.22, 0.20), size: 18, icon: Icons.auto_awesome),
      (align: const Alignment(0.28, 0.24), size: 20, icon: Icons.auto_awesome),
      (align: const Alignment(0.0, -0.24), size: 16, icon: Icons.star_rounded),
    ];

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _successAnim,
          builder: (context, _) {
            final t = _successAnim.value;
            return Opacity(
              opacity: (1.0 - t).clamp(0.0, 1.0),
              child: Container(
                color: Colors.black.withAlpha((30 * (1 - t)).toInt()),
                child: Center(
                  child: SizedBox(
                    width: 230,
                    height: 230,
                    child: Stack(
                      children: sparkles.map((item) {
                        final spread = 50 + (t * 80);
                        final dx = item.align.x * spread;
                        final dy = item.align.y * spread;
                        return Align(
                          alignment: Alignment.center,
                          child: Transform.translate(
                            offset: Offset(dx, dy),
                            child: Icon(
                              item.icon,
                              size: item.size + (t * 6),
                              color: MyApp.goldShimmer.withAlpha(
                                (210 - (t * 150)).toInt(),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlacementGuide() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final pulse = 0.65 + (_shimmerController.value * 0.35);
        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.champagneGold.withValues(alpha: 0.12),
                MyApp.goldShimmer.withValues(alpha: 0.18),
              ],
            ),
            border: Border.all(
              color: MyApp.goldShimmer.withValues(alpha: pulse),
              width: 1.4,
            ),
          ),
          child: Opacity(
            opacity: 0.96,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: _buildLiveCameraPreview(),
                  ),
                ),
                if (_showGhostOverlay && _referenceImagePath != null)
                  _buildGhostReferenceOverlay(),
                if (_isTrackProcedureFlow &&
                  (_isBodyGuide
                    ? _referenceScan?.bodyReferenceGeometry != null
                    : _referenceScan?.faceReferenceGeometry != null))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: _referenceAlignmentStatusColor,
                            width: 2.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _referenceAlignmentStatusColor.withValues(alpha: 0.22),
                              blurRadius: 12,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _referenceAlignmentStatusColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _referenceAlignmentStatusColor.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                _referenceAlignmentStatusLabel,
                                style: TextStyle(
                                  color: _referenceAlignmentStatusColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                AdaptiveCameraOutline(
                  guideType: _guideType,
                  height: _isBodyGuide ? 380 : 340,
                  angleChips: _overlayAngles,
                  selectedAngleChip: _selectedPoseTemplate,
                  poseTemplate: _selectedPoseTemplate,
                  showBottomLabel: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Fixed size of the live preview's FittedBox(fit: BoxFit.cover) child
  // below -- BoxFit.cover always crops the raw camera stream to exactly
  // this width:height ratio before display, regardless of the final
  // on-screen pixel size, since FittedBox scales its child while
  // preserving its aspect ratio. The face-framing check's coordinate
  // conversion (see analyzeLiveLandmarks/_assessFace in
  // landmark_assessment_mlkit.dart) must crop the same ratio to reason
  // about what the user actually sees, so it reads these same constants
  // rather than a second, possibly-drifting copy of "300x340".
  static const double _facePreviewWidth = 300;
  static const double _facePreviewHeight = 340;
  static const double _facePreviewAspectRatio =
      _facePreviewWidth / _facePreviewHeight;
  static const double _bodyPreviewWidth = 300;
  static const double _bodyPreviewHeight = 380;
  static const double _bodyPreviewAspectRatio =
      _bodyPreviewWidth / _bodyPreviewHeight;

  Widget _buildLiveCameraPreview() {
    final controller = _cameraController;
    if (_cameraInitFailed) {
      return DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6)),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              _cameraError ?? 'Camera unavailable',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Color(0x33000000),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _isBodyGuide ? _bodyPreviewWidth : _facePreviewWidth,
        height: _isBodyGuide ? _bodyPreviewHeight : _facePreviewHeight,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildCameraStatusBar() {
    final hasMultiLens = _availableCameras.length > 1;

    final resolved = _cameraReady
        ? resolveReadyCameraStatusBarContent(
            streamLive: _lightingStreamActive,
            isWeb: kIsWeb,
            lightingLevel: _lightingGuidance.level,
          )
        : (
            badgeLabel: 'Needs Light',
            badgeColor: AppColors.softTerracotta,
            primaryStatus: _cameraError ?? 'Starting camera...',
            secondaryStatus: null,
          );

    final badgeColor = resolved.badgeColor;
    final badgeLabel = resolved.badgeLabel;
    final primaryStatus = resolved.primaryStatus;
    final secondaryStatus = resolved.secondaryStatus;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.05),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            _cameraReady
                ? Icons.verified_outlined
                : Icons.warning_amber_rounded,
            color: _cameraReady
                ? AppColors.mutedSage
                : AppColors.softTerracotta,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primaryStatus,
                  style: TextStyle(
                    color: MyApp.textBrown,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.2,
                    height: 1.26,
                  ),
                ),
                if (secondaryStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      secondaryStatus,
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.68),
                        fontWeight: FontWeight.w600,
                        fontSize: 11.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildSubtleStatusBadge(
            label: badgeLabel,
            textColor: badgeColor,
            backgroundColor: badgeColor.withValues(alpha: 0.10),
            borderColor: badgeColor.withValues(alpha: 0.24),
          ),
          if (hasMultiLens)
            IconButton(
              tooltip: 'Switch lens',
              onPressed: _capturing ? null : _toggleCameraLens,
              icon: Icon(Icons.cameraswitch_outlined, color: MyApp.goldShimmer),
            ),
        ],
      ),
    );
  }

  _LightingThresholds get _lightingThresholds {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        // Facial captures should be strict: underexposed cheeks and forehead
        // reduce landmark stability and lesion-confidence precision.
        return const _LightingThresholds(
          darkMeanFloor: 104,
          harshMeanCeil: 168,
          darkRatioCeil: 0.24,
          harshRatioCeil: 0.17,
        );
      case ProcedureCameraGuideType.body:
        // Body framing includes more background, so brightness variance is
        // naturally wider than face-only captures.
        return const _LightingThresholds(
          darkMeanFloor: 96,
          harshMeanCeil: 176,
          darkRatioCeil: 0.28,
          harshRatioCeil: 0.21,
        );
      case ProcedureCameraGuideType.general:
        // General mode balances common webcam + phone front-camera behavior and
        // uses the empirically verified mean-luma band from device testing.
        return const _LightingThresholds(
          darkMeanFloor: 58,
          harshMeanCeil: 194,
          darkRatioCeil: 0.26,
          harshRatioCeil: 0.19,
        );
    }
  }

  double get _sharpnessVarianceFloor {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        // Slightly more forgiving for real-world smartphone / webcam captures
        // while still warning when the frame is distractingly soft.
        return 36.0;
      case ProcedureCameraGuideType.body:
        // Body surfaces have lower high-frequency detail than facial skin.
        return 24.0;
      case ProcedureCameraGuideType.general:
        // Relaxed enough to avoid blocking routine captures without losing
        // the useful blur cue.
        return 28.0;
    }
  }

  double get _targetFaceFillFloor {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        // Give normal arm-length phone holding distances plenty of room to pass
        // the scale check while still maintaining a meaningful visual reference.
        return 0.08;
      case ProcedureCameraGuideType.body:
        // Body framing tolerates a wider range of distance changes.
        return 0.07;
      case ProcedureCameraGuideType.general:
        return 0.08;
    }
  }

  double get _targetFaceFillCeil {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        // This wider upper bound prevents valid close-to-mid range captures from
        // getting flagged as over-scaled in everyday use.
        return 0.35;
      case ProcedureCameraGuideType.body:
        // Full arm-extension body captures can legitimately land just under
        // 0.29; keep that comfortably green while still warning before the
        // general/facial close-range ceilings.
        return 0.32;
      case ProcedureCameraGuideType.general:
        return 0.38;
    }
  }

  double get _backlightDeltaCeil {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        // Tight tolerance for asymmetrical edge illumination in facial mode.
        return 42.0;
      case ProcedureCameraGuideType.body:
        return 50.0;
      case ProcedureCameraGuideType.general:
        return 46.0;
    }
  }

  double _estimateLaplacianVarianceFromYPlane(CameraImage image) {
    final yPlane = image.planes.firstOrNull;
    if (yPlane == null || yPlane.bytes.isEmpty) return 0;

    final bytesPerPixel = _primaryPlaneBytesPerPixel(image, yPlane);
    final bytes = yPlane.bytes;
    final width = image.width;
    final height = image.height;
    final rowStride = yPlane.bytesPerRow;
    if (width < 6 || height < 6 || rowStride < width * bytesPerPixel) return 0;

    // Downsample aggressively to keep the stream loop lightweight.
    const step = 4;
    var count = 0;
    var sum = 0.0;
    var sumSq = 0.0;

    for (var y = 2; y < height - 2; y += step) {
      final row = y * rowStride;
      for (var x = 2; x < width - 2; x += step) {
        final idx = row + x * bytesPerPixel;
        final c = _luminanceFromBytes(bytes, idx, bytesPerPixel);
        final left = _luminanceFromBytes(bytes, idx - bytesPerPixel, bytesPerPixel);
        final right = _luminanceFromBytes(bytes, idx + bytesPerPixel, bytesPerPixel);
        final up = _luminanceFromBytes(bytes, idx - rowStride, bytesPerPixel);
        final down = _luminanceFromBytes(bytes, idx + rowStride, bytesPerPixel);

        final lap = (4 * c) - left - right - up - down;
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }

    if (count == 0) return 0;
    final mean = sum / count;
    final variance = (sumSq / count) - (mean * mean);
    return variance.isFinite ? variance.clamp(0.0, 5000.0) : 0.0;
  }

  void _updateQaBannerFromReport(ClinicalQualityReport report) {
    final next = report.primaryInstruction;
    if (next == _qaBannerMessage) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || next == _qaBannerMessage) return;
      setState(() => _qaBannerMessage = next);
    });
  }

  Widget _buildQaTopBanner(ClinicalQualityReport report) {
    final show = !report.allGreen || _capturing;
    final warning = report.all.any((s) => s.state == QualityState.red);
    final bg = warning
        ? AppColors.softTerracotta.withValues(alpha: 0.94)
        : AppColors.champagneGold.withValues(alpha: 0.94);

    return AnimatedSlide(
      offset: show ? Offset.zero : const Offset(0, -1.25),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: show ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: SafeArea(
          bottom: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  warning ? Icons.warning_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _qaBannerMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClinicalControlsCard() {
    final lightingColor = switch (_lightingGuidance.level) {
      LightingLevel.optimal => AppColors.mutedSage,
      LightingLevel.tooDark => AppColors.softTerracotta,
      LightingLevel.tooHarsh => AppColors.softTerracotta,
      LightingLevel.unknown => MyApp.textBrown,
    };

    final modeLabel = switch (_guideType) {
      ProcedureCameraGuideType.facial => 'Facial template set',
      ProcedureCameraGuideType.body => 'Body template set',
      ProcedureCameraGuideType.general => 'General template set',
    };

    final guidanceLabel = _liveLandmarkAssessment.available
        ? 'Live Pose Detection'
        : 'Standard Guidance';
    final referenceLabel = _referenceImagePath == null
        ? 'No Reference Yet'
        : _isGoodReferencePhoto
        ? 'Good Reference'
        : 'Standard Reference';
    final guidanceColor = _liveLandmarkAssessment.available
        ? AppColors.mutedSage
        : AppColors.refinedSlate.withValues(alpha: 0.58);
    const referencePanelBorder = AppColors.borders;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                color: MyApp.goldShimmer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Progress Capture Controls',
                style: TextStyle(
                  color: MyApp.textBrown,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                modeLabel,
                style: TextStyle(
                  color: MyApp.textBrown.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w600,
                  fontSize: 11.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.cardBackground.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: referencePanelBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Reference Alignment',
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.70),
                        fontWeight: FontWeight.w700,
                        fontSize: 11.4,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    _buildSubtleStatusBadge(
                      label: '$guidanceLabel • $referenceLabel',
                      textColor: guidanceColor,
                      backgroundColor: _liveLandmarkAssessment.available
                          ? AppColors.mutedSage.withValues(alpha: 0.12)
                          : AppColors.borders.withValues(alpha: 0.34),
                      borderColor: _liveLandmarkAssessment.available
                          ? AppColors.mutedSage.withValues(alpha: 0.32)
                          : AppColors.borders,
                      showDot: true,
                      dotColor: guidanceColor,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Switch(
                      value: _showGhostOverlay,
                      onChanged: _referenceImagePath == null
                          ? null
                          : (v) => setState(() => _showGhostOverlay = v),
                      activeThumbColor: MyApp.goldShimmer,
                      activeTrackColor: MyApp.goldShimmer.withValues(
                        alpha: 0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _referenceImagePath == null
                            ? 'Ghost overlay unlocks after your first baseline capture.'
                            : 'Ghost overlay is active. Match to your best prior reference.',
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.82),
                          fontSize: 12.2,
                          fontWeight: FontWeight.w700,
                          height: 1.28,
                        ),
                      ),
                    ),
                    if (_referenceImagePath != null)
                      Text(
                        '${(_ghostOverlayOpacity * 100).round()}%',
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.52),
                          fontSize: 10.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Text(
                      'Ghost blend',
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.58),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _showGhostOverlay ? 'Aligned overlay' : 'Overlay off',
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.52),
                        fontSize: 10.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _ghostOverlayOpacity,
                  min: 0.12,
                  max: 0.32,
                  divisions: 10,
                  label: '${(_ghostOverlayOpacity * 100).round()}%',
                  onChanged: (_referenceImagePath == null || !_showGhostOverlay)
                      ? null
                      : (v) => setState(() => _ghostOverlayOpacity = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Exact pose template',
            style: TextStyle(
              color: MyApp.textBrown,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _poseTemplates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final template = _poseTemplates[index];
                final selected = template == _selectedPoseTemplate;
                return ChoiceChip(
                  label: Text(template),
                  selected: selected,
                  onSelected: (_) {
                    if (template == _selectedPoseTemplate) return;
                    setState(() => _selectedPoseTemplate = template);
                    _loadReferenceContext();
                  },
                  selectedColor: MyApp.goldShimmer.withValues(alpha: 0.24),
                  labelStyle: TextStyle(
                    color: MyApp.textBrown,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.cardBackground.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: lightingColor.withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.wb_twilight_outlined,
                      color: lightingColor,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Smart lighting guidance: ${_lightingGuidance.label}',
                      style: TextStyle(
                        color: lightingColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _lightingGuidance.instruction,
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.8),
                    fontSize: 12.2,
                    fontWeight: FontWeight.w600,
                    height: 1.32,
                  ),
                ),
              ],
            ),
          ),
          if (_isBodyGuide && _selectedBodyCaptureMode != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: AppColors.cardBackground.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: MyApp.goldShimmer.withValues(alpha: 0.28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _selectedBodyCaptureMode == BodyCaptureMode.mirror
                            ? Icons.flip_rounded
                            : _selectedBodyCaptureMode ==
                                  BodyCaptureMode.timer
                            ? Icons.timer_outlined
                            : Icons.people_alt_outlined,
                        color: MyApp.goldShimmer,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _selectedBodyCaptureMode!.label,
                          style: TextStyle(
                            color: MyApp.goldShimmer,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.8,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _changeBodyCaptureMode,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Change',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _bodyCaptureModeInstruction,
                    style: TextStyle(
                      color: MyApp.textBrown.withValues(alpha: 0.8),
                      fontSize: 12.2,
                      fontWeight: FontWeight.w600,
                      height: 1.32,
                    ),
                  ),
                  if (_selectedBodyCaptureMode == BodyCaptureMode.timer) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed:
                            (_timerCaptureCountdown != null || _capturing)
                            ? null
                            : _startTimerCapture,
                        icon: const Icon(Icons.timer_outlined, size: 16),
                        label: Text(
                          _timerCaptureCountdown != null
                              ? 'Capturing in $_timerCaptureCountdown…'
                              : 'Start timer (8s)',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (_lastConsistencyScore != null) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final visuals = _consistencyVisuals(_lastConsistencyScore!);
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: visuals.color.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: visuals.color.withValues(alpha: 0.34),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Consistency Score: $_lastConsistencyScore% (${visuals.label})',
                        style: TextStyle(
                          color: visuals.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        visuals.note,
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveGuidanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.center_focus_strong,
                color: MyApp.goldShimmer,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Live alignment guidance',
                style: TextStyle(
                  color: MyApp.textBrown,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _liveAlignmentInstruction,
            style: TextStyle(
              color: MyApp.textBrown,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _liveAlignmentSecondary,
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.74),
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtleStatusBadge({
    required String label,
    required Color textColor,
    required Color backgroundColor,
    required Color borderColor,
    bool showDot = false,
    Color? dotColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor ?? textColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 10.2,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

enum LightingLevel { unknown, tooDark, tooHarsh, optimal }

/// Badge label/color + primary/secondary status text for the top camera
/// status card, once the camera itself is ready (the caller still owns the
/// separate "camera not ready yet" / [_cameraError] branch).
///
/// When [streamLive] is true, this branches on [lightingLevel] -- the SAME
/// signal that drives the "Smart lighting guidance" chip
/// ([lightingChipLabelForLevel]) and the bottom QA banner -- instead of
/// unconditionally claiming "Optimal" the instant the frame stream starts.
/// That is the fix for the two surfaces previously being able to disagree
/// (e.g. this card saying "Optimal" while the chip said "Too dark") even
/// though both were describing the same live frame.
({String badgeLabel, Color badgeColor, String primaryStatus, String? secondaryStatus})
resolveReadyCameraStatusBarContent({
  required bool streamLive,
  required bool isWeb,
  required LightingLevel lightingLevel,
}) {
  if (streamLive) {
    return switch (lightingLevel) {
      LightingLevel.optimal => (
        badgeLabel: 'Optimal',
        badgeColor: AppColors.mutedSage,
        primaryStatus: 'Lighting is well-calibrated for accurate comparisons.',
        secondaryStatus: null,
      ),
      LightingLevel.tooDark => (
        badgeLabel: 'Needs Light',
        badgeColor: AppColors.softTerracotta,
        primaryStatus: 'Dim light — move to better light.',
        secondaryStatus: null,
      ),
      LightingLevel.tooHarsh => (
        badgeLabel: 'Too Bright',
        badgeColor: AppColors.softTerracotta,
        primaryStatus: 'Harsh lighting detected — move away from direct light.',
        secondaryStatus: null,
      ),
      LightingLevel.unknown => (
        badgeLabel: 'Calibrating',
        badgeColor: MyApp.textBrown,
        primaryStatus: 'Calibrating exposure…',
        secondaryStatus: null,
      ),
    };
  }
  if (isWeb) {
    return (
      badgeLabel: 'Web Analysis',
      badgeColor: AppColors.champagneGold,
      primaryStatus: 'Guidance is active with browser-safe analysis mode.',
      secondaryStatus: 'Using photo analysis',
    );
  }
  // Neither the live stream nor web-simulated mode: the frame stream hasn't
  // started yet (or errored out), so lighting genuinely can't be measured.
  return (
    badgeLabel: 'Needs Light',
    badgeColor: AppColors.softTerracotta,
    primaryStatus: 'Move to softer front light for the most reliable results.',
    secondaryStatus: 'Tip: face a window or soft front light to improve consistency.',
  );
}

/// The exact chip label text for each [LightingLevel], matching the labels
/// [_LightingGuidance] instances are constructed with in
/// [_lightingFromCameraImage]/[_analyzeLighting]/[_LightingGuidance.unknown].
/// Exposed standalone so tests can confirm [resolveReadyCameraStatusBarContent]
/// never disagrees with it.
String lightingChipLabelForLevel(LightingLevel level) => switch (level) {
  LightingLevel.optimal => 'Lighting optimal',
  LightingLevel.tooDark => 'Too dark',
  LightingLevel.tooHarsh => 'Too harsh',
  LightingLevel.unknown => 'Calibration needed',
};

class _LightingGuidance {
  final LightingLevel level;
  final String label;
  final String instruction;

  const _LightingGuidance({
    required this.level,
    required this.label,
    required this.instruction,
  });

  const _LightingGuidance.unknown()
    : level = LightingLevel.unknown,
      label = 'Calibration needed',
      instruction =
          'Capture a baseline image to calibrate lighting recommendations.';
}

class _LightingThresholds {
  final double darkMeanFloor;
  final double harshMeanCeil;
  final double darkRatioCeil;
  final double harshRatioCeil;

  const _LightingThresholds({
    required this.darkMeanFloor,
    required this.harshMeanCeil,
    required this.darkRatioCeil,
    required this.harshRatioCeil,
  });
}

class _LightingFrameSummary {
  final double mean;
  final double contrast;
  final double darkRatio;
  final double brightRatio;
  final double leftMean;
  final double rightMean;
  final double topMean;
  final double bottomMean;

  const _LightingFrameSummary({
    required this.mean,
    required this.contrast,
    required this.darkRatio,
    required this.brightRatio,
    required this.leftMean,
    required this.rightMean,
    required this.topMean,
    required this.bottomMean,
  });

  const _LightingFrameSummary.empty()
    : mean = 0,
      contrast = 0,
      darkRatio = 0,
      brightRatio = 0,
      leftMean = 0,
      rightMean = 0,
      topMean = 0,
      bottomMean = 0;

  bool get isEmpty =>
      mean == 0 && contrast == 0 && leftMean == 0 && rightMean == 0;
}

/// Subtle teal confirmation pill shown on the web pre-capture screen once the
/// patient has acknowledged the makeup disclosure with "Face is clean".
class _CleanFaceConfirmedChip extends StatelessWidget {
  const _CleanFaceConfirmedChip();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: MyApp.clinicalTeal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: MyApp.clinicalTeal.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_outlined, color: MyApp.clinicalTeal, size: 13),
            const SizedBox(width: 5),
            Text(
              'Clean face confirmed',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: MyApp.clinicalTeal,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
