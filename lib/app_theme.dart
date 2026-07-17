import 'package:flutter/material.dart';
export 'theme/app_colors.dart';
import 'theme/app_colors.dart';

class MyApp {
  static final ValueNotifier<ThemeMode> themeModeNotifier =
  ValueNotifier<ThemeMode>(ThemeMode.light);
  static const double cardRadiusValue = 20;
  static const double buttonRadiusValue = 18;
  static const double primaryButtonHeight = 58;
  static const double sectionHeaderFontSize = 21;
  static const EdgeInsets cardPadding = EdgeInsets.all(20);

  static bool get isDark {
    final mode = themeModeNotifier.value;
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  static Color get champagne =>
      isDark ? AppColors.darkCanvas : AppColors.canvas;
  static Color get blush =>
      isDark ? AppColors.darkSurface : AppColors.cardBackground;
  static Color get roseGold =>
      isDark ? AppColors.softTerracotta : AppColors.softTerracotta;
  static Color get goldShimmer => AppColors.champagneGold;
  static Color get textBrown =>
      Colors.black;
  static Color get surface =>
      isDark ? AppColors.darkSurface : AppColors.cardBackground;
  static Color get clinicalNavy =>
      Colors.black;
  static Color get clinicalSlate => isDark
      ? Colors.black
      : Colors.black;
  static Color get clinicalTeal => AppColors.mutedSage;
  static Color get clinicalMuted => isDark
      ? Colors.black
      : Colors.black;
  static BorderRadius get cardRadius => BorderRadius.circular(cardRadiusValue);
  static BorderRadius get buttonRadius =>
      BorderRadius.circular(buttonRadiusValue);

  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  static RoundedRectangleBorder get cardShape => RoundedRectangleBorder(
    borderRadius: cardRadius,
    side: BorderSide(
      color: AppColors.borders.withValues(alpha: isDark ? 0.24 : 1.0),
    ),
  );

  static BoxDecoration surfaceCardDecoration({double tintOpacity = 0.08}) {
    return BoxDecoration(
      color: surface,
      borderRadius: cardRadius,
      border: Border.all(
        color: AppColors.borders.withValues(alpha: isDark ? 0.24 : 1.0),
      ),
      boxShadow: cardShadow,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          surface,
          goldShimmer.withValues(alpha: tintOpacity),
        ],
      ),
    );
  }

  static TextStyle pageTitleStyle({Color? color}) => TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: color ?? textBrown,
  );

  static TextStyle sectionTitleStyle({Color? color}) => TextStyle(
    fontSize: sectionHeaderFontSize,
    fontWeight: FontWeight.w800,
    color: color ?? textBrown,
  );

  static TextStyle cardTitleStyle({Color? color}) => TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: color ?? textBrown,
  );

  static ButtonStyle get primaryGoldButton => ElevatedButton.styleFrom(
    backgroundColor: goldShimmer,
    foregroundColor: Colors.black,
    minimumSize: const Size(double.infinity, primaryButtonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
    shape: RoundedRectangleBorder(borderRadius: buttonRadius),
    elevation: 3,
    shadowColor: goldShimmer.withValues(alpha: 0.28),
    overlayColor: AppColors.goldHover.withValues(alpha: 0.18),
    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
  );

  static ButtonStyle get primaryRoseButton => ElevatedButton.styleFrom(
    backgroundColor: goldShimmer,
    foregroundColor: Colors.black,
    minimumSize: const Size(double.infinity, primaryButtonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
    shape: RoundedRectangleBorder(borderRadius: buttonRadius),
    elevation: 3,
    shadowColor: goldShimmer.withValues(alpha: 0.28),
    overlayColor: AppColors.goldHover.withValues(alpha: 0.18),
    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
  );

  static ButtonStyle secondaryOutlineButton({Color? accent}) =>
      ElevatedButton.styleFrom(
        backgroundColor: surface,
        foregroundColor: accent ?? textBrown,
        minimumSize: const Size(double.infinity, primaryButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: buttonRadius,
          side: BorderSide(
            color: (accent ?? goldShimmer).withValues(alpha: 0.45),
            width: 1.2,
          ),
        ),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      );

  static void setThemeMode(ThemeMode mode) {
    themeModeNotifier.value = mode;
  }

  MyApp._();
}
