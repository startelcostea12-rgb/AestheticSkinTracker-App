// lib/widgets/from_your_logs.dart
//
// The "From your logs" block: context notes built by RecommendationContext
// from what the user already stored. Shown on the home recommendation card,
// product detail, and the routine screen. Renders nothing when there are no
// notes.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/recommendation_context.dart';
import '../utils/upload_gate.dart';

class FromYourLogsBlock extends StatelessWidget {
  const FromYourLogsBlock({
    super.key,
    required this.notes,
    this.margin = const EdgeInsets.fromLTRB(14, 8, 14, 0),
  });

  final List<String> notes;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('recommendations_context_notes'),
      margin: margin,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.brandAccent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.history_edu_outlined,
                size: 15,
                color: AppColors.brandAccent,
              ),
              SizedBox(width: 6),
              Text(
                'From your logs',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textStructure,
                ),
              ),
            ],
          ),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                note,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textStructure,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loads the stored inputs and shows the notes about any of [relevantTo]
/// (product names, ingredients, routine steps). Shows nothing while loading,
/// when no note is relevant, or once a free user has used every free local
/// scan (FreeLocalScans.localNotesAvailable).
class FromYourLogsSection extends StatefulWidget {
  const FromYourLogsSection({
    super.key,
    required this.relevantTo,
    this.margin = EdgeInsets.zero,
    this.loadInputs = RecommendationContextInputs.load,
  });

  final List<String> relevantTo;
  final EdgeInsetsGeometry margin;
  final Future<RecommendationContextInputs> Function() loadInputs;

  @override
  State<FromYourLogsSection> createState() => _FromYourLogsSectionState();
}

class _FromYourLogsSectionState extends State<FromYourLogsSection> {
  List<ContextNote> _notes = const <ContextNote>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!await FreeLocalScans.localNotesAvailable()) return;
      final inputs = await widget.loadInputs();
      if (!mounted) return;
      setState(() => _notes = RecommendationContext.contextNotes(inputs));
    } catch (_) {
      // Missing or unreadable data shows nothing.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FromYourLogsBlock(
      notes: RecommendationContext.relevantTo(_notes, widget.relevantTo),
      margin: widget.margin,
    );
  }
}
