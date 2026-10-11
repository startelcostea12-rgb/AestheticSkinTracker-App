import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/utils/display_aggregation.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';

const _cheekSensitiveMetricKeys = <String>[
  'texture_smoothness',
  'pigment_load',
  'pore_visibility',
  'skin_tone_radiance_evenness',
  'structural_firmness_elasticity',
];

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
          child: LuxeReportLayout(
            rawPayload: payload,
            requireBackendVerdict: true,
          ),
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
    Map<String, dynamic>? metricRanges,
    Map<String, dynamic>? metricNoiseFloors,
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
      if (metricRanges != null)
        'multi_frame_analysis': <String, dynamic>{
          'metric_ranges': metricRanges,
        },
      if (metricNoiseFloors != null)
        'metric_noise_floor_2sd': metricNoiseFloors,
    };
  }

  Map<String, dynamic> cheekPairPayload({
    required String currentSide,
    required String baselineSide,
  }) {
    final metricMatrix = <String, dynamic>{
      'localized_redness': 24.0,
      for (final key in _cheekSensitiveMetricKeys) key: 42.0,
    };
    final baselineMetricMatrix = <String, dynamic>{
      'localized_redness': 30.0,
      for (final key in _cheekSensitiveMetricKeys) key: 40.0,
    };
    final trendStatus = <String, String>{
      'localized_redness': 'improved',
      for (final key in _cheekSensitiveMetricKeys) key: 'improved',
      'texture_smoothness': 'stable',
    };
    final trendDeltas = <String, double>{
      'localized_redness': -20.0,
      for (final key in _cheekSensitiveMetricKeys) key: 5.0,
      'texture_smoothness': 0.0,
    };
    Map<String, dynamic> imagePayload(String side) => <String, dynamic>{
      'image_quality': <String, dynamic>{
        'redness_cheek_side': side,
        'cheek_side_convention': cheekSideConventionSubjectAnatomical,
        'redness_cheek_p10_a_after_wb': 5.0,
        'redness_cheek_p95_a_after_wb': 10.0,
      },
      aiScanPerFrameDiagnosticsKey: <Map<String, dynamic>>[
        for (var frame = 0; frame < 3; frame++) {'cheek_p95_a_after_wb': 10.0},
      ],
    };
    final trends = downgradeRednessTrendForCaptureMismatch(
      trendStatus: trendStatus,
      trendDeltas: trendDeltas,
      trendLockReasons: const {},
      currentPayload: imagePayload(currentSide),
      baselinePayload: imagePayload(baselineSide),
    );
    return <String, dynamic>{
      'is_follow_up': true,
      'local_history_count': 2,
      'metric_matrix': metricMatrix,
      'baseline_metric_matrix': baselineMetricMatrix,
      'metric_extraction_paths': <String, dynamic>{
        for (final key in metricMatrix.keys) key: 'primary_roi',
      },
      'baseline_metric_extraction_paths': <String, dynamic>{
        for (final key in metricMatrix.keys) key: 'primary_roi',
      },
      'trend_status': trends.trendStatus,
      'trend_deltas': trends.trendDeltas,
      'trend_lock_reasons': trends.trendLockReasons,
    };
  }

  testWidgets('backend "stable" with no lock reason: no arrow, no percent', (
    tester,
  ) async {
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
  });

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

  testWidgets('stable firmness keeps backend stable label below 4 points', (
    tester,
  ) async {
    final payload = basePayload(
      baseline: 52.0,
      current: 53.2,
      metricKey: 'structural_firmness_elasticity',
      trendStatus: {'structural_firmness_elasticity': 'stable'},
      trendDeltas: {'structural_firmness_elasticity': 0.0},
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(
      const ValueKey('result_metric_structural_firmness_elasticity'),
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('Stable - change within tracking noise'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('No verdict for this metric'),
      ),
      findsNothing,
    );
    expect(
      find.textContaining('Structural Firmness & Elasticity: Stable'),
      findsOneWidget,
    );
  });

  testWidgets('stable locked firmness remains not comparable', (tester) async {
    final payload = basePayload(
      baseline: 52.0,
      current: 53.2,
      metricKey: 'structural_firmness_elasticity',
      trendStatus: {'structural_firmness_elasticity': 'stable'},
      trendDeltas: {'structural_firmness_elasticity': 0.0},
      trendLockReasons: {
        'structural_firmness_elasticity': 'capture_quality_mismatch',
      },
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(
      const ValueKey('result_metric_structural_firmness_elasticity'),
    );
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Not comparable:'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('No verdict for this metric'),
      ),
      findsNothing,
    );
  });

  testWidgets('wide texture spread keeps the backend Stable verdict', (
    tester,
  ) async {
    final payload = basePayload(
      baseline: 59.6,
      current: 43.1,
      metricKey: 'texture_smoothness',
      trendStatus: {'texture_smoothness': 'stable'},
      trendDeltas: {'texture_smoothness': 0.0},
      metricRanges: {
        'texture_smoothness': {'min': 13.6, 'max': 58.3, 'count': 3},
      },
      metricNoiseFloors: {'texture_smoothness': 5.4},
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_texture_smoothness'));
    expect(
      find.descendant(of: card, matching: find.textContaining('43.1')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('Stable - change within tracking noise'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('No verdict for this metric'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'trusted metric with a backend worsened verdict keeps it above its '
    'noise floor',
    (tester) async {
      final payload = basePayload(
        baseline: 8.0,
        current: 10.0,
        metricKey: 'pore_visibility',
        trendStatus: {'pore_visibility': 'worsened'},
        trendDeltas: {'pore_visibility': 25.0},
        metricRanges: {
          'pore_visibility': {'min': 8.5, 'max': 11.5, 'count': 3},
        },
        metricNoiseFloors: {'pore_visibility': 1.0},
      );
      await tester.pumpWidget(harness(payload));
      await tester.pumpAndSettle();

      final card = find.byKey(const ValueKey('result_metric_pore_visibility'));
      expect(
        find.descendant(of: card, matching: find.text('Worsened')),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('No verdict for this metric'),
        ),
        findsNothing,
      );
      expect(find.textContaining('Pore Visibility: No verdict'), findsNothing);
    },
  );

  testWidgets('locked trusted metric above its noise floor is not comparable', (
    tester,
  ) async {
    final payload = basePayload(
      baseline: 8.0,
      current: 10.0,
      metricKey: 'pore_visibility',
      trendStatus: {'pore_visibility': 'stable'},
      trendDeltas: {'pore_visibility': 0.0},
      trendLockReasons: {'pore_visibility': 'lighting_mismatch'},
      metricRanges: {
        'pore_visibility': {'min': 8.5, 'max': 11.5, 'count': 3},
      },
      metricNoiseFloors: {'pore_visibility': 1.0},
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_pore_visibility'));
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Not comparable:'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('No verdict for this metric'),
      ),
      findsNothing,
    );
  });

  testWidgets('hidden metric with a backend verdict still shows no verdict', (
    tester,
  ) async {
    final payload = basePayload(
      baseline: 30.0,
      current: 40.0,
      metricKey: 'wrinkle_load',
      trendStatus: {'wrinkle_load': 'worsened'},
      trendDeltas: {'wrinkle_load': 33.3},
      metricRanges: {
        'wrinkle_load': {'min': 35.0, 'max': 45.0, 'count': 3},
      },
      metricNoiseFloors: {'wrinkle_load': 3.7},
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_wrinkle_load'));
    expect(
      find.descendant(of: card, matching: find.textContaining('40.0')),
      findsWidgets,
    );
    for (final label in const ['Improved', 'Worsened']) {
      expect(
        find.descendant(of: card, matching: find.text(label)),
        findsNothing,
      );
    }
    expect(
      find.descendant(of: card, matching: find.textContaining('Stable')),
      findsNothing,
    );
  });

  testWidgets('trusted metric without a backend verdict keeps the frame-spread '
      'No verdict', (tester) async {
    final payload = basePayload(
      baseline: 22.3,
      current: 27.9,
      metricRanges: {
        'pigment_load': {'min': 24.0, 'max': 31.0, 'count': 3},
      },
      metricNoiseFloors: {'pigment_load': 2.0},
    );
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

    final card = find.byKey(const ValueKey('result_metric_pigment_load'));
    expect(
      find.descendant(
        of: card,
        matching: find.text('No verdict for this metric'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Worsened')),
      findsNothing,
    );
  });

  testWidgets('tight texture spread keeps the Stable verdict', (tester) async {
    final payload = basePayload(
      baseline: 59.6,
      current: 43.1,
      metricKey: 'texture_smoothness',
      trendStatus: {'texture_smoothness': 'stable'},
      trendDeltas: {'texture_smoothness': 0.0},
      metricRanges: {
        'texture_smoothness': {'min': 42.5, 'max': 43.7, 'count': 3},
      },
      metricNoiseFloors: {'texture_smoothness': 5.4},
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_texture_smoothness'));
    expect(
      find.descendant(
        of: card,
        matching: find.text('Stable - change within tracking noise'),
      ),
      findsWidgets,
    );
  });

  testWidgets('locked redness omits baseline-to-current progression arrow', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        basePayload(
          baseline: 16.5,
          current: 28.4,
          metricKey: 'localized_redness',
          trendLockReasons: {'localized_redness': 'cheek_mismatch'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_localized_redness'));
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Not comparable:'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('28.4')),
      findsWidgets,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('16.5 -> 28.4')),
      findsNothing,
    );
  });

  testWidgets('card and CSV use the same scan-level metric values', (
    tester,
  ) async {
    final payload = <String, dynamic>{
      'is_follow_up': true,
      'local_history_count': 2,
      'metric_matrix': <String, dynamic>{
        'texture_smoothness': 43.1,
        'localized_redness': 28.4,
      },
      'baseline_metric_matrix': <String, dynamic>{
        'texture_smoothness': 59.6,
        'localized_redness': 16.5,
      },
      'metric_extraction_paths': <String, dynamic>{
        'texture_smoothness': 'primary_roi',
        'localized_redness': 'primary_roi',
      },
      'baseline_metric_extraction_paths': <String, dynamic>{
        'texture_smoothness': 'primary_roi',
        'localized_redness': 'primary_roi',
      },
      'trend_status': <String, dynamic>{'texture_smoothness': 'stable'},
      'trend_lock_reasons': <String, dynamic>{
        'localized_redness': 'cheek_mismatch',
      },
    };
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final scan = ScanHistoryEntry(
      id: 'same-result-scan',
      timestamp: DateTime.utc(2026, 10, 4),
      scanType: ScanHistoryEntry.scanTypeAiAnalysis,
      estimatedSkinAge: 0,
      metrics: const <String, double>{},
      rawPayload: payload,
    );
    final rows = AiScanDataCsvExporter.format([
      scan,
    ], registryBaselineScanIds: const {}).split('\r\n');
    final header = rows.first.split(',');
    final values = rows[1].split(',');

    for (final entry in const {
      'texture_smoothness': '43.1',
      'localized_redness': '28.4',
    }.entries) {
      final card = find.byKey(ValueKey('result_metric_${entry.key}'));
      expect(
        find.descendant(of: card, matching: find.textContaining(entry.value)),
        findsWidgets,
      );
      expect(values[header.indexOf('${entry.key}_value')], entry.value);
    }
  });

  testWidgets('unlocked redness keeps the backend stable verdict', (
    tester,
  ) async {
    final payload = basePayload(
      baseline: 24.0,
      current: 25.0,
      metricKey: 'localized_redness',
      trendStatus: {'localized_redness': 'stable'},
      trendDeltas: {'localized_redness': 4.2},
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_localized_redness'));
    expect(
      find.descendant(
        of: card,
        matching: find.text('Stable - change within tracking noise'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('No verdict for this metric'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Not comparable:'),
      ),
      findsNothing,
    );
  });

  testWidgets('unlocked redness keeps the backend improved verdict', (
    tester,
  ) async {
    final payload = basePayload(
      baseline: 30.0,
      current: 25.0,
      metricKey: 'localized_redness',
      trendStatus: {'localized_redness': 'improved'},
      trendDeltas: {'localized_redness': -16.7},
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_localized_redness'));
    expect(
      find.descendant(of: card, matching: find.text('Improved')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('No verdict for this metric'),
      ),
      findsNothing,
    );
  });

  testWidgets('a 0.0 redness reading gains no trend verdict', (tester) async {
    final payload = basePayload(
      baseline: 12.0,
      current: 0.0,
      metricKey: 'localized_redness',
      trendStatus: {'localized_redness': 'improved'},
      trendDeltas: {'localized_redness': -100.0},
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_localized_redness'));
    expect(
      find.descendant(of: card, matching: find.textContaining('0.0')),
      findsWidgets,
    );
    for (final label in const ['Improved', 'Worsened']) {
      expect(
        find.descendant(of: card, matching: find.text(label)),
        findsNothing,
      );
    }
    expect(
      find.descendant(
        of: card,
        matching: find.text('No verdict for this metric'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cheek-locked redness still says Not comparable', (tester) async {
    final payload = basePayload(
      baseline: 24.0,
      current: 25.0,
      metricKey: 'localized_redness',
      trendStatus: {'localized_redness': 'stable'},
      trendDeltas: {'localized_redness': 4.2},
      trendLockReasons: {'localized_redness': 'cheek_mismatch'},
    );
    await tester.pumpWidget(harness(payload));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_localized_redness'));
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Not comparable:'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('Stable - change within tracking noise'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'firmness hides a 3-point change but preserves a 5-point verdict',
    (tester) async {
      Future<void> pumpFirmness(double current) async {
        await tester.pumpWidget(
          harness(
            basePayload(
              baseline: 40.0,
              current: current,
              metricKey: 'structural_firmness_elasticity',
              trendStatus: {'structural_firmness_elasticity': 'improved'},
              trendDeltas: {'structural_firmness_elasticity': 12.5},
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpFirmness(43.0);
      var card = find.byKey(
        const ValueKey('result_metric_structural_firmness_elasticity'),
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('43.0')),
        findsWidgets,
      );
      expect(
        find.descendant(of: card, matching: find.text('Improved')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('No verdict for this metric'),
        ),
        findsOneWidget,
      );

      await pumpFirmness(45.0);
      card = find.byKey(
        const ValueKey('result_metric_structural_firmness_elasticity'),
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('45.0')),
        findsWidgets,
      );
      expect(
        find.descendant(of: card, matching: find.text('Improved')),
        findsWidgets,
      );
    },
  );

  testWidgets('pigment under a 2-point move keeps its verdict', (tester) async {
    await tester.pumpWidget(
      harness(
        basePayload(
          baseline: 40.0,
          current: 41.0,
          trendStatus: {'pigment_load': 'worsened'},
          trendDeltas: {'pigment_load': 2.5},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('result_metric_pigment_load'));
    expect(
      find.descendant(of: card, matching: find.textContaining('41.0')),
      findsWidgets,
    );
    expect(
      find.descendant(of: card, matching: find.text('Worsened')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('No verdict for this metric'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'opposite cheeks lock redness but keep other result verdicts and scores',
    (tester) async {
      await tester.pumpWidget(
        harness(cheekPairPayload(currentSide: 'left', baselineSide: 'right')),
      );
      await tester.pumpAndSettle();

      final rednessCard = find.byKey(
        const ValueKey('result_metric_localized_redness'),
      );
      expect(
        find.descendant(
          of: rednessCard,
          matching: find.textContaining('Not comparable:'),
        ),
        findsOneWidget,
      );

      for (final key in _cheekSensitiveMetricKeys) {
        final card = find.byKey(ValueKey('result_metric_$key'));
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('Not comparable:'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('42.0')),
          findsWidgets,
        );
        if (key == 'texture_smoothness') {
          expect(
            find.descendant(
              of: card,
              matching: find.text('Stable - change within tracking noise'),
            ),
            findsOneWidget,
          );
        }
        if (key == 'pigment_load') {
          expect(
            find.descendant(of: card, matching: find.text('Improved')),
            findsOneWidget,
          );
        }
      }
    },
  );

  testWidgets('same cheeks retain the Stable texture verdict', (tester) async {
    await tester.pumpWidget(
      harness(cheekPairPayload(currentSide: 'left', baselineSide: 'left')),
    );
    await tester.pumpAndSettle();

    final textureCard = find.byKey(
      const ValueKey('result_metric_texture_smoothness'),
    );
    expect(
      find.descendant(
        of: textureCard,
        matching: find.text('Stable - change within tracking noise'),
      ),
      findsWidgets,
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

  group(
    'post-scan results screen (trusted metrics need a backend verdict)',
    () {
      Future<Finder> pumpResults(
        WidgetTester tester,
        Map<String, dynamic> payload,
        String metricKey,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SkinAiAnalysisResultsScreen(
              analysisResult: payload,
              croppedImageBytes: null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        return find.byKey(ValueKey('result_metric_$metricKey'));
      }

      testWidgets('trusted metric with no backend status shows No verdict', (
        tester,
      ) async {
        // Without a backend verdict the legacy recompute would call
        // 22.3 -> 27.9 Worsened (see the requireBackendVerdict=false test).
        final card = await pumpResults(
          tester,
          basePayload(baseline: 22.3, current: 27.9),
          'pigment_load',
        );
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.textContaining('27.9')),
          findsWidgets,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('No verdict for this metric'),
          ),
          findsOneWidget,
        );
        for (final label in const ['Improved', 'Worsened']) {
          expect(
            find.descendant(of: card, matching: find.text(label)),
            findsNothing,
          );
        }
        expect(
          find.descendant(of: card, matching: find.textContaining('Stable')),
          findsNothing,
        );
      });

      testWidgets(
        'the same metric with a backend worsened verdict says Worsened',
        (tester) async {
          final card = await pumpResults(
            tester,
            basePayload(
              baseline: 22.3,
              current: 27.9,
              trendStatus: {'pigment_load': 'worsened'},
              trendDeltas: {'pigment_load': 25.1},
            ),
            'pigment_load',
          );
          expect(
            find.descendant(of: card, matching: find.text('Worsened')),
            findsWidgets,
          );
          expect(
            find.descendant(
              of: card,
              matching: find.text('No verdict for this metric'),
            ),
            findsNothing,
          );
        },
      );

      testWidgets('a locked trusted metric still says Not comparable', (
        tester,
      ) async {
        final card = await pumpResults(
          tester,
          basePayload(
            baseline: 22.3,
            current: 27.9,
            trendStatus: {'pigment_load': 'stable'},
            trendDeltas: {'pigment_load': 0.0},
            trendLockReasons: {'pigment_load': 'lighting_mismatch'},
          ),
          'pigment_load',
        );
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('Not comparable:'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('a 0.0 redness with no backend status shows No verdict', (
        tester,
      ) async {
        final card = await pumpResults(
          tester,
          basePayload(
            baseline: 12.0,
            current: 0.0,
            metricKey: 'localized_redness',
          ),
          'localized_redness',
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('No verdict for this metric'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Improved')),
          findsNothing,
        );
      });

      testWidgets('a hidden metric stays number-only', (tester) async {
        final card = await pumpResults(
          tester,
          basePayload(baseline: 30.0, current: 40.0, metricKey: 'wrinkle_load'),
          'wrinkle_load',
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('40.0')),
          findsWidgets,
        );
        for (final label in const ['Improved', 'Worsened']) {
          expect(
            find.descendant(of: card, matching: find.text(label)),
            findsNothing,
          );
        }
      });
    },
  );

  group('pore_contraction_index is hidden on the live results views', () {
    Map<String, dynamic> payload() => <String, dynamic>{
      'is_follow_up': true,
      'local_history_count': 2,
      'metric_matrix': <String, dynamic>{
        'pore_contraction_index': 72.0,
        'pore_visibility': 10.0,
      },
      'baseline_metric_matrix': <String, dynamic>{
        'pore_contraction_index': 60.0,
        // A 3-point move, above pore_visibility's 2.0 display floor, so the
        // control card keeps its verdict on the live views.
        'pore_visibility': 7.0,
      },
      'metric_extraction_paths': <String, dynamic>{
        'pore_contraction_index': 'primary_roi',
        'pore_visibility': 'primary_roi',
      },
      'baseline_metric_extraction_paths': <String, dynamic>{
        'pore_contraction_index': 'primary_roi',
        'pore_visibility': 'primary_roi',
      },
      'trend_status': <String, dynamic>{
        'pore_contraction_index': 'improved',
        'pore_visibility': 'worsened',
      },
      'trend_deltas': <String, dynamic>{
        'pore_contraction_index': 20.0,
        'pore_visibility': 25.0,
      },
    };

    void expectPoreContractionHidden() {
      expect(
        find.byKey(const ValueKey('result_metric_pore_contraction_index')),
        findsNothing,
      );
      expect(find.textContaining('72.0'), findsNothing);
      expect(find.textContaining('Pore Contraction'), findsNothing);
      final poreCard = find.byKey(
        const ValueKey('result_metric_pore_visibility'),
      );
      expect(poreCard, findsOneWidget);
      expect(
        find.descendant(of: poreCard, matching: find.text('Worsened')),
        findsWidgets,
      );
    }

    testWidgets('main live results card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LuxeReportLayout(
                rawPayload: payload(),
                requireBackendVerdict: true,
                hiddenMetricKeys: liveResultsHiddenMetricKeys,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectPoreContractionHidden();
    });

    testWidgets('SkinAiAnalysisResultsScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SkinAiAnalysisResultsScreen(
            analysisResult: payload(),
            croppedImageBytes: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectPoreContractionHidden();
    });

    test('both live views in the screen pass the hidden-metric set', () {
      final source = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      expect(
        'hiddenMetricKeys: liveResultsHiddenMetricKeys'.allMatches(source),
        hasLength(2),
      );
      expect(liveResultsHiddenMetricKeys, {'pore_contraction_index'});
    });

    testWidgets('other report callers still render pore_contraction_index', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LuxeReportLayout(rawPayload: payload()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('result_metric_pore_contraction_index')),
        findsOneWidget,
      );
    });

    test('the scan-data export still contains pore_contraction_index', () {
      final scan = ScanHistoryEntry(
        id: 'pore-contraction-export',
        timestamp: DateTime.utc(2026, 10, 6),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: payload(),
      );
      final rows = AiScanDataCsvExporter.format([
        scan,
      ], registryBaselineScanIds: const {}).split('\r\n');
      final header = rows.first.split(',');
      final values = rows[1].split(',');
      expect(header, contains('pore_contraction_index_value'));
      expect(values[header.indexOf('pore_contraction_index_value')], '72.0');
    });
  });

  group('measured display noise floors on the live results views', () {
    Widget liveHarness(Map<String, dynamic> payload) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LuxeReportLayout(
            rawPayload: payload,
            requireBackendVerdict: true,
            applyDisplayNoiseFloors: true,
          ),
        ),
      ),
    );

    Finder card(String key) => find.byKey(ValueKey('result_metric_$key'));
    Finder inCard(String key, Finder matching) =>
        find.descendant(of: card(key), matching: matching);

    testWidgets('a 2-point texture move shows no verdict and no percent', (
      tester,
    ) async {
      await tester.pumpWidget(
        liveHarness(
          basePayload(
            baseline: 57.5,
            current: 59.5,
            metricKey: 'texture_smoothness',
            trendStatus: {'texture_smoothness': 'improved'},
            trendDeltas: {'texture_smoothness': 3.5},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        inCard('texture_smoothness', find.text('No verdict for this metric')),
        findsOneWidget,
      );
      expect(inCard('texture_smoothness', find.text('Improved')), findsNothing);
      expect(
        inCard('texture_smoothness', find.textContaining('Stable')),
        findsNothing,
      );
      expect(
        inCard('texture_smoothness', find.textContaining('%')),
        findsNothing,
      );
      expect(
        inCard('texture_smoothness', find.textContaining('59.5')),
        findsWidgets,
      );
    });

    testWidgets('a move exactly at the floor shows no verdict', (tester) async {
      await tester.pumpWidget(
        liveHarness(
          basePayload(
            baseline: 57.0,
            current: 60.0,
            metricKey: 'texture_smoothness',
            trendStatus: {'texture_smoothness': 'stable'},
            trendDeltas: {'texture_smoothness': 0.0},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        inCard('texture_smoothness', find.text('No verdict for this metric')),
        findsOneWidget,
      );
    });

    testWidgets('a 4-point texture move can show stable or improved', (
      tester,
    ) async {
      await tester.pumpWidget(
        liveHarness(
          basePayload(
            baseline: 57.5,
            current: 61.5,
            metricKey: 'texture_smoothness',
            trendStatus: {'texture_smoothness': 'stable'},
            trendDeltas: {'texture_smoothness': 0.0},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        inCard(
          'texture_smoothness',
          find.text('Stable - change within tracking noise'),
        ),
        findsWidgets,
      );

      await tester.pumpWidget(
        liveHarness(
          basePayload(
            baseline: 50.0,
            current: 54.0,
            metricKey: 'texture_smoothness',
            trendStatus: {'texture_smoothness': 'improved'},
            trendDeltas: {'texture_smoothness': 8.0},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(inCard('texture_smoothness', find.text('Improved')), findsWidgets);
      expect(
        inCard('texture_smoothness', find.text('No verdict for this metric')),
        findsNothing,
      );
    });

    testWidgets('firmness uses its 4-point floor', (tester) async {
      await tester.pumpWidget(
        liveHarness(
          basePayload(
            baseline: 55.8,
            current: 52.2,
            metricKey: 'structural_firmness_elasticity',
            trendStatus: {'structural_firmness_elasticity': 'worsened'},
            trendDeltas: {'structural_firmness_elasticity': -6.5},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        inCard(
          'structural_firmness_elasticity',
          find.text('No verdict for this metric'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        liveHarness(
          basePayload(
            baseline: 55.8,
            current: 51.0,
            metricKey: 'structural_firmness_elasticity',
            trendStatus: {'structural_firmness_elasticity': 'worsened'},
            trendDeltas: {'structural_firmness_elasticity': -8.6},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        inCard('structural_firmness_elasticity', find.text('Worsened')),
        findsWidgets,
      );
    });

    testWidgets('the six hidden metrics never show a verdict', (tester) async {
      const hidden = [
        'wrinkle_load',
        'rosacea_severity',
        'diffuse_flushing_erythema',
        'pore_contraction_index',
        'under_eye_dark_circle_density',
        'under_eye_texture_density',
      ];
      for (final key in hidden) {
        await tester.pumpWidget(
          liveHarness(
            basePayload(
              baseline: 20.0,
              current: 45.0,
              metricKey: key,
              trendStatus: {key: 'worsened'},
              trendDeltas: {key: 125.0},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          inCard(key, find.textContaining('45.0')),
          findsWidgets,
          reason: key,
        );
        for (final label in const ['Improved', 'Worsened']) {
          expect(inCard(key, find.text(label)), findsNothing, reason: key);
        }
        expect(
          inCard(key, find.textContaining('Stable')),
          findsNothing,
          reason: key,
        );
        expect(
          inCard(key, find.textContaining('%')),
          findsNothing,
          reason: key,
        );
      }
    });

    testWidgets('a locked metric inside its floor still says Not comparable', (
      tester,
    ) async {
      await tester.pumpWidget(
        liveHarness(
          basePayload(
            baseline: 57.5,
            current: 59.5,
            metricKey: 'texture_smoothness',
            trendStatus: {'texture_smoothness': 'stable'},
            trendDeltas: {'texture_smoothness': 0.0},
            trendLockReasons: {'texture_smoothness': 'lighting_mismatch'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        inCard('texture_smoothness', find.textContaining('Not comparable:')),
        findsOneWidget,
      );
      expect(
        inCard('texture_smoothness', find.text('No verdict for this metric')),
        findsNothing,
      );
    });

    testWidgets('callers without the floors keep the existing verdict', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          basePayload(
            baseline: 57.5,
            current: 59.5,
            metricKey: 'texture_smoothness',
            trendStatus: {'texture_smoothness': 'stable'},
            trendDeltas: {'texture_smoothness': 0.0},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        inCard(
          'texture_smoothness',
          find.text('Stable - change within tracking noise'),
        ),
        findsWidgets,
      );
    });

    test('the export carries each metric\'s display floor', () {
      final scan = ScanHistoryEntry(
        id: 'noise-floor-export',
        timestamp: DateTime.utc(2026, 10, 10, 20),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: const <String, dynamic>{
          'metric_matrix': <String, dynamic>{'texture_smoothness': 57.0},
        },
      );
      final rows = AiScanDataCsvExporter.format([
        scan,
      ], registryBaselineScanIds: const {}).split('\r\n');
      final header = rows.first.split(',');
      final values = rows[1].split(',');
      String cell(String column) => values[header.indexOf(column)];

      expect(cell('texture_smoothness_noise_floor'), '3.0');
      expect(cell('pigment_load_noise_floor'), '3.0');
      expect(cell('skin_tone_radiance_evenness_noise_floor'), '3.0');
      expect(cell('structural_firmness_elasticity_noise_floor'), '4.0');
      expect(cell('pore_visibility_noise_floor'), '2.0');
      expect(cell('sebum_excess_oil_gloss_noise_floor'), '3.0');
      expect(cell('localized_redness_noise_floor'), '5.0');
      expect(cell('wrinkle_load_noise_floor'), isEmpty);
    });

    test('both live views turn the floors on', () {
      final source = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      expect('applyDisplayNoiseFloors: true'.allMatches(source), hasLength(2));
    });
  });

  group('median of frames for untrusted metrics on the live results views', () {
    const six = [
      'wrinkle_load',
      'pore_contraction_index',
      'under_eye_dark_circle_density',
      'under_eye_texture_density',
      'diffuse_flushing_erythema',
      'rosacea_severity',
    ];

    // Frames 44 / 45 / 75: the mean is 54.7, the median is 45.0.
    Map<String, dynamic> outlierPayload(String key, {String? lockReason}) =>
        <String, dynamic>{
          'is_follow_up': true,
          'local_history_count': 2,
          'metric_matrix': <String, dynamic>{
            key: (44.0 + 45.0 + 75.0) / 3.0,
            'texture_smoothness': (56.0 + 57.0 + 75.0) / 3.0,
          },
          'baseline_metric_matrix': <String, dynamic>{
            key: 44.0,
            'texture_smoothness': 56.0,
          },
          'metric_extraction_paths': <String, dynamic>{
            key: 'primary_roi',
            'texture_smoothness': 'laplacian_fallback',
          },
          'baseline_metric_extraction_paths': <String, dynamic>{
            key: 'primary_roi',
            'texture_smoothness': 'laplacian_fallback',
          },
          // A locked metric arrives as backend "stable" plus its lock.
          'trend_status': <String, dynamic>{
            'texture_smoothness': lockReason == null ? 'improved' : 'stable',
          },
          'trend_deltas': <String, dynamic>{
            'texture_smoothness': lockReason == null ? 11.9 : 0.0,
          },
          if (lockReason != null)
            'trend_lock_reasons': <String, dynamic>{
              'texture_smoothness': lockReason,
            },
          'multi_frame_analysis': <String, dynamic>{
            'metric_frame_values': <String, dynamic>{
              key: [44.0, 45.0, 75.0],
              'texture_smoothness': [56.0, 57.0, 75.0],
            },
          },
        };

    Widget live(Map<String, dynamic> payload) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LuxeReportLayout(
            rawPayload: payload,
            requireBackendVerdict: true,
            hiddenMetricKeys: liveResultsHiddenMetricKeys,
            applyDisplayNoiseFloors: true,
            medianDisplayMetricKeys: medianDisplayMetricKeys,
          ),
        ),
      ),
    );

    Finder card(String key) => find.byKey(ValueKey('result_metric_$key'));

    testWidgets('a single-frame outlier is ignored for the six metrics', (
      tester,
    ) async {
      // pore_contraction_index is hidden on the live views entirely, so it
      // is checked through the parser below rather than a card.
      for (final key in six.where(
        (key) => !liveResultsHiddenMetricKeys.contains(key),
      )) {
        await tester.pumpWidget(live(outlierPayload(key)));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: card(key), matching: find.textContaining('45.0')),
          findsWidgets,
          reason: key,
        );
        expect(
          find.descendant(of: card(key), matching: find.textContaining('54.7')),
          findsNothing,
          reason: key,
        );
        for (final label in const ['Improved', 'Worsened']) {
          expect(
            find.descendant(of: card(key), matching: find.text(label)),
            findsNothing,
            reason: key,
          );
        }
      }
    });

    test('the parser uses the median for all six, the mean otherwise', () {
      for (final key in six) {
        final metrics = LuxeMetricParser.parseTimelinePayload(
          outlierPayload(key),
          medianDisplayMetricKeys: medianDisplayMetricKeys,
        );
        final six_ = metrics.singleWhere((m) => m.key == key);
        final texture = metrics.singleWhere(
          (m) => m.key == 'texture_smoothness',
        );
        expect(six_.currentScore, closeTo(45.0, 1e-9), reason: key);
        expect(texture.currentScore, closeTo(62.667, 0.001), reason: key);
      }
      // Without the option (history, Track Procedure, progress report) the
      // saved mean is used.
      final defaults = LuxeMetricParser.parseTimelinePayload(
        outlierPayload('wrinkle_load'),
      );
      expect(
        defaults.singleWhere((m) => m.key == 'wrinkle_load').currentScore,
        closeTo(54.667, 0.001),
      );
    });

    testWidgets('other metrics still show the mean on the live card', (
      tester,
    ) async {
      await tester.pumpWidget(live(outlierPayload('wrinkle_load')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: card('texture_smoothness'),
          matching: find.textContaining('62.7'),
        ),
        findsWidgets,
      );
    });

    testWidgets('a locked metric still says Not comparable', (tester) async {
      await tester.pumpWidget(
        live(outlierPayload('wrinkle_load', lockReason: 'lighting_mismatch')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: card('texture_smoothness'),
          matching: find.textContaining('Not comparable:'),
        ),
        findsOneWidget,
      );
    });

    test('the export keeps the mean and flags the display aggregation', () {
      final scan = ScanHistoryEntry(
        id: 'median-display',
        timestamp: DateTime.utc(2026, 10, 10, 21),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: outlierPayload('wrinkle_load'),
      );
      final rows = AiScanDataCsvExporter.format([
        scan,
      ], registryBaselineScanIds: const {}).split('\r\n');
      final header = rows.first.split(',');
      final values = rows[1].split(',');
      String cell(String column) => values[header.indexOf(column)];

      expect(cell('wrinkle_load_value'), startsWith('54.6'));
      for (final key in six) {
        expect(cell('${key}_display_aggregation'), 'median', reason: key);
      }
      expect(cell('texture_smoothness_display_aggregation'), 'mean');
      expect(cell('pigment_load_display_aggregation'), 'mean');
    });

    test('both live views pass the median set', () {
      final source = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      expect(
        'medianDisplayMetricKeys: medianDisplayMetricKeys'.allMatches(source),
        hasLength(2),
      );
      expect(medianDisplayMetricKeys, six.toSet());
    });
  });

  group('the card says why there is no verdict', () {
    Widget live(Map<String, dynamic> payload) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LuxeReportLayout(
            rawPayload: payload,
            requireBackendVerdict: true,
            applyDisplayNoiseFloors: true,
          ),
        ),
      ),
    );

    Finder inCard(String key, Finder matching) => find.descendant(
      of: find.byKey(ValueKey('result_metric_$key')),
      matching: matching,
    );

    testWidgets('within the display floor', (tester) async {
      await tester.pumpWidget(
        live(
          basePayload(
            baseline: 57.5,
            current: 59.5,
            metricKey: 'texture_smoothness',
            trendStatus: {'texture_smoothness': 'improved'},
            trendDeltas: {'texture_smoothness': 3.5},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        inCard('texture_smoothness', find.text('No verdict for this metric')),
        findsOneWidget,
      );
      expect(
        inCard(
          'texture_smoothness',
          find.textContaining('Within ±3 measurement noise'),
        ),
        findsWidgets,
      );
      expect(
        find.textContaining(
          'Texture Smoothness: No verdict for this metric '
          '(Within ±3 measurement noise)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('redness at 0', (tester) async {
      await tester.pumpWidget(
        live(
          basePayload(
            baseline: 12.0,
            current: 0.0,
            metricKey: 'localized_redness',
            trendStatus: {'localized_redness': 'improved'},
            trendDeltas: {'localized_redness': -100.0},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        inCard('localized_redness', find.textContaining('Redness at 0')),
        findsWidgets,
      );
    });

    testWidgets('frames disagreed', (tester) async {
      final aggregate = averageBackendAnalysisFrames([
        for (final (value, status) in const [
          (8.5, 'stable'),
          (9.9, 'worsened'),
          (10.3, 'worsened'),
        ])
          {
            'metric_matrix': {'pigment_load': value},
            'metric_extraction_paths': {'pigment_load': 'cheek_primary'},
            'trend_status': {'pigment_load': status},
            'trend_deltas': {'pigment_load': 0.0},
          },
      ], requestedFrames: 3);
      expect(
        (aggregate.response['multi_frame_analysis']
            as Map)['trend_status_disagreements'],
        ['pigment_load'],
      );
      await tester.pumpWidget(
        live({
          ...aggregate.response,
          'is_follow_up': true,
          'local_history_count': 2,
          'baseline_metric_matrix': {'pigment_load': 4.0},
          'baseline_metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        }),
      );
      await tester.pumpAndSettle();
      expect(
        inCard('pigment_load', find.textContaining('Frames disagreed')),
        findsWidgets,
      );
    });

    testWidgets('frames varied more than the noise floor', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LuxeReportLayout(
                rawPayload: basePayload(
                  baseline: 22.3,
                  current: 27.9,
                  metricRanges: {
                    'pigment_load': {'min': 24.0, 'max': 31.0, 'count': 3},
                  },
                  metricNoiseFloors: {'pigment_load': 2.0},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        inCard(
          'pigment_load',
          find.textContaining("Frames varied more than this metric's"),
        ),
        findsWidgets,
      );
    });

    testWidgets('no trend from the backend', (tester) async {
      await tester.pumpWidget(live(basePayload(baseline: 22.3, current: 27.9)));
      await tester.pumpAndSettle();
      expect(
        inCard(
          'pigment_load',
          find.textContaining('No trend was computed for this scan'),
        ),
        findsWidgets,
      );
    });

    testWidgets('a verdict is still shown when there is one', (tester) async {
      await tester.pumpWidget(
        live(
          basePayload(
            baseline: 50.0,
            current: 54.0,
            metricKey: 'texture_smoothness',
            trendStatus: {'texture_smoothness': 'improved'},
            trendDeltas: {'texture_smoothness': 8.0},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(inCard('texture_smoothness', find.text('Improved')), findsWidgets);
      expect(
        inCard('texture_smoothness', find.textContaining('measurement noise')),
        findsNothing,
      );
    });
  });
}
