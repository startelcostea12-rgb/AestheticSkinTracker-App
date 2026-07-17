/// Thin façade that routes OCR calls to the web implementation (Tesseract.js)
/// or a no-op stub on non-web platforms.
///
/// Usage:
///   final text = await OcrService.performOcr(bytes, 'photo.jpg');
///   // Returns extracted text, or null if not an image / OCR failed.
library ocr_service;

import 'dart:typed_data';

import 'ocr_service_web.dart' if (dart.library.io) 'ocr_service_stub.dart';

abstract final class OcrService {
  /// Returns recognised text from [bytes] (JPEG/PNG), or `null` on failure.
  static Future<String?> performOcr(Uint8List bytes, String fileName) =>
      recognizeText(bytes, fileName);

  /// Post-process OCR'd text: fixes common medical spelling errors, removes
  /// junk characters, normalises spacing and punctuation.
  static String cleanText(String text) => performCleanText(text);

  static bool isImageFile(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png';
  }
}
