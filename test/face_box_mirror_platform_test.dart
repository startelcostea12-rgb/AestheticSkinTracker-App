import 'package:camera/camera.dart';
import 'package:aesthetic_skin_tracker/utils/landmark_assessment_mlkit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers shouldMirrorFaceBoxForPreview -- the platform-dependent decision
/// of whether analyzeLiveLandmarks must apply its own X mirror flip before
/// comparing a live face box to the guide.
///
/// iOS already mirrors the front camera's video-data-output connection
/// natively (camera_avfoundation's DefaultCamera.createConnection sets
/// isVideoMirrored = true on the same buffer that feeds both the on-screen
/// preview and this CameraImage stream), so flipping again in Dart would
/// double-mirror it back to raw-sensor orientation. Android has no
/// equivalent for the analysis buffer -- only the on-screen preview WIDGET
/// is mirrored, separately, via Transform.scale -- so the Dart-side flip
/// is the only correction needed there.
void main() {
  group('shouldMirrorFaceBoxForPreview', () {
    test('iOS front camera does not flip X (already mirrored natively)', () {
      final result = shouldMirrorFaceBoxForPreview(
        lensDirection: CameraLensDirection.front,
        isIOS: true,
      );
      expect(result, isFalse);
    });

    test('Android front camera still flips X (no native mirror exists)', () {
      final result = shouldMirrorFaceBoxForPreview(
        lensDirection: CameraLensDirection.front,
        isIOS: false,
      );
      expect(result, isTrue);
    });

    test('iOS back camera does not flip X', () {
      final result = shouldMirrorFaceBoxForPreview(
        lensDirection: CameraLensDirection.back,
        isIOS: true,
      );
      expect(result, isFalse);
    });

    test('Android back camera does not flip X', () {
      final result = shouldMirrorFaceBoxForPreview(
        lensDirection: CameraLensDirection.back,
        isIOS: false,
      );
      expect(result, isFalse);
    });
  });
}
