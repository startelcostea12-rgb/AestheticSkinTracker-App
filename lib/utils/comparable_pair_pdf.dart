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

const String comparablePairPdfClinicPlaceholder = '[Clinic name]';

String _date(DateTime t) => DateFormat('MMM d, y h:mm a').format(t);
String _value(double? v) => v == null ? '-' : v.toStringAsFixed(1);

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
