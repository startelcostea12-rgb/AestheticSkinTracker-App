/// Web implementation of OCR using Tesseract.js (loaded via index.html).
/// Called by the global `runOCR(dataUrl)` and `cleanMedicalText(text)` JS functions.
library ocr_service_web;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('runOCR')
external JSPromise<JSString> _jsRunOCR(JSString dataUrl);

@JS('cleanMedicalText')
external JSString _jsCleanMedicalText(JSString text);

Future<String?> recognizeText(Uint8List bytes, String fileName) async {
  final ext = fileName.split('.').last.toLowerCase();
  if (ext != 'jpg' && ext != 'jpeg' && ext != 'png') return null;

  try {
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    final jsResult = await _jsRunOCR(dataUrl.toJS).toDart;
    final text = jsResult.toDart.trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}

String performCleanText(String text) {
  try {
    return _jsCleanMedicalText(text.toJS).toDart;
  } catch (_) {
    return text;
  }
}
