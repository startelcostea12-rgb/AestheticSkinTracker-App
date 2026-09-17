import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData light(BuildContext context) {
    final base = Theme.of(context).textTheme.apply(
      bodyColor: AppColors.textStructure,
      displayColor: AppColors.textStructure,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: AppColors.warmAlabaster,
      primaryColor: AppColors.brandAccent,
      cardColor: AppColors.cardBackground,
      canvasColor: AppColors.warmAlabaster,
      dividerColor: AppColors.borders,
      textTheme: base.copyWith(
        headlineMedium: const TextStyle(
          inherit: true,
          fontFamily: 'Serif',
          color: AppColors.textStructure,
        ),
      ),
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.brandAccent,
        onPrimary: Colors.white,
        secondary: AppColors.brandAccent,
        onSecondary: Colors.white,
        // Tertiary/error intentionally stay in the status family (not
        // brand) — Material uses `error` for form validation/destructive
        // affordances, which is a "something's wrong" signal, not chrome.
        tertiary: AppColors.kMetricWorsenedColor,
        onTertiary: Colors.white,
        error: AppColors.kMetricWorsenedColor,
        onError: Colors.white,
        surface: AppColors.cardBackground,
        onSurface: AppColors.textStructure,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textStructure,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: AppColors.borders),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandAccent,
          foregroundColor: Colors.white,
          overlayColor: AppColors.goldHover.withValues(alpha: 0.18),
          elevation: 2,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brandAccent,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        iconColor: AppColors.brandAccent,
        prefixIconColor: AppColors.brandAccent,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(
            color: AppColors.brandAccent,
            width: 1.4,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: AppColors.borders),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandAccent,
        linearTrackColor: AppColors.borders,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.textStructure,
        unselectedLabelColor: AppColors.textStructure,
        indicatorColor: AppColors.brandAccent,
      ),
    );
  }

  /// Real dark theme (previously a no-op that forced Brightness.light).
  /// Surfaces move to a dark charcoal family, text inverts to off-white,
  /// and the brand accent / status colors each get a lighter tint so they
  /// keep sufficient contrast against dark surfaces while remaining
  /// recognizably "the same" accent/status hues as light mode.
  static ThemeData dark(BuildContext context) {
    final base = Theme.of(context).textTheme.apply(
      bodyColor: AppColors.darkText,
      displayColor: AppColors.darkText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: AppColors.darkCanvas,
      primaryColor: AppColors.darkAccent,
      cardColor: AppColors.darkCardBackground,
      canvasColor: AppColors.darkCanvas,
      dividerColor: AppColors.darkBorders,
      textTheme: base.copyWith(
        headlineMedium: const TextStyle(
          inherit: true,
          fontFamily: 'Serif',
          color: AppColors.darkText,
        ),
      ),
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.darkAccent,
        onPrimary: AppColors.darkCanvas,
        secondary: AppColors.darkAccent,
        onSecondary: AppColors.darkCanvas,
        tertiary: AppColors.darkMetricWorsenedColor,
        onTertiary: AppColors.darkCanvas,
        error: AppColors.darkMetricWorsenedColor,
        onError: AppColors.darkCanvas,
        surface: AppColors.darkCardBackground,
        onSurface: AppColors.darkText,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.darkText,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.darkCardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: AppColors.darkBorders),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkAccent,
          foregroundColor: AppColors.darkCanvas,
          overlayColor: AppColors.darkAccent.withValues(alpha: 0.24),
          elevation: 2,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.darkAccent,
        foregroundColor: AppColors.darkCanvas,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface,
        iconColor: AppColors.darkAccent,
        prefixIconColor: AppColors.darkAccent,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: AppColors.darkAccent, width: 1.4),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: AppColors.darkBorders),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.darkAccent,
        linearTrackColor: AppColors.darkBorders,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.darkText,
        unselectedLabelColor: AppColors.darkText,
        indicatorColor: AppColors.darkAccent,
      ),
    );
  }

  AppTheme._();
}


