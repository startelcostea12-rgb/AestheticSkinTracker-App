// Home card: the saved morning and evening routine (product names only).

import 'package:flutter/material.dart';

import '../app_theme.dart';

class HomeRoutineCard extends StatelessWidget {
  const HomeRoutineCard({super.key, required this.routine, this.onOpen});

  final Map<String, dynamic> routine;
  final VoidCallback? onOpen;

  static List<String> stepsOf(Map<String, dynamic> routine, String key) {
    final raw = routine[key];
    if (raw is! List) return const <String>[];
    return [
      for (final item in raw)
        if ((item?.toString().trim() ?? '').isNotEmpty) item.toString().trim(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.textStructure;
    Widget period(String title, List<String> steps) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: ink, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        if (steps.isEmpty)
          Text('—', style: TextStyle(color: ink.withValues(alpha: 0.6)))
        else
          for (final step in steps)
            Text(
              step,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ink),
            ),
      ],
    );
    return Container(
      key: const ValueKey('home_routine_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'My routine',
                  style: TextStyle(
                    color: ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (onOpen != null)
                TextButton(onPressed: onOpen, child: const Text('Open')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: period('Morning', stepsOf(routine, 'morningSteps')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: period('Evening', stepsOf(routine, 'eveningSteps')),
              ),
            ],
          ),
          if ((routine['notes']?.toString().trim() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Notes: ${routine['notes'].toString().trim()}',
              key: const ValueKey('home_routine_notes'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink.withValues(alpha: 0.8),
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
