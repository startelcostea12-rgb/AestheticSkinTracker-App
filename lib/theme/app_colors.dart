import 'package:flutter/material.dart';

/// Clinical-modern palette.
///
/// Two color families are kept deliberately separate and must never swap
/// roles (see kMetricImprovedColor / kMetricWorsenedColor below):
///   - Brand/chrome accent (`brandAccent` and its aliases below) — app bar,
///     buttons, active nav, FAB, links, generic decorative accents. This is
///     "this is interactive / this is our brand," not a judgment call.
///   - Metric status colors (`kMetricImprovedColor` / `kMetricWorsenedColor`)
///     — reserved exclusively for improved/worsened/stable signaling on
///     scan comparisons, trend badges, and delta chips. Never use these for
///     chrome; never use the brand accent for a status badge.
class AppColors {
  // ── Brand / chrome ────────────────────────────────────────────────────
  static const Color brandAccent = Color(0xFFC1552E); // terracotta
  static const Color champagneGold = Color(0xFFD9A441); // muted gold
  static const Color onChampagneGold = Colors.white;
  static const Color goldHover = Color(0xFFB96C30); // terracotta-toned hover

  // ── Text ──────────────────────────────────────────────────────────────
  static const Color textStructure = Color(0xFF2B211C); // espresso
  static const Color refinedSlate = textStructure;

  // ── Surfaces ──────────────────────────────────────────────────────────
  static const Color canvas = Color(0xFFF7EFE5); // bone
  static const Color warmAlabaster = canvas;
  static const Color cardBackground = Color(0xFFF9F2E8); // slightly warmer bone
  static const Color borders = Color(0xFFE9DCC8);

  // ── Metric status (reserved — see class doc) ─────────────────────────
  static const Color kMetricImprovedColor = Color(0xFF6E8B5D); // sage
  static const Color kMetricWorsenedColor = Color(0xFFA8402C); // brick

  /// Deprecated aliases kept only so any missed call site still resolves to
  /// the correct *status* color rather than silently reverting to the old
  /// sage/terracotta hex. Prefer kMetricImprovedColor / kMetricWorsenedColor
  /// directly in new code — these names conflate brand-era naming
  /// ("positiveProgress"/"healingRedness") with what is now strictly a
  /// status-only meaning.
  static const Color positiveProgress = kMetricImprovedColor;
  static const Color mutedSage = kMetricImprovedColor;
  static const Color healingRedness = kMetricWorsenedColor;
  static const Color softTerracotta = kMetricWorsenedColor;

  // ── Dark mode ─────────────────────────────────────────────────────────
  static const Color darkCanvas = Color(0xFF1E1714); // deep espresso dark
  static const Color darkSurface = Color(0xFF2A221F);
  static const Color darkCardBackground = Color(0xFF332B27);
  static const Color darkBorders = Color(0xFF4B3B35);
  static const Color darkText = Color(0xFFF5EEE7); // bone/off-white
  static const Color darkAccent = Color(0xFFD56F48); // terracotta in dark mode
  static const Color darkMetricImprovedColor = Color(0xFF8BAA7A);
  static const Color darkMetricWorsenedColor = Color(0xFFBF6D52);

  AppColors._();
}
