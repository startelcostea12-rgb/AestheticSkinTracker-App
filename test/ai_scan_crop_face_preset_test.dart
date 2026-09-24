import 'package:aesthetic_skin_tracker/widgets/image_crop_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the AI Skin Analysis crop dialog's face-centered initial square:
/// faceCenteredInitialCropSquare (the face-box -> square math) and
/// initialCropDisplayRect (how that square, or its absence, becomes the
/// dialog's starting on-screen rectangle). Both are pure functions -- no
/// image decoding, ML Kit, or widget pumping needed.
void main() {
  group('faceCenteredInitialCropSquare', () {
    test('a centered face produces a square centered on the face', () {
      // 720x1280 still, a roughly square face box centered in the frame.
      final region = faceCenteredInitialCropSquare(
        faceLeft: 260,
        faceTop: 500,
        faceWidth: 200,
        faceHeight: 200,
        stillWidth: 720,
        stillHeight: 1280,
      );

      // side = max(200, 200) / 0.75 = 266.67; faceCenter = (360, 600).
      const expectedSide = 200 / 0.75;
      const expectedLeftPx = 360 - (expectedSide / 2);
      const expectedTopPx = 600 - (expectedSide / 2);

      expect(region.left, closeTo(expectedLeftPx / 720, 1e-6));
      expect(region.top, closeTo(expectedTopPx / 1280, 1e-6));
      expect(region.size, closeTo(expectedSide / 720, 1e-6)); // shorter side
    });

    test(
      'a wide face box lets width set the side (not height)',
      () {
        // Width (300) far exceeds height (120) -- side must be driven by
        // the larger dimension, per the /0.75 rule.
        final region = faceCenteredInitialCropSquare(
          faceLeft: 100,
          faceTop: 400,
          faceWidth: 300,
          faceHeight: 120,
          stillWidth: 720,
          stillHeight: 1280,
        );

        const expectedSide = 300 / 0.75; // == 400, driven by width
        expect(region.size, closeTo(expectedSide / 720, 1e-6));
      },
    );

    test(
      'a face near the edge shifts the square to stay fully inside the '
      'still, without shrinking it',
      () {
        // Face box hugging the top-left corner -- naive centering would
        // put the square partly off-frame (negative left/top).
        final region = faceCenteredInitialCropSquare(
          faceLeft: 0,
          faceTop: 0,
          faceWidth: 150,
          faceHeight: 150,
          stillWidth: 720,
          stillHeight: 1280,
        );

        const expectedSide = 150 / 0.75; // == 200
        // Face center is at (75, 75); naive left/top would be
        // 75 - 100 = -25, clamped to 0.
        expect(region.left, closeTo(0.0, 1e-9));
        expect(region.top, closeTo(0.0, 1e-9));
        expect(region.size, closeTo(expectedSide / 720, 1e-6));
      },
    );

    test(
      'side is clamped to the still\'s shorter side when the face is huge',
      () {
        final region = faceCenteredInitialCropSquare(
          faceLeft: 50,
          faceTop: 50,
          faceWidth: 700,
          faceHeight: 700,
          stillWidth: 720,
          stillHeight: 1280,
        );

        // Raw side would be 700/0.75 = 933.3, far exceeding the still's
        // shorter side (720) -- must clamp to 720, i.e. size == 1.0.
        expect(region.size, closeTo(1.0, 1e-9));
      },
    );
  });

  group('initialCropDisplayRect', () {
    test(
      'no initial region falls back to the existing default: a square '
      '78% of the smaller container dimension, centered',
      () {
        final rect = initialCropDisplayRect(
          containerWidth: 400,
          containerHeight: 300,
          imageWidth: 720,
          imageHeight: 1280,
          initialRegion: null,
        );

        const expectedSize = 300 * 0.78; // min(400,300) * 0.78
        expect(rect.size, closeTo(expectedSize, 1e-9));
        expect(rect.left, closeTo((400 - expectedSize) / 2, 1e-9));
        expect(rect.top, closeTo((300 - expectedSize) / 2, 1e-9));
      },
    );

    test(
      'an initial region is converted from normalized native-image space '
      'into display space using the same contain-fit scale as _doCrop',
      () {
        const region = NormalizedSquareCrop(left: 0.2, top: 0.3, size: 0.5);
        final rect = initialCropDisplayRect(
          containerWidth: 400,
          containerHeight: 300,
          imageWidth: 720,
          imageHeight: 1280,
          initialRegion: region,
        );

        const imgW = 720.0, imgH = 1280.0;
        const scale = 300 / imgH; // height-constrained contain fit
        const displayW = imgW * scale;
        const offsetX = (400 - displayW) / 2;
        const offsetY = 0.0; // height fills the container exactly
        const sourceSize = imgW; // min(imgW, imgH)
        final nativeSize = region.size * sourceSize;
        final nativeLeft = region.left * imgW;
        final nativeTop = region.top * imgH;

        expect(rect.size, closeTo(nativeSize * scale, 1e-6));
        expect(rect.left, closeTo(offsetX + (nativeLeft * scale), 1e-6));
        expect(rect.top, closeTo(offsetY + (nativeTop * scale), 1e-6));
      },
    );
  });
}
