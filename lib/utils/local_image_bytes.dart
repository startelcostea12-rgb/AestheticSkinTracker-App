import 'dart:typed_data';

import 'local_image_bytes_stub.dart'
    if (dart.library.io) 'local_image_bytes_io.dart'
    as impl;

Future<Uint8List?> readLocalImageBytes(String ref) {
  return impl.readLocalImageBytes(ref);
}
