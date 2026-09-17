import 'package:aesthetic_skin_tracker/utils/severity_band.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('severityBandLabel', () {
    test('returns null for null or non-finite scores', () {
      expect(severityBandLabel(null), isNull);
      expect(severityBandLabel(double.nan), isNull);
      expect(severityBandLabel(double.infinity), isNull);
    });

    test('the 4-photo calibration sample lands in the expected bands', () {
      // These are the exact real photo-to-score pairs used to derive the
      // boundary constants -- if this ever fails, the boundaries have
      // drifted from the sample they were calibrated against.
      expect(severityBandLabel(28.7), 'Almost Clear');
      expect(severityBandLabel(49.3), 'Mild');
      expect(severityBandLabel(51.3), 'Moderate');
      expect(severityBandLabel(72.7), 'Severe');
    });

    test('buckets a range of scores into the correct band', () {
      expect(severityBandLabel(0.0), 'Clear');
      expect(severityBandLabel(5.0), 'Clear');
      expect(severityBandLabel(5.1), 'Almost Clear');
      expect(severityBandLabel(20.0), 'Almost Clear');
      expect(severityBandLabel(39.0), 'Almost Clear');
      expect(severityBandLabel(39.1), 'Mild');
      expect(severityBandLabel(45.0), 'Mild');
      expect(severityBandLabel(50.0), 'Mild');
      expect(severityBandLabel(50.1), 'Moderate');
      expect(severityBandLabel(60.0), 'Moderate');
      expect(severityBandLabel(65.0), 'Moderate');
      expect(severityBandLabel(65.1), 'Severe');
      expect(severityBandLabel(90.0), 'Severe');
      expect(severityBandLabel(100.0), 'Severe');
    });

    test('boundary constants are ordered and within 0-100', () {
      expect(kSeverityBandClearMax, lessThan(kSeverityBandAlmostClearMax));
      expect(kSeverityBandAlmostClearMax, lessThan(kSeverityBandMildMax));
      expect(kSeverityBandMildMax, lessThan(kSeverityBandModerateMax));
      expect(kSeverityBandModerateMax, lessThan(100.0));
      expect(kSeverityBandClearMax, greaterThan(0.0));
    });
  });

  group('formatScoreWithSeverityBand', () {
    test('prepends the band label for a supported metric key', () {
      expect(
        formatScoreWithSeverityBand('localized_redness', 49.3),
        'Mild (49.3)',
      );
      expect(
        formatScoreWithSeverityBand('localized_redness', 72.7),
        'Severe (72.7)',
      );
    });

    test('falls back to the plain score for an unsupported metric key, unchanged from before', () {
      expect(
        formatScoreWithSeverityBand('texture_smoothness', 58.1),
        '58.1',
      );
      expect(
        formatScoreWithSeverityBand('pigment_load', 61.3),
        '61.3',
        reason: 'pigment_load is explicitly deferred until it has its own '
            'calibration sample',
      );
    });
  });
}
