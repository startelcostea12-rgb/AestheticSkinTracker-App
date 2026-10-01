import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/services/skin_history_repository.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Map<String, String>> parseCsv(String csv) {
  final rows = csv.split('\r\n');
  final columns = rows.first.split(',');
  return [
    for (final row in rows.skip(1))
      {
        for (var index = 0; index < columns.length; index++)
          columns[index]: row.split(',')[index],
      },
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('computed zero is saved and exported while omitted stays absent', () async {
    final measuredZero = await SkinHistoryRepository.instance.saveScan(
      metrics: const <String, double>{},
      timestamp: DateTime.utc(2026, 9, 28, 13, 27, 26),
      scanType: ScanHistoryEntry.scanTypeAiAnalysis,
      rawPayload: const <String, dynamic>{
        'metric_matrix': <String, dynamic>{'localized_redness': 0.0},
      },
    );
    final omitted = await SkinHistoryRepository.instance.saveScan(
      metrics: const <String, double>{},
      timestamp: DateTime.utc(2026, 9, 28, 13, 28, 3),
      scanType: ScanHistoryEntry.scanTypeAiAnalysis,
      rawPayload: const <String, dynamic>{
        'metric_matrix': <String, dynamic>{'texture_smoothness': 60.0},
      },
    );

    expect(measuredZero.metrics, containsPair('localized_redness', 0.0));
    expect(omitted.metrics.containsKey('localized_redness'), isFalse);
    final omittedMetrics = LuxeMetricParser.parseTimelinePayload(
      omitted.rawPayload!,
    );
    expect(
      omittedMetrics.any((metric) => metric.key == 'localized_redness'),
      isFalse,
    );

    final csv = AiScanDataCsvExporter.format(
      <ScanHistoryEntry>[measuredZero, omitted],
      registryBaselineScanIds: const <String>{},
    );
    final rows = parseCsv(csv);
    final zeroRow = rows.singleWhere((row) => row['scan_id'] == measuredZero.id);
    final omittedRow = rows.singleWhere((row) => row['scan_id'] == omitted.id);
    expect(zeroRow['localized_redness_value'], '0.0');
    expect(omittedRow['localized_redness_value'], isEmpty);
  });

  testWidgets('computed zero is shown instead of treated as missing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LuxeReportLayout(
              rawPayload: <String, dynamic>{
                'metric_matrix': <String, dynamic>{'localized_redness': 0.0},
                'local_history_count': 1,
                'is_follow_up': false,
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Localized Redness'), findsOneWidget);
    expect(find.textContaining('Current Clear (0.0)'), findsWidgets);
  });

  testWidgets('zero baseline compares without a percentage', (tester) async {
    const payload = <String, dynamic>{
      'metric_matrix': <String, dynamic>{'localized_redness': 2.3},
      'baseline_metric_matrix': <String, dynamic>{'localized_redness': 0.0},
      'metric_extraction_paths': <String, dynamic>{
        'localized_redness': 'cheek_primary',
      },
      'baseline_metric_extraction_paths': <String, dynamic>{
        'localized_redness': 'cheek_primary',
      },
      'trend_deltas': <String, dynamic>{'localized_redness': 0.0},
      'trend_status': <String, dynamic>{'localized_redness': 'stable'},
      'local_history_count': 2,
      'is_follow_up': true,
    };

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LuxeReportLayout(
              rawPayload: payload,
              requireBackendVerdict: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Baseline 0.0'), findsWidgets);
    final rednessCard = find.byKey(
      const ValueKey('result_metric_localized_redness'),
    );
    expect(
      find.descendant(of: rednessCard, matching: find.textContaining('%')),
      findsNothing,
    );
    expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
    expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    expect(
      LuxeMetricParser.formatDisplayDelta(
        baseline: 0.0,
        current: 2.3,
        deltaPct: 100.0,
        includeSign: true,
      ),
      '+2.3 pts',
    );
  });
}
