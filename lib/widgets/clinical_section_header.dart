import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Shared clinical section header used across reports & detail screens.
/// Renders a small gold→rose icon tile, an optional uppercase eyebrow caption,
/// and the section title in the global `MyApp.sectionTitleStyle`.
class ClinicalSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? eyebrow;
  final Color? textColor;
  final Widget? trailing;

  const ClinicalSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.eyebrow,
    this.textColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedTextColor =
        textColor ??
        Theme.of(context).textTheme.bodyLarge?.color ??
        MyApp.textBrown;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                MyApp.goldShimmer.withValues(alpha: 0.18),
                MyApp.roseGold.withValues(alpha: 0.14),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: MyApp.goldShimmer.withValues(alpha: 0.28),
              width: 0.8,
            ),
          ),
          child: Icon(icon, color: MyApp.goldShimmer, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                    color: MyApp.clinicalMuted,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              Text(
                title,
                style: MyApp.sectionTitleStyle(color: resolvedTextColor),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// Compact clinical AppBar styling: uppercase eyebrow above the title in
/// the AppBar's center area. Use as `title:` on a standard AppBar.
class ClinicalAppBarTitle extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final Color? color;

  const ClinicalAppBarTitle({
    super.key,
    required this.title,
    this.eyebrow,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        Theme.of(context).textTheme.titleLarge?.color ??
        MyApp.textBrown;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (eyebrow != null)
          Text(
            eyebrow!.toUpperCase(),
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
              color: MyApp.clinicalMuted,
            ),
          ),
        const SizedBox(height: 1),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: c,
          ),
        ),
      ],
    );
  }
}
