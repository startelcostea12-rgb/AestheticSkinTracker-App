import 'dart:io';

import 'package:aesthetic_skin_tracker/utils/safety_signal_defaults.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Stop inferring a rosacea score from profile words": the `rosacea_score`
/// safety field sent with a scan comes only from a stored `rosaceaSeverity`
/// value, otherwise the existing 2.5 default. Profile / notes / goals text
/// such as "redness", "flushing", "rosacea" or "vascular" must never raise it
/// (it used to jump to 6.0).
///
/// `_buildSafetySignalFields` (camera_screen.dart) and
/// `_inferSafetySignalFields` (utils/skin_analysis_service.dart) are private
/// and read SharedPreferences, so both now delegate the rosacea value to the
/// pure [resolveRosaceaSafetyScore]. That function has no text parameter at
/// all, so words cannot influence it; the source checks below pin that the two
/// callers use it and no longer carry the word-based 6.0 branch.
void main() {
  group('resolveRosaceaSafetyScore', () {
    test('keeps the existing 2.5 default when nothing is stored', () {
      expect(kDefaultRosaceaSafetyScore, 2.5);
      expect(resolveRosaceaSafetyScore(null), 2.5);
    });

    test('never invents the old 6.0 profile-word score', () {
      expect(resolveRosaceaSafetyScore(null), isNot(6.0));
    });

    test('uses a stored rosaceaSeverity when one exists', () {
      expect(resolveRosaceaSafetyScore(7.3), 7.3);
      expect(resolveRosaceaSafetyScore(0.0), 0.0);
      expect(resolveRosaceaSafetyScore(1.0), 1.0);
    });

    test('keeps the existing 0-10 clamp', () {
      expect(resolveRosaceaSafetyScore(14.0), 10.0);
      expect(resolveRosaceaSafetyScore(-3.0), 0.0);
    });

    test('formats like the request field (one decimal)', () {
      expect(resolveRosaceaSafetyScore(null).toStringAsFixed(1), '2.5');
      expect(resolveRosaceaSafetyScore(4.0).toStringAsFixed(1), '4.0');
    });
  });

  group('callers no longer infer rosacea from profile words', () {
    String functionRegion(String path, String startMarker, String endMarker) {
      final source = File(path).readAsStringSync();
      final start = source.indexOf(startMarker);
      expect(start, greaterThanOrEqualTo(0), reason: '$startMarker in $path');
      final end = source.indexOf(endMarker, start);
      expect(end, greaterThan(start), reason: '$endMarker in $path');
      return source.substring(start, end);
    }

    void expectNoWordInference(String region) {
      expect(region, contains('resolveRosaceaSafetyScore('));
      expect(region, isNot(contains('rosaceaConcern')));
      expect(region, isNot(contains('6.0')));
      expect(region, isNot(contains("'redness'")));
      expect(region, isNot(contains("'flushing'")));
      expect(region, isNot(contains("'vascular'")));
      expect(region, isNot(contains("'rosacea'")));
      expect(region, isNot(contains('defaultRosacea')));
    }

    test('camera_screen.dart _buildSafetySignalFields', () {
      expectNoWordInference(
        functionRegion(
          'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
          'Future<Map<String, String>> _buildSafetySignalFields()',
          '// ── Clinical auto-capture state',
        ),
      );
    });

    test('utils/skin_analysis_service.dart _inferSafetySignalFields', () {
      expectNoWordInference(
        functionRegion(
          'lib/utils/skin_analysis_service.dart',
          'static Future<Map<String, String>> _inferSafetySignalFields()',
          "'compromised_barrier': compromisedBarrier",
        ),
      );
    });
  });
}
