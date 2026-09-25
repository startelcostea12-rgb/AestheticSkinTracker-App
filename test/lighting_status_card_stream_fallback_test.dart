import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers resolveReadyCameraStatusBarContent's streamLive fallback -- the
/// top status card previously claimed a lighting problem ("Needs Light" /
/// "Move to softer front light...") whenever streamLive was false,
/// regardless of the real lightingLevel, even though the LIGHTING chip
/// (which reads lightingLevel directly, with no streamLive gate) could be
/// green at the very same moment. The fallback text must now be neutral --
/// "no reading yet", not "there's a lighting problem".
///
/// Also covers the flip side: once the stream is marked live again (e.g.
/// immediately after a frame is actually processed following a pause --
/// see _startLightingStream's per-frame self-healing re-assertion of
/// _lightingStreamActive), the card must go back to using the real
/// lightingLevel instead of the generic fallback.
void main() {
  group('resolveReadyCameraStatusBarContent streamLive fallback', () {
    test('stream not live, not web -> neutral fallback, no "Needs Light"', () {
      final result = resolveReadyCameraStatusBarContent(
        streamLive: false,
        isWeb: false,
        lightingLevel: LightingLevel.unknown,
      );
      expect(result.badgeLabel, isNot('Needs Light'));
      expect(result.primaryStatus.toLowerCase(), isNot(contains('needs light')));
      expect(result.primaryStatus.toLowerCase(), isNot(contains('softer front light')));
      expect(
        (result.secondaryStatus ?? '').toLowerCase(),
        isNot(contains('front light')),
      );
    });

    test(
      'stream not live fallback text is unaffected by the last-known '
      'lightingLevel (never claims a problem it cannot currently measure)',
      () {
        for (final level in LightingLevel.values) {
          final result = resolveReadyCameraStatusBarContent(
            streamLive: false,
            isWeb: false,
            lightingLevel: level,
          );
          expect(result.badgeLabel, isNot('Needs Light'));
          expect(
            result.primaryStatus.toLowerCase(),
            isNot(contains('needs light')),
          );
        }
      },
    );

    test(
      'stream live again with an optimal reading (e.g. right after a frame '
      'arrives following a pause) -> card reports optimal, not the fallback',
      () {
        final result = resolveReadyCameraStatusBarContent(
          streamLive: true,
          isWeb: false,
          lightingLevel: LightingLevel.optimal,
        );
        expect(result.badgeLabel, 'Optimal');
        expect(result.primaryStatus.toLowerCase(), isNot(contains('needs light')));
        expect(result.primaryStatus.toLowerCase(), isNot(contains('checking')));
      },
    );

    test('web mode is unaffected by the streamLive fallback change', () {
      final result = resolveReadyCameraStatusBarContent(
        streamLive: false,
        isWeb: true,
        lightingLevel: LightingLevel.unknown,
      );
      expect(result.badgeLabel, 'Web Analysis');
    });
  });
}
