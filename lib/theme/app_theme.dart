import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData light(BuildContext context) {
    final base = Theme.of(context).textTheme.apply(
      bodyColor: Colors.black,
      displayColor: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: AppColors.warmAlabaster,
      primaryColor: AppColors.champagneGold,
      cardColor: AppColors.cardBackground,
      canvasColor: AppColors.warmAlabaster,
      dividerColor: AppColors.borders,
      textTheme: base.copyWith(
        headlineMedium: const TextStyle(
          inherit: true,
          fontFamily: 'Serif',
          color: Colors.black,
        ),
      ),
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.champagneGold,
        onPrimary: Colors.black,
        secondary: AppColors.mutedSage,
        onSecondary: Colors.black,
        tertiary: AppColors.softTerracotta,
        onTertiary: Colors.black,
        error: AppColors.softTerracotta,
        onError: Colors.black,
        surface: AppColors.cardBackground,
        onSurface: Colors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borders),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.champagneGold,
          foregroundColor: Colors.black,
          overlayColor: AppColors.goldHover.withValues(alpha: 0.18),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.champagneGold,
        foregroundColor: Colors.black,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        iconColor: AppColors.champagneGold,
        prefixIconColor: AppColors.champagneGold,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.champagneGold,
            width: 1.4,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borders),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.mutedSage,
        linearTrackColor: AppColors.borders,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.black,
        unselectedLabelColor: Colors.black,
        indicatorColor: AppColors.champagneGold,
      ),
    );
  }

  static ThemeData dark(BuildContext context) {
    // Keep dark mode stylistically aligned with the light luxe palette so
    // text contrast remains consistently black across the app.
    return light(context).copyWith(brightness: Brightness.light);
  }

  AppTheme._();
}
