import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image/image.dart' as img;

import 'landmark_assessment.dart';

// ── Debug-only pipeline outcome counters (kDebugMode) ───────────────────
// Purely observational running totals, incremented at the three points
// below where a live frame's fate is decided. Never read by any gating/
// threshold logic — they exist so a debug overlay (see camera_screen.dart)
// can distinguish three failure modes that all look identical from
// `LandmarkAssessment.available == false` alone:
//   1. debugConversionNullCount — _inputImageFromCameraImage returned
//      null, so the frame never reached ML Kit at all (e.g. an
//      unsupported CameraImage format/rotation for this platform).
//   2. debugZeroDetectionsCount — ML Kit ran successfully but found no
//      face/pose in the frame.
//   3. debugDetectedCount — ML Kit found at least one face/pose.
// Left at 0 (and never incremented) outside kDebugMode.
int debugConversionNullCount = 0;
int debugZeroDetectionsCount = 0;
int debugDetectedCount = 0;

// ── Debug-only raw face-box geometry (kDebugMode) ───────────────────────
// The most recent live-stream face detection's raw Face.boundingBox center
// (in pixels, ML Kit's own coordinate space) and the width/height _assessFace
// actually divided by to normalize it into centerOffsetX/Y. Purely
// observational — added to investigate/verify a centerDelta miscalculation
// on rotated (90/270deg) iOS frames; never read by any gating logic. Left
// null outside kDebugMode (and whenever no face has been detected yet).
double? debugFaceBoxCenterXPx;
double? debugFaceBoxCenterYPx;
double? debugNormalizeWidthPx;
double? debugNormalizeHeightPx;

// ── Debug-only pre-conversion face geometry (kDebugMode) ────────────────
// The most recent live-stream face detection's centerOffsetX/Y and
// faceFillRatio computed the OLD way -- directly from the raw ML-Kit-
// normalized image, with no front-camera mirror flip and no BoxFit.cover
// crop applied -- kept only so the debug overlay can show this value next
// to the corrected (visible-preview-space) one LandmarkAssessment now
// returns. Never read by any gating logic. Left null outside kDebugMode
// (and whenever no face has been detected yet).
double? debugRawCenterOffsetX;
double? debugRawCenterOffsetY;
double? debugRawFaceFillRatio;

final FaceDetector _streamFaceDetector = FaceDetector(
  options: FaceDetectorOptions(
    enableLandmarks: true,
    enableTracking: true,
    performanceMode: FaceDetectorMode.fast,
  ),
);

final FaceDetector _singleFaceDetector = FaceDetector(
  options: FaceDetectorOptions(
    enableLandmarks: true,
    enableClassification: true,
    performanceMode: FaceDetectorMode.accurate,
  ),
);

final PoseDetector _streamPoseDetector = PoseDetector(
  options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
);

final PoseDetector _singlePoseDetector = PoseDetector(
  options: PoseDetectorOptions(
    mode: PoseDetectionMode.single,
    model: PoseDetectionModel.accurate,
  ),
);

const _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

Future<LandmarkAssessment> analyzeLiveLandmarks({
  required CameraImage image,
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
  required bool isBody,
  required String poseTemplate,
  required double previewAspectRatio,
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return LandmarkAssessment.unsupported;
  }

  final inputImage = _inputImageFromCameraImage(
    image: image,
    camera: camera,
    deviceOrientation: deviceOrientation,
  );
  if (inputImage == null) {
    if (kDebugMode) debugConversionNullCount++;
    return LandmarkAssessment.unsupported;
  }

  if (isBody) {
    return _assessBody(inputImage, poseTemplate, useSingle: false);
  }
  // Body mode never receives this or previewAspectRatio: the coordinate-
  // space fix is scoped to the face guide path only, per _assessBody's
  // own (unconverted) geometry. See shouldMirrorFaceBoxForPreview's doc
  // comment for why whether to flip is platform-dependent.
  return _assessFace(
    inputImage,
    poseTemplate,
    useSingle: false,
    mirrorPreview: shouldMirrorFaceBoxForPreview(
      lensDirection: camera.lensDirection,
      isIOS: Platform.isIOS,
    ),
    previewAspectRatio: previewAspectRatio,
  );
}

