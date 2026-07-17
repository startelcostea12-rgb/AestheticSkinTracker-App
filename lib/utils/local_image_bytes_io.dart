import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readLocalImageBytes(String ref) async {
  final file = File(ref);
  if (!file.existsSync()) {
    return null;
  }
  return file.readAsBytes();
}
