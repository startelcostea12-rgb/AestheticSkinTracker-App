// Native TFLite implementation of the ACNE04 acne-severity classifier.
//
// Loads `assets/models/acne_severity_acne04.tflite` via tflite_flutter,
// preprocesses the input image to a 224×224 float32 tensor normalised
// to [0,1] (standard ImageNet-style preprocessing — adjust the
// constants below to match your specific exported model), runs one
// forward pass, and returns a 0–10 inflammatory-acne severity mapped
// from the predicted Hayashi grade (0–3).
//
// The asset is OPTIONAL. When the file isn't bundled,
// [loadAcneSeverityModel] returns null and the rest of the app falls
// back to the rule engine. See `assets/models/README.md` for sourcing
// instructions.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'skin_analysis_model.dart';

const _modelAssetPath = 'assets/models/acne_severity_acne04.tflite';
const _inputSize = 224;
const _modelName = 'ACNE04 Hayashi Classifier (MobileNetV2)';
const _modelDataset =
    'ACNE04 — 1,457 facial photos, Hayashi grade 0–3 (Wu et al., 2019)';
const _modelAccuracy = 'Top-1 ~84% on ACNE04 test split (research benchmark)';

Future<SkinAnalysisAi?> loadAcneSeverityModel() async {
  try {
    // Probe the asset bundle first — calling Interpreter.fromAsset on a
    // missing file throws an opaque error; this lets us return a clean
    // null and surface a helpful "model not installed" message.
    try {
      await rootBundle.load(_modelAssetPath);
    } catch (_) {
      return null;
    }
    final interpreter = await Interpreter.fromAsset(_modelAssetPath);
    return _NativeAcneSeverityModel(interpreter);
  } catch (e, st) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ai] TFLite model load failed: $e\n$st');
    }
    return null;
  }
}

class _NativeAcneSeverityModel implements SkinAnalysisAi {
  final Interpreter _interpreter;
  bool _disposed = false;

  _NativeAcneSeverityModel(this._interpreter);

  @override
  ModelInfo get info => const ModelInfo(
    name: _modelName,
    dataset: _modelDataset,
    reportedAccuracy: _modelAccuracy,
    backend: 'TFLite (native)',
  );

  @override
  Future<SkinAnalysisModelOutput?> analyze(Uint8List bytes) async {
    if (_disposed) return null;
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = img.copyResize(
        decoded,
        width: _inputSize,
        height: _inputSize,
      );

      // Build the input tensor as a 4-D float32 buffer [1,H,W,3]
      // normalised to [0,1]. If your model uses ImageNet mean/std
      // normalisation instead, replace the per-pixel divisor below.
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

      // Output: 4 softmax probabilities for Hayashi grades 0..3.
      final output = List.filled(1, List.filled(4, 0.0));
      _interpreter.run(input, output);

      final probs = output[0];
      int top = 0;
      double topP = probs[0];
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > topP) {
          topP = probs[i];
          top = i;
        }
      }

      // Hayashi grade → 0–10 mapping: 0→0 (clear), 1→3 (mild),
      // 2→6 (moderate), 3→9 (severe).
      const gradeToScore = [0, 3, 6, 9];
      return SkinAnalysisModelOutput(
        acneSeverity: gradeToScore[top],
        confidence: topP.clamp(0.0, 1.0),
        modelMetrics: const {'acneSeverity'},
        info: info,
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ai] TFLite inference failed: $e');
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
