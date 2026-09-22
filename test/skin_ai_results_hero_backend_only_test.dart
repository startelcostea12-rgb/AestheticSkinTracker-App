import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the AI Skin Analysis results hero (headline + subheadline +
/// capture-quality badge), which used to be built from
/// AcneRosaceaPhotoAnalyzer's local pixel-heuristic report — a
/// standalone-on-device engine never cross-checked against the real
/// backend (see [buildBackendHeroCopy]'s doc comment). It is now built
/// exclusively from [buildBackendHeroCopy]/[captureQualityBadgeLabel],
/// two top-level pure functions that take only backend-shaped inputs
/// (a metric_matrix map, a raw capture-quality tag) and nothing else —
/// no PhotoAnalysisResult, no on-device model output, no screen state.
/// That signature is itself the guarantee this asserts: there is no
/// parameter through which local-heuristic data could reach the hero.
void main() {
  group('buildBackendHeroCopy (results hero headline/subheadline)', () {
    test('empty metric_matrix (no backend data yet) is not treated as "no concern"', () {
      final copy = buildBackendHeroCopy(const {});

      expect(copy.headline, 'Scan captured');
      expect(copy.subheadline.toLowerCase(), contains('backend'));
    });

    test('never contains diagnostic condition names, even when every '
        'inflammatory backend metric is maxed out', () {
      final copy = buildBackendHeroCopy(const {
        'localized_redness': 92.0,
        'rosacea_severity': 88.0,
        'breakout_activity': 95.0,
        'pigment_load': 10.0,
        'wrinkle_load': 5.0,
        'texture_smoothness': 90.0,
      });

      for (final banned in ['acne', 'rosacea', 'telangiectasia']) {
        expect(
          copy.headline.toLowerCase(),
          isNot(contains(banned)),
          reason: 'headline must not name a condition: "${copy.headline}"',
        );
        expect(
          copy.subheadline.toLowerCase(),
          isNot(contains(banned)),
          reason: 'subheadline must not name a condition: "${copy.subheadline}"',
        );
      }
    });

    test('high localized_redness/rosacea_severity surfaces a plain-language '
        '"redness" concern, not a rosacea diagnosis', () {
      final copy = buildBackendHeroCopy(const {
        'localized_redness': 20.0,
        'rosacea_severity': 80.0,
      });

      expect(copy.headline, contains('redness'));
      expect(copy.headline, isNot(contains('rosacea')));
    });

    test('a key the backend never populated is "no data", not scored as zero '
        'concern -- a scan with only pigment_load present should not claim '
        'a calm result driven by absent redness/breakout data', () {
      final copyPigmentOnly = buildBackendHeroCopy(const {'pigment_load': 85.0});
      expect(copyPigmentOnly.headline, contains('tone evenness'));

      // Confirm it is really reading pigment_load and not silently
      // defaulting everything (including pigment) to zero.
      final copyEmpty = buildBackendHeroCopy(const {});
      expect(copyEmpty.headline, isNot(copyPigmentOnly.headline));
    });

    test('a calm scan (all real metrics low) reads as calm, in plain '
        'language', () {
      final copy = buildBackendHeroCopy(const {
        'localized_redness': 5.0,
        'rosacea_severity': 4.0,
        'breakout_activity': 3.0,
        'pigment_load': 6.0,
        'wrinkle_load': 2.0,
        'texture_smoothness': 95.0,
      });

      expect(copy.headline, 'Calm, low-concern scan');
    });

    test('texture_smoothness is inverted before ranking (higher smoothness '
        'must not read as a high texture concern)', () {
      final smoothOnly = buildBackendHeroCopy(const {'texture_smoothness': 95.0});
      final roughOnly = buildBackendHeroCopy(const {'texture_smoothness': 10.0});

      expect(smoothOnly.headline, 'Calm, low-concern scan');
      expect(roughOnly.headline, contains('texture'));
    });
  });

  group('captureQualityBadgeLabel (replaces the old confidence badge)', () {
    test('maps every known backend capture-quality tag to a plain label, '
        'never a percentage', () {
      const expected = {
        'normal': 'Good capture quality',
        'low_light': 'Low light',
        'poor_angle': 'Off angle',
        'uneven_lighting': 'Uneven lighting',
        'blurry': 'Blurry',
        'face_offcenter': 'Off-center',
      };

      for (final entry in expected.entries) {
        final label = captureQualityBadgeLabel(entry.key);
        expect(label, entry.value);
        expect(label, isNot(contains('%')));
      }
    });

    test('null/unknown/empty tag falls back to an honest "unknown" label '
        'rather than fabricating a number', () {
      expect(captureQualityBadgeLabel(null), 'Capture quality unknown');
      expect(captureQualityBadgeLabel(''), 'Capture quality unknown');
      expect(captureQualityBadgeLabel('some_future_tag'), 'Capture quality unknown');
    });

    test('is case/whitespace tolerant, matching main.py\'s '
        '_normalize_capture_quality convention', () {
      expect(captureQualityBadgeLabel(' LOW_LIGHT '), 'Low light');
    });
  });
}
