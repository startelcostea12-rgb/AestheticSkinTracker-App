import 'dart:convert';
import 'dart:io';

import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_comparison_baseline.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/comparable_pair_pdf.dart';
import 'package:aesthetic_skin_tracker/utils/last_comparable_pair.dart';
import 'package:aesthetic_skin_tracker/utils/scan_note.dart';
import 'package:aesthetic_skin_tracker/widgets/scan_note_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScanHistoryEntry _scan(
  String id,
  int day, {
  String? note,
  String? comparedWith,
}) => ScanHistoryEntry(
  id: id,
  timestamp: DateTime(2026, 10, day, 9, 30),
  scanType: ScanHistoryEntry.scanTypeAiAnalysis,
  estimatedSkinAge: 0,
  metrics: const <String, double>{},
  poseTemplate: 'Front',
  guideType: 'facial',
  rawPayload: <String, dynamic>{
    'metric_matrix': <String, dynamic>{'texture_smoothness': 59.0},
    'note_unrelated': 1,
    if (note != null) scanNoteKey: note,
    aiComparisonBaselineScanIdKey: comparedWith,
  },
);

Map<String, String> _csvRow(ScanHistoryEntry scan) {
  final rows = AiScanDataCsvExporter.format([
    scan,
  ], registryBaselineScanIds: const {}).split('\r\n');
  final header = rows.first.split(',');
  final values = rows[1].split(',');
  return {for (var i = 0; i < header.length; i++) header[i]: values[i]};
}

Future<String> _pdfWords(ComparablePair pair) async {
  final raw = latin1.decode(
    await buildComparablePairPdf(pair, compress: false),
  );
  return RegExp(r'\[\((.*?)\)\]TJ')
      .allMatches(raw)
      .map((m) => m.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')'))
      .join(' ');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a note is saved with the scan; a blank note removes it', () async {
    await AppPrefs.addScanEntry(_scan('s1', 2));
    expect(
      await saveScanNote(scanId: 's1', note: '  lamp at 45 deg  '),
      isTrue,
    );
    var saved = (await AppPrefs.getScanEntries()).single;
    expect(scanNoteOf(saved), 'lamp at 45 deg');
    expect(saved.rawPayload!['note_unrelated'], 1);
    expect(saved.rawPayload!['metric_matrix'], {'texture_smoothness': 59.0});

    expect(await saveScanNote(scanId: 's1', note: '   '), isTrue);
    saved = (await AppPrefs.getScanEntries()).single;
    expect(saved.rawPayload!.containsKey(scanNoteKey), isFalse);
    expect(scanNoteOf(saved), isNull);

    expect(await saveScanNote(scanId: 'missing', note: 'x'), isFalse);
  });

  testWidgets('the results field saves the note', (tester) async {
    await AppPrefs.addScanEntry(_scan('s1', 2));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ScanNoteField(scanId: 's1')),
      ),
    );
    expect(find.text('Note for this scan'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('scan_note_field')),
      'Chin a bit higher than baseline',
    );
    await tester.tap(find.byKey(const ValueKey('scan_note_save')));
    await tester.pumpAndSettle();
    expect(find.text('Note saved'), findsOneWidget);
    final saved = (await AppPrefs.getScanEntries()).single;
    expect(scanNoteOf(saved), 'Chin a bit higher than baseline');
  });

  test('CSV: the note column, empty without a note', () {
    expect(
      _csvRow(_scan('a', 1, note: 'lamp moved'))['scan_note'],
      'lamp moved',
    );
    expect(_csvRow(_scan('b', 1))['scan_note'], isEmpty);
  });

  test(
    'PDF: notes included; empty notes omitted; punctuation made safe',
    () async {
      final withNotes = await _pdfWords(
        lastComparablePair([
          _scan('base', 1, note: 'Baseline under lamp'),
          _scan('later', 2, comparedWith: 'base', note: 'Blinds “closed” — ok'),
        ])!,
      );
      expect(withNotes, contains('Note (earlier scan): Baseline under lamp'));
      expect(withNotes, contains('Note (later scan): Blinds "closed" - ok'));

      final noNotes = await _pdfWords(
        lastComparablePair([
          _scan('base', 1),
          _scan('later', 2, comparedWith: 'base'),
        ])!,
      );
      expect(noNotes, isNot(contains('Note')));
      expect(pdfSafeText('emoji \u{1F600} ok'), 'emoji ? ok');
    },
  );

  test('the results screen shows the field for the scan it saved', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    expect(source, contains('_savedScanId = savedEntry?.id;'));
    expect(source, contains('if (_savedScanId != null) ...['));
    expect(source, contains('ScanNoteField('));
  });
}
