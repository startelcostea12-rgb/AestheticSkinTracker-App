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

  /// Closes the underlying interpreters and resets state. Safe to call
  /// multiple times; after disposal, [init] will reload on next use.
  void dispose() => _backend.dispose();
}
