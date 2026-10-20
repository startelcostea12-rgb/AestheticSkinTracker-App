import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';

import 'barcode_reader.dart';

Future<BarcodeReadResult> readProductBarcode() async {
  final XFile? photo;
  try {
    photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1800,
      maxHeight: 1800,
    );
  } catch (_) {
    return const BarcodeReadResult(BarcodeReadStatus.unsupported);
  }
  if (photo == null) {
    return const BarcodeReadResult(BarcodeReadStatus.cancelled);
  }
  final scanner = BarcodeScanner(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upca,
      BarcodeFormat.upce,
    ],
  );
  try {
    final barcodes = await scanner.processImage(
      InputImage.fromFilePath(photo.path),
    );
    for (final barcode in barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        return BarcodeReadResult(BarcodeReadStatus.found, code);
      }
    }
    return const BarcodeReadResult(BarcodeReadStatus.noBarcode);
  } catch (_) {
    // ML Kit is only on iOS/Android; desktop builds land here.
    return const BarcodeReadResult(BarcodeReadStatus.unsupported);
  } finally {
    await scanner.close();
  }
}
