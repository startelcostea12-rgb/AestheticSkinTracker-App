// lib/widgets/makeup_disclosure_dialog.dart
//
// Clinical pre-scan disclosure surfaced before the camera initializes. The
// patient is asked whether their face is clean of makeup, sunscreen and
// active skincare products — anything that occludes the skin surface and
// reduces analysis accuracy.
//
// Returns:
//   `false` → face is clean, proceed with full clinical-accuracy capture.
//   `true`  → makeup acknowledged, scan will be flagged `makeupPresent: true`.
//   `null`  → user dismissed without choosing (callers should abort and pop).

import 'package:flutter/material.dart';

import '../app_theme.dart';

class MakeupDisclosureDialog {
  /// Presents the disclosure modal. Non-dismissible on tap-outside; the only
  /// exits are Cancel, "Face is clean", or "Wearing makeup".
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _MakeupDisclosureBody(),
    );
  }
}

class _MakeupDisclosureBody extends StatelessWidget {
  const _MakeupDisclosureBody();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: MyApp.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: MyApp.clinicalTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.face_retouching_natural,
                      color: MyApp.clinicalNavy,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pre-scan check',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: MyApp.clinicalMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Clean skin for accurate analysis',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: MyApp.textBrown,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Body / clinical guidance ──────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: MyApp.clinicalNavy.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: MyApp.clinicalNavy.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'For the most accurate skin analysis, please remove all '
                      'makeup, sunscreen, and skincare products before scanning.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: MyApp.textBrown,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _bullet(
                      'Makeup obscures erythema, pigmentation, and pore signals.',
                    ),
                    _bullet(
                      'Sunscreen can flatten texture and lighten apparent tone.',
                    ),
                    _bullet(
                      'Recently-applied serums temporarily alter surface reflectivity.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Primary action — clean face ───────────────────────────
              _PrimaryActionTile(
                icon: Icons.verified_outlined,
                title: 'Face is clean',
                subtitle: 'Continue with a full high-consistency scan.',
                accent: MyApp.clinicalTeal,
                onTap: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 10),

              // ── Secondary action — makeup acknowledged ────────────────
              _PrimaryActionTile(
                icon: Icons.warning_amber_rounded,
                title: 'Wearing makeup — scan anyway',
                subtitle: 'Scan will be flagged; accuracy reduced for trends.',
                accent: MyApp.roseGold,
                onTap: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 6),

              // ── Cancel ────────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: MyApp.clinicalMuted,
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: MyApp.clinicalMuted.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: MyApp.textBrown.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionTile extends StatelessWidget {
  const _PrimaryActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Icon(icon, color: accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: MyApp.textBrown,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: MyApp.textBrown.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: accent.withValues(alpha: 0.85),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
