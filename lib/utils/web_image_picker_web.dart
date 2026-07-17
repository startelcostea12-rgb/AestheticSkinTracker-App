import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('_flutterPickImage')
external void _flutterPickImage(JSFunction callback);

void openWebImagePicker(void Function(Uint8List?) onComplete) {
  _flutterPickImage(
    ((JSAny? dataUrl) {
      if (dataUrl == null || dataUrl is! JSString) {
        onComplete(null);
        return;
      }

      final parts = dataUrl.toDart.split(',');
      if (parts.length < 2) {
        onComplete(null);
        return;
      }
      onComplete(base64Decode(parts[1]));
    }).toJS,
  );
}

Future<Uint8List?> pickWebImageBytes() async => null;
