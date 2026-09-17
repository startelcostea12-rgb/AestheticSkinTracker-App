import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'landmark_assessment_stub.dart'
    if (dart.library.io) 'landmark_assessment_mlkit.dart'
    as impl;

class LandmarkAssessment {
  const LandmarkAssessment({
    required this.available,
    required this.primaryInstruction,
    required this.secondaryInstruction,
    this.yaw,
    this.pitch,
    this.roll,
    this.eyeTilt,
    this.shoulderTilt,
    this.centerOffsetX = 0,
    this.centerOffsetY = 0,
    this.landmarkQuality = 0,
    this.poseSimilarity = 0,
    this.rotationProxy = 0,
    this.faceFillRatio = 0,
    this.mode = 'fallback',
    this.bodyReferenceGeometry,
    this.faceReferenceGeometry,
  });

  final bool available;
  final String primaryInstruction;
  final String secondaryInstruction;
  final double? yaw;
  final double? pitch;
  final double? roll;
  final double? eyeTilt;
  final double? shoulderTilt;
  final double centerOffsetX;
  final double centerOffsetY;
  final double landmarkQuality;
  final double poseSimilarity;
  final double rotationProxy;
  final double faceFillRatio;
  final String mode;
  final Map<String, double>? bodyReferenceGeometry;
  final Map<String, double>? faceReferenceGeometry;

  Map<String, double> toMetricMap() {
    return {
      'capture_center_offset_x': centerOffsetX,
      'capture_center_offset_y': centerOffsetY,
      'capture_landmark_quality': landmarkQuality,
      'capture_pose_similarity': poseSimilarity,
      'capture_rotation_proxy': rotationProxy,
      'capture_face_fill_ratio': faceFillRatio,
      if (yaw != null) 'capture_yaw': yaw!,
      if (pitch != null) 'capture_pitch': pitch!,
      if (roll != null) 'capture_roll': roll!,
      if (eyeTilt != null) 'capture_eye_tilt': eyeTilt!,
      if (shoulderTilt != null) 'capture_shoulder_tilt': shoulderTilt!,
    };
  }

  static const unsupported = LandmarkAssessment(
    available: false,
    primaryInstruction:
        'Use the ghost overlay and guide outline to match your previous photo.',
    secondaryInstruction:
        'Advanced landmark guidance is not available on this platform.',
  );
}

Future<LandmarkAssessment> analyzeLiveLandmarks({
  required CameraImage image,
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
  required bool isBody,
  required String poseTemplate,
}) {
  return impl.analyzeLiveLandmarks(
    image: image,
    camera: camera,
    deviceOrientation: deviceOrientation,
    isBody: isBody,
    poseTemplate: poseTemplate,
  );
}

Future<LandmarkAssessment> analyzeCapturedLandmarks({
  required Uint8List bytes,
  String? filePath,
  required bool isBody,
  required String poseTemplate,
}) {
  return impl.analyzeCapturedLandmarks(
    bytes: bytes,
    filePath: filePath,
    isBody: isBody,
    poseTemplate: poseTemplate,
  );
}

Future<void> closeLandmarkAnalyzers() {
  return impl.closeLandmarkAnalyzers();
}
