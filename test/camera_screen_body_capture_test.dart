import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Builds a 4x4 solid-color-block test image: left half red, right half
/// blue. Flat color blocks survive JPEG's DCT compression essentially
/// exactly, so this is safe to compare post round-trip without a tolerance
/// wide enough to hide a real bug.
Uint8List _leftRedRightBlueImage() {
  final image = img.Image(width: 4, height: 4);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      final color = x < 2
          ? img.ColorRgb8(220, 20, 20) // left = red
          : img.ColorRgb8(20, 20, 220); // right = blue
      image.setPixel(x, y, color);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

bool _isRedDominant(img.Pixel p) => p.r > p.b;
bool _isBlueDominant(img.Pixel p) => p.b > p.r;

void main() {
  group('flipForStorageIfMirror', () {
    test(
      'mirror mode actually swaps pixel columns left-to-right, not just reorders bytes',
      () {
        final original = _leftRedRightBlueImage();
        final flippedBytes = flipForStorageIfMirror(
          original,
          BodyCaptureMode.mirror,
        );

        final decoded = img.decodeImage(flippedBytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, 4);
        expect(decoded.height, 4);

        // Before the flip: left=red, right=blue. After: left=blue, right=red.
        expect(
          _isBlueDominant(decoded.getPixel(0, 0)),
          isTrue,
          reason: 'left column should now be blue (was right/blue pre-flip)',
        );
        expect(
          _isBlueDominant(decoded.getPixel(1, 3)),
          isTrue,
          reason: 'left column should now be blue (was right/blue pre-flip)',
        );
        expect(
          _isRedDominant(decoded.getPixel(2, 0)),
          isTrue,
          reason: 'right column should now be red (was left/red pre-flip)',
        );
        expect(
          _isRedDominant(decoded.getPixel(3, 3)),
          isTrue,
          reason: 'right column should now be red (was left/red pre-flip)',
        );
      },
    );

    test('assisted mode returns the original bytes unchanged (no flip)', () {
      final original = _leftRedRightBlueImage();
      final result = flipForStorageIfMirror(original, BodyCaptureMode.assisted);
      expect(result, same(original));
    });

    test('timer mode returns the original bytes unchanged (no flip)', () {
      final original = _leftRedRightBlueImage();
      final result = flipForStorageIfMirror(original, BodyCaptureMode.timer);
      expect(result, same(original));
    });

    test('null mode (non-body scan) returns the original bytes unchanged', () {
      final original = _leftRedRightBlueImage();
      final result = flipForStorageIfMirror(original, null);
      expect(result, same(original));
    });

    test('undecodable bytes fall back to returning the input unchanged', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = flipForStorageIfMirror(garbage, BodyCaptureMode.mirror);
      expect(result, same(garbage));
    });
  });
}
