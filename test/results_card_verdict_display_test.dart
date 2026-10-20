import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The six metrics whose verdicts are never shown on the results card.
const _untrusted = <String>[
  'wrinkle_load',
  'rosacea_severity',
  'diffuse_flushing_erythema',
  'pore_contraction_index',
  'under_eye_dark_circle_density',
  'under_eye_texture_density',
];

/// Live results payload (as the scan screen renders it) for [metrics]:
/// key -> (baseline, current, status, delta, lock).
Map<String, dynamic> _payload(
  Map<
    String,
    ({
      double baseline,
      double current,
      String? status,
      double? delta,
      String? lock,
    })
  >
  metrics,
) => <String, dynamic>{
  'is_follow_up': true,
  'local_history_count': 2,
  'metric_matrix': {for (final e in metrics.entries) e.key: e.value.current},
  'baseline_metric_matrix': {
    for (final e in metrics.entries) e.key: e.value.baseline,
  },
  'metric_extraction_paths': {for (final k in metrics.keys) k: 'primary_roi'},
  'baseline_metric_extraction_paths': {
    for (final k in metrics.keys) k: 'primary_roi',
  },
  'trend_status': {
    for (final e in metrics.entries)
      if (e.value.status != null) e.key: e.value.status,
  },
  'trend_deltas': {
    for (final e in metrics.entries)
      if (e.value.delta != null) e.key: e.value.delta,
  },
  'trend_lock_reasons': {
    for (final e in metrics.entries)
      if (e.value.lock != null) e.key: e.value.lock,
  },
};

