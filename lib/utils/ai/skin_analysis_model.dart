// On-device AI skin-analysis abstraction.
//
// This layer wraps the *real* AI model (TFLite on native, TensorFlow.js
// on web) behind a platform-agnostic interface so the rest of the app
// can call it the same way everywhere. When the model file is missing
// or fails to load, [SkinAnalysisAi.tryLoad] returns null and callers
// fall back to the calibrated rule engine in
// `acne_rosacea_photo_analysis.dart`.
//
// IMPORTANT — model honesty contract:
// The currently-supported model is an ACNE04-trained Hayashi grading
// classifier (0–3). It is research-grade, NOT diagnostic. The UI
// surfaces the model name, training dataset, and reported accuracy
// next to every score, plus a clear "not a substitute for medical
// advice" disclaimer.

import 'dart:typed_data';

// Platform selector: native (dart:io) → TFLite, web (dart:js_interop)
// → TF.js, otherwise a no-op stub.
import 'acne_severity_model_stub.dart'
    if (dart.library.io) 'acne_severity_model_native.dart'
    if (dart.library.js_interop) 'acne_severity_model_web.dart';

/// Identity card for whichever model is actually loaded — surfaced in
/// the result UI so the user can see exactly what made the prediction.
class ModelInfo {
  /// Display name of the underlying neural network.
  final String name;

  /// Training dataset (e.g. "ACNE04 — 1,457 images, Hayashi grading").
  final String dataset;

  /// Self-reported / paper-reported accuracy on the dataset benchmark.
  final String reportedAccuracy;

  /// Backend in use (`TFLite (native)`, `TensorFlow.js (web)`,
  /// `Rule engine fallback`).
  final String backend;

  /// True when this is the rule-engine fallback — UI uses this to
  /// suppress the "AI model" framing.
  final bool isFallback;

  const ModelInfo({
    required this.name,
    required this.dataset,
    required this.reportedAccuracy,
    required this.backend,
    this.isFallback = false,
  });

  static const fallback = ModelInfo(
    name: 'Clinical analysis baseline',
    dataset: 'Dermatology-anchored heuristics (GAGS + NRS-adapted)',
    reportedAccuracy: 'Deterministic clinical scoring',
    backend: 'Built-in analysis baseline',
    isFallback: true,
  );
}

/// Structured output of one inference pass.
///
/// All scores are 0–10 on the same scale the app uses elsewhere. The
/// model currently produces an inflammatory-acne severity grade; the
/// other slots are filled by the rule engine and merged at the call
/// site, with [modelMetrics] listing the keys that came from the model
/// (so the UI can mark them differently).
class SkinAnalysisModelOutput {
  /// Inflammatory acne severity (0–10). Mapped from Hayashi grade
  /// 0/1/2/3 → 0/3/6/9 when the ACNE04 model is the active backend.
  final int? acneSeverity;

  /// Raw model confidence (0–1) for the top class.
  final double confidence;

  /// Tracker metric keys whose values in this output came from the
  /// model (vs. from the rule engine).
  final Set<String> modelMetrics;

  /// The model that produced this output (or fallback info).
  final ModelInfo info;

  const SkinAnalysisModelOutput({
    required this.acneSeverity,
    required this.confidence,
    required this.modelMetrics,
    required this.info,
  });
}

/// Platform-specific AI implementations satisfy this interface. The
/// `loadAcneSeverityModel` top-level function is selected at compile
/// time by the conditional import above and returns the right impl
/// (or null when the model file is missing).
abstract class SkinAnalysisAi {
  ModelInfo get info;

  /// Runs inference on raw image bytes (any common format — the impl
  /// is responsible for decoding + preprocessing). Returns null when
  /// inference itself fails; the caller falls back to the rule engine.
  Future<SkinAnalysisModelOutput?> analyze(Uint8List bytes);

  /// Releases native interpreter resources. Safe to call multiple times.
  void dispose();

  /// Public entry point — call from anywhere. Returns null when no model
  /// asset is bundled or the runtime can't initialise (e.g. missing DLL
  /// on Windows, missing TF.js on web). Callers MUST handle null.
  static Future<SkinAnalysisAi?> tryLoad() => loadAcneSeverityModel();
}
