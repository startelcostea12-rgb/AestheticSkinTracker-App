import 'dart:math' as math;

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers faceRoiRectInRawStreamPixels -- the lighting-sampling ROI
/// placement _estimateFaceRoiLumaFromStream uses, now driven by the raw
/// (pre-mirror, pre-crop-conversion) face box instead of the visible-
/// preview-space centerOffsetX/Y and faceFillRatio, which live in a
/// different coordinate space than the raw CameraImage buffer the ROI is
/// actually sampled from.
void main() {
  group('faceRoiRectInRawStreamPixels', () {
    test(
      'a face box off-center in a 720x1280 stream: the ROI lands on that '
      'box in raw pixels',
      () {
        const width = 720;
        const height = 1280;

        // A face box off-center (well left of the horizontal middle, well
        // above the vertical middle), the exact fields _assessFace stores
        // in faceReferenceGeometry (rawFaceCenterXNorm/YNorm, faceWidthNorm/
        // faceHeightNorm), all normalized against this same raw frame.
        const faceLeftPx = 120.0;
        const faceTopPx = 300.0;
        const faceWidthPx = 180.0;
        const faceHeightPx = 220.0;
        const rawCenterXNorm = (faceLeftPx + faceWidthPx / 2) / width;
        const rawCenterYNorm = (faceTopPx + faceHeightPx / 2) / height;
        const rawFaceWidthNorm = faceWidthPx / width;
        const rawFaceHeightNorm = faceHeightPx / height;

        final roi = faceRoiRectInRawStreamPixels(
          rawCenterXNorm: rawCenterXNorm,
          rawCenterYNorm: rawCenterYNorm,
          rawFaceWidthNorm: rawFaceWidthNorm,
          rawFaceHeightNorm: rawFaceHeightNorm,
          width: width,
          height: height,
        );

        // The ROI must be centered on the face box's own center, in RAW
        // pixel coordinates -- not shifted toward the frame's own center,
        // and not scaled against some other (e.g. guide-relative) area.
        const expectedCenterX = faceLeftPx + faceWidthPx / 2;
        const expectedCenterY = faceTopPx + faceHeightPx / 2;
        final roiCenterX = (roi.left + roi.right) / 2;
        final roiCenterY = (roi.top + roi.bottom) / 2;
        expect(roiCenterX, closeTo(expectedCenterX, 1.0));
        expect(roiCenterY, closeTo(expectedCenterY, 1.0));

        // The ROI must actually overlap the face box, not land elsewhere
        // in the frame (e.g. at the visible-preview guide's center).
        expect(roi.right, greaterThan(faceLeftPx));
        expect(roi.left, lessThan(faceLeftPx + faceWidthPx));
        expect(roi.bottom, greaterThan(faceTopPx));
        expect(roi.top, lessThan(faceTopPx + faceHeightPx));

        // Size rule, unchanged from before this fix: fill is the raw face
        // box's own area fraction of the full raw frame (not the
        // guide-relative faceFillRatio), clamped to [0.10, 0.40], then
        // roiW = width*sqrt(fill)*0.90, roiH = height*sqrt(fill)*1.05.
        const rawFill = rawFaceWidthNorm * rawFaceHeightNorm;
        final expectedFill = rawFill.clamp(0.10, 0.40);
        final expectedRoiW = (width * math.sqrt(expectedFill) * 0.90)
            .round()
            .clamp(24, width);
        final expectedRoiH = (height * math.sqrt(expectedFill) * 1.05)
            .round()
            .clamp(24, height);
        expect(roi.right - roi.left, closeTo(expectedRoiW, 1));
        expect(roi.bottom - roi.top, closeTo(expectedRoiH, 1));

        // Always fully inside the raw frame.
        expect(roi.left, greaterThanOrEqualTo(0));
        expect(roi.top, greaterThanOrEqualTo(0));
        expect(roi.right, lessThanOrEqualTo(width));
        expect(roi.bottom, lessThanOrEqualTo(height));
      },
    );

    test('the ROI stays fully inside the frame for a face near an edge', () {
      final roi = faceRoiRectInRawStreamPixels(
        rawCenterXNorm: 0.02,
        rawCenterYNorm: 0.02,
        rawFaceWidthNorm: 0.15,
        rawFaceHeightNorm: 0.15,
        width: 720,
        height: 1280,
      );

      expect(roi.left, greaterThanOrEqualTo(0));
      expect(roi.top, greaterThanOrEqualTo(0));
      expect(roi.right, lessThanOrEqualTo(720));
      expect(roi.bottom, lessThanOrEqualTo(1280));
    });
  });
}
