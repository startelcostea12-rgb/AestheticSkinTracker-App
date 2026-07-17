import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/procedure.dart';

class RecoveryMilestone {
  const RecoveryMilestone({
    required this.label,
    required this.description,
    required this.dayOffset,
  });

  final String label;
  final String description;
  final int dayOffset;
}

enum RecoveryMilestoneState { passed, current, upcoming }

class RecoveryTimelineCard extends StatelessWidget {
  const RecoveryTimelineCard({
    super.key,
    required this.procedureType,
    required this.startDate,
    this.timelineMilestones = const [],
    this.onMilestoneTap,
    this.onAddMilestone,
  });

  final String procedureType;
  final DateTime startDate;
  final List<ProcedureTimelineMilestone> timelineMilestones;
  final ValueChanged<ProcedureTimelineMilestone>? onMilestoneTap;
  final VoidCallback? onAddMilestone;

  static const Map<String, List<RecoveryMilestone>> _procedureMilestones = {
    'Hair Transplant': [
      RecoveryMilestone(
        label: 'Day 1-3',
        description:
            'Scalp tenderness, tightness, and mild swelling are common while grafts are still delicate and must be protected carefully.',
        dayOffset: 3,
      ),
      RecoveryMilestone(
        label: 'Day 7-10',
        description:
            'Scabbing usually sheds during this period and many clinics clear patients to resume gentle scalp washing techniques.',
        dayOffset: 10,
      ),
      RecoveryMilestone(
        label: 'Week 2-4',
        description:
            'Most visible healing settles down, though temporary shedding of transplanted hairs can begin as follicles cycle.',
        dayOffset: 28,
      ),
      RecoveryMilestone(
        label: 'Month 3-4',
        description:
            'Early regrowth often starts to become visible, though density is still patchy and immature.',
        dayOffset: 120,
      ),
      RecoveryMilestone(
        label: 'Month 6-9',
        description:
            'Noticeable thickening and coverage improvements are common as more grafts enter active growth.',
        dayOffset: 270,
      ),
      RecoveryMilestone(
        label: 'Month 12',
        description:
            'Final results are usually judged around one year when growth, texture, and density have matured more fully.',
        dayOffset: 365,
      ),
    ],
    'Rhinoplasty': [
      RecoveryMilestone(
        label: 'Day 1-3',
        description:
            'Initial swelling and bruising are usually most noticeable. Elevation, icing, and rest are especially important.',
        dayOffset: 3,
      ),
      RecoveryMilestone(
        label: 'Day 7-10',
        description:
            'Stitches, splint, or external dressings are often removed around this window, depending on your surgeon.',
        dayOffset: 10,
      ),
      RecoveryMilestone(
        label: 'Week 2-3',
        description:
            'Most bruising typically fades and social downtime becomes easier for many patients.',
        dayOffset: 21,
      ),
      RecoveryMilestone(
        label: 'Month 1',
        description:
            'Around 50-60% of the visible result is often apparent, though tip swelling may still linger.',
        dayOffset: 30,
      ),
      RecoveryMilestone(
        label: 'Month 3',
        description:
            'About 70-80% of the contour change is usually visible as swelling continues to settle.',
        dayOffset: 90,
      ),
      RecoveryMilestone(
        label: 'Month 12',
        description:
            'Final result is typically visible once the nose has fully refined and matured.',
        dayOffset: 365,
      ),
    ],
    'Facelift': [
      RecoveryMilestone(
        label: 'Day 1-3',
        description:
            'Initial swelling, tightness, and bruising are expected while tissues begin settling into their new position.',
        dayOffset: 3,
      ),
      RecoveryMilestone(
        label: 'Day 7-10',
        description:
            'Stitches are commonly removed during this window and bruising often begins to soften noticeably.',
        dayOffset: 10,
      ),
      RecoveryMilestone(
        label: 'Week 2-3',
        description:
            'Most bruising fades and many patients feel comfortable resuming more social activities.',
        dayOffset: 21,
      ),
      RecoveryMilestone(
        label: 'Month 1',
        description:
            'About 50-60% of the refreshed result is usually visible, with residual swelling still improving.',
        dayOffset: 30,
      ),
      RecoveryMilestone(
        label: 'Month 3',
        description:
            'Roughly 70-80% of the final contour is often visible as incisions and tissues continue to mature.',
        dayOffset: 90,
      ),
      RecoveryMilestone(
        label: 'Month 12',
        description:
            'Final result is generally appreciated once scar maturation and deep tissue settling are complete.',
        dayOffset: 365,
      ),
    ],
    'Blepharoplasty': [
      RecoveryMilestone(
        label: 'Day 1-3',
        description:
            'Swelling, bruising, and tightness around the eyes are expected early in recovery.',
        dayOffset: 3,
      ),
      RecoveryMilestone(
        label: 'Day 7-10',
        description:
            'Stitches are usually removed in this phase and eyelid comfort often improves quickly after.',
        dayOffset: 10,
      ),
      RecoveryMilestone(
        label: 'Week 2-3',
        description:
            'Most bruising fades and the eye area begins to look more naturally rested.',
        dayOffset: 21,
      ),
      RecoveryMilestone(
        label: 'Month 1',
        description:
            'About 50-60% of the refreshed upper or lower lid result is commonly visible.',
        dayOffset: 30,
      ),
      RecoveryMilestone(
        label: 'Month 3',
        description:
            'Around 70-80% of the final outcome is often visible as swelling continues to resolve.',
        dayOffset: 90,
      ),
      RecoveryMilestone(
        label: 'Month 12',
        description:
            'Final eyelid contour and scar maturation are typically reached by this stage.',
        dayOffset: 365,
      ),
    ],
  };

