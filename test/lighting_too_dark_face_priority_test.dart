import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers isLightingTooDark -- the decision _lightingFromCameraImage uses
/// for the "Dim light" warning / LIGHTING chip. Once a face ROI sample
/// exists, it alone decides tooDark; the whole-frame mean/darkRatio (which
/// include the background) are used only when there is no face sample.
void main() {
  group('isLightingTooDark', () {
    test(
      'face ROI bright + dark background -> not tooDark (face rule wins, '
      'whole-frame darkRatio/mean are ignored)',
      () {
        final result = isLightingTooDark(
          faceRoiLuma: 152.5,
          wholeFrameMean: 118.6,
          wholeFrameDarkRatio: 0.346,
          darkMeanFloor: 104,
          darkRatioCeil: 0.24,
        );
        expect(result, isFalse);
      },
    );

    test('face ROI dark -> tooDark, regardless of the whole frame', () {
      final result = isLightingTooDark(
        faceRoiLuma: 40.0,
        wholeFrameMean: 200.0, // whole frame bright -- must not save it
        wholeFrameDarkRatio: 0.0,
        darkMeanFloor: 104,
        darkRatioCeil: 0.24,
      );
      expect(result, isTrue);
    });

    test(
      'no face sample: whole-frame mean rule applies as before',
      () {
        final tooDark = isLightingTooDark(
          faceRoiLuma: 0,
          wholeFrameMean: 50.0, // below floor
          wholeFrameDarkRatio: 0.0,
          darkMeanFloor: 104,
          darkRatioCeil: 0.24,
        );
        expect(tooDark, isTrue);

        final notTooDark = isLightingTooDark(
          faceRoiLuma: 0,
          wholeFrameMean: 150.0, // above floor
          wholeFrameDarkRatio: 0.0,
          darkMeanFloor: 104,
          darkRatioCeil: 0.24,
        );
        expect(notTooDark, isFalse);
      },
    );

    test(
      'no face sample: whole-frame darkRatio rule applies as before',
      () {
        final result = isLightingTooDark(
          faceRoiLuma: 0,
          wholeFrameMean: 150.0, // above floor
          wholeFrameDarkRatio: 0.30, // above ceil
          darkMeanFloor: 104,
          darkRatioCeil: 0.24,
        );
        expect(result, isTrue);
      },
    );
  });
}
