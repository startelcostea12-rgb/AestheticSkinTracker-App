import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;

class WebPreparedImage {
  final Uint8List bytes;
  final String detectedMimeType;
  final bool convertedToJpeg;

  const WebPreparedImage({
    required this.bytes,
    required this.detectedMimeType,
    required this.convertedToJpeg,
  });
}

class WebPrepareImageResult {
  final WebPreparedImage? image;
  final String? errorMessage;

  const WebPrepareImageResult._({this.image, this.errorMessage});

  factory WebPrepareImageResult.success(WebPreparedImage image) {
    return WebPrepareImageResult._(image: image);
  }

  factory WebPrepareImageResult.failure(String message) {
    return WebPrepareImageResult._(errorMessage: message);
  }

  bool get isSuccess => image != null;
}

const int _defaultMaxUploadBytes = 10 * 1024 * 1024;

String _formatSizeMb(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb.toStringAsFixed(mb >= 10 ? 0 : 1);
}

String detectMimeTypeFromBytes(Uint8List bytes, {String? fallbackFileName}) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }

  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }

  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }

  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return 'image/gif';
  }

  if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return 'image/bmp';
  }

  if (bytes.length >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    if (brand.startsWith('heic') ||
        brand.startsWith('heix') ||
        brand.startsWith('hevc') ||
        brand.startsWith('hevx')) {
      return 'image/heic';
    }
    if (brand.startsWith('mif1') || brand.startsWith('msf1')) {
      return 'image/heif';
    }
    if (brand.startsWith('avif')) {
      return 'image/avif';
    }
  }

  final ext = (fallbackFileName ?? '').toLowerCase();
  if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) return 'image/jpeg';
  if (ext.endsWith('.png')) return 'image/png';
  if (ext.endsWith('.webp')) return 'image/webp';
  if (ext.endsWith('.heic')) return 'image/heic';
  if (ext.endsWith('.heif')) return 'image/heif';
  if (ext.endsWith('.gif')) return 'image/gif';
  if (ext.endsWith('.bmp')) return 'image/bmp';
  if (ext.endsWith('.avif')) return 'image/avif';

  return 'application/octet-stream';
}

bool _isImageMime(String mimeType) => mimeType.startsWith('image/');

Future<Uint8List?> _convertToJpeg(Uint8List bytes) async {
  final decoded = img.decodeImage(bytes);
  if (decoded != null) {
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
  }

  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final pngData = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    frame.image.dispose();
    if (pngData == null || pngData.lengthInBytes == 0) return null;

    final pngBytes = pngData.buffer.asUint8List();
    final viaPng = img.decodeImage(pngBytes);
    if (viaPng == null) return null;
    return Uint8List.fromList(img.encodeJpg(viaPng, quality: 90));
  } catch (_) {
    return null;
  }
}

Future<WebPrepareImageResult> prepareWebUploadImage(
  Uint8List bytes, {
  String? fileName,
  int maxBytes = _defaultMaxUploadBytes,
}) async {
  if (bytes.length > maxBytes) {
    return WebPrepareImageResult.failure(
      'This image is too large (${_formatSizeMb(bytes.length)} MB). '
      'Please upload an image under ${_formatSizeMb(maxBytes)} MB.',
    );
  }

  final detectedMime = detectMimeTypeFromBytes(
    bytes,
    fallbackFileName: fileName,
  );

  if (!_isImageMime(detectedMime)) {
    return WebPrepareImageResult.failure(
      'The selected file is not a supported image. Please choose a photo file such as JPG, PNG, WEBP, or HEIC.',
    );
  }

  if (detectedMime == 'image/jpeg') {
    return WebPrepareImageResult.success(
      WebPreparedImage(
        bytes: bytes,
        detectedMimeType: detectedMime,
        convertedToJpeg: false,
      ),
    );
  }

  final converted = await _convertToJpeg(bytes);
  if (converted != null && converted.isNotEmpty) {
    return WebPrepareImageResult.success(
      WebPreparedImage(
        bytes: converted,
        detectedMimeType: detectedMime,
        convertedToJpeg: true,
      ),
    );
  }

  final format = detectedMime.replaceFirst('image/', '').toUpperCase();
  return WebPrepareImageResult.failure(
    'We detected a $format image, but could not convert it for analysis.'
    '${kIsWeb ? ' If this came from iPhone photos, try exporting as JPG and upload again.' : ''}',
  );
}
