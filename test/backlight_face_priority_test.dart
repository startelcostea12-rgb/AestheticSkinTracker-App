import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers isBacklit -- the decision behind the LIGHTING chip's "Harsh
/// backlighting detected" text. Same principle as isLightingTooDark
/// (commit 67609bd): once a face ROI sample exists, backlighting is judged
/// by comparing the face against the whole-frame mean, not by the
/// whole-frame quadrant edgeDelta alone -- a well-lit face over a dim or
/// unevenly-lit background must never register as backlit.
void main() {
  group('isBacklit', () {
    test(
      'bright face, dim background, large whole-frame edgeDelta -> not '
      'backlit (face-relative rule wins; whole-frame edgeDelta ignored)',
      () {
        final result = isBacklit(
          faceRoiLuma: 127.0,
          wholeFrameMean: 101.9,
          wholeFrameEdgeDelta: 60.0, // would fail the old whole-frame rule
          backlightDeltaCeil: 42.0,
        );
        expect(result, isFalse);
      },
    );

    test(
      'face sample present, surroundings much brighter than the face -> '
      'backlit (classic backlighting: light source behind the subject)',
      () {
        final result = isBacklit(
          faceRoiLuma: 60.0,
          wholeFrameMean: 150.0, // whole frame (incl. bright background) well above face
          wholeFrameEdgeDelta: 0.0, // even if whole-frame edgeDelta is fine
          backlightDeltaCeil: 42.0,
        );
        expect(result, isTrue);
      },
    );

    test('no face sample: whole-frame edgeDelta rule applies as before', () {
      final backlit = isBacklit(
        faceRoiLuma: 0,
        wholeFrameMean: 100.0,
        wholeFrameEdgeDelta: 50.0, // above ceil
        backlightDeltaCeil: 42.0,
      );
      expect(backlit, isTrue);

      final notBacklit = isBacklit(
        faceRoiLuma: 0,
        wholeFrameMean: 100.0,
        wholeFrameEdgeDelta: 10.0, // below ceil
        backlightDeltaCeil: 42.0,
      );
      expect(notBacklit, isFalse);
    });
  });
}
