// Native TFLite implementation of a YOLOv8 / YOLOv11-Nano acne
// detector. Expects a 640×640 RGB input normalised to [0,1] and an
// output tensor of shape [1, 4+numClasses, numAnchors] (the standard
// modern Ultralytics export). Decodes (cx,cy,w,h) + per-class scores,
// applies class-aware NMS, and returns the kept [Detection]s in
// normalised image coordinates.
//
// Tolerant of shape variations: if the output is transposed to
// [1, numAnchors, 4+numClasses] we detect and handle that too.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'skin_detections.dart';
import 'yolo_acne_detector.dart';

const _assetPath = 'assets/models/yolo_acne_detector.tflite';
const _inputSize = 640;
const _scoreThreshold = 0.25;
const _iouThreshold = 0.45;
const _maxDetections = 100;

Future<YoloAcneDetector?> loadYoloAcneDetector() async {
  try {
    try {
      await rootBundle.load(_assetPath);
    } catch (_) {
      return null;
    }
    final interpreter = await Interpreter.fromAsset(_assetPath);
    return _NativeYoloDetector(interpreter);
  } catch (e, st) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ai] YOLO load failed: $e\n$st');
    }
    return null;
  }
}

class _NativeYoloDetector implements YoloAcneDetector {
  final Interpreter _interpreter;
  bool _disposed = false;

  _NativeYoloDetector(this._interpreter);

  @override
  Future<List<Detection>?> detect(Uint8List bytes) async {
    if (_disposed) return null;
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final resized = img.copyResize(
        decoded,
        width: _inputSize,
        height: _inputSize,
      );

      // Build [1, H, W, 3] float32 input normalised to [0, 1].
      final input = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (y) => List.generate(_inputSize, (x) {
            final p = resized.getPixel(x, y);
            return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
          }),
        ),
      );

      // Discover output shape so we work with whatever the user
      // exported (84×8400, 8400×84, custom numClasses, etc.).
      final outShape = _interpreter.getOutputTensors().first.shape;
      if (outShape.length != 3 || outShape[0] != 1) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[ai] YOLO unexpected output rank: $outShape');
        }
        return null;
      }
      final d1 = outShape[1];
      final d2 = outShape[2];

      // Allocate matching nested buffer.
      final output = List.generate(
        1,
        (_) => List.generate(d1, (_) => List.filled(d2, 0.0)),
      );
      _interpreter.run(input, output);

      // Layout heuristic: YOLOv8 default is [1, 4+C, A] where A is
      // usually 8400 for 640 input. If d2 > d1, that's the layout.
      // Otherwise assume transposed [1, A, 4+C].
      final bool channelsFirst = d2 >= d1;
      final int features = channelsFirst ? d1 : d2;
      final int anchors = channelsFirst ? d2 : d1;
      final int numClasses = features - 4;
      if (numClasses <= 0) return const [];

      final labels = _labelsFor(numClasses);
      double valAt(int feat, int anchor) => channelsFirst
          ? (output[0][feat][anchor] as num).toDouble()
          : (output[0][anchor][feat] as num).toDouble();

      final raw = <Detection>[];
      for (int a = 0; a < anchors; a++) {
        // Find top class for this anchor.
        int bestClass = -1;
        double bestScore = 0;
        for (int c = 0; c < numClasses; c++) {
          final s = valAt(4 + c, a);
          if (s > bestScore) {
            bestScore = s;
            bestClass = c;
          }
        }
        if (bestClass < 0 || bestScore < _scoreThreshold) continue;

        // Box: (cx, cy, w, h). YOLOv8 TFLite export commonly emits
        // pixel coords relative to the input; if values look already
        // normalised (max < ~2), keep them.
        final cx = valAt(0, a);
        final cy = valAt(1, a);
        final w = valAt(2, a);
        final h = valAt(3, a);
        double normX = cx, normY = cy, normW = w, normH = h;
        if (cx > 2 || cy > 2 || w > 2 || h > 2) {
          normX /= _inputSize;
          normY /= _inputSize;
          normW /= _inputSize;
          normH /= _inputSize;
        }
        final left = (normX - normW / 2).clamp(0.0, 1.0);
        final top = (normY - normH / 2).clamp(0.0, 1.0);
        final right = (normX + normW / 2).clamp(0.0, 1.0);
        final bottom = (normY + normH / 2).clamp(0.0, 1.0);
        if (right - left <= 0 || bottom - top <= 0) continue;

        raw.add(
          Detection(
            classId: bestClass,
            label: bestClass < labels.length
                ? labels[bestClass]
                : 'class_$bestClass',
            score: bestScore.clamp(0.0, 1.0),
            box: BBox(left, top, right, bottom),
          ),
        );
      }

      final kept = nonMaxSuppression(raw, iouThreshold: _iouThreshold);
      if (kept.length <= _maxDetections) return kept;
      return kept.sublist(0, _maxDetections);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ai] YOLO inference failed: $e');
      }
      return null;
    }
  }

  List<String> _labelsFor(int numClasses) {
    if (numClasses <= kDefaultAcneLabels.length) {
      return kDefaultAcneLabels.sublist(0, numClasses);
    }
    return [
      ...kDefaultAcneLabels,
      for (int i = kDefaultAcneLabels.length; i < numClasses; i++) 'class_$i',
    ];
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _interpreter.close();
    } catch (_) {}
  }
}