/// Whether the live face-framing conversion must apply its own X mirror
/// flip for this platform + lens combination. Pulled out as a pure
/// function -- taking the platform as a plain [isIOS] parameter rather
/// than reading `dart:io`'s `Platform` internally -- purely so both
/// platforms' behavior are directly unit-testable without needing to run
/// on that platform.
///
/// The on-screen result (front camera always appears mirrored) is the
/// same on both platforms, but whether THIS function needs to apply the
/// flip itself is not:
///
///   - iOS: camera_avfoundation's DefaultCamera.createConnection sets
///     `connection.isVideoMirrored = true` on the front camera's video
///     data output connection -- the SAME connection/buffer that both
///     feeds the CameraImage stream AND backs the on-screen preview
///     texture (`copyPixelBuffer()` returns the same `latestPixelBuffer`).
///     So on iOS the frame handed to ML Kit is already mirrored to match
///     the screen before Dart ever sees it; flipping X again here would
///     double-mirror it back to raw-sensor orientation.
///   - Android (camera_android_camerax): no equivalent exists for the
///     ImageAnalysis/CameraImage stream -- the only mirroring found is a
///     `Transform.scale` on the on-screen PREVIEW WIDGET itself
///     (`image_reader_rotated_preview.dart`), which never touches the
///     analysis buffer. So the frame ML Kit sees on Android is genuinely
///     unmirrored, and this flip is the only place that corrects it.
bool shouldMirrorFaceBoxForPreview({
  required CameraLensDirection lensDirection,
  required bool isIOS,
}) {
  return lensDirection == CameraLensDirection.front && !isIOS;
}

Future<LandmarkAssessment> analyzeCapturedLandmarks({
  required Uint8List bytes,
  String? filePath,
  required bool isBody,
  required String poseTemplate,
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return LandmarkAssessment.unsupported;
  }

  InputImage? inputImage;
  if (filePath != null && filePath.trim().isNotEmpty) {
    inputImage = InputImage.fromFilePath(filePath);
  } else {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return LandmarkAssessment.unsupported;
    final rgbaBytes = Uint8List(decoded.width * decoded.height * 4);
    var offset = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        rgbaBytes[offset++] = pixel.r.toInt();
        rgbaBytes[offset++] = pixel.g.toInt();
        rgbaBytes[offset++] = pixel.b.toInt();
        rgbaBytes[offset++] = pixel.a.toInt();
      }
    }
    inputImage = InputImage.fromBitmap(
      bitmap: rgbaBytes,
      width: decoded.width,
      height: decoded.height,
    );
  }

  return isBody
      ? _assessBody(inputImage, poseTemplate, useSingle: true)
      : _assessFace(inputImage, poseTemplate, useSingle: true);
}

/// Detects the primary (largest) face's bounding box directly on an
/// already-decoded still image's pixels -- the exact same pixels, already
/// EXIF-rotated to their final upright orientation, that the AI Skin
/// Analysis crop dialog cuts its square from (see `img.decodeImage` in
/// image_crop_dialog.dart). Uses the same [_singleFaceDetector] instance
/// [analyzeCapturedLandmarks] uses for a captured still, fed via
/// `InputImage.fromBitmap` on the decoded RGBA pixels at rotation 0 --
/// never `InputImage.fromFilePath`/`fromBytes` on the raw JPEG, which
/// would hand ML Kit whatever orientation the file's own EXIF/decoder
/// produces and could silently disagree with the orientation the crop is
/// actually cut from.
///
/// Returns null on web/desktop, on any detection error, or when no face
/// is found -- callers should keep their own existing fallback in that
/// case.
Future<({double left, double top, double width, double height})?>
detectPrimaryFaceBoxOnDecodedImage(img.Image decoded) async {
  if (!Platform.isAndroid && !Platform.isIOS) return null;
  try {
    final rgbaBytes = Uint8List(decoded.width * decoded.height * 4);
    var offset = 0;
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        rgbaBytes[offset++] = pixel.r.toInt();
        rgbaBytes[offset++] = pixel.g.toInt();
        rgbaBytes[offset++] = pixel.b.toInt();
        rgbaBytes[offset++] = pixel.a.toInt();
      }
    }
    final inputImage = InputImage.fromBitmap(
      bitmap: rgbaBytes,
      width: decoded.width,
      height: decoded.height,
    );
    final faces = await _singleFaceDetector.processImage(inputImage);
    if (faces.isEmpty) return null;

    faces.sort((a, b) {
      final aArea = a.boundingBox.width * a.boundingBox.height;
      final bArea = b.boundingBox.width * b.boundingBox.height;
      return bArea.compareTo(aArea);
    });
    final box = faces.first.boundingBox;
    return (
      left: box.left.toDouble(),
      top: box.top.toDouble(),
      width: box.width.toDouble(),
      height: box.height.toDouble(),
    );
  } catch (e) {
    debugPrint('[AiScanCropPreset] face detection on captured still failed: $e');
    return null;
  }
}

