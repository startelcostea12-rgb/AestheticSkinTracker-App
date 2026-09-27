import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/models/ai_scan_frame_exposure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Builds a solid-color JPEG, standing in for one burst-capture frame.
Uint8List _solidColorJpeg(int r, int g, int b, {int size = 8}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixel(x, y, img.ColorRgb8(r, g, b));
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  test('EXIF rationals become decimal values and missing values stay null', () {
    expect(exifRationalAsDouble('1/120'), closeTo(1 / 120, 1e-12));
    expect(exifRationalAsDouble('-1/3'), closeTo(-1 / 3, 1e-12));
    expect(exifRationalAsDouble(null), isNull);
    expect(exifRationalAsDouble('1/0'), isNull);
  });

  group('meanLuminanceFromImageBytes', () {
    test('computes the expected mean luminance for a solid-color frame', () {
      final bytes = _solidColorJpeg(128, 128, 128);

      final luminance = meanLuminanceFromImageBytes(bytes);

      expect(luminance, isNotNull);
      // 0.299*128 + 0.587*128 + 0.114*128 == 128 (JPEG lossy compression can
      // shift a flat block by a few units, so allow a small tolerance).
      expect(luminance, closeTo(128.0, 3.0));
    });

    test('returns null for undecodable bytes', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);

      expect(meanLuminanceFromImageBytes(garbage), isNull);
    });

    test(
      'three burst frames at different brightness produce three distinct, '
      'correctly-ordered luminance readings -- purely for logging, this '
      'never influences which frame _burstFrameScoreFromPreview would '
      'select (that scoring is untouched and reads only sharpness/'
      'alignment/pitch/exposure, never these values)',
      () {
        final dim = meanLuminanceFromImageBytes(_solidColorJpeg(40, 40, 40));
        final mid = meanLuminanceFromImageBytes(_solidColorJpeg(120, 120, 120));
        final bright = meanLuminanceFromImageBytes(
          _solidColorJpeg(220, 220, 220),
        );

        expect(dim, isNotNull);
        expect(mid, isNotNull);
        expect(bright, isNotNull);
        expect(dim!, lessThan(mid!));
        expect(mid, lessThan(bright!));
      },
    );
  });
}