Future<void> _pumpLive(
  WidgetTester tester,
  Map<String, dynamic> payload,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 8000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LuxeReportLayout(
            rawPayload: payload,
            requireBackendVerdict: true,
            applyDisplayNoiseFloors: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every text on one metric card, joined.
String _cardText(WidgetTester tester, String key) {
  final card = find.byKey(ValueKey('result_metric_$key'));
  expect(card, findsOneWidget, reason: key);
  return find
      .descendant(of: card, matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .join(' | ');
}

/// The headline (first, large text) of one metric card.
Text _headline(WidgetTester tester, String key) => tester.widget<Text>(
  find
      .descendant(
        of: find.byKey(ValueKey('result_metric_$key')),
        matching: find.byType(Text),
      )
      .first,
);

final _verdictWords = RegExp(r'\b(Improved|Worsened|Stable)\b');
final _percent = RegExp(r'\d%|\bpts\b');
const _neutral = Color(0xFF8E7F6D);

void main() {
  group('locked metrics', () {
    for (final lock in [
      'lighting_mismatch',
      'formula_version_mismatch',
      'cast_mismatch',
      'path_mismatch',
    ]) {
      testWidgets('$lock: Not comparable, number kept, no status or percent '
          'even when a directional status is still in the payload', (
        tester,
      ) async {
        await _pumpLive(
          tester,
          _payload({
            'texture_smoothness': (
              baseline: 40.0,
              current: 60.0,
              status: 'improved',
              delta: 50.0,
              lock: lock,
            ),
            'pigment_load': (
              baseline: 30.0,
              current: 10.0,
              status: 'worsened',
              delta: -66.0,
              lock: lock,
            ),
          }),
        );
        for (final key in ['texture_smoothness', 'pigment_load']) {
          final text = _cardText(tester, key);
          expect(text, contains('Not comparable'), reason: '$key: $text');
          expect(_verdictWords.hasMatch(text), isFalse, reason: text);
          expect(_percent.hasMatch(text), isFalse, reason: text);
          expect(_headline(tester, key).style!.color, _neutral, reason: key);
        }
        expect(_cardText(tester, 'texture_smoothness'), contains('60.0'));
        expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
        expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
      });
    }

    testWidgets('cheek_mismatch on redness is Not comparable', (tester) async {
      await _pumpLive(
        tester,
        _payload({
          'localized_redness': (
            baseline: 10.0,
            current: 20.0,
            status: null,
            delta: null,
            lock: 'cheek_mismatch',
          ),
        }),
      );
      final text = _cardText(tester, 'localized_redness');
      expect(text, contains('Not comparable'));
      expect(_verdictWords.hasMatch(text), isFalse, reason: text);
      expect(_headline(tester, 'localized_redness').style!.color, _neutral);
    });
  });

  group('untrusted metrics', () {
    testWidgets('the six never show a verdict or percent; number shown in '
        'neutral styling', (tester) async {
      await _pumpLive(
        tester,
        _payload({
          for (final (i, key) in _untrusted.indexed)
            key: (
              baseline: 20.0,
              current: 40.0 + i,
              status: i.isEven ? 'worsened' : 'improved',
              delta: 100.0,
              lock: null,
            ),
        }),
      );
      for (final (i, key) in _untrusted.indexed) {
        final text = _cardText(tester, key);
        expect(_verdictWords.hasMatch(text), isFalse, reason: '$key: $text');
        expect(_percent.hasMatch(text), isFalse, reason: '$key: $text');
        expect(text, contains((40.0 + i).toStringAsFixed(1)), reason: key);
        expect(_headline(tester, key).style!.color, _neutral, reason: key);
      }
    });

    testWidgets('a locked untrusted metric is Not comparable', (tester) async {
      await _pumpLive(
        tester,
        _payload({
          'wrinkle_load': (
            baseline: 20.0,
            current: 30.0,
            status: null,
            delta: null,
            lock: 'lighting_mismatch',
          ),
        }),
      );
      final text = _cardText(tester, 'wrinkle_load');
      expect(text, contains('Not comparable'));
      expect(_verdictWords.hasMatch(text), isFalse, reason: text);
    });
  });

  group('trusted metrics keep their verdicts', () {
    testWidgets('texture can still show stable', (tester) async {
      await _pumpLive(
        tester,
        _payload({
          'texture_smoothness': (
            baseline: 50.0,
            current: 50.5,
            status: 'stable',
            delta: 1.0,
            lock: null,
          ),
        }),
      );
      expect(_cardText(tester, 'texture_smoothness'), contains('Stable'));
    });

    testWidgets('pigment can still show improved in its verdict colour', (
      tester,
    ) async {
      await _pumpLive(
        tester,
        _payload({
          'pigment_load': (
            baseline: 40.0,
            current: 20.0,
            status: 'improved',
            delta: -50.0,
            lock: null,
          ),
        }),
      );
      expect(_cardText(tester, 'pigment_load'), contains('Improved'));
      expect(_headline(tester, 'pigment_load').style!.color, isNot(_neutral));
    });
  });

  test('a worsening delta keeps its sign in the shared formatter (used by '
      'other screens)', () {
    expect(
      LuxeMetricParser.formatDisplayDelta(
        baseline: 8.0,
        current: 2.0,
        deltaPct: -75.0,
        includeSign: true,
      ),
      '-6.0 pts',
    );
  });

  group('plain card wording', () {
    const trusted = <String>[
      'texture_smoothness',
      'pigment_load',
      'skin_tone_radiance_evenness',
      'structural_firmness_elasticity',
      'pore_visibility',
      'localized_redness',
    ];

    Map<String, dynamic> allMetrics() => _payload({
      for (final key in [...trusted, ..._untrusted])
        key: (
          baseline: 30.0,
          current: 40.0,
          status: key == 'texture_smoothness' ? 'improved' : null,
          delta: key == 'texture_smoothness' ? 33.0 : null,
          lock: key == 'pigment_load'
              ? 'lighting_mismatch'
              : key == 'localized_redness'
              ? 'cheek_mismatch'
              : key == 'wrinkle_load'
              ? 'formula_version_mismatch'
              : null,
        ),
    });

    testWidgets('short plain labels on every card', (tester) async {
      await _pumpLive(tester, allMetrics());
      for (final entry in liveResultsShortLabels.entries) {
        expect(
          _cardText(tester, entry.key),
          contains(entry.value),
          reason: entry.key,
        );
      }
      expect(find.textContaining('Erythema'), findsNothing);
      expect(find.textContaining('Density'), findsNothing);
      expect(find.textContaining('scan vectors'), findsNothing);
      expect(find.text('Confidence unavailable'), findsNothing);
    });

    testWidgets('locked cards say only "Not comparable": no lock reason', (
      tester,
    ) async {
      await _pumpLive(tester, allMetrics());
      for (final key in ['pigment_load', 'localized_redness', 'wrinkle_load']) {
        expect(_headline(tester, key).data, 'Not comparable', reason: key);
        final text = _cardText(tester, key);
        for (final technical in [
          'Standalone entry',
          'brightness',
          'cheek',
          'scoring',
          'mismatch',
          'Not comparable:',
        ]) {
          expect(text, isNot(contains(technical)), reason: '$key: $text');
        }
        expect(text, contains('40.0'), reason: key);
      }
      // The summary also says just "Not comparable" for a lock.
      expect(find.text('Pigment: Not comparable.'), findsOneWidget);
      expect(find.textContaining('Standalone entry'), findsNothing);
    });

    testWidgets('trusted unlocked card keeps its verdict and numbers', (
      tester,
    ) async {
      await _pumpLive(tester, allMetrics());
      final text = _cardText(tester, 'texture_smoothness');
      expect(text, contains('Improved'));
      expect(text, contains('Current 40.0 · Baseline 30.0'));
      expect(text, contains('Texture: 30.0 -> 40.0'));
    });

    for (final width in [320.0, 375.0]) {
      testWidgets('every card fits at ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 6000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LuxeReportLayout(
                  rawPayload: allMetrics(),
                  requireBackendVerdict: true,
                  applyDisplayNoiseFloors: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