Future<void> closeLandmarkAnalyzers() async {
  await _streamFaceDetector.close();
  await _singleFaceDetector.close();
  await _streamPoseDetector.close();
  await _singlePoseDetector.close();
}

InputImage? _inputImageFromCameraImage({
  required CameraImage image,
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
}) {
  final sensorOrientation = camera.sensorOrientation;
  InputImageRotation? rotation;
  if (Platform.isIOS) {
    rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
  } else if (Platform.isAndroid) {
    var rotationCompensation = _orientations[deviceOrientation];
    if (rotationCompensation == null) return null;
    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (sensorOrientation - rotationCompensation + 360) % 360;
    }
    rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
  }
  if (rotation == null) return null;

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null) return null;

  const androidSupportedFormats = [
    InputImageFormat.nv21,
    InputImageFormat.yv12,
    InputImageFormat.yuv_420_888,
  ];

  if ((Platform.isAndroid && !androidSupportedFormats.contains(format)) ||
      (Platform.isIOS && format != InputImageFormat.bgra8888)) {
    return null;
  }

  InputImageFormat resolvedFormat = format;
  Uint8List bytes;
  if (image.planes.length == 1) {
    bytes = image.planes.first.bytes;
  } else if (Platform.isAndroid &&
      (format == InputImageFormat.yuv_420_888 ||
          format == InputImageFormat.yv12) &&
      image.planes.length == 3) {
    bytes = _convertYUV420ToNV21(image);
    resolvedFormat = InputImageFormat.nv21;
  } else {
    bytes = _concatenatePlanes(image);
  }

  return InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: resolvedFormat,
      bytesPerRow: image.planes.first.bytesPerRow,
    ),
  );
}

Uint8List _convertYUV420ToNV21(CameraImage image) {
  final width = image.width;
  final height = image.height;
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  final nv21 = Uint8List(width * height + (width * height ~/ 2));
  nv21.setRange(0, width * height, yPlane.bytes);
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;
  final vPixelStride = vPlane.bytesPerPixel ?? 1;
  var uvIndex = width * height;
  for (int row = 0; row < height ~/ 2; row++) {
    final uRowStart = row * uPlane.bytesPerRow;
    final vRowStart = row * vPlane.bytesPerRow;
    for (int col = 0; col < width ~/ 2; col++) {
      final uIndex = uRowStart + col * uvPixelStride;
      final vIndex = vRowStart + col * vPixelStride;
      nv21[uvIndex++] = vPlane.bytes[vIndex];
      nv21[uvIndex++] = uPlane.bytes[uIndex];
    }
  }
  return nv21;
}

Uint8List _concatenatePlanes(CameraImage image) {
  final totalBytes = image.planes.fold<int>(
    0,
    (sum, plane) => sum + plane.bytes.length,
  );
  final buffer = Uint8List(totalBytes);
  var offset = 0;
  for (final plane in image.planes) {
    buffer.setRange(offset, offset + plane.bytes.length, plane.bytes);
    offset += plane.bytes.length;
  }
  return buffer;
}

