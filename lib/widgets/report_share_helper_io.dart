import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/report_disclaimer.dart';

Future<String?> shareProfessionalReportPdf(
  Uint8List bytes, {
  required String fileName,
}) async {
  final tmp = await getTemporaryDirectory();
  final file = File('${tmp.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(file.path)],
    subject: 'AestheticSkinTracker Professional Report',
    text: recoveryReportDisclaimerText,
  );
  return file.path;
}

/// Not applicable on native — returns false.
Future<bool> openPdfDocumentOnWeb(
  Uint8List bytes, {
  required String fileName,
}) async {
  return false;
}
