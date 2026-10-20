/// Reads one product barcode from a camera photo (ML Kit on device; a stub
/// that reports "unsupported" elsewhere, e.g. web).
library;

import 'barcode_reader_stub.dart'
    if (dart.library.io) 'barcode_reader_mlkit.dart'
    as impl;

enum BarcodeReadStatus { found, cancelled, noBarcode, unsupported }

class BarcodeReadResult {
  const BarcodeReadResult(this.status, [this.code]);

  final BarcodeReadStatus status;

  /// The decoded digits when [status] is found.
  final String? code;
}

/// Opens the camera, then decodes the first EAN/UPC barcode in the photo.
Future<BarcodeReadResult> readProductBarcode() => impl.readProductBarcode();
