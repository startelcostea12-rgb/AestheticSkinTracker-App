import 'package:flutter/foundation.dart';

class AppLogger {
  static bool _verboseEnabled = false;

  static bool get verboseEnabled => _verboseEnabled;

  static void setVerboseEnabled(bool enabled) {
    _verboseEnabled = enabled;
  }

  static void debug(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  static void verbose(String message) {
    if (!kDebugMode || !_verboseEnabled) return;
    debugPrint(message);
  }
}
