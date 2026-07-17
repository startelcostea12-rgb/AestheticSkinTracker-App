// Skin Analysis Backend (platform-agnostic contract)
// ---------------------------------------------------
// Defines the interface that every platform-specific skin-analysis
// implementation must satisfy, plus the shared exception type.
//
// The native (`dart:io` + `tflite_flutter`) implementation lives in
// `skin_analysis_service_io.dart`; the web stub lives in
// `skin_analysis_service_web.dart`. The public `SkinAnalysisService`
// facade (in `skin_analysis_service.dart`) picks the right one via a
// conditional import, so web builds never touch `dart:ffi`.

/// Contract for a backend that runs the bundled TFLite skin-analysis
/// models and merges their outputs into one normalised metric map
/// (values in the [0, 1] range).
abstract class SkinAnalysisBackend {
  /// Loads the underlying models. Idempotent and concurrency-safe.
  Future<void> init();

  /// Runs all available models against the image at [imagePath] and
  /// returns a merged metric map. Unavailable models simply omit their
  /// keys; an empty map means no model produced output.
  Future<Map<String, double>> runFullAnalysis(String imagePath);

  /// Releases any native resources. Safe to call multiple times.
  void dispose();

  bool get isInitialised;
  bool get isMainModelReady;
  bool get isAcneRosaceaModelReady;
}

/// Thrown for unrecoverable input problems (e.g. a missing or
/// undecodable image). Model-load/inference failures degrade gracefully
/// and do NOT raise this.
class SkinAnalysisException implements Exception {
  final String message;
  SkinAnalysisException(this.message);

  @override
  String toString() => 'SkinAnalysisException: $message';
}
