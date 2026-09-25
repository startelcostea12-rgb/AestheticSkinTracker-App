import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers isTooCloseForCropMargin -- the aiSkinAnalysis-only replacement
/// for the fill-ratio-based "too close" ceiling (commit 9f3e1b3 made the
/// old converted faceFillRatio read ~1.5x larger than it was calibrated
/// against). Two independent triggers: the raw face box's larger side
/// exceeding 75% of the live stream frame's shorter side (where the
/// auto-crop square starts clamping and the margin disappears), or any
/// part of the face box lying outside the visible preview rect.
void main() {
  group('isTooCloseForCropMargin', () {
    test(
      'larger side ~40% of the shorter side, box fully inside the visible '
      'rect -> not too close',
      () {
        // 720x1280 stream: shorter side 720. A 288px face (40% of 720).
        final result = isTooCloseForCropMargin(
          rawFaceWidthPx: 288,
          rawFaceHeightPx: 260,
          liveFrameWidthPx: 720,
          liveFrameHeightPx: 1280,
          visibleLeftNorm: 0.30,
          visibleTopNorm: 0.28,
          visibleRightNorm: 0.70,
          visibleBottomNorm: 0.68,
        );
        expect(result, isFalse);
      },
    );

    test(
      'larger side over 75% of the shorter side -> too close, even with '
      'the box still fully inside the visible rect',
      () {
        // 540px is exactly 75% of a 720 shorter side; go a bit over.
        final result = isTooCloseForCropMargin(
          rawFaceWidthPx: 560,
          rawFaceHeightPx: 520,
          liveFrameWidthPx: 720,
          liveFrameHeightPx: 1280,
          visibleLeftNorm: 0.10,
          visibleTopNorm: 0.10,
          visibleRightNorm: 0.90,
          visibleBottomNorm: 0.90,
        );
        expect(result, isTrue);
      },
    );

    test(
      'exactly at the 0.75 line is not yet too close (strictly greater-than)',
      () {
        final result = isTooCloseForCropMargin(
          rawFaceWidthPx: 540, // exactly 0.75 of 720
          rawFaceHeightPx: 500,
          liveFrameWidthPx: 720,
          liveFrameHeightPx: 1280,
          visibleLeftNorm: 0.10,
          visibleTopNorm: 0.10,
          visibleRightNorm: 0.90,
          visibleBottomNorm: 0.90,
        );
        expect(result, isFalse);
      },
    );

    test(
      'box partly outside the visible rect, same coordinate space -> too '
      'close, even when the fraction rule alone would pass',
      () {
        // Larger side well under 75% of the shorter side...
        final result = isTooCloseForCropMargin(
          rawFaceWidthPx: 200,
          rawFaceHeightPx: 180,
          liveFrameWidthPx: 720,
          liveFrameHeightPx: 1280,
          // ...but the visible-preview-space box spills past the right
          // and bottom edges of [0,1]x[0,1].
          visibleLeftNorm: 0.60,
          visibleTopNorm: 0.85,
          visibleRightNorm: 1.05,
          visibleBottomNorm: 1.10,
        );
        expect(result, isTrue);
      },
    );

    test('a box spilling past the left/top edges also counts as too close', () {
      final result = isTooCloseForCropMargin(
        rawFaceWidthPx: 200,
        rawFaceHeightPx: 180,
        liveFrameWidthPx: 720,
        liveFrameHeightPx: 1280,
        visibleLeftNorm: -0.05,
        visibleTopNorm: -0.02,
        visibleRightNorm: 0.40,
        visibleBottomNorm: 0.30,
      );
      expect(result, isTrue);
    });

    test(
      'the reported bug scenario (raw fill 0.266, converted fill 0.413, old '
      'ceiling 0.35) is not too close under the new rule at normal framing',
      () {
        // Reconstruct a plausible raw face box: on a 720x1280 stream, a
        // raw faceFillRatio of ~0.266 (face box area / full frame area)
        // with a roughly square-ish box works out to a larger side well
        // under the 0.75*720=540px line.
        final result = isTooCloseForCropMargin(
          rawFaceWidthPx: 430,
          rawFaceHeightPx: 470, // area/frame ≈ (430*470)/(720*1280) ≈ 0.218
          liveFrameWidthPx: 720,
          liveFrameHeightPx: 1280,
          visibleLeftNorm: 0.15,
          visibleTopNorm: 0.12,
          visibleRightNorm: 0.85,
          visibleBottomNorm: 0.88,
        );
        expect(result, isFalse);
      },
    );
  });
}
