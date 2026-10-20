// Home empty state when there are no AI scans yet: what the first scan is
// for, three short tips (controlled scan, same light, same setup), and a
// button to start. Takes the place of the last-comparable-pair card.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'home_section_style.dart';

class HomeFirstScanCard extends StatelessWidget {
  const HomeFirstScanCard({super.key, required this.onStartScan});

  final VoidCallback onStartScan;

  static const String title = 'Start with your first scan';
  static const String intro =
      'Your first AI scan becomes your baseline. Later scans are compared '
      'with it.';
  static const List<({IconData icon, String text})> tips = [
    (
      icon: Icons.center_focus_strong_outlined,
      text: 'Choose Controlled scan. It is the most consistent for tracking.',
    ),
    (
      icon: Icons.light_mode_outlined,
      text:
          'Use the same light every time: one daylight lamp in front of you, '
          'blinds closed.',
    ),
    (
      icon: Icons.straighten_rounded,
      text: 'Keep the same distance and chin height, with bare, clean skin.',
    ),
  ];
  static const String followUp =
      'After a follow-up scan in the same light, your comparison and picks '
      'for your concerns appear here.';

  @override
  Widget build(BuildContext context) {
    const sage = Color(0xFF7A8B7B);
    return Container(
      key: const ValueKey('home_first_scan_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(title, style: homeSectionTitleStyle),
          const SizedBox(height: homeSectionTitleGap),
          Text(intro, style: homeSectionMessageStyle()),
          const SizedBox(height: 12),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(tip.icon, size: 18, color: sage),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tip.text,
                      style: const TextStyle(
                        color: AppColors.textStructure,
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
            child: FilledButton.icon(
              key: const ValueKey('home_first_scan_button'),
              onPressed: onStartScan,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Start a scan'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            followUp,
            style: homeSectionSubtleStyle().copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}
