// Web stub for HapticFeedback and SystemSound APIs
// Only used on web via conditional import

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
