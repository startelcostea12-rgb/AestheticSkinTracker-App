import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/ai_scan_frame_exposure.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _baseline({required double? iso, required double? bv}) =>
    <String, dynamic>{
      aiScanPerFrameDiagnosticsKey: [
        for (var i = 0; i < 3; i++) {'iso': iso, 'brightness_value': bv},
      ],
    };

List<AiScanFrameExposure> _frames({int? iso = 400, double? bv}) => [
  for (var i = 0; i < 3; i++)
    AiScanFrameExposure(iso: iso, brightnessValue: bv),
];

void main() {
  group('aiScanPreUploadLightingCheck', () {
    test('a brightness move past the existing rule would lock', () {
      final check = aiScanPreUploadLightingCheck(
        frameExposure: _frames(bv: 2.60),
        baselinePayload: _baseline(iso: 400, bv: 1.44),
      );
      expect(check.wouldLock, isTrue);
      expect(check.missingExposure, isFalse);
      expect(check.currentBrightnessValue, 2.60);
      expect(check.baselineBrightnessValue, 1.44);
    });

    test('matched lamp light does not lock', () {
      final check = aiScanPreUploadLightingCheck(
        frameExposure: _frames(bv: 1.60),
        baselinePayload: _baseline(iso: 400, bv: 1.44),
      );
      expect(check.wouldLock, isFalse);
      expect(check.missingExposure, isFalse);
    });

    test('agrees with lockTrendsForLightingMismatch on the same payloads', () {
      for (final bv in [0.30, 0.44, 1.44, 2.44, 2.60]) {
        final baseline = _baseline(iso: 400, bv: 1.44);
        final frames = _frames(bv: bv);
        final resultsLock =
            lockTrendsForLightingMismatch(
              trendStatus: const {'texture_smoothness': 'stable'},
              trendDeltas: const {'texture_smoothness': 0.0},
              trendLockReasons: const {},
              currentPayload: {
                aiScanPerFrameDiagnosticsKey: [
                  for (final f in frames) f.toJson(),
                ],
              },
              baselinePayload: baseline,
            ).trendLockReasons['texture_smoothness'] ==
            'lighting_mismatch';
        final check = aiScanPreUploadLightingCheck(
          frameExposure: frames,
          baselinePayload: baseline,
        );
        expect(check.wouldLock, resultsLock, reason: 'bv=$bv');
      }
    });

    test('missing exposure is reported, not offered as a retake', () {
      final check = aiScanPreUploadLightingCheck(
        frameExposure: _frames(bv: 1.50),
        baselinePayload: _baseline(iso: 400, bv: null),
      );
      expect(check.wouldLock, isFalse);
      expect(check.missingExposure, isTrue);
    });

    test('no baseline never prompts', () {
      final check = aiScanPreUploadLightingCheck(
        frameExposure: _frames(bv: 5.0),
        baselinePayload: null,
      );
      expect(check.wouldLock, isFalse);
      expect(check.missingExposure, isFalse);
    });
  });

  test('the check runs after the baseline resolves and before upload', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    final run = source.indexOf('Future<void> _runAnalysis() async {');
    final baseline = source.indexOf('await _getPreviousMetrics();', run);
    final check = source.indexOf('aiScanPreUploadLightingCheck(', run);
    final upload = source.indexOf('analyzeBackendFrames(', run);
    expect(run, isNonNegative);
    expect(baseline, greaterThan(run));
    expect(check, greaterThan(baseline));
    expect(upload, greaterThan(check));
    expect(source, contains("'Retake under your lamp'"));
  });
}
