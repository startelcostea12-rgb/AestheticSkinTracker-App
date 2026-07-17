import 'dart:typed_data';

import 'web_blob_bytes_stub.dart'
    if (dart.library.html) 'web_blob_bytes_web.dart'
    as impl;

Future<Uint8List?> readWebBlobBytes(String url) => impl.readWebBlobBytes(url);
