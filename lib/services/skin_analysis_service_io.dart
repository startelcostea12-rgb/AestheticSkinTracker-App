// Skin Analysis Backend — native implementation
// ----------------------------------------------
// Runs the app's two on-device TensorFlow Lite models against a
// captured face photo. Selected automatically (via conditional import
// in `skin_analysis_service.dart`) on platforms where `dart:io` and
// `dart:ffi` are available — i.e. Android, iOS, macOS, Windows, Linux.
//
//   1. Main skin-analysis model  (`skin_analysis_model.tflite`)
//      → outputs 4 metrics: pigment, redness, texture, wrinkle
//   2. Acne + Rosacea specialist (`acne_rosacea_model.tflite`)
//      → outputs 2 metrics: acne_severity, rosacea_intensity
//
// Both models share the same input contract: a 224×224 RGB image,
// float32, normalised to the [0, 1] range, laid out as a 4-D tensor
// of shape [1, 224, 224, 3].

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'skin_analysis_backend.dart';

/// Factory used by the conditional import in the public facade.
SkinAnalysisBackend createSkinAnalysisBackend() => IoSkinAnalysisBackend();

/// Native, TFLite-powered implementation of [SkinAnalysisBackend].
class IoSkinAnalysisBackend implements SkinAnalysisBackend {
  // ── Model configuration ───────────────────────────────────────────
  static const String _mainModelAsset =
      'assets/models/skin_analysis_model.tflite';
  static const String _acneRosaceaModelAsset =
      'assets/models/acne_rosacea_model.tflite';

  /// Required square input dimension for both models.
  static const int _inputSize = 224;

  /// Canonical metric order emitted by the main model. The first four
  /// are the "general skin quality" head; the last two are the
  /// "inflammatory" head. A 6-output model produces all of them; a
  /// 4-output model produces only the first four (the specialist model
  /// then supplies the remaining two).
  static const List<String> _allMetrics = [
    'pigment',
    'redness',
    'texture',
    'wrinkle',
    'acne_severity',
    'rosacea_intensity',
  ];

  /// Metric keys emitted by the specialist model, in output-tensor order.
  static const List<String> _acneRosaceaMetrics = [
    'acne_severity',
    'rosacea_intensity',
  ];

  // ── Runtime state ─────────────────────────────────────────────────
  Interpreter? _mainInterpreter;
  Interpreter? _acneRosaceaInterpreter;

  /// Number of metrics the loaded main model emits (4 or 6). Detected
  /// from its output tensor shape at load time; defaults to 6.
  int _mainOutputLength = 6;

  bool _initialised = false;
  Future<void>? _initFuture;

  @override
  bool get isInitialised => _initialised;

  @override
  bool get isMainModelReady => _mainInterpreter != null;

  @override
  bool get isAcneRosaceaModelReady =>
      // Covered either by the 6-output main model or the specialist.
      (_mainInterpreter != null && _mainOutputLength >= _allMetrics.length) ||
      _acneRosaceaInterpreter != null;

  // ── Loading ───────────────────────────────────────────────────────

  @override
  Future<void> init() {
    if (_initialised) return Future.value();
    return _initFuture ??= _load();
  }

