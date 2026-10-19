// One-time "Recommended lighting" tip on the AI scan screen. Practical
// capture guidance only -- no medical claims.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/app_prefs.dart';

/// AppPrefs key set once the tip has been dismissed.
const String lightingTipSeenKey = 'scan_lighting_tip_seen';

Future<bool> shouldShowLightingTip() async =>
    await AppPrefs.getString(lightingTipSeenKey) != 'true';

Future<void> markLightingTipSeen() =>
    AppPrefs.setString(lightingTipSeenKey, 'true');

class LightingTipCard extends StatelessWidget {
  const LightingTipCard({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  static const List<String> tips = <String>[
    'Use a daylight (neutral white) lamp in front of you, at about eye level.',
    'Close the blinds so window light does not mix with the lamp.',
    'Avoid harsh direct light and light from behind you.',
    'Keep the same lamp, distance and chin height every scan.',
  ];

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.textStructure;
    return Container(
      key: const ValueKey('lighting_tip'),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_incandescent_outlined, size: 18, color: ink),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Recommended lighting',
                  style: TextStyle(color: ink, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onDismiss,
              ),
            ],
          ),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('• $tip', style: const TextStyle(color: ink)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('lighting_tip_dismiss'),
              onPressed: onDismiss,
              child: const Text('Got it'),
            ),
          ),
        ],
      ),
    );
  }
}
