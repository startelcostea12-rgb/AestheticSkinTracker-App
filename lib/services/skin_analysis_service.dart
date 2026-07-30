// Skin Analysis Service (public facade)
// -------------------------------------
// A single, production-ready entry point for running the app's two
// on-device TensorFlow Lite models against a captured face photo and
// merging their outputs into one normalised 6-metric map:
//
//   pigment, redness, texture, wrinkle      (general skin quality)
//   acne_severity, rosacea_intensity        (inflammatory conditions)
//
// All values are returned on a [0, 1] scale.
//
// Platform handling:
//  • The real, TFLite-powered implementation
//    (`skin_analysis_service_io.dart`) is used on platforms with
//    `dart:io` + `dart:ffi` — Android, iOS, macOS, Windows, Linux.
//  • On web, `tflite_flutter` cannot compile (it imports `dart:ffi`),
//    so a no-op stub (`skin_analysis_service_web.dart`) is selected via
//    the conditional import below; `runFullAnalysis` returns an empty
//    map and callers fall back to the rule-engine report.
//
// The backend is chosen at compile time, so web builds never reference
// `dart:ffi`.

import 'skin_analysis_backend.dart';
// Default to the web stub; switch to the native backend wherever
// `dart:io` is available.
import 'skin_analysis_service_web.dart'
    if (dart.library.io) 'skin_analysis_service_io.dart';

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

export 'skin_analysis_backend.dart' show SkinAnalysisException;

/// Runs the bundled TFLite skin-analysis models and merges their
/// outputs into one normalised metric map.
///
/// Usage:
/// ```dart
/// final service = SkinAnalysisService.instance;
/// await service.init();                       // safe to call repeatedly
/// final metrics = await service.runFullAnalysis(imagePath);
/// final redness = metrics['redness'];         // 0.0 – 1.0, or null
/// ```
class SkinAnalysisService {
  // ── Singleton plumbing ────────────────────────────────────────────
  SkinAnalysisService._() : _backend = createSkinAnalysisBackend();

  /// The shared, app-wide instance.
  static final SkinAnalysisService instance = SkinAnalysisService._();

  /// Platform-specific implementation (native TFLite or web no-op),
  /// resolved at compile time via the conditional import above.
  final SkinAnalysisBackend _backend;

  // ── Status ────────────────────────────────────────────────────────

  /// True once [init] has completed.
  bool get isInitialised => _backend.isInitialised;
  bool get isMainModelReady => _backend.isMainModelReady;
  bool get isAcneRosaceaModelReady => _backend.isAcneRosaceaModelReady;

  // ── Public API ────────────────────────────────────────────────────

  /// Loads the underlying models. Idempotent and concurrency-safe.
  Future<void> init() => _backend.init();

  /// Runs all available models against the image at [imagePath] and
  /// returns a merged map of metrics, each clamped to the [0, 1] range:
  ///
  /// ```
  /// {
  ///   "pigment":           double,
  ///   "redness":           double,
  ///   "texture":           double,
  ///   "wrinkle":           double,
  ///   "acne_severity":     double,
  ///   "rosacea_intensity": double,
  /// }
  /// ```
  ///
  /// Behaviour:
  ///  • Calls [init] automatically if needed.
  ///  • If a model is unavailable (or on web), its keys are omitted
  ///    (rather than returning fabricated zeros) so callers can fall
  ///    back cleanly.
  ///  • Throws [SkinAnalysisException] only for unrecoverable input
  ///    errors (missing/undecodable image).
  Future<Map<String, double>> runFullAnalysis(String imagePath) =>
      _backend.runFullAnalysis(imagePath);

  /// Compatibility helper used by UI flows that expect a backend-shaped
  /// analysis payload. Keeps those flows offline by mapping the local
  /// analysis output into the same structure.
  static Future<Map<String, dynamic>> uploadSingleImageFile({
    required XFile? image,
    Uri? uri,
    Map<String, String> fields = const {},
    Map<String, dynamic>? baselineMetricMatrix,
  }) async {
    if (image == null) {
      throw SkinAnalysisException('Image is required for analysis.');
    }

    final metrics = await instance.runFullAnalysis(image.path);
    return _toBackendShape(metrics);
  }

  /// Byte-based compatibility wrapper for the same backend-shaped payload.
  static Future<Map<String, dynamic>> analyzeImageFromBytes(
    Uint8List bytes, {
    String? filename,
    Map<String, dynamic>? baselineMetricMatrix,
  }) async {
    final image = XFile.fromData(
      bytes,
      name: filename ?? 'analysis.jpg',
      mimeType: 'image/jpeg',
    );
    return uploadSingleImageFile(image: image, baselineMetricMatrix: baselineMetricMatrix);
  }

  static Map<String, dynamic> _toBackendShape(Map<String, double> metrics) {
    double pctFromConcern(double value) => (value.clamp(0.0, 1.0) * 100.0);

    final metricMatrix = <String, dynamic>{
      if (metrics['redness'] != null)
        'localized_redness': pctFromConcern(metrics['redness']!),
      if (metrics['texture'] != null)
        'texture_smoothness': (100.0 - pctFromConcern(metrics['texture']!)).clamp(0.0, 100.0),
      if (metrics['pore'] != null)
        'pore_visibility': pctFromConcern(metrics['pore']!),
      if (metrics['acne_severity'] != null)
        'breakout_activity': pctFromConcern(metrics['acne_severity']!),
      if (metrics['pigment'] != null)
        'pigment_load': pctFromConcern(metrics['pigment']!),
      if (metrics['wrinkle'] != null)
        'wrinkle_load': pctFromConcern(metrics['wrinkle']!),
    };

    return <String, dynamic>{
      'status': 'success',
      'success': true,
      'modelUsed': 'local-tflite',
      'metrics': <String, dynamic>{
        if (metrics['redness'] != null)
          'calibrated_redness_score': (100.0 - pctFromConcern(metrics['redness']!)).clamp(0.0, 100.0),
        if (metrics['texture'] != null)
          'calibrated_smoothness_score': (100.0 - pctFromConcern(metrics['texture']!)).clamp(0.0, 100.0),
        'metric_matrix': metricMatrix,
        'trend_deltas': <String, double>{},
      },
      'metric_matrix': metricMatrix,
      'trend_deltas': <String, double>{},
      'serverTrendDeltas': <String, double>{},
      'fullMetrics': metrics,
    };
  }

  /// Closes the underlying interpreters and resets state. Safe to call
  /// multiple times; after disposal, [init] will reload on next use.
  void dispose() => _backend.dispose();
}
