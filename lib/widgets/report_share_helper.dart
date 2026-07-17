import 'dart:typed_data';

import 'report_share_helper_stub.dart'
    if (dart.library.html) 'report_share_helper_web.dart'
    if (dart.library.io) 'report_share_helper_io.dart'
    as impl;

Future<String?> shareProfessionalReportPdf(
  Uint8List bytes, {
  required String fileName,
}) {
  return impl.shareProfessionalReportPdf(bytes, fileName: fileName);
}

/// Opens the PDF in a new browser tab on web; returns false on native.
Future<bool> openPdfDocumentOnWeb(Uint8List bytes, {required String fileName}) {
  return impl.openPdfDocumentOnWeb(bytes, fileName: fileName);
}
