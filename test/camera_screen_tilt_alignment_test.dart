import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/utils/landmark_assessment.dart';
import 'package:aesthetic_skin_tracker/widgets/clinical_camera_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bodyTiltAngleFromAssessment', () {
    test('returns shoulder tilt, completely ignoring rotationProxy (widthRatio)', () {
      // The exact bug scenario: shoulders wider than hips (rotationProxy =
      // widthRatio = 1.3), but the shoulder line itself is level. Before
      // the fix this fed into a head-tilt formula and produced ~39°.
      const assessment = LandmarkAssessment(
        available: true,
        primaryInstruction: '',
        secondaryInstruction: '',
        shoulderTilt: 0.0,
        rotationProxy: 1.3,
        mode: 'body',
      );

      expect(bodyTiltAngleFromAssessment(assessment), closeTo(0.0, 0.001));
    });

    test('correctly detects a genuine shoulder tilt', () {
      const assessment = LandmarkAssessment(
        available: true,
        primaryInstruction: '',
        secondaryInstruction: '',
        shoulderTilt: 20.0,
        rotationProxy: 1.0,
        mode: 'body',
      );

      expect(bodyTiltAngleFromAssessment(assessment), closeTo(20.0, 0.001));
    });

    test('takes the absolute value of a negative shoulder tilt', () {
      const assessment = LandmarkAssessment(
        available: true,
        primaryInstruction: '',
        secondaryInstruction: '',
        shoulderTilt: -12.0,
      );

      expect(bodyTiltAngleFromAssessment(assessment), closeTo(12.0, 0.001));
    });

    test('returns null when the assessment is unavailable', () {
      expect(bodyTiltAngleFromAssessment(LandmarkAssessment.unsupported), isNull);
    });

    test('a wide-shoulder body (widthRatio 1.5) with a level shoulder line is still ~0, not ~45', () {
      const assessment = LandmarkAssessment(
        available: true,
        primaryInstruction: '',
        secondaryInstruction: '',
        shoulderTilt: 1.0,
        rotationProxy: 1.5,
      );

      expect(bodyTiltAngleFromAssessment(assessment), closeTo(1.0, 0.001));
    });
  });

  group('headTiltAngleFromAssessment (face mode) — unchanged from original behavior', () {
    test('sums yaw+pitch+roll magnitudes when any are non-zero', () {
      const assessment = LandmarkAssessment(
        available: true,
        primaryInstruction: '',
        secondaryInstruction: '',
        yaw: 10.0,
        pitch: -5.0,
        roll: 3.0,
      );

      expect(headTiltAngleFromAssessment(assessment), closeTo(18.0, 0.001));
    });

    test('falls back to the rotationProxy+eyeTilt synthetic value when yaw/pitch/roll are all zero', () {
      const assessment = LandmarkAssessment(
        available: true,
        primaryInstruction: '',
        secondaryInstruction: '',
        yaw: 0.0,
        pitch: 0.0,
        roll: 0.0,
        rotationProxy: 0.5,
        eyeTilt: 2.0,
      );

      // (0.5 * 30).abs() + (2.0.abs() * 30) = 15 + 60 = 75
      expect(headTiltAngleFromAssessment(assessment), closeTo(75.0, 0.001));
    });

    test('falls back when yaw/pitch/roll are unset (default null -> 0)', () {
      const assessment = LandmarkAssessment(
        available: true,
        primaryInstruction: '',
        secondaryInstruction: '',
        rotationProxy: 1.3,
      );

      // This IS the face-mode fallback path, unchanged by the fix — it's
      // only wrong to reach when the assessment is actually a body pose,
      // which _CameraScreenState now avoids by calling
      // bodyTiltAngleFromAssessment instead for body mode.
      expect(headTiltAngleFromAssessment(assessment), closeTo(39.0, 0.001));
    });

    test('returns null when the assessment is unavailable', () {
      expect(headTiltAngleFromAssessment(LandmarkAssessment.unsupported), isNull);
    });
  });

  group('alignmentQualityStatus — pure red/yellow/green threshold classification', () {
    test(
        'BODY: the previously-broken scenario (shoulders wider than hips, but level '
        'and well-centered) is now green', () {
      final status = alignmentQualityStatus(
        isBodyGuide: true,
        tilt: 0.0,
        centerDelta: 0.05,
      );

      expect(status, QualityState.green);
    });

    test('BODY: a genuinely tilted shoulder line (20 degrees) is red', () {
      final status = alignmentQualityStatus(
        isBodyGuide: true,
        tilt: 20.0,
        centerDelta: 0.05,
      );

      expect(status, QualityState.red);
    });

    test('BODY: a moderately tilted shoulder line (10 degrees) is yellow', () {
      final status = alignmentQualityStatus(
        isBodyGuide: true,
        tilt: 10.0,
        centerDelta: 0.05,
      );

      expect(status, QualityState.yellow);
    });

    test('BODY: null tilt (no pose detected) is red regardless of centering', () {
      final status = alignmentQualityStatus(
        isBodyGuide: true,
        tilt: null,
        centerDelta: 0.0,
      );

      expect(status, QualityState.red);
    });

    test('BODY: the OLD widthRatio-derived tilt value for a wide-shouldered, level body '
        'was never green -- documents why the bug was real', () {
      const widthRatio = 1.3;
      final oldBuggyTilt = (widthRatio * 30.0).abs(); // == 39.0, the pre-fix formula

      final status = alignmentQualityStatus(
        isBodyGuide: true,
        tilt: oldBuggyTilt,
        centerDelta: 0.05,
      );

      expect(status, isNot(QualityState.green));
    });

    test('FACE: thresholds are unchanged -- 35 degree aggregate tilt is yellow', () {
      final status = alignmentQualityStatus(
        isBodyGuide: false,
        tilt: 35.0,
        centerDelta: 0.05,
      );

      expect(status, QualityState.yellow);
    });

    test('FACE: thresholds are unchanged -- 45 degree aggregate tilt is red', () {
      final status = alignmentQualityStatus(
        isBodyGuide: false,
        tilt: 45.0,
        centerDelta: 0.05,
      );

      expect(status, QualityState.red);
    });

    test('FACE: a level, centered face is green', () {
      final status = alignmentQualityStatus(
        isBodyGuide: false,
        tilt: 5.0,
        centerDelta: 0.05,
      );

      expect(status, QualityState.green);
    });

    test('centerDelta alone can force red/yellow independent of tilt, for both modes', () {
      expect(
        alignmentQualityStatus(isBodyGuide: true, tilt: 0.0, centerDelta: 0.40),
        QualityState.red,
      );
      expect(
        alignmentQualityStatus(isBodyGuide: false, tilt: 0.0, centerDelta: 0.30),
        QualityState.yellow,
      );
    });
  });
}