  static const List<RecoveryMilestone> _injectableMilestones = [
    RecoveryMilestone(
      label: 'Day 1-3',
      description:
          'Swelling, injection-site tenderness, and minor bruising are most common during the first few days.',
      dayOffset: 3,
    ),
    RecoveryMilestone(
      label: 'Week 1',
      description:
          'Most visible bruising fades and early cosmetic changes are easier to assess.',
      dayOffset: 7,
    ),
    RecoveryMilestone(
      label: 'Week 2',
      description:
          'Results usually settle into a more natural look by this stage for many injectable treatments.',
      dayOffset: 14,
    ),
    RecoveryMilestone(
      label: 'Month 1',
      description:
          'Refinement and symmetry are easier to evaluate once residual swelling fully resolves.',
      dayOffset: 30,
    ),
  ];

  static const List<RecoveryMilestone> _energyDeviceMilestones = [
    RecoveryMilestone(
      label: 'Day 1-3',
      description:
          'Initial redness, warmth, and mild swelling are common after resurfacing or collagen-stimulating treatments.',
      dayOffset: 3,
    ),
    RecoveryMilestone(
      label: 'Day 7-10',
      description:
          'Peeling, dryness, or micro-crusting typically subsides and skin tone starts evening out.',
      dayOffset: 10,
    ),
    RecoveryMilestone(
      label: 'Week 2-3',
      description:
          'Most visible recovery settles and smoother texture becomes easier to appreciate.',
      dayOffset: 21,
    ),
    RecoveryMilestone(
      label: 'Month 1',
      description:
          'Early collagen remodeling is often visible, with about half of the expected refinement apparent.',
      dayOffset: 30,
    ),
    RecoveryMilestone(
      label: 'Month 3',
      description:
          'Collagen stimulation usually becomes more evident and 70-80% of the result may be visible.',
      dayOffset: 90,
    ),
  ];

  static const List<RecoveryMilestone> _genericMilestones = [
    RecoveryMilestone(
      label: 'Day 1-3',
      description:
          'Initial swelling, redness, or bruising are expected while the treatment area begins healing.',
      dayOffset: 3,
    ),
    RecoveryMilestone(
      label: 'Week 1',
      description:
          'Most early downtime fades and aftercare routines become easier to maintain consistently.',
      dayOffset: 7,
    ),
    RecoveryMilestone(
      label: 'Week 2-3',
      description:
          'Visible recovery improves and the treatment area typically looks calmer and more settled.',
      dayOffset: 21,
    ),
    RecoveryMilestone(
      label: 'Month 1',
      description:
          'About 50-60% of the intended improvement is often easier to appreciate by this stage.',
      dayOffset: 30,
    ),
    RecoveryMilestone(
      label: 'Month 3',
      description:
          'Around 70-80% of the final result may be visible as tissue remodeling continues.',
      dayOffset: 90,
    ),
  ];

