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

    test('keeps explicit zero pigment baseline instead of later aliases', () {
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

      expect(pigment.baselineScore, 0.0);
      expect(pigment.hasBaselineValue, isTrue);
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
          // Real backend payloads always carry these (see
          // skin_ai_analysis_screen.dart's _mergePayloadForPersistence);
          // matching, known paths on both sides so the path-mismatch
          // honesty guard doesn't preempt the confidence/swing checks
          // this test is actually exercising.
          'metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
          },
          'baseline_metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
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
          'metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
          },
          'baseline_metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
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
      'rosacea severity shows its number without trend verdict styling',
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
          'metric_extraction_paths': <String, dynamic>{
            'rosacea_severity': 'primary_roi',
          },
          'baseline_metric_extraction_paths': <String, dynamic>{
            'rosacea_severity': 'primary_roi',
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

        expect(find.text('92.0'), findsOneWidget);
        expect(find.text('Starting point'), findsNothing);
        expect(find.text('Worsened'), findsNothing);
        expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
      },
    );

    testWidgets(
      'a genuine backend "stable" (no trend_lock_reason) keeps the plain '
      '"Stable - change within tracking noise" wording',
      (tester) async {
        final payload = <String, dynamic>{
          'is_follow_up': true,
          'local_history_count': 2,
          'metric_matrix': <String, dynamic>{
            'pigment_load': 51.0,
          },
          'baseline_metric_matrix': <String, dynamic>{
            'pigment_load': 50.0,
          },
          'metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
          },
          'baseline_metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
          },
          'trend_deltas': <String, dynamic>{'pigment_load': 0.0},
          'trend_status': <String, dynamic>{'pigment_load': 'stable'},
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LuxeReportLayout(rawPayload: payload),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Stable - change within tracking noise'),
          findsOneWidget,
        );
        expect(find.textContaining('Standalone entry'), findsNothing);
      },
    );

    testWidgets(
      'a backend "stable" forced by capture_quality_mismatch shows a '
      'distinct standalone-entry label instead of generic "Stable"',
      (tester) async {
        final payload = <String, dynamic>{
          'is_follow_up': true,
          'local_history_count': 2,
          'metric_matrix': <String, dynamic>{
            'pigment_load': 80.0,
          },
          'baseline_metric_matrix': <String, dynamic>{
            'pigment_load': 50.0,
          },
          'metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
          },
          'baseline_metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
          },
          'trend_deltas': <String, dynamic>{'pigment_load': 0.0},
          'trend_status': <String, dynamic>{'pigment_load': 'stable'},
          'trend_lock_reasons': <String, dynamic>{
            'pigment_load': 'capture_quality_mismatch',
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

        expect(
          find.text('Stable - change within tracking noise'),
          findsNothing,
        );
        expect(find.textContaining('Standalone entry'), findsWidgets);
      },
    );

    testWidgets(
      'trend lock display reads the metric-specific reason, not a wrong-level decoy',
      (tester) async {
        final payload = <String, dynamic>{
          'is_follow_up': true,
          'local_history_count': 2,
          'metric_matrix': <String, dynamic>{
            'pigment_load': 80.0,
          },
          'baseline_metric_matrix': <String, dynamic>{
            'pigment_load': 50.0,
          },
          'metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
          },
          'baseline_metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
          },
          'trend_deltas': <String, dynamic>{'pigment_load': 0.0},
          'trend_status': <String, dynamic>{'pigment_load': 'stable'},
          'trend_lock_reason': 'capture_quality_mismatch',
          'trend_lock_reasons': <String, dynamic>{
            'pigment_load': null,
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

        expect(
          find.text('Stable - change within tracking noise'),
          findsOneWidget,
        );
        expect(find.textContaining('Standalone entry'), findsNothing);
      },
    );

    testWidgets(
      'a backend "stable" forced by resolution_mismatch shows a distinct '
      'standalone-entry label instead of generic "Stable"',
      (tester) async {
        final payload = <String, dynamic>{
          'is_follow_up': true,
          'local_history_count': 2,
          'metric_matrix': <String, dynamic>{
            'pigment_load': 80.0,
          },
          'baseline_metric_matrix': <String, dynamic>{
            'pigment_load': 50.0,
          },
          'metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
          },
          'baseline_metric_extraction_paths': <String, dynamic>{
            'pigment_load': 'primary_roi',
          },
          'trend_deltas': <String, dynamic>{'pigment_load': 0.0},
          'trend_status': <String, dynamic>{'pigment_load': 'stable'},
          'trend_lock_reasons': <String, dynamic>{
            'pigment_load': 'resolution_mismatch',
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

        expect(
          find.text('Stable - change within tracking noise'),
          findsNothing,
        );
        expect(find.textContaining('Standalone entry'), findsWidgets);
      },
    );
  });
}
