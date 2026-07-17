// Stub implementation — returned when neither dart:io nor
// dart:js_interop is available (e.g. test platforms). Always returns
// null so callers fall back to the rule engine.

import 'dart:typed_data';

import 'skin_analysis_model.dart';

Future<SkinAnalysisAi?> loadAcneSeverityModel() async => null;

// Re-exported only so the conditional import target name is satisfied.
// ignore: unused_element
class _StubModel implements SkinAnalysisAi {
  @override
  ModelInfo get info => ModelInfo.fallback;
  @override
  Future<SkinAnalysisModelOutput?> analyze(Uint8List bytes) async => null;
  @override
  void dispose() {}
}
