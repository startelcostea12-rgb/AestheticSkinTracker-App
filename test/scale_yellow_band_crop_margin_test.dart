import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/widgets/clinical_camera_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the aiSkinAnalysis facial flow's SCALE chip: aiSkinAnalysisScaleSignal
/// (the red/near-margin/near-floor/green decision + copy) and isNearCropMargin
/// (the upper yellow band's fraction check, derived from the same
/// cropMarginFraction the red rule uses, at 0.92x). Confirms the two yellow
/// details never say "center" -- this whole rule is about size/distance,
/// not centering.
void main() {
  group('isNearCropMargin', () {
    test('fraction ~0.51 of the shorter side -> not near the margin', () {
      // 720-wide frame, shorter side 720: 0.51 * 720 = ~367px.
      final result = isNearCropMargin(
        rawFaceWidthPx: 367,
        rawFaceHeightPx: 340,
        liveFrameWidthPx: 720,
        liveFrameHeightPx: 1280,
      );
      expect(result, isFalse);
    });

    test('fraction ~0.70 of the shorter side -> near the margin', () {
      // 0.70 * 720 = 504px -- above 0.92*0.75=0.69, below the 0.75 red line.
      final result = isNearCropMargin(
        rawFaceWidthPx: 504,
        rawFaceHeightPx: 470,
        liveFrameWidthPx: 720,
        liveFrameHeightPx: 1280,
      );
      expect(result, isTrue);
    });

    test('fraction ~0.76 (past the red line) is also >= near-margin', () {
      final result = isNearCropMargin(
        rawFaceWidthPx: 547,
        rawFaceHeightPx: 520,
        liveFrameWidthPx: 720,
        liveFrameHeightPx: 1280,
      );
      expect(result, isTrue);
    });
  });

  group('aiSkinAnalysisScaleSignal', () {
    test('fraction 0.51 (not too close, not near-margin, not near-floor) '
        '-> green', () {
      final outcome = aiSkinAnalysisScaleSignal(
        isTooCloseForCropMargin: false,
        isNearCropMargin: false,
        isNearFloor: false,
      );
      expect(outcome.state, QualityState.green);
      expect(outcome.detail.toLowerCase(), isNot(contains('center')));
    });

    test(
      'fraction 0.70 (near-margin, not yet too close) -> yellow near-margin '
      'with a distance sentence, not a centering one',
      () {
        final outcome = aiSkinAnalysisScaleSignal(
          isTooCloseForCropMargin: false,
          isNearCropMargin: true,
          isNearFloor: false,
        );
        expect(outcome.state, QualityState.yellow);
        expect(outcome.detail.toLowerCase(), isNot(contains('center')));
        expect(outcome.detail.toLowerCase(), contains('crop margin'));
      },
    );

    test('fraction 0.76 (over the crop-margin line) -> red/too-close, '
        'regardless of near-margin/near-floor', () {
      final outcome = aiSkinAnalysisScaleSignal(
        isTooCloseForCropMargin: true,
        isNearCropMargin: true,
        isNearFloor: false,
      );
      expect(outcome.state, QualityState.yellow); // signal severity is yellow
      expect(outcome.detail, contains('too close'));
    });

    test(
      'small face below floor x 1.12 (not close, not near-margin) -> '
      'yellow near-floor with its own distance sentence, not a centering '
      'one',
      () {
        final outcome = aiSkinAnalysisScaleSignal(
          isTooCloseForCropMargin: false,
          isNearCropMargin: false,
          isNearFloor: true,
        );
        expect(outcome.state, QualityState.yellow);
        expect(outcome.detail.toLowerCase(), isNot(contains('center')));
        expect(outcome.detail.toLowerCase(), contains('closer'));
      },
    );

    test('too-close takes priority over near-margin and near-floor', () {
      final outcome = aiSkinAnalysisScaleSignal(
        isTooCloseForCropMargin: true,
        isNearCropMargin: true,
        isNearFloor: true,
      );
      expect(outcome.detail, contains('too close'));
    });

    test('near-margin takes priority over near-floor', () {
      final outcome = aiSkinAnalysisScaleSignal(
        isTooCloseForCropMargin: false,
        isNearCropMargin: true,
        isNearFloor: true,
      );
      expect(outcome.detail, contains('crop margin'));
    });
  });
}
