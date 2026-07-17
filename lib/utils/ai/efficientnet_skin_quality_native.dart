// Native EfficientNet-B0 skin-quality classifier.
//
// Input  : 224×224 RGB float32, ImageNet-normalised
//          (mean [0.485, 0.456, 0.406], std [0.229, 0.224, 0.225]).
// Output : [1, K] where K ∈ {1..5}. Heads are interpreted in order
//          [texture, wrinkles, pores, elasticity, overall]; missing
//          trailing heads stay null.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'efficientnet_skin_quality.dart';
import 'skin_detections.dart';

const _assetPath = 'assets/models/efficientnet_skin_quality.tflite';
const _inputSize = 224;
const _imagenetMean = [0.485, 0.456, 0.406];
const _imagenetStd = [0.229, 0.224, 0.225];

Future<EfficientNetSkinQuality?> loadEfficientNetSkinQuality() async {
  try {
    try {
      await rootBundle.load(_assetPath);
    } catch (_) {
      return null;
    }
    final interpreter = await Interpreter.fromAsset(_assetPath);
    return _NativeEfficientNet(interpreter);
  } catch (e, st) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ai] EfficientNet load failed: $e\n$st');
    }
    return null;
  }
}

class _NativeEfficientNet implements EfficientNetSkinQuality {
  final Interpreter _interpreter;
  bool _disposed = false;

  _NativeEfficientNet(this._interpreter);

  @override
  Future<SkinQualityScores?> analyze(Uint8List bytes) async {
    if (_disposed) return null;
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = img.copyResize(
        decoded,
        width: _inputSize,
        height: _inputSize,
      );

      // [1,H,W,3] float32 with ImageNet normalisation.
      final input = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (y) => List.generate(_inputSize, (x) {
            final p = resized.getPixel(x, y);
            return [
              (p.r / 255.0 - _imagenetMean[0]) / _imagenetStd[0],
              (p.g / 255.0 - _imagenetMean[1]) / _imagenetStd[1],
              (p.b / 255.0 - _imagenetMean[2]) / _imagenetStd[2],
            ];
          }),
        ),
      );

      final outShape = _interpreter.getOutputTensors().first.shape;
      if (outShape.isEmpty || outShape[0] != 1) return null;
      final k = outShape.length == 2 ? outShape[1] : outShape.last;
      if (k <= 0) return null;

      final output = List.filled(1, List.filled(k, 0.0));
      _interpreter.run(input, output);
      final row = output[0];

      double? at(int i) {
        if (i >= row.length) return null;
        final v = row[i].toDouble();
        // If the head produced a logit (outside [0,1]), squash with
        // sigmoid; otherwise pass through (already a probability).
        if (v < 0 || v > 1) {
          return 1.0 / (1.0 + math.exp(-v));
        }
        return v;
      }

      return SkinQualityScores(
        texture: at(0),
        wrinkles: at(1),
        pores: at(2),
        elasticity: at(3),
        overall: at(4),
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ai] EfficientNet inference failed: $e');
      }
      return null;
    }
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
