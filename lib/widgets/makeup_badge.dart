// lib/widgets/makeup_badge.dart
//
// Compact clinical badge shown on any scan tile whose underlying
// [ScanHistoryEntry.makeupPresent] flag is true. Communicates that the scan's
// metrics carry reduced clinical confidence and should be interpreted
// alongside the makeup-disclosed context.

import 'package:flutter/material.dart';

import '../app_theme.dart';

class MakeupBadge extends StatelessWidget {
  const MakeupBadge({super.key, this.compact = false, this.label});

  /// Compact form drops the long descriptor and shows only "Makeup".
  /// Useful for dense list rows where horizontal space is tight.
  final bool compact;

  /// Optional override label. Defaults to the canonical clinical wording.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text =
        label ?? (compact ? 'Makeup' : 'Makeup Detected — Accuracy Reduced');
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: MyApp.roseGold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: MyApp.roseGold,
            size: compact ? 11 : 13,
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(
            text,
            style: TextStyle(
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
              color: MyApp.roseGold,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
