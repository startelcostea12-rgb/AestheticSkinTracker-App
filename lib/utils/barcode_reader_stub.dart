import 'barcode_reader.dart';

Future<BarcodeReadResult> readProductBarcode() async =>
    const BarcodeReadResult(BarcodeReadStatus.unsupported);