  static const Set<String> _injectableProcedureTypes = {
    'Botox / Dysport / Xeomin',
    'Dermal Fillers',
    'Lip Augmentation',
    'Thread Lift',
  };

  static const Set<String> _energyProcedureTypes = {
    'Microneedling',
    'RF Microneedling',
    'Halo Laser',
    'Fractional Laser',
    'CO2 Laser Resurfacing',
    'IPL',
    'Chemical Peel',
    'Morpheus8',
  };

  static List<ProcedureTimelineMilestone> defaultTimelineMilestonesFor(
    String procedureType,
    DateTime startDate,
  ) {
    final card = RecoveryTimelineCard(
      procedureType: procedureType,
      startDate: startDate,
    );
    final canonicalType = canonicalProcedureType(procedureType);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    return card._milestonesFor(procedureType).asMap().entries.map((entry) {
      final milestone = entry.value;
      final expectedDate = start.add(Duration(days: milestone.dayOffset));
      return ProcedureTimelineMilestone(
        id: '${canonicalType}_${milestone.label}_${milestone.dayOffset}',
        label: milestone.label,
        description: milestone.description,
        expectedDate: expectedDate,
        displayOrder: entry.key,
      );
    }).toList();
  }

  List<RecoveryMilestone> _milestonesFor(String type) {
    final canonicalType = canonicalProcedureType(type);
    if (_procedureMilestones.containsKey(canonicalType)) {
      return _procedureMilestones[canonicalType]!;
    }
    if (_injectableProcedureTypes.contains(canonicalType)) {
      return _injectableMilestones;
    }
    if (_energyProcedureTypes.contains(canonicalType)) {
      return _energyDeviceMilestones;
    }
    return _genericMilestones;
  }

  List<ProcedureTimelineMilestone> _resolvedMilestones() {
    final items = timelineMilestones.isNotEmpty
        ? List<ProcedureTimelineMilestone>.from(timelineMilestones)
        : defaultTimelineMilestonesFor(procedureType, startDate);
    items.sort((a, b) {
      final orderCompare = a.displayOrder.compareTo(b.displayOrder);
      if (orderCompare != 0) return orderCompare;
      final dateCompare = a.expectedDate.compareTo(b.expectedDate);
      if (dateCompare != 0) return dateCompare;
      return a.id.compareTo(b.id);
    });
    return items;
  }

  List<ProcedureTimelineMilestone> _chronologicalMilestones(
    List<ProcedureTimelineMilestone> milestones,
  ) {
    final items = List<ProcedureTimelineMilestone>.from(milestones);
    items.sort((a, b) {
      final dateCompare = a.expectedDate.compareTo(b.expectedDate);
      if (dateCompare != 0) return dateCompare;
      final orderCompare = a.displayOrder.compareTo(b.displayOrder);
      if (orderCompare != 0) return orderCompare;
      return a.id.compareTo(b.id);
    });
    return items;
  }

  int _daysSinceStart() {
    final today = DateTime.now();
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final current = DateTime(today.year, today.month, today.day);
    final diff = current.difference(start).inDays;
    return diff < 0 ? 0 : diff;
  }

  RecoveryMilestoneState _stateForTimelineMilestone(
    List<ProcedureTimelineMilestone> milestones,
    int index,
    DateTime today,
  ) {
    final milestoneDate = DateTime(
      milestones[index].expectedDate.year,
      milestones[index].expectedDate.month,
      milestones[index].expectedDate.day,
    );
    if (!today.isBefore(milestoneDate)) {
      return RecoveryMilestoneState.passed;
    }

    final previousDate = index == 0
        ? DateTime(startDate.year, startDate.month, startDate.day)
        : DateTime(
            milestones[index - 1].expectedDate.year,
            milestones[index - 1].expectedDate.month,
            milestones[index - 1].expectedDate.day,
          );
    if (!today.isBefore(previousDate)) {
      return RecoveryMilestoneState.current;
    }
    return RecoveryMilestoneState.upcoming;
  }

