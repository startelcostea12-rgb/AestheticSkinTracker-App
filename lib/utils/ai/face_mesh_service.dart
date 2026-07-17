// FaceMeshService — single-frame ML Kit Face Mesh wrapper.
//
// Public facade with conditional import: the native implementation
// (Android / iOS) calls google_mlkit_face_mesh_detection; the stub
// (web / desktop) returns a "not run" result so the rest of the
// pipeline keeps working.
//
// NOTE: only signals that are EXTRACTABLE from a single still photo
// are surfaced — face crop, face-coverage ratio, left/right symmetry.
// Elasticity needs video (or a before/after pair) and is intentionally
// NOT claimed by this service.

import 'dart:typed_data';

import 'face_mesh_service_stub.dart'
    if (dart.library.io) 'face_mesh_service_native.dart'
    as impl;

/// Result of one Face Mesh pass.
class FaceMeshResult {
  /// True when ML Kit ran and at least one mesh was detected.
  final bool meshDetected;

  /// Cropped face bytes (PNG-encoded) if cropping succeeded, else the
  /// original input bytes are returned so downstream code never has
  /// to special-case "no crop".
  final Uint8List bytes;

  /// Fraction of the input frame occupied by the face bbox (0–1).
  /// `null` when no mesh was detected.
  final double? faceCoverage;

  /// 0–1 score: 1.0 = perfectly symmetric L/R landmarks, lower means
  /// possible swelling, asymmetric inflammation, or angled capture.
  /// `null` when no mesh was detected.
  final double? symmetryScore;

  /// Reason the mesh wasn't used (for badge / debug). Empty string
  /// when [meshDetected] is true.
  final String fallbackReason;

  const FaceMeshResult({
    required this.meshDetected,
    required this.bytes,
    required this.faceCoverage,
    required this.symmetryScore,
    required this.fallbackReason,
  });

  factory FaceMeshResult.passthrough(Uint8List bytes, String reason) =>
      FaceMeshResult(
        meshDetected: false,
        bytes: bytes,
        faceCoverage: null,
        symmetryScore: null,
        fallbackReason: reason,
      );
}

class FaceMeshService {
  /// Crop [bytes] to the detected face and emit structural signals.
  /// Always safe — falls back to passing the bytes through on any
  /// failure or unsupported platform.
  static Future<FaceMeshResult> analyze(Uint8List bytes) =>
      impl.runFaceMesh(bytes);
}