/// Pure coordinate-space conversion for the live face-framing check: maps
/// a face box from raw ML-Kit-normalized image space into the space the
/// user actually sees in the live preview widget -- i.e. after whatever
/// horizontal mirror the preview applies for a front-facing camera, and
/// after whatever BoxFit.cover crop the preview widget applies to fit the
/// raw camera stream's aspect ratio into its own. A pure function of its
/// inputs only (no camera/ML Kit access), so it's unit-testable on its
/// own. Does not touch tilt/yaw/pitch/roll -- those are angles, not
/// positions, and are unaffected by either the mirror or the crop.
///
/// [mirrorPreview] must be the exact same flag the preview widget itself
/// uses to decide whether to mirror -- this function never re-derives or
/// guesses it, it only applies whatever the caller passed in.
///
/// [sourceAspectRatio] is the raw camera stream's width/height;
/// [previewAspectRatio] is the on-screen preview viewport's width/height
/// (the box BoxFit.cover crops the stream to fit, preserving aspect
/// ratio). Passing `previewAspectRatio == sourceAspectRatio` makes the
/// crop step an exact no-op, which is how the captured-still-photo path
/// (no live preview to crop against) opts out of the crop conversion
/// while still going through this same function.
({double centerX, double centerY, double widthNorm, double heightNorm})
convertFaceBoxToVisiblePreviewSpace({
  required double rawCenterXNorm,
  required double rawCenterYNorm,
  required double rawWidthNorm,
  required double rawHeightNorm,
  required bool mirrorPreview,
  required double sourceAspectRatio,
  required double previewAspectRatio,
}) {
  final mirroredCenterX = mirrorPreview
      ? (1.0 - rawCenterXNorm)
      : rawCenterXNorm;

  final validAspects = sourceAspectRatio > 0 && previewAspectRatio > 0;
  final visibleWidthFrac = validAspects
      ? math.min(1.0, previewAspectRatio / sourceAspectRatio)
      : 1.0;
  final visibleHeightFrac = validAspects
      ? math.min(1.0, sourceAspectRatio / previewAspectRatio)
      : 1.0;
  final cropXFrac = (1.0 - visibleWidthFrac) / 2.0;
  final cropYFrac = (1.0 - visibleHeightFrac) / 2.0;

  return (
    centerX: (mirroredCenterX - cropXFrac) / visibleWidthFrac,
    centerY: (rawCenterYNorm - cropYFrac) / visibleHeightFrac,
    widthNorm: rawWidthNorm / visibleWidthFrac,
    heightNorm: rawHeightNorm / visibleHeightFrac,
  );
}

