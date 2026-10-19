import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/app_prefs.dart';
import '../utils/product_routine_builder.dart';

/// Edit the morning and evening routine by hand: a plain list of product
/// names per period, saved as the active routine (the same store the
/// photo/typed-list builder and the Routines screen use). No product
/// database and no recommendations.
class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({super.key, this.initialRoutine});

  /// The current active routine payload, if any.
  final Map<String, dynamic>? initialRoutine;

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  late final List<String> _morning = _steps('morningSteps');
  late final List<String> _evening = _steps('eveningSteps');
  final _morningInput = TextEditingController();
  final _eveningInput = TextEditingController();
  late final _notes = TextEditingController(
    text: widget.initialRoutine?['notes']?.toString() ?? '',
  );

  List<String> _steps(String key) {
    final raw = widget.initialRoutine?[key];
    if (raw is! List) return <String>[];
    return raw
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  @override
  void dispose() {
    _morningInput.dispose();
    _eveningInput.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _add(List<String> steps, TextEditingController input) {
    final text = input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (!steps.contains(text)) steps.add(text);
      input.clear();
    });
  }

  Future<void> _save() async {
    final previous = widget.initialRoutine ?? const <String, dynamic>{};
    final payload = <String, dynamic>{
      // Keep fields this editor doesn't manage (e.g. detected products,
      // routine notes).
      ...previous,
      ...activeAiRoutinePayload(
        morningSteps: List<String>.of(_morning),
        eveningSteps: List<String>.of(_evening),
        detectedProducts: [
          for (final item in (previous['detectedProducts'] as List? ?? []))
            item.toString(),
        ],
        source: 'manual',
      ),
    };
    // Free-text product notes kept with the routine (profile-level); empty
    // notes are not stored.
    final notes = _notes.text.trim();
    if (notes.isEmpty) {
      payload.remove('notes');
    } else {
      payload['notes'] = notes;
    }
    await AppPrefs.saveActiveAiRoutine(payload);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _section({
    required String title,
    required String period,
    required List<String> steps,
    required TextEditingController input,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: AppColors.refinedSlate,
          ),
        ),
        const SizedBox(height: 6),
        if (steps.isEmpty)
          const Text('No products yet')
        else
          for (var i = 0; i < steps.length; i++)
            ListTile(
              key: ValueKey('routine_${period}_item_$i'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text('${i + 1}.'),
              title: Text(steps[i]),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => steps.removeAt(i)),
              ),
            ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: ValueKey('routine_${period}_input'),
                controller: input,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Add a product',
                  isDense: true,
                ),
                onSubmitted: (_) => _add(steps, input),
              ),
            ),
            IconButton(
              key: ValueKey('routine_${period}_add'),
              tooltip: 'Add',
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => _add(steps, input),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit routine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _section(
            title: 'Morning',
            period: 'morning',
            steps: _morning,
            input: _morningInput,
          ),
          const SizedBox(height: 20),
          _section(
            title: 'Evening',
            period: 'evening',
            steps: _evening,
            input: _eveningInput,
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('routine_notes'),
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Product notes',
              hintText:
                  'Optional: products you use, when you started, '
                  'anything you noticed',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('routine_save'),
            onPressed: _save,
            child: const Text('Save routine'),
          ),
        ],
      ),
    );
  }
}
