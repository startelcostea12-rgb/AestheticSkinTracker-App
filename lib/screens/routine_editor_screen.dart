import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/app_prefs.dart';
import '../utils/product_routine_builder.dart';
import '../utils/skincare_name_suggestions.dart';
import '../widgets/home_section_style.dart';

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
  final _morningFocus = FocusNode();
  final _eveningFocus = FocusNode();
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
    _morningFocus.dispose();
    _eveningFocus.dispose();
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

  static const Color _sage = Color(0xFF7A8B7B);

  BoxDecoration get _cardDecoration => BoxDecoration(
    color: AppColors.cardBackground,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: AppColors.borders),
  );

  Widget _section({
    required String title,
    required String period,
    required IconData icon,
    required List<String> steps,
    required TextEditingController input,
    required FocusNode focus,
  }) {
    final muted = AppColors.textStructure.withValues(alpha: 0.7);
    final count = steps.length;
    return Container(
      key: ValueKey('routine_${period}_section'),
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: _sage),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: homeSectionTitleStyle)),
              Text(
                count == 0 ? 'No steps' : '$count step${count == 1 ? '' : 's'}',
                style: TextStyle(
                  color: muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: homeSectionTitleGap),
          if (steps.isEmpty)
            Container(
              key: ValueKey('routine_${period}_empty'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.warmAlabaster,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borders),
              ),
              child: Text(
                'No ${title.toLowerCase()} products yet. Add your first one '
                'below.',
                style: homeSectionMessageStyle(),
              ),
            )
          else
            for (var i = 0; i < steps.length; i++)
              _stepTile(period: period, index: i, steps: steps),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _productNameField(
                  period: period,
                  title: title,
                  steps: steps,
                  input: input,
                  focus: focus,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: ValueKey('routine_${period}_add'),
                tooltip: 'Add',
                style: IconButton.styleFrom(
                  backgroundColor: _sage,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _add(steps, input),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The product-name field with suggestions from
  /// skincareNameSuggestionList as the user types. Picking one fills the
  /// field; anything else can still be typed and added.
  Widget _productNameField({
    required String period,
    required String title,
    required List<String> steps,
    required TextEditingController input,
    required FocusNode focus,
  }) {
    return RawAutocomplete<String>(
      textEditingController: input,
      focusNode: focus,
      optionsBuilder: (value) => skincareNameSuggestions(value.text),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
          TextField(
            key: ValueKey('routine_${period}_input'),
            controller: controller,
            focusNode: focusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Add a ${title.toLowerCase()} product',
              isDense: true,
              filled: true,
              fillColor: AppColors.warmAlabaster,
              prefixIcon: const Icon(Icons.edit_outlined, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (_) => _add(steps, input),
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          key: ValueKey('routine_${period}_suggestions'),
          elevation: 4,
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    key: ValueKey('routine_suggestion_$option'),
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepTile({
    required String period,
    required int index,
    required List<String> steps,
  }) {
    return Container(
      key: ValueKey('routine_${period}_item_$index'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.warmAlabaster,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borders),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: _sage.withValues(alpha: 0.15),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: _sage,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              steps[index],
              style: const TextStyle(
                color: AppColors.textStructure,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textStructure.withValues(alpha: 0.6),
            onPressed: () => setState(() => steps.removeAt(index)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: AppColors.warmAlabaster,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Edit routine',
          style: TextStyle(
            color: AppColors.refinedSlate,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.refinedSlate),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Add products in the order you use them. Tap × to remove one. '
            'Changes are saved when you tap Save routine.',
            key: const ValueKey('routine_editor_hint'),
            style: homeSectionMessageStyle(),
          ),
          const SizedBox(height: homeSectionGap),
          _section(
            title: 'Morning',
            period: 'morning',
            icon: Icons.wb_sunny_outlined,
            steps: _morning,
            input: _morningInput,
            focus: _morningFocus,
          ),
          const SizedBox(height: homeSectionGap),
          _section(
            title: 'Evening',
            period: 'evening',
            icon: Icons.nights_stay_outlined,
            steps: _evening,
            input: _eveningInput,
            focus: _eveningFocus,
          ),
          const SizedBox(height: homeSectionGap),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notes_rounded, size: 20, color: _sage),
                    SizedBox(width: 8),
                    Text('Product notes', style: homeSectionTitleStyle),
                  ],
                ),
                const SizedBox(height: homeSectionTitleGap),
                TextField(
                  key: const ValueKey('routine_notes'),
                  controller: _notes,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText:
                        'Optional: products you use, when you started, '
                        'anything you noticed',
                    filled: true,
                    fillColor: AppColors.warmAlabaster,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const ValueKey('routine_save'),
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save routine'),
            ),
          ),
        ],
      ),
    );
  }
}
