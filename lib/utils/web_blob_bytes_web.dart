import 'dart:typed_data';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<Uint8List?> readWebBlobBytes(String url) async {
  final request = await html.HttpRequest.request(
    url,
    responseType: 'arraybuffer',
  );
  final response = request.response;
  if (response is ByteBuffer) return response.asUint8List();
  if (response is Uint8List) return response;
  return null;
}
