/// Non-web stub — OCR is not available on native platforms.
library ocr_service_stub;

import 'dart:typed_data';

Future<String?> recognizeText(Uint8List bytes, String fileName) async => null;

String performCleanText(String text) => text;
