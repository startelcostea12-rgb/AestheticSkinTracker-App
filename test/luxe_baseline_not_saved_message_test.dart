import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the results-screen consistency fix: when a scan was eligible to
/// become the first baseline for its key but did NOT actually become one
/// (failed a single-scan honesty gate), LuxeReportLayout must never claim
/// "Baseline scan captured" -- it must show the rejection reason instead.
/// Passing null preserves the original heuristic-driven message for every
/// other caller (Track Procedure, progress report) unchanged.
void main() {
  // A payload that makes LuxeReportLayout's own heuristic decide "this
  // looks like a first/pending-baseline scan" (no follow-up flag, low
  // history count, every metric marked initial_baseline) -- the exact
  // shape that previously always rendered "Baseline scan captured"
  // regardless of whether a baseline was actually saved.
  const pendingBaselinePayload = <String, dynamic>{
    'initial_baseline': true,
    'local_history_count': 1,
    'metric_matrix': <String, dynamic>{'localized_redness': 20.0},
  };

  Widget harness({String? baselineNotSavedReason}) {
    return MaterialApp(
      home: Scaffold(
        body: LuxeReportLayout(
          rawPayload: pendingBaselinePayload,
          baselineNotSavedReason: baselineNotSavedReason,
        ),
      ),
    );
  }

  testWidgets(
    'with no override, shows the normal "Baseline scan captured" message',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('Baseline scan captured'), findsOneWidget);
      expect(find.textContaining('Not saved as baseline'), findsNothing);
    },
  );

  testWidgets(
    'with a rejection reason set, never claims "Baseline scan captured" '
    'and shows the reason instead',
    (tester) async {
      const reason = "Not saved as baseline: capture quality was 'blurry'.";
      await tester.pumpWidget(harness(baselineNotSavedReason: reason));
      await tester.pumpAndSettle();

      expect(find.text('Baseline scan captured'), findsNothing);
      expect(find.text('Not saved as baseline'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
    },
  );
}
