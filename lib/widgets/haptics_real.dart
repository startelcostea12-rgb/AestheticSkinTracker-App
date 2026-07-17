// lib/utils/haptics_real.dart
// This file is used on real mobile devices (Android/iOS)

import 'package:flutter/services.dart' as services;

class HapticFeedback {
  static Future<void> lightImpact() async {
    await services.HapticFeedback.lightImpact();
  }

  static Future<void> mediumImpact() async {
    await services.HapticFeedback.mediumImpact();
  }

  static Future<void> heavyImpact() async {
    await services.HapticFeedback.heavyImpact();
  }
}