Future<LandmarkAssessment> _assessFace(
  InputImage inputImage,
  String poseTemplate, {
  required bool useSingle,
  bool mirrorPreview = false,
  double? previewAspectRatio,
}) async {
  final detector = useSingle ? _singleFaceDetector : _streamFaceDetector;
  final faces = await detector.processImage(inputImage);
  if (faces.isEmpty) {
    if (kDebugMode && !useSingle) debugZeroDetectionsCount++;
    return const LandmarkAssessment(
      available: false,
      primaryInstruction: 'Center your face inside the outline.',
      secondaryInstruction:
          'Keep the whole face visible for accurate guidance.',
      mode: 'face',
    );
  }
  if (kDebugMode && !useSingle) debugDetectedCount++;

  faces.sort((a, b) {
    final aArea = a.boundingBox.width * a.boundingBox.height;
    final bArea = b.boundingBox.width * b.boundingBox.height;
    return bArea.compareTo(aArea);
  });
  final face = faces.first;
  final imageSize = inputImage.metadata?.size;

  // ML Kit's Face.boundingBox coordinate space relative to the raw
  // InputImageMetadata.size (image.width/image.height from the
  // CameraImage) is PLATFORM-DEPENDENT at 90/270deg rotation — confirmed
  // against the official coordinates_translator.dart shipped with the
  // google_mlkit_face_detection/pose_detection example app (flutter-ml/
  // google_ml_kit_flutter, packages/example/lib/vision_detector_views/
  // painters/coordinates_translator.dart):
  //
  //   translateX/Y at rotation90deg/270deg divide by `imageSize.width`/
  //   `.height` UNSWAPPED on iOS, but by the SWAPPED dimension
  //   (`.height` for x, `.width` for y) on Android. i.e. iOS's native ML
  //   Kit returns boxes in the raw, pre-rotation buffer's coordinate
  //   space; Android's returns them already in upright/rotated
  //   coordinates, so normalizing them needs the raw dimensions swapped
  //   to match.
  //
  // A previous version of this function swapped unconditionally (right
  // for Android, wrong for iOS — the bug this file's history was written
  // to explain); the version before that never swapped at all (right for
  // iOS, wrong for Android). Both were guesses never checked against the
  // platform split above. This now matches the official translator
  // exactly. faceFillRatio was never a reliable signal for catching either
  // mistake: it only uses the width*height PRODUCT, which is swap-
  // invariant, so it looks "correct" regardless of whether the swap
  // direction is right for the running platform. Re-verify against the
  // debug overlay's raw bounding-box-center/normalize-dimensions readout
  // before changing this again.
  final rotation = inputImage.metadata?.rotation ?? InputImageRotation.rotation0deg;
  final requiresSwapOnAndroid = Platform.isAndroid &&
      (rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg);
  double imageWidth = imageSize?.width ?? face.boundingBox.width;
  double imageHeight = imageSize?.height ?? face.boundingBox.height;
  if (requiresSwapOnAndroid) {
    final swapped = imageWidth;
    imageWidth = imageHeight;
    imageHeight = swapped;
  }

  const guideCenterX = 0.5;
  const guideCenterY = 0.48;
  const guideWidthRatio = 0.68;
  const guideHeightRatio = 0.84;

  final faceCenterX = face.boundingBox.center.dx / imageWidth;
  final faceCenterY = face.boundingBox.center.dy / imageHeight;
  final rawFaceWidthNorm = face.boundingBox.width / imageWidth;
  final rawFaceHeightNorm = face.boundingBox.height / imageHeight;
  if (kDebugMode && !useSingle) {
    debugFaceBoxCenterXPx = face.boundingBox.center.dx;
    debugFaceBoxCenterYPx = face.boundingBox.center.dy;
    debugNormalizeWidthPx = imageWidth;
    debugNormalizeHeightPx = imageHeight;
    // Old (pre-conversion) numbers, purely for the debug overlay's
    // raw-vs-converted comparison -- see this function's guideArea/
    // faceFillRatio computation below for why these are mathematically
    // identical to what this file computed before the mirror/crop fix.
    const rawGuideArea = guideWidthRatio * guideHeightRatio;
    final rawFaceArea = (rawFaceWidthNorm * rawFaceHeightNorm).clamp(
      0.0,
      rawGuideArea,
    );
    debugRawFaceFillRatio = (rawFaceArea / rawGuideArea).clamp(0.0, 1.0);
    debugRawCenterOffsetX = (faceCenterX - guideCenterX).clamp(-1.0, 1.0);
    debugRawCenterOffsetY = (faceCenterY - guideCenterY).clamp(-1.0, 1.0);
  }

  // Convert the raw ML-Kit-normalized face box into visible-preview space
  // -- accounting for front-camera mirroring and the BoxFit.cover crop the
  // live preview widget applies -- before comparing it against the guide
  // box below. See convertFaceBoxToVisiblePreviewSpace's doc comment.
  // useSingle (captured-still-photo) calls pass no previewAspectRatio, so
  // this resolves to sourceAspectRatio itself, making the crop step an
  // exact no-op and leaving that path's numbers unchanged.
  final sourceAspectRatio = imageWidth / imageHeight;
  final converted = convertFaceBoxToVisiblePreviewSpace(
    rawCenterXNorm: faceCenterX,
    rawCenterYNorm: faceCenterY,
    rawWidthNorm: rawFaceWidthNorm,
    rawHeightNorm: rawFaceHeightNorm,
    mirrorPreview: mirrorPreview,
    sourceAspectRatio: sourceAspectRatio,
    previewAspectRatio: previewAspectRatio ?? sourceAspectRatio,
  );

  const guideArea = guideWidthRatio * guideHeightRatio;
  final faceArea = (converted.widthNorm * converted.heightNorm).clamp(
    0.0,
    guideArea,
  );
  final faceFillRatio = (faceArea / guideArea).clamp(0.0, 1.0).toDouble();

  final centerOffsetX =
      (converted.centerX - guideCenterX).clamp(-1.0, 1.0).toDouble();
  final centerOffsetY =
      (converted.centerY - guideCenterY).clamp(-1.0, 1.0).toDouble();
  final yaw = face.headEulerAngleY ?? 0;
  final pitch = face.headEulerAngleX ?? 0;
  final roll = face.headEulerAngleZ ?? 0;
  final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
  final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
  double eyeTilt = 0;
  double eyeDistanceNorm = 0;
  if (leftEye != null && rightEye != null) {
    final eyeDx = (rightEye.x - leftEye.x).toDouble();
    final eyeDy = (rightEye.y - leftEye.y).toDouble();
    eyeDistanceNorm =
        (math.sqrt((eyeDx * eyeDx) + (eyeDy * eyeDy)) / imageWidth)
            .clamp(0.0, 1.0)
            .toDouble();
    eyeTilt =
        math.atan2(
          (rightEye.y - leftEye.y).toDouble(),
          (rightEye.x - leftEye.x).toDouble(),
        ) *
        180 /
        math.pi;
  }

  final targetYaw = switch (poseTemplate) {
    'Front' => 0.0,
    'Left 45°' => -28.0,
    'Left Profile' => -48.0,
    'Right 45°' => 28.0,
    'Right Profile' => 48.0,
    _ => 0.0,
  };
  final yawDelta = yaw - targetYaw;
  final centerPenalty =
      (centerOffsetX.abs() * 100) + (centerOffsetY.abs() * 90);
  final posePenalty =
      (yawDelta.abs() * 0.8) +
      (pitch.abs() * 0.7) +
      (roll.abs() * 0.8) +
      (eyeTilt.abs() * 0.6);
  final quality = (100 - centerPenalty - posePenalty).clamp(0, 100).toDouble();
    final faceWidthNorm = (face.boundingBox.width / imageWidth)
      .clamp(0.0, 1.0)
      .toDouble();
    final faceHeightNorm = (face.boundingBox.height / imageHeight)
      .clamp(0.0, 1.0)
      .toDouble();
    final faceAspectRatio = face.boundingBox.height > 0
      ? face.boundingBox.width / face.boundingBox.height
      : 0.0;

  print(
    '[MLKIT FACE POSE] poseTemplate=$poseTemplate yaw=${yaw.toStringAsFixed(2)}° pitch=${pitch.toStringAsFixed(2)}° roll=${roll.toStringAsFixed(2)}° eyeTilt=${eyeTilt.toStringAsFixed(2)}° centerOffsetX=${centerOffsetX.toStringAsFixed(3)} centerOffsetY=${centerOffsetY.toStringAsFixed(3)} faceFillRatio=${faceFillRatio.toStringAsFixed(3)} targetYaw=${targetYaw.toStringAsFixed(2)}° yawDelta=${yawDelta.toStringAsFixed(2)}°',
  );

  String primary;
  if (centerOffsetX.abs() > 0.08) {
    primary = centerOffsetX > 0
        ? 'Move your face slightly left to center it.'
        : 'Move your face slightly right to center it.';
  } else if (centerOffsetY.abs() > 0.08) {
    primary = centerOffsetY > 0
        ? 'Raise the camera slightly or lift your face higher.'
        : 'Lower the camera slightly to match the frame.';
  } else if (roll.abs() > 6 || eyeTilt.abs() > 5) {
    primary = roll > 0
        ? 'Tilt your head slightly right to level the eyes.'
        : 'Tilt your head slightly left to level the eyes.';
  } else if (pitch.abs() > 7) {
    primary = pitch > 0
        ? 'Lower your chin slightly.'
        : 'Lift your chin slightly.';
  } else if (yawDelta.abs() > 8) {
    primary = yawDelta > 0
        ? 'Turn your face slightly left to match the target angle.'
        : 'Turn your face slightly right to match the target angle.';
  } else {
    primary = 'Pose is aligned. Hold still and match the ghost overlay.';
  }

  return LandmarkAssessment(
    available: true,
    primaryInstruction: primary,
    secondaryInstruction:
        'Keep both eyes level and the face centered for the most reliable facial metrics.',
    yaw: yaw,
    pitch: pitch,
    roll: roll,
    eyeTilt: eyeTilt,
    centerOffsetX: centerOffsetX,
    centerOffsetY: centerOffsetY,
    landmarkQuality: quality / 100,
    poseSimilarity: (100 - posePenalty).clamp(0, 100).toDouble(),
    rotationProxy: yaw,
    faceFillRatio: faceFillRatio,
    mode: 'face',
    faceReferenceGeometry: {
      'eyeDistanceNorm': eyeDistanceNorm,
      'faceWidthNorm': faceWidthNorm,
      'faceHeightNorm': faceHeightNorm,
      'faceAspectRatio': faceAspectRatio,
      'centerOffsetX': centerOffsetX,
      'centerOffsetY': centerOffsetY,
      // Raw (pre-mirror, pre-crop-conversion) normalized face center --
      // plain position in the raw stream frame ([0,1], NOT an offset from
      // the guide like centerOffsetX/Y above). Together with faceWidthNorm/
      // faceHeightNorm (also raw), this is what
      // _estimateFaceRoiLumaFromStream (camera_screen.dart) uses to locate
      // its luma-sampling ROI directly on the raw CameraImage buffer --
      // that buffer is in raw stream pixel space, so it must never be
      // indexed with the visible-preview-space (mirrored/cover-cropped)
      // centerOffsetX/Y or faceFillRatio above.
      'rawFaceCenterXNorm': faceCenterX,
      'rawFaceCenterYNorm': faceCenterY,
    },
  );
}

