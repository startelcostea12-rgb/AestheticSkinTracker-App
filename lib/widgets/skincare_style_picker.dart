// Multi-select chips for "What type of skincare do you prefer?", used in
// onboarding and in Settings.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/skincare_style_catalog.dart';

class SkincareStylePicker extends StatelessWidget {
  const SkincareStylePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<SkincareStyle> selected;
  final ValueChanged<Set<SkincareStyle>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final style in SkincareStyle.values)
          FilterChip(
            key: ValueKey('style_chip_${style.id}'),
            label: Text(style.label),
            selected: selected.contains(style),
            selectedColor: AppColors.brandAccent.withValues(alpha: 0.22),
            onSelected: (on) {
              final next = Set<SkincareStyle>.of(selected);
              on ? next.add(style) : next.remove(style);
              onChanged(next);
            },
          ),
      ],
    );
  }
}

/// Settings row showing the saved styles; tapping opens the picker.
class SkincareStyleSettingsTile extends StatefulWidget {
  const SkincareStyleSettingsTile({super.key});

  @override
  State<SkincareStyleSettingsTile> createState() =>
      _SkincareStyleSettingsTileState();
}

class _SkincareStyleSettingsTileState extends State<SkincareStyleSettingsTile> {
  Set<SkincareStyle> _styles = const {};

  @override
  void initState() {
    super.initState();
    loadSkincareStyles().then((styles) {
      if (mounted) setState(() => _styles = styles);
    });
  }

  Future<void> _edit() async {
    var draft = Set<SkincareStyle>.of(_styles);
    final saved = await showModalBottomSheet<Set<SkincareStyle>>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  skincareStyleQuestion,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 12),
                SkincareStylePicker(
                  selected: draft,
                  onChanged: (next) => setSheetState(() => draft = next),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const ValueKey('style_settings_save'),
                    onPressed: () => Navigator.of(sheetContext).pop(draft),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == null) return;
    await saveSkincareStyles(saved);
    if (mounted) setState(() => _styles = saved);
  }

  @override
  Widget build(BuildContext context) {
    final summary = _styles.isEmpty
        ? 'Not set'
        : [
            for (final style in SkincareStyle.values)
              if (_styles.contains(style)) style.label,
          ].join(', ');
    return ListTile(
      key: const ValueKey('settings_skincare_style'),
      leading: const Icon(Icons.spa_outlined),
      title: const Text(
        'Skincare style',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(summary),
      trailing: const Icon(Icons.chevron_right),
      onTap: _edit,
    );
  }
}