  Future<void> _load() async {
    _mainInterpreter = await _loadInterpreter(_mainModelAsset);
    _mainOutputLength = _detectOutputLength(_mainInterpreter) ?? 6;

    // Only needed when the main model is the legacy 4-metric variant.
    if (_mainOutputLength < _allMetrics.length) {
      _acneRosaceaInterpreter = await _loadInterpreter(_acneRosaceaModelAsset);
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[SkinAnalysisService] Main model emits '
        '$_mainOutputLength metric(s).',
      );
    }
    _initialised = true;
    _initFuture = null;
  }

  /// Reads the trailing dimension of the model's first output tensor
  /// (e.g. [1, 6] → 6). Returns null if it can't be determined.
  int? _detectOutputLength(Interpreter? interpreter) {
    if (interpreter == null) return null;
    try {
      final shape = interpreter.getOutputTensor(0).shape;
      if (shape.isEmpty) return null;
      return shape.last;
    } catch (_) {
      return null;
    }
  }

  /// Loads a single interpreter, returning null if the asset is absent
  /// or the model cannot be parsed.
  Future<Interpreter?> _loadInterpreter(String assetPath) async {
    try {
      // Probe the bundle first — `Interpreter.fromAsset` throws an
      // opaque error on a missing file, so this gives us a clean null.
      try {
        await rootBundle.load(assetPath);
      } catch (_) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[SkinAnalysisService] Model not bundled: $assetPath');
        }
        return null;
      }
      final interpreter = await Interpreter.fromAsset(assetPath);
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SkinAnalysisService] Loaded $assetPath');
      }
      return interpreter;
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SkinAnalysisService] Failed to load $assetPath: $e\n$st');
      }
      return null;
    }
  }

  // ── Public API ────────────────────────────────────────────────────

  @override
  Future<Map<String, double>> runFullAnalysis(String imagePath) async {
    await init();

    // 1. Read + decode the source image.
    final img.Image decoded = await _decodeImage(imagePath);

    // 2. Preprocess once and reuse for both models (identical contract).
    final input = _preprocess(decoded);

    // 3. Run each model independently; failures degrade gracefully.
    final results = <String, double>{};
    results.addAll(_runMain(input));
    results.addAll(_runAcneRosacea(input));

    if (results.isEmpty && kDebugMode) {
      // ignore: avoid_print
      print('[SkinAnalysisService] No models produced output.');
    }
    return results;
  }

  // ── Inference helpers ─────────────────────────────────────────────

  /// Runs the main `skin_analysis_model.tflite` and returns its raw
  /// output vector (values clamped to [0, 1]) in canonical metric
  /// order: pigment, redness, texture, wrinkle[, acne_severity,
  /// rosacea_intensity]. Returns an empty list on any failure.
  List<double> _runTFLiteInference(List<List<List<List<double>>>> input) {
    final interpreter = _mainInterpreter;
    if (interpreter == null) return const <double>[];
    try {
      // Output shape: [1, N] float32 where N is 4 or 6.
      final output = List.generate(
        1,
        (_) => List<double>.filled(_mainOutputLength, 0),
      );
      interpreter.run(input, output);
      return [for (final v in output[0]) v.clamp(0.0, 1.0).toDouble()];
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SkinAnalysisService] Main model inference failed: $e');
      }
      return const <double>[];
    }
  }

  /// Maps the main model's raw vector onto its canonical metric keys.
  /// Handles both the 6-output (all metrics) and legacy 4-output
  /// (general metrics only) variants. Empty map on failure.
  Map<String, double> _runMain(List<List<List<List<double>>>> input) {
    final values = _runTFLiteInference(input);
    if (values.isEmpty) return const {};
    final out = <String, double>{};
    for (var i = 0; i < values.length && i < _allMetrics.length; i++) {
      out[_allMetrics[i]] = values[i];
    }
    return out;
  }

  /// Runs the 2-metric acne+rosacea model. Empty map on any failure.
  Map<String, double> _runAcneRosacea(List<List<List<List<double>>>> input) {
    final interpreter = _acneRosaceaInterpreter;
    if (interpreter == null) return const {};
    try {
      // Output shape: [1, 2] float32.
      final output = List.generate(
        1,
        (_) => List<double>.filled(_acneRosaceaMetrics.length, 0),
      );
      interpreter.run(input, output);
      return _mapOutput(output[0], _acneRosaceaMetrics);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SkinAnalysisService] Acne/Rosacea inference failed: $e');
      }
      return const {};
    }
  }

  /// Zips a raw output vector with its metric keys, clamping to [0, 1].
  Map<String, double> _mapOutput(List<double> values, List<String> keys) {
    final out = <String, double>{};
    for (var i = 0; i < keys.length && i < values.length; i++) {
      out[keys[i]] = values[i].clamp(0.0, 1.0).toDouble();
    }
    return out;
  }

  // ── Preprocessing ─────────────────────────────────────────────────

  /// Reads the file and decodes it into an [img.Image].
  Future<img.Image> _decodeImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw SkinAnalysisException('Image file not found: $imagePath');
    }
    final Uint8List bytes = await file.readAsBytes();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw SkinAnalysisException('Unable to decode image: $imagePath');
    }
    return decoded;
  }

  /// Resizes to 224×224, drops alpha, and normalises each RGB channel
  /// to [0, 1], producing a [1, 224, 224, 3] float32 tensor.
  List<List<List<List<double>>>> _preprocess(img.Image image) {
    final resized = img.copyResize(
      image,
      width: _inputSize,
      height: _inputSize,
    );

    return List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final p = resized.getPixel(x, y);
          return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
        }),
      ),
    );
  }

  // ── Teardown ──────────────────────────────────────────────────────

  @override
  void dispose() {
    try {
      _mainInterpreter?.close();
    } catch (_) {}
    try {
      _acneRosaceaInterpreter?.close();
    } catch (_) {}
    _mainInterpreter = null;
    _acneRosaceaInterpreter = null;
    _initialised = false;
    _initFuture = null;
  }
}
