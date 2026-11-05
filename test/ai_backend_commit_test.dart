import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_backend_commit.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAiBackendCommit', () {
    test('prefers analyze-response backend_commit over health', () {
      expect(
        resolveAiBackendCommit(
          analyzeResponse: const {'backend_commit': 'abc123'},
          healthCommit: 'health-only',
        ),
        'abc123',
      );
    });

    test('falls back to health commit for older analyze responses', () {
      expect(
        resolveAiBackendCommit(
          analyzeResponse: const {'metric_matrix': <String, dynamic>{}},
          healthCommit: ' from-health ',
        ),
        'from-health',
      );
    });

    test('returns null when no server commit is available', () {
      expect(resolveAiBackendCommit(analyzeResponse: const {}), isNull);
      expect(resolveAiBackendCommit(healthCommit: '  '), isNull);
    });
  });

  test('recordAiBackendCommit ignores blank values', () {
    final payload = <String, dynamic>{};
    recordAiBackendCommit(payload, null);
    recordAiBackendCommit(payload, '   ');
    expect(payload.containsKey(aiBackendCommitKey), isFalse);
    recordAiBackendCommit(payload, 'deadbeef');
    expect(payload[aiBackendCommitKey], 'deadbeef');
  });

  test('CSV export includes persisted backend_commit and leaves older scans empty', () {
    ScanHistoryEntry scan(String id, {String? commit}) {
      return ScanHistoryEntry(
        id: id,
        timestamp: DateTime.parse('2026-09-25T06:13:00'),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: {
          'metric_matrix': <String, dynamic>{'rosacea_severity': 3.0},
          if (commit != null) 'backend_commit': commit,
        },
      );
    }

    final csv = AiScanDataCsvExporter.format(
      [scan('with-commit', commit: 'cafe123'), scan('legacy')],
      registryBaselineScanIds: const {},
    );
    final rows = csv.split('\r\n');
    final columns = rows.first.split(',');
    final parsed = [
      for (final row in rows.skip(1))
        {
          for (var i = 0; i < columns.length; i++)
            columns[i]: row.split(',')[i],
        },
    ];
    final byId = {for (final row in parsed) row['scan_id']: row};
    expect(byId['with-commit']!['backend_commit'], 'cafe123');
    expect(byId['legacy']!['backend_commit'], isEmpty);
  });
}
