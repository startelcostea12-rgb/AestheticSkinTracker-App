import 'dart:html' as html;
import 'dart:typed_data';

Future<String?> shareProfessionalReportPdf(
  Uint8List bytes, {
  required String fileName,
}) async {
  final blob = html.Blob(<dynamic>[bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);

  return 'web-download:$fileName';
}

/// Opens [bytes] as a PDF in a new browser tab.
/// Falls back to download if the popup is blocked.
Future<bool> openPdfDocumentOnWeb(
  Uint8List bytes, {
  required String fileName,
}) async {
  final blob = html.Blob(<dynamic>[bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  // Revoke after a delay so the browser tab has time to load the blob.
  Future<void>.delayed(
    const Duration(seconds: 60),
    () => html.Url.revokeObjectUrl(url),
  );
  return true;
}
