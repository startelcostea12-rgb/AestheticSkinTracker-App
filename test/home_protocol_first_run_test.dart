import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/screens/home_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/widgets/scan_based_recommendations_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScanHistoryEntry _aiScan({
  required String id,
  required DateTime timestamp,
  Map<String, double>? metrics,
  Map<String, dynamic>? rawPayload,
  String poseTemplate = 'Front',
}) {
  return ScanHistoryEntry(
    id: id,
    timestamp: timestamp,
    procedureId: 'procedure-home',
    scanType: ScanHistoryEntry.scanTypeAiAnalysis,
    estimatedSkinAge: 0,
    metrics: metrics ?? const <String, double>{'localized_redness': 30.0},
    poseTemplate: poseTemplate,
    guideType: 'facial',
    captureQuality: 'normal',
    scanEngine: ScanHistoryEntry.engineBackendOpencv,
    rawPayload: <String, dynamic>{
      'metric_extraction_paths': <String, dynamic>{
        'localized_redness': 'primary_roi',
      },
      'metric_formula_versions': <String, dynamic>{'localized_redness': 1},
      ...?rawPayload,
    },
  );
}

Future<void> _pumpHomeWithScans(
  WidgetTester tester,
  List<ScanHistoryEntry> scans,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final procedure = Procedure(
    id: 'procedure-home',
    type: 'Microneedling',
    provider: 'Clinic',
    startDate: DateTime(2026, 9, 1),
    numSessions: 1,
  );
  await AppPrefs.saveProcedureHistory([procedure.toJson()]);
  await AppPrefs.setSelectedProcedureId(procedure.id);
  for (final scan in scans) {
    await AppPrefs.addScanEntry(scan);
  }
  await tester.pumpWidget(const MaterialApp(home: HomePage()));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home leads with protocol, scan and comparable pair only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final procedure = Procedure(
      id: 'procedure-home',
      type: 'Microneedling',
      provider: 'Clinic',
      startDate: DateTime(2026, 9, 1),
      numSessions: 1,
    );
    await AppPrefs.saveProcedureHistory([procedure.toJson()]);
    await AppPrefs.setSelectedProcedureId(procedure.id);
    await AppPrefs.addScanEntry(
      _aiScan(id: 'baseline-home', timestamp: DateTime(2026, 9, 10)),
    );
    await AppPrefs.addScanEntry(
      _aiScan(id: 'latest-home', timestamp: DateTime(2026, 9, 20)),
    );

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Current protocol'), findsOneWidget);
    expect(find.text('Microneedling'), findsWidgets);
    expect(find.text('Scan this protocol'), findsOneWidget);
    expect(find.text('Last comparable pair'), findsOneWidget);
    expect(find.textContaining('→'), findsOneWidget);
    expect(find.byType(ScanBasedRecommendationsCard), findsNothing);
    expect(find.text('Product Store'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home_protocol_scan_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Skin Scan'), findsOneWidget);
    expect(await AppPrefs.getSelectedProcedureIdOrNull(), procedure.id);
  });

  testWidgets('locked metric shows Not comparable without verdict or percent', (
    tester,
  ) async {
    await _pumpHomeWithScans(tester, [
      _aiScan(id: 'baseline', timestamp: DateTime(2026, 9, 10)),
      _aiScan(
        id: 'latest',
        timestamp: DateTime(2026, 9, 20),
        metrics: const {'texture_smoothness': 42.0},
        rawPayload: const {
          'trend_status': {'texture_smoothness': 'improved'},
          'trend_lock_reasons': {'texture_smoothness': 'capture_mismatch'},
          'trend_deltas': {'texture_smoothness': 17.0},
        },
      ),
    ]);

    final row = find.byKey(
      const ValueKey('home_pair_metric_texture_smoothness'),
    );
    expect(
      find.descendant(of: row, matching: find.text('42.0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Not comparable')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Improved')),
      findsNothing,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('%')),
      findsNothing,
    );
  });

  testWidgets('unlocked texture shows backend Stable verdict', (tester) async {
    await _pumpHomeWithScans(tester, [
      _aiScan(id: 'baseline', timestamp: DateTime(2026, 9, 10)),
      _aiScan(
        id: 'latest',
        timestamp: DateTime(2026, 9, 20),
        metrics: const {'texture_smoothness': 42.0},
        rawPayload: const {
          'trend_status': {'texture_smoothness': 'stable'},
        },
      ),
    ]);

    final row = find.byKey(
      const ValueKey('home_pair_metric_texture_smoothness'),
    );
    expect(
      find.descendant(of: row, matching: find.text('42.0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Stable')),
      findsOneWidget,
    );
  });

  testWidgets('pair card displays each saved primary metric number', (
    tester,
  ) async {
    const values = <String, double>{
      'texture_smoothness': 41.0,
      'pigment_load': 42.0,
      'skin_tone_radiance_evenness': 43.0,
      'structural_firmness_elasticity': 44.0,
      'pore_visibility': 45.0,
      'localized_redness': 46.0,
    };
    await _pumpHomeWithScans(tester, [
      _aiScan(id: 'baseline', timestamp: DateTime(2026, 9, 10)),
      _aiScan(
        id: 'latest',
        timestamp: DateTime(2026, 9, 20),
        metrics: values,
        rawPayload: const {
          'trend_status': {'pigment_load': 'worsened'},
          'trend_deltas': {'pigment_load': -17.3},
        },
      ),
    ]);

    for (final entry in values.entries) {
      final row = find.byKey(ValueKey('home_pair_metric_${entry.key}'));
      expect(
        find.descendant(
          of: row,
          matching: find.text(entry.value.toStringAsFixed(1)),
        ),
        findsOneWidget,
      );
    }
    final card = find.byKey(const ValueKey('home_last_comparable_pair'));
    expect(
      find.descendant(of: card, matching: find.textContaining('%')),
      findsNothing,
    );
  });

  testWidgets('hidden metrics never receive a verdict on the pair card', (
    tester,
  ) async {
    const hidden = [
      'wrinkle_load',
      'rosacea_severity',
      'diffuse_flushing_erythema',
      'pore_contraction_index',
      'under_eye_dark_circle_density',
      'under_eye_texture_density',
    ];
    await _pumpHomeWithScans(tester, [
      _aiScan(id: 'baseline', timestamp: DateTime(2026, 9, 10)),
      _aiScan(
        id: 'latest',
        timestamp: DateTime(2026, 9, 20),
        metrics: {for (final key in hidden) key: 30.0},
        rawPayload: {
          'trend_status': {for (final key in hidden) key: 'improved'},
        },
      ),
    ]);

    final card = find.byKey(const ValueKey('home_last_comparable_pair'));
    for (final key in hidden) {
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(ValueKey('home_pair_metric_$key')),
        ),
        findsNothing,
      );
    }
    expect(
      find.descendant(of: card, matching: find.text('Improved')),
      findsNothing,
    );
  });

  testWidgets('no real pair shows an empty state', (tester) async {
    await _pumpHomeWithScans(tester, [
      _aiScan(id: 'only-scan', timestamp: DateTime(2026, 9, 10)),
    ]);

    final card = find.byKey(const ValueKey('home_last_comparable_pair'));
    expect(
      find.descendant(of: card, matching: find.text('No comparable pair yet.')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Texture')),
      findsNothing,
    );
  });

  testWidgets('newest scan without a baseline leaves the last valid pair', (
    tester,
  ) async {
    await _pumpHomeWithScans(tester, [
      _aiScan(id: 'baseline', timestamp: DateTime(2026, 9, 10)),
      _aiScan(id: 'paired', timestamp: DateTime(2026, 9, 20)),
      _aiScan(
        id: 'different-angle',
        timestamp: DateTime(2026, 9, 30),
        poseTemplate: 'Side',
      ),
    ]);

    final card = find.byKey(const ValueKey('home_last_comparable_pair'));
    expect(
      find.descendant(of: card, matching: find.textContaining('Sep 20')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('Sep 30')),
      findsNothing,
    );
  });
}
