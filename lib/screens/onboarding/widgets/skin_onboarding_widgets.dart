import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/skin_profile.dart';

class OnboardingStepShell extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const OnboardingStepShell({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.champagneGold.withValues(alpha: 0.16),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.46),
              ),
            ),
            child: Icon(icon, color: AppColors.goldHover),
          ),
          const SizedBox(height: 18),
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: AppColors.goldHover,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.refinedSlate,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.refinedSlate.withValues(alpha: 0.68),
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              height: 1.42,
            ),
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class LuxeChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const LuxeChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.champagneGold.withValues(alpha: 0.20)
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.champagneGold
                  : AppColors.borders.withValues(alpha: 0.86),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.champagneGold.withValues(alpha: 0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 17,
                  color: selected ? AppColors.goldHover : AppColors.mutedSage,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.refinedSlate,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WelcomeSkinTypeStep extends StatelessWidget {
  /// Maximum number of skin types a user may select simultaneously.
  static const int maxSelection = 3;

  final Set<SkinType> selectedSkinTypes;
  final ValueChanged<SkinType> onToggle;

  const WelcomeSkinTypeStep({
    super.key,
    required this.selectedSkinTypes,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final count = selectedSkinTypes.length;
    final atMax = count >= maxSelection;

    return OnboardingStepShell(
      eyebrow: 'Step 1 of 7',
      title: 'Let\u2019s tailor your glow plan.',
      subtitle:
          'Select all that apply (up to $maxSelection) for better personalized recommendations.',
      icon: Icons.spa_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── selection counter ───────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: count == 0
                ? Text(
                    'Choose your skin type(s) below.',
                    key: const ValueKey('none'),
                    style: TextStyle(
                      color: AppColors.refinedSlate.withValues(alpha: 0.52),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Row(
                    key: ValueKey(count),
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.champagneGold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.champagneGold
                                .withValues(alpha: 0.52),
                          ),
                        ),
                        child: Text(
                          '$count of $maxSelection selected',
                          style: const TextStyle(
                            color: AppColors.goldHover,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      if (atMax) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Maximum reached',
                          style: TextStyle(
                            color: AppColors.refinedSlate.withValues(alpha: 0.45),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          // ── chips ───────────────────────────────────────────────────────
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: SkinType.values.map((type) {
              final selected = selectedSkinTypes.contains(type);
              final disabled = atMax && !selected;
              return _SkinTypeChip(
                type: type,
                selected: selected,
                disabled: disabled,
                onTap: disabled ? null : () => onToggle(type),
              );
            }).toList(),
          ),
          // ── inline descriptions for selected types ──────────────────────
          if (selectedSkinTypes.isNotEmpty) ...[
            const SizedBox(height: 20),
            ...selectedSkinTypes.map(
              (type) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _skinTypeIcon(type),
                      size: 15,
                      color: AppColors.goldHover,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${skinTypeLabel(type)}: ${_skinTypeDescription(type)}',
                        style: TextStyle(
                          color: AppColors.refinedSlate.withValues(alpha: 0.72),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Single skin-type chip with selected / disabled states.
class _SkinTypeChip extends StatelessWidget {
  final SkinType type;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _SkinTypeChip({
    required this.type,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.38 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.champagneGold.withValues(alpha: 0.20)
                  : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? AppColors.champagneGold
                    : AppColors.borders.withValues(alpha: 0.86),
                width: selected ? 1.4 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.champagneGold.withValues(alpha: 0.16),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _skinTypeIcon(type),
                  size: 17,
                  color: selected ? AppColors.goldHover : AppColors.mutedSage,
                ),
                const SizedBox(width: 8),
                Text(
                  skinTypeLabel(type),
                  style: TextStyle(
                    color: AppColors.refinedSlate,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: AppColors.goldHover,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _skinTypeDescription(SkinType type) => switch (type) {
      SkinType.dry => 'Tight, flaky, prone to dehydration and fine lines.',
      SkinType.oily => 'Shine-prone, enlarged pores, breakout-friendly.',
      SkinType.combination => 'Oily T-zone with dry or normal cheeks.',
      SkinType.normal => 'Balanced with few blemishes and minimal concerns.',
      SkinType.sensitive => 'Reactive, easily irritated, prone to redness.',
    };

class SensitivityStep extends StatelessWidget {
  final SensitivityLevel? selectedLevel;
  final ValueChanged<SensitivityLevel> onChanged;

  const SensitivityStep({
    super.key,
    required this.selectedLevel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      eyebrow: 'Step 2 of 7',
      title: 'How reactive is your skin?',
      subtitle:
          'Sensitivity changes how quickly the app suggests actives, procedures, and recovery routines.',
      icon: Icons.favorite_rounded,
      child: Column(
        children: SensitivityLevel.values
            .map(
              (level) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SelectionTile(
                  title: sensitivityLevelLabel(level),
                  subtitle: sensitivityLevelDescription(level),
                  selected: selectedLevel == level,
                  onTap: () => onChanged(level),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class MainConcernsStep extends StatelessWidget {
  final Set<String> selectedConcerns;
  final ValueChanged<String> onToggle;

  const MainConcernsStep({
    super.key,
    required this.selectedConcerns,
    required this.onToggle,
  });

  static const concerns = [
    'Redness',
    'Texture',
    'Acne',
    'Pigmentation',
    'Scars',
    'Dryness',
    'Aging',
    'Pores',
    'Sensitivity',
    'Dullness',
    'Uneven Tone',
    'Post-Procedure Recovery',
  ];

  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      eyebrow: 'Step 3 of 7',
      title: 'Choose your top concerns.',
      subtitle:
          'Select every concern that matters. You can refine this later as your skin changes.',
      icon: Icons.auto_awesome_rounded,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: concerns
            .map(
              (concern) => LuxeChoiceChip(
                label: concern,
                selected: selectedConcerns.contains(concern),
                onTap: () => onToggle(concern),
              ),
            )
            .toList(),
      ),
    );
  }
}

class CurrentRoutineStep extends StatelessWidget {
  /// Maximum product preferences a user may select simultaneously.
  static const int maxPreferenceSelection = 3;

  final Map<String, Set<String>> routine;
  final ValueChanged<String> onAddProduct;
  final void Function(String section, String product) onRemoveProduct;
  final TextEditingController productController;
  final Set<String> selectedPreferences;
  final TextEditingController otherPreferenceController;
  final TextEditingController favoriteIngredientController;
  final TextEditingController ingredientToAvoidController;
  final Set<String> favoriteIngredients;
  final Set<String> ingredientsToAvoid;
  final ValueChanged<String> onPreferenceToggle;
  final ValueChanged<String> onAddFavoriteIngredient;
  final ValueChanged<String> onRemoveFavoriteIngredient;
  final ValueChanged<String> onAddIngredientToAvoid;
  final ValueChanged<String> onRemoveIngredientToAvoid;

  const CurrentRoutineStep({
    super.key,
    required this.routine,
    required this.onAddProduct,
    required this.onRemoveProduct,
    required this.productController,
    required this.selectedPreferences,
    required this.otherPreferenceController,
    required this.favoriteIngredientController,
    required this.ingredientToAvoidController,
    required this.favoriteIngredients,
    required this.ingredientsToAvoid,
    required this.onPreferenceToggle,
    required this.onAddFavoriteIngredient,
    required this.onRemoveFavoriteIngredient,
    required this.onAddIngredientToAvoid,
    required this.onRemoveIngredientToAvoid,
  });



  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      eyebrow: 'Step 7 of 7',
      title: 'What’s in your routine now?',
      subtitle:
          'Finish with products, preferences, favorite ingredients, and anything your coach should avoid recommending.',
      icon: Icons.local_florist_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Current routine'),
          const SizedBox(height: 8),
          _TextEntryRow(
            controller: productController,
            hintText: 'Add product or step',
            buttonLabel: 'Add',
            onSubmit: () => onAddProduct(productController.text),
          ),
          const SizedBox(height: 18),
          for (final section in routine.keys) ...[
            _SectionLabel(section),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final product in routine[section] ?? const <String>{})
                  InputChip(
                    label: Text(product),
                    onDeleted: () => onRemoveProduct(section, product),
                    backgroundColor: AppColors.champagneGold.withValues(
                      alpha: 0.12,
                    ),
                    side: BorderSide(
                      color: AppColors.champagneGold.withValues(alpha: 0.30),
                    ),
                  ),
                if ((routine[section] ?? const <String>{}).isEmpty)
                  Text(
                    'No $section steps added yet.',
                    style: TextStyle(
                      color: AppColors.refinedSlate.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 6),
          const _SectionLabel('Product preference'),
          const SizedBox(height: 10),
          _ProductPreferenceSection(
            selectedPreferences: selectedPreferences,
            onPreferenceToggle: onPreferenceToggle,
            otherPreferenceController: otherPreferenceController,
          ),
          const SizedBox(height: 22),
          const _SectionLabel('Favorite ingredients'),
          const SizedBox(height: 8),
          _TextEntryRow(
            controller: favoriteIngredientController,
            hintText: 'e.g. ceramides, niacinamide, snail mucin',
            buttonLabel: 'Add',
            onSubmit: () =>
                onAddFavoriteIngredient(favoriteIngredientController.text),
          ),
          const SizedBox(height: 10),
          _IngredientChips(
            ingredients: favoriteIngredients,
            emptyText: 'No favorite ingredients added yet.',
            onDeleted: onRemoveFavoriteIngredient,
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Ingredients to avoid'),
          const SizedBox(height: 8),
          _TextEntryRow(
            controller: ingredientToAvoidController,
            hintText: 'e.g. fragrance, retinoids, benzoyl peroxide',
            buttonLabel: 'Add',
            onSubmit: () =>
                onAddIngredientToAvoid(ingredientToAvoidController.text),
          ),
          const SizedBox(height: 10),
          _IngredientChips(
            ingredients: ingredientsToAvoid,
            emptyText: 'No ingredients to avoid added yet.',
            onDeleted: onRemoveIngredientToAvoid,
          ),
        ],
      ),
    );
  }
}

/// Displays product preference multi-select with counter badge and special "Other" handling.
class _ProductPreferenceSection extends StatelessWidget {
  static const maxSelection = 3;
  
  static const List<String> preferenceLabels = [
    'Korean (K-beauty)',
    'Natural / Organic',
    'Western / Pharmacy',
    'Clean Beauty',
    'Luxury / Medical-grade',
    'Mixed',
    'Other',
  ];
  
  static const List<String> preferenceValues = [
    'korean',
    'natural',
    'western',
    'clean_beauty',
    'luxury',
    'mixed',
    'other',
  ];

  final Set<String> selectedPreferences;
  final ValueChanged<String> onPreferenceToggle;
  final TextEditingController otherPreferenceController;

  const _ProductPreferenceSection({
    required this.selectedPreferences,
    required this.onPreferenceToggle,
    required this.otherPreferenceController,
  });

  @override
  Widget build(BuildContext context) {
    final isFull = selectedPreferences.length >= maxSelection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hint text
        Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: Text(
            'Select all that apply (up to 3) — many people mix categories.',
            style: TextStyle(
              color: AppColors.refinedSlate.withValues(alpha: 0.70),
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        // Counter badge
        SizedBox(
          height: 32,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              selectedPreferences.length >= maxSelection
                  ? 'Maximum reached'
                  : '${selectedPreferences.length} of $maxSelection selected',
              key: ValueKey('${selectedPreferences.length}'),
              style: const TextStyle(
                color: AppColors.champagneGold,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Preference chips
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (int i = 0; i < preferenceValues.length; i++)
              _ProductPrefChip(
                label: preferenceLabels[i],
                value: preferenceValues[i],
                selected: selectedPreferences.contains(preferenceValues[i]),
                disabled: isFull && !selectedPreferences.contains(preferenceValues[i]),
                onTap: () => onPreferenceToggle(preferenceValues[i]),
              ),
          ],
        ),
        // "Other" text field (shown only when selected)
        if (selectedPreferences.contains('other')) ...[
          const SizedBox(height: 14),
          TextField(
            controller: otherPreferenceController,
            decoration: _inputDecoration('Tell us your preferred style'),
          ),
        ],
      ],
    );
  }
}

/// FilterChip variant for product preference selection with disabled/dimmed state.
class _ProductPrefChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _ProductPrefChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.38 : 1.0,
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: disabled ? null : (_) => onTap(),
        backgroundColor: selected
            ? AppColors.champagneGold.withValues(alpha: 0.20)
            : AppColors.refinedSlate.withValues(alpha: 0.08),
        side: BorderSide(
          color: selected
              ? AppColors.champagneGold.withValues(alpha: 0.50)
              : AppColors.refinedSlate.withValues(alpha: 0.20),
        ),
        labelStyle: TextStyle(
          color: selected
              ? AppColors.champagneGold
              : AppColors.refinedSlate.withValues(alpha: 0.75),
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

class PastProceduresStep extends StatelessWidget {
  final List<SkinProcedureHistoryEntry> procedures;
  final TextEditingController procedureNameController;
  final TextEditingController procedureOutcomeController;
  final DateTime? selectedProcedureDate;
  final VoidCallback onPickDate;
  final VoidCallback onAddProcedure;
  final ValueChanged<int> onRemoveProcedure;

  const PastProceduresStep({
    super.key,
    required this.procedures,
    required this.procedureNameController,
    required this.procedureOutcomeController,
    required this.selectedProcedureDate,
    required this.onPickDate,
    required this.onAddProcedure,
    required this.onRemoveProcedure,
  });

  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      eyebrow: 'Step 4 of 7',
      title: 'Any past procedures?',
      subtitle:
          'Add treatments like microneedling, Halo, IPL, peels, injectables, or extractions. Outcomes help the coach stay realistic.',
      icon: Icons.event_available_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: procedureNameController,
            decoration: _inputDecoration('Procedure name'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: procedureOutcomeController,
            decoration: _inputDecoration('Outcome or notes'),
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(
                    selectedProcedureDate == null
                        ? 'Add date'
                        : _dateLabel(selectedProcedureDate!),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: onAddProcedure,
                style: MyApp.primaryGoldButton.copyWith(
                  minimumSize: WidgetStateProperty.all(const Size(96, 48)),
                ),
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (procedures.isEmpty)
            const _SoftNotice(
              text:
                  'No procedures added. That is perfectly fine; your coach can still build a gentle routine.',
            )
          else
            for (var index = 0; index < procedures.length; index++)
              _ProcedureTile(
                entry: procedures[index],
                onDelete: () => onRemoveProcedure(index),
              ),
        ],
      ),
    );
  }
}

class EnvironmentStep extends StatelessWidget {
  final TextEditingController locationController;
  final TextEditingController climateController;
  final TextEditingController humidityController;

  const EnvironmentStep({
    super.key,
    required this.locationController,
    required this.climateController,
    required this.humidityController,
  });

  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      eyebrow: 'Step 5 of 7',
      title: 'Where does your skin live?',
      subtitle:
          'Climate, humidity, and seasonal stress can change hydration, redness, sunscreen needs, and recovery timing.',
      icon: Icons.wb_sunny_rounded,
      child: Column(
        children: [
          TextField(
            controller: locationController,
            decoration: _inputDecoration('Location, city, or region'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: climateController,
            decoration: _inputDecoration('Climate, e.g. dry, humid, cold'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: humidityController,
            decoration: _inputDecoration('Humidity or environment notes'),
          ),
        ],
      ),
    );
  }
}

class GoalsFinalStep extends StatelessWidget {
  final Set<String> selectedGoals;
  final ValueChanged<String> onToggleGoal;
  final TextEditingController notesController;

  const GoalsFinalStep({
    super.key,
    required this.selectedGoals,
    required this.onToggleGoal,
    required this.notesController,
  });

  static const goals = [
    'Calm redness',
    'Repair barrier',
    'Smooth texture',
    'Fade pigmentation',
    'Support procedure recovery',
    'Build simple routine',
    'Reduce breakouts',
    'Plan future procedures',
    'Improve hydration',
    'Age gracefully',
  ];

  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      eyebrow: 'Step 6 of 7',
      title: 'Set your glow goals.',
      subtitle:
          'Pick the outcomes you want the app to optimize for. Add anything personal in notes.',
      icon: Icons.stars_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: goals
                .map(
                  (goal) => LuxeChoiceChip(
                    label: goal,
                    selected: selectedGoals.contains(goal),
                    onTap: () => onToggleGoal(goal),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: notesController,
            decoration: _inputDecoration('Notes for your coach'),
            minLines: 3,
            maxLines: 5,
          ),
        ],
      ),
    );
  }
}

class _SelectionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SelectionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.champagneGold.withValues(alpha: 0.16)
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.champagneGold
                  : AppColors.borders.withValues(alpha: 0.86),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.circle_outlined,
                color: selected ? AppColors.goldHover : AppColors.mutedSage,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.refinedSlate,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.refinedSlate.withValues(alpha: 0.62),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IngredientChips extends StatelessWidget {
  final Set<String> ingredients;
  final String emptyText;
  final ValueChanged<String> onDeleted;

  const _IngredientChips({
    required this.ingredients,
    required this.emptyText,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    if (ingredients.isEmpty) {
      return Text(
        emptyText,
        style: TextStyle(
          color: AppColors.refinedSlate.withValues(alpha: 0.55),
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final ingredient in ingredients)
          InputChip(
            label: Text(ingredient),
            onDeleted: () => onDeleted(ingredient),
            backgroundColor: AppColors.champagneGold.withValues(alpha: 0.12),
            side: BorderSide(
              color: AppColors.champagneGold.withValues(alpha: 0.30),
            ),
          ),
      ],
    );
  }
}

class _TextEntryRow extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String buttonLabel;
  final VoidCallback onSubmit;

  const _TextEntryRow({
    required this.controller,
    required this.hintText,
    required this.buttonLabel,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: _inputDecoration(hintText),
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: onSubmit,
          style: MyApp.primaryGoldButton.copyWith(
            minimumSize: WidgetStateProperty.all(const Size(86, 48)),
          ),
          child: Text(buttonLabel),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.refinedSlate,
        fontSize: 14,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _SoftNotice extends StatelessWidget {
  final String text;

  const _SoftNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.champagneGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.refinedSlate.withValues(alpha: 0.72),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ProcedureTile extends StatelessWidget {
  final SkinProcedureHistoryEntry entry;
  final VoidCallback onDelete;

  const _ProcedureTile({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borders),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_fix_high_rounded, color: AppColors.goldHover),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.procedureName,
                  style: const TextStyle(
                    color: AppColors.refinedSlate,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (entry.date != null || entry.outcome.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (entry.date != null) _dateLabel(entry.date!),
                        if (entry.outcome.trim().isNotEmpty) entry.outcome,
                      ].join(' • '),
                      style: TextStyle(
                        color: AppColors.refinedSlate.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded),
            color: AppColors.refinedSlate.withValues(alpha: 0.54),
            tooltip: 'Remove procedure',
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: AppColors.cardBackground,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: AppColors.borders.withValues(alpha: 0.8)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: AppColors.borders.withValues(alpha: 0.8)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.champagneGold, width: 1.4),
    ),
  );
}

String skinTypeLabel(SkinType type) {
  return switch (type) {
    SkinType.dry => 'Dry',
    SkinType.oily => 'Oily',
    SkinType.combination => 'Combination',
    SkinType.normal => 'Normal',
    SkinType.sensitive => 'Sensitive',
  };
}

String sensitivityLevelLabel(SensitivityLevel level) {
  return switch (level) {
    SensitivityLevel.low => 'Low',
    SensitivityLevel.moderate => 'Moderate',
    SensitivityLevel.high => 'High',
    SensitivityLevel.veryHigh => 'Very High',
  };
}

String sensitivityLevelDescription(SensitivityLevel level) {
  return switch (level) {
    SensitivityLevel.low => 'Rarely stings, burns, or flushes.',
    SensitivityLevel.moderate => 'Occasional redness or dryness with actives.',
    SensitivityLevel.high => 'Reacts easily and needs slow changes.',
    SensitivityLevel.veryHigh =>
      'Very reactive, post-procedure, or barrier-fragile.',
  };
}

IconData _skinTypeIcon(SkinType type) {
  return switch (type) {
    SkinType.dry => Icons.water_drop_outlined,
    SkinType.oily => Icons.blur_on_rounded,
    SkinType.combination => Icons.bubble_chart_rounded,
    SkinType.normal => Icons.check_circle_outline_rounded,
    SkinType.sensitive => Icons.favorite_border_rounded,
  };
}

String _dateLabel(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
