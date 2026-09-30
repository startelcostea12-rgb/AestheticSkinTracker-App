import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/screens/home_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/widgets/scan_based_recommendations_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScanHistoryEntry _aiScan({required String id, required DateTime timestamp}) {
  return ScanHistoryEntry(
    id: id,
    timestamp: timestamp,
    procedureId: 'procedure-home',
    scanType: ScanHistoryEntry.scanTypeAiAnalysis,
    estimatedSkinAge: 0,
    metrics: const <String, double>{'localized_redness': 30.0},
    poseTemplate: 'Front',
    guideType: 'facial',
    captureQuality: 'normal',
    scanEngine: ScanHistoryEntry.engineBackendOpencv,
    rawPayload: const <String, dynamic>{
      'metric_extraction_paths': <String, dynamic>{
        'localized_redness': 'primary_roi',
      },
      'metric_formula_versions': <String, dynamic>{'localized_redness': 1},
    },
  );
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
}