Future<LandmarkAssessment> _assessBody(
  InputImage inputImage,
  String poseTemplate, {
  required bool useSingle,
}) async {
  final detector = useSingle ? _singlePoseDetector : _streamPoseDetector;
  final poses = await detector.processImage(inputImage);
  if (poses.isEmpty) {
    if (kDebugMode && !useSingle) debugZeroDetectionsCount++;
    return const LandmarkAssessment(
      available: false,
      primaryInstruction: 'Center your body inside the outline.',
      secondaryInstruction:
          'Keep shoulders and hips visible for accurate body alignment.',
      mode: 'body',
    );
  }
  if (kDebugMode && !useSingle) debugDetectedCount++;

  final pose = poses.first;
  final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
  final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
  final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
  final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
  if (leftShoulder == null ||
      rightShoulder == null ||
      leftHip == null ||
      rightHip == null) {
    return const LandmarkAssessment(
      available: false,
      primaryInstruction:
          'Keep the upper body fully visible for alignment guidance.',
      secondaryInstruction: 'Show both shoulders and hips in frame.',
      mode: 'body',
    );
  }

  // Same platform-dependent rotation handling as _assessFace above (see
  // that function's doc comment for the full explanation, sourced from
  // the official coordinates_translator.dart): iOS's pose landmarks are
  // in the raw, pre-rotation metadata.size coordinate space at
  // 90/270deg; Android's are already upright, so the raw dimensions must
  // be swapped to normalize them correctly.
  final rotation = inputImage.metadata?.rotation ?? InputImageRotation.rotation0deg;
  final requiresSwapOnAndroid = Platform.isAndroid &&
      (rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg);
  double imageWidth = inputImage.metadata?.size.width ?? 1.0;
  double imageHeight = inputImage.metadata?.size.height ?? 1.0;
  if (requiresSwapOnAndroid) {
    final swapped = imageWidth;
    imageWidth = imageHeight;
    imageHeight = swapped;
  }

  final centerX =
      (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4;
  final centerY =
      (leftShoulder.y + rightShoulder.y + leftHip.y + rightHip.y) / 4;
  final centerOffsetX = ((centerX / imageWidth) - 0.5)
      .clamp(-0.5, 0.5)
      .toDouble();
  final centerOffsetY = ((centerY / imageHeight) - 0.5)
      .clamp(-0.5, 0.5)
      .toDouble();
  final shoulderTilt =
      math.atan2(
        rightShoulder.y - leftShoulder.y,
        rightShoulder.x - leftShoulder.x,
      ) *
      180 /
      math.pi;
  final shoulderWidth = (rightShoulder.x - leftShoulder.x).abs();
  final hipWidth = (rightHip.x - leftHip.x).abs().clamp(1, double.infinity);
  final widthRatio = shoulderWidth / hipWidth;
  final shoulderMidX = ((leftShoulder.x + rightShoulder.x) / 2.0) / imageWidth;
  final shoulderMidY = ((leftShoulder.y + rightShoulder.y) / 2.0) / imageHeight;
  final hipMidX = ((leftHip.x + rightHip.x) / 2.0) / imageWidth;
  final hipMidY = ((leftHip.y + rightHip.y) / 2.0) / imageHeight;
  final shoulderWidthNorm = (shoulderWidth / imageWidth).clamp(0.0, 1.0);
  final hipWidthNorm = (hipWidth / imageWidth).clamp(0.0, 1.0);
  final shoulderToHipRatio = hipWidthNorm > 0 ? shoulderWidthNorm / hipWidthNorm : 0.0;
  final dx = (shoulderMidX - hipMidX) * imageWidth;
  final dy = (shoulderMidY - hipMidY) * imageHeight;
  final shoulderToHipDistance = math.sqrt((dx * dx) + (dy * dy));
  final scaleNorm = (shoulderToHipDistance * 1.25 / math.max(imageWidth, imageHeight))
      .clamp(0.0, 1.0);
  final roiX0Norm = ((math.min(leftHip.x, rightHip.x) / imageWidth) - (0.5 * scaleNorm))
      .clamp(0.0, 1.0);
  final roiX1Norm = ((math.max(leftHip.x, rightHip.x) / imageWidth) + (0.5 * scaleNorm))
      .clamp(0.0, 1.0);
  final roiY0Norm = ((math.min(leftHip.y, rightHip.y) / imageHeight) - (0.35 * scaleNorm))
      .clamp(0.0, 1.0);
  final roiY1Norm = ((math.max(leftHip.y, rightHip.y) / imageHeight) + (0.85 * scaleNorm))
      .clamp(0.0, 1.0);

  final targetRatio = switch (poseTemplate) {
    'Front' => 1.0,
    'Back' => 1.0,
    'Left 45°' => 0.82,
    'Right 45°' => 0.82,
    'Left Side' => 0.55,
    'Right Side' => 0.55,
    _ => 1.0,
  };

  final rotationProxy = widthRatio;
  final ratioDelta = (widthRatio - targetRatio).abs() * 60;
  final centerPenalty =
      (centerOffsetX.abs() * 100) + (centerOffsetY.abs() * 90);
  final posePenalty = ratioDelta + (shoulderTilt.abs() * 0.9);
  final quality = (100 - centerPenalty - posePenalty).clamp(0, 100).toDouble();

  String primary;
  if (centerOffsetX.abs() > 0.09) {
    primary = centerOffsetX > 0
        ? 'Move your body slightly left to center it.'
        : 'Move your body slightly right to center it.';
  } else if (shoulderTilt.abs() > 5) {
    primary = shoulderTilt > 0
        ? 'Lower your right shoulder to level the frame.'
        : 'Lower your left shoulder to level the frame.';
  } else if (ratioDelta > 10) {
    primary = widthRatio > targetRatio
        ? 'Rotate slightly more toward the side angle.'
        : 'Rotate slightly back toward the front angle.';
  } else {
    primary =
        'Body alignment looks strong. Hold still and match the ghost overlay.';
  }

  return LandmarkAssessment(
    available: true,
    primaryInstruction: primary,
    secondaryInstruction:
        'Keep shoulders level, torso centered, and match the selected body angle.',
    shoulderTilt: shoulderTilt,
    centerOffsetX: centerOffsetX,
    centerOffsetY: centerOffsetY,
    landmarkQuality: quality / 100,
    poseSimilarity: (100 - posePenalty).clamp(0, 100).toDouble(),
    rotationProxy: rotationProxy,
    mode: 'body',
    bodyReferenceGeometry: {
      'shoulderMidX': shoulderMidX,
      'shoulderMidY': shoulderMidY,
      'hipMidX': hipMidX,
      'hipMidY': hipMidY,
      'shoulderWidthNorm': shoulderWidthNorm,
      'hipWidthNorm': hipWidthNorm,
      'shoulderToHipRatio': shoulderToHipRatio,
      'roiX0Norm': roiX0Norm,
      'roiX1Norm': roiX1Norm,
      'roiY0Norm': roiY0Norm,
      'roiY1Norm': roiY1Norm,
      'centerOffsetX': centerOffsetX,
      'centerOffsetY': centerOffsetY,
    },
  );
}
