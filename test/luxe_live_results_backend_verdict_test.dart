import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';

/// Covers the fix for the live AI Skin Analysis results screen ignoring the
/// backend's own trend verdict: _buildLuxeResultsPayload used to include
/// trend_deltas but never trend_status/trend_lock_reasons, so every card
/// fell back to LuxeReportLayout's local recompute (flat 8% / 2.0pt bands,
/// no per-metric noise floor) and could show "Worsened +25.1%" on a metric
/// the backend had actually judged "insufficient_signal".
///
/// LuxeReportLayout.requireBackendVerdict: true is what the live results
/// screen now passes so every card and the clinical progress summary use
/// ONLY the backend's trend_status/trend_lock_reason -- never a locally
/// recomputed number -- and a metric with no backend verdict at all reads
/// as "No verdict" rather than silently falling back to a guess.
void main() {
  // Matches the live results screen's own scaffolding, which always wraps
  // LuxeReportLayout in a scroll view -- some of the honest-label wording
  // below ("Not enough signal: ...") is longer than the old one-word labels
  // and only fits on a fixed-height test surface with room to scroll.
  Widget harness(Map<String, dynamic> payload) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LuxeReportLayout(rawPayload: payload, requireBackendVerdict: true),
        ),
      ),
    );
  }

  Map<String, dynamic> basePayload({
    required double baseline,
    required double current,
    String metricKey = 'pigment_load',
    Map<String, dynamic>? trendDeltas,
    Map<String, dynamic>? trendStatus,
    Map<String, dynamic>? trendLockReasons,
  }) {
    return <String, dynamic>{
      'is_follow_up': true,
      'local_history_count': 2,
      'metric_matrix': <String, dynamic>{metricKey: current},
      'baseline_metric_matrix': <String, dynamic>{metricKey: baseline},
      'metric_extraction_paths': <String, dynamic>{metricKey: 'primary_roi'},
      'baseline_metric_extraction_paths': <String, dynamic>{
        metricKey: 'primary_roi',
      },
      if (trendDeltas != null) 'trend_deltas': trendDeltas,
      if (trendStatus != null) 'trend_status': trendStatus,
      if (trendLockReasons != null) 'trend_lock_reasons': trendLockReasons,
    };
  }

  testWidgets(
    'backend "stable" with no lock reason: no arrow, no percent',
    (tester) async {
      final payload = basePayload(
        baseline: 22.3,
        current: 27.9,
        trendDeltas: {'pigment_load': 0.0},
        trendStatus: {'pigment_load': 'stable'},
      );

      await tester.pumpWidget(harness(payload));
      await tester.pumpAndSettle();

      expect(find.text('Stable - change within tracking noise'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
      expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    },
  );

  testWidgets(
    'backend "insufficient_signal": not-enough-signal label, no percent',
    (tester) async {
      final payload = basePayload(
        baseline: 22.3,
        current: 27.9,
        trendDeltas: {'pigment_load': 0.0},
        trendStatus: {'pigment_load': 'insufficient_signal'},
      );

      await tester.pumpWidget(harness(payload));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Not enough signal: change is smaller than this metric's "
          'measurement noise',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
      expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    },
  );

  testWidgets(
    'backend sent no trend_status at all: "No verdict for this metric", no percent',
    (tester) async {
      // No trend_deltas/trend_status/trend_lock_reasons keys at all -- the
      // exact shape a real backend build that doesn't trend this metric (or
      // an in-between app state) would send.
      final payload = basePayload(baseline: 22.3, current: 27.9);

      await tester.pumpWidget(harness(payload));
      await tester.pumpAndSettle();

      expect(find.text('No verdict for this metric'), findsOneWidget);
      expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
      expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    },
  );

  testWidgets(
    'a lock reason shows "Not comparable: <reason>", never plain "Stable", no percent',
    (tester) async {
      final payload = basePayload(
        baseline: 22.3,
        current: 27.9,
        trendDeltas: {'pigment_load': 0.0},
        trendStatus: {'pigment_load': 'stable'},
        trendLockReasons: {'pigment_load': 'angle_or_guide_mismatch'},
      );

      await tester.pumpWidget(harness(payload));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not comparable:'), findsOneWidget);
      expect(find.text('Stable - change within tracking noise'), findsNothing);
      expect(find.text('Stable'), findsNothing);
      expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
      expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
      expect(find.byIcon(Icons.trending_flat_rounded), findsNothing);
      final label = tester.widget<Text>(find.textContaining('Not comparable:'));
      expect(label.style?.color, const Color(0xFF8E7F6D));
      final card = find.byKey(const ValueKey('result_metric_pigment_load'));
      expect(
        find.descendant(of: card, matching: find.textContaining('%')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a lock reason without trend status or delta still shows Not comparable',
    (tester) async {
      final payload = basePayload(
        baseline: 22.3,
        current: 27.9,
        trendLockReasons: {'pigment_load': 'lighting_mismatch'},
      );

      await tester.pumpWidget(harness(payload));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not comparable:'), findsOneWidget);
      expect(find.text('No verdict for this metric'), findsNothing);
      expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
      expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    },
  );

  testWidgets(
    'backend "worsened" keeps its verdict and score without a percent',
    (tester) async {
      final payload = basePayload(
        baseline: 22.3,
        current: 27.9,
        trendDeltas: {'pigment_load': 25.1},
        trendStatus: {'pigment_load': 'worsened'},
      );

      await tester.pumpWidget(harness(payload));
      await tester.pumpAndSettle();

      expect(find.text('Worsened'), findsWidgets);
      expect(find.textContaining('27.9'), findsWidgets);
      expect(find.text('Pigment Load: Worsened.'), findsOneWidget);
      final card = find.byKey(const ValueKey('result_metric_pigment_load'));
      expect(
        find.descendant(of: card, matching: find.textContaining('%')),
        findsNothing,
      );
      expect(find.textContaining('25.1%'), findsNothing);
    },
  );

  testWidgets('unlocked texture still says Stable without a percent', (
    tester,
  ) async {
    final payload = basePayload(
      baseline: 42.0,
      current: 42.5,
      metricKey: 'texture_smoothness',
      trendStatus: {'texture_smoothness': 'stable'},
      trendDeltas: {'texture_smoothness': 1.2},
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_texture_smoothness'));
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Stable - change within tracking noise'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('42.5')),
      findsWidgets,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('%')),
      findsNothing,
    );
  });

  testWidgets(
    'without requireBackendVerdict, a missing trend_status still falls back '
    'to the legacy local recompute (Track Procedure / progress report / '
    'history keep their existing behavior)',
    (tester) async {
      final payload = basePayload(baseline: 22.3, current: 27.9);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LuxeReportLayout(rawPayload: payload),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No verdict for this metric'), findsNothing);
      // pigment_load is higher-is-worse; 22.3 -> 27.9 is a >8% increase
      // with matching extraction paths, so the legacy recompute calls it
      // Worsened -- exactly the pre-existing (if imprecise) behavior for any
      // caller that hasn't opted into requireBackendVerdict.
      expect(find.text('Worsened'), findsWidgets);
    },
  );
}
