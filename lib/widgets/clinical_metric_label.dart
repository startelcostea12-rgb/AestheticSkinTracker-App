// lib/widgets/clinical_metric_label.dart
//
// A single source-of-truth widget for displaying a clinical skin metric
// label alongside a short plain-English explanation in parentheses, with a
// hover/long-press Tooltip carrying the full friendly description.
//
//   Compact mode  → "Rhytids (wrinkles)"           — Home, Before & After
//   Detailed mode → "Rhytids (fine lines & wrinkles)" — Reports, detail screens
//
// The parenthetical and tooltip are sourced from [SkinMetricRegistry] so
// every screen renders the same explanatory copy.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/skin_metric_labels.dart';

class ClinicalMetricLabel extends StatelessWidget {
  /// The metric label as it appears in code (e.g. `'Erythema'`).
  final String label;

  /// When true, renders the short parenthetical (`(wrinkles)`).
  /// When false, renders the full friendly description
  /// (`(fine lines & wrinkles)`).
  final bool compact;

  /// Style applied to the clinical name. The parenthetical inherits
  /// this style with a lighter weight and muted colour.
  final TextStyle? style;

  /// Additional context (e.g. derivation formula) appended to the tooltip.
  final String? extraTooltip;

  /// Maximum number of lines for the label. Defaults to 2.
  final int maxLines;

  const ClinicalMetricLabel({
    super.key,
    required this.label,
    this.compact = true,
    this.style,
    this.extraTooltip,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final spec = SkinMetricRegistry.byLabel(label);
    final baseStyle =
        style ??
        TextStyle(
          color: MyApp.textBrown,
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
          height: 1.2,
        );

    // Unknown metric — fall back to a plain Text so we never break layouts.
    if (spec == null) {
      return Text(
        label,
        style: baseStyle,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final parenthetical = compact
        ? spec.shortExplanation
        : spec.friendlyDescription;
    final tooltipMessage = extraTooltip == null || extraTooltip!.trim().isEmpty
        ? spec.tooltip
        : '${spec.tooltip}\n\n${extraTooltip!.trim()}';

    final muted = (baseStyle.color ?? MyApp.textBrown).withValues(alpha: 0.62);

    final richLabel = Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: spec.clinicalName),
          TextSpan(
            text: ' ($parenthetical)',
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );

    return Tooltip(
      message: tooltipMessage,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 11.5,
        height: 1.4,
      ),
      child: richLabel,
    );
  }
}
