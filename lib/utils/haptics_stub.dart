// Web stub for haptics and system sound
// Place in lib/utils/haptics_stub.dart

class HapticFeedback {
  static Future<void> lightImpact() async {}
  static Future<void> mediumImpact() async {}
}

class SystemSoundType {
  static const click = 0;
}

class SystemSound {
  static Future<void> play(dynamic type) async {}
}
