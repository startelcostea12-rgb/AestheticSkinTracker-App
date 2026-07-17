// Web stub for dart:io APIs
// Place in lib/utils/io_stub.dart

class File {
  File(String path);
  Future<void> writeAsBytes(List<int> bytes, {bool flush = false}) async {}
  Future<bool> exists() async => false;
  String get path => '';
}

class Directory {
  Directory(String path);
  String get path => '';
}

class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
}

String get pathSeparator => '/';
