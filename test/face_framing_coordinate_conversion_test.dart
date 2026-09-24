import 'package:aesthetic_skin_tracker/utils/landmark_assessment_mlkit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers convertFaceBoxToVisiblePreviewSpace -- the pure coordinate-space
/// conversion the live face-framing check (_isLiveFacePresentAndCentered /
/// _isAlignmentInRange in camera_screen.dart) now runs the face's center
/// and width/height through before comparing them to the guide box,
/// accounting for front-camera mirroring and the BoxFit.cover crop the
/// live preview widget applies. Tilt/yaw/pitch/roll are angles, untouched
/// by this conversion, and are not exercised here.
void main() {
  group('convertFaceBoxToVisiblePreviewSpace', () {
    test('mirror flips X only, leaving Y untouched', () {
      final unmirrored = convertFaceBoxToVisiblePreviewSpace(
        rawCenterXNorm: 0.3,
        rawCenterYNorm: 0.5,
        rawWidthNorm: 0.2,
        rawHeightNorm: 0.2,
        mirrorPreview: false,
        sourceAspectRatio: 1.0,
        previewAspectRatio: 1.0,
      );
      final mirrored = convertFaceBoxToVisiblePreviewSpace(
        rawCenterXNorm: 0.3,
        rawCenterYNorm: 0.5,
        rawWidthNorm: 0.2,
        rawHeightNorm: 0.2,
        mirrorPreview: true,
        sourceAspectRatio: 1.0,
        previewAspectRatio: 1.0,
      );

      expect(unmirrored.centerX, closeTo(0.3, 1e-9));
      expect(mirrored.centerX, closeTo(0.7, 1e-9));
      // Y (and width/height) must be completely unaffected by the mirror.
      expect(mirrored.centerY, closeTo(unmirrored.centerY, 1e-9));
      expect(mirrored.widthNorm, closeTo(unmirrored.widthNorm, 1e-9));
      expect(mirrored.heightNorm, closeTo(unmirrored.heightNorm, 1e-9));
    });

    test(
      'mirroring a face does not change centerDelta when guide X is 0.5',
      () {
        // guideCenterX in the real gate (camera_screen.dart /
        // landmark_assessment_mlkit.dart) is 0.5 -- mirroring a raw X
        // around 0.5 must produce the same distance from 0.5, since 0.5
        // is the mirror's own fixed point.
        const guideCenterX = 0.5;

        final unmirrored = convertFaceBoxToVisiblePreviewSpace(
          rawCenterXNorm: 0.3,
          rawCenterYNorm: 0.48,
          rawWidthNorm: 0.2,
          rawHeightNorm: 0.2,
          mirrorPreview: false,
          sourceAspectRatio: 1.0,
          previewAspectRatio: 1.0,
        );
        final mirrored = convertFaceBoxToVisiblePreviewSpace(
          rawCenterXNorm: 0.3,
          rawCenterYNorm: 0.48,
          rawWidthNorm: 0.2,
          rawHeightNorm: 0.2,
          mirrorPreview: true,
          sourceAspectRatio: 1.0,
          previewAspectRatio: 1.0,
        );

        final unmirroredDeltaX = (unmirrored.centerX - guideCenterX).abs();
        final mirroredDeltaX = (mirrored.centerX - guideCenterX).abs();
        expect(mirroredDeltaX, closeTo(unmirroredDeltaX, 1e-9));
      },
    );

    test(
      'cover-crop for a stream taller than the widget crops top/bottom, '
      'leaving a face at the exact vertical center still centered but '
      'pushing an off-center-enough face outside the visible [0,1] range',
      () {
        // Portrait stream (9:16) shown in the wider face-preview viewport
        // (300x340) -- BoxFit.cover crops the stream's top and bottom.
        const sourceAspectRatio = 9 / 16;
        const previewAspectRatio = 300 / 340;

        final centered = convertFaceBoxToVisiblePreviewSpace(
          rawCenterXNorm: 0.5,
          rawCenterYNorm: 0.5,
          rawWidthNorm: 0.1,
          rawHeightNorm: 0.1,
          mirrorPreview: false,
          sourceAspectRatio: sourceAspectRatio,
          previewAspectRatio: previewAspectRatio,
        );
        expect(centered.centerY, closeTo(0.5, 1e-9));
        // No horizontal crop in this orientation -- X passes through.
        expect(centered.centerX, closeTo(0.5, 1e-9));

        final nearTop = convertFaceBoxToVisiblePreviewSpace(
          rawCenterXNorm: 0.5,
          rawCenterYNorm: 0.1,
          rawWidthNorm: 0.1,
          rawHeightNorm: 0.1,
          mirrorPreview: false,
          sourceAspectRatio: sourceAspectRatio,
          previewAspectRatio: previewAspectRatio,
        );
        // y=0.1 sits inside the cropped-off top margin, so it must land
        // outside the visible [0,1] range once converted.
        expect(nearTop.centerY, lessThan(0.0));
      },
    );

    test(
      'cover-crop for a stream wider than the widget crops left/right, '
      'leaving a face at the exact horizontal center still centered but '
      'pushing an off-center-enough face outside the visible [0,1] range',
      () {
        // Landscape stream (16:9) shown in the same face-preview viewport
        // (300x340) -- BoxFit.cover crops the stream's left and right.
        const sourceAspectRatio = 16 / 9;
        const previewAspectRatio = 300 / 340;

        final centered = convertFaceBoxToVisiblePreviewSpace(
          rawCenterXNorm: 0.5,
          rawCenterYNorm: 0.5,
          rawWidthNorm: 0.1,
          rawHeightNorm: 0.1,
          mirrorPreview: false,
          sourceAspectRatio: sourceAspectRatio,
          previewAspectRatio: previewAspectRatio,
        );
        expect(centered.centerX, closeTo(0.5, 1e-9));
        // No vertical crop in this orientation -- Y passes through.
        expect(centered.centerY, closeTo(0.5, 1e-9));

        final nearLeft = convertFaceBoxToVisiblePreviewSpace(
          rawCenterXNorm: 0.1,
          rawCenterYNorm: 0.5,
          rawWidthNorm: 0.1,
          rawHeightNorm: 0.1,
          mirrorPreview: false,
          sourceAspectRatio: sourceAspectRatio,
          previewAspectRatio: previewAspectRatio,
        );
        // x=0.1 sits inside the cropped-off left margin, so it must land
        // outside the visible [0,1] range once converted.
        expect(nearLeft.centerX, lessThan(0.0));
      },
    );

    test(
      'a face that fills the visible guide passes the fill check, even '
      'though its raw (pre-crop) width alone looks far too small for it',
      () {
        // Same wide (16:9-in-300x340) crop as above: only ~49.6% of the
        // raw stream's width survives the cover-crop, so a face that
        // exactly fills the guide box on screen has a raw width fraction
        // roughly HALF of the guide's own width ratio.
        const sourceAspectRatio = 16 / 9;
        const previewAspectRatio = 300 / 340;
        const guideWidthRatio = 0.68;
        const guideHeightRatio = 0.84;
        const visibleWidthFrac = previewAspectRatio / sourceAspectRatio;

        // Chosen so that, once converted, widthNorm == guideWidthRatio and
        // heightNorm == guideHeightRatio exactly -- i.e. a face exactly
        // filling the visible guide box.
        const rawWidthNorm = guideWidthRatio * visibleWidthFrac;
        const rawHeightNorm = guideHeightRatio; // no vertical crop here

        // Sanity check on the premise: the raw width is far smaller than
        // the guide's own width ratio, which is exactly why the old,
        // uncorrected code would have misread this face as badly
        // under-filling the guide.
        expect(rawWidthNorm, lessThan(guideWidthRatio * 0.6));

        final converted = convertFaceBoxToVisiblePreviewSpace(
          rawCenterXNorm: 0.5,
          rawCenterYNorm: 0.48,
          rawWidthNorm: rawWidthNorm,
          rawHeightNorm: rawHeightNorm,
          mirrorPreview: false,
          sourceAspectRatio: sourceAspectRatio,
          previewAspectRatio: previewAspectRatio,
        );

        const guideArea = guideWidthRatio * guideHeightRatio;
        final faceArea = (converted.widthNorm * converted.heightNorm).clamp(
          0.0,
          guideArea,
        );
        final faceFillRatio = (faceArea / guideArea).clamp(0.0, 1.0);

        // Exactly fills the guide -> fill ratio is 1.0, which clears the
        // real gate's floor*0.82 threshold with room to spare.
        expect(faceFillRatio, closeTo(1.0, 1e-6));
        const targetFaceFillFloor = 0.08; // ProcedureCameraGuideType.facial
        expect(faceFillRatio, greaterThanOrEqualTo(targetFaceFillFloor * 0.82));
      },
    );
  });
}
