import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';

void main() {
  group('Luxe baseline hardening', () {
    test('rejects ceiling baseline alias and keeps baseline pending', () {
      final payload = <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': <String, dynamic>{
          'localized_redness': 17.3,
        },
        'baseline_metric_matrix': <String, dynamic>{
          'calibrated_redness_score': 100.0,
        },
        'metric_confidence': <String, dynamic>{
          'localized_redness': 'medium',
        },
      };

      final metrics = LuxeMetricParser.parseTimelinePayload(payload);
      final redness = metrics.firstWhere((m) => m.key == 'localized_redness');

      expect(redness.currentScore, closeTo(17.3, 0.0001));
      expect(redness.baselineScore, 0.0);
      expect(redness.improvementPercent, 0.0);
    });

    test('accepts mid-range alias baseline for pigment after rejecting extremes', () {
      final payload = <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': <String, dynamic>{
          'pigment_load': 28.0,
        },
        'baseline_metric_matrix': <String, dynamic>{
          'pigment_score': 0.0,
          'pigment': 100.0,
          'radiance': 31.5,
        },
      };

      final metrics = LuxeMetricParser.parseTimelinePayload(payload);
      final pigment = metrics.firstWhere((m) => m.key == 'pigment_load');

      expect(pigment.baselineScore, closeTo(31.5, 0.0001));
    });

    test('captures current metric confidence from payload', () {
      final payload = <String, dynamic>{
        'is_follow_up': true,
        'local_history_count': 2,
        'metric_matrix': <String, dynamic>{
          'texture_smoothness': 56.0,
        },
        'baseline_metric_matrix': <String, dynamic>{
          'texture_smoothness': 50.0,
        },
        'metric_confidence': <String, dynamic>{
          'texture_smoothness': 'low',
        },
      };

      final metrics = LuxeMetricParser.parseTimelinePayload(payload);
      final texture = metrics.firstWhere((m) => m.key == 'texture_smoothness');

      expect(texture.baselineScore, closeTo(50.0, 0.0001));
      expect(texture.improvementPercent, closeTo(12.0, 0.0001));
      expect(texture.currentConfidence, 'low');
    });

    test('caps displayed percentage change at 100%', () {
      final display = LuxeMetricParser.formatDisplayDelta(
        baseline: 40.0,
        current: 95.0,
        deltaPct: 275.0,
      );

      expect(display, '100.0%');
    });

    test('switches to points display when baseline is below 10', () {
      final display = LuxeMetricParser.formatDisplayDelta(
        baseline: 4.0,
        current: 9.2,
        deltaPct: 130.0,
      );

      expect(display, '5.2 pts');
    });

    test('shows signed points when requested', () {
      final up = LuxeMetricParser.formatDisplayDelta(
        baseline: 3.6,
        current: 80.0,
        deltaPct: 2122.2,
        includeSign: true,
      );
      final down = LuxeMetricParser.formatDisplayDelta(
        baseline: 8.0,
        current: 2.0,
        deltaPct: -75.0,
        includeSign: true,
      );

      expect(up, '+76.4 pts');
      expect(down, '-6.0 pts');
    });

    testWidgets(
      'low confidence above metric threshold becomes insufficient signal with re-scan subtext',
      (tester) async {
        final payload = <String, dynamic>{
          'is_follow_up': true,
          'local_history_count': 2,
          'metric_matrix': <String, dynamic>{
            'pigment_load': 10.0,
          },
          'baseline_metric_matrix': <String, dynamic>{
            'pigment_load': 90.0,
          },
          'metric_confidence': <String, dynamic>{
            'pigment_load': 'low',
          },
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LuxeReportLayout(rawPayload: payload),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Insufficient signal'), findsOneWidget);
        expect(
          find.textContaining('Re-scan recommended (Lighting/Angle variance)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'medium confidence large delta still shows directional status',
      (tester) async {
        final payload = <String, dynamic>{
          'is_follow_up': true,
          'local_history_count': 2,
          'metric_matrix': <String, dynamic>{
            'pigment_load': 10.0,
          },
          'baseline_metric_matrix': <String, dynamic>{
            'pigment_load': 90.0,
          },
          'metric_confidence': <String, dynamic>{
            'pigment_load': 'medium',
          },
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LuxeReportLayout(rawPayload: payload),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Improved'), findsWidgets);
        expect(
          find.textContaining('Re-scan recommended (Lighting/Angle variance)'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'rosacea severity increase is worsened with red badge styling',
      (tester) async {
        final payload = <String, dynamic>{
          'is_follow_up': true,
          'local_history_count': 2,
          'metric_matrix': <String, dynamic>{
            'rosacea_severity': 92.0,
          },
          'baseline_metric_matrix': <String, dynamic>{
            'rosacea_severity': 12.8,
          },
          'metric_confidence': <String, dynamic>{
            'rosacea_severity': 'medium',
          },
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LuxeReportLayout(rawPayload: payload),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Worsened'), findsWidgets);
        expect(find.byIcon(Icons.trending_down_rounded), findsWidgets);

        final worsenedLabel = tester.widget<Text>(find.text('Worsened').first);
        expect(worsenedLabel.style?.color, const Color(0xFFC76A55));
      },
    );
  });
}
