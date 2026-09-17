import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only explicit trackProcedure purpose enables reference locking', () {
    expect(
      isTrackProcedureCapturePurpose(CameraCapturePurpose.trackProcedure),
      isTrue,
    );
    for (final purpose in CameraCapturePurpose.values.where(
      (value) => value != CameraCapturePurpose.trackProcedure,
    )) {
      expect(isTrackProcedureCapturePurpose(purpose), isFalse);
      expect(referencePoseLockingEnabled(purpose), isFalse);
    }
    expect(
      referencePoseLockingEnabled(CameraCapturePurpose.trackProcedure),
      isTrue,
    );
  });

  test('AI multi-frame capture requires the AI Skin Analysis purpose', () {
    expect(
      () => CameraScreen(
        aiMultiFrameCapture: true,
        capturePurpose: CameraCapturePurpose.trackProcedure,
      ),
      throwsAssertionError,
    );
    expect(
      () => const CameraScreen(
        aiMultiFrameCapture: true,
        capturePurpose: CameraCapturePurpose.aiSkinAnalysis,
      ),
      returnsNormally,
    );
  });

  test('all current CameraScreen callers declare their purpose explicitly', () {
    const expectedByFile = <String, List<String>>{
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart': [
        'CameraCapturePurpose.aiSkinAnalysis',
      ],
      'lib/screens/procedure_camera_guide_screen.dart': [
        'CameraCapturePurpose.trackProcedure',
      ],
      'lib/features/procedures/presentation/procedure_profiles_screen.dart': [
        'CameraCapturePurpose.trackProcedure',
      ],
      'lib/screens/home_screen.dart': [
        'CameraCapturePurpose.skincareTracking',
        'CameraCapturePurpose.trackProcedure',
      ],
      'lib/screens/active_skincare_details_screen.dart': [
        'CameraCapturePurpose.skincareTracking',
      ],
      'lib/challenges/glow_up_challenge_screen.dart': [
        'CameraCapturePurpose.challenge',
      ],
      'lib/challenges/year_end_challenge_screen.dart': [
        'CameraCapturePurpose.trackProcedure',
        'CameraCapturePurpose.challenge',
      ],
      'lib/screens/peptide_tracker_screen.dart': [
        'CameraCapturePurpose.trackProcedure',
      ],
      'lib/main.dart': ['CameraCapturePurpose.generic'],
    };

    for (final entry in expectedByFile.entries) {
      final source = File(entry.key).readAsStringSync();
      for (final expectedPurpose in entry.value) {
        expect(source, contains(expectedPurpose), reason: entry.key);
      }
    }

      final callerSources = expectedByFile.keys
        .map((path) => File(path).readAsStringSync())
        .join('\n');
      final constructorCalls = RegExp(r'CameraScreen\s*\(')
        .allMatches(callerSources)
        .length;
      final explicitPurposes = RegExp(r'capturePurpose\s*:')
        .allMatches(callerSources)
        .length;
      expect(explicitPurposes, constructorCalls);
  });

  test('locked procedure reference prefers the first baseline for that procedure', () {
    ScanHistoryEntry entry({
      required String id,
      required String procedureId,
      required DateTime timestamp,
      bool isBaseline = false,
    }) => ScanHistoryEntry(
      id: id,
      timestamp: timestamp,
      procedureId: procedureId,
      estimatedSkinAge: 0,
      metrics: const {},
      isBaseline: isBaseline,
    );

    final history = [
      entry(
        id: 'later-preferred',
        procedureId: 'procedure-a',
        timestamp: DateTime(2026, 2, 1),
      ),
      entry(
        id: 'locked-first',
        procedureId: 'procedure-a',
        timestamp: DateTime(2026, 1, 1),
        isBaseline: true,
      ),
      entry(
        id: 'other-procedure',
        procedureId: 'procedure-b',
        timestamp: DateTime(2025, 1, 1),
        isBaseline: true,
      ),
    ];

    expect(
      lockedProcedureReference(history, 'procedure-a')?.id,
      'locked-first',
    );
    expect(lockedProcedureReference(history, 'procedure-b')?.id, 'other-procedure');
    expect(lockedProcedureReference(history, 'missing'), isNull);
  });

  test('body reference score separates matched and poorly aligned geometry', () {
    const reference = {
      'shoulderWidthNorm': 0.40,
      'hipWidthNorm': 0.36,
      'shoulderToHipRatio': 1.11,
      'centerOffsetX': 0.0,
      'centerOffsetY': 0.0,
    };
    const matched = {
      'shoulderWidthNorm': 0.41,
      'hipWidthNorm': 0.35,
      'shoulderToHipRatio': 1.10,
      'centerOffsetX': 0.01,
      'centerOffsetY': -0.01,
    };
    const poor = {
      'shoulderWidthNorm': 0.18,
      'hipWidthNorm': 0.62,
      'shoulderToHipRatio': 0.35,
      'centerOffsetX': 0.30,
      'centerOffsetY': 0.25,
    };

    expect(bodyReferenceAlignmentScore(reference, matched), greaterThan(82));
    expect(
      bodyReferenceAlignmentScore(reference, poor),
      lessThan(minimumComparableReferenceAlignmentScore),
    );
    expect(bodyReferenceAlignmentScore(null, matched), isNull);
  });

  test('face reference score separates matched and poorly aligned geometry', () {
    const reference = {
      'eyeDistanceNorm': 0.22,
      'faceWidthNorm': 0.48,
      'faceHeightNorm': 0.62,
      'faceAspectRatio': 0.77,
      'centerOffsetX': 0.0,
      'centerOffsetY': 0.0,
    };
    const matched = {
      'eyeDistanceNorm': 0.225,
      'faceWidthNorm': 0.49,
      'faceHeightNorm': 0.61,
      'faceAspectRatio': 0.78,
      'centerOffsetX': 0.01,
      'centerOffsetY': -0.01,
    };
    const poor = {
      'eyeDistanceNorm': 0.08,
      'faceWidthNorm': 0.25,
      'faceHeightNorm': 0.30,
      'faceAspectRatio': 1.30,
      'centerOffsetX': 0.30,
      'centerOffsetY': 0.25,
    };

    expect(faceReferenceAlignmentScore(reference, matched), greaterThan(82));
    expect(
      faceReferenceAlignmentScore(reference, poor),
      lessThan(minimumComparableReferenceAlignmentScore),
    );
    expect(faceReferenceAlignmentScore(null, matched), isNull);
  });
}