  ProcedureTimelineMilestone _currentTimelineMilestone(
    List<ProcedureTimelineMilestone> milestones,
    DateTime today,
  ) {
    for (var index = 0; index < milestones.length; index++) {
      if (_stateForTimelineMilestone(milestones, index, today) ==
          RecoveryMilestoneState.current) {
        return milestones[index];
      }
    }
    return milestones.last;
  }

  double _timelineProgressFromDates(
    List<ProcedureTimelineMilestone> milestones,
    DateTime today,
  ) {
    if (milestones.isEmpty) return 0;
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(
      milestones.last.expectedDate.year,
      milestones.last.expectedDate.month,
      milestones.last.expectedDate.day,
    );
    final total = end.difference(start).inDays;
    if (total <= 0) return 0;
    final elapsed = today.difference(start).inDays;
    return (elapsed / total).clamp(0, 1);
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Color _colorFor(RecoveryMilestoneState state) {
    switch (state) {
      case RecoveryMilestoneState.passed:
        return AppColors.mutedSage;
      case RecoveryMilestoneState.current:
        return AppColors.champagneGold;
      case RecoveryMilestoneState.upcoming:
        return AppColors.refinedSlate.withValues(alpha: 0.45);
    }
  }

  IconData _iconFor(RecoveryMilestoneState state) {
    switch (state) {
      case RecoveryMilestoneState.passed:
        return Icons.check_circle;
      case RecoveryMilestoneState.current:
        return Icons.radio_button_checked;
      case RecoveryMilestoneState.upcoming:
        return Icons.radio_button_unchecked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final milestones = _resolvedMilestones();
    final chronologicalMilestones = _chronologicalMilestones(milestones);
    final elapsedDays = _daysSinceStart();
    final today = DateTime.now();
    final currentMilestone = _currentTimelineMilestone(
      chronologicalMilestones,
      today,
    );
    final progress = _timelineProgressFromDates(chronologicalMilestones, today);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.20),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.canvas,
                    AppColors.champagneGold.withValues(alpha: 0.14),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.healing,
                          color: AppColors.champagneGold,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recovery Timeline',
                              style: MyApp.pageTitleStyle(),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$procedureType · Day $elapsedDays',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.refinedSlate.withValues(
                                  alpha: 0.68,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _formatDate(currentMilestone.expectedDate),
                          style: const TextStyle(
                            color: AppColors.refinedSlate,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 9,
                      backgroundColor: Colors.white.withValues(alpha: 0.72),
                      color: AppColors.champagneGold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Current phase: ${currentMilestone.label} · ${currentMilestone.description}',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: AppColors.refinedSlate.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ...List.generate(milestones.length, (index) {
              final milestone = milestones[index];
              final chronologicalIndex = chronologicalMilestones.indexWhere(
                (item) => item.id == milestone.id,
              );
              final state = _stateForTimelineMilestone(
                chronologicalMilestones,
                chronologicalIndex,
                today,
              );
              final color = _colorFor(state);
              final isLast = index == milestones.length - 1;
              return _timelineRow(
                milestone: milestone,
                state: state,
                color: color,
                isLast: isLast,
              );
            }),
            if (onAddMilestone != null) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onAddMilestone,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Custom Milestone'),
                  style: MyApp.primaryGoldButton,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                'These milestone ranges are educational estimates. Continue following your surgeon or provider’s aftercare instructions for your own recovery timeline.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.refinedSlate.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timelineRow({
    required ProcedureTimelineMilestone milestone,
    required RecoveryMilestoneState state,
    required Color color,
    required bool isLast,
  }) {
    final isCurrent = state == RecoveryMilestoneState.current;
    final rowContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.champagneGold.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: isCurrent
            ? Border.all(color: AppColors.champagneGold.withValues(alpha: 0.28))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(_iconFor(state), size: 18, color: color),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 58,
                    margin: const EdgeInsets.only(top: 4),
                    color: color.withValues(alpha: 0.35),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        milestone.label,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: color.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        _formatDate(milestone.expectedDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.refinedSlate.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  milestone.description,
                  style: const TextStyle(
                    color: AppColors.refinedSlate,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                if (onMilestoneTap != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Tap to edit date',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.refinedSlate.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: onMilestoneTap == null
          ? rowContent
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onMilestoneTap!(milestone),
                borderRadius: BorderRadius.circular(14),
                child: rowContent,
              ),
            ),
    );
  }
}
