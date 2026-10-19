/// One-page clinic PDF of the last comparable pair (see lastComparablePair):
/// a clinic-name placeholder, the two dates, absolute values for the six
/// comparablePairMetricKeys, and any lock reasons. No arrows, no
/// percentages, no verdicts. ASCII text only, so the built-in PDF font
/// renders every character.
library;

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'last_comparable_pair.dart';
import 'scan_note.dart';

const String comparablePairPdfClinicPlaceholder = '[Clinic name]';

String _date(DateTime t) => DateFormat('MMM d, y h:mm a').format(t);
String _value(double? v) => v == null ? '-' : v.toStringAsFixed(1);

/// Notes are free text: map typographic punctuation to ASCII and replace
/// anything else outside Latin-1 with '?', so the built-in font draws it.
String pdfSafeText(String text) {
  final mapped = text
      .replaceAll(RegExp('[\u2018\u2019]'), "'")
      .replaceAll(RegExp('[\u201C\u201D]'), '"')
      .replaceAll(RegExp('[\u2013\u2014]'), '-')
      .replaceAll('\u2026', '...');
  return String.fromCharCodes(
    mapped.runes.map(
      (r) => (r == 0x0A || (r >= 0x20 && r <= 0x7E) || (r >= 0xA0 && r <= 0xFF))
          ? r
          : 0x3F,
    ),
  );
}

/// [compress] false keeps the content stream as plain text (used by tests).
Future<Uint8List> buildComparablePairPdf(
  ComparablePair pair, {
  String clinicName = comparablePairPdfClinicPlaceholder,
  bool compress = true,
}) async {
  final doc = pw.Document(compress: compress);
  final baseline = pair.baseline;
  pw.Widget cell(String text, {bool bold = false, bool right = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        child: pw.Text(
          text,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(48),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            clinicName,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Skin scan comparison',
            style: const pw.TextStyle(fontSize: 13),
          ),
          pw.SizedBox(height: 16),
          if (baseline != null) ...[
            pw.Text('Earlier scan: ${_date(baseline.timestamp)}'),
            pw.Text('Later scan: ${_date(pair.latest.timestamp)}'),
          ] else ...[
            pw.Text('Scan: ${_date(pair.latest.timestamp)}'),
            pw.Text('No prior comparable scan.'),
          ],
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1),
              if (baseline != null) 2: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                children: [
                  cell('Metric', bold: true),
                  if (baseline != null)
                    cell('Earlier', bold: true, right: true),
                  cell(
                    baseline != null ? 'Later' : 'Value',
                    bold: true,
                    right: true,
                  ),
                ],
              ),
              for (final key in comparablePairMetricKeys)
                pw.TableRow(
                  children: [
                    cell(comparablePairMetricLabels[key]!),
                    if (baseline != null)
                      cell(_value(pair.baselineValue(key)), right: true),
                    cell(_value(pair.latestValue(key)), right: true),
                  ],
                ),
            ],
          ),
          if (pair.lockReasons.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              'Lock reasons',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            for (final entry in pair.lockReasons.entries)
              pw.Text(
                '${entry.key.replaceAll('_', ' ')}: '
                '${entry.value.replaceAll('_', ' ')}',
              ),
          ],
          for (final (label, scan) in [
            if (baseline != null) ('Note (earlier scan)', baseline),
            (baseline != null ? 'Note (later scan)' : 'Note', pair.latest),
          ])
            if (scanNoteOf(scan) case final note?) ...[
              pw.SizedBox(height: 10),
              pw.Text(
                '$label: ${pdfSafeText(note)}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          pw.Spacer(),
          pw.Text(
            'Absolute values only. Not a diagnosis.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
