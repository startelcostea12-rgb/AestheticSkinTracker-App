import 'dart:typed_data';

import 'web_image_picker_stub.dart'
    if (dart.library.html) 'web_image_picker_web.dart'
    as impl;

/// Synchronous trigger — exactly mirrors scar tracker pattern.
/// Calls [onComplete] with bytes, or null if cancelled/failed.
void openWebImagePicker(void Function(Uint8List?) onComplete) {
  impl.openWebImagePicker(onComplete);
}

Future<Uint8List?> pickWebImageBytes() {
  return impl.pickWebImageBytes();
}
