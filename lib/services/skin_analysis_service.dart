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
  ///
  /// The returned `metric_matrix` is currently empty (see `_toBackendShape`'s
  /// doc comment) — this on-device model's estimates for the app's
  /// verified clinical metrics have zero real-user validation and are
  /// deliberately withheld from the clinical report display until that
  /// changes. `fullMetrics` still carries the model's raw [0, 1] output.
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

  /// `pigment`, `redness`, `texture`, `wrinkle`, and `acne_severity` are
  /// deliberately NOT surfaced into `metric_matrix` (or the legacy
  /// `calibrated_*_score` fields) below, even though the on-device model
  /// estimates all of them — this app already has extensively-verified,
  /// honesty-gate-hardened formula metrics under `pigment_load`,
  /// `localized_redness`, `texture_smoothness`, `wrinkle_load`, and
  /// `breakout_activity` (see main.py), and this model's estimates for
  /// those same clinical concepts have zero real-user validation.
  /// Writing them into the same key names would silently swap the
  /// trusted formula output for unverified model output the next time
  /// this on-device path runs — exactly what must not happen.
  ///
  /// `acne_severity` and `rosacea_intensity` were also considered for a
  /// distinctly-named `metric_matrix` entry (there's no formula metric
  /// literally named either of those — the formula analogs are
  /// `breakout_activity` and `rosacea_severity`), but a corrected-
  /// normalization probe against 5 reference photos (see
  /// skin_analysis_service_io.dart's `_allMetrics` doc comment) found the
  /// model's output does not track visible redness/rosacea severity in a
  /// sensible order on any index — including a severe clinical rosacea
  /// photo scoring lower than clear-skin references. Wiring them into a
  /// user-facing report — "Beta" label or not — isn't justified by that
  /// evidence, so they stay out of `metric_matrix` until a real index
  /// mapping is confirmed against labeled data.
  static Map<String, dynamic> _toBackendShape(Map<String, double> metrics) {
    // Intentionally empty for now — see the doc comment above. The raw
    // model output is still returned in `fullMetrics` below so it isn't
    // lost, just not yet displayed as a trustworthy clinical score.
    final metricMatrix = <String, dynamic>{};

    return <String, dynamic>{
      'status': 'success',
      'success': true,
      'modelUsed': 'local-tflite',
      'metrics': <String, dynamic>{
        'metric_matrix': metricMatrix,
        'trend_deltas': <String, double>{},
      },
      'metric_matrix': metricMatrix,
      'trend_deltas': <String, double>{},
      'serverTrendDeltas': <String, double>{},
      // Raw [0, 1] model output for every metric the on-device model
      // estimates — kept for transparency/debugging/future recalibration
      // even though none of it is surfaced into `metric_matrix` yet.
      'fullMetrics': metrics,
    };
  }

  /// Closes the underlying interpreters and resets state. Safe to call
  /// multiple times; after disposal, [init] will reload on next use.
  void dispose() => _backend.dispose();
}
