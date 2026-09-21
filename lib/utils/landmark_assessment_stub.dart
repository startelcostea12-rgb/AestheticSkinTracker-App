import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'landmark_assessment.dart';

Future<LandmarkAssessment> analyzeLiveLandmarks({
  required CameraImage image,
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
  required bool isBody,
  required String poseTemplate,
}) async {
  return LandmarkAssessment.unsupported;
}

Future<LandmarkAssessment> analyzeCapturedLandmarks({
  required Uint8List bytes,
  String? filePath,
  required bool isBody,
  required String poseTemplate,
}) async {
  return LandmarkAssessment.unsupported;
}

Future<void> closeLandmarkAnalyzers() async {}

// Web/unsupported-platform counterparts to the mlkit implementation's
// debug-only outcome counters — always 0 here since this stub never runs
// ML Kit at all. See landmark_assessment_mlkit.dart for what these mean.
int debugConversionNullCount = 0;
int debugZeroDetectionsCount = 0;
int debugDetectedCount = 0;
