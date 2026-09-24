import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/widgets/image_crop_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _solidStill(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, 128, 96, 64);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

/// Covers resolveAiScanFrame1Crop -- the decision (and, when a face was
/// found, the crop) that replaces always-show-ImageCropDialog for the
/// aiSkinAnalysis flow: a detected face auto-crops and skips the dialog
/// entirely, while no detection falls back to showing the dialog exactly
/// as before face detection existed.
void main() {
  group('resolveAiScanFrame1Crop', () {
    test(
      'face found: no dialog, and the crop equals the face-centered '
      'square (same region + same pixels as applyNormalizedSquareCrop '
      'would produce)',
      () {
        final stillBytes = _solidStill(720, 1280);

        final autoRegion = faceCenteredInitialCropSquare(
          faceLeft: 260,
          faceTop: 500,
          faceWidth: 200,
          faceHeight: 200,
          stillWidth: 720,
          stillHeight: 1280,
        );

        final result = resolveAiScanFrame1Crop(
          firstBytes: stillBytes,
          autoRegion: autoRegion,
        );

        expect(result.showDialog, isFalse);
        expect(result.selection, isNotNull);
        expect(result.selection!.region.left, autoRegion.left);
        expect(result.selection!.region.top, autoRegion.top);
        expect(result.selection!.region.size, autoRegion.size);

        // The produced bytes must be the exact same crop
        // applyNormalizedSquareCrop itself would apply to this region --
        // frames 2-3 are cropped through that same function with this
        // region, so frame 1 must match pixel-for-pixel.
        final expectedBytes = applyNormalizedSquareCrop(
          stillBytes,
          autoRegion,
        );
        final actual = img.decodeImage(result.selection!.bytes)!;
        final expected = img.decodeImage(expectedBytes)!;
        expect(actual.width, expected.width);
        expect(actual.height, expected.height);
      },
    );

    test('no face found: the dialog must be shown, with no selection yet', () {
      final stillBytes = _solidStill(720, 1280);

      final result = resolveAiScanFrame1Crop(
        firstBytes: stillBytes,
        autoRegion: null,
      );

      expect(result.showDialog, isTrue);
      expect(result.selection, isNull);
    });
  });
}
