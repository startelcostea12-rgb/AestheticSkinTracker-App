import 'package:flutter/material.dart';

extension ColorWithValues on Color {
  /// Returns a copy of this color with the given alpha (opacity) value (0.0-1.0 or 0-1 for ints).
  Color withValues({double? alpha}) {
    int a = alpha != null
        ? (alpha <= 1.0 ? (alpha * 255).round() : alpha.round())
        : (this.a * 255.0).round().clamp(0, 255);
    return withAlpha(a);
  }
}
