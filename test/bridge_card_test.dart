import 'package:aesthetic_skin_tracker/models/peptide_model.dart';
import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/widgets/bridge_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScanHistoryEntry scan({
    required String id,
    required DateTime timestamp,
    required Map<String, double> metrics,
    required Map<String, dynamic> rawPayload,
  }) {
    return ScanHistoryEntry(
      id: id,
      timestamp: timestamp,
      estimatedSkinAge: 0,
      procedureId: 'proc_correlation',
      metrics: metrics,
      rawPayload: rawPayload,
      captureQuality: 'normal',
    );
  }

  PeptideEntry peptide(DateTime startDate) => PeptideEntry(
    id: 'pep_correlation',
    name: 'GHK-Cu',
    frequency: 'Twice daily',
    startDate: startDate,
    category: 'anti-aging',
  );

  test('peptide correlation excludes pigment_load on the rebaselined formula', () {
    final baseline = scan(
      id: 'baseline',
      timestamp: DateTime(2026, 9, 1),
      metrics: const {'pigment_load': 45.0},
      rawPayload: const {},
    );
    final latest = scan(
      id: 'latest',
      timestamp: DateTime(2026, 9, 8),
      metrics: const {'pigment_load': 30.0},
      rawPayload: const {
        'trend_status': {'pigment_load': 'improved'},
      },
    );

    expect(
      BridgeCard.computePeptideTrendInsight(
        scans: [baseline, latest],
        latest: latest,
        activePeptides: [peptide(DateTime(2026, 8, 30))],
      ),
      isNull,
    );
  });

  test('peptide correlation still selects localized_redness and rosacea', () {
    final baseline = scan(
      id: 'baseline',
      timestamp: DateTime(2026, 9, 1),
      metrics: const {'localized_redness': 55.0},
      rawPayload: const {},
    );
    final rednessLatest = scan(
      id: 'redness_latest',
      timestamp: DateTime(2026, 9, 8),
      metrics: const {'localized_redness': 30.0},
      rawPayload: const {
        'trend_status': {'localized_redness': 'improved'},
      },
    );
    final rosaceaLatest = scan(
      id: 'rosacea_latest',
      timestamp: DateTime(2026, 9, 9),
      metrics: const {'rosacea_severity': 30.0},
      rawPayload: const {
        'trend_status': {'rosacea_severity': 'improved'},
      },
    );
    final activePeptides = [peptide(DateTime(2026, 8, 30))];

    expect(
      BridgeCard.computePeptideTrendInsight(
        scans: [baseline, rednessLatest],
        latest: rednessLatest,
        activePeptides: activePeptides,
      ),
      contains('redness has trended down'),
    );
    expect(
      BridgeCard.computePeptideTrendInsight(
        scans: [baseline, rosaceaLatest],
        latest: rosaceaLatest,
        activePeptides: activePeptides,
      ),
      contains('rosacea has trended down'),
    );
  });

  testWidgets('BridgeCard shows procedure day, active peptide, and honest downtrend', (tester) async {
    final procedure = Procedure(
      id: 'proc_1',
      type: 'Halo',
      provider: 'Dr. Lee',
      startDate: DateTime.now().subtract(const Duration(days: 11)),
      numSessions: 1,
    );

    final peptide = PeptideEntry(
      id: 'pep_1',
      name: 'GHK-Cu',
      frequency: 'Twice daily',
      startDate: DateTime.now().subtract(const Duration(days: 7)),
      category: 'anti-aging',
    );

    final scan = ScanHistoryEntry(
      id: 'scan_1',
      timestamp: DateTime.now(),
      estimatedSkinAge: 28,
      metrics: {'localized_redness': 62.0},
      captureQuality: 'normal',
      rawPayload: {
        'trend_status': {'localized_redness': 'improved'},
        'metric_extraction_paths': {'localized_redness': 'cheek_primary'},
        'baseline_metric_extraction_paths': {'localized_redness': 'cheek_primary'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: BridgeCard(
                activeProcedure: procedure,
                activePeptides: [peptide],
                scans: [scan],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Day 12 post-Halo'), findsOneWidget);
    expect(find.textContaining('on GHK-Cu'), findsOneWidget);
    expect(find.textContaining('redness trending down since baseline'), findsOneWidget);
  });

  testWidgets('BridgeCard falls back to neutral tracking when honesty guard forces stable', (tester) async {
    final procedure = Procedure(
      id: 'proc_2',
      type: 'Halo',
      provider: 'Dr. Lee',
      startDate: DateTime.now().subtract(const Duration(days: 8)),
      numSessions: 1,
    );

    final scan = ScanHistoryEntry(
      id: 'scan_2',
      timestamp: DateTime.now(),
      estimatedSkinAge: 29,
      metrics: {'localized_redness': 56.0},
      captureQuality: 'low_light',
      rawPayload: {
        'trend_status': {'localized_redness': 'improved'},
        'metric_extraction_paths': {'localized_redness': 'cheek_primary'},
        'baseline_metric_extraction_paths': {'localized_redness': 'jawline'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: BridgeCard(
                activeProcedure: procedure,
                scans: [scan],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('steady since baseline'), findsOneWidget);
    expect(find.textContaining('redness trending down since baseline'), findsNothing);
  });

  testWidgets('BridgeCard keeps "steady since baseline" for a genuine small-delta stable trend', (tester) async {
    final procedure = Procedure(
      id: 'proc_stable_genuine',
      type: 'Halo',
      provider: 'Dr. Lee',
      startDate: DateTime.now().subtract(const Duration(days: 8)),
      numSessions: 1,
    );

    final scan = ScanHistoryEntry(
      id: 'scan_stable_genuine',
      timestamp: DateTime.now(),
      estimatedSkinAge: 29,
      metrics: {'localized_redness': 51.0},
      captureQuality: 'normal',
      rawPayload: {
        'trend_status': {'localized_redness': 'stable'},
        'trend_lock_reasons': {'localized_redness': null},
        'metric_extraction_paths': {'localized_redness': 'cheek_primary'},
        'baseline_metric_extraction_paths': {'localized_redness': 'cheek_primary'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: BridgeCard(
                activeProcedure: procedure,
                scans: [scan],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('steady since baseline'), findsOneWidget);
  });

  testWidgets('BridgeCard shows a distinct standalone-entry label when "stable" is a capture_quality_mismatch lock', (tester) async {
    final procedure = Procedure(
      id: 'proc_stable_locked',
      type: 'Halo',
      provider: 'Dr. Lee',
      startDate: DateTime.now().subtract(const Duration(days: 8)),
      numSessions: 1,
    );

    final scan = ScanHistoryEntry(
      id: 'scan_stable_locked',
      timestamp: DateTime.now(),
      estimatedSkinAge: 29,
      metrics: {'localized_redness': 56.0},
      captureQuality: 'normal',
      rawPayload: {
        'trend_status': {'localized_redness': 'stable'},
        'trend_lock_reasons': {'localized_redness': 'capture_quality_mismatch'},
        'metric_extraction_paths': {'localized_redness': 'cheek_primary'},
        'baseline_metric_extraction_paths': {'localized_redness': 'cheek_primary'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: BridgeCard(
                activeProcedure: procedure,
                scans: [scan],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Standalone entry'), findsOneWidget);
    expect(find.textContaining('steady since baseline'), findsNothing);
  });

  testWidgets('BridgeCard shows a distinct standalone-entry label when "stable" is a resolution_mismatch lock', (tester) async {
    final procedure = Procedure(
      id: 'proc_stable_res_locked',
      type: 'Halo',
      provider: 'Dr. Lee',
      startDate: DateTime.now().subtract(const Duration(days: 8)),
      numSessions: 1,
    );

    final scan = ScanHistoryEntry(
      id: 'scan_stable_res_locked',
      timestamp: DateTime.now(),
      estimatedSkinAge: 29,
      metrics: {'localized_redness': 56.0},
      captureQuality: 'normal',
      rawPayload: {
        'trend_status': {'localized_redness': 'stable'},
        'trend_lock_reasons': {'localized_redness': 'resolution_mismatch'},
        'metric_extraction_paths': {'localized_redness': 'cheek_primary'},
        'baseline_metric_extraction_paths': {'localized_redness': 'cheek_primary'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: BridgeCard(
                activeProcedure: procedure,
                scans: [scan],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Standalone entry'), findsOneWidget);
    expect(find.textContaining('resolution'), findsOneWidget);
    expect(find.textContaining('steady since baseline'), findsNothing);
  });

  testWidgets('BridgeCard shows baseline-set wording before a valid comparison exists', (tester) async {
    final procedure = Procedure(
      id: 'proc_3',
      type: 'Halo',
      provider: 'Dr. Lee',
      startDate: DateTime.now().subtract(const Duration(days: 2)),
      numSessions: 1,
    );

    final scan = ScanHistoryEntry(
      id: 'scan_3',
      timestamp: DateTime.now(),
      estimatedSkinAge: 30,
      metrics: {'localized_redness': 44.0},
      captureQuality: 'normal',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: BridgeCard(
                activeProcedure: procedure,
                scans: [scan],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Day 3 post-Halo'), findsOneWidget);
    expect(find.textContaining('baseline set'), findsOneWidget);
  });

  testWidgets('BridgeCard shows neutral recovery fallback when no active procedure is set', (tester) async {
    final scan = ScanHistoryEntry(
      id: 'scan_4',
      timestamp: DateTime.now(),
      estimatedSkinAge: 30,
      metrics: {'localized_redness': 52.0},
      captureQuality: 'normal',
      procedure: 'AI Skin Analysis',
      rawPayload: {
        'trend_status': {'localized_redness': 'stable'},
        'metric_extraction_paths': {'localized_redness': 'cheek_primary'},
        'baseline_metric_extraction_paths': {'localized_redness': 'cheek_primary'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: BridgeCard(
                activeProcedure: null,
                scans: [scan],
                activePeptides: [
                  PeptideEntry(
                    id: 'pep_2',
                    name: 'GHK-Cu',
                    frequency: 'Twice daily',
                    startDate: DateTime.now().subtract(const Duration(days: 5)),
                    category: 'anti-aging',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Recovery check-in'), findsOneWidget);
    expect(find.textContaining('on GHK-Cu'), findsOneWidget);
    expect(find.textContaining('Day '), findsNothing);
    expect(find.textContaining('post-AI Skin Analysis'), findsNothing);
  });

  testWidgets('Age estimate shows neutral state when capture quality is poor', (tester) async {
    final scan = ScanHistoryEntry(
      id: 'scan_5',
      timestamp: DateTime.now(),
      estimatedSkinAge: 47,
      metrics: {
        'redness': 42.0,
        'texture': 57.0,
        'wrinkle': 62.0,
        'pore': 61.0,
        'darkSpots': 48.0,
        'elasticity': 58.0,
      },
      captureQuality: 'low_light',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: BridgeCard(
                scans: [scan],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Estimate unavailable'), findsOneWidget);
    expect(find.textContaining('47'), findsNothing);
    expect(find.textContaining('years'), findsNothing);
  });
}
