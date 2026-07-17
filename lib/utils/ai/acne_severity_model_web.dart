// Web (TensorFlow.js) implementation of the ACNE04 acne-severity
// classifier.
//
// On the web platform `tflite_flutter` cannot be used (no native
// runtime). Instead we load a TF.js-converted version of the same model
// via JS interop. The model + TF.js library are loaded from
// `web/index.html`; this file calls the small JS shim defined there.
//
// The asset is OPTIONAL. When `window.skinAnalysisAi` is not present
// at runtime, [loadAcneSeverityModel] returns null and the rest of the
// app falls back to the rule engine. See `assets/models/README.md` and
// `web/index.html` for the matching JS shim.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import 'skin_analysis_model.dart';

const _modelName = 'ACNE04 Hayashi Classifier (TF.js)';
const _modelDataset =
    'ACNE04 — 1,457 facial photos, Hayashi grade 0–3 (Wu et al., 2019)';
const _modelAccuracy = 'Top-1 ~84% on ACNE04 test split (research benchmark)';

// JS shim contract — see web/index.html for the implementation:
//   window.skinAnalysisAi = {
//     ready: Promise<boolean>,
//     analyzeBytes: (Uint8Array) => Promise<{grade:number, confidence:number}>
//   };
@JS('window.skinAnalysisAi')
external JSObject? get _aiShim;

@JS('window.skinAnalysisAi.ready')
external JSPromise<JSBoolean> _shimReady();

@JS('window.skinAnalysisAi.analyzeBytes')
external JSPromise<JSObject> _shimAnalyze(JSUint8Array bytes);

Future<SkinAnalysisAi?> loadAcneSeverityModel() async {
  try {
    if (_aiShim == null) return null;
    final ready = await _shimReady().toDart;
    if (!ready.toDart) return null;
    return _WebAcneSeverityModel();
  } catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ai] TF.js model load failed: $e');
    }
    return null;
  }
}

class _WebAcneSeverityModel implements SkinAnalysisAi {
  bool _disposed = false;

  @override
  ModelInfo get info => const ModelInfo(
    name: _modelName,
    dataset: _modelDataset,
    reportedAccuracy: _modelAccuracy,
    backend: 'TensorFlow.js (web)',
  );

  @override
  Future<SkinAnalysisModelOutput?> analyze(Uint8List bytes) async {
    if (_disposed) return null;
    try {
      final result = await _shimAnalyze(bytes.toJS).toDart;
      final grade =
          (result.getProperty('grade'.toJS) as JSNumber?)?.toDartInt ?? 0;
      final conf =
          (result.getProperty('confidence'.toJS) as JSNumber?)?.toDartDouble ??
          0.0;
      const gradeToScore = [0, 3, 6, 9];
      final safeGrade = grade.clamp(0, 3);
      return SkinAnalysisModelOutput(
        acneSeverity: gradeToScore[safeGrade],
        confidence: conf.clamp(0.0, 1.0),
        modelMetrics: const {'acneSeverity'},
        info: info,
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ai] TF.js inference failed: $e');
      }
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
  }
}
