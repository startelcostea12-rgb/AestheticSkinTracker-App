// Skin Analysis Backend — web stub
// --------------------------------
// `tflite_flutter` depends on `dart:ffi`, which is unavailable in the
// browser. On web we therefore provide a no-op backend: file-based
// on-device inference is skipped and callers fall back to the existing
// rule-engine report. Selected via the conditional import in
// `skin_analysis_service.dart`.

import 'skin_analysis_backend.dart';

/// Factory used by the conditional import in the public facade.
SkinAnalysisBackend createSkinAnalysisBackend() => WebSkinAnalysisBackend();

/// No-op [SkinAnalysisBackend] for web. Always returns an empty metric
/// map so the UI degrades cleanly to the rule-engine results.
class WebSkinAnalysisBackend implements SkinAnalysisBackend {
  @override
  Future<void> init() async {}

  @override
  Future<Map<String, double>> runFullAnalysis(String imagePath) async =>
      const <String, double>{};

  @override
  void dispose() {}

  @override
  bool get isInitialised => true;

  @override
  bool get isMainModelReady => false;

  @override
  bool get isAcneRosaceaModelReady => false;
}
