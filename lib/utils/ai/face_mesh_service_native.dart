// Native (Android / iOS) Face Mesh implementation.
// On desktop platforms the ML Kit plugin will simply throw on first
// call; we catch and return a passthrough result so the rest of the
// pipeline (TFLite + rule engine) continues uninterrupted.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:image/image.dart' as img;

import 'face_mesh_service.dart';

// MediaPipe Face Mesh paired landmark indices used for the symmetry
// score. These are stable across the 468-point topology.
const List<List<int>> _symmetryPairs = [
  [33, 263], // outer eye corners
  [133, 362], // inner eye corners
  [61, 291], // mouth corners
  [234, 454], // outer cheek
  [49, 279], // nostril wings
  [127, 356], // temple
];

FaceMeshDetector? _detector;

FaceMeshDetector _ensureDetector() {
  return _detector ??= FaceMeshDetector(
    option: FaceMeshDetectorOptions.faceMesh,
  );
}

Future<FaceMeshResult> runFaceMesh(Uint8List bytes) async {
  if (!(Platform.isAndroid || Platform.isIOS)) {
    return FaceMeshResult.passthrough(
      bytes,
      'ML Kit Face Mesh is Android/iOS only',
    );
  }

  File? tmp;
  try {
    tmp = await File(
      '${Directory.systemTemp.path}/skin_ai_${DateTime.now().microsecondsSinceEpoch}.jpg',
    ).writeAsBytes(bytes, flush: true);

    final detector = _ensureDetector();
    final meshes = await detector.processImage(
      InputImage.fromFilePath(tmp.path),
    );
    if (meshes.isEmpty) {
      return FaceMeshResult.passthrough(bytes, 'No face detected');
    }

    // Pick the largest mesh if multiple faces.
    final mesh = meshes.reduce((a, b) {
      final aArea = a.boundingBox.width * a.boundingBox.height;
      final bArea = b.boundingBox.width * b.boundingBox.height;
      return aArea >= bArea ? a : b;
    });

    // Decode the image to know its real pixel dimensions and to crop.
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return FaceMeshResult.passthrough(bytes, 'Image decode failed');
    }

    final bbox = mesh.boundingBox;
    final faceCoverage =
        (bbox.width * bbox.height) / (decoded.width * decoded.height);

    // Pad the bbox ~15% on each side, clamp to image bounds.
    final padX = bbox.width * 0.15;
    final padY = bbox.height * 0.20; // extra top padding for forehead
    final left = (bbox.left - padX)
        .clamp(0.0, decoded.width.toDouble())
        .toInt();
    final top = (bbox.top - padY).clamp(0.0, decoded.height.toDouble()).toInt();
    final right = (bbox.right + padX)
        .clamp(0.0, decoded.width.toDouble())
        .toInt();
    final bottom = (bbox.bottom + padY)
        .clamp(0.0, decoded.height.toDouble())
        .toInt();
    final cropW = math.max(1, right - left);
    final cropH = math.max(1, bottom - top);

    Uint8List outBytes = bytes;
    try {
      final cropped = img.copyCrop(
        decoded,
        x: left,
        y: top,
        width: cropW,
        height: cropH,
      );
      outBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
    } catch (_) {
      // Cropping failed → use original bytes, still report meshDetected
      // so the badge reflects that ML Kit succeeded.
    }

    return FaceMeshResult(
      meshDetected: true,
      bytes: outBytes,
      faceCoverage: faceCoverage.clamp(0.0, 1.0),
      symmetryScore: _computeSymmetry(mesh, bbox.width.toDouble()),
      fallbackReason: '',
    );
  } catch (e) {
    return FaceMeshResult.passthrough(bytes, 'ML Kit error: $e');
  } finally {
    if (tmp != null) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}

double? _computeSymmetry(FaceMesh mesh, double faceWidth) {
  if (faceWidth <= 0 || mesh.points.isEmpty) return null;

  final points = mesh.points;
  if (points.length < 460) return null; // need full 468-point topology

  // Use the nose tip (landmark 1) as the midline reference. Falls back
  // to the bbox horizontal center if landmark 1 is missing.
  final nose = points[1];
  final midX = nose.x.toDouble();

  double totalDiff = 0;
  int sampled = 0;
  for (final pair in _symmetryPairs) {
    if (pair[0] >= points.length || pair[1] >= points.length) continue;
    final l = points[pair[0]];
    final r = points[pair[1]];
    final lDist = (midX - l.x).abs();
    final rDist = (r.x - midX).abs();
    final diff = (lDist - rDist).abs() / faceWidth;
    totalDiff += diff;
    sampled++;
  }
  if (sampled == 0) return null;
  final meanDiff = totalDiff / sampled;
  // 2x scaling so a 25% per-pair asymmetry pulls the score to 0.5.
  return (1.0 - (meanDiff * 2.0)).clamp(0.0, 1.0);
}
