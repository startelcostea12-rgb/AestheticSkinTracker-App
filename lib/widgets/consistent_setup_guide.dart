// "Consistent Setup": five short points for taking comparable scans. Shown
// automatically the first time a face scan is started (scans start on the
// Front pose) and reopenable from the Skin Scan ⋮ menu. Display only: no
// metric, formula, threshold or lock is affected.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/app_prefs.dart';

/// AppPrefs flag: 'true' once the user has dismissed the guide.
const String consistentSetupGuideSeenKey = 'consistent_setup_guide_seen';

const String consistentSetupGuideTitle = 'Consistent Setup';

const String consistentSetupGuideIntro =
    'Colour readings like redness shift with light. Keep these the same '
    'every scan so changes you see are real:';

const List<({IconData icon, String text})> consistentSetupPoints = [
  (
    icon: Icons.crop_square_rounded,
    text: 'Hold the gray card in view on every scan.',
  ),
  (
    icon: Icons.light_mode_outlined,
    text:
        'Use the same daylight lamp (5000–6500K) in front of you at eye '
        'level, with the blinds closed.',
  ),
  (
    icon: Icons.straighten_rounded,
    text: 'Keep the same distance from the camera and the same chin height.',
  ),
  (icon: Icons.schedule_rounded, text: 'Scan at about the same time of day.'),
  (
    icon: Icons.face_retouching_natural_outlined,
    text: 'Bare, clean skin, hair back, and hold still until capture ends.',
  ),
];

Future<bool> shouldShowConsistentSetupGuide() async =>
    await AppPrefs.getString(consistentSetupGuideSeenKey) != 'true';

Future<void> markConsistentSetupGuideSeen() =>
    AppPrefs.setString(consistentSetupGuideSeenKey, 'true');

/// Opens the guide as a bottom sheet. Closing it (Got it, swipe or tap
/// outside) marks it seen, so it is not shown automatically again.
Future<void> showConsistentSetupGuide(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const ConsistentSetupGuideSheet(),
  );
  await markConsistentSetupGuideSeen();
}

/// Shows the guide only if the user has not seen it yet.
Future<void> showConsistentSetupGuideIfFirstTime(BuildContext context) async {
  if (!await shouldShowConsistentSetupGuide()) return;
  if (!context.mounted) return;
  await showConsistentSetupGuide(context);
}

class ConsistentSetupGuideSheet extends StatelessWidget {
  const ConsistentSetupGuideSheet({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.textStructure;
    const sage = Color(0xFF7A8B7B);
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('consistent_setup_guide'),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              consistentSetupGuideTitle,
              style: TextStyle(
                color: ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              consistentSetupGuideIntro,
              style: TextStyle(
                color: ink.withValues(alpha: 0.75),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            for (final (index, point) in consistentSetupPoints.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: sage.withValues(alpha: 0.15),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: sage,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(point.icon, size: 18, color: sage),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        point.text,
                        style: const TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const ValueKey('consistent_setup_guide_got_it'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
