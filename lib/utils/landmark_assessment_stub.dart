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
