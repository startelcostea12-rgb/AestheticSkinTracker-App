import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

String? _documentsDirectory;

String? get scanPhotoDocumentsDirectory => _documentsDirectory;

Future<void> initializeScanPhotoPaths() async {
  if (kIsWeb) return;
  try {
    _documentsDirectory = (await getApplicationDocumentsDirectory()).path;
  } on MissingPluginException {
    _documentsDirectory = null;
  } on MissingPlatformDirectoryException {
    _documentsDirectory = null;
  } on UnsupportedError {
    _documentsDirectory = null;
  }
}

String? storedScanPhotoPath(String? imagePath, String? documentsDirectory) {
  if (imagePath == null || imagePath.isEmpty || documentsDirectory == null) {
    return imagePath;
  }
  final uri = Uri.tryParse(imagePath);
  if (uri == null || uri.hasScheme) return imagePath;
  final root = Uri.directory(documentsDirectory).path;
  if (imagePath.startsWith(root)) return imagePath.substring(root.length);
  final legacyIos =
      imagePath.contains('/Containers/Data/Application/') ||
      imagePath.startsWith('/var/mobile/Applications/');
  final documentsIndex = imagePath.indexOf('/Documents/');
  if (legacyIos && documentsIndex >= 0) {
    return imagePath.substring(documentsIndex + '/Documents/'.length);
  }
  return imagePath;
}

String? resolvedScanPhotoPath(String? imagePath, String? documentsDirectory) {
  final stored = storedScanPhotoPath(imagePath, documentsDirectory);
  if (stored == null || stored.isEmpty || documentsDirectory == null) {
    return stored;
  }
  final uri = Uri.tryParse(stored);
  if (uri == null || uri.hasScheme || stored.startsWith('/')) return stored;
  if (uri.pathSegments.contains('..')) return imagePath;
  return Uri.directory(documentsDirectory).resolveUri(uri).toFilePath();
}

Future<String?> loadScanPhotoPath(
  String? imagePath,
  String? documentsDirectory,
) async {
  final resolved = resolvedScanPhotoPath(imagePath, documentsDirectory);
  if (kIsWeb || imagePath == null || imagePath.isEmpty || documentsDirectory == null) {
    return resolved;
  }
  final uri = Uri.tryParse(imagePath);
  if (uri == null || uri.hasScheme || uri.pathSegments.contains('..')) {
    return imagePath;
  }
  try {
    if (uri.hasAbsolutePath && await File(imagePath).exists()) return imagePath;
    if (resolved != null && await File(resolved).exists()) return resolved;
    final filename = uri.pathSegments.last;
    final documents = Directory(documentsDirectory);
    if (await documents.exists()) {
      String? match;
      await for (final entry in documents.list(recursive: true, followLinks: false)) {
        if (entry is! File || entry.uri.pathSegments.last != filename) continue;
        if (match != null) return uri.hasAbsolutePath ? imagePath : resolved;
        match = entry.path;
      }
      if (match != null) return match;
    }
  } on FileSystemException {
    return uri.hasAbsolutePath ? imagePath : resolved;
  }
  return uri.hasAbsolutePath ? imagePath : resolved;
}
