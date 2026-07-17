// YoloAcneDetector — public facade.
//
// Loads `assets/models/yolo_acne_detector.tflite` (YOLOv8-Nano or
// YOLOv11-Nano export, 640×640 input) and returns a list of lesion
// [Detection]s. On any failure (missing asset, decode error, runtime
// failure) the load function returns null and the runner falls back
// to the next-best engine.
//
// Native impl lives in `yolo_acne_detector_native.dart` and uses
// tflite_flutter. Stub returns null on web / unsupported platforms.

import 'dart:typed_data';

import 'skin_detections.dart';
import 'yolo_acne_detector_stub.dart'
    if (dart.library.io) 'yolo_acne_detector_native.dart'
    as impl;

/// Interface satisfied by the native impl. Always safe to call.
abstract class YoloAcneDetector {
  /// Runs detection on already-cropped face [bytes]. Returns an empty
  /// list when nothing crosses the score threshold; returns null when
  /// the model itself failed mid-call (caller should treat as "engine
  /// not available for this frame" and continue).
  Future<List<Detection>?> detect(Uint8List bytes);

  void dispose();
}

/// Top-level loader — null when the model asset isn't bundled or
/// initialisation fails. Idempotent for the caller; cache the result.
Future<YoloAcneDetector?> loadYoloAcneDetector() => impl.loadYoloAcneDetector();
