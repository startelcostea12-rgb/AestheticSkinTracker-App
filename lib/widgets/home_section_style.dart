// Shared spacing and title style for the stacked home sections (last
// comparable pair, routine, concerns, style picks, protocol), so they
// read as one set.

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Vertical gap between home sections.
const double homeSectionGap = 12;

/// Gap between a section title and its body.
const double homeSectionTitleGap = 8;

/// Title style for every home section card.
const TextStyle homeSectionTitleStyle = TextStyle(
  color: AppColors.textStructure,
  fontSize: 16,
  fontWeight: FontWeight.w900,
);

/// Secondary line under an item name (descriptions, brands).
TextStyle homeSectionSubtleStyle() => TextStyle(
  color: AppColors.textStructure.withValues(alpha: 0.75),
  fontSize: 12.5,
);

/// Disclaimer line at the bottom of a recommendations section.
TextStyle homeSectionDisclaimerStyle() => TextStyle(
  color: AppColors.textStructure.withValues(alpha: 0.65),
  fontSize: 11,
  fontStyle: FontStyle.italic,
);

/// Empty-state and status messages inside a home section.
TextStyle homeSectionMessageStyle() => TextStyle(
  color: AppColors.textStructure.withValues(alpha: 0.75),
  height: 1.35,
);
